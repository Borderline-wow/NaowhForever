-------------------------------------------------------------------------------
--  NaowhForever_Welcome.lua -- the welcome window: what Naowh Forever is, how to start and
--  our Discord. Shown once per account, a few seconds into the first login and out of combat;
--  /nf welcome and QoL > System open it again. Nothing is made until it shows.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local T = ns.THEME
local Parts = ns.Shared.Parts
local St = ns.Shared.Style

local WIDTH = 460
local INSET = St.CONTENT_INSET
local EDGE = St.WINDOW_PAD
local HEADER = St.WINDOW_HEADER
local BODY_SIZE = 13
local LINE_GAP = 10
local BUTTON_H = 26
local BUTTON_GAP = 8
local DISCORD_W, SETTINGS_W, CLOSE_W = 120, 120, 90
local OPAQUE = 1
local SHOW_DELAY = 5
local POSITION_KEY = "welcomeWindow"

local TITLE = "Welcome to Naowh Forever"
local SUBTITLE = "Good to have you here."
local DISCORD_TITLE = "Naowh's Discord"

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

login:SetScript("OnEvent", function(self, event, isInitialLogin)
    if event == "PLAYER_ENTERING_WORLD" then
        if not (armed or isInitialLogin) or ns.AccountSettings().welcomeSeen then return Stop() end
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
