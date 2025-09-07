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

-- ============================================================
-- Role icon support (robust: atlas + texcoord fallback)
-- ============================================================

-- Detect whether SetAtlas("RoleIcon-Tank") is available
local function WowUI_HasRoleAtlases()
    local tex = UIParent:CreateTexture(nil, "OVERLAY")
    local ok = pcall(tex.SetAtlas, tex, "RoleIcon-Tank", true)
    tex:Hide()
    tex:SetTexture(nil)
    return ok
end
local USE_ROLE_ATLASES = WowUI_HasRoleAtlases()

-- Fallback texcoords for UI-LFG-RoleIcons
local ROLE_TEXCOORDS = {
    TANK   = { left=0.5,  right=0.75, top=0.0,  bottom=0.25 },
    HEALER = { left=0.75, right=1.0,  top=0.0,  bottom=0.25 },
    DAMAGER= { left=0.25, right=0.5,  top=0.0,  bottom=0.25 },
    DPS    = { left=0.25, right=0.5,  top=0.0,  bottom=0.25 },
}

-- Hard-forced sprite sheet + coords to guarantee a visible icon
local function SetRoleIconTexture(tex, role)
    if not tex then return false end
    if role == "DAMAGER" then role = "DPS" end

    tex:SetAlpha(1)
    tex:SetDrawLayer("OVERLAY", 4)
    tex:Show()

    -- Clear any prior atlas state before switching
    tex:SetAtlas(nil)

    -- Preferred: the tiny role atlases used by Blizzard party/raid frames
    local ok = false
    if role == "TANK" then
        ok = pcall(tex.SetAtlas, tex, "RoleIcon-Tiny-Tank", true)
    elseif role == "HEALER" then
        ok = pcall(tex.SetAtlas, tex, "RoleIcon-Tiny-Healer", true)
    elseif role == "DPS" then
        ok = pcall(tex.SetAtlas, tex, "RoleIcon-Tiny-DPS", true)
    end
    if ok then return true end

    -- Fallback: larger atlases (if Tiny not present)
    if role == "TANK" then
        ok = pcall(tex.SetAtlas, tex, "RoleIcon-Tank", true)
    elseif role == "HEALER" then
        ok = pcall(tex.SetAtlas, tex, "RoleIcon-Healer", true)
    elseif role == "DPS" then
        ok = pcall(tex.SetAtlas, tex, "RoleIcon-DPS", true)
    end
    if ok then return true end

    -- Final fallback: sprite sheet
    if role == "DPS" then
        tex:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-ROLES")
        tex:SetTexCoord(0.00, 0.25, 0.00, 0.25)
        return true
    elseif role == "TANK" then
        tex:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-ROLES")
        tex:SetTexCoord(0.25, 0.50, 0.00, 0.25)
        return true
    elseif role == "HEALER" then
        tex:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-ROLES")
        tex:SetTexCoord(0.50, 0.75, 0.00, 0.25)
        return true
    end

    tex:SetTexture(nil)
    tex:Hide()
    return false
end

-- Fallback: derive role from specialization if the assigned role is NONE/unknown
local function GetEffectiveUnitRole(unit)
    local role = UnitGroupRolesAssigned(unit)
    if role and role ~= "NONE" then
        return role
    end

    -- Player spec role
    if UnitIsUnit(unit, "player") then
        local getSpec = _G.GetSpecialization
        local getRole = _G.GetSpecializationRole
        if getSpec and getRole then
            local spec = getSpec()
            if spec then
                local r = getRole(spec)
                if r == "TANK" or r == "HEALER" or r == "DAMAGER" then
                    return r
                end
            end
        end
        return "NONE"
    end

    -- Party/Raid: try inspect spec role (only works when inspect data is available)
    local getInspectSpec = _G.GetInspectSpecialization
    local getSpecInfoByID = _G.GetSpecializationInfoByID
    if getInspectSpec and getSpecInfoByID then
        local specID = getInspectSpec(unit)
        if specID and specID > 0 then
            local _, _, _, _, _, roleToken = getSpecInfoByID(specID)
            if roleToken == "TANK" or roleToken == "HEALER" or roleToken == "DAMAGER" then
                return roleToken
            end
        end
    end

    return "NONE"
end

