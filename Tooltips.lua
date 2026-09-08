local _, AchievementsUtils = ...
local MAX_PARENT_DEPTH = 8
local CTRL_TIMEOUT = 10
local TRACKER_DELAY = 0.5
local adding = false
local installed = false
local lastCtrlID = nil
local lastCtrlTime = 0
local trackerPending = false

local function IsInAchievementFrame(frame)
    if type(AchievementFrame) ~= "table" then return false end
    local guard = 0
    while frame and guard < 30 do
        if frame == AchievementFrame then return true end
        if frame.GetParent == nil then return false end
        frame = frame:GetParent()
        guard = guard + 1
    end

    return false
end

local function GetOwnerAchievementID(owner)
    if type(owner) ~= "table" then return nil end
    if not IsInAchievementFrame(owner) then return nil end
    local frame = owner
    local guard = 0
    while frame and guard < MAX_PARENT_DEPTH do
        local id = frame.id
        if type(id) ~= "number" then id = frame.achievementID end
        if type(id) == "number" and id > 0 and AchievementsUtils:GetAchievement(id) then return id end
        if frame.GetParent == nil then return nil end
        frame = frame:GetParent()
        guard = guard + 1
    end

    return nil
end

local function AddProgressLines(lines, id, maxLines)
    local done, total = AchievementsUtils:GetCriteriaProgress(id)
    if total <= 0 then return end
    if total > 1 then
        tinsert(
            lines,
            {
                ["left"] = AchievementsUtils:Trans("LID_PROGRESS", nil, format("%d/%d", done, total)),
                ["r"] = 1,
                ["g"] = 0.82,
                ["b"] = 0
            }
        )
    end

    local shown = 0
    for i = 1, total do
        if shown >= maxLines then
            tinsert(
                lines,
                {
                    ["left"] = AchievementsUtils:Trans("LID_ANDMORE", nil, total - i + 1),
                    ["r"] = 0.6,
                    ["g"] = 0.6,
                    ["b"] = 0.6
                }
            )

            break
        end

        local criteriaString, _, completed, quantity, reqQuantity, _, _, _, quantityString = GetAchievementCriteriaInfo(id, i)
        if not completed then
            local left = criteriaString
            if left == nil or left == "" then left = quantityString end
            local right = nil
            if reqQuantity and reqQuantity > 1 then
                right = format("%d/%d", quantity or 0, reqQuantity)
                if left == nil or left == "" then
                    left = quantityString or ""
                    right = nil
                end
            end

            if left and left ~= "" then
                tinsert(
                    lines,
                    {
                        ["left"] = left,
                        ["right"] = right,
                        ["r"] = 1,
                        ["g"] = 1,
                        ["b"] = 1,
                        ["r2"] = 1,
                        ["g2"] = 0.82,
                        ["b2"] = 0
                    }
                )

                shown = shown + 1
            end
        end
    end
end

local function AddAchievementRow(lines, id, prefix)
    local ach = AchievementsUtils:GetAchievement(id)
    if ach == nil then return end
    local color = {0.7, 0.7, 0.7}
    if ach.completed then color = {0.25, 1, 0.25} end
    tinsert(
        lines,
        {
            ["left"] = (prefix or "") .. ach.name,
            ["right"] = tostring(ach.points),
            ["r"] = color[1],
            ["g"] = color[2],
            ["b"] = color[3],
            ["r2"] = 1,
            ["g2"] = 0.82,
            ["b2"] = 0
        }
    )
end

local function AddSeriesLines(lines, id)
    local before, after = AchievementsUtils:GetSeries(id)
    if #before <= 0 and #after <= 0 then return end
    tinsert(
        lines,
        {
            ["left"] = AchievementsUtils:Trans("LID_PARTOFSERIES"),
            ["r"] = 1,
            ["g"] = 0.82,
            ["b"] = 0
        }
    )

    for _, value in ipairs(before) do
        AddAchievementRow(lines, value, "  ")
    end

    local ach = AchievementsUtils:GetAchievement(id)
    if ach then
        tinsert(
            lines,
            {
                ["left"] = "  " .. ach.name,
                ["right"] = tostring(ach.points),
                ["r"] = 1,
                ["g"] = 1,
                ["b"] = 1,
                ["r2"] = 1,
                ["g2"] = 0.82,
                ["b2"] = 0
            }
        )
    end

    for _, value in ipairs(after) do
        AddAchievementRow(lines, value, "  ")
    end
