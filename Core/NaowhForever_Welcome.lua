-------------------------------------------------------------------------------
--  NaowhForever_Welcome.lua -- the welcome window: what Naowh Forever is, how to start, which
--  of Naowh's setups to start from (ns.PRESETS: Minimalist or Recommended), and our Discord.
--  Shown once per account, a few seconds into the first login (or the reload another addon's
--  setup asks for before it is seen) and out of combat; /nf welcome and QoL > System open it
--  again. Nothing is made until it shows. A preset picked on a new
--  account applies at once; picked again later, it asks first, as on the Defaults card. Its
--  height follows its contents once the game has laid the text out, whatever the resolution.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local T = ns.THEME
local Parts = ns.Shared.Parts
local St = ns.Shared.Style

local WIDTH = 520
local INSET = St.CONTENT_INSET
local EDGE = St.WINDOW_PAD
local HEADER = St.WINDOW_HEADER
local BODY_SIZE = 13
local LINE_GAP = 10
local BUTTON_H = 26
local BUTTON_GAP = 8
local DISCORD_W, SETTINGS_W, CLOSE_W = 120, 120, 90
local PRESET_W, PRESET_GAP, PICK_GAP, PRESET_SPACE = 130, 6, 14, 14
local PICTURE_SHARE = 0.25
local PICTURES = "Interface\\AddOns\\NaowhForever\\Media\\Welcome\\"
local OPAQUE = 1
local SHOW_DELAY = 5
local POSITION_KEY = "welcomeWindow"

local TITLE = "Welcome to Naowh Forever"
local SUBTITLE = "Good to have you here."
local DISCORD_TITLE = "Naowh's Discord"
local PICK = "How do you want to start?"

local window, timer, armed
local login = CreateFrame("Frame")

local function Lines()
    return {
        "Quality of life, guides and tools for WoW Forever, all in one place.",
        "Type " .. ns.Color("accent", "/nf") .. " to open the settings and turn on what you want.",
        "We keep improving the addon and would love your feedback. Come say hi on our Discord.",
    }
end

local function Seen()
    ns.AccountSettings().welcomeSeen = true
end

local function Hidden(self)
    if not self:IsShown() then Seen() end
end

local function JoinDiscord()
    Seen()
    ns.ShowCopyLine(DISCORD_TITLE, ns.NAOWH_DISCORD, St.LOGO)
end

local function OpenSettings()
    window:Hide()
    ns.OpenOptionsWindow()
end

local function Close()
    window:Hide()
end

local function Pick(key)
    local fresh = not ns.AccountSettings().welcomeSeen
    window:Hide()
    if fresh and key == ns.PRESETS.newInstall then return end
    ns.UsePreset(key, not fresh)
end

local function Fit(content)
    window:SetHeight(math.ceil(content:GetHeight()) + INSET + BUTTON_H + EDGE)
end

