local _, AchievementsUtils = ...
local ADDON = "AchievementsUtils"
local ICON = 133176
local META_CRITERIA_TYPE = 8
local WOWHEAD_POPUP = "ACHIEVEMENTSUTILS_WOWHEAD"
local WOWHEAD_LOCALES = {
    ["deDE"] = "de",
    ["esES"] = "es",
    ["esMX"] = "es",
    ["frFR"] = "fr",
    ["itIT"] = "it",
    ["ptBR"] = "pt",
    ["ruRU"] = "ru",
    ["koKR"] = "ko",
    ["zhCN"] = "cn"
}

local optionList = {}
local optionByKey = {}
local optionCallbacks = {}
local eventHandlers = {}
local hasAchievementAPI = nil
local trackingType = nil
if Enum and Enum.ContentTrackingType then trackingType = Enum.ContentTrackingType.Achievement end
local events = CreateFrame("Frame", "AchievementsUtilsEventFrame")
events:SetScript("OnEvent", function(sel, event, ...)
    local handlers = eventHandlers[event]
    if handlers == nil then return end
    for _, callback in ipairs(handlers) do
        callback(event, ...)
    end
end)

local options = {
    {
        ["key"] = "CATGENERAL",
        ["kind"] = "category",
        ["label"] = "LID_GENERAL"
    },
    {
        ["key"] = "SHOWMINIMAPBUTTON",
        ["kind"] = "toggle",
        ["label"] = "LID_SHOWMINIMAPBUTTON",
        ["default"] = AchievementsUtils:GetWoWBuild() ~= "RETAIL"
    },
    {
        ["key"] = "CATFRAME",
        ["kind"] = "category",
        ["label"] = "LID_ACHIEVEMENTFRAME"
    },
    {
        ["key"] = "MOVABLE",
        ["kind"] = "toggle",
        ["label"] = "LID_MOVABLE",
        ["default"] = true
    },
    {
        ["key"] = "SAVEPOSITION",
        ["kind"] = "toggle",
        ["label"] = "LID_SAVEPOSITION",
        ["parent"] = "MOVABLE",
        ["default"] = true
    },
    {
        ["key"] = "RESTORESTATE",
        ["kind"] = "toggle",
        ["label"] = "LID_RESTORESTATE",
        ["default"] = true
    },
    {
        ["key"] = "HISTORY",
        ["kind"] = "toggle",
        ["label"] = "LID_HISTORY",
        ["default"] = true
    },
    {
        ["key"] = "HISTORYMAX",
        ["kind"] = "slider",
        ["label"] = "LID_HISTORYMAX",
        ["parent"] = "HISTORY",
        ["default"] = 20,
        ["min"] = 2,
        ["max"] = 50,
        ["step"] = 1,
        ["decimals"] = 0
    },
    {
        ["key"] = "CATTABS",
        ["kind"] = "category",
        ["label"] = "LID_TABS"
    },
    {
        ["key"] = "TABS",
        ["kind"] = "toggle",
        ["label"] = "LID_ENABLETABS",
        ["default"] = true
    },
    {
        ["key"] = "TABSEARCH",
        ["kind"] = "toggle",
        ["label"] = "LID_TABSEARCH",
        ["parent"] = "TABS",
        ["default"] = true
    },
    {
        ["key"] = "TABSUGGESTIONS",
        ["kind"] = "toggle",
        ["label"] = "LID_TABSUGGESTIONS",
        ["parent"] = "TABS",
        ["default"] = true
    },
    {
        ["key"] = "TABWATCH",
        ["kind"] = "toggle",
        ["label"] = "LID_TABWATCH",
        ["parent"] = "TABS",
        ["default"] = true
    },
    {
        ["key"] = "TABRELATED",
        ["kind"] = "toggle",
        ["label"] = "LID_TABRELATED",
        ["parent"] = "TABS",
        ["default"] = true
    },
    {
        ["key"] = "ACHSTYLE",
        ["kind"] = "dropdown",
        ["label"] = "LID_ACHSTYLE",
        ["parent"] = "TABS",
        ["default"] = "DEFAULT"
    },
    {
        ["key"] = "CATTOOLTIP",
        ["kind"] = "category",
        ["label"] = "LID_ACHIEVEMENTTOOLTIP"
    },
    {
        ["key"] = "ACHTOOLTIP",
        ["kind"] = "toggle",
        ["label"] = "LID_ENABLEACHTOOLTIP",
        ["default"] = true
    },
    {
        ["key"] = "TTPROGRESS",
        ["kind"] = "toggle",
        ["label"] = "LID_TTPROGRESS",
        ["parent"] = "ACHTOOLTIP",
        ["default"] = true
    },
    {
        ["key"] = "TTSERIES",
        ["kind"] = "toggle",
        ["label"] = "LID_TTSERIES",
        ["parent"] = "ACHTOOLTIP",
        ["default"] = true
    },
    {
        ["key"] = "TTREQUIREDBY",
        ["kind"] = "toggle",
        ["label"] = "LID_TTREQUIREDBY",
        ["parent"] = "ACHTOOLTIP",
        ["needsIndex"] = true,
        ["default"] = true
    },
    {
        ["key"] = "TTTRACKER",
        ["kind"] = "toggle",
        ["label"] = "LID_TTTRACKER",
        ["parent"] = "ACHTOOLTIP",
        ["default"] = true
    },
    {
        ["key"] = "TTID",
        ["kind"] = "toggle",
        ["label"] = "LID_TTID",
        ["parent"] = "ACHTOOLTIP",
        ["default"] = false
    },
    {
        ["key"] = "TTMAXLINES",
        ["kind"] = "slider",
        ["label"] = "LID_TTMAXLINES",
        ["parent"] = "ACHTOOLTIP",
        ["default"] = 10,
        ["min"] = 1,
        ["max"] = 30,
        ["step"] = 1,
        ["decimals"] = 0
    },
    {
        ["key"] = "CATLINKS",
        ["kind"] = "category",
        ["label"] = "LID_LINKS"
    },
    {
        ["key"] = "LINKS",
        ["kind"] = "toggle",
        ["label"] = "LID_ENABLELINKS",
        ["default"] = true
    },
    {
        ["key"] = "LINKCOMPARE",
        ["kind"] = "toggle",
        ["label"] = "LID_LINKCOMPARE",
        ["parent"] = "LINKS",
        ["default"] = true
    },
    {
        ["key"] = "LINKTRACK",
        ["kind"] = "toggle",
        ["label"] = "LID_LINKTRACK",
        ["parent"] = "LINKS",
        ["default"] = true
    },
    {
        ["key"] = "WOWHEAD",
        ["kind"] = "toggle",
        ["label"] = "LID_WOWHEAD",
        ["default"] = true
    },
    {
        ["key"] = "CATREMINDERS",
        ["kind"] = "category",
        ["label"] = "LID_REMINDERS"
    },
    {
        ["key"] = "REMINDERS",
        ["kind"] = "toggle",
        ["label"] = "LID_ENABLEREMINDERS",
        ["needsIndex"] = true,
        ["default"] = true
    },
    {
        ["key"] = "REMINDERUNITS",
        ["kind"] = "toggle",
        ["label"] = "LID_REMINDERUNITS",
        ["parent"] = "REMINDERS",
        ["default"] = true
    },
    {
        ["key"] = "REMINDERCLASSES",
        ["kind"] = "toggle",
        ["label"] = "LID_REMINDERCLASSES",
        ["parent"] = "REMINDERUNITS",
        ["default"] = true
    },
    {
        ["key"] = "REMINDERITEMS",
        ["kind"] = "toggle",
        ["label"] = "LID_REMINDERITEMS",
        ["parent"] = "REMINDERS",
        ["default"] = true
    },
    {
        ["key"] = "REMINDEROBJECTS",
        ["kind"] = "toggle",
        ["label"] = "LID_REMINDEROBJECTS",
        ["parent"] = "REMINDERS",
        ["default"] = true
    },
    {
        ["key"] = "REMINDERDONE",
        ["kind"] = "toggle",
        ["label"] = "LID_REMINDERDONE",
        ["parent"] = "REMINDERS",
        ["default"] = true
    },
    {
        ["key"] = "REMINDERSOUND",
        ["kind"] = "toggle",
        ["label"] = "LID_REMINDERSOUND",
        ["parent"] = "REMINDERS",
        ["default"] = false
    },
    {
        ["key"] = "REMINDERSOUNDID",
        ["kind"] = "dropdown",
        ["label"] = "LID_REMINDERSOUNDID",
        ["parent"] = "REMINDERSOUND",
        ["default"] = "RAID_WARNING"
    },
    {
        ["key"] = "CATAUTOTRACK",
        ["kind"] = "category",
        ["label"] = "LID_AUTOTRACK"
    },
    {
        ["key"] = "AUTOTRACK",
        ["kind"] = "toggle",
        ["label"] = "LID_ENABLEAUTOTRACK",
        ["default"] = true
    },
    {
        ["key"] = "AUTOTRACKZONE",
        ["kind"] = "toggle",
        ["label"] = "LID_AUTOTRACKZONE",
        ["parent"] = "AUTOTRACK",
        ["needsIndex"] = true,
        ["default"] = true
    },
    {
        ["key"] = "AUTOTRACKTIMED",
        ["kind"] = "toggle",
        ["label"] = "LID_AUTOTRACKTIMED",
        ["parent"] = "AUTOTRACK",
        ["needsIndex"] = true,
        ["default"] = true
    },
    {
        ["key"] = "AUTOTRACKWATCH",
        ["kind"] = "toggle",
        ["label"] = "LID_AUTOTRACKWATCH",
        ["parent"] = "AUTOTRACK",
        ["default"] = false
    },
    {
        ["key"] = "AUTOTRACKMAX",
        ["kind"] = "slider",
        ["label"] = "LID_AUTOTRACKMAX",
        ["parent"] = "AUTOTRACK",
        ["default"] = 3,
        ["min"] = 1,
        ["max"] = 10,
        ["step"] = 1,
        ["decimals"] = 0
    },
}

