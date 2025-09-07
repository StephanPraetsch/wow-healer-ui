local ADDON_NAME = ...
local WowHealerUI = _G.WowHealerUI

local GroupView = {}
WowHealerUI:RegisterModule("GroupView", GroupView)

local ROOT
local UNIT_BUTTONS = {}

-- Configuration
local BUTTON_WIDTH, BUTTON_HEIGHT = 220, 28
local H_SPACING, V_SPACING = 8, 4
local FRAME_PADDING = 6 -- padding inside the surrounding frame
local HEADER_OFFSET = 18 -- vertical space for the header

-- Sorting by role then name
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
        local raidName, _, subgroup = GetRaidRosterInfo(i)
        if raidName == unitName then
            return subgroup or 1
        end
    end
    return 1
end

local function GetUnitIlvl(unit)
    if UnitIsUnit(unit, "player") and GetAverageItemLevel then
        local overall, equipped = GetAverageItemLevel()
        if equipped and equipped > 0 then
            return math.floor(equipped + 0.5)
        end
    end
    return nil
end

local function GetGroupTitle()
    if IsInRaid() then
        return "raid"
    elseif IsInGroup() then
        return "group"
    else
        return "solo"
    end
end

-- Map UnitGroupRolesAssigned() to role icon texcoords in UI-LFG-RoleIcons
local ROLE_TEXCOORDS = {
    TANK   = { left=0.5,  right=0.75, top=0.0,  bottom=0.25 },
    HEALER = { left=0.75, right=1.0,  top=0.0,  bottom=0.25 },
    DAMAGER= { left=0.25, right=0.5,  top=0.0,  bottom=0.25 },
}

