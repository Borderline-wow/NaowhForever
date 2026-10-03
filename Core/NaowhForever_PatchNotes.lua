-------------------------------------------------------------------------------
--  NaowhForever_PatchNotes.lua -- the Patch Notes page. The client cannot read
--  CHANGELOG.md, so the notes players see in game live here, newest first.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local UI = ns.UI

local NOTES = {
    { title = "0.5.18-beta", lines = {
        "New options window: the modules are grouped under Adventure, Combat and Utilities on "
            .. "the left, a module's categories are tabs under its title, and the search at the top "
            .. "finds any setting. It fits on a 1080p screen.",
        "Action Bars (Utilities): save your action bars as a named set and put them back later, "
            .. "out of combat. Sets are shared by every character of your class. Also /nf bars "
            .. "save, restore, test, delete or list.",
        "Top Bar: hover the clock to see your saved instances and when each resets, or type "
            .. "/nf lockouts. Friends and Guild can each be switched off under Buttons.",
        "Campfire: each camp benefit shows as a short tag (+Spirit, +ATK, +ARM, +STR and so on), "
            .. "and Ctrl-click the Camp Nearby alert to dismiss it until you leave that campfire.",
        "XP Bar: Ctrl + right-click it to reset the session time and XP/Hour. Other clicks go "
            .. "through the bar.",
        "QoL, XP: XP Bar, XP per Hour and Group XP moved from Questing to their own tab. The XP "
            .. "Bar settings show a preview of the bar: click a text on it to change it. Three more "
            .. "spots for texts: Top, and Left and Right beside the bar.",
        "Skip Modifier (QoL, Questing): pick the key you hold to skip quest automation, Alt, "
            .. "Ctrl or Shift.",
        "Shift-Click Searches AH (Professions): with the auction house open, Shift-click a recipe "
            .. "or a reagent to search for it.",
        "Unlock Mode: the position readout sits on the display you select.",
        "Buttons, dropdowns and input boxes have a black border that lights up blue under the "
            .. "mouse.",
        "Supporter badges sit after the name in chat, and show in the Guild & Communities list.",
        "Dungeon Quests: a quest you can't pick up yet says what to do first.",
        "QoL, General: Co-Tank Debuffs sits inside Co-Tank Frame, and Stealth Reminder's colours "
            .. "fold away. Auction House Price moved to QoL, Tooltip Display.",
        "Fixed: the Naowh font no longer replaces the game's own fonts (Settings, Font has Game "
            .. "Font and Combat Text Font if you want them), Reload UI buttons, Blessings icon "
            .. "borders, Bag Space in Unlock Mode, Global Copy and a Buff Reminders error.",
        "New features are off until you turn them on.",
    } },
    { title = "0.5.17-beta", lines = {
        "Group XP (QoL, XP): a bar for each group member with their level and XP, for "
            .. "levelling together. Everyone who wants to show up needs Naowh Forever with Group "
            .. "XP on.",
        "Share Quests With Group (QoL, Questing): quests you pick up from an NPC are shared "
            .. "with your group. Hold Alt to keep one to yourself.",
        "Unspent Talent Points (QoL, Combat & Alerts): a reminder while you have talent points "
            .. "to spend.",
        "Accept Popup Macro (Macros, Focus & Cursor): presses the popup on screen for you. It "
            .. "presses whichever popup is on top.",
        "Bag Space (QoL, Loot & Items): your cheapest items as a row of icons. Ctrl-click "
            .. "deletes, click sells, middle-click ignores. It also combines part stacks and "
            .. "warns about items a quest still needs.",
        "Mail & Alts (QoL, Loot & Items): what your alts carry on item tooltips, Alts and "
            .. "Attach buttons on the mailbox, and a warning for mail about to expire.",
        "Search box at the top of the sidebar: finds a setting and takes you to it. Thanks to "
            .. "Lyssa.",
        "Supporter Badges (QoL, Interface) for Naowh's Legendary patrons, the developers and "
            .. "the moderators.",
        "Themes (Settings, Colors): eight colour presets or your own colours for this window. "
            .. "Thanks to Lyssa.",
        "Discovery: track the 40 library books around Azeroth, with a zone tracker, world map "
            .. "pins and an alert when one is nearby.",
        "Professions: crafting profit from your auction house scan, Buy Materials and Search AH "
            .. "buttons, a recipe filter, Track Recipe and a gathering reminder.",
        "XP Bar: pick the text for each of five spots around the bar.",
        "Flight Timer (QoL, Flight & Camp): a new look, bigger, with a Scale slider and a Land "
            .. "Early button.",
        "Campfire: sharper artwork, and an Alert Under slider for Camp Nearby.",
        "Settings: features fold into dropdowns that open when you switch them on, with single "
            .. "switches above them. Crosshair melee range moved inside Crosshair.",
        "BiS List: several lists per class, quality borders, a rank button per slot, Fill Empty "
            .. "Slots and adding items by ID. Dungeon Quests: click a chain step for a waypoint.",
        "Combat Alert: new Combat and Safe voice clips, and no more stutter on the pull with "
            .. "Text to Speech.",
        "Co-Tank Frame: Righteous Fury counts as tanking, and debuffs show in combat.",
        "Class macros are character macros now, with a right-click icon picker. Key bindings "
            .. "have their own Naowh Forever section.",
        "Fixed: Death Release Protection outside instances, Smart Reminders with BigWigs and "
            .. "DBM, the Unknown name on login, Auto Repair without the Restock Reminder, Swing "
            .. "Timer set to Always, the empty trinket slot error and the cursor staying clipped "
            .. "after a crash, among others.",
        "New features are off until you turn them on.",
    } },
    { title = "Naowh Forever preview", lines = {
        "Smart Reminders is now Naowh Forever, and Smart Reminders is one of its modules. "
            .. "The addon folder is NaowhForever now: settings saved before the rename come "
            .. "back if you copy WTF\\...\\SavedVariables\\NaowhSmartReminders.lua to "
            .. "NaowhForever.lua with the game closed.",
        "New layout: Unlock Mode, Settings, Patch Notes and Profiles along the top, and the "
            .. "modules in the sidebar: Smart Reminders, QoL, Dungeon Quests, Gear Sets, BiS "
            .. "List, Macros and AuraBuffs.",
        "/nf opens this window, alongside /naowh, /nao, /nsr and /smartreminders.",
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
    local h
    for _, entry in ipairs(NOTES) do
        _, h = W:SectionHeader(parent, entry.title:upper(), y); y = y - h
        for _, line in ipairs(entry.lines) do
            _, h = W:Note(parent, "- " .. line, y); y = y - h + 12
        end
        y = y - 12
    end
    return y
end