for _, info in ipairs(options) do
    tinsert(optionList, info)
    optionByKey[info.key] = info
end

function AchievementsUtils:IsSecret(value)
    return issecretvalue ~= nil and issecretvalue(value) == true
end

function AchievementsUtils:GetAddonName()
    return ADDON
end

function AchievementsUtils:GetIcon()
    return ICON
end

function AchievementsUtils:GetMetaCriteriaType()
    return META_CRITERIA_TYPE
end

function AchievementsUtils:GetOptionList()
    return optionList
end

function AchievementsUtils:GetOptionInfo(key)
    return optionByKey[key]
end

function AchievementsUtils:GetDB()
    AchievementsUtilsDB = AchievementsUtilsDB or {}
    return AchievementsUtilsDB
end

function AchievementsUtils:GetCharDB()
    AchievementsUtilsPCDB = AchievementsUtilsPCDB or {}
    return AchievementsUtilsPCDB
end

function AchievementsUtils:GetOption(key)
    local info = optionByKey[key]
    local default = nil
    if info then default = info.default end
    return AchievementsUtils:GV(AchievementsUtils:GetDB(), key, default)
end

function AchievementsUtils:OnOptionChanged(key, callback)
    optionCallbacks[key] = optionCallbacks[key] or {}
    tinsert(optionCallbacks[key], callback)
