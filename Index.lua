local _, AchievementsUtils = ...
local CATEGORY_CHUNK = 6
local CRITERIA_CHUNK = 40
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

local function ScanCriteria(entry)
    local id = entry.id
    local num = GetAchievementNumCriteria(id) or 0
    if num <= 0 then return end
    local metaType = AchievementsUtils:GetMetaCriteriaType()
    local wantNames = not entry.completed
    for i = 1, num do
        local criteriaString, criteriaType, _, _, _, _, _, assetID = GetAchievementCriteriaInfo(id, i)
        if criteriaType == metaType and type(assetID) == "number" and assetID > 0 then
            local list = index.requiredBy[assetID]
            if list == nil then
                list = {}
                index.requiredBy[assetID] = list
            end

            tinsert(list, id)
        elseif wantNames then
            AddCriteriaName(entry, criteriaString, i)
        end

        if wantNames then
            local duration = select(12, GetAchievementCriteriaInfo(id, i))
            if type(duration) == "number" and duration > 0 and entry.timed ~= true then
                entry.timed = true
                tinsert(index.timed, id)
            end
        end
    end
end

local function AddAchievement(id, categoryID, categoryName)
    if index.byId[id] then return end
    local ach = AchievementsUtils:GetAchievement(id)
    if ach == nil then return end
    local entry = {
        ["id"] = ach.id,
        ["name"] = ach.name,
        ["lname"] = string.lower(ach.name),
        ["ldesc"] = string.lower(ach.description or ""),
        ["lreward"] = string.lower(ach.reward or ""),
        ["points"] = ach.points,
        ["icon"] = ach.icon,
        ["completed"] = ach.completed,
        ["category"] = categoryID,
        ["categoryName"] = categoryName or ""
    }

    index.byId[entry.id] = entry
    tinsert(index.list, entry)
    index.count = index.count + 1
end

local function StepCategories()
    for _ = 1, CATEGORY_CHUNK do
        build.catPos = build.catPos + 1
        local categoryID = build.categories[build.catPos]
        if categoryID == nil then return true end
        local categoryName = GetCategoryInfo(categoryID)
        index.categories[categoryID] = categoryName
        local num = GetCategoryNumAchievements(categoryID) or 0
        for i = 1, num do
            local id = GetAchievementInfo(categoryID, i)
            if type(id) == "number" then AddAchievement(id, categoryID, categoryName) end
        end
    end

    return false
end

local function StepCriteria()
    for _ = 1, CRITERIA_CHUNK do
        build.critPos = build.critPos + 1
        local entry = index.list[build.critPos]
        if entry == nil then return true end
        ScanCriteria(entry)
    end

    return false
end

local function Tick()
    if build == nil then return end
    if not index.ready then
        if StepCategories() then index.ready = true end
        C_Timer.After(0, Tick)

        return
    end

    if index.criteriaWanted and not index.criteriaReady then
        if StepCriteria() then
            index.criteriaReady = true
        else
            C_Timer.After(0, Tick)

            return
        end
    end

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
                ["critPos"] = 0
            }

            C_Timer.After(0, Tick)

            return true
        end

        return true
    end

    index = NewIndex()
    index.criteriaWanted = NeedsCriteria()
    build = {
        ["categories"] = {GetCategoryList()},
        ["catPos"] = 0,
        ["critPos"] = 0
    }

    C_Timer.After(0, Tick)

    return true
end

function AchievementsUtils:GetIndex()
    if index == nil then AchievementsUtils:BuildIndex() end

    return index
end

function AchievementsUtils:IsIndexReady()
    return index ~= nil and index.ready
end

function AchievementsUtils:IsCriteriaIndexReady()
    return index ~= nil and index.criteriaReady
end

function AchievementsUtils:GetIndexStatus()
    if not AchievementsUtils:HasAchievementAPI() then return AchievementsUtils:Trans("LID_INDEXUNAVAILABLE") end
    if index == nil then return AchievementsUtils:Trans("LID_INDEXIDLE") end
    if not index.ready then return AchievementsUtils:Trans("LID_INDEXBUILDING", nil, index.count) end
    if index.criteriaWanted and not index.criteriaReady then return AchievementsUtils:Trans("LID_INDEXCRITERIA", nil, index.count) end

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

function AchievementsUtils:FindInProgress(maxResults)
    local results = {}
    if index == nil or not index.ready then return results end
    maxResults = maxResults or 40
    for _, entry in ipairs(index.list) do
        if not entry.completed then
            local done, total = AchievementsUtils:GetCriteriaProgress(entry.id)
            if total > 1 and done > 0 and done < total then
                entry.progressDone = done
                entry.progressTotal = total
                tinsert(results, entry)
                if #results >= maxResults then break end
            end
        end
    end

    return results
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
