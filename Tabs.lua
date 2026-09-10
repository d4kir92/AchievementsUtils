local _, AchievementsUtils = ...
local ROW_HEIGHT = 26
local HEADER_HEIGHT = 30
local FOOTER_HEIGHT = 18
local MAX_ROWS = 40
local INDENT_BASE = 2
local INDENT_STEP = 14
local SCROLL_WIDTH = 16
local SCROLL_MARGIN = 4
local SCROLL_THUMB_HEIGHT = 32
local SCROLL_MIN_THUMB = 0.05
local SCROLL_PAN = 0.1
local TAB_SPACING = 6
local ZONE_REFRESH_DELAY = 0.5
local INDEX_POLL_DELAY = 0.3
local SECTION_MAX = 30
local MIN_NEEDLE = 5
local SCAN_BUDGET = {
    ["scan"] = 4000,
    ["check"] = 80,
    ["time"] = 6
}

local TICK_DELAY = 0.02
local STRATA_ORDER = {"BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "FULLSCREEN", "FULLSCREEN_DIALOG"}
local PANEL_TEXTURE = 235397
local PANEL_LEFT = 0
local PANEL_RIGHT = 1
local PANEL_TOP = 0.5
local PANEL_BOTTOM = 1
local COLLAPSED_ICON = "Interface\\Buttons\\UI-PlusButton-Up"
local EXPANDED_ICON = "Interface\\Buttons\\UI-MinusButton-Up"
local PLAQUE_HEIGHT = 84
local PLAQUE_TEXTUREHEIGHT = 256
local PLAQUE_PARCHMENT = "Interface\\AchievementFrame\\UI-Achievement-Parchment-Horizontal"
local PLAQUE_PARCHMENT_GRAY = "Interface\\AchievementFrame\\UI-Achievement-Parchment-Horizontal-Desaturated"
local PLAQUE_BORDERS = "Interface\\AchievementFrame\\UI-Achievement-Borders"
local PLAQUE_SHIELDS = "Interface\\AchievementFrame\\UI-Achievement-Shields"
local PLAQUE_SHIELDS_NOPOINTS = "Interface\\AchievementFrame\\UI-Achievement-Shields-NoPoints"
local PLAQUE_ICONFRAME = "Interface\\AchievementFrame\\UI-Achievement-IconFrame"
local PLAQUE_REWARDBG = "Interface\\AchievementFrame\\UI-Achievement-Reward-Background"
local PLAQUE_TITLE_SAT = {0, 0.9765625, 0.66015625, 0.73828125}
local PLAQUE_TITLE_DESAT = {0, 1, 0.91796875, 0.99609375}
local PLAQUE_LABELWIDTH = 320
local PLAQUE_ICONX = 38
local PLAQUE_ICONY = -39
local PLAQUE_CONTENTLEFT = 80
local PLAQUE_CONTENTRIGHT = -80
local PLAQUE_BACKDROP = {
    ["edgeFile"] = "Interface\\Tooltips\\UI-Tooltip-Border",
    ["edgeSize"] = 16,
    ["insets"] = {
        ["left"] = 5,
        ["right"] = 5,
        ["top"] = 5,
        ["bottom"] = 5
    }
}

local styleChoices = {
    {
        ["value"] = "DEFAULT",
        ["label"] = "LID_ACHSTYLEDEFAULT"
    },
    {
        ["value"] = "COMPACT",
        ["label"] = "LID_ACHSTYLECOMPACT"
    },
}

local tabDefs = {
    {
        ["key"] = "TABSEARCH",
        ["label"] = "LID_TABSEARCHNAME"
    },
    {
        ["key"] = "TABSUGGESTIONS",
        ["label"] = "LID_TABSUGGESTIONSNAME"
    },
    {
        ["key"] = "TABWATCH",
        ["label"] = "LID_TABWATCHNAME"
    },
    {
        ["key"] = "TABRELATED",
        ["label"] = "LID_TABRELATEDNAME"
    },
}

local panel = nil
local blizzardHooked = false
local searchBox = nil
local statusText = nil
local scrollBar = nil
local scrollUpdating = false
local scrollMax = 0
local filteredItems = {}
local searchTexts = {}
local searchRestoring = false
local tabs = {}
local rows = {}
local items = {}
local visibleItems = {}
local activeTab = nil
local offset = 0
local currentLevel = 1
local suggestJob = nil
local suggestCache = nil
local zonePending = false
local indexPending = false
local indexStage = 0
local lastZone = nil
local lastSubZone = nil
local selectedAchievement = nil
local searchPending = false
local restored = false
function AchievementsUtils:GetAchStyleChoices()
    return styleChoices
end

local function IsPlaqueStyle()
    return AchievementsUtils:GetOption("ACHSTYLE") ~= "COMPACT"
end

local function ItemHeight(item)
    if item == nil then return ROW_HEIGHT end
    if item.id and IsPlaqueStyle() then return PLAQUE_HEIGHT end
    return ROW_HEIGHT
end

local function ItemIndent(item)
    if item == nil then return 0 end
    if item.id == nil or not IsPlaqueStyle() then return 0 end
    local level = item.level or 1
    if level <= 1 then return 0 end
    return (level - 1) * INDENT_STEP
end

local function GetListHeight()
    if panel == nil then return 0 end
    local height = panel:GetHeight()
    if height == nil or height <= 0 then return ROW_HEIGHT * 10 end
    return height - HEADER_HEIGHT - FOOTER_HEIGHT
end

local function CountFrom(startIndex, step)
    local available = GetListHeight()
    local used = 0
    local count = 0
    local index = startIndex
    while count < MAX_ROWS do
        local item = visibleItems[index]
        if item == nil then break end
        local height = ItemHeight(item)
        if used + height > available then break end
        used = used + height
        count = count + 1
        index = index + step
    end

    if count < 1 and #visibleItems > 0 then count = 1 end
    return count
end

local function CountVisibleRows()
    if panel == nil then return 0 end
    return CountFrom(offset + 1, 1)
end

local function AddItem(id, seen)
    if type(id) ~= "number" then return end
    if seen[id] then return end
    seen[id] = true
    tinsert(items, {
        ["id"] = id,
        ["level"] = currentLevel
    })
end

local function IsCollapsed(key)
    if key == nil then return false end
    local db = AchievementsUtils:GetDB()
    if type(db["TABCOLLAPSED"]) ~= "table" then return false end
    return db["TABCOLLAPSED"][key] == true
end

local function SetCollapsed(key, collapsed)
    if key == nil then return end
    local db = AchievementsUtils:GetDB()
    if type(db["TABCOLLAPSED"]) ~= "table" then db["TABCOLLAPSED"] = {} end
    if collapsed then
        db["TABCOLLAPSED"][key] = true
    else
        db["TABCOLLAPSED"][key] = nil
    end
end

local function UsesFilter()
    return activeTab == "TABSUGGESTIONS" or activeTab == "TABWATCH"
end

local function GetFilterNeedle()
    if not UsesFilter() then return "" end
    if searchBox == nil then return "" end

    return string.lower(strtrim(searchBox:GetText() or ""))
end

local function ApplyFilter()
    wipe(filteredItems)
    local needle = GetFilterNeedle()
    if needle == "" then
        for _, item in ipairs(items) do
            tinsert(filteredItems, item)
        end

        return
    end

    local pending = {}
    for _, item in ipairs(items) do
        if item.header then
            while #pending > 0 and (pending[#pending].level or 1) >= (item.level or 1) do
                tremove(pending)
            end

            tinsert(pending, item)
        elseif item.id then
            local entry = AchievementsUtils:GetEntry(item.id)
            if entry and AchievementsUtils:EntryMatches(entry, needle) then
                for _, header in ipairs(pending) do
                    tinsert(filteredItems, header)
                end

                wipe(pending)
                tinsert(filteredItems, item)
            end
        else
            tinsert(filteredItems, item)
        end
    end

    if #filteredItems > 0 then return end
    tinsert(filteredItems, {
        ["info"] = AchievementsUtils:Trans("LID_NORESULTS"),
        ["level"] = 1
    })
end

local function ApplyCollapse()
    ApplyFilter()
    wipe(visibleItems)
    local hiddenLevel = nil
    for _, item in ipairs(filteredItems) do
        if item.header then
            local level = item.level or 1
            if hiddenLevel == nil or level <= hiddenLevel then
                hiddenLevel = nil
                tinsert(visibleItems, item)
                if IsCollapsed(item.key) then hiddenLevel = level end
            end
        elseif hiddenLevel == nil then
            tinsert(visibleItems, item)
        end
    end
end

local function AddHeader(text, key, level)
    if text == nil or text == "" then return end
    currentLevel = level or 1
    tinsert(items, {
        ["header"] = text,
        ["key"] = key,
        ["level"] = currentLevel
    })
end

local function AddGroup(list, seen, keyPrefix, level)
    local singles = {}
    local metas = {}
    for _, entry in ipairs(list) do
        if not seen[entry.id] then
            if entry.isMeta then
                tinsert(metas, entry)
            else
                tinsert(singles, entry)
            end
        end
    end

    if #singles > 0 and #metas > 0 then
        AddHeader(AchievementsUtils:Trans("LID_SINGLEACHIEVEMENTS"), keyPrefix .. ":SINGLE", level)
        for _, entry in ipairs(singles) do
            AddItem(entry.id, seen)
        end

        AddHeader(AchievementsUtils:Trans("LID_METAACHIEVEMENTS"), keyPrefix .. ":META", level)
        for _, entry in ipairs(metas) do
            AddItem(entry.id, seen)
        end
        return
    end

    for _, entry in ipairs(list) do
        AddItem(entry.id, seen)
    end
end

local function AddInfo(text)
    if text == nil or text == "" then return end
    tinsert(items, {
        ["info"] = text,
        ["level"] = currentLevel
    })
end

local function BuildSearch()
    local text = ""
    if searchBox then text = searchBox:GetText() end
    if strtrim(text or "") == "" then
        AddInfo(AchievementsUtils:Trans("LID_SEARCHHINT"))
        return
    end

    local seen = {}
    local results = AchievementsUtils:SearchAchievements(text, 300)
    for _, entry in ipairs(results) do
        AddItem(entry.id, seen)
    end

    if #items <= 0 then AddInfo(AchievementsUtils:Trans("LID_NORESULTS")) end
end

local function IsHolidayRunning(info, now)
    local sequence = info.sequenceType
    if sequence == nil then return true end
    if sequence == "INFO" then return false end
    if now.hour == nil then return true end
    if sequence == "START" and type(info.startTime) == "table" and info.startTime.hour and now.hour < info.startTime.hour then return false end
    if sequence == "END" and type(info.endTime) == "table" and info.endTime.hour and now.hour >= info.endTime.hour then return false end
    return true
end

local function GetHolidayNames()
    local names = {}
    if C_Calendar == nil then return names end
    if C_Calendar.GetNumDayEvents == nil or C_Calendar.GetDayEvent == nil then return names end
    if C_DateAndTime == nil or C_DateAndTime.GetCurrentCalendarTime == nil then return names end
    local now = C_DateAndTime.GetCurrentCalendarTime()
    if type(now) ~= "table" or now.monthDay == nil then return names end
    local num = C_Calendar.GetNumDayEvents(0, now.monthDay) or 0
    for i = 1, num do
        local info = C_Calendar.GetDayEvent(0, now.monthDay, i)
        if type(info) == "table" and info.title then
            local isHoliday = info.calendarType == "HOLIDAY"
            if Enum and Enum.CalendarEventType and info.eventType == Enum.CalendarEventType.Holiday then isHoliday = true end
            if isHoliday and IsHolidayRunning(info, now) then tinsert(names, info.title) end
        end
    end
    return names
end

local function GetNeedles(text)
    local needles = {}
    if type(text) ~= "string" or text == "" then return needles end
    local full = string.lower(text)
    tinsert(needles, full)
    local longest = nil
    for word in string.gmatch(full, "[^%s]+") do
        if string.len(word) >= MIN_NEEDLE and (longest == nil or string.len(word) > string.len(longest)) then longest = word end
    end

    if longest and longest ~= full then tinsert(needles, longest) end
    return needles
end

local function MatchesText(entry, needles)
    for _, needle in ipairs(needles) do
        if AchievementsUtils:EntryMatches(entry, needle) then return true end
    end
    return false
end

local function AddSection(headerText, headerKey, list, seen)
    if headerText == nil or headerText == "" then return end
    AddHeader(headerText, headerKey, 1)
    local open = {}
    for _, entry in ipairs(list) do
        if not seen[entry.id] then tinsert(open, entry) end
    end

    if #open <= 0 then
        AddInfo(AchievementsUtils:Trans("LID_NOSUGGESTIONS"))
        return
    end

    AddHeader(AchievementsUtils:Trans("LID_INPROGRESS"), headerKey .. ":INPROGRESS", 2)
    AddGroup(open, seen, headerKey, 3)
end

local function AddZoneSection(sections, text, key, zone, optional)
    if zone == nil or zone == "" then return end
    local needles = GetNeedles(zone)
    tinsert(sections, {
        ["text"] = text,
        ["key"] = key,
        ["optional"] = optional,
        ["found"] = {},
        ["match"] = function(entry) return MatchesText(entry, needles) end
    })
end

local function SuggestSignature(sections)
    local parts = {}
    for i = 1, #sections do
        parts[i] = sections[i].key .. "=" .. sections[i].text
    end

    tinsert(parts, tostring(AchievementsUtils:GetIndexCount()))
    tinsert(parts, tostring(AchievementsUtils:IsOpenCriteriaReady()))
    return table.concat(parts, "\30")
end

local function BuildSuggestions()
    suggestJob = nil
    if not AchievementsUtils:IsIndexReady() then
        AddInfo(AchievementsUtils:GetIndexStatus())
        return
    end

    local sections = {}
    for _, title in ipairs(GetHolidayNames()) do
        local categoryID = AchievementsUtils:FindCategoryByName(title)
        if categoryID then
            tinsert(sections, {
                ["text"] = AchievementsUtils:Trans("LID_HOLIDAY", nil, title),
                ["key"] = "HOLIDAY:" .. title,
                ["optional"] = true,
                ["found"] = {},
                ["match"] = function(entry) return entry.category == categoryID end
            })
        end
    end

    local zone = GetZoneText()
    local sub = GetSubZoneText()
    lastZone = zone
    lastSubZone = sub
    AddZoneSection(sections, AchievementsUtils:Trans("LID_CURRENTZONE", nil, zone or ""), "ZONE", zone, false)
    if sub ~= zone then AddZoneSection(sections, AchievementsUtils:Trans("LID_CURRENTZONE", nil, sub or ""), "SUBZONE", sub, true) end
    local expansion = AchievementsUtils:GetExpansionName()
    if expansion then
        local needle = string.lower(expansion)
        tinsert(sections, {
            ["text"] = AchievementsUtils:Trans("LID_EXPANSION", nil, expansion),
            ["key"] = "EXPANSION",
            ["found"] = {},
            ["match"] = function(entry) return string.find(entry.lcategory, needle, 1, true) ~= nil end
        })
    end

    if #sections <= 0 then
        AddInfo(AchievementsUtils:Trans("LID_NOSUGGESTIONS"))
        return
    end

    local signature = SuggestSignature(sections)
    if suggestCache and suggestCache.signature == signature then
        for i = 1, #suggestCache.items do
            items[i] = suggestCache.items[i]
        end

        return
    end

    suggestJob = {
        ["sections"] = sections,
        ["seen"] = {},
        ["signature"] = signature,
        ["cursor"] = 0,
        ["count"] = AchievementsUtils:GetIndexCount()
    }
end

local function BuildWatch()
    local seen = {}
    local list = AchievementsUtils:GetWatchList()
    for _, id in ipairs(list) do
        AddItem(id, seen)
    end

    if #items <= 0 then AddInfo(AchievementsUtils:Trans("LID_WATCHEMPTY")) end
end

local function BuildRelated()
    local seen = {}
    local id = selectedAchievement
    if id == nil then
        AddInfo(AchievementsUtils:Trans("LID_NOSELECTION"))
        return
    end

    local ach = AchievementsUtils:GetAchievement(id)
    if ach == nil then
        AddInfo(AchievementsUtils:Trans("LID_NOSELECTION"))
        return
    end

    AddHeader(ach.name)
    local before, after = AchievementsUtils:GetSeries(id)
    if #before > 0 or #after > 0 then
        AddHeader(AchievementsUtils:Trans("LID_PARTOFSERIES"), "SERIES")
        for _, value in ipairs(before) do
            AddItem(value, seen)
        end

        AddItem(id, seen)
        for _, value in ipairs(after) do
            AddItem(value, seen)
        end
    end

    local requiredBy = AchievementsUtils:GetRequiredBy(id)
    if requiredBy and #requiredBy > 0 then
        AddHeader(AchievementsUtils:Trans("LID_REQUIREDBY"), "REQUIREDBY")
        for _, value in ipairs(requiredBy) do
            AddItem(value, seen)
        end
    end

    local metaType = AchievementsUtils:GetMetaCriteriaType()
    local num = GetAchievementNumCriteria(id) or 0
    local metaAdded = false
    for i = 1, num do
        local _, criteriaType, _, _, _, _, _, assetID = GetAchievementCriteriaInfo(id, i)
        if criteriaType == metaType and type(assetID) == "number" and assetID > 0 then
            if not metaAdded then
                AddHeader(AchievementsUtils:Trans("LID_CONSISTSOF"), "CONSISTSOF")
                metaAdded = true
            end

            AddItem(assetID, seen)
        end
    end

    if #items <= 1 then AddInfo(AchievementsUtils:Trans("LID_NORELATED")) end
end

local function GetSuggestPercent()
    if suggestJob == nil then return 100 end
    local total = suggestJob.count or 0
    if total <= 0 then return 99 end
    local value = math.floor(suggestJob.cursor / total * 100)
    if value < 0 then value = 0 end
    if value > 99 then value = 99 end
    return value
end

local function UpdateStatus()
    if statusText == nil then return end
    local count = 0
    for _, item in ipairs(filteredItems) do
        if item.id then count = count + 1 end
    end

    local text = AchievementsUtils:Trans("LID_RESULTS", nil, count)
    if not AchievementsUtils:IsIndexReady() or (activeTab == "TABRELATED" and not AchievementsUtils:IsCriteriaIndexReady()) then text = text .. "  |cff888888" .. AchievementsUtils:GetIndexStatus() .. "|r" end
    if suggestJob then text = text .. "  |cffffd200" .. AchievementsUtils:Trans("LID_SEARCHPROGRESS", nil, GetSuggestPercent() .. "%") .. "|r" end
    statusText:SetText(text)
end

local function PickFont(name, fallback)
    if _G[name] then return name end
    return fallback
end

local function EnsurePlaque(row)
    if row.plaqueParts then return end
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetPoint("TOPLEFT", row, "TOPLEFT", 3, -3)
    row.bg:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -3, 3)
    row.titleBar = row:CreateTexture(nil, "BORDER")
    row.titleBar:SetTexture(PLAQUE_BORDERS)
    row.titleBar:SetHeight(24)
    row.titleBar:SetPoint("TOPLEFT", row, "TOPLEFT", 5, -5)
    row.titleBar:SetPoint("TOPRIGHT", row, "TOPRIGHT", -5, -5)
    row.glow = row:CreateTexture(nil, "BORDER")
    row.glow:SetTexture(PLAQUE_BORDERS)
    row.glow:SetTexCoord(0, 1, 0.00390625, 0.25390625)
    row.glow:SetPoint("TOPLEFT", row.titleBar, "BOTTOMLEFT", 0, 4)
    row.glow:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -5, 4)
    row.rewardBg = row:CreateTexture(nil, "BORDER")
    row.rewardBg:SetTexture(PLAQUE_REWARDBG)
    row.rewardBg:SetTexCoord(0, 0.69, 0, 0.75)
    row.rewardBg:SetHeight(24)
    row.rewardBg:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 5, 4)
    row.rewardBg:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -5, 4)
    row.iconTexture = row:CreateTexture(nil, "ARTWORK")
    row.iconTexture:SetDrawLayer("ARTWORK", 1)
    row.iconTexture:SetSize(50, 50)
    row.iconTexture:SetPoint("CENTER", row, "TOPLEFT", PLAQUE_ICONX, PLAQUE_ICONY + 3)
    row.iconBorder = row:CreateTexture(nil, "ARTWORK")
    row.iconBorder:SetDrawLayer("ARTWORK", 2)
    row.iconBorder:SetTexture(PLAQUE_ICONFRAME)
    row.iconBorder:SetTexCoord(0, 0.5625, 0, 0.5625)
    row.iconBorder:SetSize(72, 72)
    row.iconBorder:SetPoint("CENTER", row, "TOPLEFT", PLAQUE_ICONX - 1, PLAQUE_ICONY + 2)
    row.shieldIcon = row:CreateTexture(nil, "ARTWORK")
    row.shieldIcon:SetDrawLayer("ARTWORK", 2)
    row.shieldIcon:SetSize(66, 64)
    row.shieldIcon:SetPoint("TOPRIGHT", row, "TOPRIGHT", -6, -6)
    row.label = row:CreateFontString(nil, "OVERLAY", PickFont("GameFontHighlightMedium", "GameFontHighlight"))
    row.label:SetHeight(20)
    row.label:SetWidth(PLAQUE_LABELWIDTH)
    row.label:SetPoint("TOP", row.titleBar, "TOP", 0, 0)
    row.label:SetJustifyH("CENTER")
    if row.label.SetWordWrap then row.label:SetWordWrap(false) end
    row.mark = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.mark:SetPoint("LEFT", row.titleBar, "LEFT", 8, 0)
    row.mark:SetJustifyH("LEFT")
    row.desc = row:CreateFontString(nil, "OVERLAY", PickFont("AchievementDescriptionFont", "GameFontHighlightSmall"))
    row.desc:SetPoint("TOPLEFT", row, "TOPLEFT", PLAQUE_CONTENTLEFT, -30)
    row.desc:SetPoint("TOPRIGHT", row, "TOPRIGHT", PLAQUE_CONTENTRIGHT, -30)
    row.desc:SetHeight(34)
    row.desc:SetJustifyH("CENTER")
    row.desc:SetJustifyV("TOP")
    if row.desc.SetMaxLines then row.desc:SetMaxLines(3) end
    row.points = row:CreateFontString(nil, "OVERLAY", PickFont("AchievementPointsFont", "GameFontNormalLarge"))
    row.points:SetSize(42, 16)
    row.points:SetPoint("TOPRIGHT", row, "TOPRIGHT", -19, -26)
    row.date = row:CreateFontString(nil, "OVERLAY", PickFont("AchievementDateFont", "GameFontNormalSmall"))
    row.date:SetSize(100, 14)
    row.date:SetPoint("TOP", row, "TOPRIGHT", -40, -58)
    row.date:SetJustifyH("CENTER")
    row.rewardText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.rewardText:SetHeight(20)
    row.rewardText:SetPoint("TOPLEFT", row.rewardBg, "TOPLEFT", 10, 1)
    row.rewardText:SetPoint("TOPRIGHT", row.rewardBg, "TOPRIGHT", -10, 1)
    row.rewardText:SetJustifyH("CENTER")
    if row.rewardText.SetWordWrap then row.rewardText:SetWordWrap(false) end
    row.plaqueParts = {row.bg, row.titleBar, row.glow, row.rewardBg, row.iconTexture, row.iconBorder, row.shieldIcon, row.label, row.mark, row.desc, row.points, row.date, row.rewardText}
