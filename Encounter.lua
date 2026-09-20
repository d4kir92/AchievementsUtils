local _, AchievementsUtils = ...
local FRAME_WIDTH = 360
local ROW_HEIGHT = 18
local HEADER_HEIGHT = 22
local PADDING = 8
local ICON_SIZE = 14
local RESULT_DELAY = 2
local TICK_DELAY = 1
local MAX_ROWS = 12
local DEFAULT_Y = -160
local BOSS_UNITS = 8
local CATEGORY_MAX = 300
local COLOR_OPEN = {1, 0.82, 0}
local COLOR_DONE = {0.2, 1, 0.2}
local COLOR_FAIL = {1, 0.3, 0.3}
local COLOR_INFO = {0.7, 0.7, 0.7}
local frame = nil
local header = nil
local rows = {}
local state = nil
local token = 0
local hasEncounterEvents = nil

local function HasEncounterEvents()
    if hasEncounterEvents ~= nil then return hasEncounterEvents end
    hasEncounterEvents = false
    if C_EventUtils and C_EventUtils.IsEventValid then hasEncounterEvents = C_EventUtils.IsEventValid("ENCOUNTER_START") == true end

    return hasEncounterEvents
end

local function SavePosition()
    if frame == nil then return end
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    if point == nil then return end
    AchievementsUtils:SV(
        AchievementsUtils:GetDB(),
        "ENCOUNTERPOSITION",
        {
            ["point"] = point,
            ["relativePoint"] = relativePoint,
            ["x"] = x,
            ["y"] = y
        }
    )
end

local function ApplyPosition()
    if frame == nil then return end
    local pos = AchievementsUtils:GV(AchievementsUtils:GetDB(), "ENCOUNTERPOSITION", nil)
    frame:ClearAllPoints()
    if type(pos) == "table" and pos.point ~= nil then
        frame:SetPoint(pos.point, UIParent, pos.relativePoint or pos.point, pos.x or 0, pos.y or 0)

        return
    end

    frame:SetPoint("TOP", UIParent, "TOP", 0, DEFAULT_Y)
end

local function ApplyScale()
    if frame == nil then return end
    local scale = tonumber(AchievementsUtils:GetOption("ENCOUNTERSCALE")) or 1
    if scale < 0.5 then scale = 0.5 end
    frame:SetScale(scale)
end

local function ApplyMovable()
    if frame == nil then return end
    local movable = AchievementsUtils:IsEnabled("ENCOUNTERMOVABLE")
    frame:EnableMouse(movable)
    if movable then
        frame.bg:SetVertexColor(0.1, 0.1, 0.3, 0.8)
    else
        frame.bg:SetVertexColor(0, 0, 0, 0.45)
    end
end

function AchievementsUtils:ResetEncounterPosition()
    AchievementsUtils:SV(AchievementsUtils:GetDB(), "ENCOUNTERPOSITION", nil)
    ApplyPosition()
end

local function RowTop(index)
    return HEADER_HEIGHT + PADDING + (index - 1) * ROW_HEIGHT
end

local function CreateRow(index)
    local row = CreateFrame("Frame", "AchievementsUtilsEncounterRow" .. index, frame)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, -RowTop(index))
    row:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PADDING, -RowTop(index))
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ICON_SIZE, ICON_SIZE)
    row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row.right = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.right:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.right:SetJustifyH("RIGHT")
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.text:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
    row.text:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
    row.text:SetJustifyH("LEFT")
    if row.text.SetWordWrap then row.text:SetWordWrap(false) end

    return row
end

local function CreateDisplay()
    if frame ~= nil then return end
    frame = CreateFrame("Frame", "AchievementsUtilsEncounterFrame", UIParent)
    frame:SetWidth(FRAME_WIDTH)
    frame:SetHeight(HEADER_HEIGHT + PADDING * 2)
    frame:SetFrameStrata("MEDIUM")
    frame:SetMovable(true)
    AchievementsUtils:SetClampedToScreen(frame, true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript(
        "OnDragStart",
        function(sel)
            if not AchievementsUtils:IsEnabled("ENCOUNTERMOVABLE") then return end
            sel:StartMoving()
        end
    )

    frame:SetScript(
        "OnDragStop",
        function(sel)
            sel:StopMovingOrSizing()
            SavePosition()
        end
    )

    frame.bg = frame:CreateTexture(nil, "BACKGROUND")
    frame.bg:SetAllPoints(frame)
    if frame.bg.SetColorTexture then
        frame.bg:SetColorTexture(1, 1, 1, 1)
    else
        frame.bg:SetTexture(1, 1, 1, 1)
    end

    header = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, -PADDING)
    header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PADDING, -PADDING)
    header:SetJustifyH("CENTER")
    frame:Hide()
    ApplyPosition()
    ApplyScale()
    ApplyMovable()
end

