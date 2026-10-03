-------------------------------------------------------------------------------
--  NaowhForever_GlobalCopy.lua -- the QoL global copy: /copy for the text under the cursor, and a
--  hotkey for tooltip IDs. Frame text can be secret, so every read is checked and pcalled.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.QoLSettings
local T = ns.THEME

local keyboard
local Apply

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

-- Global Copy's keyboard watch goes back on (Apply) once the box closes.
local function Reapply()
    Apply()
end

local function ShowCopyBox(title, text)
    if not text or text == "" then
        ns.Print("No copyable text found.")
        return
    end
    ns.ShowCopyBox(title, text, Reapply)
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
            local shown, over, name = frame:IsVisible(), frame:IsMouseOver(), frame:GetName()
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
-- Classify before reading, comparing, formatting or parsing any tooltip value.
local function Accessible(value)
    return not Secret(value) and CanAccess(value)
end

local TYPES = {
    [Enum.TooltipDataType.Spell] = { kind = "spell", label = "Spell ID", setting = "tooltipSpellID" },
    [Enum.TooltipDataType.Item] = { kind = "item", label = "Item ID", setting = "tooltipItemID" },
    [Enum.TooltipDataType.Unit] = { kind = "npc", label = "NPC ID", setting = "tooltipNPCID" },
}

local function DisplayOn()
    return S.Get("enabled") and S.Get("tooltipDisplay")
end

local function Resolve(data)
    if not Accessible(data) or (issecrettable and issecrettable(data)) then return end
    if type(data) ~= "table" then return end
    local dataType = data.type
    if not Accessible(dataType) then return end
    local info = TYPES[dataType]
    if not info then return end
    local id
    if info.kind == "npc" then
        local guid = data.guid
        if not Accessible(guid) then return info, nil, true end
        if type(guid) ~= "string" then return end
        local kind, _, _, _, _, entry = strsplit("-", guid)
        if kind ~= "Creature" and kind ~= "Vehicle" then return end
        id = tonumber(entry)
    else
        id = data.id
    end
    if not Accessible(id) then return info, nil, true end
    if type(id) ~= "number" or id <= 0 or id ~= math.floor(id) then return end
    return info, id, false
end

local function URL(info, id)
    local database = S.Get("tooltipWowhead") == "classic" and "classic/" or ""
    return "https://www.wowhead.com/" .. database .. info.kind .. "=" .. tostring(id)
end

-- A copy card: the accent line, an icon, a kicker over the title, X, and a one-line box at
-- boxY with the hint under it. key keeps each kind of card's frames apart.
local function Card(key, height, texture, kickerText, title, boxY)
    local UI = ns.UI
    local dimmer, panel = ns.MakeModal(500, height, key)
    local accent = UI.Keep(panel, "accent", function(p) return ns.Solid(p, "OVERLAY", T.accent, 1) end)
    accent:SetPoint("TOPLEFT"); accent:SetPoint("TOPRIGHT"); accent:SetHeight(2)
    local icon = UI.Keep(panel, "icon", function(p) return p:CreateTexture(nil, "ARTWORK") end)
    icon:SetSize(40, 40); icon:SetPoint("TOPLEFT", 18, -20); icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:SetTexture(texture or "Interface\\Icons\\INV_Misc_Book_09")
    local kicker = UI.KeepFont(panel, "kicker", 10, "OUTLINE", T.accent)
    kicker:SetPoint("TOPLEFT", 70, -20); kicker:SetText(kickerText)
    local name = UI.KeepFont(panel, "name", 16, "OUTLINE")
    name:SetPoint("TOPLEFT", 70, -38); name:SetPoint("RIGHT", -44, 0)
    name:SetJustifyH("LEFT"); name:SetWordWrap(false); name:SetText(title)
    UI.KeepButton(panel, "close", "X", 24, 24, function() dimmer:Hide() end):SetPoint("TOPRIGHT", -10, -10)
    local box = UI.Keep(panel, "value", function(p)
        local edit = CreateFrame("EditBox", nil, p)
        edit:SetAutoFocus(false); edit:SetMultiLine(false)
        edit:SetTextInsets(10, 10, 0, 0); edit:SetFontObject("GameFontHighlight")
        ns.Solid(edit, "BACKGROUND", T.bg, 1):SetAllPoints(); ns.Border(edit)
        return edit
    end)
    box:SetPoint("TOPLEFT", 18, boxY); box:SetSize(464, 36)
    box:SetScript("OnEscapePressed", function() box:ClearFocus(); dimmer:Hide() end)
    local hint = UI.KeepFont(panel, "hint", 12, nil, T.muted)
    hint:SetPoint("TOPLEFT", 18, boxY - 49); hint:SetText("Text selected. Press Ctrl+C to copy.")
    return dimmer, panel, box
