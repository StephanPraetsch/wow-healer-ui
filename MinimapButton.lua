local ADDON_NAME = ...
local WowHealerUI = _G.WowHealerUI

local Mini = {}
WowHealerUI:RegisterModule("MinimapButton", Mini)

local button
local dragging = false
local RADIUS_OUTER = 92 -- place outside the minimap ring; adjust if your UI scale differs

local function GetMinimapCenter()
    local mx, my = Minimap:GetCenter()
    local scale = UIParent:GetEffectiveScale()
    return mx, my, scale
end

local function UpdatePositionFromAngle(angle)
    if not button then return end
    WowHealerUI_DB.minimap.pos = angle
    local rad = math.rad(angle)
    local x = RADIUS_OUTER * math.cos(rad)
    local y = RADIUS_OUTER * math.sin(rad)
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function UpdateAngleFromCursor()
    local mx, my, scale = GetMinimapCenter()
    local px, py = GetCursorPosition()
    local dx, dy = px/scale - mx, py/scale - my
    local angle = math.deg(math.atan2(dy, dx))
    if angle < 0 then angle = angle + 360 end
    UpdatePositionFromAngle(angle)
end

local function EnsurePosition()
    local angle = WowHealerUI_DB and WowHealerUI_DB.minimap and WowHealerUI_DB.minimap.pos or 225
    UpdatePositionFromAngle(angle)
end

function Mini:OnInit()
    button = CreateFrame("Button", "WowHealerUIMinimapButton", Minimap)
    button:SetSize(32, 32)
    button:SetFrameStrata("MEDIUM")
    button:SetMovable(true)
    button:RegisterForDrag("LeftButton")

    local overlay = button:CreateTexture(nil, "OVERLAY")
    overlay:SetSize(52, 52)
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    overlay:SetPoint("TOPLEFT", 0, 0)

    local icon = button:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", 0, 0)
    icon:SetTexture(WowHealerUI.ICON_TEXTURE)
    button.icon = icon

    -- Drag behavior: smoothly follow cursor, set angle outside the ring
    button:SetScript("OnDragStart", function(self)
        dragging = true
        self:SetScript("OnUpdate", function()
            if dragging then
                UpdateAngleFromCursor()
            end
        end)
    end)

    button:SetScript("OnDragStop", function(self)
        dragging = false
        self:SetScript("OnUpdate", nil)
        EnsurePosition()
    end)

    button:SetScript("OnMouseWheel", function(self, delta)
        local angle = WowHealerUI_DB.minimap.pos or 225
        angle = angle + (delta > 0 and 5 or -5)
        if angle < 0 then angle = angle + 360 end
        if angle >= 360 then angle = angle - 360 end
        UpdatePositionFromAngle(angle)
    end)
    button:EnableMouseWheel(true)

    button:SetScript("OnClick", function(self, btn)
        if btn == "LeftButton" then
            if Settings and Settings.OpenToCategory then
                Settings.OpenToCategory("wow-healer-ui")
            end
        elseif btn == "RightButton" then
            WowHealerUI:ToggleEnabled(not WowHealerUI:IsEnabled())
        end
    end)

    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("wow-healer-ui", 1,1,1)
        GameTooltip:AddLine("Left-click: Open config", 0.9,0.9,0.9)
        GameTooltip:AddLine("Right-click: Toggle addon", 0.9,0.9,0.9)
        GameTooltip:AddLine("Drag: Move icon", 0.9,0.9,0.9)
        GameTooltip:AddLine("Mousewheel: Rotate icon", 0.9,0.9,0.9)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    EnsurePosition()
end

function Mini:OnLogin()
    if WowHealerUI_DB.minimap.hide then
        button:Hide()
    else
        button:Show()
    end
    EnsurePosition()
end

function Mini:OnConfigChanged(what)
    if what == "minimap" then
        if WowHealerUI_DB.minimap.hide then
            button:Hide()
        else
            button:Show()
            EnsurePosition()
        end
    end
end

function Mini:OnEnableChanged(enabled)
    if enabled then
        button.icon:SetDesaturated(false)
        button:SetAlpha(1)
    else
        button.icon:SetDesaturated(true)
        button:SetAlpha(0.5)
    end
end