local function Presets()
    local P = ns.PRESETS
    if not (P and P.order and #P.order > 1 and ns.UsePreset) then return nil end
    return P
end

local function Build()
    window = Parts.Window(WIDTH, HEADER, POSITION_KEY)
    window.backdrop:Paint(OPAQUE)
    Parts.TitleBar(window, TITLE, SUBTITLE)
    window:HookScript("OnHide", Hidden)
    local height, above = HEADER + INSET, nil
    window.lines = {}
    for i, text in ipairs(Lines()) do
        local line = ns.Font(window, BODY_SIZE, nil, T.fg)
        line:SetWidth(WIDTH - INSET * 2)
        line:SetJustifyH("LEFT")
        line:SetText(text)
        if above then
            line:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -LINE_GAP)
            height = height + LINE_GAP
        else
            line:SetPoint("TOPLEFT", INSET, -(HEADER + INSET))
        end
        height = height + math.ceil(line:GetStringHeight())
        window.lines[i] = line
        above = line
    end
    local P = Presets()
    if P then
        local head = ns.Font(window, BODY_SIZE, nil, T.accent)
        head:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -PICK_GAP)
        head:SetText(PICK)
        height = height + PICK_GAP + math.ceil(head:GetStringHeight())
        above = head
        window.presets = {}
        local width = WIDTH - INSET * 2
        local tall = math.floor(width * PICTURE_SHARE + 0.5)
        for i, key in ipairs(P.order) do
            local gap = i == 1 and LINE_GAP or PRESET_SPACE
            local holder = CreateFrame("Frame", nil, window)
            holder:SetSize(width, tall)
            holder:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -gap)
            local picture = holder:CreateTexture(nil, "ARTWORK")
            picture:SetAllPoints()
            picture:SetTexture(PICTURES .. key .. ".png")
            ns.Border(holder, { r = 0, g = 0, b = 0 })
            local button = ns.Button(window, P[key].name, PRESET_W, BUTTON_H, function() Pick(key) end)
            ns.Tooltip(button, P[key].name, function() return ns.PresetChanges and ns.PresetChanges(key) end)
            button:SetPoint("TOPLEFT", holder, "BOTTOMLEFT", 0, -PRESET_GAP)
            local about = ns.Font(window, BODY_SIZE, nil, T.muted)
            about:SetPoint("LEFT", button, "RIGHT", BUTTON_GAP, 0)
            about:SetPoint("RIGHT", window, "RIGHT", -INSET, 0)
            about:SetJustifyH("LEFT")
            about:SetText(P[key].about)
            height = height + gap + tall + PRESET_GAP + BUTTON_H
            window.presets[i] = button
            above = button
        end
    end
    window.content = CreateFrame("Frame", nil, window)
    window.content:SetPoint("TOPLEFT")
    window.content:SetPoint("BOTTOMRIGHT", above, "BOTTOMRIGHT")
    window.content:SetScript("OnSizeChanged", Fit)
    window.discord = ns.AccentBorder(ns.Button(window, "Join Discord", DISCORD_W, BUTTON_H, JoinDiscord))
    window.discord:SetPoint("BOTTOMLEFT", EDGE, EDGE)
    window.settings = ns.Button(window, "Open Settings", SETTINGS_W, BUTTON_H, OpenSettings)
    window.settings:SetPoint("LEFT", window.discord, "RIGHT", BUTTON_GAP, 0)
    window.close = ns.Button(window, "Close", CLOSE_W, BUTTON_H, Close)
    window.close:SetPoint("BOTTOMRIGHT", -EDGE, EDGE)
    window:SetHeight(height + INSET + BUTTON_H + EDGE)
end

local function Show()
    if not window then Build() end
    window:Show()
end

local function Stop()
    login:UnregisterAllEvents()
    if timer then timer:Cancel() end
    timer = nil
end

function ns.ShowWelcome()
    Stop()
    ns.OpenFromOptions(Show)
end

local function Due()
    timer = nil
    if ns.AccountSettings().welcomeSeen then return Stop() end
    if InCombatLockdown() then
        login:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    ns.ShowWelcome()
end

login:SetScript("OnEvent", function(self, event, isInitialLogin, isReloadingUi)
    if event == "PLAYER_ENTERING_WORLD" then
        if not (armed or isInitialLogin or isReloadingUi) or ns.AccountSettings().welcomeSeen then
            return Stop()
        end
        armed = true
        if timer then timer:Cancel() end
        timer = C_Timer.NewTimer(SHOW_DELAY, Due)
        self:RegisterEvent("PLAYER_LEAVING_WORLD")
    elseif event == "PLAYER_LEAVING_WORLD" then
        if timer then timer:Cancel() end
        timer = nil
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    elseif event == "PLAYER_REGEN_ENABLED" then
        Due()
    end
end)
login:RegisterEvent("PLAYER_ENTERING_WORLD")

local Settings = ns.Shared.Settings
Settings.Page("QoL/System", ns.QoLSettings):Card({
    id = "welcome", name = "Welcome", order = 40,
    help = "The window from your first login, with how to get started and our Discord.",
    rows = {
        { label = "Welcome Window", buttonText = "Show", button = ns.ShowWelcome,
          help = "Opens the welcome window again." },
    },
})
