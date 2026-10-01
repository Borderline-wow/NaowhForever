-------------------------------------------------------------------------------
--  NaowhForever_EquipmentReminder.lua -- the QoL equipment reminder: your trinkets, weapons and
--  enchants in a window on entering an instance or on a ready check.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.QoLSettings
local T = ns.THEME

local SHOWN_SLOTS = {
    { id = 13, name = "Trinket 1" }, { id = 14, name = "Trinket 2" },
    { id = 16, name = "Main Hand" }, { id = 17, name = "Off Hand" }, { id = 18, name = "Ranged" },
}
local ENCHANT_SLOTS = {
    [1] = "Head", [2] = "Neck", [3] = "Shoulder", [5] = "Chest", [6] = "Waist", [7] = "Legs",
    [8] = "Feet", [9] = "Wrist", [10] = "Hands", [11] = "Ring 1", [12] = "Ring 2", [15] = "Back",
    [16] = "Main Hand", [17] = "Off Hand", [18] = "Ranged",
}
local SPACING = 6

local frame, hideTimer
local buttons = {}

local function On()
    return S.Get("enabled") and S.Get("equipReminder")
end

local function EnchantName(slot)
    local data = C_TooltipInfo.GetInventoryItem("player", slot)
    for _, line in ipairs(data and data.lines or {}) do
        if line.type == Enum.TooltipDataLineType.ItemEnchantmentPermanent then
            local text = line.leftText
            text = text:match("Enchanted: (.+)") or text
            return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|A.-|a", ""))
        end
    end
end

-- The enchants on your gear now become the ones expected from then on.
function ns.CaptureEnchants()
    local rules, count = {}, 0
    for slot in pairs(ENCHANT_SLOTS) do
        local name = GetInventoryItemID("player", slot) and EnchantName(slot)
        if name then
            rules[slot] = name
            count = count + 1
        end
    end
    S.Set("equipEnchantRules", rules)
    return count
end

local function EnchantIssues()
    local issues = {}
    for slot, expected in pairs(S.Get("equipEnchantRules")) do
        if GetInventoryItemID("player", slot) then
            local have = EnchantName(slot)
            if have ~= expected then
                issues[#issues + 1] = { slot = ENCHANT_SLOTS[slot] or ("Slot " .. slot), have = have,
                    expected = expected }
            end
        end
    end
    table.sort(issues, function(a, b) return a.slot < b.slot end)
    return issues
end

local function SlotButton(slot)
    local b = CreateFrame("Button", nil, frame)
    b.slot = slot
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.border = ns.Border(b)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        if GetInventoryItemID("player", self.slot.id) then
            GameTooltip:SetInventoryItem("player", self.slot.id)
        else
            GameTooltip:SetText(self.slot.name .. " - Empty")
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    return b
end

local function Build()
    frame = CreateFrame("Frame", "NaowhForeverEquipmentReminder", UIParent)
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        S.Set("equipPos", { point = point, relPoint = relPoint, x = x, y = y })
    end)
    ns.Solid(frame, "BACKGROUND", T.bg, 0.95):SetAllPoints()
    ns.Border(frame, T.accent)

    local title = ns.Font(frame, 13, nil, T.accent)
    title:SetPoint("TOP", 0, -8)
    title:SetText("Equipment Check")

    local close = ns.Button(frame, "X", 18, 18, function()
        frame:Hide()
        if hideTimer then hideTimer:Cancel(); hideTimer = nil end
    end)
    close:SetPoint("TOPRIGHT", -4, -4)

    for i, slot in ipairs(SHOWN_SLOTS) do buttons[i] = SlotButton(slot) end

    frame.status = CreateFrame("Frame", nil, frame)
    frame.status:SetSize(200, 18)
    frame.status:SetPoint("BOTTOM", 0, 6)
    frame.status:EnableMouse(true)
    frame.status.text = ns.Font(frame.status, 12)
    frame.status.text:SetPoint("CENTER")
    frame.status:SetScript("OnEnter", function(self)
        if not self.issues or #self.issues == 0 then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Enchant Issues", 1, 0.4, 0.4)
        for _, issue in ipairs(self.issues) do
            GameTooltip:AddDoubleLine(issue.slot .. ":", issue.have and "Wrong Enchant" or "Missing",
                1, 1, 1, 1, 0.5, 0.3)
            if issue.have then GameTooltip:AddDoubleLine("  Have:", issue.have, 0.6, 0.6, 0.6, 1, 0.5, 0.5) end
            GameTooltip:AddDoubleLine("  Expected:", issue.expected, 0.6, 0.6, 0.6, 0.5, 0.8, 0.5)
        end
        GameTooltip:Show()
    end)
    frame.status:SetScript("OnLeave", GameTooltip_Hide)
    frame:Hide()
