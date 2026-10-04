-------------------------------------------------------------------------------
--  SettingsPage.lua -- the character panel's tab on the BiS List's settings: what it does, its
--  switch and what it shows on the slots, and with EllesmereUI, that the switch swaps its
--  character panel for this one. Page builder only, resolved by the options window at open time.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local CP = ns.CharacterPanel
local S = ns.QoLSettings

local ABOUT = "Your character panel (C) in the BiS List's look: each slot with its item level, "
    .. "Forever's mark on what is new in Forever, your BiS's star and a dot where a better enchant "
    .. "waits, and your Naowh Score under your level. The game keeps the panel and everything it "
    .. "does; Naowh only restyles it. Rather keep the game's look? Slot Marks puts the marks alone "
    .. "on its slots."

local ELLESMERE = "You have EllesmereUI's character panel on. Turn on Naowh Character Panel below "
    .. "and it takes over: EllesmereUI's turns off, and comes back if you turn Naowh's off again "
    .. "(each after a reload)."
-- The slots' marks: with either switch, the Naowh Character Panel or Slot Marks.
local function MarksOff()
    return not (S.Get("characterPanel") or S.Get("characterPanelSlotMarks"))
end
local function OnSlots(row)
    row.disabled = MarksOff
    return row
end

local ELLESMERE_BACK = "EllesmereUI's character panel was turned back on in its options, so Naowh's "
    .. "stays off. Turn Naowh Character Panel off and on again to switch back."

function ns.BuildQoLCharacterPanelPage(parent, y)
    local UI = ns.UI
    local W = UI.Widgets
    local _, h
    _, h = W:Note(parent, ABOUT, y); y = y - h
    if CP.EllesmereSheet() then
        _, h = W:Note(parent, ns.QoLSettings.Get("characterPanel") and ELLESMERE_BACK or ELLESMERE, y); y = y - h
    end
    _, h = W:SectionHeader(parent, "CHARACTER PANEL" .. UI.STATUS.untested, y); y = y - h
    _, h = W:Feature(parent, y,
        S.Toggle("characterPanel", "Naowh Character Panel",
            "Restyles your character panel in the BiS List's look. With EllesmereUI, turning this on "
            .. "turns its character panel off, and turning this off turns it back on, after a reload.")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("characterPanelBadge", "Supporter Badge",
            "Your supporter badge, big in the panel's top corner; without one, the Legendary badge "
            .. "in grey: click it for what it is.", "characterPanel"),
        S.Toggle("characterPanelScore", "Naowh Score",
            "Your Naowh Score, big under your level: hover it for your score with your BiS and "
            .. "the best in the game, click it for the BiS List.", "characterPanel")
    ); y = y - h

    _, h = W:SectionHeader(parent, "SLOT MARKS", y); y = y - h
    _, h = W:Feature(parent, y,
        S.Toggle("characterPanelSlotMarks", "Slot Marks",
            "The marks on the game's own character panel, as it looks (or EllesmereUI's), without the "
            .. "Naowh Character Panel. With it on, its slots have them already. On by default.")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        OnSlots(S.Toggle("characterPanelLevels", "Item Level",
            "Each slot's item level, in its icon's corner.")),
        OnSlots(S.Toggle("characterPanelMarks", "BiS Marks",
            "Your BiS's star on a slot, and Forever's mark on what is new in Forever."))
    ); y = y - h
    _, h = W:DualRow(parent, y,
        OnSlots(S.Toggle("characterPanelEnchants", "Enchant Dots",
            "A dot on a slot where a better enchant for your level waits: hover it for the advice, "
            .. "click it to ask in Trade."))
    ); y = y - h
    return y
end