end

local function HidePlaque(row)
    if row.plaqueParts == nil then return end
    for _, part in ipairs(row.plaqueParts) do
        part:Hide()
    end

    if row.SetBackdrop then row:SetBackdrop(nil) end
end

local function SetPlaqueBorder(row, completed)
    if row.SetBackdrop == nil then return end
    row:SetBackdrop(PLAQUE_BACKDROP)
    if not completed then
        row:SetBackdropBorderColor(0.5, 0.5, 0.5)
        return
    end

    if ACHIEVEMENT_RED_BORDER_COLOR and ACHIEVEMENT_RED_BORDER_COLOR.GetRGB then
        row:SetBackdropBorderColor(ACHIEVEMENT_RED_BORDER_COLOR:GetRGB())
        return
    end

    row:SetBackdropBorderColor(0.7, 0.15, 0.05)
end

local function ShowPlaque(row, ach)
    EnsurePlaque(row)
    for _, part in ipairs(row.plaqueParts) do
        part:Show()
    end

    local completed = ach.completed
    row.bg:SetTexCoord(0, 1, 1 - (PLAQUE_HEIGHT / PLAQUE_TEXTUREHEIGHT), 1)
    local title = PLAQUE_TITLE_DESAT
    if completed then
        row.bg:SetTexture(PLAQUE_PARCHMENT)
        title = PLAQUE_TITLE_SAT
        row.glow:SetVertexColor(1, 1, 1)
        row.label:SetTextColor(1, 1, 1)
        row.desc:SetTextColor(0, 0, 0, 1)
        row.desc:SetShadowOffset(0, 0)
        row.iconBorder:SetVertexColor(1, 1, 1)
        row.iconTexture:SetVertexColor(1, 1, 1)
        row.points:SetTextColor(1, 1, 1)
    else
        row.bg:SetTexture(PLAQUE_PARCHMENT_GRAY)
        row.glow:SetVertexColor(0.22, 0.17, 0.13)
        row.label:SetTextColor(0.65, 0.65, 0.65)
        row.desc:SetTextColor(1, 1, 1, 1)
        row.desc:SetShadowOffset(1, -1)
        row.iconBorder:SetVertexColor(0.75, 0.75, 0.75)
        row.iconTexture:SetVertexColor(0.55, 0.55, 0.55)
        row.points:SetTextColor(0.65, 0.65, 0.65)
    end

    row.titleBar:SetTexCoord(title[1], title[2], title[3], title[4])
    row.titleBar:SetVertexColor(1, 1, 1, 0.8)
    row.label:SetText(ach.name)
    row.desc:SetText(ach.description)
    row.iconTexture:SetTexture(ach.icon)
    if ach.points > 0 then
        row.shieldIcon:SetTexture(PLAQUE_SHIELDS)
        row.points:SetText(ach.points)
    else
        row.shieldIcon:SetTexture(PLAQUE_SHIELDS_NOPOINTS)
        row.points:SetText("")
    end

    if completed then
        row.shieldIcon:SetTexCoord(0, 0.5, 0, 0.5)
    else
        row.shieldIcon:SetTexCoord(0.5, 1, 0, 0.5)
    end

    local mark = ""
    if AchievementsUtils:IsWatched(ach.id) then mark = "|cff55d2ff*|r " end
    if AchievementsUtils:IsTracked(ach.id) then mark = mark .. "|cff40ff40>|r" end
    row.mark:SetText(mark)
    if completed and ach.day and ach.month and ach.year and SHORTDATE then
        row.date:SetText(format(SHORTDATE, ach.day, ach.month, ach.year))
        row.date:SetTextColor(1, 0.82, 0)
    else
        local done, total = AchievementsUtils:GetCriteriaProgress(ach.id)
        if not completed and total > 1 then
            row.date:SetText(format("%d/%d", done, total))
            row.date:SetTextColor(0.65, 0.65, 0.65)
        else
            row.date:Hide()
        end
    end

    if ach.reward ~= "" then
        row.rewardText:SetText(ach.reward)
        if completed then
            row.rewardBg:SetVertexColor(1, 1, 1)
            row.rewardText:SetTextColor(1, 0.82, 0)
        else
            row.rewardBg:SetVertexColor(0.35, 0.35, 0.35)
            row.rewardText:SetTextColor(0.8, 0.8, 0.8)
        end
    else
        row.rewardBg:Hide()
        row.rewardText:Hide()
    end

    SetPlaqueBorder(row, completed)
