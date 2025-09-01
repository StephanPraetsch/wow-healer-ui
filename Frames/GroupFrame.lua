local ADDON, ns = ...
ns = ns or {}
ns.Frames = ns.Frames or {}

local GroupFrame = CreateFrame("Frame", "WHUI_GroupFrame", UIParent, "SecureHandlerStateTemplate")
ns.Frames.GroupFrame = GroupFrame

GroupFrame:SetPoint("CENTER", UIParent, "CENTER", -300, 0)
GroupFrame:SetSize(180, 400)
GroupFrame:Hide()

GroupFrame.title = GroupFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
GroupFrame.title:SetPoint("TOPLEFT", 4, -4)
GroupFrame.title:SetText("Healer Group")

GroupFrame.container = CreateFrame("Frame", nil, GroupFrame)
GroupFrame.container:SetPoint("TOPLEFT", 0, -20)
GroupFrame.container:SetPoint("BOTTOMRIGHT", 0, 0)

GroupFrame.buttons = {}

local function GetRosterUnits()
    local units = {}
    if IsInRaid() then
        for i=1,40 do
            local unit = "raid"..i
            if UnitExists(unit) then table.insert(units, unit) end
        end
    elseif IsInGroup() then
        table.insert(units, "player")
        for i=1,4 do
            local unit = "party"..i
            if UnitExists(unit) then table.insert(units, unit) end
        end
    else
        table.insert(units, "player")
    end
    return units
end

local function LayoutButtons(self)
    local y = -2
    for i, btn in ipairs(self.buttons) do
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", self.container, "TOPLEFT", 10, y)
        btn:SetPoint("TOPRIGHT", self.container, "TOPRIGHT", -10, y)
        btn:SetHeight(40)
        y = y - 42
    end
    local height = 24 + (#self.buttons * 42) + 10
    self:SetHeight(math.max(height, 120))
end

function GroupFrame:UpdateUnits()
    if not WOWHealerUI_DB.enabled or not WOWHealerUI_DB.replacePlayerFrame then
        self:Hide()
        return
    end

    local units = GetRosterUnits()
    -- Reuse or create
    for i, unit in ipairs(units) do
        if not self.buttons[i] then
            self.buttons[i] = ns.Frames_CreateUnitButton(self.container, unit)
        else
            self.buttons[i].unit = unit
            ns.Frames_UpdateUnitButtonClickBindings(self.buttons[i])
        end
        self.buttons[i]:Show()
        -- Force refresh of data
        if self.buttons[i].GetScript and self.buttons[i]:GetScript("OnEvent") then
            self.buttons[i]:GetScript("OnEvent")("UNIT_HEALTH")
            self.buttons[i]:GetScript("OnEvent")("UNIT_POWER_UPDATE")
            self.buttons[i]:GetScript("OnEvent")("UNIT_AURA")
        end
    end
    for i = #units + 1, #self.buttons do
        self.buttons[i]:Hide()
    end

    LayoutButtons(self)
    self:Show()
end

function GroupFrame:OnUnitAura(unit)
    for _, btn in ipairs(self.buttons) do
        if btn.unit == unit then
            if btn.GetScript and btn:GetScript("OnEvent") then
                btn:GetScript("OnEvent")("UNIT_AURA")
            end
            break
        end
    end
end

function GroupFrame:UpdateClickBindings()
    if InCombatLockdown() then return end
    for _, btn in ipairs(self.buttons) do
        ns.Frames_UpdateUnitButtonClickBindings(btn)
    end
end