end

local function FireOption(key, value)
    local list = optionCallbacks[key]
    if list == nil then return end
    for _, callback in ipairs(list) do
        callback(value, key)
    end
end

local function FireChildren(key)
    for _, info in ipairs(optionList) do
        if info.parent == key then
            FireOption(info.key, AchievementsUtils:GetOption(info.key))
            FireChildren(info.key)
        end
    end
end

function AchievementsUtils:SetOption(key, value)
    AchievementsUtils:SV(AchievementsUtils:GetDB(), key, value)
    FireOption(key, value)
    FireChildren(key)
end

function AchievementsUtils:IsEnabled(key)
    local info = optionByKey[key]
    if info == nil then return false end
    while info do
        if AchievementsUtils:GetOption(info.key) ~= true then return false end
        info = optionByKey[info.parent]
    end
    return true
end

function AchievementsUtils:GetOptionLabel(key)
    local info = optionByKey[key]
    if info == nil then return key end
    return AchievementsUtils:TryTrans(info.label)
end

function AchievementsUtils:AddEvent(event, callback)
    if eventHandlers[event] == nil then
        eventHandlers[event] = {}
        AchievementsUtils:RegisterEvent(events, event)
    end

    tinsert(eventHandlers[event], callback)
end

local uiCallbacks = {}
local uiReady = false
local function CheckAchievementUI()
    if uiReady then return end
    if type(AchievementFrame) ~= "table" then return end
    uiReady = true
    for _, callback in ipairs(uiCallbacks) do
        callback()
    end

    uiCallbacks = {}
end