end

local function RowRightInset()
    if scrollBar == nil or not scrollBar:IsShown() then return -4 end
    local width = scrollBar:GetWidth() or 0
    if width <= 0 then width = SCROLL_WIDTH end
    return -4 - width - SCROLL_MARGIN
end

local function AnchorRow(row, indent, top)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", panel, "TOPLEFT", 4 + indent, -top)
    row:SetPoint("TOPRIGHT", panel, "TOPRIGHT", RowRightInset(), -top)
end

local function UpdateScroll(maxOffset, visible)
    if scrollBar == nil then return end
    scrollMax = maxOffset
    if maxOffset <= 0 then
        scrollBar:Hide()
        return
    end

    scrollUpdating = true
    if scrollBar.auSlider then
        scrollBar:SetMinMaxValues(0, maxOffset)
        scrollBar:SetValue(offset)
    else
        local total = #visibleItems
        local share = 1
        if total > 0 then share = visible / total end
        if share < SCROLL_MIN_THUMB then share = SCROLL_MIN_THUMB end
        if share > 0.99 then share = 0.99 end
        scrollBar:SetVisibleExtentPercentage(share)
        scrollBar:SetScrollPercentage(offset / maxOffset, true)
    end

    scrollUpdating = false
    scrollBar:Show()
end