end

local function ShowIDCard(info, id, title, mode)
    if InCombatLockdown() then return end
    local UI = ns.UI
    local texture
    if info.kind == "spell" then texture = C_Spell.GetSpellTexture(id)
    elseif info.kind == "item" then texture = C_Item.GetItemIconByID(id) end
    if not Accessible(texture) then texture = nil end
    local dimmer, panel, box = Card("tooltipCopy", 230, texture, "NAOWH  /  TOOLTIP COPY", title or info.label, -112)
    local note = UI.KeepFont(panel, "note", 10, nil, T.muted)
    note:SetPoint("TOPLEFT", 18, -187); note:SetWidth(464); note:SetJustifyH("LEFT")
    note:SetText("Wowhead may not list Forever-specific entries. Open links in your browser.")
    local idButton, linkButton
    local function Select(pick)
        box:SetText(pick == "id" and tostring(id) or URL(info, id))
        idButton.label:SetTextColor(pick == "id" and T.accent.r or T.muted.r, pick == "id" and T.accent.g or T.muted.g, pick == "id" and T.accent.b or T.muted.b)
        linkButton.label:SetTextColor(pick == "url" and T.accent.r or T.muted.r, pick == "url" and T.accent.g or T.muted.g, pick == "url" and T.accent.b or T.muted.b)
        box:SetFocus(); box:HighlightText()
    end
    idButton = UI.KeepButton(panel, "id", info.label .. ": " .. id, 180, 26, function() Select("id") end)
    idButton:SetPoint("TOPLEFT", 18, -76)
    linkButton = UI.KeepButton(panel, "link", "Wowhead Link", 150, 26, function() Select("url") end)
    linkButton:SetPoint("LEFT", idButton, "RIGHT", 8, 0)
    dimmer.onClose = function() box:ClearFocus(); Apply() end
    dimmer:Show(); Select(mode or S.Get("tooltipCopyFormat"))
end

-- The copy card for anything with an ID the tooltips do not cover (the Dungeon Journal's
-- quests): kind is Wowhead's ("quest"), label names the ID; mode "url" or "id" picks what
-- is selected first, else the Tooltip Copy setting.
function ns.ShowCopyCard(kind, label, id, title, mode)
    if InCombatLockdown() then ns.Print("Copy cards are available outside combat."); return end
    ShowIDCard({ kind = kind, label = label }, id, title, mode)
end

-- A line to copy (a message for chat, a link), on the same card, selected for Ctrl+C.
---@param title string
---@param text string
---@param texture? number|string the card's icon
function ns.ShowCopyLine(title, text, texture)
    if InCombatLockdown() then ns.Print("Copy cards are available outside combat."); return end
    local dimmer, _, box = Card("copyLine", 150, texture, "NAOWH  /  COPY", title, -76)
    box:SetText(text)
    dimmer.onClose = function() box:ClearFocus() end
    dimmer:Show()
    box:SetFocus(); box:HighlightText()
end

function ns.PreviewTooltipCopyCard()
    if InCombatLockdown() then ns.Print("Copy cards are available outside combat."); return end
    ShowIDCard(TYPES[Enum.TooltipDataType.Spell], 133, "Fireball - Preview")
end