end

local function Refresh()
    local size = S.Get("equipIconSize")
    local width = #SHOWN_SLOTS * size + (#SHOWN_SLOTS - 1) * SPACING
    for i, b in ipairs(buttons) do
        b:SetSize(size, size)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", frame, "TOP", -width / 2 + (i - 1) * (size + SPACING), -30)
        local texture = GetInventoryItemTexture("player", b.slot.id)
        b.icon:SetTexture(texture)
        local quality = texture and GetInventoryItemQuality("player", b.slot.id)
        if quality then
            local r, g, bl = C_Item.GetItemQualityColor(quality)
            b.border:SetColor(r, g, bl)
        else
            b.border:SetColor(0, 0, 0)
        end
    end

    local enchants = S.Get("equipEnchants")
    frame.status:SetShown(enchants)
    if enchants then
        local issues = EnchantIssues()
        frame.status.issues = issues
        if #issues == 0 then
            frame.status.text:SetText("|cff4dd17aEnchants OK|r")
        else
            frame.status.text:SetText(("|cffff6666%d Enchant Issue%s|r"):format(#issues, #issues > 1 and "s" or ""))
        end
    end
    frame:SetSize(math.max(200, width + 20), size + (enchants and 66 or 44))
end

local function Place()
    local pos = S.Get("equipPos")
    frame:ClearAllPoints()
    if pos then
        frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
    end
end

function ns.ShowEquipmentReminder()
    if InCombatLockdown() then return end
    if not frame then Build() end
    Place()
    Refresh()
    frame:Show()
    if hideTimer then hideTimer:Cancel(); hideTimer = nil end
    local delay = S.Get("equipAutoHide")
    if delay > 0 then
        hideTimer = C_Timer.NewTimer(delay, function()
            hideTimer = nil
            frame:Hide()
        end)
    end
end

local function ShowSoon(delay)
    C_Timer.After(delay, function()
        if On() and not InCombatLockdown() then ns.ShowEquipmentReminder() end
    end)
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, arg)
    if event == "PLAYER_ENTERING_WORLD" then
        local inInstance, kind = IsInInstance()
        if inInstance and (kind == "party" or kind == "raid") and S.Get("equipOnInstance") then ShowSoon(1) end
    elseif event == "READY_CHECK" then
        if S.Get("equipOnReadyCheck") then ShowSoon(0.2) end
    elseif event == "UNIT_INVENTORY_CHANGED" and arg == "player" and frame and frame:IsShown() then
        Refresh()
    end
end)

local function Apply()
    events:UnregisterAllEvents()
    if not On() then
        if frame then frame:Hide() end
        return
    end
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    events:RegisterEvent("READY_CHECK")
    events:RegisterEvent("UNIT_INVENTORY_CHANGED")
    if frame and frame:IsShown() then Refresh() end
end

hooksecurefunc(S, "Set", function(key)
    if key == "enabled" or (key:find("^equip") and key ~= "equipPos") then Apply() end
end)
hooksecurefunc(ns, "Apply", Apply)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", Apply)
