# Changelog

## Unreleased

### Added
- Professions module: Naowh's profession window over Blizzard's, with your recipes by
  category, reagents and Create / Create All in the middle, and Blizzard's profession tabs
  on its edge. The overview tab shows every profession as a card. Off shows Blizzard's
  window as before.
- Unlearned Recipes: the recipes you have not learned yet, listed under your own, with the
  skill each needs, what it costs and where it comes from (nearest trainers, the vendor
  selling it, or what drops it). Click a trainer or vendor to set a waypoint. Covers every
  crafting profession plus Cooking, Fishing and First Aid; with the Naowh window off it is
  a drawer beside Blizzard's. /nf recipes prints what the profession API reports.

### Changed
- Dungeon Quests: each quest's state sits in its own column on the right, quests are listed
  in the order you work through them (to pick up, in log, complete, finished), and a
  finished quest is greyed with a check in place of its level. The tracker draws each quest
  as its own bar on a darker panel. The tracker's on/off is now only the module switch.
- XP Bar: the bar runs the full width, with the percentage inside it on the right.

### Fixed
- XP Bar: Time to Level and the quest and rested percentages no longer break for a moment
  after login or a reload, when the game still reports 0 XP to level.

## 0.5.13-beta

### Added
- Top Bar module: friends and guild on the left, the clock in the middle, addon buttons
  on either side, FPS and latency underneath. Dungeon Quests and BiS List are on it by
  default, and any addon's broker button can be added from its Buttons section, on the
  left or the right, along with an optional Hearthstone button. Move it in Unlock Mode.
  It replaces NaowhUI's top bar on Forever.
- Every module with its own window (Dungeon Quests, Gear Sets, Blessings, BiS List, Threat
  Meter) now has a broker button, which the Top Bar and any broker display can carry, and an
  optional minimap button next to the Naowh Forever logo. Settings > Minimap Buttons turns
  those on; they start off.

### Removed
- The micro menu bar. The Top Bar carries Dungeon Quests and BiS List, and any other
  module can be added to it.

### Fixed
- XP Bar: Blizzard's experience bar is faded out instead of hidden. Hiding it from the
  addon tainted Edit Mode's action bar layout, so a pet or stance bar change in combat
  was blocked (ADDON_ACTION_BLOCKED on MultiBarBottomRight). The space it took is kept.
- Crosshair: Melee Spell ID 0 now works for paladins (Holy Strike), and the class check
  no longer calls a function Forever only keeps as a deprecated shim.
- Text prompts wrap a long title inside the box instead of running past its edges.
- Smart Reminders: the alert preview no longer shows while the module is switched off. It
  put an empty square on screen whenever the Naowh Forever window was open, on any page.
- BiS List: item names no longer show as "item 12345" the first time you open a gear
  slot. An item the server could not load held back every other name in that slot until
  you clicked something.
- Dungeon Quests: clicking a quest you have, or Track in quest log in a chain list, now
  tracks it and selects it in your quest log instead of opening the log. Opening it from
  the addon left the world map's quest pins blocked the next time you opened the map in
  combat (ADDON_ACTION_BLOCKED on SetPassThroughButtons).
- Blessings: the Next Blessing and Next Greater Blessing key fields no longer take keys
  you press before clicking them. Walking with the Blessings page open bound W, A, S or D
  to a blessing.

## 0.5.12-beta

### Added
- Resize any Naowh Forever window by dragging its bottom-right corner, the main window
  and each module's own window alike. Each keeps its size, and pages spread out to the
  new width when you let go.
- XP Bar (QoL > General): level, experience and percentage on one bar, with completed
  quest XP and rested experience drawn past the fill, and optional played, session and
  levelling text underneath. Replaces Blizzard's experience bar while it is on. Off by
  default; move it in Unlock Mode.
- Dungeon Quest Tracker: Show Outside Dungeons (off by default) keeps it up in the world,
  listing each dungeon with one of your quests in the log or one you still need near your
  level. /nf dungeon and the X on the tracker switch it on and off.
- Dungeon Quest Tracker: Show Single Dungeon (off by default) adds a dropdown to the
  tracker to list a single dungeon. Entering a dungeon selects it.
- Dungeon Quest Tracker: a pin in front of each quest. On a quest you still need it marks
  the quest giver on your map; on one in your log it marks where you hand it in (the
  quest giver, or the turn-in NPC where that is someone else). Clicking a quest you have
  opens it in your quest log. Hover a line or pin for where the quest starts.
- Dungeon Quests: with TomTom installed, waypoints from the tracker and the Dungeon
  Quests page use TomTom's waypoint and arrow instead of the game's.