function AchievementsUtils:OnAchievementUIReady(callback)
    if uiReady then
        callback()
        return
    end

    tinsert(uiCallbacks, callback)
    CheckAchievementUI()
end

function AchievementsUtils:LoadAchievementUI()
    if type(AchievementFrame) ~= "table" then AchievementsUtils:LoadAddOn("Blizzard_AchievementUI") end
    CheckAchievementUI()
    return type(AchievementFrame) == "table"
end

function AchievementsUtils:HasAchievementAPI()
    if hasAchievementAPI == nil then hasAchievementAPI = type(GetAchievementInfo) == "function" and type(GetCategoryList) == "function" and type(GetAchievementNumCriteria) == "function" end
    return hasAchievementAPI
end

function AchievementsUtils:GetAchievement(id)
    if not AchievementsUtils:HasAchievementAPI() then return nil end
    if type(id) ~= "number" then return nil end
    local aid, name, points, completed, month, day, year, description, flags, icon, rewardText = GetAchievementInfo(id)
    if aid == nil or name == nil then return nil end
    return {
        ["id"] = aid,
        ["name"] = name,
        ["points"] = points or 0,
        ["completed"] = completed == true,
        ["month"] = month,
        ["day"] = day,
        ["year"] = year,
        ["description"] = description or "",
        ["flags"] = flags or 0,
        ["icon"] = icon,
        ["reward"] = rewardText or ""
    }
end

function AchievementsUtils:IsCompleted(id)
    local ach = AchievementsUtils:GetAchievement(id)
    if ach == nil then return false end
    return ach.completed
end

function AchievementsUtils:GetCriteriaProgress(id)
    if not AchievementsUtils:HasAchievementAPI() then return 0, 0 end
    local num = GetAchievementNumCriteria(id) or 0
    local done = 0
    for i = 1, num do
        local _, _, completed = GetAchievementCriteriaInfo(id, i)
        if completed then done = done + 1 end
    end
    return done, num
end

function AchievementsUtils:GetSeries(id)
    local before = {}
    local after = {}
    if type(GetPreviousAchievement) == "function" then
        local prev = GetPreviousAchievement(id)
        local guard = 0
        while prev and guard < 20 do
            tinsert(before, 1, prev)
            guard = guard + 1
            prev = GetPreviousAchievement(prev)
        end
    end

    if type(GetNextAchievement) == "function" then
        local next = GetNextAchievement(id)
        local guard = 0
        while next and guard < 20 do
            tinsert(after, next)
            guard = guard + 1
            next = GetNextAchievement(next)
        end
    end
    return before, after
end

function AchievementsUtils:IsTracked(id)
    if C_ContentTracking and trackingType and C_ContentTracking.IsTracking then return C_ContentTracking.IsTracking(trackingType, id) == true end
    if type(GetTrackedAchievements) == "function" then
        local tracked = {GetTrackedAchievements()}
        for _, value in ipairs(tracked) do
            if value == id then return true end
        end
    end
    return false
end

function AchievementsUtils:GetTrackedCount()
    if C_ContentTracking and trackingType and C_ContentTracking.GetTrackedIDs then
        local ids = C_ContentTracking.GetTrackedIDs(trackingType)
        if type(ids) == "table" then return #ids end
    end

    if type(GetTrackedAchievements) == "function" then
        local tracked = {GetTrackedAchievements()}
        return #tracked
    end
    return 0
end

function AchievementsUtils:SetTracked(id, value)
    if type(id) ~= "number" then return end
    if C_ContentTracking and trackingType then
        if value then
            if C_ContentTracking.StartTracking then C_ContentTracking.StartTracking(trackingType, id) end
        elseif C_ContentTracking.StopTracking then
            local stopType = nil
            if Enum and Enum.ContentTrackingStopType then stopType = Enum.ContentTrackingStopType.Manual end
            C_ContentTracking.StopTracking(trackingType, id, stopType)
        end
        return
    end

    if value then
        if type(AddTrackedAchievement) == "function" then AddTrackedAchievement(id) end
    elseif type(RemoveTrackedAchievement) == "function" then
        RemoveTrackedAchievement(id)
    end
end

function AchievementsUtils:ToggleTracked(id)
    local tracked = not AchievementsUtils:IsTracked(id)
    AchievementsUtils:SetTracked(id, tracked)
    return tracked
end

