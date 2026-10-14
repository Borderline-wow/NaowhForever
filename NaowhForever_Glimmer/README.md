# Glimmer

Herbs, ore, quest objects, chests and your fishing bobber light up as you walk up to them, in one of
five effects: dim while out of reach, a flash and full brightness once you can use them. Herbs and
ore take the color of your chance of a skill-up and get a line under their name saying so; a node
your skill is too low for shows red with the skill it needs. Quest objects get the line of the
quest objective they count for. A second switch keeps the game's loot sparkle on quest items
through graphics presets. Two map switches: every spot herbs and ore grow near you as icons on the
minimap, ringed in their skill-up color, and every herb and vein you gather on the world map. Its settings page is Glimmer/Settings; its switches and their defaults
come from `ns.FEATURES.glimmer`.

## Layout

```
NaowhForever_Glimmer/
  NaowhForever_Glimmer.toc   the addon; lists only Glimmer.xml
  Glimmer.xml                every file, in load order
  Glimmer.lua                the settings (ns.GlimmerSettings), the module table (ns.Glimmer, G), its categories
  Constants.lua              the names, game settings, timings and limits its files share (G.C)
  Data/
    Nodes.lua                every herb, vein and chest by object ID, with the skill it needs (G.NODES),
                             from Tools/build/glimmer_nodes.py
  CVars.lua                  the game settings it changes, saved first and put back (G.CVars)
  Target.lua                 what the soft interact target is, its reach and its skill-up chance (G.Target)
  Spots.lua                  where herbs and veins grow (NaowhForever_GlimmerData), and the ones gathered (G.Spots)
  View/
    Style.lua                its look: skill colors, effect sizes and timings (G.Style)
    Effects.lua              the five effects on a frame, over the world and on the previews (G.Effects)
  UI/
    Conflict.lua             the question when another addon changes the same game settings (G.CheckOthers)
    Highlight.lua            the effect and its line on the target's nameplate, and its events
    Minimap.lua              where herbs and veins grow, as icons on the minimap
    MapPins.xml              the Gathered pin's template, and the file that fills it
    MapPins.lua              the herbs and veins you gathered on the world map, noted as you loot them
    SettingsPage.lua         its settings page, declared as cards, with its previews
  Media/                     glow, flare, ring, beam and bracket, drawn by Tools/media/make_media.py
  README.md                  this file
```

## Why

- The game always picks one object to interact with, the `softinteract` unit, and gives it a
  nameplate when `SoftTargetNameplateInteract` is on. Glimmer hangs its effect on that nameplate,
  so only that one object lights up and the effect follows it on screen with no work of ours.
- `SoftTargetInteract` 3 keeps the soft target on, and `SoftTargetInteractOnlyInRange` 0 lets it pick
  objects beyond reach, so they can light up dim before you get there. The range is capped at 15
  yards on the page because the client drops the soft target near there whatever is asked.
- The nameplate is only opened for an object Glimmer lights (`onlyHighlighted`), so NPCs, mailboxes
  and doors do not grow a nameplate. Whether to open it does not need the nameplate: the object is
  read from the unit token, then the nameplate arrives with `NAME_PLATE_UNIT_ADDED`.
- In combat the game will not change these settings, and an open soft target nameplate would sit
  on every lootable corpse with 0% health. The nameplate is closed on `PLAYER_REGEN_DISABLED`, just
  before the lockdown, and Glimmer rests until combat ends; a setting changed in combat is applied
  after it.
- What an object is comes from the object ID in its GUID, looked up in `G.NODES`; the bobber is
  object 35591. IDs work in every language. A herb or vein the data does not know is still found by
  the cursor the game would show on it (`SetUnitCursorTexture`): Mine or GatherHerbs, with an Unable
  variant when the game would refuse it.
- Quest objects come from `C_QuestLog.UnitIsRelatedToActiveQuest`, and their line is the quest
  objective line of the object's own tooltip, as the game words it.
- Gathering gives a point every time up to 25 skill over the node's (orange), usually up to 50
  (yellow), rarely up to 100 (green), and never past that (grey): `SKILL_ORANGE`, `SKILL_YELLOW`,
  `SKILL_GREEN`. The node's skill comes from the data, so a node your skill is too low for is red
  from as far as it is picked, not only once in reach.
- `UnitIsInInteractRange` is not in the 12.1 API docs but answers on Forever; without it every
  object counts as in reach. Its answer is read every `STATE_CHECK` while an object is lit, and a
  change must hold for `STATE_HOLD` before it shows, so the edge of reach does not flicker. That
  check runs only while something is lit; nothing runs while no object is.
- The effect is parented to the nameplate, one frame level under it so the game's name stays on
  top, and ignores the nameplate's alpha so it does not fade with it.
- The game settings Glimmer changes are saved in the account settings before the first change and
  written back when Glimmer or the Quest Item Sparkle is turned off, or by Restore. A graphics
  preset turns the quest sparkle settings back; `CVAR_UPDATE` on a preset or one of those settings
  puts them back `SPARKLE_AGAIN` seconds later, after the preset has finished writing.
- Taking the quest sparkle off only shows after a full restart of the game, so the card says so.
- Other addons that change the same soft target settings (`OTHER_ADDONS`) undo Glimmer's and it
  undoes theirs; with one on as well, Glimmer asks once per session to disable it.
- A slider drag sets its key on every step, so settings apply once on the next frame.
- The game does not tell an addon where its tracking dots are, and it cannot switch tracking for you:
  Find Herbs and Find Minerals are casts, which only a click may start. So the minimap icons come from
  where Wowhead Forever has each herb and vein growing (`ns.GlimmerSpots`, in the load-on-demand
  NaowhForever_GlimmerData), and herbs and ore show together whatever you track. The game's own dot on
  top of an icon is a node up right now.
- The minimap shows at most `MINIMAP_MAX` icons, the spots inside its view. Placing them is
  `Parts.MinimapLayer` (Shared/UI/MinimapPins.lua): it moves them only while you move or the minimap
  turns.
- The spot data loads the first time Minimap Icons is on, out of combat: loading an addon in combat is
  not something to rely on, so it waits for the fight to end, and only then does `PLAYER_REGEN_ENABLED`
  redraw the icons. A skill-up repaints their rings, and redraws them only when it changes whether
  herbs or ore show. Gathered on the Map alone never loads the data.
- Only My Professions shows herbs to an herbalist and ore to a miner; a character with neither sees
  both, so the icons still help someone deciding what to learn.
- A gather is noted when the loot window opens while the soft target is a herb or vein in reach and
  the loot came from it (`GetLootSourceInfo`), so it needs no spell IDs and a corpse looted beside a
  node does not count. One node counts once per loot window, even if it is opened again. Where it is
  noted is a pin already there for that node within `SNAP` (tenths of a map percent) of where you
  stand, else the data's own spot for it when the data is loaded, else where you stand, so gathering
  a node again when it grows back counts on the same pin. Each
  map keeps at most `MAX_GATHERED` nodes, dropping the one gathered longest ago. They are kept in the
  account settings, so every character's gathering shows.

## Checking

- `lua Tools/regression/test-glimmer.lua`: reading the target, skill-up colors, the game settings
  saved and put back, combat, the nameplate it opens, the minimap icons and the gathered pins, against
  stubs of the game's API.