- Dungeon Quests: the seven new Forever dungeons that had no quests listed (Excavation
  Site: Wetlands, City of Dalaran, The Drowned City, Krol'dok, Alcaz Prison, Blackmaw Hold,
  Shaper's Terrace) are on the page and in the dropdown now, and all nine new dungeons show
  their level range.
- Dungeon Quests: a quest in your log has a green border on the tracker and the Dungeon
  Quests page, and once its objectives are done it reads Complete in green instead of In
  log, so you know it is ready to hand in.
- Dungeon Quests: every dungeon shows its level range now, not only the new ones. Within 5
  levels of it the range turns green, with IN RANGE on the Dungeon Quests page; the tracker
  shows it next to each dungeon outside and in the Show Single Dungeon dropdown.
- BiS List, Dungeon Quests, Gear Sets, Blessings and Threat Meter open in a window of their
  own, without the rest of the options: /nfbis, /nfdq, /nfgear, /nfbless and /nfthreat open
  or close each one.
- A micro menu bar at the top of the screen has a button for each. It shows BiS and Dungeon
  Quests to start with; choose its buttons or hide it under Settings > Micro Menu, and move
  it in Unlock Mode.
- Gear Sets: rename a set with Ctrl-click on its bar button or the Rename button on the
  Gear Sets page. Wear While Mounted and Wear While Resting follow the new name.
- Buffs & Consumables (AuraBuffs) now works: a row of icons for missing food, flask and
  elixir buffs in dungeons and raids, or wherever you choose under Show In. It can warn a
  few minutes before a buff runs out, and skips anything you do not carry.
- Scrolls in your bags show until you read them.
- Raid Buff Reminders shows how many in your group are missing Arcane Intellect,
  Fortitude, Divine Spirit, Mark of the Wild or a Blessing.
- Move the icons in Unlock Mode. Reminders pause in combat, since Forever hides auras from
  addons then, and pick up again after.
- Saved quest rewards (QoL > General > Questing): Alt-click a reward you can choose, in the
  quest log or at the quest giver, to save it for that quest in your profile. It is selected
  when you hand the quest in, and Auto Turn In takes it for you. Picks travel with the
  profile, so a shared profile comes with its rewards chosen. Suggested by Gingi.
- UI Clutter (QoL > Interface): Hide Error Messages, Hide Tutorial Pop-ups, Hide Screenshot
  Status and Skip Cinematics now work. Hide Error Messages also silences the voice line with
  the red text. Turning Hide Tutorial Pop-ups off puts back the tutorial settings you had.
  Skip Cinematics skips only cinematics already seen on this account.
- FPS counter (QoL > Interface), with optional local and world latency. Move it in Unlock
  Mode.
- Dungeon Quests: quest chains. Click a quest on the tracker, or its Chain button on the
  Dungeon Quests page, to list every quest in its chain in order, the ones before it and
  the ones after, each marked Completed, In log or Not done. A chain quest you have opens
  in your quest log from that list. Chains come from Wowhead's Forever quest database.
- BiS list: the slot picker lists every dungeon drop for that slot that your class can
  use under Other Dungeon Drops, below the ranking for your spec, with its item level,
  required level and the boss that drops it. It shows drops within 10 levels of yours;
  Show All lists every level. Click one to add it as your next pick. Dungeons Wowhead has
  no Forever loot for yet (Dire Maul and most of the new dungeons) are not in it.
- BiS list: the page looks like the character pane, your character in the middle with
  your gear slots around it. Slots start empty; click one to open a picker in the middle
  of the screen and choose its items in order from the ranking for your spec, your BiS
  first, then your 2nd, 3rd and so on. A slot shows its BiS with a green border and a
  check mark, and +N for the rest.
- BiS list: a Where Your Items Drop panel to the right of your character has a line per
  slot with its BiS, where it drops and +N for your other picks. Click the + on a line to
  list every pick for that slot with its boss and place. Run Next at
  the top names the places holding the most BiS picks you do not have yet.

Brought over from NaowhQOL:
- Questing (QoL > General): accept quests, hand in finished ones, and pick quests from
  an NPC's options for you. Hold Alt to skip it.
- Skip Loot Confirmations (QoL > Loot & Items): Need, Greed, disenchant and
  bind-on-pickup confirmations answered for you.
- Combat Timer (QoL > Alerts): how long the fight has run, with the time in chat when it
  ends.
- UI clutter (QoL > Interface): hide alert pop-ups, event toasts and zone text, and keep
  the cursor in the game window during combat.
- Crosshair (QoL > Interface), with a colour change and sound while your target is out
  of melee range.
- A new Tools tab under QoL:
  - Auto Combat Logging in raids, asking once per raid and difficulty.
  - Global Copy: /copy for the text under the cursor, and a hotkey that copies a
    tooltip's spell, item or NPC ID.
  - Custom Slash Commands that open a game window or run another command.

### Fixed
- Dungeon Quests: Afadra Dunwall (The Restless Dead) is marked at her real spot in Old
  Ironforge.
- Dungeon Quests: the level in brackets is the quest level the game reports, the same
  number as the quest log, instead of the guide's, which was often off (Leaders of the
  Fang read 15; it is 22).
- Dungeon Quests: quests with more than one step or a version per faction now read In log
  or Completed correctly, where before they could show Missing. Covers Searching for the Lost
  Satchel (Ragefire Chasm), Unending Torment and Crest of Lordaeron (Ruins of Lordaeron),
  and Allegiance to the Old Gods and The Essence of Aku'Mai (Blackfathom Deeps). A chain
  that is part done shows Next step. Crest of Lordaeron was missing and is listed now,
  and Searching for the Lost Satchel shows its real quest giver, Rahauro in Thunder Bluff.
- Blessings and Restock look up which spells you know through the current spellbook call.
  The old call only exists on Forever while deprecated APIs are loaded, so without them
  the Blessings bar could not find your blessing ranks and class reagent restocking found
  no spells.
- Macros: the macros on the Macros page are now actually made. Switching one on adds it to
  your character macros (NF Health, NF Mana, NF Food, NF Bandage, NF Trinket 1 and 2,
  NF Focus); put it on a bar once and it follows your bags, changing after combat if your
  bags change during a fight. Switching it off, or turning the module off, deletes it; a
  profile or spec switch that has it off leaves it on your bars. Announce Focus uses raid
  chat in a raid and party chat in a party. Before this the settings saved but no macro
  was ever written.
- XP per Hour: Reset now also resets the XP Bar's Time to Level, XP/Hour and Session.
  They kept their own count, so resetting seemed to do nothing when reading the bar.

These QoL settings were saved before, but nothing acted on them. They now work:
- Stealth Reminder (QoL > General): RESTEALTH on screen while a rogue or druid is out
  of stealth and out of combat, and STEALTH while stealthed. Druids choose Cat Form only
  or any form.
- Stance / Form Reminder (QoL > General): a warning while a warrior has no stance, a
  paladin has no aura, or a druid or shadow priest is out of the form picked on the page,
  with an optional repeating sound.
- Co-Tank Frame (QoL > General): the other tank's health while you are tanking, with
  their debuffs beside it out of combat. Click it to target them. It can also anchor to
  another frame by name.
- Auto-Fill Delete Confirmation (QoL > Loot & Items) types DELETE for you and shows the
  item as a link in the dialog.
- Low Durability Warning (QoL > Alerts).
- Combat Alert (QoL > Alerts): text as you enter and leave combat, each with an optional
  sound or spoken line.

Each on-screen reminder can be moved in Unlock Mode, and its text, colours and font set on
its page.

### Changed
- Loot Feed: Show Reputation and Glow are off by default. Anyone who switched them on
  keeps them on.
- XP per Hour: the level splits read "Level 23  1/4" and so on, instead of "Split 1", so
  each line says which level it belongs to.
- BiS list: each slot holds a ranked list of picks instead of one item. The picker lists
  your picks in order, with Up, Down and Remove, above the ranking you add from, each item
  with its rank and where it comes from: the quest, vendor or NPC from Wowhead's Forever
  database when the ranking gives no source. Tooltips, the loot feed and drop alerts say
  BiS for your first pick and BiS #2, #3 and so on for the rest. Your current list carries
  over as your BiS picks.
- BiS list: Alt+Shift-click adds an item as the next pick for its slot, or as its BiS when
  the slot has none, and never pushes out an item you already picked.
- BiS list: a two-hander as your Main Hand BiS greys out the Off Hand but keeps its picks.
  They count again once your Main Hand BiS is a one-hander.
- BiS list: picking is from the ranking and the dungeon drops now; the Add Item by ID
  button and the item ID entry are gone. Shared lists keep the order of your picks, and
  older strings still import. Worn marks a BiS pick you are wearing.
- Dungeon Quests: quests grey to you are no longer listed on the tracker (in dungeons and
  with Show Single Dungeon too) or on the Dungeon Quests page. Quests in your log and chains
  you are partway through still show, and Show Completed still lists the ones you did.
- The options window no longer builds a fresh copy of a page every time a setting on it
  changes, which used memory for the rest of the session. Every page now reuses its own.
- Popups and editors (reminder editors, pickers, confirmations, copy boxes, the gear set
  icon picker) are built once and reused instead of adding a new window each time they
  open.
- Campfire: standing near a campfire no longer stacks up a new hidden timer every time
  your buffs change.