local function UpdateRows()
    if panel == nil then return end
    local maxOffset = #visibleItems - CountFrom(#visibleItems, -1)
    if maxOffset < 0 then maxOffset = 0 end
    if offset > maxOffset then offset = maxOffset end
    if offset < 0 then offset = 0 end
    local visible = CountVisibleRows()
    UpdateScroll(maxOffset, visible)
    for i = 1, MAX_ROWS do
        local row = rows[i]
        if row and i > visible then row:Hide() end
    end

    local top = HEADER_HEIGHT
    for i = 1, visible do
        local row = rows[i]
        if row == nil then break end
        local item = visibleItems[i + offset]
        if item == nil then
            row:Hide()
        else
            local height = ItemHeight(item)
            row:SetHeight(height)
            AnchorRow(row, ItemIndent(item), top)
            top = top + height
            row:Show()
            row.id = nil
            row.headerKey = nil
            row.icon:Hide()
            row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            row.icon:SetSize(20, 20)
            local level = item.level or 1
            row.icon:ClearAllPoints()
            row.icon:SetPoint("LEFT", row, "LEFT", INDENT_BASE + (level - 1) * INDENT_STEP, 0)
            row.right:SetText("")
            row.name:SetFontObject("GameFontNormal")
            row.name:Show()
            HidePlaque(row)
            if item.header then
                if level <= 1 then row.name:SetFontObject("GameFontNormalLarge") end
                row.name:SetText("|cffffd200" .. item.header .. "|r")
                if item.key then
                    row.headerKey = item.key
                    row:EnableMouse(true)
                    row.icon:SetTexCoord(0, 1, 0, 1)
                    row.icon:SetSize(16, 16)
                    if IsCollapsed(item.key) then
                        row.icon:SetTexture(COLLAPSED_ICON)
                    else
                        row.icon:SetTexture(EXPANDED_ICON)
                    end

                    row.icon:Show()
                else
                    row:EnableMouse(false)
                end
            elseif item.info then
                row.name:SetText("|cff999999" .. item.info .. "|r")
                row:EnableMouse(false)
            else
                local ach = AchievementsUtils:GetAchievement(item.id)
                if ach == nil then
                    row.name:SetText("|cff999999" .. tostring(item.id) .. "|r")
                    row:EnableMouse(false)
                elseif IsPlaqueStyle() then
                    row.id = item.id
                    row:EnableMouse(true)
                    row.name:Hide()
                    ShowPlaque(row, ach)
                else
                    row.id = item.id
                    row:EnableMouse(true)
                    row.icon:SetTexture(ach.icon)
                    row.icon:Show()
                    local prefix = ""
                    if AchievementsUtils:IsWatched(ach.id) then prefix = "|cff55d2ff*|r " end
                    if AchievementsUtils:IsTracked(ach.id) then prefix = prefix .. "|cff40ff40>|r " end
                    row.name:SetText(prefix .. AchievementsUtils:ColorByStatus(ach.name, ach.completed))
                    if ach.completed then
                        row.right:SetText("|cff40ff40" .. tostring(ach.points) .. "|r")
                    else
                        local done, total = AchievementsUtils:GetCriteriaProgress(ach.id)
                        if total > 1 then
                            row.right:SetText(format("|cffffd200%d/%d|r", done, total))
                        else
                            row.right:SetText("|cff999999" .. tostring(ach.points) .. "|r")
                        end
                    end
                end
            end
        end
    end

    UpdateStatus()