-- ============================================================
-- Sorting by role then name
-- ============================================================
local function RoleSort(u1, u2)
    local prio = { TANK=1, HEALER=2, DAMAGER=3, DPS=3, NONE=4 }
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
    local ilvl = WowHealerUI.ItemLevel and WowHealerUI.ItemLevel:GetIlvl(unit)
    if ilvl then return math.floor(ilvl + 0.5) end
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

-- ============================================================
-- Raider.IO helpers (optional)
-- ============================================================
local function GetUnitFullName(unit)
    local name, realm = UnitName(unit)
    if not name then return nil end
    if not realm or realm == "" then
        realm = GetRealmName()
    end
    return name.."-"..realm:gsub("%s+", "")
end

local function GetRaiderIOScore(unit)
    if not _G.RaiderIO then return nil end

    if type(RaiderIO.GetScore) == "function" then
        local ok, score = pcall(RaiderIO.GetScore, unit)
        if ok and type(score) == "number" then return score end
    end

    if type(RaiderIO.GetProfile) == "function" then
        local ok, profile = pcall(RaiderIO.GetProfile, unit)
        if ok and type(profile) == "table" and type(profile.mythicKeystoneProfile) == "table" then
            local score = profile.mythicKeystoneProfile and profile.mythicKeystoneProfile.currentScore
            if type(score) == "number" then return score end
        end
        local fullname = GetUnitFullName(unit)
        if fullname then
            local ok2, profile2 = pcall(RaiderIO.GetProfile, fullname)
            if ok2 and type(profile2) == "table" and type(profile2.mythicKeystoneProfile) == "table" then
                local score2 = profile2.mythicKeystoneProfile and profile2.mythicKeystoneProfile.currentScore
                if type(score2) == "number" then return score2 end
            end
        end
    end

    return nil
end

-- Colorize score like Raider.IO simple thresholds
local function ColorForRio(score)
    if not score or score <= 0 then return 0.7, 0.7, 0.7 end           -- gray
    if score < 1000 then return 0.2, 1.0, 0.2 end                       -- green
    if score < 1500 then return 0.2, 0.6, 1.0 end                       -- blue
    if score < 2200 then return 0.7, 0.4, 1.0 end                        -- purple
    return 1.0, 0.6, 0.2                                                -- orange
end

-- ============================================================
-- Range helper + throttle for live updates
-- ============================================================
local function IsUnitInRange(unit)
    local inRange, checked = UnitInRange(unit)
    if checked == false then
        return true -- avoid initial flicker
    end
    return inRange == true
end

local RANGE_THROTTLE = 0.2
local rangeTickerElapsed = 0

