-- Buttons.lua: the Top Bar's buttons: friends, guild and Hearthstone as secure buttons, and one per broker (ns.TopBar.Buttons).
local ns = _G.NaowhForever

local TB = ns.TopBar
local C = TB.C
local St = TB.Style
local Look = TB.Look
local Tooltips = TB.Tooltips

local HEARTHSTONE, BADGE_SIZE, LDB_PREFIX = C.HEARTHSTONE, C.BADGE_SIZE, C.LDB_PREFIX
local BADGE_RISE = 1
local MISSING_ALPHA = 0.35
local HEARTH_TIP_EVERY = 0.5
local SECURE_NAME = "NaowhForeverTopBar_"
local HEARTH_MACRO = "/use item:"

local CLICK_THROUGH = {
    friends = { "QuickJoinToastButton", "FriendsMicroButton", "SocialsMicroButton" },
    guild = { "GuildMicroButton" },
}

local buttons = {}

local function Leave(self)
    self.icon:SetVertexColor(Look.IconColor())
    self:SetScript("OnUpdate", nil)
    GameTooltip:Hide()
    self.onHover()
end

local function HearthTick(self, elapsed)
    self.tipTime = self.tipTime + elapsed
    if self.tipTime < HEARTH_TIP_EVERY then return end
    self.tipTime = 0
    Tooltips.Button(self)
end

local function SecureEnter(self)
    self.onHover()
    self.icon:SetVertexColor(Look.HoverColor())
    Tooltips.Button(self)
    if self.key ~= "hearth" then return end
    self.tipTime = 0
    self:SetScript("OnUpdate", HearthTick)
end

local function BrokerClick(self, button)
    local obj = TB.LDB():GetDataObjectByName(self.broker)
    if obj and obj.OnClick then obj.OnClick(self, button) end
end

local function BrokerEnter(self)
    self.onHover()
    self.icon:SetVertexColor(Look.HoverColor())
    Tooltips.Broker(self, self.broker)
end

local function BrokerLeave(self)
    Tooltips.LeaveBroker(self, self.broker)
end

local function NewButton(key, parent, template, onHover)
    local b = CreateFrame("Button", template and (SECURE_NAME .. key) or nil, parent, template)
    b:RegisterForClicks("AnyUp")
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("CENTER")
    if ns.classicSkin then b:SetHighlightTexture(ns.Shared.Style.CLASSIC_HIGHLIGHT, "ADD") end
    b.key = key
    b.onHover = onHover
    b:SetScript("OnLeave", Leave)
    buttons[key] = b
    return b
end

local function ClickTarget(key)
    local target
    for _, name in ipairs(CLICK_THROUGH[key]) do target = target or _G[name] end
    return target
end

local Buttons = { list = buttons }
TB.Buttons = Buttons

function Buttons.Badge(b, color)
    b.badge = b:CreateFontString(nil, "OVERLAY")
    b.badge:SetFont(ns.UIFontPath(), BADGE_SIZE, "OUTLINE")
    b.badge:SetPoint("CENTER", b.icon, "BOTTOM", 0, BADGE_RISE)
    b.badge:SetTextColor(color.r, color.g, color.b)
end

function Buttons.Secure(key, parent, onHover)
    local b = NewButton(key, parent, "SecureActionButtonTemplate", onHover)
    if not ns.Shared.Parts.ClassicIcon(b.icon, key) then b.icon:SetTexture(St.ICON[key]) end
    b:SetAttribute("useOnKeyDown", false)
    if key == "hearth" then
        b:SetAttribute("type", "macro")
        b:SetAttribute("macrotext", HEARTH_MACRO .. HEARTHSTONE)
    else
        local target = ClickTarget(key)
        if target then
            b:SetAttribute("*type1", "click")
            b:SetAttribute("*clickbutton1", target)
        else
            b:SetAlpha(MISSING_ALPHA)
        end
    end
    b:SetScript("OnEnter", SecureEnter)
    return b
end

function Buttons.Broker(name, parent, onHover)
    local b = buttons[LDB_PREFIX .. name]
    if b then return b end
    b = NewButton(LDB_PREFIX .. name, parent, nil, onHover)
    b.broker = name
    b:SetScript("OnClick", BrokerClick)
    b:SetScript("OnEnter", BrokerEnter)
    b:HookScript("OnLeave", BrokerLeave)
    return b
end

function Buttons.SetBadge(b, n)
    if b.count == n then return end
    b.count = n
    b.badge:SetText(n and n > 0 and n or "")
end