function AchievementsUtils:GetWatchList()
    local db = AchievementsUtils:GetCharDB()
    if type(db["WATCH"]) ~= "table" then db["WATCH"] = {} end
    return db["WATCH"]
end

function AchievementsUtils:IsWatched(id)
    for _, value in ipairs(AchievementsUtils:GetWatchList()) do
        if value == id then return true end
    end
    return false
end

function AchievementsUtils:ToggleWatch(id)
    local list = AchievementsUtils:GetWatchList()
    for i, value in ipairs(list) do
        if value == id then
            tremove(list, i)
            FireOption("WATCHLIST", list)
            return false
        end
    end

    tinsert(list, id)
    FireOption("WATCHLIST", list)
    return true
end

function AchievementsUtils:OpenAchievementUI()
    if not AchievementsUtils:LoadAchievementUI() then return false end
    if not AchievementFrame:IsShown() then
        if type(AchievementFrame_ToggleAchievementFrame) == "function" then
            AchievementFrame_ToggleAchievementFrame()
        elseif type(ShowUIPanel) == "function" then
            ShowUIPanel(AchievementFrame)
        else
            AchievementFrame:Show()
        end
    end
    return AchievementFrame:IsShown()
end

function AchievementsUtils:OpenToAchievement(id)
    if not AchievementsUtils:OpenAchievementUI() then return end
    if type(AchievementsUtils.HideExtraTab) == "function" then AchievementsUtils:HideExtraTab() end
    local tab = _G["AchievementFrameTab1"]
    if tab and tab.Click and AchievementFrame.selectedTab ~= 1 then tab:Click() end
    if type(AchievementFrame_SelectAchievement) == "function" then AchievementFrame_SelectAchievement(id) end
end

function AchievementsUtils:GetWowheadURL(id)
    if type(id) ~= "number" then return nil end
    local prefix = WOWHEAD_LOCALES[GetLocale()]
    if prefix then return format("https://www.wowhead.com/%s/achievement=%d", prefix, id) end
    return format("https://www.wowhead.com/achievement=%d", id)
end

local function SetupWowheadPopup()
    if type(StaticPopupDialogs) ~= "table" then return false end
    if type(StaticPopup_Show) ~= "function" then return false end
    if StaticPopupDialogs[WOWHEAD_POPUP] then return true end
    StaticPopupDialogs[WOWHEAD_POPUP] = {
        ["text"] = "%s",
        ["button1"] = OKAY or "OK",
        ["hasEditBox"] = true,
        ["editBoxWidth"] = 260,
        ["timeout"] = 0,
        ["whileDead"] = true,
        ["hideOnEscape"] = true,
        ["preferredIndex"] = 3,
        ["OnShow"] = function(sel, data)
            local box = sel.editBox
            if box == nil and sel.GetName then box = _G[(sel:GetName() or "") .. "EditBox"] end
            if box == nil then return end
            box:SetText(data or "")
            box:HighlightText()
            box:SetFocus()
        end,
        ["EditBoxOnEnterPressed"] = function(sel) sel:GetParent():Hide() end,
        ["EditBoxOnEscapePressed"] = function(sel) sel:GetParent():Hide() end
    }
    return true
end

function AchievementsUtils:ShowWowheadLink(id)
    local url = AchievementsUtils:GetWowheadURL(id)
    if url == nil then return end
    local ach = AchievementsUtils:GetAchievement(id)
    local name = tostring(id)
    if ach then name = ach.name end
    if not SetupWowheadPopup() then
        AchievementsUtils:MSG(AchievementsUtils:Trans("LID_WOWHEADPOPUP", nil, name), url)
        return
    end

    StaticPopupDialogs[WOWHEAD_POPUP].text = AchievementsUtils:Trans("LID_WOWHEADPOPUP", nil, "%s")
    StaticPopup_Show(WOWHEAD_POPUP, name, nil, url)
end

function AchievementsUtils:GetPoints(id)
    local ach = AchievementsUtils:GetAchievement(id)
    if ach == nil then return 0 end
    return ach.points
end

function AchievementsUtils:ColorByStatus(text, completed)
    if completed then return "|cff40ff40" .. text .. "|r" end
    return "|cffffd200" .. text .. "|r"
end

AchievementsUtils:AddEvent("ADDON_LOADED", function(event, name) if name == "Blizzard_AchievementUI" then CheckAchievementUI() end end)
AchievementsUtils:AddEvent("PLAYER_LOGIN", function() CheckAchievementUI() end)
