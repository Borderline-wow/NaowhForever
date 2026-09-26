-------------------------------------------------------------------------------
--  NaowhForever_GlobalCopy.lua -- the QoL global copy: /copy puts the text of whatever is
--  under the cursor (or a frame named after it) in a box to copy from, and a hotkey over a
--  tooltip copies its spell, item or NPC ID.
--
--  Frame text can be secret in restricted content, and reading it then raises, so every
--  read is checked with canaccessvalue and wrapped in pcall.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.QoLSettings
local T = ns.THEME

local keyboard

local function On()
    return S.Get("enabled") and S.Get("globalCopy")
end

local function Secret(v)
    return issecretvalue and issecretvalue(v)
end

local function CanAccess(v)
    return not canaccessvalue or canaccessvalue(v)
end

local function CanAccessAll(...)
    return not canaccessallvalues or canaccessallvalues(...)
end

local function ShowCopyBox(title, text)
    if not text or text == "" then
        ns.Print("No copyable text found.")
        return
    end
    local UI = ns.UI
    local dimmer, panel = ns.MakeModal(520, 260, "globalCopy")
    local head = UI.KeepFont(panel, "head", 14, "OUTLINE", T.accent)
    head:SetPoint("TOPLEFT", 14, -12)
    head:SetText(title)
    local hint = UI.KeepFont(panel, "hint", 11, nil, T.muted)
    hint:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -6)
    hint:SetText("Ctrl+A, Ctrl+C to copy")
    UI.KeepButton(panel, "close", "X", 22, 22, function() dimmer:Hide() end):SetPoint("TOPRIGHT", -8, -8)

    local scroll = UI.Keep(panel, "scroll", function(p)
        local sf = CreateFrame("ScrollFrame", nil, p, "UIPanelScrollFrameTemplate")
        ns.Solid(sf, "BACKGROUND", T.bg, 1):SetAllPoints()
        local eb = CreateFrame("EditBox", nil, sf)
        eb:SetMultiLine(true)
        eb:SetAutoFocus(false)
        eb:SetFontObject("GameFontHighlight")
        eb:SetWidth(460)
        eb:SetTextInsets(4, 4, 4, 4)
        sf:SetScrollChild(eb)
        sf.box = eb
        return sf
    end)
    scroll:SetPoint("TOPLEFT", 14, -54)
    scroll:SetPoint("BOTTOMRIGHT", -32, 14)
    local box = scroll.box
    box:SetText(text)
    box:SetScript("OnEscapePressed", function() dimmer:Hide() end)
    dimmer:Show()
    box:SetFocus()
    box:HighlightText()
end

