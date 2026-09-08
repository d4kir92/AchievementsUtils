local _, AchievementsUtils = ...
local BUILD_BUDGET = {
    ["count"] = 3000,
    ["time"] = 8
}

local CRITERIA_BUDGET = {
    ["count"] = 1500,
    ["time"] = 8
}

local BUILD_TARGET = 1
local COMBAT_RETRY_DELAY = 1

local BUILD_DELAY = 0
local MAX_CRITERIA_MATCHES = 6
local index = nil
local build = nil

local function NewIndex()
    return {
        ["list"] = {},
        ["byId"] = {},
        ["categories"] = {},
        ["requiredBy"] = {},
        ["criteriaNames"] = {},
        ["timed"] = {},
        ["ready"] = false,
        ["criteriaReady"] = false,
        ["criteriaWanted"] = false,
        ["count"] = 0,
        ["criteriaCount"] = 0
    }
end

local function NeedsCriteria()
    if AchievementsUtils:IsEnabled("REMINDERS") then return true end
    if AchievementsUtils:IsEnabled("TTREQUIREDBY") then return true end
    if AchievementsUtils:IsEnabled("TABRELATED") then return true end
    if AchievementsUtils:IsEnabled("TABSUGGESTIONS") then return true end
    if AchievementsUtils:IsEnabled("AUTOTRACKTIMED") then return true end

    return false
end

local function AddCriteriaName(entry, name, criteriaIndex)
    if name == nil or name == "" then return end
    local key = string.lower(name)
    local list = index.criteriaNames[key]
    if list == nil then
        list = {}
        index.criteriaNames[key] = list
    end

    if #list >= MAX_CRITERIA_MATCHES then return end
    tinsert(
        list,
        {
            ["id"] = entry.id,
            ["index"] = criteriaIndex
        }
    )

    index.criteriaCount = index.criteriaCount + 1
end

local function Clock()
    if type(debugprofilestop) ~= "function" then return nil end

    return debugprofilestop()
end

local function Expired(clock, limit)
    if clock == nil or limit == nil then return false end

    return debugprofilestop() - clock >= limit
end

local function TimeLimit(base)
    if build == nil or build.started == nil or type(GetTime) ~= "function" then return base end
    if GetTime() - build.started >= BUILD_TARGET then return nil end

    return base
end

local function ScanCriteria(entry, metaType)
    local id = entry.id
    local num = GetAchievementNumCriteria(id) or 0
    if num <= 0 then return end
    local wantNames = not entry.completed
    for i = 1, num do
        local criteriaString, criteriaType, _, _, _, _, _, assetID, _, _, _, duration = GetAchievementCriteriaInfo(id, i)
        if criteriaType == metaType and type(assetID) == "number" and assetID > 0 then
            entry.isMeta = true
            local list = index.requiredBy[assetID]
            if list == nil then
                list = {}
                index.requiredBy[assetID] = list
            end

            tinsert(list, id)
        elseif wantNames then
            AddCriteriaName(entry, criteriaString, i)
        end

        if wantNames and entry.timed ~= true and type(duration) == "number" and duration > 0 then
            entry.timed = true
            tinsert(index.timed, id)
        end
    end
end

local function AddAchievement(id, categoryID, categoryName, name, points, completed, description, icon, reward)
    if index.byId[id] then return end
    if name == nil then return end
    local entry = {
        ["id"] = id,
        ["name"] = name,
        ["lname"] = string.lower(name),
        ["ldesc"] = string.lower(description or ""),
        ["lreward"] = string.lower(reward or ""),
        ["points"] = points or 0,
        ["icon"] = icon,
        ["completed"] = completed == true,
        ["category"] = categoryID,
        ["categoryName"] = categoryName or "",
        ["lcategory"] = string.lower(categoryName or "")
    }

    index.byId[id] = entry
    tinsert(index.list, entry)
    index.count = index.count + 1
end

local function StepCategories()
    local clock = Clock()
    local limit = TimeLimit(BUILD_BUDGET.time)
    local processed = 0
    while processed < BUILD_BUDGET.count do
        local categoryID = build.categories[build.catPos + 1]
        if categoryID == nil then return true end
        if type(categoryID) ~= "number" then
            build.catPos = build.catPos + 1
            build.achTotal = nil
        elseif build.achTotal == nil then
            build.catName = GetCategoryInfo(categoryID)
            index.categories[categoryID] = build.catName
            build.achTotal = GetCategoryNumAchievements(categoryID) or 0
            build.achPos = 0
        elseif build.achPos >= build.achTotal then
            build.catPos = build.catPos + 1
            build.achTotal = nil
        else
            build.achPos = build.achPos + 1
            local id, name, points, completed, _, _, _, description, _, icon, reward = GetAchievementInfo(categoryID, build.achPos)
            if type(id) == "number" then AddAchievement(id, categoryID, build.catName, name, points, completed, description, icon, reward) end
            processed = processed + 1
            if Expired(clock, limit) then return false end
        end
    end

    return false