- Lighter in combat: the Blessings bar, threat meter, trainer glow, loot feed, gear set bar
  and Smart Reminders' boss mod handling do less work per event, and XP per Hour stops its
  clock at max level.

## 0.5.11-beta

### Added
- Campfire: Show Only When Low keeps the camp icon hidden until Camp Benefits has less
  time left than you choose (10 to 59 minutes, 10 by default). Off by default.
- Campfire: while you sit at a campfire, the icon counts down the minute until Camp
  Benefits lands, then switches to the camp's own timer.

### Fixed
- Campfire: "Spell ID" no longer shows in the list of active camp buffs.
- Death Release Protection (QoL > General) now works: in a dungeon or raid, Release Spirit
  has to be held down for the Hold Time before it releases, and a plain click does nothing.
  The setting was saved before, but nothing acted on it.

## 0.5.10-beta

### Added
- Auction prices: a Scan Prices button on the auction house reads every listing and keeps
  the lowest buyout for each item (Blizzard allows one full scan every 15 minutes). Item
  tooltips show that price, and the loot feed can use it as its Price Source, no
  TradeSkillMaster needed. Settings under QoL > Loot & Items > Auction Prices.

## 0.5.9-beta

### Added
- Blessings: Next Blessing and Next Greater Blessing keybinds, like Pally Power's. Bind
  them on the Blessings page or in Key Bindings > AddOns > Naowh Forever. Each press
  blesses the next player who needs it; the Greater key only covers classes that share one
  blessing, while you carry Symbols of Kings. In combat a key steps through the players who
  needed it when the fight began.

## 0.5.8-beta

### Fixed
- Loot feed: the bag count on a looted item is your new total, not the count from before
  the loot.

## 0.5.7-beta

### Changed
- BiS list: every gear slot laid out like the character pane. Pick it opens that slot's
  ranking for your spec, with each item's icon, source and tooltip; the chosen item shows
  in its slot with a mark when you are wearing it. Rankings For switches between your
  class's specs. The last choice in every slot takes an item ID of your own.
- The list keeps one item per slot (two rings, two trinkets). Alt+Shift-click puts an item
  in its slot. An older list moves into slots on first use; anything that no longer fits
  is named in chat.
- Export now shares the slots and the spec, so a list you import comes in slot for slot.
  Older strings still import.

## 0.5.6-beta

### Fixed
- Threat meter: no more "attempt to perform boolean test on a secret boolean value"
  errors while your target is targeting someone.

## 0.5.5-beta

### Fixed
- Blessings: no more "table index is nil" error when someone joins your group while
  their character is still loading. They show up on the bar a moment later.

## 0.5.4-beta

### Changed
- The options window opens on Settings instead of Smart Reminders.
- Window Scale goes up to 200%, for large or high-resolution monitors.

## 0.5.3-beta

### Fixed
- Blessings: no more "Auras cannot be accessed" errors on boss pulls. While the game
  keeps auras hidden the bar holds what it showed before the pull, and its buttons still
  cast; the marks and timers catch up once auras are readable again.
- The campfire icon no longer reports the Camp Benefits buff gone, or plays its sound,
  at the start of a world boss pull.

## 0.5.2-beta

### Fixed
- Blessings: the bar waits for combat to end before it is built (a reload mid-fight), the
  bar cannot be dragged in combat, and a plan changed in combat is shared once it ends. A
  Greater Blessing is only used while you carry Symbols of Kings. The Blessings switch in
  the sidebar turns the module on and off by itself.
- The flight timer works on characters without the Adventure Legacy perk tree.
- The trainer popup's Update Bars no longer mistakes a spell whose rank has not loaded yet
  for a lower rank.
- The restock reminder follows your bags while it is up, so restocking from the bank or
  mail updates it; it only pulses when it first appears.
- The threat meter only redraws for your target's threat, not every mob nearby.
- The gear set icon picker no longer errors after the UI is hidden and shown again.
- Maginor Dumas's town map pin sits with the other Stormwind mage trainers.

### Upgrading
- The addon's folder is now NaowhForever. Delete the old NaowhSmartReminders folder, or both
  load and every reminder fires twice.

## 0.5.1-beta

### Added
- Threat Meter: threat on your target for everyone in the group, one bar each, with an
  optional pull aggro bar and a warning sound. Off until you turn it on.
- Gear sets: a new set asks for an icon from the same list the equipment manager offers.

### Fixed
- The flight timer counts down from your first flight on a route instead of counting up.
  The time comes from the length of every leg of the trip, 20% shorter with Frequent
  Flier. A flight picked up after a reload mid-air still counts up.
- Town map pins and dungeon quest waypoints in Stormwind, Mulgore, Redridge and the Eastern
  Plaguelands sit where the NPCs stand. Forever redrew those maps over a wider area, so the
  auction house showed in Cathedral Square and the mage trainers south of the park.
- Restock no longer asks for 1000 of "item 0" when your ammo slot is empty.
- The trainer popup closes after Update Bars once every slot is swapped.

### Changed
- The trainer popup's Update Bars only swaps each spell's highest rank on your bars. A lower
  rank sitting beside it, such as a healer's Rank 1 heal, stays for downranking, and if your
  top rank is already on your bars nothing of that spell changes.

## 0.5.0-beta

### Added
- Trainer popup: after a trainer visit, a window lists the abilities you just learned, and
  they glow on your bars until you use them. One button swaps every lower rank on your bars,
  keyboard and controller, for the highest rank you know. Right-click a spell in the window
  to keep its lower ranks for downranking. /naowh ranks checks your bars any time.
- Blessings: each class button casts on the next member of that class who needs a blessing
  (missing first, then running out), skipping anyone dead, offline or out of range. Greater
  Blessings only when the whole class shares one, otherwise the highest single rank. Each
  class opens a player list with per-player choices, aura and Righteous Fury buttons sit at
  the front, and an assignments grid shows every paladin's plan, editable by the leader and
  assistants.
- /naowh townaudit: open an NPC's window while standing next to them to see how far the
  town map pin is from where they really stand, or that the map is missing them.

### Changed
- The addon is Naowh Forever throughout: folder, files, saved settings, chat prefix and the
  addon table other addons read (`_G.NaowhForever`). Smart Reminders is one of its modules.
  Settings saved before the rename load once `SavedVariables\NaowhSmartReminders.lua` is
  copied over as `NaowhForever.lua`. `/nf` joins the existing slash commands.
- The town map has 38 NPCs Forever added that Classic never had: Horde paladin and
  Alliance shaman trainers among other new class trainers, Dalaran's innkeeper, bankers and
  vendors in Alterac Mountains, reagent and ammo vendors and an auctioneer.
- Unlock Mode, Settings, Patch Notes and Profiles moved from the sidebar to the top of the
  window, beside the close button. The sidebar now starts with the module list.
