-- LootCard.lua: the card on Loot & Items that Looting, Vendors, Auction Prices and Mail & Alts put their settings into.
local ns = _G.NaowhForever

ns.Shared.Settings.Page("QoL/Loot & Items", ns.QoLSettings):Card({
    id = "lootTrade", name = "Looting, Vendors, Mail & Auction House", order = 10,
    help = "Looting, selling and repairing at vendors, auction house prices, and mail with your alts.",
    rows = {},
})
