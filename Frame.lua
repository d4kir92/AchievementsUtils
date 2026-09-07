local _, AchievementsUtils = ...
local installed = false

local function SavePosition()
    if not AchievementsUtils:IsEnabled("SAVEPOSITION") then return end
    if type(AchievementFrame) ~= "table" then return end
    local point, _, relativePoint, x, y = AchievementFrame:GetPoint(1)
    if point == nil then return end
    AchievementsUtils:SV(
        AchievementsUtils:GetDB(),
        "FRAMEPOSITION",
        {
            ["point"] = point,
            ["relativePoint"] = relativePoint,
            ["x"] = x,
            ["y"] = y
        }
    )
end

local function ApplyPosition()
    if type(AchievementFrame) ~= "table" then return end
    if not AchievementsUtils:IsEnabled("SAVEPOSITION") then return end
    local pos = AchievementsUtils:GV(AchievementsUtils:GetDB(), "FRAMEPOSITION", nil)
    if type(pos) ~= "table" then return end
    if pos.point == nil then return end
    AchievementFrame:ClearAllPoints()
    AchievementFrame:SetPoint(pos.point, UIParent, pos.relativePoint or pos.point, pos.x or 0, pos.y or 0)
end

function AchievementsUtils:ResetFramePosition()
    AchievementsUtils:SV(AchievementsUtils:GetDB(), "FRAMEPOSITION", nil)
    if type(AchievementFrame) ~= "table" then return end
    AchievementFrame:ClearAllPoints()
    AchievementFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
end

local function OnDragStart()
    if not AchievementsUtils:IsEnabled("MOVABLE") then return end
    if InCombatLockdown() then return end
    AchievementFrame:StartMoving()
end

local function OnDragStop()
    if type(AchievementFrame) ~= "table" then return end
    AchievementFrame:StopMovingOrSizing()
    SavePosition()
end

local function Install()
    if installed then return end
    if type(AchievementFrame) ~= "table" then return end
    installed = true
    AchievementFrame:SetMovable(true)
    AchievementFrame:EnableMouse(true)
    AchievementsUtils:SetClampedToScreen(AchievementFrame, true)
    AchievementFrame:RegisterForDrag("LeftButton")
    AchievementFrame:HookScript("OnDragStart", OnDragStart)
    AchievementFrame:HookScript("OnDragStop", OnDragStop)
    AchievementFrame:HookScript(
        "OnShow",
        function()
            C_Timer.After(0, ApplyPosition)
        end
    )

    ApplyPosition()
end

AchievementsUtils:OnAchievementUIReady(
    function()
        if AchievementsUtils:GetOption("MOVABLE") == false then return end
        Install()
    end
)

AchievementsUtils:OnOptionChanged(
    "MOVABLE",
    function(value)
        if value ~= true then return end
        if not AchievementsUtils:LoadAchievementUI() then return end
        Install()
    end
)
