local ADDON, ns = ...
ns = ns or {}
ns.Frames = ns.Frames or {}
local Utils = ns.Utils
local Data = ns.Data

local UnitButton = CreateFrame("Button", "WHUI_UnitButtonTemplate", UIParent, "SecureUnitButtonTemplate")
-- Build-time template holder; we will Instantiate using CreateFrame with inherited "SecureUnitButtonTemplate"

local function CreateHealthBar(parent)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetStatusBarTexture("Interface\\TARGETINGFRAME\\UI-StatusBar")
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(1)
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints(true)
    bar.bg:SetTexture("Interface\\Buttons\\WHITE8x8")
    bar.bg:SetVertexColor(0, 0, 0, 0.6)
    return bar
end

local function CreatePowerBar(parent)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetStatusBarTexture("Interface\\TARGETINGFRAME\\UI-StatusBar")
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(1)
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints(true)
    bar.bg:SetTexture("Interface\\Buttons\\WHITE8x8")
    bar.bg:SetVertexColor(0, 0, 0, 0.6)
    return bar
end

local function SetBorderColor(frame, r,g,b,a)
    frame.border:SetVertexColor(r,g,b,a or 1)
    frame.border:Show()
end

local function ClearBorder(frame)
    frame.border:Hide()
end

local function UpdateHealth(self)
    local hp, hpMax = UnitHealth(self.unit), UnitHealthMax(self.unit)
    self.health:SetMinMaxValues(0, hpMax)
    self.health:SetValue(hp)
    local perc = (hpMax > 0) and (hp / hpMax) or 0
    if perc > 0.5 then self.health:SetStatusBarColor(0.1, 0.8, 0.1)
    elseif perc > 0.25 then self.health:SetStatusBarColor(0.9, 0.7, 0.1)
    else self.health:SetStatusBarColor(0.9, 0.1, 0.1) end
    self.nameText:SetText(UnitName(self.unit) or "")
end

local function UpdatePower(self)
    local p, pMax = UnitPower(self.unit), UnitPowerMax(self.unit)
    self.power:SetMinMaxValues(0, pMax)
    self.power:SetValue(pMax > 0 and p or 0)
    local pt = UnitPowerType(self.unit)
    if pt == 0 then self.power:SetStatusBarColor(0.2, 0.4, 1) -- mana
    elseif pt == 1 then self.power:SetStatusBarColor(1, 0.2, 0.2) -- rage
    elseif pt == 3 then self.power:SetStatusBarColor(1, 1, 0.2) -- energy
    else self.power:SetStatusBarColor(0.6, 0.6, 0.6) end
end

local function UpdateAuras(self)
    local dispellable = false
    local dangerous = false
    local Data = ns.Data

    -- Dispellable check (class-aware)
    dispellable = select(1, ns.Utils.IsDispellableByPlayer(self.unit))

    -- Dangerous debuff check via C_UnitAuras
    if C_UnitAuras and C_UnitAuras.GetDebuffDataByIndex then
        for i = 1, 40 do
            local aura = C_UnitAuras.GetDebuffDataByIndex(self.unit, i)
            if not aura or not aura.spellId then break end
            if Data and Data.DangerousDebuffs and Data.DangerousDebuffs[aura.spellId] then
                dangerous = true
                break
            end
        end
    else
        -- Fallback to UnitAura if available
        if UnitAura then
            for i = 1, 40 do
                local name, _, _, _, _, _, _, _, _, spellId = UnitAura(self.unit, i, "HARMFUL")
                if not name then break end
                if Data and Data.DangerousDebuffs and Data.DangerousDebuffs[spellId] then
                    dangerous = true
                    break
                end
            end
        end
    end

    -- Border priority: dangerous (orange) > dispellable (white)
    self.border:Hide()
    if WOWHealerUI_DB.showDangerousHighlight and dangerous then
        self.border:SetVertexColor(1, 0.5, 0, 1)
        self.border:Show()
    elseif WOWHealerUI_DB.showDispellableHighlight and dispellable then
        self.border:SetVertexColor(1, 1, 1, 1)
        self.border:Show()
    end
end

