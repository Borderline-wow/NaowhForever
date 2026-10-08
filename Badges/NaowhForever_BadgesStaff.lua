-------------------------------------------------------------------------------
--  NaowhForever_BadgesStaff.lua -- Naowh, the developers, the moderators and
--  Ellesmere (EllesmereUI), edited by hand in a normal pull request. Keyed by region (GetCurrentRegion) and character GUID: names on
--  Forever aren't unique, and regions have their own characters. Forever reports its own
--  region numbers, not retail's 1 to 5 (90 for Dieman's characters). /nf badges id gives the
--  region and IDs to use: "90:Player-4613-006EB819" goes under [90]. A staff entry wins over
--  a patron one.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever

-- tier: "naowh", "developer", "moderator" or "ellesmere"; title is optional ("Lead Developer").
ns.BADGE_STAFF = {
    [90] = {
        ["Player-4618-0111FC51"] = "naowh", -- Naowh
        ["Player-4613-006EB819"] = { tier = "developer", title = "Lead Developer" }, -- Dieman
        ["Player-4620-0069A23D"] = { tier = "developer", title = "Lead Developer" }, -- Glyalith
    },
}