- The logo is redrawn with smooth edges, so it stays sharp at the size the window shows it.
- Dungeon Quests, Gear Sets and BiS List are modules of their own instead of QoL tabs, each
  with its own switch in the sidebar. Turning QoL off no longer turns them off. Their
  settings stay where they were, so nothing needs setting up again.
- The restock reminder stays up while you are in town and short on something, instead of
  hiding after a set time. It goes away once a vendor has you covered, when you leave or
  when combat starts, and pulses only when it first appears. The Display Time slider is gone.

### Removed
- The Trash tab and its ExBoss trash cooldown alerts. ExBoss does not run on Forever, so
  nothing on the tab could fire. Debuff alerts are unaffected. Trash rules already saved in
  a profile or a shared pack still load, they just no longer do anything.

## 1.4.25

### Fixed
- The Trash tab now says outright that trash cooldown alerts need ExBoss. Without it the
  tab showed an empty dungeon list and "No enabled trash rules for this instance and
  spec", which reads as nothing being set up rather than the timer engine being absent.
  Both the ability list and the timings behind every alert come from ExBoss, so nothing
  on the tab can fire without it.
- The ability list on the Trash tab now says why it is empty when it has nothing to show.
  The line written for that case could not be reached, so the list sat blank instead.

## 1.4.24

### Changed
- When a personalized profile is refused because it belongs to another account, the message
  now names both BattleTags: the one the pack is signed to and the one you are logged in to
  Battle.net as. Reading them side by side shows you whether the tag saved on naowh.gg has a
  typo in it, which the old wording gave you no way to tell.

## 1.4.23

### Fixed
- A personalized profile from naowh.gg no longer refuses to import when your BattleTag is
  saved on the site with different capitals than Battle.net holds. `Silkytouch#1976` and
  `SilkyTouch#1976` are the same account, and the check now treats them that way. It was
  reporting "this pack is licensed to a different Battle.net account", which pointed at the
  wrong problem entirely, and the 30 day change lock meant you could not correct it yourself.

## 1.4.22

### Added
- A pack shared with `/nutank share` is now named **Naowh** by default, and
  `/nutank share <name>` names it whatever you type. That name is what the profile ends up
  called when someone imports it.
- Importing a pack whose name you already have offers to **replace** that profile instead of
  landing another copy beside it. Off by default, and only offered when the name is actually
  taken, so nothing is replaced without choosing it. Replacing clears the profile first, so
  none of the old contents survive underneath. "Default" is never replaced.

### Changed
- A personalized profile from naowh.gg can no longer be exported or shared onward, including
  through `/nutank share`, and merging one marks the profile it was merged into. Packs that
  did not come with a licence are unaffected, so handing work back to a curator still works
  exactly as before.
- The refusal you get when exporting a profile built on someone else's pack no longer names
  the command that bypasses it.

## 1.4.21

Housekeeping only. No gameplay or behaviour changes from 1.4.20.

### Added
- LICENSE.md, covering this addon and the libraries it embeds.

## 1.4.20

Built on 1.4.18. The 1.4.19 alpha is not included: that work is still being fixed.

### Added
- naowh.gg can hand out a personalized, signed copy of a curator's Reminder Pack, bound
  to the recipient's own BattleTag so it cannot be freely redistributed. The signature is
  checked with a real RSA-2048 verification on import. Ordinary friend-to-friend and
  self-export packs are completely unaffected.
- Russian and German locale foundations, with the English strings split into
  Locales/enUS.lua. Anything untranslated falls back to English.

### Note
- Personalized packs from naowh.gg need this version or newer. Earlier builds do not know
  about the licence appended to the string and report it as damaged on import.
- **If you ran the 1.4.19 alpha**, it rewrote your saved trash alerts one way and this
  build does not carry the code that reads them back. Those alerts will stop firing, with
  no icon and no sound. Restore the NaowhUI_SmartRemindersDB.lua backup you took, or set
  a defensive preset on the affected alerts again.

## 1.4.19

**Never released. Superseded by 1.4.20, which is built on 1.4.18.**

**Alpha. Please test this before relying on it in a key.**

This build converts your saved trash alerts when it loads: any alert still carrying the
old generic "Use a defensive" line is rewritten to a blank one. Nothing is deleted, but
the conversion is one way. If you install this and then go back to 1.4.18 or earlier,
every converted alert stops firing, with no icon, no sound and no error to tell you. Back
up NaowhUI_SmartRemindersDB.lua before you load it if you want a way back.

### Changed
- A trash alert with no defensive preset chosen now calls out whichever preset the spec
  has active, instead of saying a generic "Use a defensive". That phrase was never typed
  by anyone: the page has had no text box since these moved from free text to presets, so
  every alert switched on from the dungeon list carried it.
- An alert whose preset belongs to another spec now falls back to the active preset as
  well. It used to go silent. Copy From Spec and shared packs both produce this.
- The Defensive preset dropdown reads "This spec's active preset" where it read "None".
## 1.4.18

### Fixed
- A trash alert or boss reminder bound to a defensive preset now stays quiet when nothing
  on that preset is ready. It was still playing its sound and speaking its line -- "Use a
  defensive", on a rule that had never been given one of its own -- over icons that had
  already gone dark for the same reason. A reminder carrying only custom text is
  unchanged and still fires every time.

## 1.4.17

### Fixed
- Picking a dungeon by name while the Instance ID field was showing saved the id last
  typed in that field instead of the dungeon chosen, then snapped back to it.
- Choosing a dungeon no longer redraws the page. On an alert too incomplete to have saved
  yet, that redraw threw away the spell id, name and switches already typed into it.
- The Instance ID field no longer pushes the Unit dropdown past the bottom of its panel.

## 1.4.16

### Changed
- A debuff alert names the instance it belongs to. "Every dungeon or raid" is gone from
  the list, and a new alert starts on the first dungeon instead of everywhere. An alert
  already saved for everywhere keeps firing everywhere and shows as "Instance 0" until you
  rescope it; "Another instance (by ID)" still accepts 0 if that is what you want.

## 1.4.15

### Fixed
- A debuff alert can be scoped to an instance the dungeon list does not carry again. That
  list comes from ExBoss and holds only dungeons it has trash data for, so without ExBoss
  it is empty and nothing could be scoped at all, and a raid was never in it. The list
  gains "Another instance (by ID)", which brings the id field back.
- A second boss callout arriving while the first is still on screen no longer keeps the
  earlier cast's target name under it.
- The target name no longer overlaps the callout at small Text Size settings. It is drawn
  at a fixed size while the row spacing follows Text Size, so the two could collide.

## 1.4.14

### Fixed
- The target name on a boss cast sat a full row clear of the callout, with an empty row
  between them, because the row it used belongs to a reminder's own text and that text is
  not shown for a boss-mod callout. It could be drawn and still be impossible to find. It
  now takes the row directly beside the callout, and moves out one only when a reminder is
  actually using that row.

## 1.4.13

### Removed
- Show What Is Incoming. Its spoken half went in 1.4.11 as a second voice over BigWigs, and
  the line on its own did not earn a row on the alert. The label no longer travels from the
  boss mod to the display at all, and the rows that moved to make space have moved back.

