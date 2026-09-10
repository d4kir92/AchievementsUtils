local _, AchievementsUtils = ...
local CACHE_VERSION = 1
local CACHE_KEY = "INDEXCACHE"
local BUILD_CHUNK = 300
local CRITERIA_CHUNK = 150
local RESTORE_CHUNK = 400
local COMBAT_RETRY_DELAY = 1
local BUILD_DELAY = 0.025
local STEP_BUDGET = 7
local MAX_CRITERIA_MATCHES = 10
local FIELD_SEPARATOR = "\30"
local index = nil
local build = nil
local searchCache = nil

local function NewIndex()
    return {
        ["list"] = {},
        ["byId"] = {},
        ["byCategory"] = {},
        ["categories"] = {},
        ["requiredBy"] = {},
        ["criteriaNames"] = {},
        ["timed"] = {},
        ["ready"] = false,
        ["criteriaReady"] = false,
        ["criteriaOpenReady"] = false,
        ["criteriaWanted"] = false,
        ["metaFromCache"] = false,
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

local function CacheKey()
    local version, buildNr = GetBuildInfo()
    local locale = "enUS"
    if type(GetLocale) == "function" then locale = GetLocale() end

    return format("%s-%s-%s-%d", tostring(version), tostring(buildNr), tostring(locale), CACHE_VERSION)
end

local function LoadCache()
    local cache = AchievementsUtils:GV(AchievementsUtils:GetDB(), CACHE_KEY, nil)
    if type(cache) ~= "table" then return nil end
    if cache.key ~= CacheKey() then return nil end
    if type(cache.ids) ~= "table" or type(cache.cats) ~= "table" then return nil end
    if #cache.ids <= 0 then return nil end

    return cache
end

local function SaveCache()
    local ids = {}
    local cats = {}
    for i = 1, #index.list do
        local entry = index.list[i]
        ids[i] = entry.id
        cats[i] = entry.category
    end

    AchievementsUtils:SV(
        AchievementsUtils:GetDB(),
        CACHE_KEY,
        {
            ["key"] = CacheKey(),
            ["ids"] = ids,
            ["cats"] = cats,
            ["catNames"] = index.categories,
            ["crit"] = index.criteriaReady == true,
            ["meta"] = index.requiredBy,
            ["timed"] = index.timed,
            ["names"] = index.criteriaNames,
            ["count"] = index.criteriaCount
        }
    )
end

local function ClearCache()
    AchievementsUtils:SV(AchievementsUtils:GetDB(), CACHE_KEY, nil)
end

local function AddCriteriaName(entry, name, criteriaIndex)
    if name == nil or name == "" then return end
    local key = string.lower(name)
    local list = index.criteriaNames[key]
    if list == nil then
        list = {}
        index.criteriaNames[key] = list
    end

    if #list >= MAX_CRITERIA_MATCHES * 2 then return end
    list[#list + 1] = entry.id
    list[#list + 1] = criteriaIndex
    index.criteriaCount = index.criteriaCount + 1
end

local function Percent(done, total)
    if total == nil or total <= 0 then return "0%" end
    local value = math.floor((done or 0) / total * 100)
    if value < 0 then value = 0 end
    if value > 100 then value = 100 end

    return format("%d%%", value)
end

local function Clock()
    if type(debugprofilestop) ~= "function" then return nil end

    return debugprofilestop()
end

local function Expired(clock, limit)
    if clock == nil or limit == nil then return false end

    return debugprofilestop() - clock >= limit
end

local function ScanCriteria(entry, metaType)
    local id = entry.id
    local num = GetAchievementNumCriteria(id) or 0
    if num <= 0 then return end
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
        else
            AddCriteriaName(entry, criteriaString, i)
        end

        if entry.timed ~= true and type(duration) == "number" and duration > 0 then
            entry.timed = true
            tinsert(index.timed, id)
        end
    end
end

local function AddAchievement(id, categoryID, categoryName, name, points, completed, description, icon, reward)
    if index.byId[id] then return end
    if name == nil then return end
    local lname = string.lower(name)
    local hay = lname
    if description ~= nil and description ~= "" then hay = lname .. FIELD_SEPARATOR .. string.lower(description) end
    local entry = {
        ["id"] = id,
        ["name"] = name,
        ["lname"] = lname,
        ["hay"] = hay,
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
    local bucket = index.byCategory[categoryID]
    if bucket == nil then
        bucket = {}
        index.byCategory[categoryID] = bucket
    end

    tinsert(bucket, entry)
    index.count = index.count + 1
end

local function StepCategories()
    local processed = 0
    local clock = Clock()
    while processed < BUILD_CHUNK do
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
            build.done = build.done + 1
            if Expired(clock, STEP_BUDGET) then break end
        end
    end

    return false
end

local function StepRestore()
    local cache = build.cache
    local processed = 0
    local clock = Clock()
    while processed < RESTORE_CHUNK do
        build.restorePos = build.restorePos + 1
        local id = cache.ids[build.restorePos]
        if id == nil then return true end
        local categoryID = cache.cats[build.restorePos]
        local _, name, points, completed, _, _, _, description, _, icon, reward = GetAchievementInfo(id)
        if name ~= nil then AddAchievement(id, categoryID, index.categories[categoryID], name, points, completed, description, icon, reward) end
        processed = processed + 1
        build.done = build.restorePos
        if Expired(clock, STEP_BUDGET) then break end
    end

    return false
end

local function FinishRestore()
    local cache = build.cache
    if cache.crit ~= true or type(cache.names) ~= "table" then return end
    if type(cache.meta) == "table" then
        index.requiredBy = cache.meta
        for _, list in pairs(index.requiredBy) do
            for _, parentID in ipairs(list) do
                local entry = index.byId[parentID]
                if entry then entry.isMeta = true end
            end
        end
    end

    if type(cache.timed) == "table" then
        index.timed = cache.timed
        for _, id in ipairs(index.timed) do
            local entry = index.byId[id]
            if entry then entry.timed = true end
        end
    end

    index.criteriaNames = cache.names
    index.criteriaCount = cache.count or 0
    index.criteriaReady = true
    index.criteriaOpenReady = true
    index.metaFromCache = true
end

local function StepCriteria()
    local metaType = AchievementsUtils:GetMetaCriteriaType()
    local processed = 0
    local clock = Clock()
    while processed < CRITERIA_CHUNK do
        build.critPos = build.critPos + 1
        local entry = index.list[build.critPos]
        if entry == nil then
            index.criteriaOpenReady = true
            if build.critPass >= 2 then return true end
            build.critPass = 2
            build.critPos = 0
        elseif entry.completed == (build.critPass == 2) then
            ScanCriteria(entry, metaType)
            processed = processed + 1
            if Expired(clock, STEP_BUDGET) then break end
        end
    end

    return false
end

local Tick = nil
local function Schedule(delay)
    local current = build
    C_Timer.After(
        delay,
        function()
            if build ~= current or build == nil then return end
            Tick()
        end
    )
end

Tick = function()
    if build == nil then return end
    if type(InCombatLockdown) == "function" and InCombatLockdown() then
        build.combat = true
        if build.pausedAt == nil and type(GetTime) == "function" then build.pausedAt = GetTime() end
        Schedule(COMBAT_RETRY_DELAY)

        return
    end

    build.combat = nil
    if build.pausedAt then
        if build.started then build.started = build.started + (GetTime() - build.pausedAt) end
        build.pausedAt = nil
    end

    if not index.ready then
        local done = false
        if build.cache then
            done = StepRestore()
        else
            done = StepCategories()
        end

        if done then
            index.ready = true
            if build.cache then FinishRestore() end
        end

        Schedule(BUILD_DELAY)

        return
    end

    if index.criteriaWanted and not index.criteriaReady then
        if StepCriteria() then
            index.criteriaReady = true
        else
            Schedule(BUILD_DELAY)

            return
        end
    end

    if not index.metaFromCache then SaveCache() end
    if build.started and type(GetTime) == "function" then index.duration = GetTime() - build.started end
    build = nil
end

local function CountAchievements(categories)
    local total = 0
    for _, categoryID in ipairs(categories) do
        if type(categoryID) == "number" then total = total + (GetCategoryNumAchievements(categoryID) or 0) end
    end

    return total
end

local function NewBuild(cache)
    return {
        ["categories"] = {},
        ["cache"] = cache,
        ["restorePos"] = 0,
        ["catPos"] = 0,
        ["critPos"] = 0,
        ["critPass"] = 1,
        ["done"] = 0,
        ["total"] = 0,
        ["started"] = GetTime and GetTime() or nil
    }
end

function AchievementsUtils:BuildIndex(force)
    if not AchievementsUtils:HasAchievementAPI() then return false end
    if force then
        ClearCache()
        index = nil
        build = nil
    end

    if index ~= nil then
        if index.criteriaWanted or not NeedsCriteria() then return false end
        index.criteriaWanted = true
        if index.criteriaReady then return true end
        if build == nil and index.ready then
            build = NewBuild(nil)
            Schedule(BUILD_DELAY)
        end

        return true
    end

    if build ~= nil then return false end
    searchCache = nil
    index = NewIndex()
    index.criteriaWanted = NeedsCriteria()
    local cache = LoadCache()
    if cache then
        index.categories = cache.catNames or {}
        build = NewBuild(cache)
        build.total = #cache.ids
    else
        local categories = GetCategoryList()
        if type(categories) ~= "table" then categories = {} end
        build = NewBuild(nil)
        build.categories = categories
        build.total = CountAchievements(categories)
    end

    Schedule(BUILD_DELAY)

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

function AchievementsUtils:IsOpenCriteriaReady()
    if index == nil then return false end

    return index.criteriaReady or index.criteriaOpenReady == true
end

function AchievementsUtils:GetIndexStatus()
    if not AchievementsUtils:HasAchievementAPI() then return AchievementsUtils:Trans("LID_INDEXUNAVAILABLE") end
    if index == nil then return AchievementsUtils:Trans("LID_INDEXIDLE") end
    if build and build.combat then return AchievementsUtils:Trans("LID_INDEXCOMBAT") end
    if not index.ready then
        if build == nil or build.total == nil or build.total <= 0 then return AchievementsUtils:Trans("LID_INDEXBUILDING", nil, index.count) end

        return AchievementsUtils:Trans("LID_INDEXBUILDING", nil, Percent(build.done, build.total))
    end

    if index.criteriaWanted and not index.criteriaReady then
        local done = 0
        local total = 0
        if build and index.count > 0 then
            done = ((build.critPass or 1) - 1) * index.count + (build.critPos or 0)
            total = index.count * 2
        end

        return AchievementsUtils:Trans("LID_INDEXCRITERIA", nil, Percent(done, total))
    end

    if index.duration then return AchievementsUtils:Trans("LID_INDEXREADY", nil, format("%d, %.1fs", index.count, index.duration)) end

    return AchievementsUtils:Trans("LID_INDEXREADY", nil, index.count)
end

function AchievementsUtils:GetEntry(id)
    if index == nil then return nil end

    return index.byId[id]
end

function AchievementsUtils:GetRequiredBy(id)
    if index == nil or not index.ready then return nil end

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

function AchievementsUtils:EntryMatches(entry, needle)
    if string.find(entry.hay, needle, 1, true) then return true end

    return false
end

function AchievementsUtils:SearchAchievements(text, maxResults)
    local results = {}
    if index == nil or not index.ready then return results end
    text = string.lower(strtrim(text or ""))
    if text == "" then
        searchCache = nil

        return results
    end

    maxResults = maxResults or 300
    local source = index.list
    local cache = searchCache
    if cache and cache.max == maxResults and not cache.capped then
        local len = string.len(cache.text)
        if string.len(text) > len and string.sub(text, 1, len) == cache.text then source = cache.list end
    end

    local exact = nil
    local asNumber = tonumber(text)
    if asNumber then
        exact = index.byId[asNumber]
        if exact then tinsert(results, exact) end
    end

    for i = 1, #source do
        local entry = source[i]
        if entry ~= exact and (string.find(entry.hay, text, 1, true) or (entry.lreward ~= "" and string.find(entry.lreward, text, 1, true))) then
            tinsert(results, entry)
            if #results >= maxResults then break end
        end
    end

    searchCache = {
        ["text"] = text,
        ["list"] = results,
        ["max"] = maxResults,
        ["capped"] = #results >= maxResults
    }

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

function AchievementsUtils:ScanSections(cursor, budget, sections, maxResults)
    cursor = cursor or 0
    if index == nil or not index.ready then return cursor, true end
    local total = #index.list
    local count = #sections
    local open = 0
    for i = 1, count do
        if #sections[i].found < maxResults then open = open + 1 end
    end

    if open <= 0 then return cursor, true end
    local scanned = 0
    local checked = 0
    local clock = nil
    if budget.time then clock = Clock() end
    while scanned < budget.scan and checked < budget.check do
        cursor = cursor + 1
        if cursor > total then return cursor, true end
        local entry = index.list[cursor]
        scanned = scanned + 1
        if not entry.completed then
            local hit = false
            for i = 1, count do
                local section = sections[i]
                local found = section.found
                local size = #found
                if size < maxResults and section.match(entry) then
                    if not hit then
                        hit = true
                        checked = checked + 1
                        local done, criteria = AchievementsUtils:GetCriteriaProgress(entry.id)
                        entry.progressDone = done
                        entry.progressTotal = criteria
                    end

                    found[size + 1] = entry
                    if size + 1 >= maxResults then
                        open = open - 1
                        if open <= 0 then return cursor, true end
                    end
                end
            end
        end

        if Expired(clock, budget.time) then break end
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
    local bucket = index.byCategory[categoryID]
    if bucket == nil then return results end
    for _, entry in ipairs(bucket) do
        if not onlyOpen or not entry.completed then
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
