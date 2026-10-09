-- SetupsCard.lua: the Profiles page's Setups card: Naowh's setups applied, compared and tailored.
local ns = _G.NaowhForever

local S = ns.QoLSettings
local P = ns.PRESETS
local Settings = ns.Shared.Settings

local CUSTOM = "Custom"
local RESTORE_ASK = "Put every setting back to how it was before tailoring?"
local RESTORED = "Your settings are back. Reload now to finish?"
local RESTORE = "Restore"
local PARAGRAPH = "\n\n"

local function Tip()
    local lines = {}
    for _, key in ipairs(P.order) do
        if key ~= S.Get("preset") then lines[#lines + 1] = ns.PresetChanges(key) end
    end
    return table.concat(lines, PARAGRAPH)
end

local function DoRestore()
    if ns.Setup.Restore() then ns.ConfirmReload(RESTORED) end
end

local function Restore()
    ns.Confirm(RESTORE_ASK, DoRestore, nil, RESTORE)
end

local function NoBackup()
    return not (ns.Setup and ns.Setup.CanRestore())
end

local NAMES = { custom = CUSTOM }
for _, key in ipairs(P.order) do NAMES[key] = P[key].name end

Settings.Page(ns.SETUPS_PAGE, S):Card({
    id = "setups", name = "Setups", order = 10,
    help = "Puts your settings to one of Naowh's setups, or tailors them to how you play.",
    summary = function() return NAMES[S.Get("preset") or "custom"] or CUSTOM end,
    rows = {
        { label = "Setup", choice = { NAMES, P.order }, always = true,
          get = function() return S.Get("preset") or "custom" end,
          set = function(key) if P[key] then ns.UsePreset(key) end end,
          tip = Tip,
          help = "Minimalist has almost everything off; Recommended is Naowh's setup with the modules he uses on." },
        { label = "Tailor Setup", buttonText = "Start", button = function() ns.ShowSetup() end,
          help = "Asks a few questions and suggests what to turn on and off." },
        { label = "Before Tailoring", buttonText = "Restore", button = Restore, hidden = NoBackup,
          help = "Restores your settings to how they were before tailoring." },
    },
})