## 1.4.12

### Removed
- Show Target on Trash Casts, and everything behind it. A trash cast was matched to the
  rule that predicted it by spell id, and the client keeps that id secret for every unit
  that is not you or your pet, so the match never succeeded and the repeat never once fired
  in a dungeon. The per-rule Show target on cast and Sound on cast switches go with it.
  Rules and packs already carrying those fields keep them untouched.

### Changed
- The diagnostic trace says when a boss cast names somebody even with no alert on screen to
  put the name on. One traced dungeon now answers which abilities carry a target name at
  all, which previously took a pull per guess.

## 1.4.11

### Changed
- Debuff Alerts pick the instance they apply to by name, from the same dungeon list the
  Trash tab uses, instead of a typed Instance ID. An id the list does not carry keeps an
  entry of its own, so an alert set for a raid is not quietly moved to everywhere.

### Removed
- Say What Is Incoming, one release after it arrived. BigWigs already announces its own
  warnings, so this was a second voice saying the same thing a beat earlier.

## 1.4.10

### Added
- Say What Is Incoming, on Setup. Speaks the boss mod's own name for the ability just
  before the callout: "Frontal", then "Vampiric Blood". Said on its own rather than folded
  into the callout, so it still works when your callout is a sound file instead of speech.
  The bar's count is left off what is spoken -- "Frontal", not "Frontal one".

### Fixed
- The diagnostic trace said "no name, asked if it is on you" for a cast carrying no target
  name, describing a marker that was removed in 1.4.7. It reads "cast names nobody" again.

## 1.4.9

### Fixed
- Show What Is Incoming showed nothing on DBM. DBM identifies a timer by a numeric id
  rather than by its text, and the line was using that id; the message DBM sends alongside
  it is the label now. BigWigs was unaffected, since its identity is the bar text.
- The alert no longer leaves an empty row between the callout and the target name when the
  incoming line is switched off.
- Show Target on Boss Casts takes effect the moment you tick it, instead of waiting for the
  next pull. Its trash counterpart already did.

## 1.4.8

### Added
- Show What Is Incoming, on Setup. The alert gains a line naming the ability the boss mod is
  timing -- "Frontal", "Debuffs", "Boss Buff" -- so it says what is coming as well as what
  to press. The name is the boss mod's own bar text, which arrives as ordinary text beside
  the timer, so nothing is guessed and nothing restricted is read. Only for reminders driven
  by a BigWigs or DBM timer, since that is where the name comes from. Off until you ask.

## 1.4.7

### Removed
- Mark Me When I Am Targeted. It could never have worked. The game answers "is this cast on
  you" as a protected value, and the only way to put that on screen is a call the game
  refuses from addons, so it failed silently from the day it shipped in 1.4.1. Nothing is
  really lost: when a cast does carry a target name, that name is yours when it is on you.

### Changed
- The diagnostic trace now says why a boss cast did or did not put a name up: the switch is
  off, nothing was on screen to write on, or the cast names nobody.

## 1.4.6

### Fixed
- The rule editor no longer reads Enabled for a trash ability nothing is saved for. It was
  showing a would-be rule's defaults while that ability's own switch in the list correctly
  read off, and the missing Remove button was the only sign nothing was there. Editing a
  field on an ability you have not switched on now creates it disabled, which is what the
  editor in front of you says it will do.

## 1.4.5

### Added
- A boss cast puts the target's name on the reminder that is already on screen. The client
  will not say what a boss is casting, so a reminder could never be matched to the cast it
  warned about; whether a cast names somebody is the one thing it does answer plainly, so
  the warning already showing picks the name up when the ability goes out. Needs Show
  Target on Boss Casts, on the Dungeon Bosses or Raid Bosses tab. Boss units only: the name
  belongs to whatever is casting at that moment, which on a boss is the mechanic you were
  warned about and in a trash pack would be a guess.

### Changed
- The Trash dungeon list only offers Every dungeon when there is a saved rule no dungeon in
  the catalogue accounts for, instead of always carrying an entry that opens an empty list.

## 1.4.4

### Changed
- Show Who Is Targeted is now two switches, each on the page that owns the reminders it
  affects. Show Target on Boss Casts sits on the Dungeon Bosses and Raid Bosses tabs,
  Show Target on Trash Casts on the Trash tab, and both start off. Mark Me When I Am
  Targeted stays on Setup, since it applies wherever a name shows. The old setting is not
  carried over, so if you had it on, tick the one you want.
- Debuff Alerts are grouped by the instance each one is set for, under headers that fold
  shut. Alerts set for every dungeon or raid get their own group at the bottom. Folding a
  group leaves whatever is selected inside it open in the editor.

### Fixed
- A trash callout bound to a preset names every cooldown in the set, not just the one that
  won the pick. With Call Together ticked on Anti-Magic Shell and Death's Advance it said
  "AMS"; it now says "AMS and Death's Advance", the same line the boss callout has always
  spoken for a set.
- The Trash and Debuff Alerts lists stay where you left them. Picking a rule rebuilds the
  page, which sent the list back to the top, so anything below the fold scrolled away the
  moment you clicked it.

## 1.4.3

### Changed
- The spec list in Merge a Profile In now matches the one in Import: rows grouped by
  class and coloured by it, read as "Protection (Tank)" rather than "Protection
  Warrior", with Select All and Deselect All beside the heading.

## 1.4.2

### Changed
- Show Who Is Targeted and Mark Me When I Am Targeted now start off rather than on. Both
  are in Setup, and the trash callout repeat is behind them too, so no part of the cast
  target display shows up until one of them is ticked.

### Fixed
- The Merge a Profile In window sizes itself to the string you paste. A profile covering
  a lot of specs pushed the last rows and both "Also take their..." switches out past the
  bottom of the window, with Merge and Cancel sitting over the middle of the spec list.

## 1.4.1

### Added
- Boss casts that name a player now show that player's name on the alert in class colour,
  with YOU beside it when the cast is on you. Two switches in Setup to turn either off.
  Display only; the game does not let an addon read who was named, so the voice cannot
  follow it.
- Trash callouts get the same treatment. A trash rule warns ahead of the cast, so there is
  nobody to name yet when it fires; it now comes back at the cast itself carrying the
  name. Only for abilities that name a target, and silent unless you ask for it. Show
  target on cast and Sound on cast, per rule, on the Trash tab.
- Copy From Spec on the Debuff Alerts tab, for moving debuff alerts between specs.
- `/nutank share` exports your profile even when it came from someone else's pack, for
  handing changes back to whoever maintains it. The pack is marked so they can see it is
  theirs coming back.

### Changed
- Trash Alerts and Debuff Alerts, renamed from Trash & Debuff Alerts and Debuff Sounds.
- Each Copy From Spec now moves only its own kind. The trash one used to drag debuff
  alerts across with it.