-- ============================================================
-- UI: Create and update unit button
-- ============================================================
local function CreateUnitButton(parent)
    local b = CreateFrame("Button", nil, parent, "SecureActionButtonTemplate,BackdropTemplate")
    b:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)
    b:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    b:SetBackdropColor(0,0,0,0.0)
    b:SetBackdropBorderColor(0.2,0.2,0.2,1)

    b:RegisterForClicks("AnyDown")
    b:SetAttribute("*type1", "target")
    b:SetAttribute("unit", nil)

    -- Class background
    local classBG = b:CreateTexture(nil, "ARTWORK", nil, -8)
    classBG:SetAllPoints(true)
    classBG:SetColorTexture(1,1,1,0.20)
    b.classBG = classBG

    -- HP strip
    local hpHeight = math.floor(BUTTON_HEIGHT * 0.6)
    local hpTopOffset = 3
    local hpBG = b:CreateTexture(nil, "ARTWORK", nil, -6)
    hpBG:SetPoint("TOPLEFT", 6, -hpTopOffset)
    hpBG:SetPoint("RIGHT", -6, 0)
    hpBG:SetHeight(hpHeight)
    hpBG:SetColorTexture(0,0,0,0.35)
    b.hpBG = hpBG

    local hpFill = b:CreateTexture(nil, "ARTWORK", nil, -5)
    hpFill:SetPoint("TOPLEFT", hpBG, "TOPLEFT", 0, 0)
    hpFill:SetPoint("BOTTOMLEFT", hpBG, "BOTTOMLEFT", 0, 0)
    hpFill:SetColorTexture(0.2, 0.8, 0.2, 0.95)
    b.hpFill = hpFill

    -- Absorb overlay
    local absorbFill = b:CreateTexture(nil, "OVERLAY", nil, -4)
    absorbFill:SetPoint("TOPLEFT", hpBG, "TOPLEFT", 0, 0)
    absorbFill:SetPoint("BOTTOMLEFT", hpBG, "BOTTOMLEFT", 0, 0)
    absorbFill:SetColorTexture(1, 1, 1, 0.55)
    absorbFill:Hide()
    b.absorbFill = absorbFill

    local absorbEdge = b:CreateTexture(nil, "OVERLAY", nil, -3)
    absorbEdge:SetSize(1, hpHeight)
    absorbEdge:SetColorTexture(1, 1, 1, 0.7)
    absorbEdge:Hide()
    b.absorbEdge = absorbEdge

    -- Role icon (above the backdrop)
    local roleTex = b:CreateTexture(nil, "OVERLAY", nil, 5)
    roleTex:SetSize(16, 16)
    roleTex:SetPoint("LEFT", hpBG, "LEFT", 1, 0)
    roleTex:SetAlpha(1)
    b.roleTex = roleTex

    -- Name
    local nameFS = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    nameFS:SetPoint("LEFT", roleTex, "RIGHT", 3, 0)
    nameFS:SetText("")
    b.nameFS = nameFS

    -- Right-side text
    local rightFS = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    rightFS:SetPoint("RIGHT", hpBG, "RIGHT", -4, 0)
    rightFS:SetText("")
    b.rightFS = rightFS

    -- Dispellable debuff counter (small square + count)
    local dispFrame = CreateFrame("Frame", nil, b)
    dispFrame:SetSize(16, 16)
    dispFrame:SetPoint("RIGHT", b.hpBG, "RIGHT", -2, 0)
    dispFrame:Hide()
    b.dispFrame = dispFrame

    local dispTex = dispFrame:CreateTexture(nil, "OVERLAY")
    dispTex:SetAllPoints(true)
    -- Default to a generic debuff-looking square; we’ll color by type
    dispTex:SetTexture("Interface\\Buttons\\WHITE8x8")
    dispTex:SetVertexColor(0.6, 0, 0, 0.9) -- red-ish default
    b.dispTex = dispTex

    local dispCountFS = dispFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    dispCountFS:SetPoint("CENTER", dispFrame, "CENTER", 0, 0)
    dispCountFS:SetText("")
    b.dispCountFS = dispCountFS

    -- Resource bar
    local resBar = CreateFrame("StatusBar", nil, b)
    resBar:SetStatusBarTexture("Interface\\TARGETINGFRAME\\UI-StatusBar")
    resBar:SetPoint("TOPLEFT", hpBG, "BOTTOMLEFT", 0, -2)
    resBar:SetPoint("RIGHT", hpBG, "RIGHT", 0, 0)
    resBar:SetHeight(math.floor(BUTTON_HEIGHT * 0.18))
    resBar:SetMinMaxValues(0,1)
    local resBG = b:CreateTexture(nil, "ARTWORK", nil, -6)
    resBG:SetPoint("TOPLEFT", resBar, "TOPLEFT", 0, 0)
    resBG:SetPoint("BOTTOMRIGHT", resBar, "BOTTOMRIGHT", 0, 0)
    resBG:SetColorTexture(0,0,0,1)
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

    -- Dragging
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
    if not unit or not UnitExists(unit) then
        b.roleTex:SetTexture(nil)
        b.roleTex:Hide()
        if b.roleBG then b.roleBG:Hide() end
        return
    end
    if b.roleBG then b.roleBG:Show() end
    local role = GetEffectiveUnitRole(unit) or "NONE"
    if not SetRoleIconTexture(b.roleTex, role) then
        b.roleTex:SetTexture(nil)
        b.roleTex:Hide()
    end
end