local function InstanceCategory()
    if type(GetInstanceInfo) ~= "function" then return nil end
    local name = GetInstanceInfo()
    if type(name) ~= "string" or name == "" then return nil end

    return AchievementsUtils:FindCategoryByName(name)
end

local function SortEntries(a, b)
    if a.completed ~= b.completed then return b.completed end
    if a.points ~= b.points then return a.points > b.points end

    return a.name < b.name
end

local function Collect(bossName)
    local entries = {}
    local seen = {}
    local showDone = AchievementsUtils:IsEnabled("ENCOUNTERDONE")
    local function Add(id)
        if type(id) ~= "number" or seen[id] then return end
        local entry = AchievementsUtils:GetEntry(id)
        if entry == nil then return end
        if entry.completed and not showDone then return end
        seen[id] = true
        tinsert(entries, entry)
    end

    local matches = AchievementsUtils:FindByCriteriaName(bossName)
    if type(matches) == "table" then
        for i = 1, #matches, 2 do
            Add(matches[i])
        end
    end

    local categoryID = InstanceCategory()
    if categoryID then
        local needle = string.lower(bossName)
        for _, entry in ipairs(AchievementsUtils:FindCategoryAchievements(categoryID, not showDone, CATEGORY_MAX)) do
            if AchievementsUtils:EntryMatches(entry, needle) then Add(entry.id) end
        end
    end

    table.sort(entries, SortEntries)
    local max = math.floor(tonumber(AchievementsUtils:GetOption("ENCOUNTERMAX")) or 5)
    if max > MAX_ROWS then max = MAX_ROWS end
    local list = {}
    for i = 1, math.min(#entries, max) do
        local entry = entries[i]
        list[i] = {
            ["id"] = entry.id,
            ["name"] = entry.name,
            ["icon"] = entry.icon,
            ["done"] = entry.completed == true,
            ["wasDone"] = entry.completed == true
        }
    end

    return list
end

local function ProgressText(id)
    local num = GetAchievementNumCriteria(id) or 0
    if num <= 0 then return nil end
    if num == 1 then
        local _, _, _, quantity, reqQuantity = GetAchievementCriteriaInfo(id, 1)
        if type(reqQuantity) == "number" and reqQuantity > 1 then return format("%d/%d", quantity or 0, reqQuantity) end

        return nil
    end

    local done = 0
    for i = 1, num do
        local _, _, completed = GetAchievementCriteriaInfo(id, i)
        if completed then done = done + 1 end
    end

    return format("%d/%d", done, num)
end

local function BuildLines()
    local lines = {}
    if #state.list <= 0 then
        local text = AchievementsUtils:Trans("LID_ENCOUNTERNONE")
        if state.preview then text = AchievementsUtils:Trans("LID_ENCOUNTERDRAG") end
        tinsert(
            lines,
            {
                ["text"] = text,
                ["color"] = COLOR_INFO
            }
        )

        return lines
    end

    local showResult = state.ended and AchievementsUtils:IsEnabled("ENCOUNTERRESULT")
    for _, item in ipairs(state.list) do
        item.done = AchievementsUtils:IsCompleted(item.id)
        local line = {
            ["icon"] = item.icon,
            ["text"] = item.name,
            ["color"] = COLOR_OPEN
        }

        if item.wasDone then
            line.color = COLOR_INFO
        elseif item.done then
            line.color = COLOR_DONE
        end

        if showResult then
            if item.wasDone then
                line.right = AchievementsUtils:Trans("LID_ALREADYDONE")
                line.rightColor = COLOR_INFO
            elseif item.done then
                line.right = AchievementsUtils:Trans("LID_ENCOUNTERSUCCESS")
                line.rightColor = COLOR_DONE
            else
                line.right = AchievementsUtils:Trans("LID_ENCOUNTERFAILED")
                line.rightColor = COLOR_FAIL
                line.color = COLOR_FAIL
            end
        elseif AchievementsUtils:IsEnabled("ENCOUNTERPROGRESS") then
            line.right = ProgressText(item.id)
            line.rightColor = COLOR_INFO
        end

        tinsert(lines, line)
    end

    return lines
end

local function UpdateDisplay()
    if state == nil then return end
    CreateDisplay()
    local lines = BuildLines()
    for i = 1, MAX_ROWS do
        local line = lines[i]
        local row = rows[i]
        if line == nil then
            if row then row:Hide() end
        else
            if row == nil then
                row = CreateRow(i)
                rows[i] = row
            end

            if line.icon then
                row.icon:SetTexture(line.icon)
                row.icon:Show()
            else
                row.icon:Hide()
            end

            local color = line.color or COLOR_OPEN
            row.text:SetText(line.text)
            row.text:SetTextColor(color[1], color[2], color[3])
            local rightColor = line.rightColor or COLOR_INFO
            row.right:SetText(line.right or "")
            row.right:SetTextColor(rightColor[1], rightColor[2], rightColor[3])
            row:Show()
        end
    end

    header:SetText(state.boss)
    if state.ended then
        header:SetTextColor(COLOR_INFO[1], COLOR_INFO[2], COLOR_INFO[3])
    else
        header:SetTextColor(COLOR_OPEN[1], COLOR_OPEN[2], COLOR_OPEN[3])
    end

    frame:SetHeight(HEADER_HEIGHT + PADDING * 2 + #lines * ROW_HEIGHT)
end

local function Schedule(id)
    C_Timer.After(
        TICK_DELAY,
        function()
            if state == nil or state.token ~= id or state.ended then return end
            UpdateDisplay()
            Schedule(id)
        end
    )
end

local function Hide()
    state = nil
    if frame then frame:Hide() end
end

local function ShowPreview()
    if state ~= nil and not state.preview then return end
    CreateDisplay()
    token = token + 1
    state = {
        ["boss"] = AchievementsUtils:Trans("LID_ENCOUNTER"),
        ["list"] = {},
        ["ended"] = false,
        ["preview"] = true,
        ["token"] = token
    }

    ApplyScale()
    ApplyMovable()
    UpdateDisplay()
    frame:Show()
end

local function Start(bossName)
    if not AchievementsUtils:IsEnabled("ENCOUNTER") then return false end
    if type(bossName) ~= "string" or strtrim(bossName) == "" then return false end
    if not AchievementsUtils:IsIndexReady() then
        AchievementsUtils:BuildIndex()

        return false
    end

    CreateDisplay()
    token = token + 1
    state = {
        ["boss"] = bossName,
        ["list"] = Collect(bossName),
        ["ended"] = false,
        ["token"] = token
    }

    ApplyScale()
    ApplyMovable()
    UpdateDisplay()
    frame:Show()
    Schedule(state.token)

    return true
end

local function Stop()
    if state == nil or state.ended or state.preview then return end
    state.ended = true
    local id = state.token
    UpdateDisplay()
    C_Timer.After(
        RESULT_DELAY,
        function()
            if state == nil or state.token ~= id then return end
            UpdateDisplay()
        end
    )

    local delay = tonumber(AchievementsUtils:GetOption("ENCOUNTERHIDE")) or 15
    C_Timer.After(
        delay,
        function()
            if state == nil or state.token ~= id then return end
            Hide()
        end
    )
end

local function GetBossUnitName()
    for i = 1, BOSS_UNITS do
        local name = UnitName("boss" .. i)
        if type(name) == "string" and name ~= "" then return name end
    end

    return nil
end

function AchievementsUtils:TestEncounter(name)
    if not AchievementsUtils:IsEnabled("ENCOUNTER") then
        AchievementsUtils:MSG(AchievementsUtils:Trans("LID_ENCOUNTEROFF"))

        return
    end

    if type(name) ~= "string" or strtrim(name) == "" then name = GetBossUnitName() end
    if type(name) ~= "string" or name == "" then name = UnitName("target") end
    if type(name) ~= "string" or name == "" then
        AchievementsUtils:MSG(AchievementsUtils:Trans("LID_ENCOUNTERNOTARGET"))

        return
    end

    if not Start(name) then AchievementsUtils:MSG(AchievementsUtils:GetIndexStatus()) end
end

AchievementsUtils:AddEvent(
    "ENCOUNTER_START",
    function(event, encounterID, encounterName)
        Start(encounterName)
    end
)

AchievementsUtils:AddEvent(
    "ENCOUNTER_END",
    function()
        Stop()
    end
)

AchievementsUtils:AddEvent(
    "INSTANCE_ENCOUNTER_ENGAGE_UNIT",
    function()
        if HasEncounterEvents() then return end
        local name = GetBossUnitName()
        if name == nil then
            Stop()

            return
        end

        if state and not state.ended and state.boss == name then return end
        Start(name)
    end
)

AchievementsUtils:AddEvent(
    "PLAYER_REGEN_ENABLED",
    function()
        if HasEncounterEvents() then return end
        Stop()
    end
)

AchievementsUtils:AddEvent(
    "ACHIEVEMENT_EARNED",
    function()
        if state == nil then return end
        UpdateDisplay()
    end
)

AchievementsUtils:AddEvent(
    "CRITERIA_UPDATE",
    function()
        if state == nil or state.ended then return end
        UpdateDisplay()
    end
)

AchievementsUtils:AddEvent(
    "PLAYER_ENTERING_WORLD",
    function()
        if state ~= nil and state.preview then return end
        Hide()
    end
)
AchievementsUtils:OnOptionChanged("ENCOUNTER", function(value) if value ~= true then Hide() end end)
AchievementsUtils:OnOptionChanged("ENCOUNTERSCALE", function() ApplyScale() end)
AchievementsUtils:OnOptionChanged(
    "ENCOUNTERMOVABLE",
    function()
        ApplyMovable()
        if AchievementsUtils:IsEnabled("ENCOUNTERMOVABLE") then
            ShowPreview()
        elseif state ~= nil and state.preview then
            Hide()
        end
    end
)