- No more 32 rules per spec limit on trash and debuff rules.
- Trash and debuff rules save as you change them. The Save button is gone.
- The rule editor is one page in two columns instead of three tabs.
- Dropped the custom text field. A preset writes the callout line.
- The Trash list no longer repeats the dungeon name under the dropdown that names it.
- BIGWIGS/DBM MESSAGES is now BOSS REMINDERS, with an Add Reminder button. Cast triggers
  live in that editor too, so naming it after messages hid half of what it does.

### Fixed
- Remove no longer overlaps Test in the rule editor.

## 1.4.0

### Added
- Merge a Profile In, on the Profiles tab. Paste a string somebody else maintains, tick
  the specs you are accepting, pick which of your profiles it goes into, and it merges
  rather than landing beside them. A ticked spec is taken whole, lists, bindings and
  trash rules together. Nothing outside the ticked specs can move, which matters because
  a contributor usually works in a copy of the whole profile they were given. Per-boss
  reminders come across only for the specs they record. Raid reminders, callout lines and
  their display and sound settings record no spec and are left behind unless asked for.
- Shadowmeld joins Stoneform as a cooldown-gated debuff voice. Pick it as the sound on
  a debuff rule and it stays silent while Shadowmeld is on cooldown, unknown, unusable
  or you are dead. The two gate independently, so one being down does not quiet the
  other.
- New voice clips for both racials, supplied by Naowh, listed as "Stoneform - Naowh" and
  "Shadowmeld - Naowh" to match his other sound files.

### Fixed
- A spoken callout uses the name you gave the spell. Renaming Vampiric Blood to Vamp
  renamed the label beside the icon but not what was said, so the two channels
  disagreed about the same spell.

### Changed
- The options window is two levels: Smart Reminders, Custom Notes and Profiles across the
  top, with Setup, Cooldown Presets, Dungeon Bosses, Raid Bosses, Trash and Debuffs under
  Smart Reminders. Custom Notes is dimmed and says what it will do.
- The Trash page shows one dungeon at a time as a collapsible section, with the spell icon
  and a switch on every ability. Rows are half their old height, so a dungeon's abilities
  fit without scrolling the list.
- Debuff sounds have their own tab beside Trash. They answer to an aura rather than a
  dungeon, and were previously reachable only through a bucket at the foot of the trash
  list. Each page keeps its own selection.
- Copy From Spec sits beside the page heading, since it acts on the whole spec rather
  than on the selected dungeon.
- Trash and debuff callouts draw on the defensive alert itself, replacing what is in it,
  instead of putting a second icon and line on screen beside it. A rule with a preset
  rebuilds the alert's slots from that preset; a rule with only custom text takes the
  alert's own text row and puts the slots away, so a defensive left there by the spec's
  preset no longer shows beside the line. Each rule keeps its own sound and Speak
  Callout setting.
- The separate Ability Reminder display is gone. Every reminder now draws on the
  defensive alert, so there is one placeable display instead of two showing the same
  kind of callout in two different styles. Its Reset Ability Reminder Position button
  and its own text colour setting go with it; the alert's Defensive Text Color now
  covers both the slot labels and the authored line.
- Every trash ability row carries a switch, reading off until a reminder exists behind
  it. Turning one on writes the rule the editor would have written and opens it.
- Reminder icons carry the 1px black edge the priority slots already had.
- Callout text is now Custom text, and it greys out while a preset is supplying the line.
  What is typed there is kept and returns when the preset is cleared.
- Text in the trash editor's input boxes is inset rather than sitting on the border.
- The Trash and Debuffs pages fit the options window, so the page itself no longer
  scrolls. The editor's Cast, Text & Test and Voice settings sit behind tabs instead of
  stacked panels, Save and Remove moved onto that row, and the page reports the height
  it actually draws rather than a fixed guess. The ability list keeps its own scrollbar.
  Switching tab shows a different panel and nothing else, so a preset chosen or text
  typed and not yet saved survives the switch. Save, Test and Remove sit above the tabs,
  since they act on the whole rule rather than on one group of its settings.

### Validation and limits
- All 18 offline regression suites pass; runtime Lua syntax checked.
- This is a large UI rework and none of it has been verified in the client. The window
  layout, the split Trash and Debuffs pages, the single reminder display and both new
  dialogs are offline-tested only.
- The two racial voice clips are installed and wired but have not been heard, and their
  encoding is unverified.
- Showing who a boss cast is aimed at is not in this build. It is display only and
  cannot be meaningfully tested outside an instanced pull, so it ships on alpha first.

## 1.3.9

### Added
- Importing a single-profile pack can point every character on the account at it, including
  characters logged into later, instead of leaving each alt to be switched by hand. The
  toggle names how many characters it will move and is on by default.
- Copy From Spec on the Trash & Debuff page brings another spec's trash and debuff rules
  across, leaving anything already saved here alone and saying what did not fit the
  32-rule limit.

### Fixed
- Setting an account-wide profile now turns per-spec profile switching off, instead of
  every alt being moved back to the previous profile on its next login. Spec choices are
  kept and come back if switching is turned on again.

### Validation and limits
- All 17 offline regression suites pass; runtime Lua syntax checked.
- User confirmed the account-wide import in game, which is how the per-spec switching
  conflict was found. That fix and the trash rule copy are not yet client verified.
- Copied trash rules name the spells the source spec casts. Copying across classes is
  allowed and warned about rather than blocked.

## 1.3.8

### Added
- Bar callouts and BigWigs/DBM message reminders run side by side on the same ability:
  bars keep the ability's own preset and warning time, messages fire the message
  reminder's preset.
- Copy From Spec brings BigWigs/DBM message reminders across with the abilities, remaps
  their preset to one this spec owns, and counts them in the spec picker.

### Fixed
- The ability Test button tests the bar callout instead of refusing when the ability also
  has a message reminder, and points at that reminder's own Test.
- A message reminder is no longer muted by the repeat window when the bar callout for the
  same ability just named the same defensive.
- A reminder saved under DBM's own spell id is matched against the BigWigs key it is
  normalised to, instead of both callouts firing for one message.
- The Setup page counts message reminders when deciding whether this spec has anything
  set up, so a spec whose whole setup is reminders no longer reads as empty.

### Validation and limits
- All 16 offline regression suites pass; runtime Lua syntax checked.
- User confirmed in game. Both callouts share one reminder frame, so when a bar callout
  and a message land close together the later one replaces the display.

## 1.3.7

### Added
- Trash & Debuffs setup with profile/spec rules, EXBoss readiness predictions, preset selection, and pack sharing.
- Native player/party aura sounds and bundled English voices, including Stoneform calls gated by racial readiness.
- Test buttons for individual BigWigs/DBM message reminders.

### Fixed
- Reused and recurring trash timers can notify on later cooldown cycles without replaying same-cycle corrections.
- Invalid debuff spell and instance IDs are rejected instead of silently retaining previous values.
- Message-only abilities direct tests to their message rows instead of reporting missing talents.
- Improved ability-picker spacing, moved external-call help above its toggle, and colored the Healer label green.
- Reminder TTS uses the addon voice volume and reports preview failures.

