local ADDON_NAME = ...
local WowHealerUI = _G.WowHealerUI

local GroupView = {}
WowHealerUI:RegisterModule("GroupView", GroupView)

local ROOT
local UNIT_BUTTONS = {}
local RAID_GROUP_HEADERS = {}
local HILIGHT_COLOR = { r=1, g=1, b=0.2 }

-- Configuration
local BUTTON_WIDTH, BUTTON_HEIGHT = 200, 28
local FONT = "GameFontNormal"
local H_SPACING, V_SPACING = 8, 4
local FRAME_PADDING = 6 -- padding inside the surrounding frame

-- Unit sorting helpers
local function RoleSort(u1, u2)
    local prio = { TANK=1, HEALER=2, DAMAGER=3, NONE=4 }
    local r1 = prio[WowHealerUI:GetUnitRole(u1)] or 4
    local r2 = prio[WowHealerUI:GetUnitRole(u2)] or 4
    if r1 ~= r2 then return r1 < r2 end
    return (UnitName(u1) or "") < (UnitName(u2) or "")
end

local function BuildUnitList()
    local units = {}
    if IsInRaid() then
        for i=1, GetNumGroupMembers() do
            table.insert(units, "raid"..i)
        end
    elseif IsInGroup() then
        table.insert(units, "player")
        for i=1, GetNumSubgroupMembers() do
            table.insert(units, "party"..i)
        end
    else
        table.insert(units, "player")
    end
    return units
end

local function GetRaidGroupIndex(unit)
    if not IsInRaid() then return 1 end
    local unitName = UnitName(unit)
    for i=1, GetNumGroupMembers() do
        local raidName, rank, subgroup = GetRaidRosterInfo(i)
        if raidName == unitName then
            return subgroup or 1
        end
    end
    return 1
end

local function CreateUnitButton(parent)
    local b = CreateFrame("Button", nil, parent, "SecureActionButtonTemplate,BackdropTemplate")
    b:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)
    b:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    b:SetBackdropColor(0,0,0,0)
    b:SetBackdropBorderColor(0.2,0.2,0.2,1)

    local classBG = b:CreateTexture(nil, "BACKGROUND", nil, -8)
    classBG:SetAllPoints(true)
    classBG:SetColorTexture(1, 1, 1, 1)
    b.classBG = classBG

    b:RegisterForClicks("AnyDown")

    -- Secure spell targeting: left targets, right can be set to a spell externally
    b:SetAttribute("*type1", "target")
    b:SetAttribute("*type2", "spell")
    b:SetAttribute("spell", nil)

    local nameFS = b:CreateFontString(nil, "OVERLAY", FONT)
    nameFS:SetPoint("LEFT", 6, 0)
    nameFS:SetWidth(90)
    nameFS:SetJustifyH("LEFT")
    b.nameFS = nameFS

    local hpBar = CreateFrame("StatusBar", nil, b)
    hpBar:SetStatusBarTexture("Interface\\TARGETINGFRAME\\UI-StatusBar")
    hpBar:SetSize(80, 10)
    hpBar:SetPoint("RIGHT", -6, 6)
    hpBar:SetMinMaxValues(0,1)
    hpBar.bg = b:CreateTexture(nil, "BACKGROUND")
    hpBar.bg:SetAllPoints(hpBar)
    hpBar.bg:SetColorTexture(0.1,0.1,0.1,0.8)
    b.hpBar = hpBar

    local resBar = CreateFrame("StatusBar", nil, b)
    resBar:SetStatusBarTexture("Interface\\TARGETINGFRAME\\UI-StatusBar")
    resBar:SetSize(80, 6)
    resBar:SetPoint("RIGHT", -6, -7)
    resBar:SetMinMaxValues(0,1)
    resBar.bg = b:CreateTexture(nil, "BACKGROUND")
    resBar.bg:SetAllPoints(resBar)
    resBar.bg:SetColorTexture(0.1,0.1,0.1,0.8)
    b.resBar = resBar

    local ilvlFS = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ilvlFS:SetPoint("RIGHT", resBar, "LEFT", -6, 0)
    ilvlFS:SetText("ilvl")
    b.ilvlFS = ilvlFS

    -- Hover highlight
    b:SetScript("OnEnter", function(self)
        if not WowHealerUI:IsEnabled() then return end
        self:SetBackdropBorderColor(1,1,0.2,1)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(UnitName(self.unit) or "Unknown")
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self)
        if not WowHealerUI:IsEnabled() then return end
        self:SetBackdropBorderColor(0.2,0.2,0.2,1)
        GameTooltip:Hide()
    end)

    -- Secure unit assignment for targeting
    b:SetAttribute("unit", nil)

    return b
end

