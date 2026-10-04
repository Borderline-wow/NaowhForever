-------------------------------------------------------------------------------
--  SettingsPage.lua -- the Naowh Score's tab in QoL: what it is and yours now, its switch, and
--  where it shows. Page builder only, resolved by the options window at open time.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local Score = ns.NaowhScore
local S = ns.QoLSettings

local ABOUT = "One number for a character's gear, on the item level scale: 26.4 means your gear is "
    .. "worth a set of level 26 epics. Each slot counts its item's level by how much of an item's "
    .. "stats that slot carries and by its quality; an empty slot counts 0. Yours is shared with "
    .. "your group and guild as it changes, so everyone running Naowh Forever sees it at once."

local COMPARE = { values = { max = "Best in the Game", level = "Best for Their Level", both = "Both" },
    order = { "max", "level", "both" } }

function ns.BuildQoLNaowhScorePage(parent, y)
    local UI = ns.UI
    local W = UI.Widgets
    local _, h
    local yours = ""
    if not UI.searchScan then
        local best = Score.Best()
        yours = "  Yours now: " .. Score.Colored((Score.Unit("player")), UnitLevel("player")) .. "."
            .. (best and ("  The best Forever's gear allows: " .. Score.Text(best) .. ".") or "")
    end
    _, h = W:Note(parent, ABOUT .. yours, y); y = y - h
    _, h = W:SectionHeader(parent, "NAOWH SCORE" .. UI.STATUS.untested, y); y = y - h
    _, h = W:Feature(parent, y,
        S.Toggle("naowhScore", "Naowh Score",
            "Shows the Naowh Score of players you hover. Your own is always on the BiS List's paperdoll.")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("naowhScoreTooltip", "On Player Tooltips",
            "A player's score on their tooltip. One running Naowh Forever shares theirs; anyone else's "
            .. "is read from their gear when you hover them, as the game's Inspect does: they need no "
            .. "addon, but must be within inspect range, and it waits out combat.", "naowhScore"),
        S.Toggle("naowhScoreScan", "Scan Your Group",
            "Reads your group members' gear in the background, one at a time while they are in range "
            .. "and out of combat, so their scores are ready before you hover them.", "naowhScore")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("naowhScoreNearby", "Scan Players Nearby",
            "Reads the gear of the players around you in the background: your target, focus and "
            .. "mouseover, and everyone whose nameplate shows, one at a time while in inspect range and "
            .. "out of combat. Friendly players show nameplates only with friendly nameplates on in the "
            .. "game's Interface options.", "naowhScore"),
        S.Dropdown("naowhScoreCompare", "Grade Against", COMPARE.values, COMPARE.order,
            "A score takes the colour of an item's quality by its share of the best: grey under 25%, "
            .. "white, green from 45%, blue from 65%, purple from 80%, orange from 95%. The best in the "
            .. "game, so anyone still levelling is grey or white; the best for the player's level, "
            .. "so you see who is well geared for where they are; or Both: the score against the best in "
            .. "the game, then in gold its share of the best for their level (\"44% of level 20\"), "
            .. "as the BiS List's score card marks your level's goal in gold.", "naowhScore")
    ); y = y - h
    return y
end