end

local function StepSuggestions(job)
    if job == nil or job ~= suggestJob then return end
    local cursor, done = AchievementsUtils:ScanSections(job.cursor, SCAN_BUDGET, job.sections, SECTION_MAX)
    job.cursor = cursor
    if not done then
        local percent = GetSuggestPercent()
        if percent ~= job.percent then
            job.percent = percent
            UpdateStatus()
        end

        C_Timer.After(TICK_DELAY, function() StepSuggestions(job) end)
        return
    end

    suggestJob = nil
    for i = 1, #job.sections do
        local section = job.sections[i]
        AchievementsUtils:SortOpenResults(section.found)
        if #section.found > 0 or not section.optional then AddSection(section.text, section.key, section.found, job.seen) end
    end

    if #items <= 0 then AddInfo(AchievementsUtils:Trans("LID_NOSUGGESTIONS")) end
    local cached = {}
    for i = 1, #items do
        cached[i] = items[i]
    end

    suggestCache = {
        ["signature"] = job.signature,
        ["items"] = cached
    }

    ApplyCollapse()
    UpdateRows()
end

local function UpdateIndexInfo()
    local item = items[1]
    if item == nil or item.info == nil then return end
    item.info = AchievementsUtils:GetIndexStatus()
    UpdateRows()
end

local function PollIndex()
    if not indexPending then return end
    if panel == nil or not panel:IsShown() or activeTab == nil then
        indexPending = false
        return
    end

    if not AchievementsUtils:IsIndexBuilding() then
        indexPending = false
        AchievementsUtils:RefreshExtraTab()
        return
    end

    if indexStage < 1 and AchievementsUtils:IsIndexReady() then
        indexStage = 1
        AchievementsUtils:RefreshExtraTab()
    elseif indexStage < 2 and AchievementsUtils:IsOpenCriteriaReady() then
        indexStage = 2
        AchievementsUtils:RefreshExtraTab()
    else
        UpdateIndexInfo()
    end

    C_Timer.After(INDEX_POLL_DELAY, PollIndex)
end

local function Refresh()
    if panel == nil then return end
    suggestJob = nil
    wipe(items)
    currentLevel = 1
    if activeTab == "TABSEARCH" then
        BuildSearch()
    elseif activeTab == "TABSUGGESTIONS" then
        BuildSuggestions()
    elseif activeTab == "TABWATCH" then
        BuildWatch()
    elseif activeTab == "TABRELATED" then
        BuildRelated()
    end

    ApplyCollapse()
    UpdateRows()
    if suggestJob then StepSuggestions(suggestJob) end
    if AchievementsUtils:IsIndexBuilding() and not indexPending then
        indexPending = true
        indexStage = 0
        C_Timer.After(INDEX_POLL_DELAY, PollIndex)
    end
end

