local _, AchievementsUtils = ...
local BUTTON_SIZE = 22
local MENU_ROWS = 12
local MENU_WIDTH = 240
local ROW_HEIGHT = 18
local history = {}
local position = 0
local navigating = false
local installed = false
local backButton = nil
local forwardButton = nil
local menu = nil

local function GetMax()
    local value = tonumber(AchievementsUtils:GetOption("HISTORYMAX")) or 20
    if value < 2 then value = 2 end

    return value
end

local function HideMenu()
    if menu then menu:Hide() end
end

local function UpdateButtons()
    if backButton == nil then return end
    if not AchievementsUtils:IsEnabled("HISTORY") then
        backButton:Hide()
        forwardButton:Hide()
        HideMenu()

        return
    end

    backButton:Show()
    forwardButton:Show()
    if position > 1 then
        backButton:Enable()
    else
        backButton:Disable()
    end

    if position < #history then
        forwardButton:Enable()
    else
        forwardButton:Disable()
    end
end

local function GoTo(index)
    if index < 1 or index > #history then return end
    local id = history[index]
    if type(id) ~= "number" then return end
    position = index
    navigating = true
    AchievementsUtils:OpenToAchievement(id)
    navigating = false
    UpdateButtons()
end

local function Push(id)
    if navigating then return end
    if type(id) ~= "number" then return end
    if not AchievementsUtils:IsEnabled("HISTORY") then return end
    if type(AchievementFrame) ~= "table" or not AchievementFrame:IsShown() then return end
    if AchievementsUtils:GetAchievement(id) == nil then return end
    if history[position] == id then return end
    for i = #history, position + 1, -1 do
        tremove(history, i)
    end

    tinsert(history, id)
    local max = GetMax()
    while #history > max do
        tremove(history, 1)
    end

    position = #history
    UpdateButtons()
end

local function HookAchievementButton(button)
    if type(button) ~= "table" then return end
    if button.auHistoryHooked then return end
    if button.HookScript == nil then return end
    button.auHistoryHooked = true
    button:HookScript(
        "OnClick",
        function(sel)
            if type(IsModifierKeyDown) == "function" and IsModifierKeyDown() then return end
            Push(sel.id)
        end
    )
end

local function InstallButtonHooks()
    if EventRegistry and EventRegistry.RegisterCallback then
        EventRegistry:RegisterCallback(
            "AchievementFrameAchievement.OnEnter",
            function(_, button)
                HookAchievementButton(button)
            end,
            "AchievementsUtilsHistory"
        )

        return
    end

    if type(_G["AchievementButton_OnEnter"]) == "function" then hooksecurefunc("AchievementButton_OnEnter", HookAchievementButton) end
end

local function CreateMenu()
    if menu then return end
    if type(AchievementFrame) ~= "table" then return end
    menu = CreateFrame("Frame", "AchievementsUtilsHistoryMenu", AchievementFrame)
    menu:SetFrameStrata("DIALOG")
    menu:SetSize(MENU_WIDTH, ROW_HEIGHT + 4)
    menu:EnableMouse(true)
    AchievementsUtils:SetClampedToScreen(menu, true)
    local bg = menu:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(menu)
    if bg.SetColorTexture then
        bg:SetColorTexture(0.05, 0.05, 0.07, 0.95)
    else
        bg:SetTexture(0.05, 0.05, 0.07, 0.95)
    end

    menu.rows = {}
    for i = 1, MENU_ROWS do
        local row = CreateFrame("Button", nil, menu)
        row:SetHeight(ROW_HEIGHT)
        row:SetPoint("TOPLEFT", menu, "TOPLEFT", 3, -2 - (i - 1) * ROW_HEIGHT)
        row:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -3, -2 - (i - 1) * ROW_HEIGHT)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.text:SetPoint("LEFT", row, "LEFT", 2, 0)
        row.text:SetPoint("RIGHT", row, "RIGHT", -2, 0)
        row.text:SetJustifyH("LEFT")
        row:SetScript(
            "OnClick",
            function(sel)
                HideMenu()
                if sel.index then GoTo(sel.index) end
            end
        )

        menu.rows[i] = row
    end

    menu:Hide()
end

