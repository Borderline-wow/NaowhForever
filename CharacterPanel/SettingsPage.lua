-------------------------------------------------------------------------------
--  SettingsPage.lua -- the character panel's cards on the BiS List's settings page: the Naowh
--  Character Panel with what it adds, and Slot Marks, the marks alone on the game's own panel.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local CP = ns.CharacterPanel
local S = ns.QoLSettings

local Settings = ns.Shared and ns.Shared.Settings
if not Settings then return end

local MARKS_OFF = "Turn on Slot Marks or the Naowh Character Panel"

-- The slots' marks: with either switch, the Naowh Character Panel or Slot Marks.
local function MarksOn()
    return S.Get("characterPanel") or S.Get("characterPanelSlotMarks")
end

local function PanelSummary(store)
    if CP.EllesmereSheet() then
        return store.Get("characterPanel") and "EllesmereUI's panel was turned back on: switch this off and on"
            or "Takes over from EllesmereUI's panel, after a reload"
    end
    local badge, score = store.Get("characterPanelBadge"), store.Get("characterPanelScore")
    if badge and score then return "With your badge and Naowh Score" end
    if badge then return "With your badge" end
    if score then return "With your Naowh Score" end
    return "The slots and stats only"
end

local function MarksSummary(store)
    if store.Get("characterPanel") and not store.Get("characterPanelSlotMarks") then
        return "On the Naowh Character Panel"
    end
    local shown = 0
    for _, key in ipairs({ "characterPanelLevels", "characterPanelMarks", "characterPanelEnchants" }) do
        if store.Get(key) then shown = shown + 1 end
    end
    return ("%d of 3 marks"):format(shown)
end

local page = Settings.Page("BiS List/Settings")

page:Card({
    id = "characterPanel", name = "Character Panel", order = 50, switch = "characterPanel", store = S,
    help = "Your character panel (C) in the BiS List's look: each slot with its marks, your stats for your "
        .. "spec, and your Naowh Score under your level. The game keeps the panel and everything it does. With "
        .. "EllesmereUI, turning this on turns its character panel off, and off turns it back on, after a reload.",
    summary = PanelSummary,
    rows = {
        { key = "characterPanelBadge", label = "Supporter Badge", toggle = true,
          help = "Your supporter badge, big in the panel's top corner; without one, the Legendary badge in "
              .. "grey: click it for what it is." },
        { key = "characterPanelScore", label = "Naowh Score", toggle = true,
          help = "Your Naowh Score, big under your level: hover it for your score with your BiS and the best "
              .. "in the game, click it for the BiS List." },
    },
})

page:Card({
    id = "slotMarks", name = "Slot Marks", order = 60, switch = "characterPanelSlotMarks", store = S,
    help = "The marks on the game's own character panel, as it looks (or EllesmereUI's), without the Naowh "
        .. "Character Panel. With it on, its slots have them already.",
    summary = MarksSummary,
    rows = {
        { key = "characterPanelLevels", label = "Item Level", toggle = true, always = true, needs = MarksOn,
          why = MARKS_OFF, help = "Each slot's item level, in its icon's corner." },
        { key = "characterPanelMarks", label = "BiS Marks", toggle = true, always = true, needs = MarksOn,
          why = MARKS_OFF, help = "Your BiS's star on a slot, and Forever's mark on what is new in Forever." },
        { key = "characterPanelEnchants", label = "Enchant Dots", toggle = true, always = true, needs = MarksOn,
          why = MARKS_OFF,
          help = "A dot on a slot where a better enchant for your level waits: hover it for the advice, click "
              .. "it to ask in Trade." },
    },
})
