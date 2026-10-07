-------------------------------------------------------------------------------
--  Window.lua -- Group Inspect's window (/nf group, /nfgroup, its Top Bar and minimap launcher,
--  its key binding, Open on its settings page, and Group Inspect on a party or raid member's
--  right-click menu, added through Menu.ModifyMenu only while it is on), built from the shared
--  window parts the first time it opens: your party as a big card each (Party.lua), your raid
--  as compact rows (Raid.lua), or a friendly note while you are solo. Showing it starts the scan
--  (GI.Open), hiding it stops it (GI.Close); each change of a member repaints only that member
--  (GI.OnChange). Also the pieces the party cards, the raid rows and the settings preview share
--  (GI.UI): the look, a gear slot with its tooltip, the class icon, the NF pill, a supporter's
--  badge, a name fitted to its room, and texts made once each.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local T = ns.THEME
local S = ns.QoLSettings
local GI = ns.GroupInspect
local Shared = ns.Shared
local Parts, Items = Shared.Parts, Shared.Items

local GetItemIconByID = C_Item.GetItemIconByID

local UI = {}
GI.UI = UI

local St = setmetatable({
    WINDOW_W = 1100,
    WINDOW_H = 612,
    TOOLBAR_GAP = 12,
    PARTY_W = 203,
    PARTY_WIDE_W = 256,
    PARTY_GAP = 10,
    PARTY_MAX = 5,
    PARTY_PAD = 10,
    BAND_H = 3,
    CLASS_ICON = 32,
    ROW_CLASS_ICON = 20,
    NAME_SIZE = 15,
    NAME_MIN = 11,
    ROW_NAME_SIZE = 13,
    ROW_NAME_MIN = 10,
    SUB_SIZE = 11,
    KICKER_SIZE = 10,
    LINE_SIZE = 12,
    LINE_H = 16,
    SECTION_GAP = 12,
    KICKER_GAP = 6,
    PILL_SIZE = 9,
    BADGE = 14,
    BADGE_GAP = 4,
    ROLE_ICON = 16,
    ROW_ROLE_ICON = 14,
    SLOT = 27,
    SLOT_GAP = 4,
    WIDE_SLOT = 33,
    WIDE_SLOT_GAP = 5,
    STRIP_WEAPON_GAP = 8,
    STRIP_SLOT = 20,
    STRIP_GAP = 3,
    EMPTY_ALPHA = 0.45,
    AWAY_ALPHA = 0.55,
    ROW_H = 32,
    COLUMNS_H = 20,
    CLASS_ICONS = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes",
    CLASS_CROP = 0.02,
    ROLE_ATLAS = { TANK = "UI-LFG-RoleIcon-Tank-Micro-GroupFinder", HEALER = "UI-LFG-RoleIcon-Healer-Micro-GroupFinder",
        DAMAGER = "UI-LFG-RoleIcon-DPS-Micro-GroupFinder" },
}, { __index = Shared.Style })
UI.Style = St

local BORDER_RGB, WARN_RGB = St.BORDER_RGB, St.WARN_RGB
local HEADER, PAD, FOOTER, INSET = St.WINDOW_HEADER, St.WINDOW_PAD, St.WINDOW_FOOTER, St.CONTENT_INSET
local SCROLLBAR, TAB_H, BAR_GAP = St.SCROLLBAR, St.TAB_H, St.BAR_GAP

UI.PAGE = "Group Inspect/Settings"
UI.WAITING = "..."
UI.CONTENT_W = St.WINDOW_W - 2 * INSET
UI.LIST_W = UI.CONTENT_W - SCROLLBAR - 4
UI.TOOLBAR_TOP = HEADER + PAD + 4
UI.CONTENT_TOP = UI.TOOLBAR_TOP + TAB_H + St.TOOLBAR_GAP
UI.CONTENT_H = St.WINDOW_H - UI.CONTENT_TOP - FOOTER - PAD