### Validation and limits
- All 15 offline regression suites pass; runtime Lua syntax checked with Lua 5.1.
- User confirmed Stoneform voice in combat and a dungeon. New repeat-cycle fixes, message tests, and UI layout still need client verification; after screenshots are unavailable.
- EXBoss integration predicts readiness, not confirmed casts or targets, and depends on inspected internal scheduler methods.
- Native aura registration changes defer during combat/encounter restrictions. No specific-bleed icon or personal-target Shadowmeld voice is implemented.

## 1.3.6

### Added
- Account-wide Enable Healer Reminders switch in Setup, enabled by default.
- Healer Reminder tagging for ability preset callouts and authored reminders.
  Tags travel with shared packs; each player's opt-out stays personal.
- Turning healer reminders off cancels their pending alerts and hides their
  active displays. Existing reminders remain untagged until a curator marks them.

### Fixed
- BigWigs messages containing protected target text can trigger reminders using
  their readable spell key, including Thunder and Lightning on Adderis and Aspix.
  Protected text is discarded; this does not add player-target detection.

### Validation
- All 13 offline regression suites pass; runtime syntax checked with Lua 5.1.
- Boss-message audit passed 1,980 synthetic dispatch checks across 990 numeric
  module/key pairs. New message regression cases cover cancellation and counters.
- Live encounter validation and screenshots for these changes are outstanding.

## 1.3.5

### Fixed
- Restore the settings preview after switching profiles, including switching back
  from profiles with the icon or master switch disabled.
- Cancel stale raid reminders after deletion, replacement, disable, profile changes,
  or encounter changes. Two reminders sharing a boss bar can both fire.
- Handle early boss-mod broadcasts, exact bar cancellation, and delayed callouts
  when a bar identity is reused.
- Recover sound lookup when SharedMedia loads late, invalidate cached sounds on
  registration, and clear timeline sounds when their settings change.
- Validate nested imported settings before modifying profiles, preserve supported
  legacy shapes, and correct account-default fallback when deleting profiles.
- Keep the alert frame from overwriting the addon's global namespace.

### Performance
- Cache sound lookups, coalesce settings and spell refreshes, reuse dialog controls,
  and prune observations outside encounters.
- Reuse the main Setup page's controls and rebind their profile callbacks. Dynamic
  boss/profile editor frame growth is not fully addressed by this change.

### Validation
- All 12 offline regression suites pass under Lua 5.1, including 38 recovery cases,
  profile-preview restoration, real serializer round trips, and Setup control reuse.
- The tester reported all requested in-game checks passed after loading recovery.2.
  No exact client build, screenshots, profiler capture, or taint log was supplied.
- Combat CPU improvement and universal taint-free behavior are not claimed.

## 1.3.4

### Fixed
- Preserve charge counters across temporary API changes and avoid crediting a
  completed recharge twice, preventing false ready calls for charge abilities.
- Restore Feint charges when recharge data is unavailable and disregard its old
  inferred recharge estimate that could leave reminders silent for minutes.
- Keep delayed message reminders through unrelated settings refreshes and cancel
  them when their reminder is disabled, deleted, or replaced.
- Handle boss messages emitted at encounter start before setup finishes.

### Added
- Opt-in BigWigs/DBM message triggers with a delay and defensive preset selection.
  Existing timer-bar bindings remain for abilities without an enabled message reminder.
- BigWigs ability selection and a single-page reminder editor. Time-in-combat
  trigger creation is removed.
- Bounded charge-model diagnostics included in exports even when trace is off.

### Validation
- 106 automated regression checks pass under Lua 5.1.
- User verified Death's Advance behavior, boss-message triggers, and Feint recovery
  with icons and sound in game. Fiery Brand has automated coverage only.
- A newly reported Windwalker issue is under investigation and is not claimed fixed.

## 1.3.3

### Fixed
- Track charge spells across configured presets, including casts before a boss pull,
  and share readiness between base and replacement spell IDs.
- Restore only completed charge recharges instead of prematurely filling the stack.
- Retry an empty early warning until its boss timer expires, allowing a cooldown
  that becomes ready during that window to be called once.
- Exclude BigWigs cast bars from timer reminders, including Chillstorm uptime.
- Exclude the verified Demonic Rage uptime bar and message on Xathuux.

### Validation
- The reporter confirmed in-game testing of the fixes.
- Fiery Brand has automated coverage; no separate live Fiery Brand result was supplied.
- Unknown ordinary uptime bars retain the existing filtering behavior.

## 1.3.2

### Fixed
- Removed a charge-tracking fallback that could mark an empty defensive as ready
  before its recharge finished, causing callouts for unavailable abilities such
  as Death's Advance.

## 1.3.1

### Fixed
- Exclude developer tools and regression scripts from release packages.

## 1.3.0

### Added
- Dedicated Profiles tab for profile management and import/export.
- Minimap launcher with the NaowhUI logo and a saved, draggable position.
- Reminder Font selector shared by defensive, ability, and raid reminder text.
- Hide After Casting toggle, off by default. Dismissal uses the displayed icon
  independently of speech; protected visibility falls back to the display timer.

### Changed
- Icon Display Duration defaults to 3 seconds, adjustable from 1 to 15 seconds.
  Existing profiles retain their saved duration.
- Removed Where It Runs and its global dungeon/raid gates. The main enable
  switch and per-boss choices remain in control.
- Bundled the NaowhUI logo for the addon-list icon and colored Naowh blue in the title.

### Fixed
- Charge tracking could spend a charge twice, invent one after a failed read,
  or credit the same recharge twice. Death's Advance recovery and callouts were
  verified in Ruby Life Pools on the test build.
- Skipped warnings and warnings with empty or unusable presets no longer erase
  the previous icon before its display timer expires.

## 1.2.0

### Changed
- Importing a pack names each row by its spec rather than its class. A Warrior's
  three rows all read "Warrior (DPS)" and "Warrior (Tank)" before, with no way
  to tell Arms from Fury; they now read "Protection (Tank)", "Arms (DPS)",
  "Fury (DPS)". Class colouring is unchanged, and it is what tells apart the
  four spec names that belong to two classes each.

### Added
- Select All and Deselect All on the pack import, beside the name field. A pack
  can carry all forty specs, so bringing in one or two of them meant thirty
  eight clicks of turning the rest off.

## 1.1.2

### Fixed
- A defensive with charges could be called while you had none of them. At zero
  charges the spell's cooldown is not running, and the charge tracker read that
  idle cooldown as proof a charge was in hand, so it handed itself one. Death's
  Advance was named at 0 of 2 on Rav'i because of it. The tracker now believes
  the client when it says a charge is still recharging.
- Where the game will state your real charge count, which is everywhere outside
  a dungeon or raid, that count is now used instead of the tracked estimate. The
  estimate could only drift, and had nothing to correct itself against for the
  rest of the session once it had.

