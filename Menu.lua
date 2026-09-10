local _, AchievementsUtils = ...
local ROW_HEIGHT = 16
local ICON_ROW_HEIGHT = 20
local TITLE_HEIGHT = 22
local SEPARATOR_HEIGHT = 9
local PADDING = 8
local TEXT_INSET = 12
local ICON_SIZE = 14
local MARK_SIZE = 14
local MARK_INSET = 8
local MIN_WIDTH = 160
local MAX_WIDTH = 340
local CHECK_TEXTURE = "Interface\\RaidFrame\\ReadyCheck-Ready"
local ARROW_TEXTURE = "Interface\\ChatFrame\\ChatFrameExpandArrow"
local HIGHLIGHT_TEXTURE = "Interface\\QuestFrame\\UI-QuestTitleHighlight"
local MENU_BACKDROP = {
    ["bgFile"] = "Interface\\Buttons\\WHITE8X8",
    ["edgeFile"] = "Interface\\Tooltips\\UI-Tooltip-Border",
    ["edgeSize"] = 12,
    ["insets"] = {
        ["left"] = 3,
        ["right"] = 3,
        ["top"] = 3,
        ["bottom"] = 3
    }
}

local menus = {}
local catcher = nil
local hasGlobalMouse = nil
local ShowMenu = nil
local function HideFrom(level)
    for i = #menus, level, -1 do
        local menu = menus[i]
        if menu and menu:IsShown() then menu:Hide() end
    end
end

function AchievementsUtils:HideAchievementMenu()
    HideFrom(1)
    if catcher then catcher:Hide() end
end

local function AnyMenuHovered()
    for _, menu in ipairs(menus) do
        if menu:IsShown() and menu:IsMouseOver() then return true end
    end

    return false
end

local function CheckGlobalMouse(frame)
    if hasGlobalMouse ~= nil then return hasGlobalMouse end
    if C_EventUtils and C_EventUtils.IsEventValid then
        hasGlobalMouse = C_EventUtils.IsEventValid("GLOBAL_MOUSE_DOWN") == true

        return hasGlobalMouse
    end

    hasGlobalMouse = pcall(frame.RegisterEvent, frame, "GLOBAL_MOUSE_DOWN")
    if hasGlobalMouse then frame:UnregisterEvent("GLOBAL_MOUSE_DOWN") end

    return hasGlobalMouse
end

local function CreateCatcher()
    if catcher then return catcher end
    catcher = CreateFrame("Frame", "AchievementsUtilsMenuCatcher", UIParent)
    catcher:SetFrameStrata("FULLSCREEN_DIALOG")
    catcher:SetFrameLevel(1)
    catcher:SetAllPoints(UIParent)
    catcher:EnableMouse(true)
    catcher:SetScript("OnMouseDown", function() AchievementsUtils:HideAchievementMenu() end)
    catcher:Hide()

    return catcher
end

local function RowOnEnter(sel)
    local entry = sel.entry
    if entry == nil then return end
    if entry.entries then
        ShowMenu(sel.level + 1, entry.entries, sel)

        return
    end

    HideFrom(sel.level + 1)
end

local function RowOnClick(sel)
    local entry = sel.entry
    if entry == nil then return end
    if entry.entries then
        ShowMenu(sel.level + 1, entry.entries, sel)

        return
    end

    if entry.func == nil then return end
    AchievementsUtils:HideAchievementMenu()
    entry.func()
end

local function CreateRow(menu)
    local row = CreateFrame("Button", nil, menu)
    row:SetHeight(ROW_HEIGHT)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetHighlightTexture(HIGHLIGHT_TEXTURE)
    row.highlight = row:GetHighlightTexture()
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ICON_SIZE, ICON_SIZE)
    row.icon:SetPoint("LEFT", row, "LEFT", PADDING - 4, 0)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row.mark = row:CreateTexture(nil, "ARTWORK")
    row.mark:SetSize(MARK_SIZE, MARK_SIZE)
    row.mark:SetPoint("RIGHT", row, "RIGHT", -MARK_INSET, 0)
    row.line = row:CreateTexture(nil, "ARTWORK")
    row.line:SetHeight(1)
    row.line:SetPoint("LEFT", row, "LEFT", 6, 0)
    row.line:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    if row.line.SetColorTexture then
        row.line:SetColorTexture(0.4, 0.4, 0.4, 0.6)
    else
        row.line:SetTexture(0.4, 0.4, 0.4, 0.6)
    end

    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.text:SetJustifyH("LEFT")
    if row.text.SetWordWrap then row.text:SetWordWrap(false) end
    row:SetScript("OnEnter", RowOnEnter)
    row:SetScript("OnClick", RowOnClick)

    return row
end