local function RegisterEvents(self)
    self:RegisterUnitEvent("UNIT_HEALTH", self.unit)
    self:RegisterUnitEvent("UNIT_MAXHEALTH", self.unit)
    self:RegisterUnitEvent("UNIT_POWER_UPDATE", self.unit)
    self:RegisterUnitEvent("UNIT_DISPLAYPOWER", self.unit)
    self:RegisterUnitEvent("UNIT_AURA", self.unit)
    self:SetScript("OnEvent", function(frame, event)
        if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then UpdateHealth(frame)
        elseif event == "UNIT_POWER_UPDATE" or event == "UNIT_DISPLAYPOWER" then UpdatePower(frame)
        elseif event == "UNIT_AURA" then UpdateAuras(frame) end
    end)
end

local function SetupClickCasting(self)
    -- Secure attributes for click-casting
    local cc = WOWHealerUI_DB.clickCast or {}
    -- Left click: target by default
    self:SetAttribute("type1", cc.type1 or "target")
    if cc.macrotext1 then self:SetAttribute("macrotext1", cc.macrotext1) end
    if cc.spell1 then self:SetAttribute("spell1", cc.spell1) end

    -- Right click: cast spell if set
    self:SetAttribute("type2", cc.type2 or "spell")
    if cc.spell2 then self:SetAttribute("spell2", cc.spell2) end
    if cc.macrotext2 then self:SetAttribute("macrotext2", cc.macrotext2) end

    -- Mouseover casting support
    self:SetAttribute("unit", self.unit)
end

local function OnEnter(self)
    self.hl:Show()
end
local function OnLeave(self)
    self.hl:Hide()
end

function ns.Frames_CreateUnitButton(parent, unit)
    local btn = CreateFrame("Button", nil, parent, "SecureUnitButtonTemplate")
    btn.unit = unit
    btn:SetSize(160, 36)

    btn.bg = btn:CreateTexture(nil, "BACKGROUND")
    btn.bg:SetAllPoints(true)
    btn.bg:SetColorTexture(0, 0, 0, 0.35)

    btn.border = btn:CreateTexture(nil, "OVERLAY")
    btn.border:SetPoint("TOPLEFT", -2, 2)
    btn.border:SetPoint("BOTTOMRIGHT", 2, -2)
    btn.border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    btn.border:Hide()

    btn.hl = btn:CreateTexture(nil, "HIGHLIGHT")
    btn.hl:SetAllPoints(true)
    btn.hl:SetColorTexture(1,1,1,0.08)
    btn.hl:Hide()

    btn.nameText = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    btn.nameText:SetPoint("TOPLEFT", 4, -2)
    btn.nameText:SetJustifyH("LEFT")

    btn.health = CreateHealthBar(btn)
    btn.health:SetPoint("TOPLEFT", 4, -14)
    btn.health:SetPoint("TOPRIGHT", -4, -14)
    btn.health:SetHeight(14)

    btn.power = CreatePowerBar(btn)
    btn.power:SetPoint("TOPLEFT", btn.health, "BOTTOMLEFT", 0, -2)
    btn.power:SetPoint("TOPRIGHT", btn.health, "BOTTOMRIGHT", 0, -2)
    btn.power:SetHeight(8)

    btn:SetScript("OnEnter", OnEnter)
    btn:SetScript("OnLeave", OnLeave)

    RegisterEvents(btn)
    SetupClickCasting(btn)

    UpdateHealth(btn)
    UpdatePower(btn)
    UpdateAuras(btn)

    return btn
end

function ns.Frames_UpdateUnitButtonClickBindings(button)
    if InCombatLockdown() then return end
    if not button or not button.unit then return end
    -- Reapply attributes when settings change
    local cc = WOWHealerUI_DB.clickCast or {}
    button:SetAttribute("type1", cc.type1 or "target")
    if cc.spell1 then button:SetAttribute("spell1", cc.spell1) else button:SetAttribute("spell1", nil) end
    if cc.macrotext1 then button:SetAttribute("macrotext1", cc.macrotext1) else button:SetAttribute("macrotext1", nil) end

    button:SetAttribute("type2", cc.type2 or "spell")
    if cc.spell2 then button:SetAttribute("spell2", cc.spell2) else button:SetAttribute("spell2", nil) end
    if cc.macrotext2 then button:SetAttribute("macrotext2", cc.macrotext2) else button:SetAttribute("macrotext2", nil) end
end