local function CreateUnitButton(parent)
    local b = CreateFrame("Button", nil, parent, "SecureActionButtonTemplate,BackdropTemplate")
    b:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)
    b:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    -- fully transparent fill; we’ll paint our own class background
    b:SetBackdropColor(0,0,0,0.0)
    b:SetBackdropBorderColor(0.2,0.2,0.2,1)

    b:RegisterForClicks("AnyDown")
    -- Interactions
    b:SetAttribute("*type1", "focus")  -- Left click: focus
    b:SetAttribute("*type2", "target") -- Right click: target
    b:SetAttribute("unit", nil)

    -- Layered visuals
    -- 1) Class background (subtle tint across entire cell)
    local classBG = b:CreateTexture(nil, "ARTWORK", nil, -8)
    classBG:SetAllPoints(true)
    classBG:SetColorTexture(1,1,1,0.20)
    b.classBG = classBG

    -- 2) HP area: a wide strip with fill bar
    local hpHeight = math.floor(BUTTON_HEIGHT * 0.6)
    local hpTopOffset = 3

    -- Dark HP background strip
    local hpBG = b:CreateTexture(nil, "ARTWORK", nil, -6)
    hpBG:SetPoint("TOPLEFT", 6, -hpTopOffset)
    hpBG:SetPoint("RIGHT", -6, 0)
    hpBG:SetHeight(hpHeight)
    hpBG:SetColorTexture(0,0,0,0.35)
    b.hpBG = hpBG

    -- HP fill (class-colored), we will adjust width by HP percentage
    local hpFill = b:CreateTexture(nil, "ARTWORK", nil, -5)
    hpFill:SetPoint("TOPLEFT", hpBG, "TOPLEFT", 0, 0)
    hpFill:SetPoint("BOTTOMLEFT", hpBG, "BOTTOMLEFT", 0, 0)
    -- width set in UpdateUnitButton based on hp %
    hpFill:SetColorTexture(0.2, 0.8, 0.2, 0.95)
    b.hpFill = hpFill

    -- Role icon (left side of the HP bar)
    local roleTex = b:CreateTexture(nil, "OVERLAY")
    roleTex:SetSize(14, 14)
    roleTex:SetPoint("LEFT", hpBG, "LEFT", 2, 0)
    roleTex:SetTexture("Interface\\LFGFrame\\UI-LFG-RoleIcons")
    b.roleTex = roleTex

    -- Name + iLvl within HP bar
    local nameFS = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    nameFS:SetPoint("LEFT", roleTex, "RIGHT", 3, 0)
    nameFS:SetText("")
    b.nameFS = nameFS

    local ilvlFS = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ilvlFS:SetPoint("RIGHT", hpBG, "RIGHT", -4, 0)
    ilvlFS:SetText("")
    b.ilvlFS = ilvlFS

    -- 3) Resource bar: thin strip below HP bar
    local resBar = CreateFrame("StatusBar", nil, b)
    resBar:SetStatusBarTexture("Interface\\TARGETINGFRAME\\UI-StatusBar")
    resBar:SetPoint("TOPLEFT", hpBG, "BOTTOMLEFT", 0, -2)
    resBar:SetPoint("RIGHT", hpBG, "RIGHT", 0, 0)
    resBar:SetHeight(math.floor(BUTTON_HEIGHT * 0.18))
    resBar:SetMinMaxValues(0,1)
    resBar:SetStatusBarColor(0.1,0.4,1.0)
    local resBG = b:CreateTexture(nil, "ARTWORK", nil, -6)
    resBG:SetPoint("TOPLEFT", resBar, "TOPLEFT", 0, 0)
    resBG:SetPoint("BOTTOMRIGHT", resBar, "BOTTOMRIGHT", 0, 0)
    resBG:SetColorTexture(0,0,0,0.35)
    b.resBar = resBar

    -- Hover highlight
    b:SetScript("OnEnter", function(self)
        if not WowHealerUI:IsEnabled() then return end
        self:SetBackdropBorderColor(1,1,0.2,1)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.unit and UnitExists(self.unit) then
            GameTooltip:SetUnit(self.unit)
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self)
        if not WowHealerUI:IsEnabled() then return end
        self:SetBackdropBorderColor(0.2,0.2,0.2,1)
        GameTooltip:Hide()
    end)

    -- Move panel by dragging any cell with Shift+Left
    b:EnableMouse(true)
    b:SetMovable(true)
    b:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" and IsShiftKeyDown() then
            ROOT:StartMoving()
            ROOT.isMoving = true
        end
    end)
    b:SetScript("OnMouseUp", function(self)
        if ROOT.isMoving then
            ROOT:StopMovingOrSizing()
            ROOT.isMoving = false
            local point, _, relativePoint, xOfs, yOfs = ROOT:GetPoint(1)
            WowHealerUI.DB.groupView = WowHealerUI.DB.groupView or {}
            WowHealerUI.DB.groupView.pos = { point=point, rel="UIParent", relPoint=relativePoint, x=xOfs, y=yOfs }
        end
    end)

    return b
end

local function UpdateRoleIcon(b, unit)
    local role = UnitGroupRolesAssigned(unit)
    if role and ROLE_TEXCOORDS[role] then
        local tc = ROLE_TEXCOORDS[role]
        b.roleTex:Show()
        b.roleTex:SetTexCoord(tc.left, tc.right, tc.top, tc.bottom)
    else
        b.roleTex:Hide()
    end
end

