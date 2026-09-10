local _, AchievementsUtils = ...
local ICON = 133176
local DEFAULT_WIDTH = 540
local DEFAULT_HEIGHT = 560
local STATUS_INTERVAL = 0.5
local settings = nil
local widgets = {}
local footerStatus = nil
local resetButton = nil
local function GetTocVersion()
    if C_AddOns and C_AddOns.GetAddOnMetadata then return C_AddOns.GetAddOnMetadata("AchievementsUtils", "Version") end
    if GetAddOnMetadata then return GetAddOnMetadata("AchievementsUtils", "Version") end
    return "0.0.0"
end

local function ApplyDefaults()
    local db = AchievementsUtils:GetDB()
    for _, info in ipairs(AchievementsUtils:GetOptionList()) do
        if info.kind ~= "category" and info.default ~= nil then AchievementsUtils:SV(db, info.key, AchievementsUtils:GV(db, info.key, info.default)) end
    end
end

local function GetCollapsed(key)
    if key == nil then return nil end
    local db = AchievementsUtils:GetDB()
    if type(db["COLLAPSED"]) ~= "table" then return nil end
    return db["COLLAPSED"][key]
end

local function SetCollapsed(key, collapsed)
    if key == nil then return end
    local db = AchievementsUtils:GetDB()
    if type(db["COLLAPSED"]) ~= "table" then db["COLLAPSED"] = {} end
    if collapsed then
        db["COLLAPSED"][key] = true
    else
        db["COLLAPSED"][key] = nil
    end
end

local function LabelFor(info)
    local text = AchievementsUtils:TryTrans(info.label)
    if info.parent and not AchievementsUtils:IsEnabled(info.parent) then text = text .. " |cff888888(" .. AchievementsUtils:Trans("LID_REQUIRES", nil, AchievementsUtils:GetOptionLabel(info.parent)) .. ")|r" end
    return text
end

local function SetControlEnabled(holder, enabled)
    if holder == nil then return end
    local control = holder.slider or holder.control
    if control == nil then return end
    if enabled then
        if control.Enable then control:Enable() end
    elseif control.Disable then
        control:Disable()
    end
end

local function RefreshDependencies()
    for _, info in ipairs(AchievementsUtils:GetOptionList()) do
        local widget = widgets[info.key]
        if widget and info.parent then
            local enabled = AchievementsUtils:IsEnabled(info.parent)
            if info.kind == "toggle" then
                if widget.SetEnabled then widget:SetEnabled(enabled) end
                if widget.UpdateLabel then widget:UpdateLabel() end
            else
                SetControlEnabled(widget, enabled)
            end
        end
    end

    if resetButton then
        if AchievementsUtils:IsEnabled("MOVABLE") then
            resetButton:Enable()
        else
            resetButton:Disable()
        end
    end
end

local function AddToggle(info)
    widgets[info.key] = settings:AddCheckbox({
        ["label"] = info.label,
        ["search"] = info.key,
        ["value"] = AchievementsUtils:GetOption(info.key),
        ["textFunc"] = function() return LabelFor(info) end,
        ["func"] = function(value)
            AchievementsUtils:SetOption(info.key, value)
            RefreshDependencies()
        end
    })
end

local function AddSlider(info)
    widgets[info.key] = settings:AddSlider({
        ["label"] = info.label,
        ["search"] = info.key,
        ["value"] = AchievementsUtils:GetOption(info.key),
        ["min"] = info.min,
        ["max"] = info.max,
        ["step"] = info.step,
        ["decimals"] = info.decimals,
        ["func"] = function(value) AchievementsUtils:SetOption(info.key, value) end
    })
end

local function AddDropdown(info)
    local choices = nil
    if info.key == "REMINDERSOUNDID" then choices = AchievementsUtils:GetSoundChoices() end
    if info.key == "ACHSTYLE" then choices = AchievementsUtils:GetAchStyleChoices() end
    if choices == nil then return end
    widgets[info.key] = settings:AddDropdown({
        ["label"] = info.label,
        ["search"] = info.key,
        ["value"] = AchievementsUtils:GetOption(info.key),
        ["choices"] = choices,
        ["func"] = function(value) AchievementsUtils:SetOption(info.key, value) end
    })
end

local function AddOption(info)
    if info.needsTrack == true and not AchievementsUtils:CanTrack() then return end
    if info.kind == "category" then
        settings:AddCategory({
            ["label"] = info.label,
            ["key"] = info.key
        })

        return
    end

    if info.kind == "toggle" then
        AddToggle(info)

        return
    end

    if info.kind == "slider" then
        AddSlider(info)

        return
    end

    if info.kind == "dropdown" then AddDropdown(info) end
end

