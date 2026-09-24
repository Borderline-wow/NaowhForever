-------------------------------------------------------------------------------
--  NaowhUI_SmartReminders_PatchNotes.lua -- the Patch Notes page. The client cannot read
--  CHANGELOG.md, so the notes players see in game live here, newest first.
-------------------------------------------------------------------------------
local ns = _G.NaowhUITankReminder
local UI = ns.UI

local NOTES = {
    { title = "Naowh Forever preview", lines = {
        "Smart Reminders is now Naowh Forever. Your profiles and reminders carry over as they are.",
        "New layout: Unlock Mode, Settings, Patch Notes and Profiles in the sidebar, with "
            .. "Smart Reminders, QoL, Macros and AuraBuffs below them.",
        "Window scale and the minimap button moved to Settings.",
        "Debuff sounds moved to AuraBuffs, under Poison & Dispel.",
        "Loot feed: every loot, quest turn-in and reputation gain pops up with its icon, amount "
            .. "and value, with an "
            .. "optional gold per hour counter. Set it up in QoL, Loot & Items; move it in Unlock Mode.",
        "Loot feed appearance: width, line height, spacing (no gaps by default), font and "
            .. "font size.",
        "XP per Hour in QoL, General: experience per hour, time to level, session time and "
            .. "XP per session on screen. Move it in Unlock Mode.",
        "Flight timer in QoL, Flight & Camp: where you are flying and how long is left, with a "
            .. "reminder quote from a streamer. Move it in Unlock Mode.",
        "Campfire reminder in AuraBuffs, Campfire: a round camp icon with a countdown while "
            .. "Camp Benefits is up, and a greyed-out Refresh Camp reminder with an optional "
            .. "sound when it runs out. Open world only. Move it in Unlock Mode.",
        "Low Health reminder in AuraBuffs, Low Health: your best healthstone or healing "
            .. "potion with a LOW HEALTH warning while you are under the threshold, in combat "
            .. "too, plus an optional sound each time you drop below it. Move it in Unlock Mode.",
        "Naowh Quiz: WoW trivia that opens on a flight or at a campfire, or any time with "
            .. "/naowh quiz.",
        "Global Font in Settings: one font for the whole game UI and this addon. The Naowh "
            .. "font ships with the addon and is the default; pick any other font, or Blizzard "
            .. "Default to leave the game's fonts alone.",
        "QoL, Macros and AuraBuffs settings can be set now; each feature switches on as "
            .. "it is built.",
    } },
}

function ns.BuildPatchNotesPage(parent, y)
    local W = UI.Widgets
    local _, h
    for _, entry in ipairs(NOTES) do
        _, h = W:SectionHeader(parent, entry.title:upper(), y); y = y - h
        for _, line in ipairs(entry.lines) do
            _, h = W:Note(parent, "- " .. line, y); y = y - h + 12
        end
        y = y - 12
    end
    return y
end