local function UpdateUnitButton(b)
    local unit = b.unit
    if not unit or not UnitExists(unit) then
        b:Hide()
        return
    end

    b:Show()

    -- Class color for background + HP fill tint
    local r,g,bl = WowHealerUI:GetClassColor(unit)
    b.classBG:SetColorTexture(r, g, bl, 0.20)
    b.hpFill:SetColorTexture(r * 0.85, g * 0.85, bl * 0.85, 0.95)

    -- Role icon
    UpdateRoleIcon(b, unit)

    -- Name and iLvl in the HP bar
    local name = UnitName(unit) or "Unknown"
    local ilvl = GetUnitIlvl(unit)
    b.nameFS:SetText(name)
    b.nameFS:SetTextColor(1,1,1)
    b.ilvlFS:SetText(ilvl and tostring(ilvl) or "")
    b.ilvlFS:SetTextColor(1,1,1)

    -- Health as width fill percent
    local hp = UnitHealth(unit) or 0
    local hpMax = UnitHealthMax(unit) or 1
    if hpMax <= 0 then hpMax = 1 end
    local hpPerc = hp / hpMax
    hpPerc = math.max(0, math.min(1, hpPerc))

    -- Resize hpFill to a fraction of hpBG width
    local bgWidth = b.hpBG:GetWidth() > 0 and b.hpBG:GetWidth() or (BUTTON_WIDTH - 12)
    local fillWidth = math.floor(bgWidth * hpPerc + 0.5)
    b.hpFill:ClearAllPoints()
    b.hpFill:SetPoint("TOPLEFT", b.hpBG, "TOPLEFT", 0, 0)
    b.hpFill:SetPoint("BOTTOMLEFT", b.hpBG, "BOTTOMLEFT", 0, 0)
    b.hpFill:SetWidth(fillWidth)

    -- Resource
    local ptype = UnitPowerType(unit)
    local power = UnitPower(unit, ptype) or 0
    local powerMax = UnitPowerMax(unit, ptype) or 1
    if powerMax <= 0 then powerMax = 1 end
    local pPerc = power / powerMax
    b.resBar:SetMinMaxValues(0,1)
    b.resBar:SetValue(pPerc)
    if ptype == 0 then
        b.resBar:SetStatusBarColor(0.1,0.4,1.0) -- mana
    else
        b.resBar:SetStatusBarColor(0.9,0.8,0.2) -- other resources
    end

    -- Border alerts
    local disp = WowHealerUI.IsDispellable and WowHealerUI:IsDispellable(unit)
    local danger = WowHealerUI.IsDangerousDebuff and WowHealerUI:IsDangerousDebuff(unit)
    if danger then
        b:SetBackdropBorderColor(1, 0.5, 0, 1)
    elseif disp then
        b:SetBackdropBorderColor(1, 1, 1, 1)
    else
        b:SetBackdropBorderColor(0.2,0.2,0.2,1)
    end

    -- Secure attribute for mouseover/target/focus
    b:SetAttribute("unit", unit)
end

local function LayoutGroup(units)
    for _, b in ipairs(UNIT_BUTTONS) do
        b:Hide()
        b.unit = nil
    end

    local nextIndex = 1
    local contentWidth = BUTTON_WIDTH
    local contentHeight = 0

    if IsInRaid() then
        local groups = {}
        for _, unit in ipairs(units) do
            local g = GetRaidGroupIndex(unit)
            groups[g] = groups[g] or {}
            table.insert(groups[g], unit)
        end

        local nonEmpty = {}
        for g=1,8 do
            if groups[g] and #groups[g] > 0 then
                table.sort(groups[g], RoleSort)
                table.insert(nonEmpty, g)
            end
        end

        local maxRows = 0
        for colIndex, g in ipairs(nonEmpty) do
            local list = groups[g]
            local rows = #list
            maxRows = math.max(maxRows, rows)
            for i, unit in ipairs(list) do
                local b = UNIT_BUTTONS[nextIndex] or CreateUnitButton(ROOT); UNIT_BUTTONS[nextIndex] = b
                b.unit = unit
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", ROOT, "TOPLEFT",
                        FRAME_PADDING + (colIndex - 1) * (BUTTON_WIDTH + H_SPACING),
                        -(FRAME_PADDING + HEADER_OFFSET) + -(i - 1) * (BUTTON_HEIGHT + V_SPACING))
                UpdateUnitButton(b)
                nextIndex = nextIndex + 1
            end
        end

        local numCols = #nonEmpty
        contentWidth  = math.max(BUTTON_WIDTH, numCols * BUTTON_WIDTH + math.max(0, numCols - 1) * H_SPACING)
        contentHeight = math.max(BUTTON_HEIGHT, maxRows * BUTTON_HEIGHT + math.max(0, maxRows - 1) * V_SPACING)
    else
        table.sort(units, RoleSort)
        local rows = #units
        for i, unit in ipairs(units) do
            local b = UNIT_BUTTONS[nextIndex] or CreateUnitButton(ROOT); UNIT_BUTTONS[nextIndex] = b
            b.unit = unit
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", ROOT, "TOPLEFT",
                    FRAME_PADDING,
                    -(FRAME_PADDING + HEADER_OFFSET) + -(i - 1) * (BUTTON_HEIGHT + V_SPACING))
            UpdateUnitButton(b)
            nextIndex = nextIndex + 1
        end
        contentHeight = math.max(BUTTON_HEIGHT, rows * BUTTON_HEIGHT + math.max(0, rows - 1) * V_SPACING)
    end

    for i = nextIndex, #UNIT_BUTTONS do
        UNIT_BUTTONS[i]:Hide()
    end

    local totalWidth = contentWidth + FRAME_PADDING * 2
    local totalHeight = contentHeight + FRAME_PADDING * 2 + HEADER_OFFSET
    ROOT:SetSize(totalWidth, totalHeight)