local function BuildFooter()
    local footer = settings:AddFooter({
        ["height"] = 26
    })

    if footer == nil then return end
    local rebuild = AchievementsUtils:CreateButton("AchievementsUtilsRebuildIndex", footer)
    rebuild:SetSize(130, 22)
    rebuild:SetPoint("RIGHT", footer, "RIGHT", 0, 0)
    rebuild:SetText(AchievementsUtils:Trans("LID_INDEXREBUILD"))
    rebuild:SetScript("OnClick", function() AchievementsUtils:BuildIndex(true) end)
    resetButton = AchievementsUtils:CreateButton("AchievementsUtilsResetPosition", footer)
    resetButton:SetSize(130, 22)
    resetButton:SetPoint("RIGHT", rebuild, "LEFT", -4, 0)
    resetButton:SetText(AchievementsUtils:Trans("LID_RESETPOSITION"))
    resetButton:SetScript("OnClick", function() AchievementsUtils:ResetFramePosition() end)
    footerStatus = footer:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    footerStatus:SetPoint("LEFT", footer, "LEFT", 4, 0)
    footerStatus:SetPoint("RIGHT", resetButton, "LEFT", -6, 0)
    footerStatus:SetJustifyH("LEFT")
    local elapsed = 0
    footer:SetScript("OnUpdate", function(sel, delta)
        elapsed = elapsed + delta
        if elapsed < STATUS_INTERVAL then return end
        elapsed = 0
        footerStatus:SetText(AchievementsUtils:GetIndexStatus())
    end)
end

function AchievementsUtils:ToggleSettings()
    if settings then settings:Toggle() end
end

function AchievementsUtils:InitSettings()
    settings = AchievementsUtils:CreateUIWindow({
        ["name"] = "AchievementsUtilsSettings",
        ["pTab"] = {"CENTER"},
        ["width"] = AchievementsUtils:GV(AchievementsUtils:GetDB(), "WINDOWWIDTH", DEFAULT_WIDTH),
        ["height"] = AchievementsUtils:GV(AchievementsUtils:GetDB(), "WINDOWHEIGHT", DEFAULT_HEIGHT),
        ["minWidth"] = 380,
        ["minHeight"] = 260,
        ["onResize"] = function(width, height)
            AchievementsUtils:SV(AchievementsUtils:GetDB(), "WINDOWWIDTH", width)
            AchievementsUtils:SV(AchievementsUtils:GetDB(), "WINDOWHEIGHT", height)
        end,
        ["getCollapsed"] = function(key) return GetCollapsed(key) end,
        ["setCollapsed"] = function(key, collapsed) SetCollapsed(key, collapsed) end,
        ["title"] = format("|T%d:16:16:0:0|t AchievementsUtils v%s", ICON, GetTocVersion())
    })

    settings:SuspendLayout()
    settings:AddSearch()
    for _, info in ipairs(AchievementsUtils:GetOptionList()) do
        AddOption(info)
    end

    BuildFooter()
    settings:ResumeLayout()
    RefreshDependencies()
end

local function HandleSlash(msg)
    msg = strtrim(msg or "")
    if msg == "" then
        AchievementsUtils:ToggleSettings()
        return
    end

    local cmd = string.lower(msg)
    if cmd == "reindex" then
        AchievementsUtils:BuildIndex(true)
        AchievementsUtils:MSG(AchievementsUtils:Trans("LID_INDEXREBUILD"))
        return
    end

    if cmd == "reset" then
        AchievementsUtils:ResetFramePosition()
        return
    end

    AchievementsUtils:OpenSearchTab(msg)
end

local function HandleSearchSlash(msg)
    AchievementsUtils:OpenSearchTab(strtrim(msg or ""))
end

local loader = CreateFrame("Frame", "AchievementsUtilsSettingsLoader")
AchievementsUtils:RegisterEvent(loader, "PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
    AchievementsUtilsDB = AchievementsUtilsDB or {}
    AchievementsUtilsPCDB = AchievementsUtilsPCDB or {}
    ApplyDefaults()
    AchievementsUtils:SetVersion(ICON, GetTocVersion())
    AchievementsUtils:SetAddonOutput("AchievementsUtils", ICON)
    AchievementsUtils:CreateMinimapButton({
        ["name"] = "AchievementsUtils",
        ["icon"] = ICON,
        ["dbtab"] = AchievementsUtilsDB,
        ["dbkey"] = "SHOWMINIMAPBUTTON",
        ["vTT"] = {{format("|T%d:16:16:0:0|t AchievementsUtils", ICON), "v" .. GetTocVersion()}, {AchievementsUtils:Trans("LID_LEFTCLICK"), AchievementsUtils:Trans("LID_OPENSETTINGS")}, {AchievementsUtils:Trans("LID_RIGHTCLICK"), AchievementsUtils:Trans("LID_HIDEMINIMAPBUTTON")}},
        ["funcL"] = function() AchievementsUtils:ToggleSettings() end,
        ["funcR"] = function()
            AchievementsUtils:SV(AchievementsUtilsDB, "SHOWMINIMAPBUTTON", false)
            AchievementsUtils:HideMMBtn("AchievementsUtils")
        end
    })

    AchievementsUtils:InitSettings()
    AchievementsUtils:AddSlash("au", HandleSlash)
    AchievementsUtils:AddSlash("achievementsutils", HandleSlash)
    AchievementsUtils:AddSlash("ach", HandleSearchSlash)
    if not AchievementsUtils:HasAchievementAPI() then AchievementsUtils:MSG(AchievementsUtils:Trans("LID_INDEXUNAVAILABLE")) end
end)
