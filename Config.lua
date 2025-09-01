local ADDON, ns = ...

ns = ns or {}
ns.Config = ns.Config or {}
local Config = ns.Config

local PANEL_NAME = "wow-healer-ui"

local function CreateCheckbox(parent, label, tooltip, get, set)
    local cb = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
    cb.Text:SetText(label)
    cb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(tooltip, 1,1,1, true)
    end)
    cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    cb:SetScript("OnClick", function(self)
        if InCombatLockdown() then
            print("Cannot change this setting in combat.")
            self:SetChecked(get())
            return
        end
        set(self:GetChecked())
    end)
    cb:SetChecked(get())
    return cb
end

function Config.InitOptionsPanel()
    -- Create a scrollable canvas frame to host our controls
    local panel = CreateFrame("Frame", "WHUI_OptionsPanel", UIParent)
    panel.name = PANEL_NAME

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("wow-healer-ui")

    local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    sub:SetText("Healer-focused UI by Stephan Prätsch")

    local y = -16
    local function placeBelow(widget, offset)
        widget:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, y)
        y = y - (offset or 30)
    end

    local cb1 = CreateCheckbox(panel, "Enable addon", "Master enable/disable",
            function() return WOWHealerUI_DB.enabled end,
            function(v)
                WOWHealerUI_DB.enabled = v
                if v and ns.Frames and ns.Frames.GroupFrame then
                    ns.Frames.GroupFrame:UpdateUnits()
                end
                if ns.Frames and ns.Frames.RightPanel then
                    ns.Frames.RightPanel:Refresh()
                end
            end)
    placeBelow(cb1)

    local cb2 = CreateCheckbox(panel, "Replace Player Frame", "Show group-style frame even when solo",
            function() return WOWHealerUI_DB.replacePlayerFrame end,
            function(v)
                WOWHealerUI_DB.replacePlayerFrame = v
                if ns.Frames and ns.Frames.GroupFrame then
                    if v then ns.Frames.GroupFrame:UpdateUnits() else ns.Frames.GroupFrame:Hide() end
                end
            end)
    cb2:SetPoint("TOPLEFT", cb1, "BOTTOMLEFT", 0, -8)

    local cb3 = CreateCheckbox(panel, "Hide Quest Tracker", "Hide the default quest/objective tracker",
            function() return WOWHealerUI_DB.hideObjectiveTracker end,
            function(v)
                WOWHealerUI_DB.hideObjectiveTracker = v
                C_Timer.After(0, function()
                    local f = ObjectiveTrackerFrame
                    if f then if v then f:Hide() else f:Show() end end
                end)
            end)
    cb3:SetPoint("TOPLEFT", cb2, "BOTTOMLEFT", 0, -8)

    local cb4 = CreateCheckbox(panel, "Right Panel", "Show the right-side info panel",
            function() return WOWHealerUI_DB.rightPanel end,
            function(v)
                WOWHealerUI_DB.rightPanel = v
                if ns.Frames and ns.Frames.RightPanel then
                    if v then ns.Frames.RightPanel:Show(); ns.Frames.RightPanel:Refresh() else ns.Frames.RightPanel:Hide() end
                end
            end)
    cb4:SetPoint("TOPLEFT", cb3, "BOTTOMLEFT", 0, -8)

    local cb5 = CreateCheckbox(panel, "Highlight dispellable debuffs", "White border if you can dispel",
            function() return WOWHealerUI_DB.showDispellableHighlight end,
            function(v) WOWHealerUI_DB.showDispellableHighlight = v end)
    cb5:SetPoint("TOPLEFT", cb4, "BOTTOMLEFT", 0, -8)

    local cb6 = CreateCheckbox(panel, "Highlight dangerous debuffs", "Orange border for curated dangerous debuffs",
            function() return WOWHealerUI_DB.showDangerousHighlight end,
            function(v) WOWHealerUI_DB.showDangerousHighlight = v end)
    cb6:SetPoint("TOPLEFT", cb5, "BOTTOMLEFT", 0, -8)

    local header = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    header:SetPoint("TOPLEFT", cb6, "BOTTOMLEFT", 0, -16)
    header:SetText("Click Casting (out of combat)")

    local help = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    help:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -6)
    help:SetText("Right-click spell: set a spell name you know (e.g., 'Heal'). Left-click targets.")

    local edit = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    edit:SetAutoFocus(false)
    edit:SetSize(420, 28)
    edit:SetPoint("TOPLEFT", help, "BOTTOMLEFT", 0, -10)
    edit:SetText(WOWHealerUI_DB.clickCast and WOWHealerUI_DB.clickCast.spell2 or "")
    local label = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetPoint("BOTTOMLEFT", edit, "TOPLEFT", 4, 6)
    label:SetText("RightButton Spell (spell2)")

    edit:SetScript("OnEnterPressed", function(self)
        if InCombatLockdown() then print("Cannot change in combat"); self:ClearFocus(); return end
        WOWHealerUI_DB.clickCast = WOWHealerUI_DB.clickCast or {}
        WOWHealerUI_DB.clickCast.spell2 = self:GetText()
        self:ClearFocus()
        if ns.Frames and ns.Frames.GroupFrame and ns.Frames.GroupFrame.UpdateClickBindings then
            ns.Frames.GroupFrame:UpdateClickBindings()
        end
    end)

    -- Register with the modern Settings API
    local category = Settings.RegisterCanvasLayoutCategory(panel, PANEL_NAME)
    category.ID = PANEL_NAME
    Settings.RegisterAddOnCategory(category)

    Config._category = category
    Config._panel = panel
end

function Config.OpenOptionsPanel()
    if Config._category then
        Settings.OpenToCategory(Config._category.ID)
    else
        -- Fallback for very old clients
        if InterfaceOptionsFrame then
            InterfaceOptionsFrame_OpenToCategory(PANEL_NAME)
            InterfaceOptionsFrame_OpenToCategory(PANEL_NAME)
        end
    end
end