-- 1) Iterator
local function ForEachDebuff(unit, cb)
    print("ITER for", unit, "C_UnitAuras?", C_UnitAuras and "yes" or "no",
            "GetDebuffDataByIndex?", C_UnitAuras and (C_UnitAuras.GetDebuffDataByIndex and "yes" or "no") or "n/a")
    if C_UnitAuras and C_UnitAuras.GetDebuffDataByIndex then
        print("PATH: C_UnitAuras")
        for i = 1, 40 do
            local aura = C_UnitAuras.GetDebuffDataByIndex(unit, i)
            if not aura or not aura.name then break end
            local name       = aura.name
            local icon       = aura.icon
            local count      = aura.applications or aura.charges or aura.stackCount or 0
            local dispelType = aura.dispelName  -- IMPORTANT on Retail
            local duration   = aura.duration
            local expires    = aura.expirationTime
            local spellId    = aura.spellId
            local bossAura   = aura.isBossAura
            local continue = cb(name, icon, count, dispelType, duration, expires, spellId, bossAura, aura)
            print("DBG", UnitName(unit), name, spellId, "dispelType=", tostring(dispelType), continue)
            if continue == false then break end
        end
        return
    end

    if UnitDebuff then
        print("PATH: UnitDebuff")
        for i = 1, 40 do
            local name, icon, count, dispelType, duration, expires, caster, isStealable, nameplateShowPersonal, spellId =
            UnitDebuff(unit, i)
            if not name then break end
            local continue = cb(name, icon, count or 0, dispelType, duration, expires, spellId, false, nil)
            if continue == false then break end
        end
    else
        print("PATH: none")
    end
end

-- Colors for known dispel types; nil type gets neutral
local DEBUFF_COLORS = {
    Magic   = {0.2, 0.6, 1.0},
    Curse   = {0.6, 0.2, 1.0},
    Disease = {0.6, 0.9, 0.2},
    Poison  = {0.0, 0.9, 0.4},
    NONE    = {0.8, 0.2, 0.2}, -- neutral red-ish for non-dispellable/unknown
}

-- Count ALL debuffs on unit. If any has a dispel type, use the first one for color.
local function GetAllDebuffCountAndColor(unit)
    if not unit or not UnitExists(unit) then return 0, unpack(DEBUFF_COLORS.NONE) end

    local total = 0
    local reprType = nil

    if C_UnitAuras and C_UnitAuras.GetDebuffDataByIndex then
        for i=1,40 do
            local a = C_UnitAuras.GetDebuffDataByIndex(unit, i)
            if not a or not a.name then break end
            total = total + 1
            if not reprType and a.dispelName then
                reprType = a.dispelName
            end
        end
    elseif UnitDebuff then
        for i=1,40 do
            local name, _, _, dispelType = UnitDebuff(unit, i)
            if not name then break end
            total = total + 1
            if not reprType and dispelType then
                reprType = dispelType
            end
        end
    end

    local c = DEBUFF_COLORS[reprType or "NONE"] or DEBUFF_COLORS.NONE
    return total, c[1], c[2], c[3]
end

-- 2) Counter
local DISPEL_COLORS = {
    Magic   = {0.2, 0.6, 1.0},
    Curse   = {0.6, 0.2, 1.0},
    Disease = {0.6, 0.9, 0.2},
    Poison  = {0.0, 0.9, 0.4},
}

local CLASS_DISPELS = {
    PRIEST  = { Magic=true, Disease=true },
    SHAMAN  = { Magic=true, Curse=true },
    PALADIN = { Magic=true, Disease=true, Poison=true },
    DRUID   = { Magic=true, Curse=true, Poison=true },
    MONK    = { Magic=true, Disease=true, Poison=true },
    EVOKER  = { Magic=true, Curse=true, Poison=true },
}