local decorated = setmetatable({}, { __mode = "k" })
local hooked = setmetatable({}, { __mode = "k" })
local function Decorate(tooltip, data)
    if not DisplayOn() or tooltip:IsForbidden() then return end
    if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip and tooltip ~= ShoppingTooltip1 and tooltip ~= ShoppingTooltip2 then return end
    local info, id, hidden = Resolve(data)
    if not info or not S.Get(info.setting) then return end
    if hidden and S.Get("tooltipRestricted") ~= "hidden" then return end
    if not hooked[tooltip] then
        hooked[tooltip] = true
        tooltip:HookScript("OnTooltipCleared", function(self) decorated[self] = nil end)
    end
    if decorated[tooltip] then return end
    decorated[tooltip] = true
    tooltip:AddLine(" ")
    tooltip:AddDoubleLine(info.label, hidden and "Hidden" or tostring(id), T.accent.r, T.accent.g, T.accent.b, 0.85, 0.89, 0.93)
    if not hidden and S.Get("tooltipCopy") and (tooltip == GameTooltip or tooltip == ItemRefTooltip) then
        tooltip:AddLine(S.Get("tooltipModifier") .. "+" .. S.Get("tooltipKey") .. "  Copy ID / Wowhead link", T.muted.r, T.muted.g, T.muted.b)
    end
end

for dataType in pairs(TYPES) do TooltipDataProcessor.AddTooltipPostCall(dataType, Decorate) end

local function Matches(modifier)
    local ctrl = modifier:find("CTRL", 1, true) ~= nil
    local shift = modifier:find("SHIFT", 1, true) ~= nil
    local alt = modifier:find("ALT", 1, true) ~= nil
    return (not not IsControlKeyDown()) == ctrl and (not not IsShiftKeyDown()) == shift
        and (not not IsAltKeyDown()) == alt
end

local function OnKeyDown(self, key)
    if InCombatLockdown() then return end
    self:SetPropagateKeyboardInput(true)
    if GetCurrentKeyBoardFocus() then return end
    local modern = DisplayOn() and S.Get("tooltipCopy") and key == S.Get("tooltipKey") and Matches(S.Get("tooltipModifier"))
    local legacy = On() and S.Get("copyTooltipIds") and key == S.Get("copyKey") and Matches(S.Get("copyModifier"))
    if not modern and not legacy then return end
    local tooltip, titleLine = GameTooltip, GameTooltipTextLeft1
    if tooltip:IsForbidden() or not tooltip:IsShown() then
        tooltip, titleLine = ItemRefTooltip, ItemRefTooltipTextLeft1
    end
    if not tooltip or tooltip:IsForbidden() or not tooltip:IsShown() then return end
    local info, id = Resolve(tooltip:GetPrimaryTooltipData())
    if not info or not id or (modern and not S.Get(info.setting)) then return end
    local title = titleLine and titleLine:GetText()
    if not Accessible(title) or type(title) ~= "string" then title = info.label end
    self:SetPropagateKeyboardInput(false)
    if modern then ShowIDCard(info, id, title) else ShowCopyBox(title, tostring(id)) end
    -- The edit box owns input until the card closes, including if combat starts.
    self:EnableKeyboard(false)
end

function Apply()
    if InCombatLockdown() then return end
    local enabled = (DisplayOn() and S.Get("tooltipCopy")) or (On() and S.Get("copyTooltipIds"))
    if not keyboard and enabled then
        keyboard = CreateFrame("Frame")
        keyboard:SetScript("OnKeyDown", OnKeyDown)
        keyboard:SetScript("OnKeyUp", function(self) if not InCombatLockdown() then self:SetPropagateKeyboardInput(true) end end)
    end
    if keyboard then keyboard:SetPropagateKeyboardInput(true); keyboard:EnableKeyboard(enabled) end
end

hooksecurefunc(S, "Set", function(key)
    if key == "enabled" or key == "globalCopy" or key:find("^copy") or key:find("^tooltip") then Apply() end
end)
hooksecurefunc(ns, "Apply", Apply)
local boot = CreateFrame("Frame")
boot:SetScript("OnEvent", Apply)
boot:RegisterEvent("PLAYER_LOGIN")
boot:RegisterEvent("PLAYER_REGEN_ENABLED")
