-------------------------------------------------------------------------------
--  NaowhForever_EmoteDetection.lua -- the QoL emote detection: an alert when an instance emote
--  matches one of your words, and an /emote of your own when you cast a spell you listed.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.QoLSettings
local UI = ns.UI

local ICON = "Interface\\Icons\\INV_Misc_Food_164_Fish_Feast"
local HOLD, FADE = 4, 1

local frame, anim, unlocked
local autoEmotes = {}
local lastEmote, pending = 0, nil

local function Secret(v)
    return issecretvalue and issecretvalue(v)
end

local function AlertOn()
    return S.Get("enabled") and S.Get("emoteDetection")
end

local function AutoOn()
    return S.Get("enabled") and S.Get("autoEmote")
end

local function InInstance()
    local inInstance, kind = IsInInstance()
    return inInstance and kind ~= "none"
end

local function Build()
    frame = CreateFrame("Frame", "NaowhForeverEmoteDetection", UIParent)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    ns.Solid(frame, "BACKGROUND", ns.THEME.bg, 0.8):SetAllPoints()
    ns.Border(frame)
    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetTexture(ICON)
    frame.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    frame.icon:SetPoint("LEFT", 6, 0)
    frame.text = ns.Font(frame, 16, "OUTLINE")
    frame.text:SetPoint("LEFT", frame.icon, "RIGHT", 8, 0)
    frame.text:SetJustifyH("LEFT")
    frame.mover = UI.AttachMover(frame, "Emote Detection", function(pos) S.Set("emotePos", pos) end)
    frame:Hide()

    anim = frame:CreateAnimationGroup()
    local fade = anim:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0)
    fade:SetDuration(FADE)
    fade:SetStartDelay(HOLD)
    anim:SetScript("OnFinished", function() frame:Hide() end)
end

local function Place()
    local pos = S.Get("emotePos")
    frame:ClearAllPoints()
    if pos then
        frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    else
        frame:SetPoint("TOP", UIParent, "TOP", 0, -50)
    end
end

local function Show(text)
    anim:Stop()
    local size = S.Get("emoteFontSize")
    local c = S.Get("emoteColor")
    frame.text:SetFont(UI.FontPath(S.Get("emoteFont")), size, "OUTLINE")
    frame.text:SetTextColor(c.r, c.g, c.b, 1)
    frame.text:SetText(text)
    local iconSize = size * 2 + 8
    frame.icon:SetSize(iconSize, iconSize)
    local maxWidth = math.floor(UIParent:GetWidth() * 0.8)
    frame:SetSize(math.min(maxWidth, math.max(200, frame.text:GetStringWidth() + iconSize + 30)), iconSize + 12)
    frame:SetAlpha(1)
    frame:Show()
    if not unlocked then anim:Play() end
end

local function Matches(text)
    for token in S.Get("emotePattern"):gmatch("[^,]+") do
        token = strtrim(token)
        if token ~= "" and text:find(token, 1, true) then return true end
    end
end

-- "698: prepares a ritual of summoning; 29893: prepares a soulwell"
local function ParseAutoEmotes()
    wipe(autoEmotes)
    for id, text in S.Get("autoEmoteList"):gmatch("(%d+)%s*:%s*([^;]+)") do
        text = strtrim(text)
        if text ~= "" then autoEmotes[tonumber(id)] = text end
    end
end

local function SendEmote(text)
    C_ChatInfo.SendChatMessage(text, "EMOTE")
    lastEmote = GetTime()
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, ...)
    if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START" then
        local _, _, spellID = ...
        local text = autoEmotes[spellID]
        if not (text and AutoOn() and InInstance()) then return end
        if GetTime() - lastEmote < S.Get("autoEmoteCooldown") then return end
        if UnitAffectingCombat("player") then
            pending = text
        else
            SendEmote(text)
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pending and AutoOn() and InInstance() then
            C_Timer.After(0, function()
                if pending then SendEmote(pending) end
                pending = nil
            end)
        else
            pending = nil
        end
    else
        local text = ...
        if unlocked or not AlertOn() or Secret(text) or not text then return end
        if UnitAffectingCombat("player") or not InInstance() then return end
        if not Matches(text) then return end
        Show(text)
        if S.Get("emoteSound") then UI._PlayLSMSound(UI.SoundPathFor(S.Get("emoteSoundKey"))) end
    end
end)

local function Apply()
    events:UnregisterAllEvents()
    pending = nil
    ParseAutoEmotes()
    if AutoOn() then
        events:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
        events:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
    end
    if not (AlertOn() or unlocked) then
        if frame then
            anim:Stop()
            frame:Hide()
        end
        return
    end
    if not frame then Build() end
    Place()
    frame.mover:SetShown(unlocked == true)
    if unlocked then
        Show("Emote Detection Preview")
    else
        anim:Stop()
        frame:Hide()
    end
    for _, event in ipairs({ "CHAT_MSG_TEXT_EMOTE", "CHAT_MSG_EMOTE", "CHAT_MSG_MONSTER_EMOTE",
        "CHAT_MSG_SYSTEM" }) do
        events:RegisterEvent(event)
    end
end

hooksecurefunc(S, "Set", function(key)
    if key == "enabled" or ((key:find("^emote") or key:find("^autoEmote")) and key ~= "emotePos") then
        Apply()
    end
end)
hooksecurefunc(ns, "Apply", Apply)
hooksecurefunc(ns, "ShowRaidReminderAnchorConfig", function()
    unlocked = S.Get("enabled") == true
    Apply()
end)
hooksecurefunc(ns, "HideRaidReminderAnchorConfig", function()
    unlocked = false
    Apply()
end)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", Apply)