local function FillMenu(menu, entries, level)
    local width = MIN_WIDTH
    local top = PADDING
    for i, entry in ipairs(entries) do
        local row = menu.rows[i]
        if row == nil then
            row = CreateRow(menu)
            menu.rows[i] = row
        end

        row.entry = entry
        row.level = level
        local height = ROW_HEIGHT
        local textLeft = TEXT_INSET
        local textRight = MARK_INSET
        row.icon:Hide()
        row.mark:Hide()
        row.line:Hide()
        if row.highlight then row.highlight:SetAlpha(0) end
        row:EnableMouse(false)
        if entry.kind == "separator" then
            height = SEPARATOR_HEIGHT
            row.text:SetText("")
            row.line:Show()
        elseif entry.kind == "title" then
            height = TITLE_HEIGHT
            row.text:SetFontObject(GameFontNormal)
            row.text:SetText(entry.text)
            row.text:SetTextColor(1, 0.82, 0)
        else
            row.text:SetFontObject(GameFontHighlightSmall)
            row.text:SetText(entry.text)
            if entry.current then
                row.text:SetTextColor(1, 0.82, 0)
            else
                row.text:SetTextColor(1, 1, 1)
            end

            if row.highlight then row.highlight:SetAlpha(1) end
            row:EnableMouse(true)
            if entry.entries then
                row.mark:SetTexture(ARROW_TEXTURE)
                row.mark:Show()
                textRight = MARK_INSET + MARK_SIZE + 2
            elseif entry.check then
                row.mark:SetTexture(CHECK_TEXTURE)
                row.mark:Show()
                textRight = MARK_INSET + MARK_SIZE + 2
            end
        end

        if entry.icon then
            row.icon:SetTexture(entry.icon)
            if row.icon.SetDesaturated then row.icon:SetDesaturated(entry.desaturate == true) end
            row.icon:Show()
            textLeft = PADDING + ICON_SIZE + 2
            if entry.kind ~= "title" and height < ICON_ROW_HEIGHT then height = ICON_ROW_HEIGHT end
        end

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", menu, "TOPLEFT", 4, -top)
        row:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -4, -top)
        row:SetHeight(height)
        row.text:ClearAllPoints()
        row.text:SetPoint("LEFT", row, "LEFT", textLeft - 4, 0)
        row.text:SetPoint("RIGHT", row, "RIGHT", -(textRight - 4), 0)
        local need = row.text:GetStringWidth() + textLeft + textRight + 8
        if need > width then width = need end
        row:Show()
        top = top + height
    end

    for i = #entries + 1, #menu.rows do
        menu.rows[i]:Hide()
    end

    if width > MAX_WIDTH then width = MAX_WIDTH end
    menu:SetWidth(width)
    menu:SetHeight(top + PADDING)
end

local function GetMenu(level)
    if menus[level] then return menus[level] end
    local template = nil
    if AchievementsUtils:CheckTemplates("BackdropTemplate") then template = "BackdropTemplate" end
    local menu = CreateFrame("Frame", "AchievementsUtilsMenu" .. level, UIParent, template)
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetFrameLevel(20 + level * 10)
    menu:SetSize(MIN_WIDTH, ROW_HEIGHT)
    menu:EnableMouse(true)
    AchievementsUtils:SetClampedToScreen(menu, true)
    if menu.SetBackdrop then
        menu:SetBackdrop(MENU_BACKDROP)
        menu:SetBackdropColor(0.03, 0.03, 0.05, 0.95)
        menu:SetBackdropBorderColor(0.5, 0.5, 0.5)
    else
        local bg = menu:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(menu)
        if bg.SetColorTexture then
            bg:SetColorTexture(0.03, 0.03, 0.05, 0.95)
        else
            bg:SetTexture(0.03, 0.03, 0.05, 0.95)
        end
    end

    menu.rows = {}
    menu:SetScript(
        "OnEvent",
        function()
            if AnyMenuHovered() then return end
            AchievementsUtils:HideAchievementMenu()
        end
    )

    menu:SetScript(
        "OnShow",
        function(sel)
            if level ~= 1 then return end
            if not CheckGlobalMouse(sel) then return end
            sel:RegisterEvent("GLOBAL_MOUSE_DOWN")
        end
    )

    menu:SetScript(
        "OnHide",
        function(sel)
            if level == 1 then
                if CheckGlobalMouse(sel) then sel:UnregisterEvent("GLOBAL_MOUSE_DOWN") end
                if catcher then catcher:Hide() end
            end

            HideFrom(level + 1)
        end
    )

    menu:Hide()
    menus[level] = menu

    return menu
end

ShowMenu = function(level, entries, row)
    local menu = GetMenu(level)
    HideFrom(level + 1)
    FillMenu(menu, entries, level)
    menu:ClearAllPoints()
    if row then
        menu:SetPoint("TOPLEFT", row, "TOPRIGHT", 2, 6)
    else
        local scale = UIParent:GetEffectiveScale()
        local x, y = GetCursorPosition()
        menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale, y / scale)
    end

    menu:Show()