local function GetDispellableCountAndColor(unit)
    if not unit or not UnitExists(unit) then return 0 end
    local _, playerClass = UnitClass("player")
    local allowed = CLASS_DISPELS[playerClass or ""]
    if not allowed then return 0 end

    local total, reprType = 0, nil
    ForEachDebuff(unit, function(_, _, _, dispelType)
        if dispelType and allowed[dispelType] then
            total = total + 1
            reprType = reprType or dispelType
        end
    end)

    if total > 0 and reprType and DISPEL_COLORS[reprType] then
        local c = DISPEL_COLORS[reprType]
        return total, c[1], c[2], c[3]
    end
    return total, 0.6, 0.0, 0.0
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

    -- Name
    local name = UnitName(unit) or "Unknown"
    b.nameFS:SetText(name)
    b.nameFS:SetTextColor(1,1,1)

    -- Right text: ilvl and rio (with colored rio)
    local ilvl = GetUnitIlvl(unit)
    local rio = GetRaiderIOScore(unit)
    local ilvlText = ilvl and tostring(ilvl) or "-"
    local rioText = rio and tostring(math.floor(rio + 0.5)) or "-"
    if rio then
        local cr, cg, cb = ColorForRio(rio)
        local function hex(x) return string.format("%02X", math.floor(x * 255 + 0.5)) end
        local colRio = "|cff" .. hex(cr) .. hex(cg) .. hex(cb) .. rioText .. "|r"
        local colIlvl = "|cffffffff" .. ilvlText .. "|r"
        b.rightFS:SetText(colIlvl .. "  " .. colRio)
    else
        b.rightFS:SetText(ilvlText .. "  " .. rioText)
        b.rightFS:SetTextColor(1,1,1)
    end

    -- Health percent
    local hp = UnitHealth(unit) or 0
    local hpMax = UnitHealthMax(unit) or 1
    if hpMax <= 0 then hpMax = 1 end
    local hpPerc = hp / hpMax
    hpPerc = math.max(0, math.min(1, hpPerc))

    -- Resize hpFill to a fraction of hpBG width
    local bgWidth = b.hpBG:GetWidth() > 0 and b.hpBG:GetWidth() or (BUTTON_WIDTH - 12)
    local hpWidth = math.floor(bgWidth * hpPerc + 0.5)
    b.hpFill:ClearAllPoints()
    b.hpFill:SetPoint("TOPLEFT", b.hpBG, "TOPLEFT", 0, 0)
    b.hpFill:SetPoint("BOTTOMLEFT", b.hpBG, "BOTTOMLEFT", 0, 0)
    b.hpFill:SetWidth(hpWidth)

    -- Absorbs overlay
    local absorbs = UnitGetTotalAbsorbs and UnitGetTotalAbsorbs(unit) or 0
    if absorbs and absorbs > 0 then
        local absPerc = absorbs / hpMax
        local absWidth = math.floor(bgWidth * absPerc + 0.5)
        local startX = hpWidth
        if startX < bgWidth and absWidth > 0 then
            if startX + absWidth > bgWidth then
                absWidth = bgWidth - startX
            end
            b.absorbFill:SetColorTexture(math.min(1, r + 0.25), math.min(1, g + 0.25), math.min(1, bl + 0.25), 0.55)
            b.absorbFill:ClearAllPoints()
            b.absorbFill:SetPoint("TOPLEFT", b.hpBG, "TOPLEFT", startX, 0)
            b.absorbFill:SetPoint("BOTTOMLEFT", b.hpBG, "BOTTOMLEFT", startX, 0)
            b.absorbFill:SetWidth(absWidth)
            b.absorbFill:Show()

            b.absorbEdge:ClearAllPoints()
            b.absorbEdge:SetPoint("TOPLEFT", b.hpBG, "TOPLEFT", startX - 1, 0)
            b.absorbEdge:SetPoint("BOTTOMLEFT", b.hpBG, "BOTTOMLEFT", startX - 1, 0)
            b.absorbEdge:Show()
        else
            b.absorbFill:Hide()
            b.absorbEdge:Hide()
        end
    else
        b.absorbFill:Hide()
        b.absorbEdge:Hide()
    end

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

    -- Debuff indicator: show count of ALL debuffs; color by type if present, else neutral
    if b.dispFrame and b.dispTex and b.dispCountFS then
        local cnt, cr, cg, cb = GetAllDebuffCountAndColor(unit)
        if cnt and cnt > 0 then
            b.dispTex:SetVertexColor(cr, cg, cb, 0.95)
            b.dispCountFS:SetText(tostring(cnt))
            b.dispFrame:Show()
        else
            b.dispFrame:Hide()
        end
    end

    -- Grey out when out of range (initial/event-driven application)
    local inRange = IsUnitInRange(unit)
    local alphaIn, alphaOut = 1.0, 0.45

    if inRange then
        b:SetAlpha(alphaIn)
        b.nameFS:SetTextColor(1, 1, 1)
        b.rightFS:SetAlpha(1)
        b.classBG:SetAlpha(0.20)
        b.hpBG:SetColorTexture(0,0,0,0.35)
        if b.resBar then b.resBar:SetAlpha(1) end
        if b.roleTex then b.roleTex:SetAlpha(1) end
        if b.absorbFill then b.absorbFill:SetAlpha(0.55) end
        if b.absorbEdge then b.absorbEdge:SetAlpha(0.7) end
        if b.dispFrame then b.dispFrame:SetAlpha(1) end
    else
        b:SetAlpha(alphaOut)
        b.nameFS:SetTextColor(0.7, 0.7, 0.7)
        b.rightFS:SetAlpha(0.7)
        b.classBG:SetAlpha(0.12)
        b.hpBG:SetColorTexture(0,0,0,0.25)
        if b.resBar then b.resBar:SetAlpha(0.6) end
        if b.roleTex then b.roleTex:SetAlpha(0.6) end
        if b.absorbFill then b.absorbFill:SetAlpha(0.35) end
        if b.absorbEdge then b.absorbEdge:SetAlpha(0.45) end
        if b.dispFrame then b.dispFrame:SetAlpha(0.7) end
    end