local function RowOnClick(sel, button)
    if sel.headerKey then
        SetCollapsed(sel.headerKey, not IsCollapsed(sel.headerKey))
        ApplyCollapse()
        UpdateRows()
        return
    end

    if sel.id == nil then return end
    if button == "RightButton" then
        if AchievementsUtils:ShowAchievementMenu(sel.id) then return end
        AchievementsUtils:ToggleWatch(sel.id)
        Refresh()
        return
    end

    if AchievementsUtils:IsEnabled("WOWHEAD") and IsAltKeyDown() then
        AchievementsUtils:ShowWowheadLink(sel.id)
        return
    end

    if IsControlKeyDown() and AchievementsUtils:CanTrack() then
        AchievementsUtils:ToggleTracked(sel.id)
        UpdateRows()
        return
    end

    AchievementsUtils:OpenToAchievement(sel.id)
end

local function RowOnEnter(sel)
    if sel.id == nil then return end
    local ach = AchievementsUtils:GetAchievement(sel.id)
    if ach == nil then return end
    GameTooltip:SetOwner(sel, "ANCHOR_RIGHT")
    GameTooltip:SetText(ach.name, 1, 1, 1)
    if ach.description ~= "" then GameTooltip:AddLine(ach.description, 1, 0.82, 0, true) end
    if ach.reward ~= "" then GameTooltip:AddLine(ach.reward, 0.1, 1, 0.1, true) end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(AchievementsUtils:Trans("LID_CLICKOPEN"), 0.6, 0.6, 0.6)
    if AchievementsUtils:CanTrack() then GameTooltip:AddLine(AchievementsUtils:Trans("LID_CTRLCLICKTRACK"), 0.6, 0.6, 0.6) end
    if AchievementsUtils:IsEnabled("CONTEXTMENU") then
        GameTooltip:AddLine(AchievementsUtils:Trans("LID_RIGHTCLICKMENU"), 0.6, 0.6, 0.6)
    else
        GameTooltip:AddLine(AchievementsUtils:Trans("LID_RIGHTCLICKWATCH"), 0.6, 0.6, 0.6)
    end

    if AchievementsUtils:IsEnabled("WOWHEAD") then GameTooltip:AddLine(AchievementsUtils:Trans("LID_ALTCLICKWOWHEAD"), 0.6, 0.6, 0.6) end
    GameTooltip:Show()
end

local function RowOnLeave()
    GameTooltip:Hide()
end

local function CreateRow(parentFrame, i)
    local template = nil
    if AchievementsUtils:CheckTemplates("BackdropTemplate") then template = "BackdropTemplate" end
    local row = CreateFrame("Button", "AchievementsUtilsRow" .. i, parentFrame, template)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", parentFrame, "TOPLEFT", 4, -HEADER_HEIGHT - (i - 1) * ROW_HEIGHT)
    row:SetPoint("TOPRIGHT", parentFrame, "TOPRIGHT", -4, -HEADER_HEIGHT - (i - 1) * ROW_HEIGHT)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
    local highlight = row:GetHighlightTexture()
    if highlight then highlight:SetVertexColor(1, 1, 1, 0.12) end
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(20, 20)
    row.icon:SetPoint("LEFT", row, "LEFT", 2, 0)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row.right = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.right:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.name:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
    row.name:SetJustifyH("LEFT")
    if row.name.SetWordWrap then row.name:SetWordWrap(false) end
    row:SetScript("OnClick", RowOnClick)
    row:SetScript("OnEnter", RowOnEnter)
    row:SetScript("OnLeave", RowOnLeave)
    return row
end

local function ScrollToPercent(percent)
    if scrollUpdating then return end
    if scrollMax <= 0 then return end
    local target = math.floor(percent * scrollMax + 0.5)
    if target < 0 then target = 0 end
    if target > scrollMax then target = scrollMax end
    if target == offset then return end
    offset = target
    UpdateRows()
end

local function CreateModernScrollBar()
    if not AchievementsUtils:CheckTemplates("MinimalScrollBar") then return nil end
    if type(ScrollBarMixin) ~= "table" then return nil end
    local bar = CreateFrame("EventFrame", "AchievementsUtilsScrollBar", panel, "MinimalScrollBar")
    bar:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -4, -HEADER_HEIGHT)
    bar:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -4, FOOTER_HEIGHT)
    bar:SetFrameLevel(panel:GetFrameLevel() + 10)
    bar:Init(1, SCROLL_PAN)
    local event = "OnScroll"
    if ScrollBarMixin and ScrollBarMixin.Event and ScrollBarMixin.Event.OnScroll then event = ScrollBarMixin.Event.OnScroll end
    bar:RegisterCallback(event, function(_, percent) ScrollToPercent(percent) end, panel)
    return bar
end

local function CreateLegacyScrollBar()
    local bar = CreateFrame("Slider", "AchievementsUtilsScrollBar", panel)
    bar.auSlider = true
    bar:SetWidth(SCROLL_WIDTH)
    bar:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -4, -HEADER_HEIGHT)
    bar:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -4, FOOTER_HEIGHT)
    bar:SetOrientation("VERTICAL")
    bar:SetValueStep(1)
    if bar.SetObeyStepOnDrag then bar:SetObeyStepOnDrag(true) end
    bar:SetMinMaxValues(0, 0)
    bar:SetValue(0)
    bar:SetFrameLevel(panel:GetFrameLevel() + 10)
    bar.track = bar:CreateTexture(nil, "BACKGROUND")
    bar.track:SetTexture("Interface\\Buttons\\WHITE8X8")
    bar.track:SetVertexColor(0, 0, 0, 0.5)
    bar.track:SetAllPoints(bar)
    bar.thumb = bar:CreateTexture(nil, "ARTWORK")
    bar.thumb:SetTexture("Interface\\Buttons\\WHITE8X8")
    bar.thumb:SetVertexColor(0.6, 0.6, 0.6, 0.9)
    bar.thumb:SetSize(SCROLL_WIDTH - 4, SCROLL_THUMB_HEIGHT)
    bar:SetThumbTexture(bar.thumb)
    bar:SetScript("OnValueChanged", function(sel, value)
        if scrollUpdating then return end
        local target = math.floor(value + 0.5)
        if target == offset then return end
        offset = target
        UpdateRows()
    end)

    return bar
end

local function CreateScrollBar()
    return CreateModernScrollBar() or CreateLegacyScrollBar()
end

local function RaisePanel()
    if panel == nil then return end
    if type(AchievementFrame) ~= "table" then return end
    local strata = AchievementFrame:GetFrameStrata()
    local target = "HIGH"
    for i, value in ipairs(STRATA_ORDER) do
        if value == strata then
            target = STRATA_ORDER[i + 1] or value
            break
        end
    end

    panel:SetFrameStrata(target)
    panel:SetFrameLevel(20)
end

local function SetPanelBackground(texture)
    texture:SetTexture(PANEL_TEXTURE)
    if texture:GetTexture() then
        texture:SetTexCoord(PANEL_LEFT, PANEL_RIGHT, PANEL_TOP, PANEL_BOTTOM)
        return
    end

    if texture.SetColorTexture then
        texture:SetColorTexture(0.04, 0.04, 0.06, 1)
    else
        texture:SetTexture(0.04, 0.04, 0.06, 1)
    end
