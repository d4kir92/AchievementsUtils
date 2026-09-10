local _, AchievementsUtils = ...
local ZONE_DELAY = 2
local CRITERIA_THROTTLE = 1
local TRACK_LIMIT = 10
local autoTracked = {}
local zonePending = false
local lastCriteria = 0
local lastZone = nil

local function CountAuto()
    local count = 0
    for _ in pairs(autoTracked) do
        count = count + 1
    end

    return count
end

local function GetMax()
    local value = tonumber(AchievementsUtils:GetOption("AUTOTRACKMAX")) or 3

    return math.floor(value)
end

local function TrackAuto(id)
    if type(id) ~= "number" then return false end
    if not AchievementsUtils:CanTrack() then return false end
    if autoTracked[id] then return false end
    if AchievementsUtils:IsTracked(id) then return false end
    if CountAuto() >= GetMax() then return false end
    if AchievementsUtils:GetTrackedCount() >= TRACK_LIMIT then return false end
    AchievementsUtils:SetTracked(id, true)
    autoTracked[id] = true

    return true
end

local function ReleaseAuto(keep)
    for id in pairs(autoTracked) do
        if keep == nil or keep[id] ~= true then
            AchievementsUtils:SetTracked(id, false)
            autoTracked[id] = nil
        end
    end
end

local function UpdateWatch(keep)
    if not AchievementsUtils:IsEnabled("AUTOTRACKWATCH") then return end
    for _, id in ipairs(AchievementsUtils:GetWatchList()) do
        if not AchievementsUtils:IsCompleted(id) then
            keep[id] = true
            TrackAuto(id)
        end
    end
end

local function UpdateZone()
    zonePending = false
    if not AchievementsUtils:IsEnabled("AUTOTRACK") then return end
    if InCombatLockdown() then return end
    local keep = {}
    if AchievementsUtils:IsEnabled("AUTOTRACKZONE") and AchievementsUtils:IsIndexReady() then
        local zone = GetZoneText()
        if zone and zone ~= "" then
            local list = AchievementsUtils:FindZoneAchievements(zone, 10)
            for _, entry in ipairs(list) do
                local done, total = AchievementsUtils:GetCriteriaProgress(entry.id)
                if total > 0 and done < total then keep[entry.id] = true end
            end
        end
    end

    UpdateWatch(keep)
    ReleaseAuto(keep)
    for id in pairs(keep) do
        TrackAuto(id)
    end
end

local function QueueZoneUpdate()
    if zonePending then return end
    if not AchievementsUtils:CanTrack() then return end
    if not AchievementsUtils:IsEnabled("AUTOTRACK") then return end
    zonePending = true
    C_Timer.After(ZONE_DELAY, UpdateZone)
end

local function CheckTimed()
    if not AchievementsUtils:CanTrack() then return end
    if not AchievementsUtils:IsEnabled("AUTOTRACKTIMED") then return end
    local list = AchievementsUtils:GetTimedAchievements()
    if list == nil then return end
    for _, id in ipairs(list) do
        if not AchievementsUtils:IsCompleted(id) and not AchievementsUtils:IsTracked(id) then
            local num = GetAchievementNumCriteria(id) or 0
            for i = 1, num do
                local duration, elapsed = select(12, GetAchievementCriteriaInfo(id, i))
                if type(duration) == "number" and duration > 0 and type(elapsed) == "number" and elapsed > 0 and elapsed < duration then
                    if TrackAuto(id) then
                        local ach = AchievementsUtils:GetAchievement(id)
                        if ach then AchievementsUtils:MSG(AchievementsUtils:Trans("LID_NOWTRACKING", nil, ach.name)) end
                    end

                    break
                end
            end
        end
    end
end

AchievementsUtils:AddEvent(
    "PLAYER_ENTERING_WORLD",
    function()
        lastZone = GetZoneText()
        QueueZoneUpdate()
    end
)

AchievementsUtils:AddEvent(
    "ZONE_CHANGED_NEW_AREA",
    function()
        local zone = GetZoneText()
        if zone == lastZone then return end
        lastZone = zone
        QueueZoneUpdate()
    end
)

AchievementsUtils:AddEvent(
    "ZONE_CHANGED",
    function()
        local zone = GetZoneText()
        if zone == lastZone then return end
        lastZone = zone
        QueueZoneUpdate()
    end
)

AchievementsUtils:AddEvent(
    "CRITERIA_UPDATE",
    function()
        local now = GetTime()
        if now - lastCriteria < CRITERIA_THROTTLE then return end
        lastCriteria = now
        CheckTimed()
    end
)

AchievementsUtils:AddEvent(
    "ACHIEVEMENT_EARNED",
    function(event, id)
        if autoTracked[id] then autoTracked[id] = nil end
    end
)

AchievementsUtils:OnOptionChanged(
    "AUTOTRACK",
    function(value)
        if value ~= true then
            ReleaseAuto(nil)

            return
        end

        QueueZoneUpdate()
    end
)

AchievementsUtils:OnOptionChanged("AUTOTRACKWATCH", function() QueueZoneUpdate() end)
AchievementsUtils:OnOptionChanged("AUTOTRACKZONE", function() QueueZoneUpdate() end)
AchievementsUtils:OnOptionChanged("WATCHLIST", function() QueueZoneUpdate() end)