local function UpdateUnitButton(b)
    local unit = b.unit
    if not unit or not UnitExists(unit) then
        b:Hide()
        return
    end

    b:Show()

    local r,g,bl = WowHealerUI:GetClassColor(unit)
    if b.classBG then
        b.classBG:SetColorTexture(r, g, bl, 1)
    end

    -- Name in white for readability
    local name = UnitName(unit) or "Unknown"
    b.nameFS:SetText(name)
    b.nameFS:SetTextColor(1,1,1)

    -- Health
    local hp = UnitHealth(unit)
    local hpMax = UnitHealthMax(unit)
    hp = math.max(0, math.min(hp, hpMax))
    local hpPerc = hpMax > 0 and hp / hpMax or 0
    b.hpBar:SetMinMaxValues(0,1)
    b.hpBar:SetValue(hpPerc)
    b.hpBar:SetStatusBarColor(0.2, 0.8, 0.2)

    -- Resource
    local powerType = UnitPowerType(unit)
    local power = UnitPower(unit, powerType)
    local powerMax = UnitPowerMax(unit, powerType)
    local pPerc = powerMax > 0 and power / powerMax or 0
    b.resBar:SetMinMaxValues(0,1)
    b.resBar:SetValue(pPerc)
    if powerType == 0 then
        b.resBar:SetStatusBarColor(0.2, 0.4, 0.9) -- mana
    else
        b.resBar:SetStatusBarColor(0.9, 0.8, 0.2) -- others
    end

    -- iLvl (self only; inspect restricted)
    local ilvlText = "-"
    if C_PaperDollInfo and C_PaperDollInfo.GetInspectItemLevel and UnitIsPlayer(unit) then
        if UnitIsUnit(unit, "player") then
            local ok, avgItemLevel = pcall(C_PaperDollInfo.GetInspectItemLevel, unit)
            if ok and avgItemLevel and avgItemLevel > 0 then
                ilvlText = string.format("%.0f", avgItemLevel)
            end
        end
    end
    b.ilvlFS:SetText(ilvlText)

    -- Debuff highlights (safe)
    local disp = false
    local danger = false
    if WowHealerUI.IsDispellable then
        disp = WowHealerUI:IsDispellable(unit)
    end
    if WowHealerUI.IsDangerousDebuff then
        danger = WowHealerUI:IsDangerousDebuff(unit)
    end

    if danger then
        b:SetBackdropBorderColor(1, 0.5, 0, 1) -- orange
    elseif disp then
        b:SetBackdropBorderColor(1, 1, 1, 1) -- white
    else
        b:SetBackdropBorderColor(0.2,0.2,0.2,1)
    end

    -- Secure attributes to allow click targeting and mouseover casts
    b:SetAttribute("unit", unit)

    b:SetScript("OnEnter", function(self)
        if not WowHealerUI:IsEnabled() then return end
        self:SetBackdropBorderColor(1,1,0.2,1)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(UnitName(self.unit) or "Unknown")
        GameTooltip:Show()
    end)
end

local function LayoutGroup(units)
    -- Hide/reset all buttons
    for _, b in ipairs(UNIT_BUTTONS) do
        b:Hide()
        b.unit = nil
    end

    local nextIndex = 1
    local contentWidth = 0
    local contentHeight = 0

    if IsInRaid() then
        -- Build per-group buckets: only keep non-empty ones
        local groups = {}
        for _, unit in ipairs(units) do
            local g = GetRaidGroupIndex(unit)
            groups[g] = groups[g] or {}
            table.insert(groups[g], unit)
        end

        -- Gather non-empty groups in order, sort units by name inside each
        local nonEmptyGroups = {}
        for g = 1, 8 do
            if groups[g] and #groups[g] > 0 then
                table.sort(groups[g], function(a, b) return (UnitName(a) or "") < (UnitName(b) or "") end)
                table.insert(nonEmptyGroups, g)
            end
        end

        local numCols = #nonEmptyGroups
        local maxRows = 0

        for colIndex, g in ipairs(nonEmptyGroups) do
            local gu = groups[g]
            local rows = #gu
            if rows > maxRows then maxRows = rows end

            for i, unit in ipairs(gu) do
                local b = UNIT_BUTTONS[nextIndex] or CreateUnitButton(ROOT); UNIT_BUTTONS[nextIndex] = b
                b.unit = unit
                b:ClearAllPoints()
                -- Offset by padding to place content inside the frame
                b:SetPoint("TOPLEFT", ROOT, "TOPLEFT",
                        FRAME_PADDING + (colIndex - 1) * (BUTTON_WIDTH + H_SPACING),
                        -FRAME_PADDING + -(i - 1) * (BUTTON_HEIGHT + V_SPACING))
                UpdateUnitButton(b)
                nextIndex = nextIndex + 1
            end
        end

        if numCols > 0 then
            contentWidth  = numCols * BUTTON_WIDTH + (numCols - 1) * H_SPACING
        else
            contentWidth = BUTTON_WIDTH
        end

        if maxRows > 0 then
            contentHeight = maxRows * BUTTON_HEIGHT + (maxRows - 1) * V_SPACING
        else
            contentHeight = BUTTON_HEIGHT
        end
    else
        -- Solo/Party: single column sorted by role
        table.sort(units, RoleSort)
        local rows = #units
        for i, unit in ipairs(units) do
            local b = UNIT_BUTTONS[nextIndex] or CreateUnitButton(ROOT); UNIT_BUTTONS[nextIndex] = b
            b.unit = unit
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", ROOT, "TOPLEFT",
                    FRAME_PADDING,
                    -FRAME_PADDING + -(i - 1) * (BUTTON_HEIGHT + V_SPACING))
            UpdateUnitButton(b)
            nextIndex = nextIndex + 1
        end

        contentWidth = BUTTON_WIDTH
        if rows > 0 then
            contentHeight = rows * BUTTON_HEIGHT + (rows - 1) * V_SPACING
        else
            contentHeight = BUTTON_HEIGHT
        end
    end

    -- Hide any unused buttons
    for i = nextIndex, #UNIT_BUTTONS do
        UNIT_BUTTONS[i]:Hide()
    end

    -- Resize ROOT to tightly fit the content plus frame padding and border
    local totalWidth = contentWidth + FRAME_PADDING * 2
    local totalHeight = contentHeight + FRAME_PADDING * 2
    ROOT:SetSize(totalWidth, totalHeight)
