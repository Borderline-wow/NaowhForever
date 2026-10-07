-------------------------------------------------------------------------------
--  Alerts.lua -- your list where you meet items: its rank on an item's tooltip,
--  Alt+Shift-click to add an item or take it off, and Drop Alert, once per drop and again when
--  one is yours, as you set it: which picks, an on-screen alert (View/Toast.lua), a line in
--  chat, a sound for each, and your star on its roll frame. The loot events are listened to
--  only while the module and Drop Alert are on.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local T = ns.THEME
local B = ns.BiS
local S = B.Settings
local Shared = ns.Shared
local Items, Parts = Shared.Items, Shared.Parts
local RankMark = Parts.RankMark
local St = Shared.Style

local A = {}
B.Alerts = A

local function Tag() return ns.Color("accent", "Naowh BiS") end

local function Rank(link)
    if not link or issecretvalue(link) then return nil end
    return ns.IsBisItem(Items.IDFrom(link))
end

TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
    local id = data and data.id
    if not id or issecretvalue(id) or not S.Get("bisTooltip") then return end
    local rank = ns.IsBisItem(id)
    if rank then
        tooltip:AddLine(Parts.RankLine(rank, B.Lists.List().name))
    end
end)

hooksecurefunc("HandleModifiedItemClick", function(link)
    if not (IsAltKeyDown() and IsShiftKeyDown() and B.On()) then return end
    local id = Items.IDFrom(link)
    if not id then return end
    if ns.IsBisItem(id) then
        ns.RemoveBisItem(id)
        ns.Print("Removed " .. Items.Name(id) .. " from your BiS list.")
    else
        ns.AddBisItem(id)
    end
end)

-------------------------------------------------------------------------------
--  Drop Alert
-------------------------------------------------------------------------------
local function AlertOn()
    return B.On() and S.Get("bisLootAlert")
end

local RANK_WORDS = { "your BiS", "your second pick" }
local WHAT = { roll = "up for a roll", dropped = "dropped", yours = "is yours" }
-- The game's own sounds, beside the addon's list: the defaults.
A.GAME_SOUNDS = { ["game:raidwarning"] = SOUNDKIT.RAID_WARNING,
    ["game:epicloot"] = SOUNDKIT.UI_EPICLOOT_TOAST or SOUNDKIT.RAID_WARNING }
A.GAME_SOUND_NAMES = { ["game:raidwarning"] = "Raid Warning (game)", ["game:epicloot"] = "Epic Loot (game)" }
-- Which ranks Alert For keeps.
local ALERT_FOR = { bis = 1, top2 = 2, all = math.huge }

function A.Play(key)
    if not key or key == "none" then return end
    local kit = A.GAME_SOUNDS[key]
    if kit then
        PlaySound(kit, "Master")
    else
        ns.UI._PlayLSMSound(ns.UI.SoundPathFor(key))
    end
end

-- Whether a pick of this rank alerts, by Alert For.
local function Alerts(rank)
    return rank ~= nil and rank <= (ALERT_FOR[S.Get("bisAlertFor")] or math.huge)
end

-- As you set it: the on-screen alert, a line in chat ("Naowh BiS <star> [Serpent's Shoulders]
-- up for a roll: your BiS for Shoulder") and the event's sound.
local function Say(link, rank, event)
    if S.Get("bisToast") then B.Toast.Show(link, rank, event) end
    if S.Get("bisAlertChat") then
        local slot = B.Lists.SlotOf(Items.IDFrom(link))
        ns.Print(Tag() .. "  " .. RankMark(rank) .. "  " .. link .. ns.Color("muted", ("  %s: %s%s"):format(WHAT[event],
            RANK_WORDS[rank] or ("your #%d pick"):format(rank), slot and " for " .. ns.L(Items.SLOT_NAME[slot]) or "")))
    end
    A.Play(S.Get(event == "yours" and "bisYoursSound" or "bisDropSound"))
end

-- Once per drop: a roll by its ID, a loot window's item by the corpse and the item, and an
-- item said in the last few minutes not again (a boss's roll, then its loot window).
local SAME_DROP = 300   -- seconds
local FORGET = 3600     -- seconds before what was said is let go
local seen, said = {}, {}

local function Forget(now)
    for key, at in pairs(seen) do
        if now - at > FORGET then seen[key] = nil end
    end
    for id, at in pairs(said) do
        if now - at > FORGET then said[id] = nil end
    end
end

local function New(key, id)
    local now = GetTime()
    local old = seen[key] or (said[id] and now - said[id] < SAME_DROP)
    seen[key] = now
    if old then return false end
    Forget(now)
    said[id] = now
    return true
end

local function Dropped(link, event, key)
    local rank = Rank(link)
    if Alerts(rank) and New(key, Items.IDFrom(link)) then Say(link, rank, event) end
end

-- Looted, won or handed to you; not a second copy of what you wear.
local function Yours(link, id)
    local rank = id and ns.IsBisItem(id)
    if Alerts(rank) and not C_Item.IsEquippedItem(id) then Say(link, rank, "yours") end
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, arg)
    if event == "START_LOOT_ROLL" then
        return Dropped(GetLootRollItemLink(arg), "roll", "roll" .. arg)
    elseif event == "CHAT_MSG_LOOT" then
        return Yours(Items.YourLoot(arg, true))
    end
    for slot = 1, GetNumLootItems() do
        local link = GetLootSlotLink(slot)
        local corpse = GetLootSourceInfo(slot)
        if link and not issecretvalue(link) and corpse and not issecretvalue(corpse) then
            Dropped(link, "dropped", corpse .. link)
        end
    end
end)