local function FrameText(frame)
    local lines = {}
    local function Collect(target)
        for _, region in ipairs({ target:GetRegions() }) do
            if region.GetText then
                local ok, shown = pcall(region.IsVisible, region)
                if ok and CanAccess(shown) and shown then
                    local textOk, text = pcall(region.GetText, region)
                    if textOk and CanAccess(text) and text and text ~= "" then
                        lines[#lines + 1] = text
                    end
                end
            end
        end
        for _, child in ipairs({ target:GetChildren() }) do Collect(child) end
    end
    if not (frame and frame.GetRegions) then return nil end
    if not pcall(Collect, frame) then return nil end
    return lines[1] and table.concat(lines, "\n") or nil
end

-- The frames under the cursor, or failing that every visible frame the cursor is over.
local function MouseText()
    local lines = {}
    for _, frame in ipairs(GetMouseFoci()) do
        if frame ~= WorldFrame then lines[#lines + 1] = FrameText(frame) end
    end
    if lines[1] then return table.concat(lines, "\n") end
    local frame = EnumerateFrames()
    while frame do
        local ok, use = pcall(function()
            local shown, over, name = frame:IsVisible(), MouseIsOver(frame), frame:GetName()
            if not CanAccessAll(shown, over, name) then return false end
            return shown and over and name ~= "WorldFrame"
        end)
        if ok and use then lines[#lines + 1] = FrameText(frame) end
        frame = EnumerateFrames(frame)
    end
    return lines[1] and table.concat(lines, "\n") or nil
end

local function CopySlash(msg)
    if not On() or InCombatLockdown() then return end
    msg = strtrim(msg or "")
    local named = msg ~= "" and _G[msg]
    local text
    if type(named) == "table" then
        text = FrameText(named)
    else
        text = MouseText()
    end
    ShowCopyBox(msg ~= "" and msg or "Global Copy", text)
end

SLASH_NAOWHFOREVERCOPY1 = "/copy"
SLASH_NAOWHFOREVERCOPY2 = "/ncopy"
SlashCmdList["NAOWHFOREVERCOPY"] = CopySlash

-------------------------------------------------------------------------------
--  Tooltip IDs
-------------------------------------------------------------------------------
local function SpellID()
    local ok, name, id = pcall(GameTooltip.GetSpell, GameTooltip)
    if ok and CanAccessAll(name, id) and id and not Secret(id) then
        return name or "Spell", tostring(id)
    end
end

local function ItemID()
    local ok, name, link = pcall(GameTooltip.GetItem, GameTooltip)
    if ok and CanAccessAll(name, link) and link and not Secret(link) then
        local id = link:match("item:(%d+)")
        if id then return name or "Item", id end
    end
end

local function UnitID()
    local ok, name, unit = pcall(GameTooltip.GetUnit, GameTooltip)
    if not (ok and CanAccessAll(name, unit)) then return end
    local guid = unit and UnitGUID(unit)
    local npcID = guid and CanAccess(guid) and select(6, strsplit("-", guid))
    if npcID then return name or "NPC", tostring(npcID) end
    if name then return "Unit", name end
end

local function DataID()
    local ok, data = pcall(GameTooltip.GetTooltipData, GameTooltip)
    if not (ok and data and CanAccess(data)) or Secret(data) then return end
    if data.id and not Secret(data.id) then return data.type or "Tooltip", tostring(data.id) end
    if data.hyperlink and CanAccess(data.hyperlink) and not Secret(data.hyperlink) then
        local link = tostring(data.hyperlink)
        local id = link:match("spell:(%d+)") or link:match("item:(%d+)")
        if id then return "Tooltip", id end
    end
end

local RESOLVERS = { SpellID, ItemID, UnitID, DataID }

local MODIFIER = {
    CTRL = IsControlKeyDown, SHIFT = IsShiftKeyDown, ALT = IsAltKeyDown,
    NONE = function() return true end,
}

local function OnKeyDown(_, key)
    if not (On() and S.Get("copyTooltipIds")) or InCombatLockdown() then return end
    if not MODIFIER[S.Get("copyModifier")]() then return end
    if strupper(key or "") ~= strupper(S.Get("copyKey")) then return end
    if not GameTooltip:IsShown() then return end
    for _, resolve in ipairs(RESOLVERS) do
        local title, text = resolve()
        if text then return ShowCopyBox(title, text) end
    end
end

-- SetPropagateKeyboardInput is protected, so the listener is made out of combat and only
-- switched on and off after that.
local function Apply()
    if not keyboard then
        if InCombatLockdown() then return end
        keyboard = CreateFrame("Frame")
        keyboard:SetPropagateKeyboardInput(true)
        keyboard:SetScript("OnKeyDown", OnKeyDown)
    end
    keyboard:EnableKeyboard(On() and S.Get("copyTooltipIds"))
end

hooksecurefunc(S, "Set", function(key)
    if key == "enabled" or key == "globalCopy" or key:find("^copy") then Apply() end
end)
hooksecurefunc(ns, "Apply", Apply)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:RegisterEvent("PLAYER_REGEN_ENABLED")
boot:SetScript("OnEvent", function(self)
    Apply()
    if keyboard then self:UnregisterAllEvents() end
end)
