-- Party.lua: Group Inspect's party of two to five, a big card each, centred side by side (GI.UI.PartyBoard).
local ns = _G.NaowhForever
local GI = ns.GroupInspect
local UI = GI.UI

local St = UI.Style
local GAP, MAX = St.PARTY_GAP, St.PARTY_MAX
local NARROW, WIDE = UI.PARTY_LAYOUTS.narrow, UI.PARTY_LAYOUTS.wide

local function Paint(board)
    local members = GI.Members()
    local n = math.min(#members, MAX)
    local l = n >= MAX and NARROW or WIDE
    board:SetHeight(l.h)
    local x = math.floor((UI.BOARD_W - (n * l.w + math.max(0, n - 1) * GAP)) / 2)
    for i = 1, MAX do
        local card = board.cards[i]
        if i <= n then
            if card.layout ~= l then UI.PlacePartyCard(card, l) end
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", x + (i - 1) * (l.w + GAP), 0)
            UI.PaintPartyCard(card, members[i])
            card:Show()
        else
            card.guid = nil
            card:Hide()
        end
    end
end

local function PaintGuid(board, guid)
    for i = 1, MAX do
        local card = board.cards[i]
        if card.guid == guid and card:IsShown() then
            local rec = GI.Member(guid)
            if not rec then return false end
            UI.PaintPartyCard(card, rec)
            return true
        end
    end
    return false
end

function UI.PartyBoard(parent)
    local board = CreateFrame("Frame", nil, parent)
    board:SetSize(UI.BOARD_W, NARROW.h)
    board.cards = {}
    for i = 1, MAX do
        board.cards[i] = UI.PartyCard(board)
        UI.PlacePartyCard(board.cards[i], NARROW)
    end
    board.Paint, board.PaintGuid = Paint, PaintGuid
    return board
end