end

-- ============================================================
-- Layout and refresh
-- ============================================================
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

    if ROOT.headerFS then
        ROOT.headerFS:SetText(GetGroupTitle())
    end

    local units = BuildUnitList()
    LayoutGroup(units)
end

-- ============================================================
-- Lifecycle and events
-- ============================================================
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
    ROOT:RegisterEvent("UNIT_AURA")

    ROOT:SetScript("OnEvent", function(self, event, arg1)
        if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" or event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER" then
            for _, b in ipairs(UNIT_BUTTONS) do
                if b:IsShown() and b.unit == arg1 then
                    UpdateUnitButton(b)
                end
            end
        elseif event == "UNIT_AURA" then
            for _, b in ipairs(UNIT_BUTTONS) do
                if b:IsShown() and b.unit == arg1 then
                    UpdateUnitButton(b)
                end
            end
        else
            -- For roster/spec/role changes, ensure icons refresh quickly
            if event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_SPECIALIZATION_CHANGED" or event == "ROLE_CHANGED_INFORM" or event == "PLAYER_ENTERING_WORLD" then
                for _, b in ipairs(UNIT_BUTTONS) do
                    if b:IsShown() and b.unit then
                        UpdateRoleIcon(b, b.unit)
                    end
                end
            end
            RefreshAll()
        end
    end)

    -- Live range ticker (smooth grey in/out while moving)
    ROOT:SetScript("OnUpdate", function(self, elapsed)
        rangeTickerElapsed = rangeTickerElapsed + elapsed
        if rangeTickerElapsed < RANGE_THROTTLE then return end
        rangeTickerElapsed = 0

        for _, b in ipairs(UNIT_BUTTONS) do
            if b:IsShown() and b.unit and UnitExists(b.unit) then
                local inRange = IsUnitInRange(b.unit)
                local alphaIn, alphaOut = 1.0, 0.45

                if inRange then
                    if b:GetAlpha() ~= alphaIn then
                        b:SetAlpha(alphaIn)
                        b.nameFS:SetTextColor(1, 1, 1)
                        b.rightFS:SetAlpha(1)
                        b.classBG:SetAlpha(0.20)
                        b.hpBG:SetColorTexture(0,0,0,0.35)
                        if b.resBar then b.resBar:SetAlpha(1) end
                        if b.roleTex then b.roleTex:SetAlpha(1) end
                        if b.absorbFill then b.absorbFill:SetAlpha(0.55) end
                        if b.absorbEdge then b.absorbEdge:SetAlpha(0.7) end
                    end
                else
                    if b:GetAlpha() ~= alphaOut then
                        b:SetAlpha(alphaOut)
                        b.nameFS:SetTextColor(0.7, 0.7, 0.7)
                        b.rightFS:SetAlpha(0.7)
                        b.classBG:SetAlpha(0.12)
                        b.hpBG:SetColorTexture(0,0,0,0.25)
                        if b.resBar then b.resBar:SetAlpha(0.6) end
                        if b.roleTex then b.roleTex:SetAlpha(0.6) end
                        if b.absorbFill then b.absorbFill:SetAlpha(0.35) end
                        if b.absorbEdge then b.absorbEdge:SetAlpha(0.45) end
                    end
                end
            end
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
