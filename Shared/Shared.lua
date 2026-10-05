-------------------------------------------------------------------------------
--  Shared.lua -- what the addon's modules share (ns.Shared), so the Dungeon Journal, the BiS
--  List and any module after them look and work the same, from one copy of the code:
--
--    Style   the house look: colours, icons and sizes (Style.lua)
--    Items   item and gear helpers: an ID from a link, quality colours, slots (Items.lua)
--    Parts   components: links, icon buttons, the backdrop and its cards, panels, side
--            panels, rank stars, item icons (Parts.lua); and a window's title bar, opacity
--            slider, switch, search and footer (Window.lua)
--    View    the engine that draws a page as pooled rows (View.lua)
--    Kinds   the rows every page has: a section title, a note, a card (Kinds.lua)
--    Played  the character's /played time, asked for once and kept running (Played.lua)
--
--  And Shared.CharacterData(key, create): what this character keeps under key in the account's
--  saved data, by its GUID (first names are not unique on Forever); nil before the game knows
--  who you are. The Journal's kills and loot, and the XP Ticker's level history.
--
--  Loaded after Core and before every module. Nothing is made or listened to at load: a
--  module builds what it uses when it first shows it.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever

ns.Shared = { Parts = {}, Kinds = {}, Items = {}, View = {} }

function ns.Shared.CharacterData(key, create)
    local guid = UnitGUID("player")
    if not guid then return end
    local account = ns.AccountSettings()
    local all = account[key]
    if type(all) ~= "table" then
        if not create then return end
        all = {}
        account[key] = all
    end
    local mine = all[guid]
    if type(mine) ~= "table" then
        if not create then return end
        mine = {}
        all[guid] = mine
    end
    return mine
end
