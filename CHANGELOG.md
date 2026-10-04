# Changelog

## Unreleased

### Added
- Settings: click the dot beside a setting you changed to put it back to its default; hover it to
  see what the default is.
- Aim Trainer (QoL > Travel, on by default): a shooting game for flight paths. Click the other
  faction's races as they pop up, in Hexakill (six targets at once, the default), Gridshot (three)
  or Reflex (one at a time, shrinking away), for a score, accuracy, combo and reaction time, with
  your best kept for every character. A miss costs 50, so spam-clicking doesn't pay. Every round
  is 30 seconds with the same targets for everyone, so scores compare fairly on its Leaderboard:
  once you have a best and with Share My Scores on, your bests are swapped with the players you
  group with and your guild's, and the results card shows your rank. Open it with /nfaim or the
  Flight Timer's Games button, or pick it under Flight Games to open by itself when a flight
  starts; it closes when you land or enter combat. Move it in Unlock Mode.
- Flight Games (QoL > Travel, under the Flight Timer): one choice of what opens by itself when a
  flight starts, Nothing, the Quiz or the Aim Trainer (the default).
- Training Planner: a waypoint to your nearest class trainer, from Waypoint to nearest trainer at
  the top of the planner, the Waypoint button on the level-up toast, or /nf trainer. With TomTom
  loaded, it uses TomTom's arrow.

### Changed
- QoL has a Character tab: Character Panel, Slot Marks and Naowh Score moved there from the BiS
  List's settings, and Supporter Badges from Interface. The BiS List's page keeps what is about
  your BiS.
- The Naowh Character Panel and Bag Marks are now on by default. With EllesmereUI's character
  panel in use, you're asked once at login which one you want.
- Loot Feed: Spacing goes down to -1, now the default, so neighbouring lines share one border
  instead of two. Its coins line up on every line, and it is the first card on QoL > Loot &
  Items. Edit it right in its preview: drag its right edge for width and a line's bottom for
  height, the wheel for text size (Shift: spacing, Ctrl: lines), click a line's value or bag
  count to show or hide it, and right-click a line for what it shows.
- QoL's Leveling & Travel tab is two again: XP (XP Bar, XP per Hour, Group XP) and Travel
  (Flight Timer, Flight Games, Quiz, Aim Trainer).
- Quiz: Quiz While Flying is gone, replaced by Flight Games, where the Aim Trainer now opens on
  flights by default. If you had turned it off, Flight Games is set to Nothing; the Quiz keeps
  its campfire toggle.
- XP Bar: click a text on the preview, or an empty spot around the bar, to pick what it shows,
  as before the settings rebuild. The eleven text dropdowns under it are gone; search still
  finds each spot and opens the card.
- Flight Timer: a new look. A card with where you left and where you land, the time left in
  blue, and a slim track you ride along on your faction's flight mount, with each stop marked on
  it (filled once passed) and the next stop and its time under it. Land Early is now a Land
  button beside Games.
- Character Panel: the grey Legendary badge for players without a badge is now off by default;
  turn on Legendary Badge Preview (QoL > Character) to see it. Your own badge still shows.

### Fixed
- Naowh Score: no more Lua error after seeing more than 300 players, like in a busy city.
- Hovering items and players no longer fills BugSack with "secret value" errors on Forever: the
  upgrade line and bag arrows wait while the game keeps your stats hidden, Naowh Score copes with
  a player it can no longer read, and the supporter plate and ID lines stop hooking the game's
  tooltip, which was reported breaking its own player-name colours.
- Naowh's Forge: no more Lua error when a macro line is just a "/" with no command yet.

## 0.5.19-beta

### Added
- Naowh's Forge (/nfmacros, the Macros page, or its minimap and top bar button): a window for
  your macros. My Macros lists your account and character macros and your pack's; the editor
  colours a macro as you type it, in a code font (JetBrains Mono), shows how many of the
  game's 255 bytes it uses, numbers its lines, marks the ones that
  will not work with what was meant (/castsequnce: did you mean /castsequence?), and beside it
  Explain says what each line does in plain words. Build conditions with Conditions, insert
  commands from Commands, pick an icon (star your favourites), Shorten a macro, and drag its
  icon to a bar. Smart Macros shows the macros the module keeps up to date with what each will
  use right now; the Library holds Naowh's macros once you import them. Export and Import share
  macros as a string.
- /nf settings, rebuilt on the Dungeon Journal's look. Every feature is a card with its
  switch and a line saying how it is set; open, its settings sit in groups, two to a line. A
  setting that is off says what it needs, a dot marks what you changed, and each card can reset
  itself. Search finds a setting by its name and opens its card.
- Every module has one Settings page, with a card on top saying where you stand. What is not a
  setting moved to the module's own window: Discovery's books (/nfdiscovery), Macros
  (/nfmacros), Action Bars (/nfbars), AuraBuffs' consumables and debuff sounds (/nfbuffs), Smart
  Reminders' presets and boss pages (/nfreminders), Gear Sets, Stat Weights, and the Dungeon
  Journal's recent kills and loot (the skull on its title bar). Opening a window from /nf closes
  /nf, and Back to Settings in its title brings you back.
- Live previews on the settings cards of everything you see on screen: the Top Bar, Crosshair,
  Mouse Ring, Focus Cast Bar, Loot Feed, XP Bar, XP per Hour, Group XP, Flight Timer, the BiS
  drop alert, the threat meter, swing timer bars, buff and camp reminders, low health, the
  gear and trinket bars, the craft timer, tracking and food bars, and Smart Reminders' displays,
  each in the moments you see it, following every setting as you change it. A moment that only
  exists with a setting on (faded, in combat, idle...) only has its tab while that is on.
- Top Bar: arrange its buttons right in the preview: drag to move, x to remove, + to add.
- Blessings: edit the bar right in its preview: right-click a class for its blessing, click the
  aura for yours, x hides the aura or Righteous Fury button and + brings it back, the wheel
  sizes the buttons (Shift: spacing) and the gap after the aura drags wider or narrower.
- Threat Meter: edit it right in its preview: drag the corner to resize, click the name or the
  status line to change them, the wheel sets row height (Shift: spacing, Ctrl: text size) and
  right-click a row for what it shows.
- Naowh Forever in the game menu (Esc), by the other addons' buttons. Game Menu Button on the
  Settings page turns it off.
- Profile strings now carry every module's settings and Unlock Mode positions, not only Smart
  Reminders'.
- The sidebar dims the modules you have off and lists them last in their group; a module with a
  window of its own opens it from the icon on its row.
- Discovery: a waypoint also opens the world map on it (Open the Map), a waypoint to your
  librarian, and new settings: tracker scale, map pin size and hand-in pin, and the nearby
  alert's ping and chat line each on their own.
- Auto Combat Logging: log raids and dungeons each Ask Once, Always or Never, keep logging when
  you leave, a chat line when it starts or stops, and the Advanced Logging prompt as a choice.
- Blessings: one Settings page with a live preview of the bar, in a group and out of range. The
  assignments grid, Auto-Assign and the preset moved to Blessings' own window: /nfbless, Open
  Blessings on its settings page, or Assignments on a class button's right-click menu.
- Quality of Life in 7 tabs instead of 13: Interface, Cursor, Combat, Questing & Group, Loot &
  Items, Leveling & Travel and System. Mouse Ring is one card, the two copy shortcuts are one,
  the auction price line sits with Auction Prices, Trainer moved to Training Planner and Naowh
  Score to BiS List.
- Credits page with the team, the people we thank, and the data and libraries Naowh Forever is
  built on; Discord, Website and GitHub links in the sidebar.
- Patch Notes as cards, the newest open, each change with where it lives.
- A smaller search box by Unlock Mode, the Dungeon Journal's boxed tabs, and no more
  UNTESTED / READY tags or "Preview build" notes. Minimap Icons moved to Settings.
