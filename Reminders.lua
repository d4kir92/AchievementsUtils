local _, AchievementsUtils = ...
local SOUND_KEYS = {"RAID_WARNING", "READY_CHECK", "MAP_PING", "IG_QUEST_LIST_OPEN", "ALARM_CLOCK_WARNING_3", "UI_TOAST_ANNOUNCEMENT"}
local SOUND_THROTTLE = 2
local MAX_REMINDER_LINES = 4
local lastSound = 0
local working = false

function AchievementsUtils:GetSoundChoices()
    local choices = {
        {
            ["value"] = "NONE",
            ["label"] = "LID_NONE"
        },
    }

    if SOUNDKIT == nil then return choices end
    for _, key in ipairs(SOUND_KEYS) do
        if SOUNDKIT[key] then
            tinsert(
                choices,
                {
                    ["value"] = key,
                    ["label"] = key
                }
            )
        end
    end

    return choices
end

local function PlayReminderSound()
    if not AchievementsUtils:IsEnabled("REMINDERSOUND") then return end
    if SOUNDKIT == nil or type(PlaySound) ~= "function" then return end
    local key = AchievementsUtils:GetOption("REMINDERSOUNDID")
    if key == nil or key == "NONE" then return end
    local soundID = SOUNDKIT[key]
    if soundID == nil then return end
    local now = GetTime()
    if now - lastSound < SOUND_THROTTLE then return end
    lastSound = now
    PlaySound(soundID)
end

local function AddLines(tooltip, name, quiet)
    if AchievementsUtils:IsSecret(name) then return false end
    if name == nil or name == "" then return false end
    local list = AchievementsUtils:FindByCriteriaName(name)
    if list == nil then return false end
    local shown = 0
    local needed = false
    for i = 1, #list, 2 do
        if shown >= MAX_REMINDER_LINES then break end
        local achID = list[i]
        local criteriaIndex = list[i + 1]
        local ach = AchievementsUtils:GetAchievement(achID)
        if ach and not ach.completed then
            local _, _, completed = GetAchievementCriteriaInfo(achID, criteriaIndex)
            if completed then
                if AchievementsUtils:IsEnabled("REMINDERDONE") then
                    tooltip:AddDoubleLine(ach.name, AchievementsUtils:Trans("LID_ALREADYDONE"), 0.4, 1, 0.4, 0.4, 1, 0.4)
                    shown = shown + 1
                end
            else
                tooltip:AddDoubleLine(ach.name, AchievementsUtils:Trans("LID_NEEDED"), 1, 0.82, 0, 1, 0.35, 0.35)
                shown = shown + 1
                needed = true
            end
        end
    end

    if shown <= 0 then return false end
    if needed and not quiet then PlayReminderSound() end

    return true
end

local function Finish(tooltip, changed, fresh)
    if changed and not fresh then tooltip:Show() end
end

local function Remember(tooltip, name, fresh)
    local known = tooltip.auReminder == name
    tooltip.auReminder = name
    if fresh then return true, known end

    return not known, known
end

local function GetTooltipName()
    local line = _G["GameTooltipTextLeft1"]
    if line == nil then return nil end
    local name = line:GetText()
    if AchievementsUtils:IsSecret(name) then return nil end
    if name == nil or name == "" then return nil end

    return name
end

local function HandleUnit(tooltip, fresh, unit)
    if not AchievementsUtils:IsEnabled("REMINDERUNITS") then return end
    local secret = AchievementsUtils:IsSecret(unit)
    if not secret and unit == nil then return end
    local name = nil
    if secret then
        name = GetTooltipName()
    elseif UnitExists(unit) then
        name = UnitName(unit)
    end

    if AchievementsUtils:IsSecret(name) then return end
    if name == nil or name == "" then return end
    local add, known = Remember(tooltip, name, fresh)
    if not add then return end
    local changed = AddLines(tooltip, name, known)
    if not secret and AchievementsUtils:IsEnabled("REMINDERCLASSES") and UnitIsPlayer(unit) then
        local className = UnitClass(unit)
        if not AchievementsUtils:IsSecret(className) and AddLines(tooltip, className, known) then changed = true end
    end

    Finish(tooltip, changed, fresh)
end

local function HandleItem(tooltip, fresh)
    if not AchievementsUtils:IsEnabled("REMINDERITEMS") then return end
    if tooltip.GetItem == nil then return end
    local name = tooltip:GetItem()
    if AchievementsUtils:IsSecret(name) then return end
    if name == nil or name == "" then return end
    local add, known = Remember(tooltip, name, fresh)
    if not add then return end
    Finish(tooltip, AddLines(tooltip, name, known), fresh)
end

local function HandleObject(tooltip, fresh)
    if not AchievementsUtils:IsEnabled("REMINDEROBJECTS") then return end
    if tooltip.GetUnit then
        local _, unit = tooltip:GetUnit()
        if AchievementsUtils:IsSecret(unit) then return end
        if unit then return end
    end

    if tooltip.GetItem then
        local item = tooltip:GetItem()
        if AchievementsUtils:IsSecret(item) then return end
        if item then return end
    end

    if tooltip.GetSpell then
        local spell = tooltip:GetSpell()
        if AchievementsUtils:IsSecret(spell) then return end
        if spell then return end
    end

    local line = _G["GameTooltipTextLeft1"]
    if line == nil then return end
    local name = line:GetText()
    if AchievementsUtils:IsSecret(name) then return end
    if name == nil or name == "" then return end
    local add, known = Remember(tooltip, name, fresh)
    if not add then return end
    Finish(tooltip, AddLines(tooltip, name, known), fresh)
end

local function Guarded(callback, tooltip, ...)
    if working then return end
    if not AchievementsUtils:IsEnabled("REMINDERS") then return end
    if tooltip ~= GameTooltip then return end
    if AchievementsUtils:HasWidgetSet(tooltip) then return end
    working = true
    callback(tooltip, ...)
    working = false
end

local objectPostCall = false
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(
        Enum.TooltipDataType.Unit,
        function(tooltip)
            if tooltip == nil or tooltip.GetUnit == nil then return end
            local _, unit = tooltip:GetUnit()
            Guarded(HandleUnit, tooltip, true, unit)
        end
    )

    TooltipDataProcessor.AddTooltipPostCall(
        Enum.TooltipDataType.Item,
        function(tooltip)
            Guarded(HandleItem, tooltip, true)
        end
    )

    if Enum.TooltipDataType.Object ~= nil then
        objectPostCall = true
        TooltipDataProcessor.AddTooltipPostCall(
            Enum.TooltipDataType.Object,
            function(tooltip)
                Guarded(HandleObject, tooltip, true)
            end
        )
    end
else
    GameTooltip:HookScript(
        "OnTooltipSetUnit",
        function(tooltip)
            if tooltip.GetUnit == nil then return end
            local _, unit = tooltip:GetUnit()
            Guarded(HandleUnit, tooltip, false, unit)
        end
    )

    GameTooltip:HookScript(
        "OnTooltipSetItem",
        function(tooltip)
            Guarded(HandleItem, tooltip, false)
        end
    )
end

if not objectPostCall then
    AchievementsUtils:OnGameTooltipShown(
        function(tooltip)
            Guarded(HandleObject, tooltip, false)
        end
    )
end

AchievementsUtils:OnGameTooltipHidden(
    function(tooltip)
        tooltip.auReminder = nil
    end
)

AchievementsUtils:OnOptionChanged(
    "REMINDERS",
    function(value)
        if value ~= true then return end
        AchievementsUtils:BuildIndex()
    end
)