local function Listen()
    events:UnregisterAllEvents()
    if not AlertOn() then return end
    events:RegisterEvent("LOOT_READY")
    events:RegisterEvent("START_LOOT_ROLL")
    if Items.READS_LOOT then events:RegisterEvent("CHAT_MSG_LOOT") end
end

S.OnChange(function(key)
    if key == "bis" or key == "bisLootAlert" then Listen() end
end)
hooksecurefunc(ns, "Apply", Listen)

-------------------------------------------------------------------------------
--  On a roll frame for one of your picks, a badge over its corner: the star and "Your BiS"
--  in its rank's colour. Ours, anchored to the game's frame, never kept on it. Forever's roll
--  frames are unverified, so a missing one just goes without.
-------------------------------------------------------------------------------
local BADGE_H, BADGE_STAR, BADGE_PAD = 20, 14, 6
local BADGE_WORDS = { "Your BiS", "Your second pick" }
local badges = {}

local function Badge(frame)
    local badge = badges[frame]
    if badge then return badge end
    badge = CreateFrame("Frame", nil, UIParent)
    badge:SetHeight(BADGE_H)
    badge:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 4, 2)
    ns.Solid(badge, "BACKGROUND", T.bg, 0.95):SetAllPoints()
    ns.Border(badge, St.BORDER_RGB)
    badge.star = badge:CreateTexture(nil, "ARTWORK")
    badge.star:SetTexture(St.STAR)
    badge.star:SetSize(BADGE_STAR, BADGE_STAR)
    badge.star:SetPoint("LEFT", BADGE_PAD, 0)
    badge.text = ns.Font(badge, 12)
    badges[frame] = badge
    return badge
end

-- The badge for rank over the frame, or none.
local function ShowBadge(frame, rank)
    if not rank then
        if badges[frame] then badges[frame]:Hide() end
        return
    end
    local badge = Badge(frame)
    local color, starred = Parts.RankColor(rank), rank <= 2
    badge:SetFrameStrata(frame:GetFrameStrata())
    badge:SetFrameLevel(frame:GetFrameLevel() + 10)
    badge.star:SetShown(starred)
    badge.star:SetVertexColor(color.r, color.g, color.b)
    badge.text:ClearAllPoints()
    if starred then
        badge.text:SetPoint("LEFT", badge.star, "RIGHT", 4, 0)
    else
        badge.text:SetPoint("LEFT", BADGE_PAD, 0)
    end
    badge.text:SetText(BADGE_WORDS[rank] or ("Your #%d pick"):format(rank))
    badge.text:SetTextColor(color.r, color.g, color.b)
    badge:SetWidth(math.ceil(badge.text:GetStringWidth()) + BADGE_PAD * 2 + (starred and BADGE_STAR + 4 or 0))
    badge:Show()
end

local function MarkRoll(frame)
    local rank = AlertOn() and S.Get("bisAlertBadge") and frame.rollID and Rank(GetLootRollItemLink(frame.rollID))
    ShowBadge(frame, Alerts(rank or nil) and rank or nil)
end

local function UnmarkRoll(frame)
    ShowBadge(frame, nil)
end

for i = 1, 4 do
    local frame = _G["GroupLootFrame" .. i]
    if frame then
        frame:HookScript("OnShow", MarkRoll)
        frame:HookScript("OnHide", UnmarkRoll)
    end
end

-------------------------------------------------------------------------------
--  Test: your first slot's BiS, as it would be met: up for a roll on a roll frame of our own
--  with its badge, then dropped, then yours, a few seconds apart.
-------------------------------------------------------------------------------
local TEST_STEP = 2.5   -- seconds between each
local TEST_W, TEST_H, TEST_ICON = 260, 44, 32
local preview, testLink, testRank

local function Preview()
    if preview then return preview end
    preview = CreateFrame("Frame", nil, UIParent)
    preview:SetSize(TEST_W, TEST_H)
    preview:SetPoint("TOP", 0, -180)
    preview:SetFrameStrata("DIALOG")
    ns.Solid(preview, "BACKGROUND", T.bg, 0.95):SetAllPoints()
    ns.Border(preview, St.BORDER_RGB)
    local icon = Parts.ItemIcon(preview, TEST_ICON)
    icon:SetPoint("LEFT", 6, 0)
    preview.icon = icon.texture
    preview.name = ns.Font(preview, 12)
    preview.name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, -2)
    preview.name:SetPoint("RIGHT", -8, 0)
    preview.name:SetJustifyH("LEFT")
    preview.name:SetWordWrap(false)
    local note = ns.Font(preview, 11, nil, T.muted)
    note:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 8, 2)
    note:SetText("Test roll")
    return preview
end

local function TestDropped() Say(testLink, testRank, "dropped") end

local function TestYours()
    Say(testLink, testRank, "yours")
    ShowBadge(preview, nil)
    preview:Hide()
end

-- false when your list has nothing to test with.
function A.Test()
    local list = B.Lists.List()
    local id
    for _, gear in ipairs(Items.GEAR_SLOTS) do
        id = id or list.slots[gear[1]]
    end
    if not id then return false end
    testRank = ns.IsBisItem(id) or 1
    testLink = select(2, C_Item.GetItemInfo(id)) or ("|cffffffff|Hitem:%d::|h[%s]|h|r"):format(id, Items.Name(id))
    local frame = Preview()
    frame.icon:SetTexture(C_Item.GetItemIconByID(id))
    frame.name:SetText(testLink)
    frame:Show()
    ShowBadge(frame, S.Get("bisAlertBadge") and testRank or nil)
    Say(testLink, testRank, "roll")
    C_Timer.After(TEST_STEP, TestDropped)
    C_Timer.After(TEST_STEP * 2, TestYours)
    return true
end
