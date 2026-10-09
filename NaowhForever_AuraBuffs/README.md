# AuraBuffs

Buff and consumable reminders, the Campfire and Low Health. Its settings page is
AuraBuffs/Settings; the consumables to watch are listed in the AuraBuffs window (`/nfbuffs`, its
minimap and Top Bar button). Its on/off switches and their defaults come from
`ns.FEATURES.auraBuffs`.

- **Buffs & Consumables:** a row of icons for missing food, flask and elixir buffs from the
  consumables you watch, and class buffs missing in your group. Hover one to use a carried item.
- **Campfire:** in two looks on one mover. Round, a camp icon with a time ring and a countdown;
  Simple, a bar in the windows' backdrop with the campfire at its left, the camp's bonuses with
  their amounts, and the time left on the right over a line that runs down green, yellow, then
  red. Hovering it lists each bonus, the time left and when to refresh.
- **Camp Nearby:** the same bar drawn bare (no backdrop, edge or line), larger by its own scale,
  sized to what it says and stacked in the Alerts group (`ns.AlertStack`), with the camp's time
  left inline after a dot while it still runs.
- **Low Health:** the best healing item in your bags, with a LOW HEALTH warning, while your health
  is under the threshold.

## Layout

```
NaowhForever_AuraBuffs/
  NaowhForever_AuraBuffs.toc   the addon; lists only AuraBuffs.xml
  AuraBuffs.xml                every file, in load order
  AuraBuffs.lua                the settings (ns.AuraBuffSettings), the module table (ns.AuraBuffs, A),
                               consumable entries kept in the profile, ns.ParseConsumableEntry,
                               the consumables list string (ns.ConsumableListString,
                               ns.ParseConsumableList), ns.CampBuffMode
  Constants.lua                the numbers several of its files share (A.C)
  Data/
    BuffReminders.lua          the spells and items behind the buff reminders (ns.BuffReminderData)
    Campfire.lua               the camp auras and each camp feature's bonus, by spell ID (A.CampData)
  BuffReminders.lua            which consumables and class buffs are missing (A.Buffs)
  CampReader.lua               which camp bonuses you have, from their auras and Camp Benefits'
                               tooltip, and their labels (A.Camp)
  LowHealth.lua                the item to offer and the curve that shows it (A.LowHealth)
  View/
    Style.lua                  its look (A.Style), on top of Shared/Style.lua
    BuffCell.lua               a buff reminder icon (A.BuffCell)
    CampIcon.lua               the campfire art and the Round look (A.CampIcon)
    CampBar.lua                the Simple bar (A.CampBar)
    CampAlert.lua              the Camp Nearby alert's look and fades (A.CampAlert)
    LowHealthLook.lua          the Low Health icon and warning (A.LowHealthLook)
  UI/
    SettingsPage.lua           the page's banner (Open AuraBuffs) and its Window card
    Campfire.lua               the Campfire reminder and the Camp Nearby alert on screen
    CampfireCards.lua          the Campfire and Camp Nearby cards, with their editable previews
    LowHealth.lua              the Low Health icon on screen
    LowHealthCard.lua          the Low Health card
    BuffMenu.lua               the carried items a buff reminder offers, as secure buttons
    BuffReminders.lua          the buff reminder row on screen
    BuffsCard.lua              the Buffs & Consumables card
    WindowPages.lua            the window's page: consumables, with list import and export
    Window.lua                 the AuraBuffs window
  Media/CampfireHD.tga         the campfire icon's art (View/CampIcon.lua)
  README.md                    this file
```

## Why

- In combat the client refuses addons the player's auras outright (`GetAuraDataByIndex` errors,
  `GetPlayerAuraBySpellID` returns nil with the buff up), and it withdraws them at boss pulls
  before `InCombatLockdown()` turns true. Every read is gated on
  `C_Secrets.ShouldAurasBeSecret()`, and the reminders keep what they last showed until combat
  ends, or they would read every buff as missing. `InCombatLockdown()` is still false while
  `PLAYER_REGEN_DISABLED` is handled, so that event is checked too.
- A `UNIT_AURA` unit arrives secret while auras are restricted; `PLAYER_REGEN_ENABLED` catches up.
- Consumable entries are profile data, never code: an item ID, then buff spell IDs only when the
  buff is not the item's own, checked as plain numbers. They travel in a profile string's
  Consumables part (`utilityReminders.consumables` in the profile); presentation settings stay in
  the module's store.
- An entry with no buff IDs: food counts any Well Fed (every cooked food's buff is named Well Fed,
  whatever it raises, so it is matched by the name of `D.WELL_FED[1]`), other items their use spell
  (`C_Item.GetItemSpell`), which needs the item cached. An uncached item is asked for once, and only
  its own `ITEM_DATA_LOAD_RESULT` refreshes: an ID with no use spell would otherwise load, refresh
  and ask again forever.
- The consumables list string is one line, since the paste box is one line:
  `NFCONSUMABLES1:food=13931,2680;battle=13454/17539`. Import also takes a profile string and keeps
  only its consumables, through the same checks as the profile import; it adds what is not listed
  yet, up to `MAX_ENTRIES` (500, the same limit the profile import enforces).
- Group auras change in bursts, so a buff refresh waits `QUEUE_DELAY` and covers the lot. Nothing
  fires as a buff runs down, so the earliest one to cross the warning time is timed.