end

local function StepCriteria()
    local clock = Clock()
    local limit = TimeLimit(CRITERIA_BUDGET.time)
    local metaType = AchievementsUtils:GetMetaCriteriaType()
    local processed = 0
    while processed < CRITERIA_BUDGET.count do
        build.critPos = build.critPos + 1
        local entry = index.list[build.critPos]
        if entry == nil then return true end
        ScanCriteria(entry, metaType)
        processed = processed + 1
        if Expired(clock, limit) then return false end
    end

    return false
end

local function Tick()
    if build == nil then return end
    if type(InCombatLockdown) == "function" and InCombatLockdown() then
        build.combat = true
        if build.pausedAt == nil and type(GetTime) == "function" then build.pausedAt = GetTime() end
        C_Timer.After(COMBAT_RETRY_DELAY, Tick)

        return
    end

    build.combat = nil
    if build.pausedAt then
        if build.started then build.started = build.started + (GetTime() - build.pausedAt) end
        build.pausedAt = nil
    end

    if not index.ready then
        if StepCategories() then index.ready = true end
        C_Timer.After(BUILD_DELAY, Tick)

        return
    end

    if index.criteriaWanted and not index.criteriaReady then
        if StepCriteria() then
            index.criteriaReady = true
        else
            C_Timer.After(BUILD_DELAY, Tick)

            return
        end
    end

    if build.started and type(GetTime) == "function" then index.duration = GetTime() - build.started end
    build = nil
end

function AchievementsUtils:BuildIndex(force)
    if not AchievementsUtils:HasAchievementAPI() then return false end
    if build ~= nil and not force then return false end
    if index ~= nil and not force then
        if index.criteriaWanted or not NeedsCriteria() then return false end
        index.criteriaWanted = true
        if index.ready then
            build = build or {
                ["categories"] = {},
                ["catPos"] = 0,
                ["critPos"] = 0,
                ["started"] = GetTime and GetTime() or nil
            }

            C_Timer.After(BUILD_DELAY, Tick)

            return true
        end

        return true
    end

    local categories = GetCategoryList()
    if type(categories) ~= "table" then categories = {} end
    index = NewIndex()
    index.criteriaWanted = NeedsCriteria()
    build = {
        ["categories"] = categories,
        ["catPos"] = 0,
        ["critPos"] = 0,
        ["started"] = GetTime and GetTime() or nil
    }

    C_Timer.After(BUILD_DELAY, Tick)

    return true
end

function AchievementsUtils:GetIndex()
    if index == nil then AchievementsUtils:BuildIndex() end

    return index
end

function AchievementsUtils:IsIndexReady()
    return index ~= nil and index.ready
end

function AchievementsUtils:IsIndexBuilding()
    return build ~= nil
end

function AchievementsUtils:IsCriteriaIndexReady()
    return index ~= nil and index.criteriaReady
end

function AchievementsUtils:GetIndexStatus()
    if not AchievementsUtils:HasAchievementAPI() then return AchievementsUtils:Trans("LID_INDEXUNAVAILABLE") end
    if index == nil then return AchievementsUtils:Trans("LID_INDEXIDLE") end
    if build and build.combat then return AchievementsUtils:Trans("LID_INDEXCOMBAT") end
    if not index.ready then return AchievementsUtils:Trans("LID_INDEXBUILDING", nil, index.count) end
    if index.criteriaWanted and not index.criteriaReady then
        local pos = 0
        if build then pos = build.critPos or 0 end

        return AchievementsUtils:Trans("LID_INDEXCRITERIA", nil, format("%d/%d", pos, index.count))
    end

    if index.duration then return AchievementsUtils:Trans("LID_INDEXREADY", nil, format("%d, %.1fs", index.count, index.duration)) end

    return AchievementsUtils:Trans("LID_INDEXREADY", nil, index.count)
end

function AchievementsUtils:GetEntry(id)
    if index == nil then return nil end

    return index.byId[id]
end

function AchievementsUtils:GetRequiredBy(id)
    if index == nil or not index.criteriaReady then return nil end

    return index.requiredBy[id]
end

function AchievementsUtils:GetTimedAchievements()
    if index == nil then return nil end

    return index.timed
end

function AchievementsUtils:FindByCriteriaName(name)
    if name == nil or name == "" then return nil end
    if index == nil or not index.criteriaReady then return nil end

    return index.criteriaNames[string.lower(name)]