end

local function AddRequiredByLines(lines, id)
    local list = AchievementsUtils:GetRequiredBy(id)
    if list == nil or #list <= 0 then return end
    tinsert(
        lines,
        {
            ["left"] = AchievementsUtils:Trans("LID_REQUIREDBY"),
            ["r"] = 1,
            ["g"] = 0.82,
            ["b"] = 0
        }
    )

    for _, value in ipairs(list) do
        AddAchievementRow(lines, value, "  ")
    end
end

local function BuildLines(id)
    local lines = {}
    local maxLines = tonumber(AchievementsUtils:GetOption("TTMAXLINES")) or 10
    if AchievementsUtils:IsEnabled("TTPROGRESS") then AddProgressLines(lines, id, maxLines) end
    if AchievementsUtils:IsEnabled("TTSERIES") then AddSeriesLines(lines, id) end
    if AchievementsUtils:IsEnabled("TTREQUIREDBY") then AddRequiredByLines(lines, id) end
    if AchievementsUtils:IsEnabled("TABWATCH") and AchievementsUtils:IsWatched(id) then
        tinsert(
            lines,
            {
                ["left"] = AchievementsUtils:Trans("LID_ONWATCHLIST"),
                ["r"] = 0.33,
                ["g"] = 0.82,
                ["b"] = 1
            }
        )
    end

    if AchievementsUtils:IsEnabled("TTID") then
        tinsert(
            lines,
            {
                ["left"] = AchievementsUtils:Trans("LID_ACHIEVEMENTID"),
                ["right"] = tostring(id),
                ["r"] = 0.6,
                ["g"] = 0.6,
                ["b"] = 0.6,
                ["r2"] = 0.6,
                ["g2"] = 0.6,
                ["b2"] = 0.6
            }
        )
    end

    return lines
end

local function Decorate(tooltip, id)
    if adding then return end
    if tooltip == nil or id == nil then return end
    if not AchievementsUtils:IsEnabled("ACHTOOLTIP") then return end
    if tooltip.auAchievement == id then return end
    tooltip.auAchievement = id
    local lines = BuildLines(id)
    if #lines <= 0 then return end
    adding = true
    tooltip:AddLine(" ")
    for _, line in ipairs(lines) do
        if line.right then
            tooltip:AddDoubleLine(line.left, line.right, line.r, line.g, line.b, line.r2, line.g2, line.b2)
        else
            tooltip:AddLine(line.left, line.r, line.g, line.b, true)
        end
    end

    tooltip:Show()
    adding = false
end

local function OnTooltipShow(tooltip)
    if adding then return end
    if tooltip.GetOwner == nil then return end
    local id = GetOwnerAchievementID(tooltip:GetOwner())
    if id == nil then return end
    Decorate(tooltip, id)
end

local function OnTooltipHide(tooltip)
    tooltip.auAchievement = nil
end

local function ShowOwnTooltip(owner, id)
    if adding then return end
    if type(owner) ~= "table" or type(id) ~= "number" then return end
    if not AchievementsUtils:IsEnabled("ACHTOOLTIP") then return end
    local ach = AchievementsUtils:GetAchievement(id)
    if ach == nil then return end
    adding = true
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(AchievementsUtils:ColorByStatus(ach.name, ach.completed), 1, 1, 1)
    if ach.description and ach.description ~= "" then GameTooltip:AddLine(ach.description, 1, 1, 1, true) end
    local lines = BuildLines(id)
    if #lines > 0 then
        GameTooltip:AddLine(" ")
        for _, line in ipairs(lines) do
            if line.right then
                GameTooltip:AddDoubleLine(line.left, line.right, line.r, line.g, line.b, line.r2, line.g2, line.b2)
            else
                GameTooltip:AddLine(line.left, line.r, line.g, line.b, true)
            end
        end
    end

    if AchievementsUtils:IsEnabled("TABWATCH") then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(AchievementsUtils:Trans("LID_RIGHTCLICKWATCH"), 0.6, 0.6, 0.6)
    end

    GameTooltip.auAchievement = id
    GameTooltip:Show()
    adding = false
end