end

local function CreatePanel()
    if panel ~= nil then return end
    if type(AchievementFrame) ~= "table" then return end
    panel = CreateFrame("Frame", "AchievementsUtilsPanel", AchievementFrame)
    local top = _G["AchievementFrameCategories"]
    if top then
        panel:SetPoint("TOPLEFT", top, "TOPLEFT", 0, 0)
    else
        panel:SetPoint("TOPLEFT", AchievementFrame, "TOPLEFT", 20, -70)
    end

    panel:SetPoint("BOTTOMRIGHT", AchievementFrame, "BOTTOMRIGHT", -20, 20)
    RaisePanel()
    panel:EnableMouse(true)
    panel:EnableMouseWheel(true)
    panel:Hide()
    panel.bg = panel:CreateTexture(nil, "BACKGROUND")
    panel.bg:SetAllPoints(panel)
    SetPanelBackground(panel.bg)
    panel:SetScript("OnMouseWheel", function(sel, delta)
        offset = offset - delta * 3
        UpdateRows()
    end)

    searchBox = CreateFrame("EditBox", "AchievementsUtilsSearchBox", panel, "InputBoxTemplate")
    searchBox:SetHeight(20)
    searchBox:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -6)
    searchBox:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -6)
    searchBox:SetAutoFocus(false)
    searchBox:SetScript("OnEscapePressed", function(sel) sel:ClearFocus() end)
    searchBox:SetScript("OnEnterPressed", function(sel) sel:ClearFocus() end)
    searchBox:SetScript("OnTextChanged", function(sel)
        if searchRestoring then return end
        if activeTab then searchTexts[activeTab] = sel:GetText() end
        if searchPending then return end
        searchPending = true
        C_Timer.After(0.25, function()
            searchPending = false
            if activeTab == "TABSEARCH" then
                offset = 0
                Refresh()
            elseif UsesFilter() then
                offset = 0
                ApplyCollapse()
                UpdateRows()
            end
        end)
    end)

    statusText = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    statusText:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 8, 4)
    statusText:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -8, 4)
    statusText:SetJustifyH("LEFT")
    scrollBar = CreateScrollBar()
    scrollBar:Hide()
    for i = 1, MAX_ROWS do
        rows[i] = CreateRow(panel, i)
        rows[i]:Hide()
    end

    AchievementFrame:HookScript("OnHide", function() AchievementsUtils:HideExtraTab() end)
end

local function UpdateTabVisuals()
    for _, tab in ipairs(tabs) do
        local selected = tab.key == activeTab
        if tab.auCustom then
            if selected then
                tab.bg:SetVertexColor(0.25, 0.25, 0.3, 1)
                tab.text:SetTextColor(1, 0.82, 0)
            else
                tab.bg:SetVertexColor(0.1, 0.1, 0.12, 1)
                tab.text:SetTextColor(0.7, 0.7, 0.7)
            end
        elseif tab.LeftActive and type(PanelTemplates_SelectTab) == "function" and type(PanelTemplates_DeselectTab) == "function" then
            if selected then
                PanelTemplates_SelectTab(tab)
            else
                PanelTemplates_DeselectTab(tab)
            end
        end
    end
end

local function DeselectBlizzardTabs()
    if type(PanelTemplates_DeselectTab) ~= "function" then return end
    for i = 1, 10 do
        local tab = _G["AchievementFrameTab" .. i]
        if tab == nil then break end
        if tab.LeftActive then PanelTemplates_DeselectTab(tab) end
    end
end

local function RestoreBlizzardTabs()
    if type(AchievementFrame) ~= "table" then return end
    if type(PanelTemplates_UpdateTabs) ~= "function" then return end
    if AchievementFrame.numTabs == nil or AchievementFrame.selectedTab == nil then return end
    PanelTemplates_UpdateTabs(AchievementFrame)
end

local function SaveState()
    if not AchievementsUtils:IsEnabled("RESTORESTATE") then return end
    AchievementsUtils:SV(AchievementsUtils:GetCharDB(), "LASTSTATE", {
        ["tab"] = activeTab,
        ["achievement"] = selectedAchievement
    })
end

local function RestoreState()
    if restored then return end
    restored = true
    if not AchievementsUtils:IsEnabled("RESTORESTATE") then return end
    if activeTab ~= nil then return end
    local state = AchievementsUtils:GV(AchievementsUtils:GetCharDB(), "LASTSTATE", nil)
    if type(state) ~= "table" then return end
    if type(state.achievement) == "number" and type(AchievementFrame_SelectAchievement) == "function" then AchievementFrame_SelectAchievement(state.achievement) end
    if type(state.tab) == "string" and AchievementsUtils:IsEnabled(state.tab) then AchievementsUtils:ShowExtraTab(state.tab) end
end

function AchievementsUtils:HideExtraTab()
    if activeTab == nil then return end
    activeTab = nil
    if panel then panel:Hide() end
    UpdateTabVisuals()
    RestoreBlizzardTabs()
    SaveState()
end

function AchievementsUtils:ShowExtraTab(key)
    if not AchievementsUtils:IsEnabled(key) then return end
    CreatePanel()
    if panel == nil then return end
    activeTab = key
    offset = 0
    RaisePanel()
    panel:Show()
    if key == "TABSEARCH" or UsesFilter() then
        searchRestoring = true
        searchBox:SetText(searchTexts[key] or "")
        searchRestoring = false
        searchBox:Show()
    else
        searchBox:Hide()
    end

    UpdateTabVisuals()
    DeselectBlizzardTabs()
    AchievementsUtils:BuildIndex()
    Refresh()
    SaveState()
end

local function CreateTab(def, index)
    local name = "AchievementsUtilsTab" .. index
    local tab = nil
    if AchievementsUtils:CheckTemplates("AchievementFrameTabButtonTemplate") then
        tab = CreateFrame("Button", name, AchievementFrame, "AchievementFrameTabButtonTemplate")
    elseif AchievementsUtils:CheckTemplates("PanelTabButtonTemplate") then
        tab = CreateFrame("Button", name, AchievementFrame, "PanelTabButtonTemplate")
    elseif AchievementsUtils:CheckTemplates("CharacterFrameTabButtonTemplate") then
        tab = CreateFrame("Button", name, AchievementFrame, "CharacterFrameTabButtonTemplate")
    end

    local label = AchievementsUtils:Trans(def.label)
    if tab == nil then
        tab = CreateFrame("Button", name, AchievementFrame)
        tab:SetSize(90, 24)
        tab.auCustom = true
        tab.bg = tab:CreateTexture(nil, "BACKGROUND")
        tab.bg:SetAllPoints(tab)
        if tab.bg.SetColorTexture then
            tab.bg:SetColorTexture(1, 1, 1, 1)
        else
            tab.bg:SetTexture(1, 1, 1, 1)
        end

        tab.text = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        tab.text:SetPoint("CENTER", tab, "CENTER", 0, 0)
        tab.text:SetText(label)
    else
        tab:SetText(label)
        if tab.LeftActive then
            tab.deselectedTextY = -3
            tab.selectedTextY = -5
            if type(PanelTemplates_DeselectTab) == "function" then PanelTemplates_DeselectTab(tab) end
        end

        if type(PanelTemplates_TabResize) == "function" and tab.Left then
            PanelTemplates_TabResize(tab, 30)
        elseif tab.GetTextWidth then
            tab:SetWidth(tab:GetTextWidth() + 34)
        end
    end

    tab.key = def.key
    tab:SetScript("OnClick", function()
        if activeTab == def.key then
            AchievementsUtils:HideExtraTab()
        else
            AchievementsUtils:ShowExtraTab(def.key)
        end
    end)
    return tab