- `ELIXIR_ICON` (13454, Greater Arcane Elixir) stands for "no elixir at all" in the preview.
- Two classic elixirs for the same stat do not stack, so one of each group counts; Forever's
  stacking is unconfirmed. Forever keeps the classic IDs for flasks, elixirs, scrolls and class
  buffs; cooked food moved to Forever-only "Nutritious Food" spells with one shared Well Fed aura
  per stat (Wowhead's Forever data, build 1.60.1). Flask of Petrification is left out: it is a
  minute of stone form, not a buff to keep up.
- Paladin blessings start off in the raid buff picks: the Blessings module covers them. A talent
  buff (Divine Spirit) only counts when you can cast it, since another player's talents cannot be
  seen. A camp buff standing in for a class buff is not seen, so it still counts as missing.
- The buff menu holds secure buttons, so it can only be hidden outside combat. It uses
  `IsMouseOver` on the frame: the old `MouseIsOver` global is gone from the game.
- Camp Benefits (1229741, probed 2026-09-19), Campfire Nearby (1283391, the area aura in range of
  a campfire, 2026-09-24) and Welcoming Campfire (1229739 and the crafting 1289723, the 60 second
  aura while sitting, before Camp Benefits lands, 2026-09-25) were probed on the client.
- Camp Benefits is earned in the open world, so dungeons, raids and battlegrounds never nag about
  it.
- The bonuses come from the hidden aura each camp feature puts on you, by spell ID, and for the
  rest from Camp Benefits' tooltip (wago.tools build 1.60.1.70205), in `FEATURES` order with no
  feature twice. One tooltip line per feature, matched by the feature's name as the client spells
  it, its numbers read in the description's order (the Lute's armor, stats, resistances; the Mana
  Well's mana, then its 5 seconds). The tooltip is kept once per Camp Benefits as soon as a read
  finds anything; an empty read is tried again at most every `LINE.RETRY` seconds.
- The time ring's color by time left: green above 30 minutes, yellow above 5, red below. Nothing
  fires as the buff runs down, so each color change is timed, and a generation number throws away
  a timer armed for an older state.
- Show Active Camp Buffs (Off, Always, On Mouseover): a profile that never picked one follows the
  old on/off switch (`campBuffs`), so nobody's setting changes. On Mouseover the buff lines stay
  written but invisible until the icon is hovered, and the icon only takes the mouse then, so
  clicks and camera drags otherwise go through.
- The Round icon's plate follows the theme's Panels color (`ns.ThemeTint`), and a black circle one
  pixel wider behind it is its 1px round border. The black disk extends past the time ring on both
  sides, edging it.
- The Simple bar: nothing draws outside it, so it can sit anywhere. Every state keeps the fire, the
  words and the bar's size the same; the down states leave the time's place empty. It is never
  narrower than four wide bonuses need at its text size (`CAMP_MIN_LABELS`), and its text never
  under 11. `FONT_LIFT` raises its words: the Naowh font sits low. Its fire has no plate or ring:
  the art (transparent round its fire) sits on the bar's own backdrop, `CAMP_ART_CROP` trimming its
  empty margin so the fire fills the square. `Parts.LabelRow` sets the Addon Font on the labels it
  makes, so the bar's font goes on after.
- Both looks keep the fire on one screen spot: Round's centre is the Simple fire's centre. The saved
  spot is LEFT for Simple and CENTER for Round (an older corner point is the Round icon's),
  converted to the current style once, when placed, from the settings alone. A setting change
  refilters the last bonuses read (`FilterBar`), so the bar repaints in every state, resting too.
- Camp Nearby shows when a campfire is in range and the camp needs a refresh: no Camp Benefits, or
  less than Alert Under left. With Simple it shows only while Camp Benefits is still up and low:
  once it is gone, the bar's own Camp Nearby pill says it. It fades in, breathes and fades out
  through animation groups, never OnUpdate. With no background its words keep the card's shadow.
  `UNIT_AURA` fires often, so its timer is only set again for a new expiry, and a new Alert Under
  disarms the old one.
- Right-click (or Ctrl-click) hides Camp Nearby until you leave the campfire's range. Only right
  clicks are taken (`SetPassThroughButtons`, set out of combat), and it takes the mouse only while
  Ctrl is down, so left clicks and camera drags still reach the world.
- Low Health offers healthstones then potions, best first, from the core's lists
  (`ns.HEALTHSTONES`, `ns.HEALING_POTIONS`, in `Shared/Game/Consumables.lua`), which the Macros
  module's NF Health reads too, so either works with the other off.
- Low Health never compares the health: a step curve turns the health percent into 1 below the
  threshold and 0 above it, and the engine applies that as the frame's alpha itself, so it works in
  combat even where health is secret to addons. The curve is flat on both sides of the threshold,
  so it gives the same answer whether it snaps to the point before or the nearest point.
- The Low Health sound and glow need the health itself. Where the client hands it over readable the
  sound plays once per dip below the threshold and the glow runs only while low; a secret read skips
  the sound and leaves the glow running under the alpha. The Font Size is the warning's; the count
  keeps its size and follows the font and outline.

## Checking

- `lua Tools/regression/test-buff-reminders.lua`: which reminders show, the item menu, the card.
- `lua Tools/regression/test-campfire-simple.lua`: both Campfire looks, the reader, Camp Nearby and
  the cards' previews.
- `lua Tools/regression/test-icon-look.lua`: Low Health's text.
- `lua Tools/regression/test-robin-final.lua`: consumable entries and the Round campfire.
- `lua Tools/regression/test-combat-perf.lua`: the buff reminders' cost in a raid.