function AchievementsUtils:RefreshAchievementTooltip(owner, id)
    if type(owner) ~= "table" or type(id) ~= "number" then return end
    if GameTooltip.auAchievement ~= id then return end
    GameTooltip.auAchievement = nil
    ShowOwnTooltip(owner, id)
end

local function HideOwnTooltip()
    if GameTooltip.auAchievement == nil then return end
    GameTooltip.auAchievement = nil
    GameTooltip:Hide()
end

local function InstallTooltipHooks()
    if installed then return end
    installed = true
    if EventRegistry and EventRegistry.RegisterCallback then
        EventRegistry:RegisterCallback(
            "AchievementFrameAchievement.OnEnter",
            function(_, button, id)
                if type(id) ~= "number" and type(button) == "table" then id = button.id end
                ShowOwnTooltip(button, id)
            end,
            "AchievementsUtils"
        )

        EventRegistry:RegisterCallback("AchievementFrameAchievement.OnLeave", function() HideOwnTooltip() end, "AchievementsUtils")

        return
    end

    if type(_G["AchievementButton_OnEnter"]) == "function" then
        hooksecurefunc(
            "AchievementButton_OnEnter",
            function(sel)
                if type(sel) ~= "table" then return end
                ShowOwnTooltip(sel, sel.id)
            end
        )
    end

    if type(_G["AchievementButton_OnLeave"]) == "function" then hooksecurefunc("AchievementButton_OnLeave", function() HideOwnTooltip() end) end
end

GameTooltip:HookScript("OnShow", OnTooltipShow)
GameTooltip:HookScript("OnHide", OnTooltipHide)
AchievementsUtils:OnAchievementUIReady(InstallTooltipHooks)

local function GetTrackerBlockID(block)
    if type(block) ~= "table" then return nil end
    local id = block.id
    if type(id) ~= "number" then id = block.achievementID end
    if type(id) ~= "number" then return nil end

    return id
end

local function HookTrackerBlock(block)
    if type(block) ~= "table" then return end
    local target = block.HeaderButton
    if type(target) ~= "table" then target = block end
    if target.auTrackerHooked then return end
    if target.HookScript == nil then return end
    target.auTrackerHooked = true
    target:HookScript(
        "OnEnter",
        function(sel)
            if not AchievementsUtils:IsEnabled("TTTRACKER") then return end
            ShowOwnTooltip(sel, GetTrackerBlockID(block))
        end
    )

    target:HookScript(
        "OnLeave",
        function()
            if not AchievementsUtils:IsEnabled("TTTRACKER") then return end
            HideOwnTooltip()
        end
    )
end

local function HookTrackerModule(module)
    if module.auTrackerModuleHooked then return end
    if type(module.GetBlock) ~= "function" then return end
    if type(module.GetExistingBlock) ~= "function" then return end
    module.auTrackerModuleHooked = true
    hooksecurefunc(
        module,
        "GetBlock",
        function(sel, id, optTemplate)
            HookTrackerBlock(sel:GetExistingBlock(id, optTemplate))
        end
    )
end

local function ScanTrackerModule(module)
    if type(module) ~= "table" then return end
    HookTrackerModule(module)
    local used = module.usedBlocks
    if type(used) ~= "table" then return end
    for _, value in pairs(used) do
        if type(value) == "table" then
            if type(value.id) == "number" then
                HookTrackerBlock(value)
            else
                for _, block in pairs(value) do
                    if type(block) == "table" and type(block.id) == "number" then HookTrackerBlock(block) end
                end
            end
        end
    end
end

local function ScanTracker()
    trackerPending = false
    if not AchievementsUtils:IsEnabled("TTTRACKER") then return end
    ScanTrackerModule(_G["AchievementObjectiveTracker"])
    ScanTrackerModule(_G["ACHIEVEMENT_TRACKER_MODULE"])
end

local function QueueTrackerScan()
    if trackerPending then return end
    if not AchievementsUtils:IsEnabled("TTTRACKER") then return end
    trackerPending = true
    C_Timer.After(TRACKER_DELAY, ScanTracker)
end

AchievementsUtils:AddEvent("PLAYER_ENTERING_WORLD", QueueTrackerScan)
AchievementsUtils:AddEvent("TRACKED_ACHIEVEMENT_LIST_CHANGED", QueueTrackerScan)
AchievementsUtils:AddEvent("TRACKED_ACHIEVEMENT_UPDATE", QueueTrackerScan)
AchievementsUtils:AddEvent("CONTENT_TRACKING_UPDATE", QueueTrackerScan)
AchievementsUtils:OnOptionChanged(
    "TTTRACKER",
    function(value)
        if value ~= true then return end
        QueueTrackerScan()
    end
)

