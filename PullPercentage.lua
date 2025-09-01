local function IsInMythicPlus()
    local inInstance, instType = IsInInstance()
    if not inInstance or instType ~= "party" then return false end
    local _, _, difficulty = GetInstanceInfo()
    return difficulty == 8
end

local function ReadForcesPercent()
    if type(C_Scenario) ~= "table" or type(C_Scenario.GetCriteriaInfo) ~= "function" then
        return 0
    end

    -- Try to find the Enemy Forces criteria; fall back to first with a valid total
    local quantity, totalQuantity = 0, 1
    local found = false

    -- Prefer explicit forces criteria
    for i = 1, 20 do
        local ok, name, _, _, q, tq = pcall(C_Scenario.GetCriteriaInfo, i)
        if not ok or not name then break end
        if type(tq) == "number" and tq > 0 then
            if type(name) == "string" and (name:find("Enemy Forces") or name:find("Forces")) then
                quantity = (type(q) == "number" and q) or 0
                totalQuantity = tq
                found = true
                break
            end
        end
    end

    -- Fallback: first criteria with total > 0
    if not found then
        for i = 1, 20 do
            local ok, name, _, _, q, tq = pcall(C_Scenario.GetCriteriaInfo, i)
            if not ok or not name then break end
            if type(tq) == "number" and tq > 0 then
                quantity = (type(q) == "number" and q) or 0
                totalQuantity = tq
                break
            end
        end
    end

    if totalQuantity <= 0 then totalQuantity = 1 end
    local pct = (quantity / totalQuantity) * 100
    if pct < 0 then pct = 0 end
    if pct > 100 then pct = 100 end
    return pct
end

function ProgressPercentage()
    if not IsInMythicPlus() then
        return string.format("%.2f%%", 0)
    end
    local pct = ReadForcesPercent()
    return string.format("%.2f%%", pct)
end