end

local function RefreshAll()
    if not WowHealerUI:IsEnabled() then
        if ROOT then ROOT:Hide() end
        return
    end
    if not ROOT then return end
    ROOT:Show()
    local units = BuildUnitList()
    LayoutGroup(units)
end

-- Optional: Save/restore position helpers
local function SaveRootPosition()
    if not ROOT then return end
    local point, relativeTo, relativePoint, xOfs, yOfs = ROOT:GetPoint(1)
    WowHealerUI.db = WowHealerUI.db or {}
    WowHealerUI.db.groupViewPos = { point=point, relativePoint=relativePoint, x=xOfs, y=yOfs }
end

local function RestoreRootPosition()
    local pos = WowHealerUI.db and WowHealerUI.db.groupViewPos
    if pos then
        ROOT:ClearAllPoints()
        ROOT:SetPoint(pos.point, UIParent, pos.relativePoint, pos.x, pos.y)
    else
        ROOT:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 20, -200)
    end
end

function GroupView:OnInit()
    ROOT = CreateFrame("Frame", "WowHealerUIGroupView", UIParent, "BackdropTemplate")
    RestoreRootPosition()

    -- Surrounding frame (background + border) around the group view
    ROOT:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    ROOT:SetBackdropColor(0, 0, 0, 0.2)
    ROOT:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)
    ROOT:Show()

    -- Movable: SHIFT + Left-click drag on ROOT background
    ROOT:SetMovable(true)
    ROOT:EnableMouse(true)

    ROOT:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" and IsShiftKeyDown() then
            self:StartMoving()
            self.isMoving = true
        end
    end)
    ROOT:SetScript("OnMouseUp", function(self, button)
        if self.isMoving then
            self:StopMovingOrSizing()
            self.isMoving = false
            SaveRootPosition()
        end
    end)
    ROOT:SetScript("OnHide", function(self)
        if self.isMoving then
            self:StopMovingOrSizing()
            self.isMoving = false
            SaveRootPosition()
        end
    end)

    ROOT:RegisterEvent("GROUP_ROSTER_UPDATE")
    ROOT:RegisterEvent("PLAYER_ROLES_ASSIGNED")
    ROOT:RegisterEvent("PLAYER_ENTERING_WORLD")
    ROOT:RegisterEvent("UNIT_HEALTH")
    ROOT:RegisterEvent("UNIT_MAXHEALTH")
    ROOT:RegisterEvent("UNIT_POWER_UPDATE")
    ROOT:RegisterEvent("UNIT_MAXPOWER")
    ROOT:RegisterEvent("UNIT_AURA")
    ROOT:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    ROOT:RegisterEvent("INSPECT_READY")

    ROOT:SetScript("OnEvent", function(self, event, arg1)
        if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" or event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER" or event == "UNIT_AURA" then
            for _, b in ipairs(UNIT_BUTTONS) do
                if b.unit == arg1 then
                    UpdateUnitButton(b)
                end
            end
        else
            RefreshAll()
        end
    end)
end

function GroupView:OnLogin()
    RefreshAll()
end

function GroupView:OnEnableChanged(enabled)
    RefreshAll()
end

function GroupView:OnPlayerEnteringWorld()
    RefreshAll()
end