UI.CLASS_NAMES = { WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue",
    PRIEST = "Priest", SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid" }
UI.CLASS_ORDER = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
UI.ARMOR = { MAGE = "Cloth", PRIEST = "Cloth", WARLOCK = "Cloth", ROGUE = "Leather", DRUID = "Leather",
    HUNTER = "Mail", SHAMAN = "Mail", WARRIOR = "Plate", PALADIN = "Plate" }
UI.ROLE_WORDS = { TANK = "Tank", HEALER = "Healer", DAMAGER = "Damage" }
UI.STATS = {
    { key = "STR", name = "Strength", short = "STR" }, { key = "AGI", name = "Agility", short = "AGI" },
    { key = "STA", name = "Stamina", short = "STA" }, { key = "INT", name = "Intellect", short = "INT" },
    { key = "SPI", name = "Spirit", short = "SPI" }, { key = "AP", name = "Attack Power", card = "Atk Power", short = "AP" },
    { key = "SP", name = "Spell Power", short = "SP" }, { key = "CRIT", name = "Crit", short = "Crit", percent = true },
    { key = "HIT", name = "Hit", short = "Hit", percent = true }, { key = "ARMOR", name = "Armor", short = "Armor" },
}
local STATE_WORDS = { queued = "Queued", inspecting = "Inspecting...", out_of_range = "Out of range",
    offline = "Offline", self = "You" }
local AWAY = { out_of_range = true, offline = true }

local KEPT = 600
local scoreTexts, scoreKept = {}, 0
local levelTexts, talentTexts, statTexts, inlineTexts, keptTexts = {}, {}, {}, {}, 0
for _, stat in ipairs(UI.STATS) do
    statTexts[stat.key], inlineTexts[stat.key] = {}, {}
end
local PERCENT, LEVEL = "%.1f%%", "Level %d %s"
local TREES, POINTS = "%d/%d/%d", "%d points"

local function Keep()
    if keptTexts < KEPT then
        keptTexts = keptTexts + 1
        return
    end
    keptTexts = 1
    wipe(levelTexts)
    wipe(talentTexts)
    for _, stat in ipairs(UI.STATS) do
        wipe(statTexts[stat.key])
        wipe(inlineTexts[stat.key])
    end
end

function UI.ScoreText(score, level)
    if not score then return UI.WAITING end
    local key = math.floor(score * 10 + 0.5) * 256 + (level or 0)
    local text = scoreTexts[key]
    if not text then
        if scoreKept >= KEPT then
            wipe(scoreTexts)
            scoreKept = 0
        end
        text = ns.NaowhScore.Colored(score, level)
        scoreTexts[key] = text
        scoreKept = scoreKept + 1
    end
    return text
end

function UI.ForgetScores()
    wipe(scoreTexts)
    scoreKept = 0
end

function UI.LevelText(level, classFile)
    local class = classFile or ""
    local byLevel = levelTexts[class]
    if not byLevel then
        byLevel = {}
        levelTexts[class] = byLevel
    end
    local key = level or 0
    local text = byLevel[key]
    if not text then
        Keep()
        local name = UI.CLASS_NAMES[class] or ""
        text = level and LEVEL:format(level, name) or name
        byLevel[key] = text
    end
    return text
end

function UI.TalentText(spent)
    if type(spent) ~= "table" then return "" end
    local a, b, c = spent[1] or 0, spent[2] or 0, spent[3] or 0
    local key = #spent == 3 and (a * 4096 + b * 64 + c) or -(a + b + c)
    local text = talentTexts[key]
    if not text then
        Keep()
        text = #spent == 3 and TREES:format(a, b, c) or POINTS:format(a + b + c)
        talentTexts[key] = text
    end
    return text
end

function UI.StatValue(stat, value)
    local byValue = statTexts[stat.key]
    local text = byValue[value]
    if not text then
        Keep()
        text = stat.percent and PERCENT:format(value) or tostring(math.floor(value + 0.5))
        byValue[value] = text
    end
    return text
end

function UI.StatInline(stat, value)
    local byValue = inlineTexts[stat.key]
    local text = byValue[value]
    if not text then
        Keep()
        text = ns.Color("muted", stat.short) .. " " .. UI.StatValue(stat, value)
        byValue[value] = text
    end
    return text
end

function UI.StateText(state)
    return STATE_WORDS[state] or ""
end

function UI.Away(rec)
    return AWAY[rec.state] == true
end

function UI.ClassColor(classFile)
    local color = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    return color or T.fg
end

function UI.MissingEnchants(rec)
    local gear = rec.gear
    if not gear then return 0 end
    local n = 0
    for _, entry in pairs(gear) do
        if entry.enchanted == false then n = n + 1 end
    end
    return n
end

local enchantTexts = {}
local ENCHANTED = " " .. ns.Color("muted", "enchanted")
local HAVE_CODE = ("|cff%02x%02x%02x"):format(St.HAVE_RGB.r * 255, St.HAVE_RGB.g * 255, St.HAVE_RGB.b * 255)

function UI.EnchantText(rec)
    local gear = rec.gear
    if not gear then return UI.WAITING end
    local have, total = 0, 0
    for _, entry in pairs(gear) do
        if entry.enchanted ~= nil then
            total = total + 1
            if entry.enchanted then have = have + 1 end
        end
    end
    if total == 0 then return "" end
    local key = have * 64 + total
    local text = enchantTexts[key]
    if not text then
        text = (have < total and St.WARN_CODE or HAVE_CODE) .. Parts.Fraction(have, total) .. "|r" .. ENCHANTED
        enchantTexts[key] = text
    end
    return text
end

local FROM_NF, FROM_GEAR, YOURS = "From their Naowh Forever", "From gear", "Yours"

function UI.StatsFrom(rec)
    if not rec.stats then return "", T.muted end
    if rec.state == "self" then return YOURS, T.accentSoft end
    if rec.statsShared then return FROM_NF, T.accentSoft end
    return FROM_GEAR, T.muted
end

function UI.FitName(fs, text, maxW, size, minSize)
    local path = ns.UIFontPath()
    fs:SetWidth(maxW)
    if fs.fitSize ~= size then
        fs.fitSize = size
        fs:SetFont(path, size, "")
    end
    fs:SetText(text)
    local width = fs:GetUnboundedStringWidth()
    while width > maxW and size > minSize do
        size = size - 1
        fs.fitSize = size
        fs:SetFont(path, size, "")
        width = fs:GetUnboundedStringWidth()
    end
    return math.min(width, maxW)
end

function UI.ClassIcon(parent, size)
    local icon = Parts.ItemIcon(parent, size)
    icon.texture:SetTexture(St.CLASS_ICONS)
    return icon
end

function UI.PaintClass(icon, classFile)
    local coords = classFile and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile]
    icon.texture:SetShown(coords ~= nil)
    if not coords then return end
    local crop = St.CLASS_CROP
    icon.texture:SetTexCoord(coords[1] + crop, coords[2] - crop, coords[3] + crop, coords[4] - crop)