- QoL > Interface, Town Map Pins: Mailboxes, every mailbox on the world map, in towns and out in
  the world, even with Town Pins Only in Capitals on (off until you turn it on). Positions come
  from Wowhead's WoW Forever database.
- QoL > Questing: On-Screen Buttons (off by default) puts Invite and Disband on your screen,
  stacked or side by side, to move in Unlock Mode. Invite invites your target, in combat
  too; Disband removes everyone (group leader, out of combat).
- QoL > Loot & Items: Auto-Replace Enchants (off by default) says yes for you when an enchant
  would replace the one already on an item. Hold Shift to be asked.
- Unlock Mode: right-click anything on screen for Element Options, which leaves Unlock Mode and
  opens that element's settings in /nf, its section already open.
- Swing Timer: Color by Seal for paladins (Swing Timer > Bars, under Seals). The melee bars take
  the color of the seal you have up, one color per seal, Seal of Martyrdom included. In combat
  that is the last seal you cast until a Judgement uses it up or it runs out; out of combat it
  is read from your buffs. Off by default.
- Macros > Consumables: Food & Drink Bar (off by default), two buttons for the best food and the
  best drink in your bags, conjured first. Click to eat or drink; move it in Unlock Mode.
- Training Planner (/nftraining, or its minimap and top bar button): a window with what your
  next trainer visit costs against your gold, a road to 60 with a dot for every level that
  brings spells (click one to see them), what is left to pay up to 60, the spells you can
  train now as cards, and what waits on a rank, a talent or a later level. Each new rank says
  how much stronger it is than the one before (+100%, and on its tooltip Fire damage 16-24 to
  33-47). Search any spell of your class, and Show Learned lists what you know. Mini swaps
  the window for a small bar with your next visit and your gold, to leave up while you level.
  Right-click a spell to skip it or all its ranks, shift-click to link it. A toast on
  level-up says how many spells wait and what they cost, and beside your class trainer a
  panel ticks what you can learn with Learn All I Can Afford, then puts the new ranks on your
  bars. Opening the trainer updates prices to what it asks, reputation discounts included.
  Off by default.
- Training Planner: a Builds tab with a leveling talent build for every class, levels 10 to 30,
  from Mobalytics' WoW Forever guides (Warrior has Arms/Fury to 15, then Protection). Pick a
  class and a build to see it level by level, which points you have already taken and which
  one comes next.
  New Build opens your class's talent tree: click talents in the order you take them and the
  build fills in level by level, keeping to the tree's rules (Undo, Clear, right-click to give
  a point back). Copy makes an editable copy of a built-in build. Export gives any build as text
  to share, Import a Build adds one someone shared with you, and Save My Talents keeps the
  talents you have now as a build of your own.
- Training Planner: Learn Next Points on your class's build spends your free talent points on it,
  in its order, and Follow This Build does it for you each time you get a new point (out of
  combat; after a fight if you level in one). Off until you pick a build to follow.
- Training Planner: its window now matches the Dungeon Journal: the Naowh title bar with an
  opacity slider (also in its settings), Spells and Builds as a switch under it, the search and
  each tab's buttons beside it, and its strips and lists on cards. Its settings page opens with
  a card on what you can train now, and has the Mini Bar switch.
- Naowh Score (QoL > Naowh Score, on by default): one number for a character's gear, on the
  item level scale (26.4 means gear worth a set of level 26 epics), fitted to Forever's own
  items: each item counts as the level of an epic with the same stats, weighted by how many
  stats its slot carries. It is coloured by how close it is to the best, on a smooth ramp from
  grey through greens, blues and purples to orange; Grade Against picks the best in the game,
  the best for the player's level, or Both (the score against the game's best, then in gold
  "44% of level 20"). Under the BiS List's paperdoll, a score card shows yours with your BiS or
  as you are now and the gain, over a bar filled to what you wear and dimmer on to your BiS,
  with your level's goal in gold under Both. Your score is shared with your group and guild
  as it changes, so other Naowh Forever players see it at once, at any distance. Player
  tooltips show anyone's: a Naowh Forever player's as they share it, anyone else's read from
  their gear as the game's Inspect does (within inspect range, out of combat). In the
  background, Scan Your Group and Scan Players Nearby (your target, focus and mouseover, and
  everyone whose nameplate shows) read theirs, so the scores are ready before you hover.