end

local function LinkToChat(id)
    if type(GetAchievementLink) ~= "function" then return end
    local link = GetAchievementLink(id)
    if link == nil then return end
    if type(ChatEdit_InsertLink) == "function" and ChatEdit_InsertLink(link) then return end
    if type(ChatFrame_OpenChat) == "function" then ChatFrame_OpenChat(link) end
end

local function AddButton(entries, text, func)
    tinsert(
        entries,
        {
            ["kind"] = "button",
            ["text"] = text,
            ["func"] = func
        }
    )
end

local function BuildSeriesEntries(id)
    local before, after = AchievementsUtils:GetSeries(id)
    if #before <= 0 and #after <= 0 then return nil end
    local entries = {}
    local function AddSeries(value, current)
        local ach = AchievementsUtils:GetAchievement(value)
        if ach == nil then return end
        local text = ach.name
        if current then text = "> " .. text end
        tinsert(
            entries,
            {
                ["kind"] = "button",
                ["text"] = text,
                ["icon"] = ach.icon,
                ["desaturate"] = not ach.completed,
                ["check"] = ach.completed,
                ["current"] = current,
                ["func"] = function() AchievementsUtils:OpenToAchievement(value) end
            }
        )
    end

    for _, value in ipairs(before) do
        AddSeries(value, false)
    end

    AddSeries(id, true)
    for _, value in ipairs(after) do
        AddSeries(value, false)
    end

    if #entries <= 0 then return nil end

    return entries
end

local function BuildEntries(id, owner)
    local ach = AchievementsUtils:GetAchievement(id)
    if ach == nil then return nil end
    local entries = {}
    tinsert(
        entries,
        {
            ["kind"] = "title",
            ["text"] = ach.name,
            ["icon"] = ach.icon,
            ["desaturate"] = not ach.completed
        }
    )

    tinsert(entries, {["kind"] = "separator"})
    if type(GetAchievementLink) == "function" then
        AddButton(entries, AchievementsUtils:Trans("LID_MENULINK"), function() LinkToChat(id) end)
    end

    if AchievementsUtils:IsEnabled("WOWHEAD") then
        AddButton(entries, AchievementsUtils:Trans("LID_MENUWOWHEAD"), function() AchievementsUtils:ShowWowheadLink(id) end)
    end

    if AchievementsUtils:IsEnabled("TABWATCH") then
        local label = "LID_MENUWATCHADD"
        if AchievementsUtils:IsWatched(id) then label = "LID_MENUWATCHREMOVE" end
        AddButton(
            entries,
            AchievementsUtils:Trans(label),
            function()
                AchievementsUtils:ToggleWatch(id)
                AchievementsUtils:RefreshAchievementTooltip(owner, id)
            end
        )
    end

    if AchievementsUtils:CanTrack() and (not ach.completed or AchievementsUtils:IsTracked(id)) then
        local label = "LID_MENUTRACK"
        if AchievementsUtils:IsTracked(id) then label = "LID_MENUUNTRACK" end
        AddButton(
            entries,
            AchievementsUtils:Trans(label),
            function()
                AchievementsUtils:ToggleTracked(id)
                AchievementsUtils:RefreshAchievementTooltip(owner, id)
                if type(AchievementsUtils.RefreshExtraTab) == "function" then AchievementsUtils:RefreshExtraTab() end
            end
        )
    end

    local series = BuildSeriesEntries(id)
    if series then
        tinsert(entries, {["kind"] = "separator"})
        tinsert(
            entries,
            {
                ["kind"] = "submenu",
                ["text"] = AchievementsUtils:Trans("LID_PARTOFSERIES"),
                ["entries"] = series
            }
        )
    end

    return entries
end

function AchievementsUtils:ShowAchievementMenu(id, owner)
    if not AchievementsUtils:IsEnabled("CONTEXTMENU") then return false end
    if type(id) ~= "number" then return false end
    local entries = BuildEntries(id, owner)
    if entries == nil then return false end
    AchievementsUtils:HideAchievementMenu()
    if type(GameTooltip) == "table" and GameTooltip:IsShown() then GameTooltip:Hide() end
    if not CheckGlobalMouse(GetMenu(1)) then CreateCatcher():Show() end
    ShowMenu(1, entries)

    return true
end

AchievementsUtils:OnAchievementUIReady(
    function()
        if type(AchievementFrame) ~= "table" then return end
        if AchievementFrame.auMenuHooked then return end
        AchievementFrame.auMenuHooked = true
        AchievementFrame:HookScript("OnHide", function() AchievementsUtils:HideAchievementMenu() end)
    end
)

AchievementsUtils:OnOptionChanged("CONTEXTMENU", function(value) if value ~= true then AchievementsUtils:HideAchievementMenu() end end)
