local _, AchievementsUtils = ...
local ROW_HEIGHT = 26
local HEADER_HEIGHT = 30
local FOOTER_HEIGHT = 18
local MAX_ROWS = 40
local STRATA_ORDER = {"BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "FULLSCREEN", "FULLSCREEN_DIALOG"}
local COLLAPSED_ICON = "Interface\\Buttons\\UI-PlusButton-Up"
local EXPANDED_ICON = "Interface\\Buttons\\UI-MinusButton-Up"
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
local tabs = {}
local rows = {}
local items = {}
local visibleItems = {}
local activeTab = nil
local offset = 0
local selectedAchievement = nil
local searchPending = false
local restored = false

local function CountVisibleRows()
    if panel == nil then return 0 end
    local height = panel:GetHeight()
    if height == nil or height <= 0 then return 10 end
    height = height - HEADER_HEIGHT - FOOTER_HEIGHT
    local count = math.floor(height / ROW_HEIGHT)
    if count < 1 then count = 1 end
    if count > MAX_ROWS then count = MAX_ROWS end

    return count
end

local function AddItem(id, seen)
    if type(id) ~= "number" then return end
    if seen[id] then return end
    seen[id] = true
    tinsert(
        items,
        {
            ["id"] = id
        }
    )
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

local function ApplyCollapse()
    wipe(visibleItems)
    local hiddenLevel = nil
    for _, item in ipairs(items) do
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
    tinsert(
        items,
        {
            ["header"] = text,
            ["key"] = key,
            ["level"] = level or 1
        }
    )
end

local function AddGroup(list, seen, keyPrefix)
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
        AddHeader(AchievementsUtils:Trans("LID_SINGLEACHIEVEMENTS"), keyPrefix .. ":SINGLE", 2)
        for _, entry in ipairs(singles) do
            AddItem(entry.id, seen)
        end

        AddHeader(AchievementsUtils:Trans("LID_METAACHIEVEMENTS"), keyPrefix .. ":META", 2)
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
    tinsert(
        items,
        {
            ["info"] = text
        }
    )
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
            if isHoliday then tinsert(names, info.title) end
        end
    end

    return names
end

local function BuildSuggestions()
    local seen = {}
    if not AchievementsUtils:IsIndexReady() then
        AddInfo(AchievementsUtils:GetIndexStatus())

        return
    end

    local zone = GetZoneText()
    if zone and zone ~= "" then
        local list = AchievementsUtils:FindZoneAchievements(zone, 30)
        if #list > 0 then
            AddHeader(AchievementsUtils:Trans("LID_CURRENTZONE", nil, zone), "ZONE")
            AddGroup(list, seen, "ZONE")
        end
    end

    local sub = GetSubZoneText()
    if sub and sub ~= "" and sub ~= zone then
        local list = AchievementsUtils:FindZoneAchievements(sub, 20)
        if #list > 0 then
            AddHeader(AchievementsUtils:Trans("LID_CURRENTZONE", nil, sub), "SUBZONE")
            AddGroup(list, seen, "SUBZONE")
        end
    end

    for _, title in ipairs(GetHolidayNames()) do
        local categoryID = AchievementsUtils:FindCategoryByName(title)
        if categoryID then
            local list = AchievementsUtils:FindCategoryAchievements(categoryID, true, 30)
            if #list > 0 then
                AddHeader(AchievementsUtils:Trans("LID_HOLIDAY", nil, title), "HOLIDAY:" .. title)
                AddGroup(list, seen, "HOLIDAY:" .. title)
            end
        end
    end

    local progress = AchievementsUtils:FindInProgress(20)
    if #progress > 0 then
        AddHeader(AchievementsUtils:Trans("LID_INPROGRESS"), "INPROGRESS")
        AddGroup(progress, seen, "INPROGRESS")
    end

    if #items <= 0 then AddInfo(AchievementsUtils:Trans("LID_NOSUGGESTIONS")) end
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

local function UpdateStatus()
    if statusText == nil then return end
    local count = 0
    for _, item in ipairs(items) do
        if item.id then count = count + 1 end
    end

    local text = AchievementsUtils:Trans("LID_RESULTS", nil, count)
    if not AchievementsUtils:IsIndexReady() or (activeTab == "TABRELATED" and not AchievementsUtils:IsCriteriaIndexReady()) then text = text .. "  |cff888888" .. AchievementsUtils:GetIndexStatus() .. "|r" end
    statusText:SetText(text)
end

local function UpdateRows()
    if panel == nil then return end
    local visible = CountVisibleRows()
    local maxOffset = #visibleItems - visible
    if maxOffset < 0 then maxOffset = 0 end
    if offset > maxOffset then offset = maxOffset end
    if offset < 0 then offset = 0 end
    for i = 1, MAX_ROWS do
        local row = rows[i]
        if row and i > visible then row:Hide() end
    end

    for i = 1, visible do
        local row = rows[i]
        if row == nil then break end
        local item = visibleItems[i + offset]
        if item == nil then
            row:Hide()
        else
            row:Show()
            row.id = nil
            row.headerKey = nil
            row.icon:Hide()
            row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            row.icon:SetSize(20, 20)
            row.icon:ClearAllPoints()
            row.icon:SetPoint("LEFT", row, "LEFT", 2, 0)
            row.right:SetText("")
            row.name:SetFontObject("GameFontNormal")
            if item.header then
                local level = item.level or 1
                if level > 1 then
                    row.icon:ClearAllPoints()
                    row.icon:SetPoint("LEFT", row, "LEFT", 16, 0)
                else
                    row.name:SetFontObject("GameFontNormalLarge")
                end

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

local function Refresh()
    if panel == nil then return end
    wipe(items)
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
        AchievementsUtils:ToggleWatch(sel.id)
        Refresh()

        return
    end

    if AchievementsUtils:IsEnabled("WOWHEAD") and IsAltKeyDown() then
        AchievementsUtils:ShowWowheadLink(sel.id)

        return
    end

    if IsControlKeyDown() then
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
    GameTooltip:AddLine(AchievementsUtils:Trans("LID_CTRLCLICKTRACK"), 0.6, 0.6, 0.6)
    GameTooltip:AddLine(AchievementsUtils:Trans("LID_RIGHTCLICKWATCH"), 0.6, 0.6, 0.6)
    if AchievementsUtils:IsEnabled("WOWHEAD") then GameTooltip:AddLine(AchievementsUtils:Trans("LID_ALTCLICKWOWHEAD"), 0.6, 0.6, 0.6) end
    GameTooltip:Show()
end

local function RowOnLeave()
    GameTooltip:Hide()
end

local function CreateRow(parentFrame, i)
    local row = CreateFrame("Button", "AchievementsUtilsRow" .. i, parentFrame)
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

local function CreatePanel()
    if panel ~= nil then return end
    if type(AchievementFrame) ~= "table" then return end
    panel = CreateFrame("Frame", "AchievementsUtilsPanel", AchievementFrame)
    local top = _G["AchievementFrameCategories"]
    if top then
        panel:SetPoint("TOPLEFT", top, "TOPLEFT", -4, 6)
    else
        panel:SetPoint("TOPLEFT", AchievementFrame, "TOPLEFT", 20, -70)
    end

    panel:SetPoint("BOTTOMRIGHT", AchievementFrame, "BOTTOMRIGHT", -22, 26)
    RaisePanel()
    panel:EnableMouse(true)
    panel:EnableMouseWheel(true)
    panel:Hide()
    panel.bg = panel:CreateTexture(nil, "BACKGROUND")
    panel.bg:SetAllPoints(panel)
    if panel.bg.SetColorTexture then
        panel.bg:SetColorTexture(0.04, 0.04, 0.06, 1)
    else
        panel.bg:SetTexture(0.04, 0.04, 0.06, 1)
    end

    panel:SetScript(
        "OnMouseWheel",
        function(sel, delta)
            offset = offset - delta * 3
            UpdateRows()
        end
    )

    searchBox = CreateFrame("EditBox", "AchievementsUtilsSearchBox", panel, "InputBoxTemplate")
    searchBox:SetHeight(20)
    searchBox:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -6)
    searchBox:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -6)
    searchBox:SetAutoFocus(false)
    searchBox:SetScript(
        "OnEscapePressed",
        function(sel)
            sel:ClearFocus()
        end
    )

    searchBox:SetScript(
        "OnEnterPressed",
        function(sel)
            sel:ClearFocus()
        end
    )

    searchBox:SetScript(
        "OnTextChanged",
        function()
            if searchPending then return end
            searchPending = true
            C_Timer.After(
                0.25,
                function()
                    searchPending = false
                    if activeTab == "TABSEARCH" then
                        offset = 0
                        Refresh()
                    end
                end
            )
        end
    )

    statusText = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    statusText:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 8, 4)
    statusText:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -8, 4)
    statusText:SetJustifyH("LEFT")
    for i = 1, MAX_ROWS do
        rows[i] = CreateRow(panel, i)
        rows[i]:Hide()
    end

    AchievementFrame:HookScript(
        "OnHide",
        function()
            AchievementsUtils:HideExtraTab()
        end
    )
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
    AchievementsUtils:SV(
        AchievementsUtils:GetCharDB(),
        "LASTSTATE",
        {
            ["tab"] = activeTab,
            ["achievement"] = selectedAchievement
        }
    )
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
    if key == "TABSEARCH" then
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
    tab:SetScript(
        "OnClick",
        function()
            if activeTab == def.key then
                AchievementsUtils:HideExtraTab()
            else
                AchievementsUtils:ShowExtraTab(def.key)
            end
        end
    )

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
                tab:SetPoint("LEFT", anchor, "RIGHT", 2, 0)
            else
                tab:SetPoint("LEFT", anchor, "RIGHT", chainX, chainY)
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
    button:HookScript(
        "OnClick",
        function(sel)
            if type(sel.id) ~= "number" then return end
            selectedAchievement = sel.id
            SaveState()
            if activeTab == "TABRELATED" then Refresh() end
        end
    )
