-------------------------------------------------------------------------------
--  View/ItemRows.lua -- one item of a boss's loot: its icon in a black border; its name in
--  its quality colour with its marks after it (an orange star for your BiS, its pick number
--  for the rest of your list, the game's green arrow for an upgrade); under that, muted, what
--  it is and the level it needs (red while above yours), then In Bag or In Bank and the
--  hanger for a look you do not have; and the drop chance on the right, over its bar, or a
--  faction reward's price. What you wear has a green bar at the card's edge. Its tooltip is
--  the game's with a line for each mark, and right-click is the BiS List.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local T = ns.THEME
local J = ns.Journal
local Loot = J.Loot
local Rep = J.Reputation
local FACT = J.FACT

local GetItemInfo = C_Item.GetItemInfo
local GetItemInfoInstant = C_Item.GetItemInfoInstant
local GetItemIconByID = C_Item.GetItemIconByID
local GetItemQualityColor = C_Item.GetItemQualityColor
local GetItemCount = C_Item.GetItemCount
local IsEquippedItem = C_Item.IsEquippedItem
-- Forever has the money string only here: the global GetCoinTextureString is not loaded.
local GetCoinTextureString = C_CurrencyInfo.GetCoinTextureString

local St = J.Style
local RED_CODE, BIS_CODE, BIS_RGB, UPGRADE_CODE = St.RED_CODE, St.BIS_CODE, St.BIS_RGB, St.UPGRADE_CODE
local LOOK_CODE, LOOK_RGB, HAVE_RGB, HANGER = St.LOOK_CODE, St.LOOK_RGB, St.HAVE_RGB, St.HANGER
local STAR, UPGRADE_ATLAS, LOGO_SMALL = St.STAR, St.UPGRADE_ATLAS, St.LOGO_SMALL
local PLACE_DOT, CARD_PAD, ICON, ITEM_H = St.PLACE_DOT, St.CARD_PAD, St.ICON, St.ITEM_H
local CHANCE_W, CHANCE_BAR_W, CHANCE_HIGH, CHANCE_FAIR = St.CHANCE_W, St.CHANCE_BAR_W, St.CHANCE_HIGH,
    St.CHANCE_FAIR
local UNUSABLE, BORDER_RGB, ROUND, BAG = St.UNUSABLE, St.BORDER_RGB, St.ROUND, St.BAG

local View = J.View
local Kinds = View.Kinds

local WEAPON, ARMOR, RECIPE = 2, 4, 9   -- the game's item classes
local ARMOR_TYPES = { [1] = true, [2] = true, [3] = true, [4] = true }   -- cloth, leather, mail, plate
-- A weapon that only goes in one hand, and how it is said in short.
local ONE_HAND_ONLY = { INVTYPE_WEAPONMAINHAND = "MH", INVTYPE_WEAPONOFFHAND = "OH" }
-- Weapons in short, as players say them ("1h Sword", "Bow"), by the game's weapon subclass
-- (Enum.ItemWeaponSubclass) rather than its words, so any client language gets them: the
-- noun, and the hands where the type says ("1h", "2h"). One of these only goes in one hand
-- says which instead ("MH Sword", "OH Dagger"). Any other weapon has the game's own name.
local WEAPON_SHORT = {
    [0] = { "Axe", "1h" }, [1] = { "Axe", "2h" }, [2] = { "Bow" }, [3] = { "Gun" },
    [4] = { "Mace", "1h" }, [5] = { "Mace", "2h" }, [6] = { "Polearm" }, [7] = { "Sword", "1h" },
    [8] = { "Sword", "2h" }, [10] = { "Staff" }, [13] = { "Fist Weapon" }, [15] = { "Dagger" },
    [16] = { "Thrown" }, [18] = { "Crossbow" }, [19] = { "Wand" },
}
local weaponNames = {}   -- subclass and hand -> its short name, made once each
local NAME_TOP, CHANCE_TOP, BAR_BOTTOM = 1, 8, 11
local BAR_H = 4             -- the chance's bar, a pill as thick as the opacity slider's track
local DEEP = 0.6            -- the bar's fill starts at its colour this dark, as the slider's does

-------------------------------------------------------------------------------
--  Tags
-------------------------------------------------------------------------------
-- An icon in a line of text is centred on the line. In a tooltip's lines the icons go this
-- much lower, level with the letters.
local INLINE_DROP = 1
-- On an item's card they stay centred: there the Naowh font's capitals fill the middle of the
-- line, measured in game (2 Oct 2026: a name's capitals on rows 13 to 21 of a 12px line, and
-- the arrow dropped by INLINE_DROP 1.5px under them, its tip at the capitals' top).
local CARD_DROP = 0

-- A texture in a line of text at the text's height, tinted; drop is how much lower.
local function Inline(texture, color, drop)
    return ("|T%s:0:0:0:%d:64:64:0:64:0:64:%d:%d:%d|t"):format(texture, -(drop or INLINE_DROP), color.r * 255,
        color.g * 255, color.b * 255)
end

-- After the name: the orange star for your #1, the pick number for the rest of your list.
local STAR_ICON = Inline(STAR, BIS_RGB)
local STAR_TAG = "  " .. Inline(STAR, BIS_RGB, CARD_DROP)

local function RankTag(rank)
    if not rank then return "" end
    return rank == 1 and STAR_TAG or ("  %s#%d|r"):format(BIS_CODE, rank)
end

-- After that: the game's green arrow when it beats what you wear in its slot.
local UPGRADE_ICON = ("|A:%s:0:0:0:%d|a"):format(UPGRADE_ATLAS, -INLINE_DROP)
local UPGRADE_TAG = "  " .. ("|A:%s:0:0:0:%d|a"):format(UPGRADE_ATLAS, -CARD_DROP)

-- On the second line: In Bag when it is in your bags, else In Bank when it is in your bank.
-- What you wear has its bar.
-- In the worn bar's green, muted: a state of the item, quieter than its name.
local KEPT_CODE = ("|cff%02x%02x%02x"):format(HAVE_RGB.r * 200, HAVE_RGB.g * 200, HAVE_RGB.b * 200)
local IN_BAG_TAG = "   " .. KEPT_CODE .. "In Bag|r"
local IN_BANK_TAG = "   " .. KEPT_CODE .. "In Bank|r"
-- A recipe you already know: the game's check and Known, in the same green.
local KNOWN_TAG = "   " .. Inline(St.CHECK, HAVE_RGB) .. " " .. KEPT_CODE .. "Known|r"

local function Kept(itemID)
    if GetItemCount(itemID) > 0 then return IN_BAG_TAG end
    if GetItemCount(itemID, true) > 0 then return IN_BANK_TAG end
    return ""
end

-- With Show Appearances on: the hanger in the looks' cyan (as on the header) on the second
-- line for a look you do not have; nothing for one you have, or on what you wear, whose look
-- you have by wearing it.
local NEW_LOOK_ICON = Inline(HANGER, LOOK_RGB)
local NEW_LOOK_TAG = "   " .. Inline(HANGER, LOOK_RGB, CARD_DROP)

-- The first of the Journal's lines in an item's tooltip, so they read as ours among other
-- addons': the Naowh N, then "Naowh" in white and "Forever" in the accent, as the options
-- window writes it. Made when shown, so it follows the theme's accent.
local LOGO_ICON = ("|T%s:0:0:0:%d|t"):format(LOGO_SMALL, -INLINE_DROP)

local function BrandLine()
    return LOGO_ICON .. " Naowh " .. ns.Color("accent", "Forever")
end

-- What a click on an item does, at the foot of its tooltip.
local CLICK_HINT = "Right-click: menu" .. PLACE_DOT .. "Shift-click: link"

-- What each mark means, under the item's tooltip: the icon, without the gap it has after a
-- name, then the words.
local STAR_LINE = STAR_ICON .. " " .. BIS_CODE .. "Your BiS|r"
local RANK_LINE = BIS_CODE .. "#%d on your BiS list|r"
local UPGRADE_LINE = UPGRADE_ICON .. " " .. UPGRADE_CODE .. "An upgrade over what you wear|r"
local NEW_LOOK_LINE = NEW_LOOK_ICON .. " " .. LOOK_CODE .. "A look you do not have yet|r"

-- A weapon's short name: "1h Sword", "MH Sword", "Bow"; nil for one with none.
local function WeaponShort(subclass, equipLoc)
    local short = WEAPON_SHORT[subclass]
    if not short then return nil end
    local hand = ONE_HAND_ONLY[equipLoc] or short[2]
    local key = subclass .. (hand or "")
    local name = weaponNames[key]
    if not name then
        name = hand and hand .. " " .. short[1] or short[1]
        weaponNames[key] = name
    end
    return name
end

-- "Leather, Chest". Weapons in short ("1h Sword", "MH Dagger", "Bow"), else by the game's
-- type, plus the hand for one that only goes in one ("Fishing Poles, Main Hand"). Just the
-- slot for rings, cloaks and such. What is not worn by its kind: "Recipe, Tailoring" for a
-- recipe, else its subtype ("Potion").
local function ItemType(itemID)
    local _, itemType, subType, equipLoc, _, classID = GetItemInfoInstant(itemID)
    local slot = equipLoc and _G[equipLoc] or ""
    local facts = J.Items[itemID]
    if not (facts and subType) then return slot end
    local class = facts[FACT.CLASS]
    if class == WEAPON then
        return WeaponShort(facts[FACT.SUBCLASS], equipLoc)
            or (ONE_HAND_ONLY[equipLoc] and subType .. ", " .. slot or subType)
    end
    if class == ARMOR and ARMOR_TYPES[facts[FACT.SUBCLASS]] then return subType .. ", " .. slot end
    if slot ~= "" then return slot end
    if classID == RECIPE and itemType then return itemType .. ", " .. subType end
    return subType
end

-------------------------------------------------------------------------------
--  Hover and clicks
-------------------------------------------------------------------------------
-- Beside the cursor: anchoring to the row's edge put the tooltip far from the item you
-- point at.
-- "10% . 1 in 10": a chance and about how many kills it takes.
local function ChanceValue(chance)
    if chance >= 100 then return "100%" .. PLACE_DOT .. "every kill" end
    return ("%s%%%s1 in %d"):format(chance, PLACE_DOT, math.max(1, math.floor(100 / chance + 0.5)))
end

-- The drop chance in the tooltip, as its marks read: a loot bag and the words, in the colour
-- its bar has on the card (the accent from CHANCE_HIGH, the soft accent from CHANCE_FAIR,
-- muted below), then how often, muted. Made when shown, so it follows the theme.
local function ChanceLine(chance)
    if not chance then
        return Inline(BAG, T.muted) .. " " .. ns.Color("muted", "Drop chance not known yet")
    end
    local key = chance >= CHANCE_HIGH and "accent" or chance >= CHANCE_FAIR and "accentSoft" or "muted"
    local often = chance >= 100 and "every kill" or ("1 in %d"):format(math.max(1, math.floor(100 / chance + 0.5)))
    return Inline(BAG, T[key]) .. " " .. ns.Color(key, chance .. "% drop chance") .. ns.Color("muted", PLACE_DOT .. often)
end

-- Under the game's own lines: the drop chance as a label and its value, as the game sets
-- out "Legs ... Leather"; the item's marks, each saying what it means; and last, muted, what
-- a click does.
local function ItemEnter(row)
    row.hover:Show()
    local muted = T.muted
    GameTooltip:SetOwner(row, "ANCHOR_CURSOR_RIGHT", 16, 0)
    GameTooltip:SetItemByID(row.itemID)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(BrandLine(), 1, 1, 1)
    -- A reward your standing has not reached: which it needs, and how much reputation to go.
    if row.needs then
        local color = J.Style.STANDING_RGB[row.needs]
        GameTooltip:AddDoubleLine("Needs " .. Rep.Label(row.needs),
            row.toGo and Rep.ToGoText(row.toGo, row.exact) or "", color.r, color.g, color.b, 1, 1, 1)
    end
    if row.priced then
        if row.price then
            GameTooltip:AddDoubleLine("Price", GetCoinTextureString(row.price), muted.r, muted.g, muted.b, 1, 1, 1)
        else
            GameTooltip:AddDoubleLine("Price", "not known yet", muted.r, muted.g, muted.b, muted.r, muted.g, muted.b)
        end
    else
        GameTooltip:AddLine(ChanceLine(row.chance))
    end
    -- Where it is on your BiS list, unless the BiS List already says so on every tooltip.
    if row.rank and not ns.QoLSettings.Get("bisTooltip") then
        GameTooltip:AddLine(row.rank == 1 and STAR_LINE or RANK_LINE:format(row.rank))
    end
    if row.upgrade then GameTooltip:AddLine(UPGRADE_LINE) end
    if row.newLook then GameTooltip:AddLine(NEW_LOOK_LINE) end
    GameTooltip:AddLine(CLICK_HINT, muted.r, muted.g, muted.b)
    GameTooltip:Show()
end

local function ItemLeave(row)
    row.hover:Hide()
    GameTooltip:Hide()
end

-- Right-click opens its menu (the BiS List for gear, its Wowhead link); Shift-click links it
-- and Ctrl-click tries it on, as anywhere else in the game. The view redraws after a BiS
-- change.
local function ItemClick(row, button)
    if button == "RightButton" then
        View.ItemMenu(row, row.itemID, row:GetParent().redrawFn)
        return
    end
    local _, link = GetItemInfo(row.itemID)
    if link then HandleModifiedItemClick(link) end
end

-------------------------------------------------------------------------------
--  The row
-------------------------------------------------------------------------------
-- Its drop chance over its bar, the bar as bright as the odds; a muted dash where it is not
-- known, so the column stays whole. Nothing with Drop Chance off.
-- Hovering the chance says what it is: how often it drops, as "about 1 kill in N", from
-- the kills Wowhead has recorded, and what the bar shows. It only listens to the
-- mouse's movement, so a click still reaches the row (right-click, Shift-click).
local function PriceEnter(row)
    local muted = T.muted
    GameTooltip:SetText("Price", 1, 1, 1)
    if row.price then
        GameTooltip:AddLine(GetCoinTextureString(row.price) .. " at the quartermaster.", 1, 1, 1, true)
    else
        GameTooltip:AddLine("No gold price: it is a quest's reward, or costs something else.",
            muted.r, muted.g, muted.b, true)
    end
    GameTooltip:Show()
end

local function ChanceEnter(zone)
    local row = zone:GetParent()
    row.hover:Show()
    local muted = T.muted
    GameTooltip:SetOwner(zone, "ANCHOR_RIGHT")
    if row.priced then return PriceEnter(row) end
    GameTooltip:SetText("Drop chance", 1, 1, 1)
    local chance = row.chance
    if chance then
        GameTooltip:AddLine(ChanceValue(chance), 1, 1, 1)
        GameTooltip:AddLine("From the kills recorded so far. The bar fills, and turns a "
            .. "brighter blue, the likelier it is.", muted.r, muted.g, muted.b, true)
    else
        GameTooltip:AddLine("Not known yet: there is no count of how often it drops.",
            muted.r, muted.g, muted.b, true)
    end
    GameTooltip:Show()
end

local function ChanceLeave(zone)
    zone:GetParent().hover:Hide()
    GameTooltip:Hide()
end

-------------------------------------------------------------------------------
--  The drop chance: the number, its % muted, over a pill-shaped bar in the opacity slider's
--  look: a track with round ends, and a fill with round ends that brightens from a deeper
--  shade to its tier's colour (the accent from CHANCE_HIGH, the soft accent from CHANCE_FAIR,
--  muted below). The bar grows with the square root of the chance, so a rare drop still shows.
-------------------------------------------------------------------------------
local PERCENT = ns.Color("muted", "%")

local function Round(row, layer, color)
    local dot = row:CreateTexture(nil, layer)
    dot:SetTexture(ROUND, nil, nil, "TRILINEAR")
    dot:SetSize(BAR_H, BAR_H)
    dot:SetVertexColor(color.r, color.g, color.b, 1)
    return dot
end

-- Each tier's fill: its deep start and bright end, made once and filled from the theme on
-- every draw, so a theme preset is followed and nothing is made per item.
local tiers = {}

local function Tier(chance)
    local key = chance >= CHANCE_HIGH and "accent" or chance >= CHANCE_FAIR and "accentSoft" or "muted"
    local tier = tiers[key]
    if not tier then
        tier = { deep = CreateColor(0, 0, 0, 1), bright = CreateColor(0, 0, 0, 1) }
        tiers[key] = tier
    end
    local color = T[key]
    tier.color = color
    tier.deep:SetRGBA(color.r * DEEP, color.g * DEEP, color.b * DEEP, 1)
    tier.bright:SetRGBA(color.r, color.g, color.b, 1)
    return tier
end

local function SetChance(row, chance, shown)
    local known = chance ~= nil and chance > 0
    row.chance, row.priced, row.price = known and chance or nil, false, nil
    row.chanceText:ClearAllPoints()
    if known then
        row.chanceText:SetPoint("TOPRIGHT", 0, -CHANCE_TOP)
        row.chanceText:SetTextColor(T.fg.r, T.fg.g, T.fg.b)
        row.chanceText:SetText(shown and (chance < 1 and "<1" or chance) .. PERCENT or "")
        local tier = Tier(chance)
        row.chanceBar:SetGradient("HORIZONTAL", tier.deep, tier.bright)
        local deep, color = tier.deep, tier.color
        row.chanceStart:SetVertexColor(deep.r, deep.g, deep.b, 1)
        row.chanceEnd:SetVertexColor(color.r, color.g, color.b, 1)
        -- Between the round ends; at least a dot at the smallest chance.
        local fill = (CHANCE_BAR_W - BAR_H) * math.sqrt(math.min(chance, 100) / 100)
        row.chanceBar:SetWidth(math.max(0.1, fill))
    else
        row.chanceText:SetPoint("RIGHT", 0, 0)
        row.chanceText:SetTextColor(T.muted.r, T.muted.g, T.muted.b)
        row.chanceText:SetText(shown and "-" or "")
    end
    local bar = shown and known
    row.chanceTrack:SetShown(bar)
    row.chanceTrackStart:SetShown(bar)
    row.chanceTrackEnd:SetShown(bar)
    row.chanceBar:SetShown(bar)
    row.chanceStart:SetShown(bar)
    row.chanceEnd:SetShown(bar)
    row.chanceZone:SetShown(shown)
end

-- A faction reward's price where the chance goes, rounded (Rep.PriceText); a muted dash
-- where it is not known.
local function SetPrice(row, copper)
    row.chance, row.priced, row.price = nil, true, copper
    row.chanceText:ClearAllPoints()
    row.chanceText:SetPoint("RIGHT", 0, 0)
    if copper then
        row.chanceText:SetTextColor(T.fg.r, T.fg.g, T.fg.b)
        row.chanceText:SetText((Rep.PriceText(copper)))
    else
        row.chanceText:SetTextColor(T.muted.r, T.muted.g, T.muted.b)
        row.chanceText:SetText("-")
    end
    row.chanceTrack:Hide()
    row.chanceTrackStart:Hide()
    row.chanceTrackEnd:Hide()
    row.chanceBar:Hide()
    row.chanceStart:Hide()
    row.chanceEnd:Hide()
    row.chanceZone:Show()
end

Kinds.item = {
    New = function(view)
        local row = CreateFrame("Button", nil, view)
        row:SetHeight(ITEM_H)
        -- The hover reaches out to the card's edges.
        row.hover = ns.Solid(row, "BACKGROUND", T.fg, 0.05)
        row.hover:SetPoint("TOPLEFT", -CARD_PAD + 1, 0)
        row.hover:SetPoint("BOTTOMRIGHT", CARD_PAD - 1, 0)
        row.hover:Hide()
        -- A faint band when it is one of the striped rows of a list (view.striped).
        row.stripe = ns.Solid(row, "BACKGROUND", T.fg, St.STRIPE)
        row.stripe:SetPoint("TOPLEFT", -CARD_PAD + 1, 0)
        row.stripe:SetPoint("BOTTOMRIGHT", CARD_PAD - 1, 0)
        row.worn = ns.Solid(row, "ARTWORK", HAVE_RGB, 1)
        row.worn:SetPoint("TOPLEFT", -CARD_PAD + 2, -4)
        row.worn:SetPoint("BOTTOMLEFT", -CARD_PAD + 2, 4)
        row.worn:SetWidth(2)
        local frame = CreateFrame("Frame", nil, row)
        frame:SetSize(ICON, ICON)
        frame:SetPoint("LEFT", 0, 0)
        ns.Border(frame, BORDER_RGB)
        row.icon = frame:CreateTexture(nil, "ARTWORK")
        ns.PixelInset(row.icon, 1)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.chanceText = ns.Font(row, 11, nil, T.fg)
        row.chanceText:SetJustifyH("RIGHT")
        local zone = CreateFrame("Frame", nil, row)
        zone:SetPoint("TOPRIGHT")
        zone:SetPoint("BOTTOMRIGHT")
        zone:SetWidth(CHANCE_W)
        zone:SetMouseMotionEnabled(true)
        zone:SetMouseClickEnabled(false)
        zone:SetScript("OnEnter", ChanceEnter)
        zone:SetScript("OnLeave", ChanceLeave)
        row.chanceZone = zone
        -- The track between its two round ends, the fill between its own.
        row.chanceTrack = ns.Solid(row, "BORDER", T.line, 1)
        row.chanceTrack:SetPoint("BOTTOMRIGHT", -BAR_H / 2, BAR_BOTTOM)
        row.chanceTrack:SetSize(CHANCE_BAR_W - BAR_H, BAR_H)
        row.chanceTrackStart = Round(row, "BORDER", T.line)
        row.chanceTrackStart:SetPoint("CENTER", row.chanceTrack, "LEFT")
        row.chanceTrackEnd = Round(row, "BORDER", T.line)
        row.chanceTrackEnd:SetPoint("CENTER", row.chanceTrack, "RIGHT")
        row.chanceBar = row:CreateTexture(nil, "ARTWORK")
        row.chanceBar:SetColorTexture(1, 1, 1, 1)
        row.chanceBar:SetPoint("LEFT", row.chanceTrack)
        row.chanceBar:SetHeight(BAR_H)
        row.chanceStart = Round(row, "ARTWORK", T.muted)
        row.chanceStart:SetPoint("CENTER", row.chanceBar, "LEFT")
        row.chanceEnd = Round(row, "ARTWORK", T.muted)
        row.chanceEnd:SetPoint("CENTER", row.chanceBar, "RIGHT")
        row.name = ns.Font(row, 12)
        row.name:SetPoint("TOPLEFT", frame, "TOPRIGHT", 8, -NAME_TOP)
        row.name:SetPoint("RIGHT", -(CHANCE_W + 8), 0)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        -- The second line in two parts: what it is, cut short when the line is too long, then
        -- its level and where you keep it, always whole.
        row.meta = ns.Font(row, 11, nil, T.muted)
        row.meta:SetPoint("BOTTOMLEFT", frame, "BOTTOMRIGHT", 8, NAME_TOP)
        row.meta:SetJustifyH("LEFT")
        row.meta:SetWordWrap(false)
        row.metaTail = ns.Font(row, 11, nil, T.muted)
        row.metaTail:SetPoint("LEFT", row.meta, "RIGHT", 0, 0)
        row.metaTail:SetJustifyH("LEFT")
        row.metaTail:SetWordWrap(false)
        row:SetScript("OnEnter", ItemEnter)
        row:SetScript("OnLeave", ItemLeave)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:SetScript("OnClick", ItemClick)
        return row
    end,
    -- Returns its height, and true when the item's name is not loaded yet (it is then in
    -- view.waitingFor, which the view's GET_ITEM_INFO_RECEIVED checks).
    ---@param itemID number
    ---@param chance? number percent, 0 or nil where not known
    ---@param rank? number its pick number on your BiS list
    ---@param upgrade boolean it beats what you wear
    ---@param price? number copper, with view.column "price" (a faction's reward)
    Set = function(row, itemID, chance, rank, upgrade, price)
        local view = row:GetParent()
        row.itemID = itemID
        row.needs, row.toGo, row.exact = nil, nil, nil   -- a faction's card sets them after
        row.hover:Hide()
        row.stripe:SetShown(view.striped)
        row.icon:SetTexture(GetItemIconByID(itemID))
        local name, _, quality = GetItemInfo(itemID)
        -- Not loaded yet: GetItemInfo has asked the server, and the view draws again when
        -- GET_ITEM_INFO_RECEIVED names this item.
        if not name then view.waitingFor[itemID] = true end
        local facts = J.Items[itemID]
        quality = quality or (facts and facts[FACT.QUALITY]) or 1
        local _, _, _, hex = GetItemQualityColor(quality)
        -- Bare (a boss's history): what the item is, and nothing about you.
        local bare = view.bare
        local worn = not bare and IsEquippedItem(itemID)
        row.worn:SetShown(worn)
        local look
        if view.filters.showAppearance and not (worn or bare) then look = Loot.Appearance(itemID) end
        local known = not bare and Loot.Recipe(itemID) ~= nil and view:RecipeKnown(itemID)
        row.rank, row.upgrade, row.newLook = rank, upgrade, look == false
        row.name:SetText("|c" .. hex .. (name or ("Item " .. itemID)) .. "|r"
            .. RankTag(rank) .. (upgrade and UPGRADE_TAG or ""))
        local required = not bare and facts and facts[FACT.REQUIRED] or 0
        local level = required > 0 and ((required > view.playerLevel and RED_CODE or "") .. "Level " .. required
            .. "|r") or ""
        local kind = ItemType(itemID)
        row.metaTail:SetText(((kind ~= "" and level ~= "") and PLACE_DOT or "") .. level
            .. (known and KNOWN_TAG or not (worn or bare) and Kept(itemID) or "")
            .. (look == false and NEW_LOOK_TAG or ""))
        -- What it is gets what the rest of the line leaves.
        row.meta:SetWidth(0)   -- unbounded, so it measures the whole text
        row.meta:SetText(kind)
        local room = row:GetWidth() - ICON - 8 - (CHANCE_W + 8) - math.ceil(row.metaTail:GetStringWidth())
        row.meta:SetWidth(math.max(1, math.min(math.ceil(row.meta:GetStringWidth()) + 1, room)))
        -- The right column: the drop chance, a faction reward's price, or nothing (a rank's
        -- reward), as the view's column says.
        local column = view.column
        if column == "price" then
            SetPrice(row, price)
        else
            SetChance(row, chance, column == nil and view.showChance)
        end
        -- Kept lit when its boss is clicked: its BiS and upgrades; the rest fade.
        row.keep = rank ~= nil or upgrade
        row.rest = (bare or Loot.Usable(itemID)) and 1 or UNUSABLE
        row:SetAlpha(row.rest)
        return ITEM_H, name == nil
    end,
}