local function FillMenu()
    local shown = 0
    if #history <= 0 then
        local row = menu.rows[1]
        row.index = nil
        row.text:SetText(AchievementsUtils:Trans("LID_HISTORYEMPTY"))
        row.text:SetTextColor(0.6, 0.6, 0.6)
        row:Show()
        shown = 1
    else
        for i = #history, 1, -1 do
            if shown >= MENU_ROWS then break end
            shown = shown + 1
            local row = menu.rows[shown]
            local id = history[i]
            local ach = AchievementsUtils:GetAchievement(id)
            local name = tostring(id)
            if ach then name = ach.name end
            row.index = i
            row.text:SetText(name)
            if i == position then
                row.text:SetTextColor(1, 0.82, 0)
            else
                row.text:SetTextColor(0.8, 0.8, 0.8)
            end

            row:Show()
        end
    end

    for i = shown + 1, MENU_ROWS do
        menu.rows[i]:Hide()
    end

    menu:SetHeight(4 + shown * ROW_HEIGHT)
end

local function ToggleMenu(anchor)
    CreateMenu()
    if menu == nil then return end
    if menu:IsShown() then
        HideMenu()

        return
    end

    FillMenu()
    menu:ClearAllPoints()
    menu:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", 0, 2)
    menu:Show()
end

local function ButtonOnEnter(sel)
    GameTooltip:SetOwner(sel, "ANCHOR_RIGHT")
    GameTooltip:SetText(AchievementsUtils:Trans(sel.auLabel), 1, 1, 1)
    GameTooltip:AddLine(AchievementsUtils:Trans("LID_RIGHTCLICKHISTORY"), 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

local function ButtonOnLeave()
    GameTooltip:Hide()
end

local function CreateNavButton(name, texture, label)
    local button = CreateFrame("Button", name, AchievementFrame)
    button:SetSize(BUTTON_SIZE, BUTTON_SIZE)
    button:SetNormalTexture(texture .. "-Up")
    button:SetPushedTexture(texture .. "-Down")
    button:SetDisabledTexture(texture .. "-Disabled")
    button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight")
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button.auLabel = label
    button:SetScript("OnEnter", ButtonOnEnter)
    button:SetScript("OnLeave", ButtonOnLeave)

    return button
end

local function Install()
    if installed then return end
    if type(AchievementFrame) ~= "table" then return end
    installed = true
    forwardButton = CreateNavButton("AchievementsUtilsHistoryForward", "Interface\\Buttons\\UI-SpellbookIcon-NextPage", "LID_HISTORYFORWARD")
    forwardButton:SetPoint("TOPRIGHT", AchievementFrame, "BOTTOMRIGHT", -8, 1)
    forwardButton:SetScript(
        "OnClick",
        function(sel, button)
            if button == "RightButton" then
                ToggleMenu(sel)

                return
            end

            HideMenu()
            GoTo(position + 1)
        end
    )

    backButton = CreateNavButton("AchievementsUtilsHistoryBack", "Interface\\Buttons\\UI-SpellbookIcon-PrevPage", "LID_HISTORYBACK")
    backButton:SetPoint("RIGHT", forwardButton, "LEFT", -2, 0)
    backButton:SetScript(
        "OnClick",
        function(sel, button)
            if button == "RightButton" then
                ToggleMenu(sel)

                return
            end

            HideMenu()
            GoTo(position - 1)
        end
    )

    AchievementFrame:HookScript("OnHide", HideMenu)
    if type(AchievementFrame_SelectAchievement) == "function" then hooksecurefunc("AchievementFrame_SelectAchievement", Push) end
    InstallButtonHooks()
    UpdateButtons()
end

AchievementsUtils:OnAchievementUIReady(
    function()
        if not AchievementsUtils:IsEnabled("HISTORY") then return end
        Install()
    end
)

AchievementsUtils:OnOptionChanged(
    "HISTORY",
    function(value)
        if value ~= true then
            UpdateButtons()

            return
        end

        if not AchievementsUtils:LoadAchievementUI() then return end
        Install()
        UpdateButtons()
    end
)

AchievementsUtils:OnOptionChanged(
    "HISTORYMAX",
    function()
        local max = GetMax()
        while #history > max do
            tremove(history, 1)
        end

        if position > #history then position = #history end
        UpdateButtons()
    end
)