local function GetLinkedCriteria(fields, criteriaIndex)
    if bit == nil then return nil end
    local field = math.floor((criteriaIndex - 1) / 32) + 1
    local value = tonumber(fields[field])
    if value == nil then return nil end
    local offset = (criteriaIndex - 1) % 32

    return bit.band(bit.rshift(value, offset), 1) == 1
end

local function CompareLink(id, parts)
    local ach = AchievementsUtils:GetAchievement(id)
    if ach == nil then return end
    local fields = {parts[8], parts[9], parts[10], parts[11]}
    local completed = parts[4] == "1"
    local num = GetAchievementNumCriteria(id) or 0
    local linkedDone = 0
    local unknown = false
    for i = 1, num do
        local value = GetLinkedCriteria(fields, i)
        if value == nil then
            unknown = true
        elseif value then
            linkedDone = linkedDone + 1
        end
    end

    local myDone, myTotal = AchievementsUtils:GetCriteriaProgress(id)
    local linkedText = AchievementsUtils:Trans("LID_NOTCOMPLETED")
    if completed then
        linkedText = AchievementsUtils:Trans("LID_COMPLETED")
        if parts[7] and parts[6] and parts[5] then linkedText = format("%s (%s.%s.%s)", linkedText, parts[6], parts[5], parts[7]) end
    elseif num > 0 and not unknown then
        linkedText = format("%s (%d/%d)", linkedText, linkedDone, num)
    end

    local myText = AchievementsUtils:Trans("LID_NOTCOMPLETED")
    if ach.completed then
        myText = AchievementsUtils:Trans("LID_COMPLETED")
        if ach.year and ach.month and ach.day then myText = format("%s (%s.%s.%s)", myText, ach.day, ach.month, 2000 + ach.year) end
    elseif myTotal > 0 then
        myText = format("%s (%d/%d)", myText, myDone, myTotal)
    end

    AchievementsUtils:MSG(AchievementsUtils:Trans("LID_COMPAREHEADER", nil, ach.name))
    AchievementsUtils:MSG(AchievementsUtils:Trans("LID_COMPARELINK"), linkedText)
    AchievementsUtils:MSG(AchievementsUtils:Trans("LID_COMPAREYOU"), myText)
end

local function OnItemRef(link, _, button)
    if type(link) ~= "string" then return end
    if not AchievementsUtils:IsEnabled("LINKS") then return end
    local parts = {strsplit(":", link)}
    if parts[1] ~= "achievement" then return end
    local id = tonumber(parts[2])
    if id == nil then return end
    if AchievementsUtils:IsEnabled("WOWHEAD") and IsAltKeyDown() then
        AchievementsUtils:ShowWowheadLink(id)

        return
    end

    if button == "MiddleButton" then
        AchievementsUtils:OpenToAchievement(id)

        return
    end

    if AchievementsUtils:IsEnabled("LINKTRACK") and IsControlKeyDown() then
        local now = GetTime()
        if lastCtrlID == id and (now - lastCtrlTime) < CTRL_TIMEOUT then
            lastCtrlID = nil
            local tracked = AchievementsUtils:ToggleTracked(id)
            local ach = AchievementsUtils:GetAchievement(id)
            local name = id
            if ach then name = ach.name end
            if tracked then
                AchievementsUtils:MSG(AchievementsUtils:Trans("LID_NOWTRACKING", nil, name))
            else
                AchievementsUtils:MSG(AchievementsUtils:Trans("LID_NOLONGERTRACKING", nil, name))
            end

            return
        end

        lastCtrlID = id
        lastCtrlTime = now
        AchievementsUtils:OpenToAchievement(id)
    end

    if AchievementsUtils:IsEnabled("LINKCOMPARE") then
        local guid = parts[3]
        if guid and guid ~= "" and guid ~= UnitGUID("player") then CompareLink(id, parts) end
    end
end

if type(SetItemRef) == "function" then
    hooksecurefunc(
        "SetItemRef",
        function(link, text, button)
            OnItemRef(link, text, button)
        end
    )
end
