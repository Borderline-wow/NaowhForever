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
--
--  Loaded after Core and before every module. Nothing is made or listened to at load: a
--  module builds what it uses when it first shows it.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever

ns.Shared = { Parts = {}, Kinds = {}, Items = {}, View = {} }