end

local function InstallSelectionHooks()
    if EventRegistry and EventRegistry.RegisterCallback then
        EventRegistry:RegisterCallback(
            "AchievementFrameAchievement.OnEnter",
            function(_, button)
                HookAchievementButton(button)
            end,
            "AchievementsUtilsTabs"
        )

        return
    end

    if type(_G["AchievementButton_OnEnter"]) == "function" then hooksecurefunc("AchievementButton_OnEnter", HookAchievementButton) end
end

AchievementsUtils:OnAchievementUIReady(
    function()
        InstallTabs()
        InstallSelectionHooks()
        if type(AchievementFrame_SelectAchievement) == "function" then
            hooksecurefunc(
                "AchievementFrame_SelectAchievement",
                function(id)
                    if type(id) == "number" then
                        selectedAchievement = id
                        SaveState()
                    end

                    if activeTab == "TABRELATED" then Refresh() end
                end
            )
        end

        if type(AchievementFrame) == "table" then
            AchievementFrame:HookScript(
                "OnShow",
                function()
                    C_Timer.After(0, RestoreState)
                end
            )
        end

        if type(PanelTemplates_SetTab) == "function" then
            hooksecurefunc(
                "PanelTemplates_SetTab",
                function(frame)
                    if frame == AchievementFrame then AchievementsUtils:HideExtraTab() end
                end
            )
        end
    end
)

for _, def in ipairs(tabDefs) do
    AchievementsUtils:OnOptionChanged(
        def.key,
        function()
            if #tabs > 0 then LayoutTabs() end
        end
    )
end

AchievementsUtils:OnOptionChanged(
    "TABS",
    function(value)
        if value ~= true then
            AchievementsUtils:HideExtraTab()
            for _, tab in ipairs(tabs) do
                tab:Hide()
            end

            return
        end

        if not AchievementsUtils:LoadAchievementUI() then return end
        InstallTabs()
    end
)

AchievementsUtils:OnOptionChanged("WATCHLIST", function() AchievementsUtils:RefreshExtraTab() end)
