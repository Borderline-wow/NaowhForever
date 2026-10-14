# Instance Tracker

Each dungeon or raid visit (time, loot, experience, deaths, reputation and who was there), the
account's new instances this hour against the game's cap, a run timer that moves in the HUD
Editor, and the leave summary. As group leader it tells Nova Instance Tracker users about a reset.

## Layout

```
NaowhForever_InstanceTracker/
  NaowhForever_InstanceTracker.toc  its metadata, and one file line: InstanceTracker.xml
  InstanceTracker.xml               every file, in load order
  InstanceTracker.lua               settings, visits, the hourly count, Nova's reset messages, the run timer
  UI/
    Pages.lua                       This Hour and History
    Window.lua                      This Hour and History in the module's own window
    SettingsPage.lua                its settings page, declared as cards
```

## Why

- Each character is saved under `instanceTrackerChars[UnitGUID]`. The old name-keyed
  `instanceTracker` blob is left unread: a name cannot tell two alts apart.
- On Forever `UnitName` is the first name and `UnitFullName` the whole one ("Glyadin Skywolf");
  both stop at a hyphen, and `UnitFullName` has been seen handing back "Name-Realm" in its first
  return, so a realm glued on is stripped. Nova's messages arrive under the first name.
- The cap is the account's: 10 new dungeons or raids in a rolling hour, summed over every
  character's list (Track Alts only changes what is listed). A login or reload inside does not
  count; a different group zoning in does (one shared name keeps the visit, and an empty roster
  while grouped has not loaded yet); a later matching zone id takes the count back. The warning
  is noted on the character, so an alt already warned does not swallow it.
- A creature, pet, object, vehicle or cast GUID is `type-0-server-instanceID-zoneUID-id-spawn`:
  instanceID is 0 outdoors and cannot tell one reset from the next, zoneUID names the copy. A
  player GUID has neither. The copy is read from the target, mouseover, nameplates and casts, and
  those events are dropped once one is read: the copy cannot change without a zone change, which
  turns them back on.
- A ghost, or a death the client kept secret, keeps the visit open instead of announcing a leave.
  A secret chat lockdown counts as locked (the summary is printed instead), a secret answer to
  whether Nova is loaded counts as loaded (no second reset line), and a secret or failed read
  keeps the sheet's previous number.
- `skipped` is the time away from the visit (logged out, reloading, outside the copy) and `seen`
  the start of a gap still open, so the timer stays put at a graveyard.
- Durability is its own scan, on UPDATE_INVENTORY_DURABILITY, so a kill does not walk every
  equipped slot. The sheet is written at once and the open page follows a second later, so a bag
  update does not rebuild it slot by slot.
- A leave summary in group chat is one message up to 255 characters, else a second complete one
  split between facts. It goes to raid chat only with Send to Raid Chat on; alone, nothing is sent.
- Nova Instance Tracker talks on the `NIT` prefix: `<command> <version> <instance>` (the name keeps
  its spaces), through LibSerialize, LibDeflate at level 9 and the addon-channel encoding. Version 1
  is the oldest Nova reads. `instanceReset` rides with a "[NIT] " chat line, `instanceResetNoMsg`
  leaves the line out and Nova prints it, `instanceResetOther` is that print from Nova World Buffs.
  AceComm reads a leading control byte as its own framing, so such a payload is sent behind the
  escape byte. A failed chat send of a reset falls back to `instanceResetNoMsg`, Reset Chat off
  still tells Nova users, and with Nova loaded nothing is sent: it posts the same line itself.
- An incoming reset from another realm, or from a group member who is not the leader, is ignored.
  A name that matches no unit is still taken: Forever's addon sender is often a full name no unit
  API returns, and Nova sends this only as the leader. A reset drops the stored copies of that
  instance but not the hour's entries: a reset does not give one back.
- The regression tests slice `InstanceTracker.lua`: `-- end copy memory` and
  `-- end Nova reset wire format` close two of the slices, and the tests pass their zone id into
  `TakeSameCopy`, so `ReadZone` is only filled in once the unit reads exist.
- On the settings page, Send to Raid Chat's `needs` sets its `why` before the row reads it: the
  module first, then Group.