end

local function GetTabChainOffset()
    local third = _G["AchievementFrameTab3"]
    if third and third.GetNumPoints and third:GetNumPoints() > 0 then
        local point, _, relativePoint, x, y = third:GetPoint(1)
        if point == "LEFT" and relativePoint == "RIGHT" and type(x) == "number" then return x, y or 0 end
    end
    return -5, 0
end

local function LayoutTabs()
    local previous = nil
    local lastBlizzard = nil
    for i = 1, 10 do
        local blizzardTab = _G["AchievementFrameTab" .. i]
        if blizzardTab and blizzardTab:IsShown() then lastBlizzard = blizzardTab end
    end

    local chainX, chainY = GetTabChainOffset()
    for _, tab in ipairs(tabs) do
        if AchievementsUtils:IsEnabled(tab.key) then
            tab:ClearAllPoints()
            local anchor = previous or lastBlizzard
            if anchor == nil then
                tab:SetPoint("TOPLEFT", AchievementFrame, "BOTTOMLEFT", 17, 3)
            elseif tab.auCustom or anchor.auCustom then
                tab:SetPoint("LEFT", anchor, "RIGHT", TAB_SPACING, 0)
            else
                tab:SetPoint("LEFT", anchor, "RIGHT", chainX + TAB_SPACING, chainY)
            end

            tab:Show()
            previous = tab
        else
            tab:Hide()
            if activeTab == tab.key then AchievementsUtils:HideExtraTab() end
        end
    end
end

local function HookBlizzardTabs()
    if blizzardHooked then return end
    blizzardHooked = true
    for i = 1, 10 do
        local tab = _G["AchievementFrameTab" .. i]
        if tab == nil then break end
        tab:HookScript("OnClick", function() AchievementsUtils:HideExtraTab() end)
    end
end

local function InstallTabs()
    if not AchievementsUtils:IsEnabled("TABS") then return end
    if type(AchievementFrame) ~= "table" then return end
    HookBlizzardTabs()
    if #tabs <= 0 then
        for i, def in ipairs(tabDefs) do
            tabs[i] = CreateTab(def, i)
        end
    end

    LayoutTabs()
end

function AchievementsUtils:OpenSearchTab(text)
    if not AchievementsUtils:OpenAchievementUI() then return end
    InstallTabs()
    if not AchievementsUtils:IsEnabled("TABSEARCH") then return end
    AchievementsUtils:ShowExtraTab("TABSEARCH")
    if searchBox and text then
        searchBox:SetText(text)
        offset = 0
        Refresh()
    end
end

function AchievementsUtils:RefreshExtraTab()
    if activeTab == nil then return end
    Refresh()
end

local function HookAchievementButton(button)
    if type(button) ~= "table" then return end
    if button.auTabsHooked then return end
    if button.HookScript == nil then return end
    button.auTabsHooked = true
    button:HookScript("OnClick", function(sel)
        if type(sel.id) ~= "number" then return end
        selectedAchievement = sel.id
        SaveState()
        if activeTab == "TABRELATED" then Refresh() end
    end)

    button:HookScript("OnMouseUp", function(sel, mouseButton)
        if mouseButton ~= "RightButton" then return end
        if type(sel.id) ~= "number" then return end
        if AchievementsUtils:ShowAchievementMenu(sel.id, sel) then return end
        if not AchievementsUtils:IsEnabled("TABWATCH") then return end
        AchievementsUtils:ToggleWatch(sel.id)
        AchievementsUtils:RefreshAchievementTooltip(sel, sel.id)
    end)
end

local function InstallSelectionHooks()
    if EventRegistry and EventRegistry.RegisterCallback then
        EventRegistry:RegisterCallback("AchievementFrameAchievement.OnEnter", function(_, button) HookAchievementButton(button) end, "AchievementsUtilsTabs")
        return
    end

    if type(_G["AchievementButton_OnEnter"]) == "function" then hooksecurefunc("AchievementButton_OnEnter", HookAchievementButton) end
end

AchievementsUtils:OnAchievementUIReady(function()
    InstallTabs()
    InstallSelectionHooks()
    if type(AchievementFrame_SelectAchievement) == "function" then
        hooksecurefunc("AchievementFrame_SelectAchievement", function(id)
            if type(id) == "number" then
                selectedAchievement = id
                SaveState()
            end

            if activeTab == "TABRELATED" then Refresh() end
        end)
    end

    if type(AchievementFrame) == "table" then AchievementFrame:HookScript("OnShow", function() C_Timer.After(0, RestoreState) end) end
    if type(PanelTemplates_SetTab) == "function" then hooksecurefunc("PanelTemplates_SetTab", function(frame) if frame == AchievementFrame then AchievementsUtils:HideExtraTab() end end) end
end)

for _, def in ipairs(tabDefs) do
    AchievementsUtils:OnOptionChanged(def.key, function() if #tabs > 0 then LayoutTabs() end end)
end

AchievementsUtils:OnOptionChanged("TABS", function(value)
    if value ~= true then
        AchievementsUtils:HideExtraTab()
        for _, tab in ipairs(tabs) do
            tab:Hide()
        end
        return
    end

    if not AchievementsUtils:LoadAchievementUI() then return end
    InstallTabs()
end)

AchievementsUtils:OnOptionChanged("ACHSTYLE", function()
    if activeTab == nil then return end
    offset = 0
    UpdateRows()
end)

AchievementsUtils:OnOptionChanged("WATCHLIST", function()
    if activeTab == "TABWATCH" then
        AchievementsUtils:RefreshExtraTab()
        return
    end

    UpdateRows()
end)

local function OnZoneChanged()
    if activeTab ~= "TABSUGGESTIONS" then return end
    if panel == nil or not panel:IsShown() then return end
    if zonePending then return end
    zonePending = true
    C_Timer.After(ZONE_REFRESH_DELAY, function()
        zonePending = false
        if activeTab ~= "TABSUGGESTIONS" then return end
        if panel == nil or not panel:IsShown() then return end
        if GetZoneText() == lastZone and GetSubZoneText() == lastSubZone then return end
        AchievementsUtils:RefreshExtraTab()
    end)
end

AchievementsUtils:AddEvent("ACHIEVEMENT_EARNED", function()
    suggestCache = nil
    if activeTab ~= "TABSUGGESTIONS" then return end
    if panel == nil or not panel:IsShown() then return end
    AchievementsUtils:RefreshExtraTab()
end)

AchievementsUtils:AddEvent("ZONE_CHANGED", OnZoneChanged)
AchievementsUtils:AddEvent("ZONE_CHANGED_INDOORS", OnZoneChanged)
AchievementsUtils:AddEvent("ZONE_CHANGED_NEW_AREA", OnZoneChanged)