- Character Panel (BiS List > Character Panel, off by default): your character panel in the BiS
  List's look: our dark frame and title, the model on the dark panel, the stats as plain rows
  under accent titles, the tabs and buttons in our colours, and your Naowh Score big under your
  level with a bar of how close it is to the best (hover it for your score with your BiS, click
  it for the BiS List). Its stats show your spec's first: the stats your spec weighs, in a fixed
  order (Agility, Strength, Attack Power, Crit, Hit, Haste, then Stamina and Armor), each with
  a bar for what it is worth against your spec's yardstick (VS AGI) and your total now; hover a
  row for what the stat is worth and what it does, or click the scales by its title to change
  the weights. A switch at the bottom gives the game's All Stats. A BiS List
  button replaces the model's zoom buttons (drag the model to turn it, scroll to zoom). Your
  supporter badge sits big in its top corner; without one, the Legendary badge in grey: click
  it for what it is and where it shows, with more on Naowh's Discord.
  Its slots: each item's level in
  its corner, its edge in its quality's colour,
  Forever's mark on what is new in Forever, your BiS's star, and a dot where a better enchant
  waits. With EllesmereUI, turning it on swaps EllesmereUI's character panel for
  this one, and turning it off swaps them back (after a reload). Rather keep the game's own
  panel (or EllesmereUI's)? Slot Marks, on the same page and on by default, puts just the
  marks on its slots.
- Bag Marks (BiS List > Settings, off by default): the BiS List's slot marks on the items in
  your bags: each piece of gear's item level, your BiS's star, Forever's mark on what is new in
  Forever, and the green upgrade arrow on gear better than what you wear by your spec's stat
  weights (BiS or not). Works in the game's bags and in EllesmereUI's bags, reagent bag and bank, where
  ours replace its item level and leave room for its BoE text and Pawn's upgrade arrow.
- Stat Weights (BiS List > Stat Weights, and the scales in the BiS List's title bar): what each
  stat is worth to your spec, which it reads from your talents, only the stats it uses, each a
  bar and a number you can type over, with your BiS list's best upgrades by them right under
  them. Reset, Export to copy your weights, and Import for someone's or a WoWSims EP export.
  Upgrades on Tooltips (off by default): gear that is an upgrade for your spec says by how much
  ("+9% upgrade"). The BiS List's upgrades and enchants
  use your weights.
- Top Bar: Faded Opacity (with Show On Mouseover) sets how visible the bar and the FPS / MS
  readout stay while the mouse is away. 0% by default, invisible as before.
- Blessings: in combat each click on a class button blesses the next member of that class who
  needed it when the fight began, then round again, instead of the same player every time. It
  follows them by name, so the raid being rearranged mid-fight does not send it to someone
  else, skips anyone who has left, and a Greater Blessing is cast once for the class.
- Blessings: class buttons show what is needed at a glance: red when someone in range is
  missing the class blessing, yellow when it is only running out, blue when only players with
  their own blessing need theirs.
- Blessings: Auto-Assign on the Assignments page spreads blessings and auras across every
  paladin in the group running Naowh Forever, the most useful blessing for each class first,
  with Salvation first for casters and rogues in a raid and never for warriors, druids or
  paladins. The
  group leader or an assistant can run it for everyone; a paladin on their own for themselves.
- Blessings: a preset on the Assignments page saves the whole group's plan and loads it again
  later for the paladins who are there.
- Blessings: a paladin's own blessings for single players are shared with the group, and show
  in the tooltip of that class on the Assignments page.
- Group Tools on QoL > Questing: a Disband Group button for leaders and an Invite Player button where you type the name.
- Dungeon Journal: every dungeon's bosses in the order you meet them, what each one drops
  and how often (Forever's new items included; a boss whose loot is not known yet says so),
  its optional bosses and loot chests, then what its trash drops (a card says how many items
  your filters hide), with your BiS marked and how many of them each boss has. Upgrade
  marks what beats your gear (a higher pick on your BiS list, or a higher item level you can
  wear), and right-click puts an item on your BiS list or gives its Wowhead link (a boss's
  too). Your quests for the
  dungeon are listed too, with a waypoint each, and right-click one to share it with your
  party. The group icon counts who else is on each quest; click it on one you don't have
  and a member running Naowh Forever shares it with you (Quest Share Requests, in the
  Journal's settings). Tracker opens a dungeon's quests in a small window to keep on
  screen while you run it, and Map opens its map: the bosses where they stand, with their
  portraits and kill order, and the entrance. Under it, the bosses in kill order with this
  run's progress (killed ones ticked and dimmed), the ones your quests need, your BiS there,
  and the loot of the boss you click; fold that away for the map alone, and pin the map to
  keep it open. Opening the world map (M) puts the Journal away, and M again brings it back. Inside a dungeon its map fills the world map (M), right-click for its zone,
  and the game's quest log beside it folds away so the Journal sits against the map (back as
  you had it once you leave). Each dungeon says whose ground its entrance is on, and the pin
  by its name points you there. Open the world map inside a dungeon and it sits beside the map; browse any
  dungeon in its own window with /nfjournal (or /nfdj) or its own key (Open Dungeon Journal, in
  its settings or Key Bindings), or bind Boss Loot at Cursor to see
  what the boss you hover drops. Search every dungeon for an item or boss, or list only
  the BiS you are still missing, or only your upgrades. The switch beside the search
  lists the dungeons on Alliance or Horde ground, or both. Loot your class can't use is hidden, and nearly every
  boss has a tip from Naowh, to read on hover and share in chat. A skull on each boss
  counts how many times this character has killed it; click it for each kill, who was in
  your group (tanks, healers, then damage, in class colours), everything that dropped, who
  won it and everyone's rolls. The Dungeon Journal page lists your latest kills and loot,
  and where. The three raids
  announced for Forever are listed too (Onyxia's Lair, The Barrow Deeps and Hyjal Summit),
  with their bosses and entrances; their loot fills in once it is known. Off by default:
  turn it on in the Dungeon Journal page.
- Dungeon Journal: Reputation and PvP tabs beside Dungeons & Raids. Reputation lists each
  faction with your standing, and its page shows every reward by the standing it needs,
  with its price, your BiS marked and how far you are from the next standing. Dungeons
  link to the factions earned in them, and back. PvP shows your rank this season, how far
  to the next one, this week's cap and what every rank gives, then the battleground
  factions and their rewards. Search finds faction rewards too. Your side's cities are
  listed with their Runecloth hand-ins, and so are the Azeroth Commerce Authority and
  Durotar Supply and Logistics, new in WoW Forever. Dungeons & Raids,
  Reputation and PvP are tabs over the list. Recipes are listed only for your professions
  (My Professions Only, in Filters), the ones you know are marked, and they fold under each
  standing's gear; Show Cosmetic Items, in Filters, hides cosmetics. A pin on a faction's page
  sets a waypoint to its quartermaster. Each faction's page shows what your
  unlocked rewards would cost and the quests that raise it: yours
  in your log, and its repeatable hand-ins (Scourgestones, Timbermaw feathers, Thorium
  Brotherhood's cores and more), listed like dungeon quests: who takes each and where, with a
  waypoint, how many your bags hold and where to get the items. A locked reward says how much
  reputation it still needs. Dungeon pages show
  your standing with the factions earned there, and the PvP rank has a track with this
  week's cap. Click a page's BiS count to open your BiS list. The Journal's footer shows the
  game build its data is from. Turn on Factions Beside the Map (in the Journal's settings) and
  the world map (M) shows, in a zone or a battleground, the factions earned there beside it. Once
  you have opened your side's PvP rank vendor, a pin on the rank's page shows where it is.
- Top Bar: hover the clock to see your saved instances, boss progress and when each resets;
  `/nf lockouts` lists them in chat.
- Campfire: Ctrl-click the Camp Nearby alert to dismiss it until you leave that campfire.
- Action Bars (new, under Utilities): save every action bar slot as a named set and restore it later,
  out of combat. Sets are shared by your class on the account; Test Restore lists what would not
  come back. Options to restore the highest rank, recreate deleted macros and save on logout
  (all off by default). Also `/nf bars save|restore|test|delete <name>` and `/nf bars list`.
- Top Bar: Friends and Guild can each be switched off in Top Bar > Buttons (both on by default).
- Top Bar: Show On Mouseover keeps the bar and its FPS / MS readout invisible until you hover
  them (Top Bar > Bar, off by default).
- QoL > Questing: Skip Modifier picks the key you hold to skip quest automation (Alt, Ctrl or
  Shift; Alt by default).
- XP Bar: Ctrl + right-click the bar to reset the session time and XP/Hour. Without Ctrl,
  clicks and camera drags go through the bar.
- Professions: Shift-Click Searches AH (off by default). While the auction house is open,
  Shift-click a recipe or a reagent and the search for the item runs straight away; while
  you type in chat, it still links it.
- Settings: six color chips beside the Theme dropdown preview the selected theme's colors before you reload.
- Professions: Buy at Vendor (Buying and Selling, off by default). At a merchant, "- [1] +
  Buy" under the chosen recipe's reagents buys every checked reagent the merchant sells for
  that many crafts in one click, such as Coarse Thread or Weak Flux. The total shows beside
  it, red when you cannot pay; hover Buy for each reagent. Buy All (x) beside it buys only
  what your bags lack for x crafts, x being the orange count next to the recipe, so Create
  All can then make them all. Buy Materials is now called Buy on AH.
- Professions: Create All stops at what your bags have room for, with "Bags: room for 14 of
  20" in red under the recipe when that is fewer than your reagents allow. Items that stack,
  such as bandages or potions, need far fewer slots than swords or armour, and stacks you
  already carry count; profession bags and the reagent bag count for what they take. Slots
  freed as the batch uses up reagent stacks count too, craft by craft.
- Professions: favourite recipes. Click the star before a recipe's name, or right-click it
  in the list; favourites get a small star in the list, and Favorites at the top of the
  Filter menu shows only them. Favourites set in Blizzard's window count too. Recipes you
  have not learned can be favourites as well.
- Professions: Shopping List (Buying and Selling, off by default). "- [1] + Add to List"
  under a recipe's reagents puts the materials Buy on AH would buy for that many crafts on
  a list, from anywhere. At the auction house the list shows beside it, with what it is
  for: Check Prices looks each material up and marks in red any well above your last scan
  or short on supply. Buy All then goes through the list: each material shows its final
  price and is bought when you click Confirm. Bought materials leave the list.
- Professions: Train Favorites (Recipe Window, off by default). A trainer who teaches a
  favourite you can learn now lists them beside their window, with the cost, to Learn one
  or Learn All.
- Professions: Search Favorites AH (Buying and Selling, off by default). At the auction
  house, the patterns, plans and manuals of your favourites are listed beside it with their
  price at your last Scan Prices, cheapest first. Buy finds the cheapest listing and asks
  "Buyout auction for:" with the live price, as the auction house does; only Accept buys it.
- Professions: the Filter menu has Bind on Equip and Bind on Pickup, showing only recipes
  whose item binds that way (either way with both ticked), unlearned recipes included.
  Items that do not bind at all, as much crafted gear on the beta, count as Bind on Equip.
- Professions: Total Craft Timer (Recipe Window, off by default). Crafting several at once
  (Create All, or Create with a count) shows one bar for the whole batch, drawn like the
  Flight Timer: the recipe and its icon, how many are done and the time left on all of them.
  The cast bar that fills for every single craft is hidden meanwhile. It sits where the
  Flight Timer is; move it in Unlock Mode as the Flight Timer. It ends when the batch is
  done, interrupted or stopped.
- Professions: Craft Orders (Recipe Window, off by default). Another player's profession
  link opens in Naowh's profession window, to order crafts from them. Choose a recipe, set
  how many crafts, tick the materials you bring (or type how many of each), and click Add to
  Order. The order on the right lists every craft with a tip you can change; Ask sends the
  crafter one message per craft with the amount, your materials and the tip: in party chat,
  starting with their name, when they are in your party, else as a whisper. Invite, at the
  top of the order, asks them into your group first. Under the reagents: the crafter's
  materials and the suggested tip, which pays back their materials plus a share of the
  items' value (10% by default, set with Suggested Tip), rounded, at least 1s; prices need
  an auction house scan.
- Dungeon Journal: Share on the quest tracker shares your quests for its dungeon with your
  group. Quests that cannot be shared are skipped. They go out one at a time, each once your
  group has answered the last, so nobody is too busy for the next; one someone was busy for
  is shared again at the end. Click the tracker's title to open the Journal's settings.
- Dungeon Journal: Accept Shared Dungeon Quests (off by default, in the Journal's settings)
  accepts a dungeon quest a group member shares with you as soon as it opens. Hold the Skip
  Modifier to look at one first.
- Threat Meter: Status Line (Layout) moves the line with your distance to pulling aggro and
  the entry count from under the bars to the top, between the title bar and the bars.
  Bottom by default.
- Threat Meter: Apply Theme to Your Bar (Colours, off by default) colors your bar in a darker shade of your theme's Accent instead of the color picked there. The tank and pull aggro colors are unchanged.
- Swing Timer: Apply Theme to Bar Colours (Colours, off by default) colors the main hand bar with your theme's Accent, the off hand bar with its lighter Accent and the ranged bar with a deeper shade of it, instead of the colors picked there.
- BiS List: its own window, in the Dungeon Journal's look. On the left your spec, your list
  and your character wearing your whole BiS, or what you wear now with each slot's BiS tried
  on as you hover it: drag to turn it, scroll to zoom. The slots are laid out as the game's
  character frame, each BiS in its quality's edge with a check once it is yours, and under
  them what your BiS gets you over what you wear: average item level and the stats it adds. On the right how many of
  your BiS are yours, then where to run next (which slots each place is for; a click opens
  the dungeon in the Journal, or out in the world puts a waypoint on who drops or sells your
  BiS there and shows it on your map, and the BiS List comes back when you
  close them), then a row per slot: its BiS, where it
  drops (a weapon says what it is), the level it needs while above yours, and its backups,
  opened under it. A wand on a slot shows the best enchant for your spec on what you wear
  there, for that item's level (no endgame enchants on a level 19 sword), and what is on it
  now; a click asks for it in Trade chat, or copies the message. A Quests page lists the
  quests that reward a pick you do not have yet, by the zone they start in, as the Dungeon
  Journal lists its own: what to do first, the level it needs, its chain, a waypoint, and the
  picks it gives under it. All, To get, In bag or To enchant filters the list. Click a slot to change its picks
  beside the window, where the ranking shows its own order. Import and Export are on the
  title bar, and the footer says when your spec's rankings were last updated.
  Open it with `/nfbis`, its own key, or the BiS stat in the Journal.

### Changed
- Training Planner: the Builds tab is laid out as the Dungeon Journal is, the class's builds in a
  list down the left and the one you pick beside it, with its buttons (Learn Next Points, Follow
  This Build, Edit or Copy, Export, Delete) over it. Its lists (a build level by level, the spells
  waiting on a rank, talent or later level, and the later levels) are one continuous list, every
  other row faintly banded, instead of a box round each row. In the talent tree each talent's
  ranks sit under it instead of over its corner.
- Top Bar settings moved from their own sidebar page to the top of QoL > General, with a Top Bar switch in place of the page's Enable switch. /nf still opens on them.
- Supporter badges: on a player's tooltip the badge is a plate of its own over the top, the
  badge and title in the tier's colour, instead of a line in the tooltip.
- BiS List and Dungeon Journal: an item new in WoW Forever has Forever's badge on its icon's
  corner, and what you wear a green bar at the row's edge. The paperdoll's slots show their
  item level in the corner and a green line under what you wear.
- BiS List: tidier rows. A slot's backups hang from it on a line; names get more room; a quest
  for your own side says just "Quest"; and an item with no known source says "World drop".
  Run Next's star counts, gains and links line up in columns. Each gain has a bar as long as
  its share of your biggest, brighter the bigger it is. A better enchant for what you wear
  shows as a small dot on that slot's icon in the paperdoll: hover for the advice, click to ask
  in Trade. Text, titles and columns share one grid.
- BiS List: right-click an item for its copy card (its ID and Wowhead link), the same card
  as the tooltips' Ctrl-Shift-C. Move and remove stay on a backup pick's icons and in the
  picker.
- Tooltip Display: the line saying which keys copy an ID is off by default; Show Shortcut Hint
  brings it back. The shortcut works either way.
- Copy cards link to Wowhead's Forever database; a Classic button beside it is there for a
  page Forever's has not got yet. The Wowhead Database setting is gone.
- BiS List: Run Next ranks quests, crafts and faction rewards with the dungeons and zones by
  how much stronger they make you, so a quest reward worth +18% comes first. Click one for
  the quest, the recipe or the faction.
- BiS List: "Your BiS over what you wear" shows the stats that matter most to your spec, by
  its stat weights, and leaves out what it does not weigh. No more "+14 more" and its
  tooltip.
- BiS List: the picker's items use the whole row for their name and where they come from,
  and the level shows only when it is above yours. A source still cut short shows in full
  when you hover it.
- Small icons are smoother: the check on gear you have, the button icons and the Forever
  mark, and item icons at any UI scale.
- BiS List: where an item comes from is a link. A dungeon drop opens the Dungeon Journal on
  that item, a reputation or PvP reward its faction there, a quest's reward the quest on the
  Quests page, an NPC's item a waypoint on them, a crafted item its recipe (if you have the
  profession), a zone its map; anything else copies its Wowhead link. Hover it to see where
  it goes.
- BiS List: a slot's backup picks open as rows like the slot's own: the rank (2nd, 3rd)
  where the slot's name is, the item, how much stronger it makes you and where it comes
  from in the same columns, move and remove on hover.
- Every sound setting (Combat Alert, Crosshair, Mouse Ring, Emotes, Focus Cast Bar, Campfire,
  Low Health, Threat Meter, Drop Alert) has a play button beside it, and plays the sound as you
  pick it.
- Dungeon Journal: the dungeon and faction lists count only the BiS you still miss there, and
  show nothing once they are all yours, instead of a second check.
- What is new in WoW Forever wears its infinity sign instead of NEW: dungeons and factions in
  the Dungeon Journal's lists and its dungeon page, and the bosses, quests and items new in
  Forever, in the Journal and the BiS List. Hover it, or the row, and the tooltip says
  "New in WoW Forever".
- Item tooltips are shorter: one line each for your BiS rank, how much of an upgrade it is and
  whether it is new in Forever, written the same way in the BiS List, the Dungeon Journal and
  on every tooltip, with nothing said twice.
- BiS List: each BiS you do not wear yet says how much stronger it makes you (+9%), by the
  stats your spec values, and Run Next puts the place that makes you strongest first, with its
  total, so you know what to farm first.
- BiS List: what drops in a dungeon is the Dungeon Journal's, so both list the same items under
  the same bosses and dungeon names, and a slot's picker offers every dungeon drop for your
  class (about three times as many as before).
- BiS List: Fill Empty Slots is gone. Pick each slot's BiS from its picker, or import a list.
- The options window's sidebar header shows the NaowhUI Forever logo, and the search box beside it is narrower.
- Flight Timer: with Land Early Button on, Blizzard's own Request Stop button is hidden
  during the flight, so there is only one. It comes back when you land.
- QoL has a new XP tab, right after Questing: XP Bar, XP per Hour and Group XP moved there from
  Questing. Your settings stay as they were.
- XP Bar settings show a preview of the bar: click a text on it, or a spot around it, to pick
  what it shows. A text shows in one spot at a time; picking it for another spot moves it
  there. If your bar already shows a text in two spots, it keeps the first one (top to
  bottom, left to right) and the other spot is emptied.
- XP Bar: three more spots for texts, Top (above the middle of the bar), Left and Right (beside
  the bar).
- XP Bar: the level inside the bar can be written shorter, as Lvl 20 or just 20.
- XP Bar: pick your own fill, completed quests, rested and background colours under XP Bar,
  Colours; Reset Colours puts them back. Reset Size & Texts does the same for the bar's width,
  height and the text in each spot.
- XP Bar: Completed Quests (XP) shows the XP of your finished quests as a number; the percent
  one is now called Completed Quests (%).
- The Naowh logo now has the closed infinity loop at the bottom, on the addon list, the main window and the small popups.
- The Minimap Button switch and the per-module minimap buttons moved from Settings to the Top Bar page, so /nf shows them straight away.
- Loot Feed Appearance options sit inside the Loot Feed dropdown instead of a second one.
- /nf opens on the Top Bar page the first time in a session; after that it reopens where you left it.
- Dungeon Quests is now part of the Dungeon Journal. Each dungeon's page lists your quests
  there: what to do first for one you can't pick up yet (and the waypoint points there),
  the level it needs, Too high for one five levels or more above you, and the whole chain
  leading up to it. The separate Dungeon Quests page is gone, and its tracker is the
  Journal's Tracker now; /nf dungeon and the Top Bar button open the Journal instead.
- Patch Notes: what's new in 0.5.18-beta on the in-game page.
- Campfire: each camp benefit shows as a short stat tag (+Spirit, +ATK, +ARM, +STR, +STA, +INT,
  +MP5, +Stats, +Crit, +Rested) instead of the camp feature's name.
- Supporter badges: the badge sits after the name in chat, at the size of the text, so every
  name starts in the same place and lines are no taller. It shows in the Guild & Communities
  member list too, after the name, and the lines on the badge's hover card line up.
- Options window: redesigned. The left menu groups the modules under Adventure, Combat and
  Utilities, a module's categories are tabs on one row under its title, the search at the top covers every
  setting, and each module's on/off switch is at the top right of its page. The window also fits
  on a 1080p screen.
- Buttons, dropdowns and input boxes have a black border that lights up blue under the mouse.
- Options window: a little taller, so the left menu fits every module without scrolling.
- Unlock Mode: the position readout sits on the display you select instead of at the bottom of
  the screen.
- QoL > General: Co-Tank Debuffs now sits inside Co-Tank Frame, and Stealth Reminder's colours
  and texts fold away under Appearance & text. Turning a feature off folds its settings away
  again.
- QoL: the auction house price on item tooltips is now switched in QoL > Tooltip Display
  (Auction House Price), with the other tooltip settings. Your setting is kept.
- Dungeon Journal: its data is updated to WoW Forever build 1.60.1.70170: 4 faction rewards changed (item levels, required levels).
- Campfire: Show Active Camp Buffs is a dropdown: Off, Always or On Mouseover, which shows
  the buffs only while the mouse is over the camp icon. Your current setting is kept.
- Dungeon Journal: its data is updated to WoW Forever build 1.60.1.70178.
- Sound dropdowns play the sound when you pick it, as Smart Reminders' already did.
- Threat Meter: Hide When Empty is now With Threat, a choice under Show, so Always really
  means always. Your setting carries over; with In Combat it becomes With Threat. In a Group
  can no longer hide the empty window, so choose With Threat for that.
- Dungeon Journal: its data is updated to WoW Forever build 1.60.1.70205.
- BiS List: picks updated from wowsrc.com's latest lists, for every spec.
- BiS List: Drop Alert says each drop once: a roll for one of your picks, then its boss's
  loot window opened as often as you like, is one line in chat with its star, the item and
  the slot it is for ("up for a roll: your BiS for Shoulder"), and another when it is yours.
  Its roll frame shows a badge with the star and "Your BiS" in place of the blue glow. Test
  in its settings plays it all for your first BiS.
- BiS List: Drop Alert is yours to set up. An alert on screen (on by default, moved in Unlock
  Mode) shows the item with your star, the line under its name and its border as you pick
  them: click them in the preview on its settings page to change them, and set its size, how
  long it stays, its background and glow. Choose which picks alert (your BiS, your top two, or
  all), a sound for a drop and one for when it is yours, and turn the chat line and the roll
  frame badge on or off.
- BiS List settings: a shorter page. Drop Alert's on-screen alert has a panel of its own: see
  it up for a roll, dropped or yours, click its star, line or border (or the chips under it)
  to change them, set its size, how long it stays, background and glow beside it, and Play
  test. Sounds play as you pick them, the list buttons sit on one row, and the star on the
  alert shows over the item's icon. On every settings page, greyed-out options can no longer
  be changed.
- BiS ranks look the same everywhere: an orange star for your BiS, a silver star for your
  second pick and a number for the rest, in the BiS List, the Dungeon Journal and on
  tooltips. What you wear is marked in green.

### Fixed
- Unlock Mode: Exit Config shows again (it was under the Level-Up Toast), Smart Reminders'
  samples move by dragging the whole display like everything else, and Bag Space's plate covers
  its whole row.
- Character panel: your Naowh Score no longer stays out beside the panel when you fold the stats
  side away.
- Blessings: the options window opens again while the bar shows your blessing buffs. Opening
  it, or changing the UI scale, raised a Lua error and left the window broken.
- Borders and divider lines no longer lose a side at some UI scales (the trainer popup's X
  missing its left edge, a panel without its top line), and icons keep their black edge all
  round. Every border, line and icon edge is now exactly one screen pixel, refitted when the
  UI scale or window scale changes.
- Opening a color swatch and closing it without picking no longer saves that color. A Custom
  theme color left at the default (including when Custom is first picked) no longer counts as
  changed, so the loot feed glow, XP bar quest and rested colors and the other HUD colors keep
  their own shades until you actually change one.
- Themes: the hint lines in the Library Books tracker and its map pins, and in the town map pins, follow your lighter Accent instead of staying light blue. Looks the same with the default theme.
- Group XP: every group member running Naowh Forever now shares their XP, even with Group XP
  switched off, so the bars no longer say "no addon" for players who never turned it on.
- Group XP: bars show everyone's XP again. Forever sends a character's full name with surname
  with each update, which never matched the party list, so every member read "no addon". Older
  versions can't be read: everyone needs this version to see each other.
- Themes: the Top Bar's clock, its FPS / MS labels and its tooltips follow your Text and Secondary Text colors instead of staying white and grey, and the tooltips of the Naowh buttons (minimap, top bar) use your Accent for the title and Text for the lines. Looks the same with the default theme.
- Themes: the Loot Feed follows your theme: the Dark style uses your Background, the Light style uses your Panels and Borders & Lines, and the glow uses your Accent. Looks the same with the default theme.
- Themes: the XP Bar's quest and rested segments and text follow your theme's Accent instead of staying gold and blue. Looks the same with the default theme.
- A copy downloaded with GitHub's green Code button has none of the addon's libraries, and
  parts of it then failed with Lua errors (Low Health's glow on a level up, among others). It
  now says at login which libraries are missing and where to download the full addon.
- Loot Feed: turning in a quest no longer shows its experience twice, once on the quest's line
  and again as Experience. With quest lines turned off it still shows as Experience.
- Blessings: the class buttons and the player list cast on the right player again in a party.
  Forever names carry a surname, and the buttons were looking players up by the whole name
  while the game knows party members by their first name.
- Blessings: a group leader's or assistant's changes to another paladin's blessings now reach
  them; they were dropped because of the surname. Changes made during combat are sent once
  it ends instead of being lost.
- Blessings: a class button no longer glows red when the only members missing their blessing
  are out of range. It lights up only for someone you can bless from where you stand.
- Recipe Finder and rank alerts: Stormwind and Eastern Plaguelands trainers and vendors
  (Lucan Cordell, the Stormwind enchanting trainer, among them) were placed at their Classic
  positions, so their waypoints pointed at the wrong spot on Forever's redrawn maps.
- Share Quests With Group no longer tries to share a quest accepted in combat, where the
  game blocks sharing.
- Discovery tracker: the zone picked in its dropdown stays picked once its last book is
  looted, showing "No more books in this area", instead of jumping to another zone.
- XP Bar: the texts above and below the bar take the room they need, so a long one is no longer
  cut off with "..." while there is space beside it. On a narrow bar they get smaller to fit,
  and the bar is at least 400 wide.
- The Naowh font is only on this addon's own windows and HUD again; the rest of the game keeps
  its own fonts. Settings > Font has Addon Font (Naowh), plus Game Font and Combat Text Font,
  both off unless you pick a font.
- The Naowh logo on the New Abilities, Quiz and Buy Materials windows is sharper and a little
  bigger.
- Blessings: every icon has the same thin black border, also while its buff is up and on
  your own blessing button.
- Bag Space: Unlock Mode shows your own items instead of question marks, where you have them.
- Buff Reminders: no more error when the mouse leaves a missing buff's item menu.
- Global Copy: /copy finds the frame under the mouse again when the game names none.
- Reload UI buttons and prompts work again, like the one after Apply All Recommended on
  QoL > Performance: they run the game's own /reload instead of causing an error. In
  combat they say to type /reload.
- QoL > Tools: a custom slash command that runs another slash command no longer makes your
  next chat message fail. Emotes like /dance work too. Macro commands like /cast, /use and
  /target, and /reload, can't be run this way; the command says so in chat.
- Sound dropdowns list None once; the second was a silent placeholder from SharedMedia.
  The QoL sound dropdowns (Combat Alert, Emote, Crosshair, Mouse Ring, Focus Cast Bar)
  now offer None as well, so a sound can be turned back to silent.

## 0.5.17-beta

### Added
- Unspent Talent Points (off by default, QoL > Combat & Alerts): text on screen while you
  have talent points to spend. Hidden in combat; move it in Unlock Mode.
- Share Quests With Group (off by default, QoL > Questing): while you are in a group, each
  quest you accept from an NPC is shared with the others, when the quest can be shared. A
  quest someone shared with you is not shared again. Hold Alt to keep one to yourself.
- Accept Popup Macro (Macros > Focus & Cursor): a macro that presses the first button of the
  popup on screen, like accepting a summons or a group invite. It presses whichever popup is
  on top, so it confirms the others too.
- Group XP (off by default, QoL > Questing): a bar for each group member with their level
  and how far through it they are, for levelling together. Everyone who wants to be seen
  needs Naowh Forever with Group XP on; anyone else shows their level only. Move it in
  Unlock Mode.
- Options window: a search box at the top of the sidebar finds a setting on the Settings
  page and on the QoL, Gear & Trinkets, Macros, AuraBuffs, Threat Meter, Swing Timer and
  Professions pages, jumps to it and lights it up, opening the dropdown it sits in. While
  you type, matching settings on the page you are on are highlighted and their dropdowns
  open. The editor pages (Smart Reminders, Profiles, BiS List, Blessings, Dungeon Quests,
  Top Bar, QoL Tools and Poison & Dispel) are found by name. Thanks to Lyssa.
- Supporter Badges: Legendary patrons on Naowh's Patreon now get the Naowh Forever N next
  to their name in chat, seen by everyone with the addon. Hover their name for their card,
  with how long they've been supporting, and their player tooltip shows it too. Type
  /nf badges id to get the code that links your characters. Naowh, the developers and the
  moderators have their own badges. Turn each part off in QoL > Interface > Supporter
  Badges, where you can also turn on a banner for when one of them joins your group.
- Discovery: a new module (off by default) for the 40 library books hidden around Azeroth.
  The Books page lists every book your faction can take, by zone, with its level set, where
  it lies, who takes it and a Waypoint button; Finished, In bags, In bank or Missing on the
  right. Books handed to the librarian count toward Friend of the Library (10) and Greater
  Friend of the Library (20); the level 60 set goes to a mage trainer instead.
- Discovery: Show Tracker (off by default). Entering a zone with books you still need pops
  up a small window listing them with a waypoint pin each, under a bar counting your
  hand-ins toward the next reward; hover the bar for both rewards and their items, click the
  title for the Books page. Books in your bags or bank get a line with where to hand them
  in. It stays while you are in that zone; the X closes it until you enter another.
- Discovery: Always Show (off by default) keeps the tracker up in every zone, with a
  dropdown of the zones where you still have books to find. Entering one selects it; the X
  switches Always Show off.
- Discovery: Show on World Map (off by default) pins every book you still need on its
  zone's map, and your librarian while you carry books. Hover for the exact spot; click for
  a waypoint.
- Discovery: Sound When Nearby (off by default) plays the map ping and names the book in
  chat when you come within range of one you still need (10 to 100 yards, default 40).
- Settings: a new COLORS section with theme presets (Midnight, Slate, Obsidian, Aubergine,
  Forest, Crimson, Rose Noir and Cotton Candy) for the addon's windows and HUD frames, plus
  a Custom option to pick your own Background, Panels, Borders & Lines, Text, Secondary Text
  and Accent colors. Choose a theme, then press Reload UI (a reminder shows under the
  section until you do). Custom can start from any theme. Off by default (Naowh
  (default)); saved for this computer.

### Changed
- Campfire: an Alert Under slider next to Camp Nearby Alert sets how many minutes of Camp
  Benefits count as needing a refresh, instead of always 2 (AuraBuffs > Campfire).
- Patch Notes: the page in the options window lists what is new in this version.
- Settings: switches that stand on their own now sit above the dropdowns on every page. On
  the QoL Questing, Loot & Items, Combat & Alerts and Performance tabs, AuraBuffs, Blessings
  and Swing Timer's aids they had been further down.
- Crosshair: Recolour Out of Melee Range and its options are inside the Crosshair dropdown
  instead of a section of their own.
- XP Bar: the text around the bar now has five spots, Top Left, Top Right, Bottom Left,
  Bottom and Bottom Right, and each shows the one you pick: Played Time, Session Time,
  Completed Quests, Rested Experience, Time to Level or XP per Hour. They replace the four
  text switches, and the texts you had on move into the spots (QoL > Questing > XP Bar).
- Flight Timer: bigger, with a Scale slider in its dropdown (QoL > Flight & Camp). The ends
  of the route are round dots, and the Land Early button uses the game's own leave-flight
  arrow.
- Settings dropdowns: switching a feature on opens its options, and the arrow is a bigger,
  bolder chevron.
- Flight Timer: a new look in Naowh's colours. The route is a line between its two ends,
  the stops on the way slide past you, and the time left sits beside it. A Land Early
  button (off by default, QoL > Flight & Camp) lands you at the next flight point.
- BiS List: lists are shared by every character of a class, and a class can keep several.
  Pick, make, rename and delete them on the List and Settings tabs; each character keeps
  using its own pick. Your current list moves over, named after your character. Importing
  a list adds it as a new one instead of replacing yours.
- BiS List: Fill Empty Slots puts the ranking's best item in every slot you have not picked,
  skipping items already picked elsewhere, so a second ring or trinket gets the next one down.
- BiS List picker: two-line rows with each item's source, item level and required level (in
  orange while it is above yours), small arrow and remove buttons, and only your own picks
  are numbered.
- BiS List: Where to Go Next lists only places you can go, not crafted, quest, reputation or
  world-drop items.
- BiS List: add any item to a slot by item ID, item link or Wowhead URL from the bottom of
  the picker.
- BiS List: a slot's BiS item is framed in a thin border of its quality colour, and the
  check mark is gone.
- BiS List: a button beside each slot steps its icon through your picks (BiS, 2nd, 3rd and so
  on) and turns green on the one you are wearing; the slot's line in Where Your Items Drop
  follows it. The slot's picker tags the item you wear Worn.
- Dungeon Quests and BiS List open straight to the dungeons and to your character panel;
  their options moved to a new Settings tab in each.
- Settings pages are shorter: a feature with several options, such as Restock or the Co-Tank
  Frame, is one row with its on/off switch, and its options open under it with a click.
  Features with a single switch stay as they are. Groups of options with no switch of their
  own, such as a module's layout or colours, open the same way.
- Dungeon Quests: click a step in a quest's Chain list for a waypoint to where it starts,
  or for a step in your log, to where the game sends you for it.
- Co-Tank Frame: Righteous Fury counts as tanking for paladins.
- Co-Tank Debuffs now show in combat, drawn by the game the way NaowhUI's co-tank does it,
  with its filter, icon, position and text settings. On by default with the frame.
- Combat Alert: two new voice clips, "Combat" and "Safe", are its default sounds for entering and
  leaving combat. Set Audio to Sound to hear a spoken alert without the stutter Text to Speech
  can cause. They are in every sound list as Voice: Combat and Voice: Safe.
- Professions: every Professions setting is off by default (Unlearned Recipes, Next Rank
  Alert, Reagents in Bags and Reagents in Bank were on). Settings a profile has already saved
  keep their value.
- Professions: the settings page is grouped into Recipe Window, Buying and Selling, and
  Gathering, two settings to a row.
- Professions: the recipe list is wider. Craft counts and required skills sit in a column at
  the left of each row, so the icons and names line up, and the profit at the right.
- Professions: Create and Create All grey out while one of the recipe's requirements is not
  met, such as being away from an anvil.
- Professions: the window follows the NaowhUI look: 1px black borders, the skill bars filled
  with Naowh's blue gradient like the XP bar, and flat checkboxes.
- Professions: amounts read as text, from the largest coin down to copper ("12g 07s 09c",
  "6s 00c").

### Fixed
- Death Release Protection no longer carries over to a death outside a dungeon or raid.
- Smart Reminders now follows an installed BigWigs or DBM on Forever, and pull triggers and
  boss-mod reminders work without Blizzard's encounter timeline. Callouts still wait for
  boss data, so nothing fires in Forever dungeons until BigWigs or DBM ship timers for them.
- Loading in while the game still calls you "Unknown" no longer files your character under
  that name or pins the wrong profile for the session.
- Pasting an oversized string into Reminder Pack import is refused instead of freezing the game.
- Auction Prices: a scan that comes back empty no longer wipes the saved prices or starts the
  15 minute wait.
- Gain/Lose a Buff or Debuff is no longer offered as a reminder trigger where the combat log is
  unavailable.
- Town Map: pins show by default in Zephras Isle.
- Flight Timer: the tooltip no longer says the first flight counts up.
- Professions: Crafting Profit (Buying and Selling, off by default). Once you have scanned
  the auction house (Scan Prices), the chosen recipe shows Buy for, Sell for and Profit: what
  its reagents cost to buy, what the item sells for, and the profit after the 5% auction cut,
  green or red. Each reagent is priced at its cheapest: a vendor's price once you have seen a
  vendor sell it, else the lowest buyout at your last scan. Hover the lines for the cost of
  each reagent. Works for unlearned recipes too.
- Professions: Profit in Recipe List (off by default) shows each recipe's profit at the right
  of its row in the list.
- Professions: with Crafting Profit or Buy Materials on, each reagent has a checkbox. Uncheck
  one you already have to leave it out of the cost and out of what Buy Materials buys, for
  every recipe that uses it.
- Professions: Search AH Button (off by default). At the auction house, a Search AH button
  next to the chosen recipe searches for the item it makes; unlearned recipes also get Search
  Recipe, for the pattern, plans or manual that teaches it.
- Professions: Buy Materials (off by default). At the auction house, "- [1] + Buy" under the
  chosen recipe's reagents buys the materials for that many crafts: every checked reagent
  vendors do not sell. Each material is searched and priced first, warns in red when it is
  more than 25% above your last scan or you cannot afford it, and is only bought when you
  click Confirm. Materials sold as single listings get Search AH instead.
- Professions: a Filter button beside the recipe search: Have Materials, Has Skill-Up,
  Profitable (once scanned) and Unlearned Recipes, with Reset Filters. It shows how many
  filters are on.
- Professions: Track Recipe on the chosen recipe's Reagents line, as in Blizzard's window:
  the recipe's reagents in your objective tracker.
- Professions: Tracking Reminder (Gathering, off by default). An icon on screen while you
  know Find Herbs, Find Minerals or Find Fish but track none of them; click it to start
  tracking (left, right and middle-click for the first, second and third). Hidden in combat,
  on flight paths, while dead, and in dungeons and raids unless Show in Dungeons and Raids is
  on. Include Find Fish can leave fish out. Move it in Unlock Mode.
- Mouse Ring: a cast pushed back by damage keeps its sweep to the new end instead of stopping at
  the old one and leaving the ring blank until the cast finishes.
- Mouse Ring: changing the Melee Spell ID takes effect at once instead of on the next target.
- Crosshair and Mouse Ring: switching Play a Sound off stops an out-of-melee sound already
  repeating.
- Cursor Clip: a crash or a closed client in the middle of a fight no longer leaves the cursor
  locked to the window; your own setting comes back at the next login.
- Mouse Ring: Recolour Ready Ring greys out while GCD Sweep is off, as the ready ring needs it.
- Combat Alert with Text to Speech no longer stutters the game on every pull. The addon re-read
  your installed Windows voices each time combat started; it now does that when you close
  the game's Settings or its Text to Speech options. The spoken line also goes out a frame
  after the combat change instead of on it.
- Auto Repair and Auto Sell Junk work with the Restock Reminder switched off. They did nothing
  at a vendor unless the reminder was on, and said nothing about it.
- Auto Repair says so when you do not have the gold to repair, instead of skipping it quietly.
- Buy at Vendors greys out while the Restock Reminder is off, as it only buys with it on.
- Professions: clicking another player's profession link with the profession window closed
  opened your own profession; it now opens theirs the first time.
- Professions: the unlearned recipe view no longer runs its requirement line under the
  Search Recipe button, or its waypoint hint into the profit lines.

## 0.5.16-beta

### Added
- Bag Space (QoL > Loot, off by default): the cheapest items in your bags as a row of
  icons, cheapest first (or grey items first), with what each stack sells for and a border
  in its quality colour, black for common items.
  Ctrl-click an icon to delete it, or click it to sell it at a vendor, and middle-click an
  item to ignore it. Uncommon and better items are only picked up by a Ctrl-click, so the
  game's own delete confirmation still applies to them. Hover an icon for what the stack
  fetches at a vendor and at the auction house; an item worth more at the auction house is
  valued at its auction price, so it comes later in the row. Reagents, ammo, quest items,
  keys, equipment set items and BiS items are never offered. It can show only when your
  bags are nearly full, hides in combat, and has a key binding that picks up the cheapest
  item, which you can set on the same page. Move it in Unlock Mode.
- Bag Space: Ignore List, on the same page, shows every item you ignored, newest first, with
  the day you ignored it and how many you carry. Search it by name, hover a row and click
  the X to stop ignoring that item, or drop an item from your bags onto it to ignore it
  before it is ever offered. Clear All starts over.
- Bag Space: each tooltip line it adds (vendor price, auction price, delete and ignore hints)
  can be turned off on its page. The quest warning always shows.
- Bag Space: a Stack button at the start of the row when part-filled stacks of the same item
  can be combined, with how many slots it frees; nothing is deleted. Free slots out of your
  total show above the row with a bag icon (orange when nearly full, red when full; hover it
  for each bag), food, drink and potions 10 or more levels below you are marked
  OLD (and can go first), and an "Inventory is full" error brings the row up for 20 seconds
  even when your free-slot threshold would hide it.
- Bag Space: an item an unfinished quest in your log still needs (Okra for Westfall Stew,
  say) gets a yellow ! and goes to the end of the row, and its tooltip names the quest and
  how many you have. Deleting it takes a second Ctrl-click within 5 seconds.
- Mail & Alts (QoL > Loot & Items, each off by default): item tooltips show what your
  characters on this realm and faction hold in bags, bank and mail. On the mailbox's Send tab,
  Alts fills the To box with one of your characters (with their level and gold) and Attach
  adds all trade goods, one type of them, or your unbound gear in one click. A login warning
  names characters whose mail expires within three days. Characters are recorded once you
  log in on them; Forget a Character removes one.
- Class macros: right-click an icon to pick another (yours only, never exported; Profile Icon
  restores it). A macro with an unknown command, a line that is not a command, or unbalanced
  brackets is marked, and hovering its icon says what is wrong. Profiles can add a note.

### Changed
- Class macros are now made as character macros, so they no longer fill General macro slots
  or show on your other characters. Class macros you already made stay where they are.
- Key bindings: Naowh Forever's bindings have their own Naowh Forever section in the game's
  Key Bindings, instead of sitting under AddOns. When a key field takes a key that was
  already in use, the message now says the key "is now bound to" the new action.
- Campfire: clearer high-resolution artwork, a larger default icon, and short buff labels such as Rested XP and Crit Strike 2%.

### Fixed
- Swing Timer: Show set to Always now keeps the bars up out of combat even with Hide When Idle on. Hide When Idle is greyed out while Show is Always, since it only applies to In Combat.
- Trinket bar: clicking an empty trinket slot no longer throws a Lua error, and hovering a slot shows the equipped trinket's tooltip instead of usage instructions (those stay on the Trinkets settings page).

## 0.5.15-beta

### Added
- Professions: Next Rank Alert (on by default). Once a profession's skill is high enough
  for its next rank (Journeyman, Expert, Artisan), a banner under the skill bar in the
  profession window, and on that profession's card in the overview, says what it takes
  (train it, buy and read the book, or do the quest) and who to see, nearest first. Click
  Waypoint (or the card's banner) to mark them on your map, with TomTom's arrow when TomTom
  is installed. It also says so once in chat; /naowh profrank repeats that. Covers every
  profession, Herbalism and Skinning included.
- Professions: an X in the recipe search box clears it.
- Professions: Crafts with Vendor Buys (off by default) adds a second, orange number next
  to each recipe: how many you could make after buying the reagents vendors sell, such
  as Weak Flux or Coarse Thread ("3 | 6", or just the orange "6" when you can make none
  yet). The chosen recipe's vendor reagents then say how many more to buy. Trade goods a
  merchant sells for gold without a stock limit are remembered when you visit them.
- Professions: Reagents in Bags and Reagents in Bank (both on by default) add Bags and Bank
  columns to the chosen recipe's reagents.
- Gear & Trinkets: a Trinket bar with two movable slots. Left-click uses the trinket,
  right-click (out of combat) picks another one from your bags.
- Macros: a Class Macros tab for macros supplied by your profile. Click or drag an icon to
  put it on your action bar. A macro that runs a script asks before it is created.
- Campfire: Buff Text Size, Buff Text Position (below, above, left or right) and Show
  Refresh Reminder settings.
- Blessings: Button Spacing, Aura / Class Gap, Timer Text Size and Class Labels settings;
  buttons go up to 70.
- XP Bar: choose the left, center and right text (level, XP, percent or rested).

### Changed
- Professions: your learned recipes sit under a Learned heading that folds away, and the
  unlearned ones are split into Learnable now, Needs more skill and Needs next rank (the
  last two folded by default). The recipe list has a scrollbar.
- Professions: Naowh's profession window is the only way the module shows recipes. The
  separate Naowh Profession Window switch and the unlearned-recipes drawer beside
  Blizzard's window are gone; the module's sidebar switch turns it all on and off.
- Buffs & Consumables: food, flask, scroll and elixir reminders come from the entries you
  add (an item ID and its buff spell IDs) or from an imported profile, instead of a built-in
  list. Hover a reminder to pick a configured item from your bags.
- Macros: the macro toggles are icons you click or drag onto your bars, created as General
  macros instead of character macros. Right-click an icon to remove its macro.
- Campfire: a new high-resolution icon. The timer ring is edged in black with no dark
  swipe over the icon, the seated label reads Resting, and each buff line shows the effect
  from the Camp Benefits tooltip.
- BiS: each spec keeps its own list; switching spec or importing no longer overwrites
  another spec's picks.
- XP Ticker: Level Splits is replaced by Level History, your most recent completed levels.
- Module names: Gear Sets is Gear & Trinkets, Alerts is Combat & Alerts.
- FPS and latency moved to the Top Bar; the On-Screen Extras options are gone.

### Fixed
- QoL's tab row no longer runs past the window edge and over the scrollbar; tabs tighten
  their spacing to fit.
- Threat Meter no longer throws a Lua error every update while it has a mob to show, which
  kept it from listing any threat.
- XP Bar: Blizzard's experience bar no longer comes back after a /reload. Its container's
  own fade-in animation was undoing the fade.

### Removed
- Streamer quotes on flights.
- Automatic loot confirmations (saved preferences are kept).

## 0.5.14-beta

### Added
- Tooltip Display (QoL > Tooltip Display): spell, item and NPC IDs under tooltips, and
  a copy card (Ctrl+Shift+C) with the ID or its Wowhead link, outside combat.
- Town Map: added 35 audited service NPC locations on Zephras Isle, including class and
  profession services, innkeeper, bank, auctioneer, vendors and repairs.
- The rest of NaowhQOL that works on Forever, each off by default:
  - Pet Tracker (QoL > Alerts): a warning while a hunter or warlock has no pet out or has
    it on passive, and optionally while the pet is low on health. A warlock who sacrificed
    their demon is left alone. Move it in Unlock Mode.
  - Equipment Reminder (QoL > Alerts): your trinkets, weapons and ranged slot in a small
    window when you enter a dungeon or raid or on a ready check, with an optional enchant
    check against the enchants you capture.
  - Emote Detection (QoL > Alerts): an alert and a sound when an emote in a dungeon or raid
    contains one of your words, plus auto emotes for spells you list, such as a summoning
    ritual.
  - Mouse Ring (QoL > Interface): a ring around your cursor with your global cooldown and
    casts swept around it, an optional trail, centre dot and border, idle fade, and a red
    recolour while your target is out of melee range.
  - GCD Tracker (QoL > Casting): your recent casts scrolling across the screen with a bar
    showing when you were busy, and an optional downtime summary after each fight. Move it
    in Unlock Mode.
  - Focus Cast Bar (QoL > Casting): your focus target's casts, coloured by whether your
    interrupt is ready, with a tick where it comes off cooldown, a shield on casts you
    cannot interrupt, and an optional sound or spoken line. Move it in Unlock Mode.
  - Performance (QoL > Performance): NaowhQOL's recommended graphics, frame rate and
    network settings, applied all at once or one at a time, with your own values kept so
    you can put them back, and the spell queue window.
- Swing Timer module: a bar for each weapon that can swing (Main Hand, Off Hand, Ranged),
  timed by the game's own swing event, so parry haste, swing resets and haste are always
  right. Range dimming, queued Heroic Strike / Cleave / Maul / Raptor Strike colors, class
  colors, textures and Unlock Mode placement. Its Timing Aids tab adds a window at the end of
  the melee swing (with optional latency), a hunter's Auto Shot cast window that turns red
  while moving, a mark where your cast ends against the next swing, and an estimated Target
  swing bar. Everything starts off.
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
- Threat Meter: focus tracking, class icons and rank numbers, and with Lock Window off
  it can be dragged and resized.
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
- Blessings: Next Blessing and Next Greater Blessing keybinds. Bind
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
