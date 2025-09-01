local ADDON_NAME = ...
local WowHealerUI = _G.WowHealerUI

local Config = {}
WowHealerUI:RegisterModule("Config", Config)

local panel

function Config:OnInit()
    -- Create panel for new Settings UI
    panel = CreateFrame("Frame", "WowHealerUIConfigPanel", UIParent)
    panel:Hide()

    panel.title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    panel.title:SetPoint("TOPLEFT", 16, -16)
    panel.title:SetText("wow-healer-ui")

    -- Enable/Disable checkbox
    local cb = CreateFrame("CheckButton", "$parentEnableCB", panel, "InterfaceOptionsCheckButtonTemplate")
    cb:SetPoint("TOPLEFT", panel.title, "BOTTOMLEFT", 0, -12)
    cb.Text:SetText("Enable addon")
    cb:SetScript("OnClick", function(self)
        WowHealerUI:ToggleEnabled(self:GetChecked())
    end)
    panel.enableCB = cb

    -- Minimap show/hide
    local cb2 = CreateFrame("CheckButton", "$parentMinimapCB", panel, "InterfaceOptionsCheckButtonTemplate")
    cb2:SetPoint("TOPLEFT", cb, "BOTTOMLEFT", 0, -8)
    cb2.Text:SetText("Show minimap icon")
    cb2:SetScript("OnClick", function(self)
        WowHealerUI_DB.minimap.hide = not self:GetChecked()
        WowHealerUI:ForEachModule("OnConfigChanged", "minimap")
    end)
    panel.minimapCB = cb2

    -- Register with new Settings UI
    local category, layout = Settings.RegisterCanvasLayoutCategory(panel, "wow-healer-ui")
    category.ID = "wow-healer-ui"
    Settings.RegisterAddOnCategory(category)
    Config._category = category
end

function Config:OnLogin()
    if not panel then return end
    panel.enableCB:SetChecked(WowHealerUI:IsEnabled())
    panel.minimapCB:SetChecked(not WowHealerUI_DB.minimap.hide)
end

-- Slash command to open settings
SLASH_WOWHEALERUI1 = "/whui"
SlashCmdList["WOWHEALERUI"] = function()
    if Settings and Settings.OpenToCategory and Config._category then
        Settings.OpenToCategory(Config._category.ID)
    end
end