end

local function SortResults(a, b)
    if a.completed ~= b.completed then return b.completed end
    if a.points ~= b.points then return a.points > b.points end

    return a.name < b.name
end

local function SortOpen(a, b)
    local aStarted = (a.progressDone or 0) > 0
    local bStarted = (b.progressDone or 0) > 0
    if aStarted ~= bStarted then return aStarted end
    if a.points ~= b.points then return a.points > b.points end

    return a.name < b.name
end

function AchievementsUtils:SearchAchievements(text, maxResults)
    local results = {}
    if index == nil or not index.ready then return results end
    text = string.lower(strtrim(text or ""))
    if text == "" then return results end
    maxResults = maxResults or 300
    local asNumber = tonumber(text)
    for _, entry in ipairs(index.list) do
        local match = false
        if asNumber and entry.id == asNumber then
            match = true
        elseif string.find(entry.lname, text, 1, true) then
            match = true
        elseif string.find(entry.ldesc, text, 1, true) then
            match = true
        elseif entry.lreward ~= "" and string.find(entry.lreward, text, 1, true) then
            match = true
        end

        if match then
            tinsert(results, entry)
            if #results >= maxResults then break end
        end
    end

    table.sort(results, SortResults)

    return results
end

function AchievementsUtils:FindZoneAchievements(zoneName, maxResults)
    local results = {}
    if index == nil or not index.ready then return results end
    if zoneName == nil or zoneName == "" then return results end
    local needle = string.lower(zoneName)
    maxResults = maxResults or 40
    for _, entry in ipairs(index.list) do
        if not entry.completed and string.find(entry.lname, needle, 1, true) then
            tinsert(results, entry)
            if #results >= maxResults then break end
        end
    end

    table.sort(results, SortResults)

    return results
end

function AchievementsUtils:GetIndexCount()
    if index == nil then return 0 end

    return index.count or 0
end

function AchievementsUtils:ScanOpenAchievements(cursor, budget, match, results, maxResults)
    cursor = cursor or 0
    if index == nil or not index.ready then return cursor, true end
    local scanned = 0
    local checked = 0
    local clock = nil
    if budget.time and type(debugprofilestop) == "function" then clock = debugprofilestop() end
    while scanned < budget.scan and checked < budget.check do
        cursor = cursor + 1
        local entry = index.list[cursor]
        if entry == nil then return cursor, true end
        scanned = scanned + 1
        if not entry.completed and (match == nil or match(entry)) then
            checked = checked + 1
            local done, total = AchievementsUtils:GetCriteriaProgress(entry.id)
            entry.progressDone = done
            entry.progressTotal = total
            tinsert(results, entry)
            if #results >= maxResults then return cursor, true end
        end

        if clock and debugprofilestop() - clock >= budget.time then break end
    end

    return cursor, false
end

function AchievementsUtils:SortOpenResults(results)
    table.sort(results, SortOpen)
end

function AchievementsUtils:GetExpansionName()
    if type(GetExpansionLevel) ~= "function" then return nil end
    local level = GetExpansionLevel()
    if type(level) ~= "number" then return nil end
    local name = _G["EXPANSION_NAME" .. level]
    if type(name) ~= "string" or name == "" then return nil end

    return name
end

function AchievementsUtils:FindCategoryAchievements(categoryID, onlyOpen, maxResults)
    local results = {}
    if index == nil or not index.ready then return results end
    maxResults = maxResults or 60
    for _, entry in ipairs(index.list) do
        if entry.category == categoryID and (not onlyOpen or not entry.completed) then
            tinsert(results, entry)
            if #results >= maxResults then break end
        end
    end

    table.sort(results, SortResults)

    return results
end

function AchievementsUtils:GetCategoryName(categoryID)
    if index == nil then return nil end

    return index.categories[categoryID]
end

function AchievementsUtils:FindCategoryByName(name)
    if index == nil or not index.ready then return nil end
    if name == nil or name == "" then return nil end
    local needle = string.lower(name)
    for categoryID, categoryName in pairs(index.categories) do
        if categoryName and string.lower(categoryName) == needle then return categoryID end
    end

    return nil
end

AchievementsUtils:AddEvent(
    "ACHIEVEMENT_EARNED",
    function(event, id)
        if index == nil then return end
        local entry = index.byId[id]
        if entry then entry.completed = true end
    end
)

AchievementsUtils:OnAchievementUIReady(
    function()
        if type(AchievementFrame) ~= "table" then return end
        AchievementFrame:HookScript(
            "OnShow",
            function()
                AchievementsUtils:BuildIndex()
            end
        )

        if AchievementFrame:IsShown() then AchievementsUtils:BuildIndex() end
    end
)
