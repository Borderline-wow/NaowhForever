-- Constants.lua: the names, timings and textures the Swing Timer's files share.
local ns = _G.NaowhForever

ns.SwingTimer.C = {
    PAGE = "Swing Timer/Settings",
    BAR_LABELS = { "MH", "OH", "R", "TGT" },
    BAR_SWITCH = { MH = "showMH", OH = "showOH", R = "showR", TGT = "targetSwing" },
    SPEED_RETURN = { MH = 1, OH = 2, R = 3, TGT = 1 },
    AUTO_SHOT_CAST = 0.5,
    FLAT_TEX = ns.Shared.Style.WHITE,
}