end

function UI.RoleIcon(parent, size)
    local icon = parent:CreateTexture(nil, "ARTWORK")
    icon:SetSize(size, size)
    icon:Hide()
    return icon
end

function UI.PaintRole(icon, role)
    local atlas = role and St.ROLE_ATLAS[role]
    icon:SetShown(atlas ~= nil)
    if atlas then icon:SetAtlas(atlas) end
    return atlas ~= nil
end

function UI.Kicker(parent, text)
    local kicker = ns.Font(parent, St.KICKER_SIZE, nil, T.accentSoft)
    kicker:SetText(text)
    return kicker
end

local RUNS_NF, VERSION, VERSION_MAX = "Runs Naowh Forever", "Version %s", 24
local OLDER = "Older than yours (%s): ask them to update."
local parts = {}

-- A version's numbers, compared part by part: "0.5.22-beta" is older than "0.5.24-beta".
local function Older(theirs, mine)
    if type(theirs) ~= "string" or type(mine) ~= "string" then return false end
    wipe(parts)
    for n in mine:gmatch("%d+") do parts[#parts + 1] = tonumber(n) end
    local i = 0
    for n in theirs:gmatch("%d+") do
        i = i + 1
        local a, b = tonumber(n), parts[i]
        if b == nil then return false end
        if a ~= b then return a < b end
    end
    return i < #parts
end
UI.Older = Older

function UI.PaintNFPill(pill, rec)
    local old = rec and rec.hasNF == true and Older(rec.nfVersion, ns.CODE_BUILD)
    Parts.ColorPill(pill, old and St.WARN_RGB or T.accent)
end

local function PillEnter(pill)
    if GameTooltip:IsForbidden() or not Parts.Tip(pill, "ANCHOR_TOP") then return end
    local guid = pill.holder.guid
    local rec = guid and GI.Member(guid)
    GameTooltip:SetText(RUNS_NF, 1, 1, 1)
    local version = rec and ns.PlainText(rec.nfVersion, VERSION_MAX)
    if version and version ~= "" then
        GameTooltip:AddLine(VERSION:format(version), T.muted.r, T.muted.g, T.muted.b)
        if Older(rec.nfVersion, ns.CODE_BUILD) then
            local w = St.WARN_RGB
            GameTooltip:AddLine(OLDER:format(ns.PlainText(ns.CODE_BUILD, VERSION_MAX)), w.r, w.g, w.b, true)
        end
    end
    GameTooltip:Show()
end

function UI.NFPill(parent, holder)
    local pill = Parts.Pill(parent, St.PILL_SIZE, T.accent)
    pill.color = T.accent
    Parts.SetPill(pill, "NF")
    pill.holder = holder
    pill:EnableMouse(true)
    pill:SetScript("OnEnter", PillEnter)
    pill:SetScript("OnLeave", GameTooltip_Hide)
    pill:Hide()
    return pill
end

local function BadgesOn()
    if ns.FEATURE_BADGES == 1 then return S.Get("badgeChat") == true end
    return S.Default("badgeChat") == true
end

function UI.BadgeOf(guid)
    if not (guid and ns.BadgeOf and BadgesOn()) then return nil end
    return ns.BadgeOf(guid)
end

local function BadgeEnter(badge)
    if GameTooltip:IsForbidden() then return end
    local tier = UI.BadgeOf(badge.holder.guid)
    if not (tier and Parts.Tip(badge, "ANCHOR_TOP")) then return end
    GameTooltip:SetText(tier.tooltipLine or tier.title or "", 1, 1, 1)
    if tier.about then GameTooltip:AddLine(tier.about, T.muted.r, T.muted.g, T.muted.b) end
    GameTooltip:Show()
end

function UI.Badge(parent, holder)
    local badge = CreateFrame("Frame", nil, parent)
    badge:SetSize(St.BADGE, St.BADGE)
    badge.icon = Parts.Smooth(badge:CreateTexture(nil, "ARTWORK"))
    badge.icon:SetAllPoints()
    badge.holder = holder
    badge:EnableMouse(true)
    badge:SetScript("OnEnter", BadgeEnter)
    badge:SetScript("OnLeave", GameTooltip_Hide)
    badge:Hide()
    return badge
end

function UI.PaintBadge(badge, guid)
    local tier = UI.BadgeOf(guid)
    local texture = tier and tier.chat
    badge:SetShown(texture ~= nil)
    if texture then badge.icon:SetTexture(texture) end
    return texture ~= nil
end

local function NameEnter(hit)
    if GameTooltip:IsForbidden() then return end
    local guid = hit.holder.guid
    local rec = guid and GI.Member(guid)
    if not (rec and Parts.Tip(hit, "ANCHOR_TOP")) then return end
    local color = UI.ClassColor(rec.classFile)
    GameTooltip:SetText(rec.name or UI.WAITING, color.r, color.g, color.b)
    GameTooltip:AddLine(UI.LevelText(rec.level, rec.classFile), T.muted.r, T.muted.g, T.muted.b)
    GameTooltip:Show()
end

function UI.NameHit(parent, holder)
    local hit = CreateFrame("Frame", nil, parent)
    hit.holder = holder
    hit:EnableMouse(true)
    hit:SetScript("OnEnter", NameEnter)
    hit:SetScript("OnLeave", GameTooltip_Hide)
    return hit
end

local NO_ENCHANT, EMPTY, NOT_READ = "No enchant", "Empty", "Not inspected yet"
local BARE = { color = WARN_RGB, tip = NO_ENCHANT }
local theirBis

local function TheirBis()
    theirBis = theirBis or Parts.RankMark(1) .. " " .. St.BIS_CODE .. "Their BiS|r"
    return theirBis
end

local function GearEnter(icon)
    if GameTooltip:IsForbidden() then return end
    local guid = icon.holder.guid
    local rec = guid and GI.Member(guid)
    local entry = rec and rec.gear and rec.gear[icon.slot]
    if not Parts.Tip(icon, "ANCHOR_RIGHT") then return end
    if entry and entry.link then
        GameTooltip:SetHyperlink(entry.link)
        if entry.bis then GameTooltip:AddLine(TheirBis()) end
        if entry.enchanted == false then GameTooltip:AddLine(NO_ENCHANT, WARN_RGB.r, WARN_RGB.g, WARN_RGB.b) end
    else
        GameTooltip:SetText(Items.SLOT_NAME[icon.slot] or "", 1, 1, 1)
        GameTooltip:AddLine(rec and rec.gear and EMPTY or NOT_READ, T.muted.r, T.muted.g, T.muted.b)
    end
    GameTooltip:Show()
end

function UI.GearIcon(parent, size, slot, holder, marks)
    local icon = Parts.ItemIcon(parent, size)
    icon.slot, icon.holder = slot, holder
    if marks then icon.marks = Parts.ItemMarks(icon, size) end
    icon.bare = ns.BiS.View.EnchantBadge(icon, BARE)
    icon.bare:EnableMouse(false)
    icon:EnableMouse(true)
    icon:SetScript("OnEnter", GearEnter)
    icon:SetScript("OnLeave", GameTooltip_Hide)
    return icon
end

local emptyArt = {}

local function EmptyArt(slot)
    local art = emptyArt[slot]
    if art == nil then
        local info = C_PaperDollInfo and C_PaperDollInfo.GetInventorySlotInfoForInvSlot
        art = info and select(2, info(slot)) or false
        emptyArt[slot] = art
    end
    return art or nil
end

function UI.PaintGear(icon, entry)
    local texture = icon.texture
    local id = entry and entry.id
    if id then
        texture:SetTexture(GetItemIconByID(id))
        texture:SetAlpha(1)
        local quality = entry.quality and ITEM_QUALITY_COLORS[entry.quality]
        local edge = quality or BORDER_RGB
        icon.edge:SetColor(edge.r, edge.g, edge.b, 1)
        icon.bare:SetShown(entry.enchanted == false)
    else
        texture:SetTexture(EmptyArt(icon.slot))
        texture:SetAlpha(St.EMPTY_ALPHA)
        icon.edge:SetColor(BORDER_RGB.r, BORDER_RGB.g, BORDER_RGB.b, 1)
        icon.bare:Hide()
    end
    if icon.marks then
        Parts.PaintItemMarks(icon.marks, id and entry.ilvl, id and entry.bis and 1 or nil,
            id ~= nil and Parts.IsForever("items", id))
    end
end

local tally = { total = 0, done = 0, waiting = 0, out = 0, offline = 0, nf = 0 }

function UI.Tally()
    local members = GI.Members()
    local done, waiting, out, offline, nf = 0, 0, 0, 0, 0
    for i = 1, #members do
        local state = members[i].state
        if state == "ready" or state == "self" then
            done = done + 1
        elseif state == "out_of_range" then
            out = out + 1
        elseif state == "offline" then
            offline = offline + 1
        else
            waiting = waiting + 1
        end
        if members[i].hasNF then nf = nf + 1 end
    end
    tally.total, tally.done, tally.waiting, tally.out, tally.offline, tally.nf = #members, done, waiting, out, offline, nf
    return tally
end

local MODE_WORDS = { party = "Party of %d", raid = "Raid of %d" }
local EVERYONE, INSPECTED = "Everyone inspected", "Inspected %d of %d"
local OUT_N, OFFLINE_N = ", %d out of range", ", %d offline"
local NF_COUNT = "%d of %d run Naowh Forever"

function UI.ProgressText(t)
    if t.total == 0 then return "" end
    local text = (t.waiting + t.out + t.offline == 0) and EVERYONE or INSPECTED:format(t.done, t.total)
    if t.out > 0 then text = text .. OUT_N:format(t.out) end
    if t.offline > 0 then text = text .. OFFLINE_N:format(t.offline) end
    return text
end

local window, board, list, raidBar
local SOLO_TITLE = "You are not in a group"
local SOLO_LINE = "Join a party or raid to see everyone's Naowh Score, gear, talents and stats."
local SOLO_LINK = "See a preview on its settings page"
local SOLO_GAP, SOLO_LIFT = 8, 30
local TURNED_ON = "Group Inspect turned on. Turn it off on its settings page."
local QOL_OFF = "Group Inspect needs the QoL module on."

local function Opacity()
    return math.floor((S.Get("groupInspectAlpha") or 1) * 100 + 0.5)
end

local function SetOpacity(value)
    S.Set("groupInspectAlpha", value / 100)
end

local function PaintBackdrop()
    window.backdrop:Paint(Opacity() / 100)
    window.opacity._refreshValue()
end

local function PaintTop()
    local t = UI.Tally()
    local mode = window.mode
    local words = MODE_WORDS[mode]
    window.summary:SetText(words and words:format(t.total) or "")
    window.progress:SetText(words and UI.ProgressText(t) or "")
    local note = window.note
    note.text:SetText(words and NF_COUNT:format(t.nf, t.total) or "")
    note:SetWidth(math.max(1, math.ceil(note.text:GetStringWidth())))
end

local function ShowMode(mode)
    window.mode = mode
    board:SetShown(mode == "party")
    list.header:SetShown(mode == "raid")
    window.scroll:SetShown(mode == "raid")
    raidBar:SetShown(mode == "raid")
    window.solo:SetShown(mode ~= "party" and mode ~= "raid")
end

local function PaintAll()
    local mode = GI.Mode()
    ShowMode(mode)
    if mode == "party" then
        board:Paint()
    elseif mode == "raid" then
        list:Draw()
    end
    PaintTop()
end
UI.PaintWindow = function()
    if window and window:IsShown() then PaintAll() end
end

local function WindowChanged(guid)
    if guid == nil or window.mode ~= GI.Mode() then
        PaintAll()
        return
    end
    if window.mode == "party" then
        if not board:PaintGuid(guid) then board:Paint() end
    elseif window.mode == "raid" then
        list:PaintGuid(guid)
    end
    PaintTop()
end

local function Changed(guid)
    if window and window:IsShown() then WindowChanged(guid) end
    local preview = UI.preview
    if preview and preview:IsVisible() then preview:Repaint(guid) end
end

local listening = false

function UI.Listen()
    if listening then return end
    listening = true
    GI.OnChange(Changed)
end

local function Shown()
    GI.Open()
end

local function Hidden()
    GI.Close()
end

local function OpenPage()
    ns.OpenOptionsWindow(UI.PAGE)
end

local function RefreshAll()
    GI.RefreshAll()
end

local function Solo(parent)
    local solo = CreateFrame("Frame", nil, parent)
    solo:SetPoint("TOPLEFT", INSET, -UI.CONTENT_TOP)
    solo:SetSize(UI.CONTENT_W, UI.CONTENT_H)
    local title = ns.Font(solo, St.CARD_NAME_SIZE + 1, nil, T.fg)
    title:SetPoint("CENTER", 0, SOLO_LIFT)
    title:SetText(SOLO_TITLE)
    local line = ns.Font(solo, St.LINE_SIZE, nil, T.muted)
    line:SetPoint("TOP", title, "BOTTOM", 0, -SOLO_GAP)
    line:SetText(SOLO_LINE)
    local link = Parts.Link(solo, OpenPage, true)
    Parts.SetLink(link, SOLO_LINK)
    link:SetPoint("TOP", line, "BOTTOM", 0, -SOLO_GAP)
    return solo
end

local function Build()
    local W, H = St.WINDOW_W, St.WINDOW_H
    window = Parts.Window(W, H, "groupInspectWindow")
    window.backdrop:Card(6, HEADER + 6, 6, FOOTER + 6)
    local close = Parts.TitleBar(window, "Group Inspect", "Your group's Naowh Score, gear, talents and stats.",
        UI.PAGE)
    local opacityIcon
    opacityIcon, window.opacity = Parts.Opacity(window, close, Opacity, SetOpacity)
    local refresh = Parts.BarButton(window, St.RESET, "Inspect everyone again",
        "Reads every member's gear and talents again.", RefreshAll, "Refresh")
    refresh:SetPoint("RIGHT", opacityIcon, "LEFT", -BAR_GAP * 2, 0)
    Parts.FooterBrand(window, UI.PAGE)
    window.note = Parts.FooterNote(window, "")

    window.summary = ns.Font(window, St.CARD_NAME_SIZE - 2, nil, T.fg)
    window.summary:SetPoint("LEFT", window, "TOPLEFT", INSET, -(UI.TOOLBAR_TOP + TAB_H / 2))
    window.progress = ns.Font(window, St.LINE_SIZE, nil, T.muted)
    window.progress:SetPoint("LEFT", window.summary, "RIGHT", PAD, 0)
    raidBar = UI.RaidBar(window)
    raidBar:SetPoint("TOPRIGHT", -INSET, -UI.TOOLBAR_TOP)

    board = UI.PartyBoard(window)
    board:SetPoint("TOPLEFT", INSET, -UI.CONTENT_TOP)

    local scroll = ns.UI.SlimScroll(window)
    scroll:SetPoint("TOPLEFT", INSET, -(UI.CONTENT_TOP + St.COLUMNS_H))
    scroll:SetPoint("BOTTOMRIGHT", -SCROLLBAR - 4, FOOTER + PAD)
    window.scroll = scroll
    list = UI.RaidList(window, scroll)
    list.header:SetPoint("TOPLEFT", INSET, -UI.CONTENT_TOP)
    scroll:SetScrollChild(list.view)

    window.solo = Solo(window)
    window.board, window.list = board, list
    window:HookScript("OnShow", Shown)
    window:HookScript("OnHide", Hidden)
    UI.Listen()
end

function ns.OpenGroupInspect()
    if not GI.On() then
        S.Set("groupInspect", true)
        if not GI.On() then
            ns.Print(QOL_OFF)
            return
        end
        ns.Print(TURNED_ON)
    end
    if not window then Build() end
    window:SetScale(ns.UIScale())
    window:Show()
    PaintBackdrop()
    PaintAll()
end

function ns.ToggleGroupInspect()
    if window and window:IsShown() then window:Hide() else ns.OpenGroupInspect() end
end

function NaowhForever_ToggleGroupInspect()
    ns.ToggleGroupInspect()
end

UI.Window = function() return window end

local MENU_TAGS = { "MENU_UNIT_PARTY", "MENU_UNIT_RAID_PLAYER", "MENU_UNIT_RAID" }
local MENU_TEXT = "Group Inspect"
local menuHandles

local function OpenFromMenu()
    ns.OpenGroupInspect()
end

local function AddToMenu(_, root)
    if not (GI.On() and IsInGroup()) then return end
    root:CreateDivider()
    root:CreateButton(MENU_TEXT, OpenFromMenu)
end

local function SyncMenu()
    local on = GI.On()
    if on and not menuHandles and Menu and Menu.ModifyMenu then
        menuHandles = {}
        for i, tag in ipairs(MENU_TAGS) do menuHandles[i] = Menu.ModifyMenu(tag, AddToMenu) end
    elseif not on and menuHandles then
        for _, handle in ipairs(menuHandles) do handle:Unregister() end
        menuHandles = nil
    end
end
UI.MENU_TAGS = MENU_TAGS

S.OnChange(function(key)
    if key == "naowhScoreCompare" then UI.ForgetScores() end
    if key == "enabled" or key == "groupInspect" then SyncMenu() end
    if not window then return end
    if (key == "enabled" or key == "groupInspect") and not GI.On() then
        window:Hide()
    elseif key == "groupInspectAlpha" then
        if window:IsShown() then PaintBackdrop() end
    elseif key == "groupInspectView" or key == "groupInspectSort" or key == "naowhScoreCompare" then
        if window:IsShown() then PaintAll() end
    end
end)

hooksecurefunc(ns, "Apply", function()
    SyncMenu()
    if window and window:IsShown() then
        PaintBackdrop()
        PaintAll()
    end
end)
