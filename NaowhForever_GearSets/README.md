# Gear & Trinkets

A bar of your equipment sets to swap with a click, saving new ones from what you wear, and
automatic swaps to a set while mounted or resting that put your previous set back afterwards.
Built on the client's own equipment manager, so the sets are the ones the character sheet
shows. Also a movable bar of your two trinket slots. Its settings are in the QoL store
(`gearSets`, `gearBarVisible`, `trinketBar` and the `gear*`/`trinket*` keys), on the
Gear & Trinkets/Settings page; the sets themselves are in the Gear Sets window (`/nfgear`, its
minimap and Top Bar button, Open Gear Sets on its settings page).

## Layout

```
NaowhForever_GearSets/
  NaowhForever_GearSets.toc   the addon; lists only GearSets.xml
  GearSets.xml                every file, in load order
  GearSets.lua                the rules and API (ns.GearSets, G): your sets, equipping one,
                              equipping after combat, the automatic swaps
  Constants.lua               what its files share (G.C): the settings page, the trinket slots
  View/
    Style.lua                 its look (G.Style), on top of Shared/Style.lua
    Look.lua                  a set or trinket button's look, on the bars and previews (G.Look)
  UI/
    Dialogs.lua               new, rename, save and delete a set, and the icon picker
    Bar.lua                   the Gear Set Bar, and the events behind it and the swaps
    TrinketBar.lua            the Trinket Bar and its picker of trinkets in your bags
    Window.lua                the Gear Sets window
    SettingsPage.lua          its settings page, declared as cards, with the bars' previews
  README.md                   this file
```

## Why

- Armor cannot change in combat, so a set asked for then waits for the fight to end
  (`G.EquipPending` on `PLAYER_REGEN_ENABLED`).
- The set an automatic swap replaced is kept per character in the account settings
  (`gearReturn`), so logging out in town or mounted still puts it back after the next login.
- A set picked by hand is kept when the automatic swap ends. Mounted beats resting.
- The automatic swap choices hold the set's name, so renaming a set updates them.
- A set swap fires `PLAYER_EQUIPMENT_CHANGED` once per slot; one redraw on the next frame covers
  the burst.
- The bar's Show (Always, In Combat, Out of Combat) is ignored in the HUD Editor, which always
  shows it; it listens to `PLAYER_REGEN_DISABLED` only when Show is not Always.
- The icon picker uses the client's own icon list, the one its equipment manager offers, with
  the icons of what you wear first. The list holds every macro icon while open, so it is
  released on close. Hiding the UI (Alt-Z, a cinematic) hides the dialog too, which releases
  the icons, so it stays closed when the UI comes back. The grid is built once; what changes
  per open (the icon list, the action) is kept on it.
- `EMPTY_ICON` (134400) is the game's question mark, for an empty trinket slot.
- The trinket slots are secure item buttons: a change to them waits for combat to end, and a
  right-click to pick a trinket works only outside combat. The bags are checked again on the
  click, since they may have changed since the picker opened.
- The secure item action errors on an empty slot (a nil link into `C_Item.IsEquippableItem`), so
  an empty slot gets no `type1`.
- The window listens only while it is open.

## Checking

- `lua Tools/regression/test-robin-final.lua`: the trinket bar (secure buttons, the picker, combat
  deferral, its events only while on) and the gear bar's Show choices.
