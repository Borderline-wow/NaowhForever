-------------------------------------------------------------------------------
--  NaowhForever_Defaults.lua -- QoL > System > Defaults: a Setup dropdown of Naowh's presets
--  (ns.PRESETS). Picking one puts the profile in use to it after a confirm, then offers the
--  reload (ns.UsePreset, also the welcome window's choice); hovering it lists what each one
--  turns on and off against your settings now (ns.PresetChanges), read from the feature cards'
--  own switches. Smart Reminders, what you answered about EllesmereUI's windows and the
--  account's data stay.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.QoLSettings
local P = ns.PRESETS
local Settings = ns.Shared.Settings

local ASK = "Apply %s to every setting and position? Your BiS lists and notes stay. Cannot be undone."
local DONE = "Every setting now follows %s. Reload now to finish?"
local CUSTOM = "Custom"
local ON, OFF, SAME = "%s turns on: %s", "%s turns off: %s", "%s is what you have now."
local RIVALS = { "characterPanel", "inspectPanel" }

function ns.ApplyPreset(key)
    local root = ns.SettingsRoot()
    local qol = type(root.qol) == "table" and root.qol or {}
    local own, was = {}, {}
    for _, k in ipairs(ns.PROFILE_OWN.qol) do own[k] = qol[k] end
    for _, k in ipairs(RIVALS) do was[k] = S.Get(k) end
    for k in pairs(root) do
        if k ~= "tankReminder" then root[k] = nil end
    end
    for k, values in pairs(P[key].profile) do root[k] = CopyTable(values) end
    if type(root.qol) ~= "table" then root.qol = {} end
    for k, value in pairs(own) do root.qol[k] = value end
    root.qol.preset = key
    for _, k in ipairs(RIVALS) do
        if S.Get(k) ~= was[k] then S.Set(k, S.Get(k)) end
    end
end

function ns.UsePreset(key, ask)
    local name = P[key].name
    local function Go()
        ns.ApplyPreset(key)
        ns.ConfirmReload(DONE:format(name))
    end
    if ask == false then return Go() end
    ns.Confirm(ASK:format(name), Go, nil, "Apply")
end

local function ByName(a, b) return a < b end

function ns.PresetChanges(key)
    local profile = P[key].profile
    local on, off, seen = {}, {}, {}
    for _, page in pairs(Settings.pages) do
        for _, card in pairs(page.cards) do
            local store, switch = card.store, card.switch
            if type(switch) == "string" and store and store.key and not seen[card.name] then
                local values = profile[store.key]
                local want = values and values[switch]
                if want == nil then want = store.Default(switch) end
                local now = store.Get(switch)
                if want == true and now ~= true then
                    on[#on + 1], seen[card.name] = card.name, true
                elseif want ~= true and now == true then
                    off[#off + 1], seen[card.name] = card.name, true
                end
            end
        end
    end
    table.sort(on, ByName)
    table.sort(off, ByName)
    local name, lines = P[key].name, {}
    if #on > 0 then lines[#lines + 1] = ON:format(name, ns.Color("accent", table.concat(on, ", "))) end
    if #off > 0 then lines[#lines + 1] = OFF:format(name, ns.Color("muted", table.concat(off, ", "))) end
    if #lines == 0 then lines[1] = SAME:format(name) end
    return table.concat(lines, "\n")
end

local function Tip()
    local lines = {}
    for _, key in ipairs(P.order) do
        if key ~= S.Get("preset") then lines[#lines + 1] = ns.PresetChanges(key) end
    end
    return table.concat(lines, "\n\n")
end

local NAMES = { custom = CUSTOM }
for _, key in ipairs(P.order) do NAMES[key] = P[key].name end

Settings.Page("QoL/System", S):Card({
    id = "defaults", name = "Defaults", order = 90,
    help = "Puts every setting and position to one of Naowh's setups.",
    summary = function() return NAMES[S.Get("preset") or "custom"] or CUSTOM end,
    rows = {
        { label = "Setup", choice = { NAMES, P.order }, always = true,
          get = function() return S.Get("preset") or "custom" end,
          set = function(key) if P[key] then ns.UsePreset(key) end end,
          tip = Tip,
          help = "Minimalist has almost everything off; Recommended is Naowh's setup with the modules he uses on." },
    },
})