end

local function RefreshAll()
    if not ROOT then return end
    if not WowHealerUI:IsEnabled() then
        ROOT:Hide()
        return
    end
    ROOT:Show()

    -- Update header
    if ROOT.headerFS then
        ROOT.headerFS:SetText(GetGroupTitle())
    end

    local units = BuildUnitList()
    LayoutGroup(units)
end

function GroupView:OnInit()
    ROOT = CreateFrame("Frame", "WowHealerUIGroupView", UIParent, "BackdropTemplate")
    ROOT:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    ROOT:SetBackdropColor(0, 0, 0, 0.2)
    ROOT:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)
    ROOT:SetClampedToScreen(true)
    ROOT:SetMovable(true)
    ROOT:EnableMouse(true)

    -- Header title
    local headerFS = ROOT:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    headerFS:SetPoint("TOPLEFT", 8, -6)
    headerFS:SetText("")
    ROOT.headerFS = headerFS

    -- Restore position
    local pos = WowHealerUI.DB and WowHealerUI.DB.groupView and WowHealerUI.DB.groupView.pos
    if pos then
        ROOT:ClearAllPoints()
        ROOT:SetPoint(pos.point or "TOPLEFT", UIParent, pos.relPoint or "TOPLEFT", pos.x or 20, pos.y or -200)
    else
        ROOT:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 20, -200)
    end

    -- Drag the whole panel with Shift+Left on the background
    ROOT:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" and IsShiftKeyDown() then
            self:StartMoving()
            self.isMoving = true
        end
    end)
    ROOT:SetScript("OnMouseUp", function(self)
        if self.isMoving then
            self:StopMovingOrSizing()
            self.isMoving = false
            local point, _, relativePoint, xOfs, yOfs = self:GetPoint(1)
            WowHealerUI.DB.groupView = WowHealerUI.DB.groupView or {}
            WowHealerUI.DB.groupView.pos = { point=point, rel="UIParent", relPoint=relativePoint, x=xOfs, y=yOfs }
        end
    end)

    -- Events
    ROOT:RegisterEvent("PLAYER_ENTERING_WORLD")
    ROOT:RegisterEvent("GROUP_ROSTER_UPDATE")
    ROOT:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    ROOT:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    ROOT:RegisterEvent("ROLE_CHANGED_INFORM")
    ROOT:RegisterEvent("UNIT_HEALTH")
    ROOT:RegisterEvent("UNIT_MAXHEALTH")
    ROOT:RegisterEvent("UNIT_POWER_UPDATE")
    ROOT:RegisterEvent("UNIT_MAXPOWER")
    ROOT:RegisterEvent("UNIT_INVENTORY_CHANGED")

    ROOT:SetScript("OnEvent", function(self, event, arg1)
        if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" or event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER" then
            for _, b in ipairs(UNIT_BUTTONS) do
                if b:IsShown() and b.unit == arg1 then
                    UpdateUnitButton(b)
                end
            end
        else
            RefreshAll()
        end
    end)

    if WowHealerUI:IsEnabled() then ROOT:Show() else ROOT:Hide() end
    C_Timer.After(0, RefreshAll)
end

function GroupView:OnLogin()
    if WowHealerUI:IsEnabled() then ROOT:Show() else ROOT:Hide() end
    RefreshAll()
end

function GroupView:OnEnableChanged(enabled)
    if enabled then
        ROOT:Show()
        RefreshAll()
    else
        ROOT:Hide()
    end
end