## 1.1.1

### Fixed
- A flood of "table index is nil" errors while BigWigs' options or Edit Mode
  were open. The preview bars BigWigs raises there are not real boss timers and
  carry no ability, and filing one under the ability it does not have was the
  error. Those bars are now ignored, which is what should have happened anyway:
  there is nothing to remind anyone about.

## 1.1.0

### Added
- Window Scale, on the setup page under Options Window. Sets the size of the
  options window and every editor it opens, from 50% to 100%, for people whose
  screen the config UI did not fit on. Saved for the computer rather than in
  the profile, so switching profile leaves it alone and an exported pack never
  carries it to someone on a different monitor.

## 1.0.1

### Fixed
- Reminder Packs could not be imported or exported on the CurseForge and Wago
  builds, which reported "The serializer libraries are missing from this
  build." Those builds pulled an unrelated library that shares the LibSerialize
  name, so nothing registered the serializer the pack code reads. Local
  installs were never affected.

### Changed
- The version moves on every release now, so the number in the TOC and beside
  the build stamp identifies which files a report came from. Three separate
  1.0.0 files were published while this was not the case.

## 1.0.0

First release.

### Added
- Boss ability reminders driven by BigWigs or DBM. Pick the boss addon under
  Hook Into; every reminder rides its bars and messages rather than a timeline
  of our own.
- Dungeon Bosses and Raid Bosses tabs: this season's pool read from your own
  Dungeon Journal, with an ability picker per boss. Boss pages start blank and
  abilities are added deliberately.
- Cooldown Presets: named lists of defensives, stored per spec. A preset binds
  to an ability, with its own warning time.
- Callout display: icon and text with independent anchors, sizes and colours,
  placed from the Customize Anchors toolbar.
- Ability Reminders, assignable to a role, class, spec, name or subgroup with
  AND/OR combinations. Text, icon, bar, ring, timer, chat line, text-to-speech,
  nameplate glow and raid-frame glow displays.
- Triggers: a boss mod bar or message, a cast starting or finishing, a phase
  starting, time after pull, time in combat, and an aura applied at a stack
  threshold.
- Skip When Already Covered, which drops a call when a big defensive or
  external is already up, for as long as you set Your Own Cast Covers You For.
  On a tank spec, boss callouts fire only for the tank the boss is actually on;
  DPS and healer specs are never gated.
- Call Together: tick two or more cooldowns on a preset and they are called as
  one -- "Vampiric Blood and Icebound Fortitude" -- showing as a single row
  named for the call. One on cooldown is left out rather than holding the
  callout back.
- Equipped on-use trinkets sit in the cooldown preset picker beside the spec's
  own defensives, and the list follows a gear swap without a reload.
- Announce in Chat, including calling for an external by name.
- Observed timings: what the boss actually did on your own pulls, recorded per
  difficulty, with a reminder built from one click.
- Reminder Packs: a whole profile as one string, with preview before apply.
- Standalone options window at `/smartreminders`, `/nsr` or `/naowh`. Own
  theme, widget kit, profiles and SavedVariables, with no EllesmereUI
  dependency.
- Diagnostics under `/nutank`: `status`, `cds`, `keys`, and a trace recorder
  with a copyable export. Pretend Tank lets a DPS reproduce a tank-buster
  report.
- Every option ships off by default.
- Callouts on any spec, not only ones with a tank role. A raid-wide hit a DPS
  answers with a personal is the same question a tank buster asks, put to
  somebody else. Adding an ability for a spec is the opt-in, and abilities are
  stored per spec, so a spec nobody has set up still calls nothing.
- Call for an External is decided per ability as well as per spec, from that
  ability's own cog, for hits the raid was never going to answer.
- Warning Time takes a negative number, calling a defensive that many seconds
  AFTER a mechanic lands rather than before it, for a hit whose useful moment
  is once it is over.
- Copy All Dungeons / All Raids From a Spec, at the top of the boss lists:
  another spec's whole setup in one press, instead of repeating the per-boss
  copy on every boss. Raids and dungeons stay on their own side, and anything
  the target spec already has is kept.
- Saving a profile under a name already taken offers to overwrite it, naming
  the profile and what replacing it costs, rather than refusing.
- A boss page with nothing on this spec says whether the profile has work under
  other specs, since an empty page otherwise reads as lost data.
- `/nutank tanksheet` cross-checks the curated tank-ability list against the
  Dungeon Journal, separating entries the journal contradicts from ones it
  simply has no role flag for.

### Changed

- Ability Reminders is marked coming soon: the tab is dimmed and opens a note.
  The same reminders are authored per boss in the meantime, which is where that
  page reads them from.
- Importing a pack never overwrites anything. It lands as a new profile under a
  name you choose, so going back to your own profile finds it as you left it,
  and a pack that does not mention a spec no longer drops the one you had.
- A whole profile exports in one string, every spec it holds, with the display,
  sound and behaviour settings alongside it for the importer to take or leave.

### Fixed before release

Found by testers on live keys and raid nights between the release branch being
cut and 1.0.0 going out.

- Tank callouts fired for both tanks on abilities the addon could not attribute
  to a boss unit. Every ability in the pool was checked against its BigWigs or
  LittleWigs module and given the slot that casts it, so a call now goes to the
  tank holding that boss. Abilities whose module never settles a slot keep the
  old behaviour rather than risk silencing a real one.
- A tank holding an add that occupied a boss frame was called for the boss's
  own ability, most visibly on Ula'tek.
- Threat momentarily reading low -- mid-cast, across a stage change, while a
  boss was untargetable -- refused callouts for the tank who had the boss the
  whole time.
- Charge defensives could read ready while on cooldown: a spell's cooldown was
  being stored as its recharge, and for Guardian of Ancient Kings those differ
  by nearly three minutes.
- A repeating ability called on some casts and not others. A boss mod's bar for
  the next cast replaced the callout already due for the current one, and a
  second announcement of the same cast could cancel the next one outright at
  short warning times.
- A debuff bar sharing an ability's spell id could take that ability's callout
  with it when it expired.
- A defensive was named over one still running.
- Rav'i's Triple Shot was treated as a tank hit. Blizzard's own Journal calls it
  a healer mechanic and it is not threat-driven, so it no longer carries the
  tank-hit sound or the tank tag in the ability picker.
- Two boss abilities landing within a second of each other, as Entombed
  Sentinels' do, announced the same defensive twice. A repeat of the same pick
  is now muted for three seconds across different abilities, while a genuine
  repeat of the same ability seconds later still gets its own line.
- Raid-frame glow did nothing for anyone using EllesmereUI raid frames, with no
  error. The library it asks first returns nothing for those frames, so the
  buttons are now looked up directly when it comes up empty.
- The options window opened with every tab blank. One file had passed Lua's
  200-local ceiling and stopped compiling, taking every page builder with it.
- A dropdown could open behind the row below it, a colour swatch could go
  unreachable, and the ability editor's layout could overlap at some sizes.
