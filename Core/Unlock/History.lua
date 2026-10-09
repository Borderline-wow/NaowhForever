-- History.lua: the HUD Editor's Undo, Redo and Revert, and what may be moved by hand.
local ns = _G.NaowhForever
local UI = ns.UI
local H = ns.HudEditor

local placement = H.placement
local IsLocked, Follows, Anchors, CopyAnchor = H.IsLocked, H.Follows, H.Anchors, H.CopyAnchor
local Place, AtCenter = H.Place, H.AtCenter

local UNDO_MAX = 50

local undo, redo = {}, {}
local lastNudged

local function Moves(item)
    if IsLocked(item) then return false end
    for _, other in ipairs(placement.group) do
        if other ~= item and Follows(item.label, other.label) then return false end
    end
    return true
end

local function Snapshot()
    local snap = { spots = {}, anchors = {} }
    for _, item in ipairs(placement.items) do
        local point, rel, relPoint, x, y = item.frame:GetPoint(1)
        if point == "CENTER" and rel == UIParent and relPoint == "CENTER" then snap.spots[item.label] = { x, y } end
    end
    for label, info in pairs(Anchors()) do
        if type(info) == "table" then snap.anchors[label] = CopyAnchor(info) end
    end
    return snap
end

local function Checkpoint(snap, nudged)
    if nudged and nudged == lastNudged then return end
    lastNudged = nudged
    undo[#undo + 1] = snap or Snapshot()
    if #undo > UNDO_MAX then table.remove(undo, 1) end
    wipe(redo)
    H.PaintHistory()
end

local function Change(item, nudged)
    if IsLocked(item) then return false end
    Checkpoint(nil, nudged)
    return true
end

local function Restore(snap)
    local anchors = Anchors()
    wipe(anchors)
    for label, info in pairs(snap.anchors) do anchors[label] = CopyAnchor(info) end
    for _, item in ipairs(placement.items) do
        local spot = snap.spots[item.label]
        if spot and not AtCenter(item.frame, spot[1], spot[2]) then
            Place(item, spot[1], spot[2])
            item.save({ point = "CENTER", relPoint = "CENTER", x = spot[1], y = spot[2] })
        end
    end
    lastNudged = nil
    if placement.selected then H.Refresh(placement.selected) end
end

local function Step(from, to)
    if InCombatLockdown() or #from == 0 or placement.dragging then return end
    to[#to + 1] = Snapshot()
    Restore(table.remove(from))
    H.PaintHistory()
end

function UI.UndoMove() Step(undo, redo) end
function UI.RedoMove() Step(redo, undo) end

function UI.RevertMoves()
    if InCombatLockdown() or #undo == 0 or placement.dragging then return end
    redo[#redo + 1] = Snapshot()
    Restore(undo[1])
    wipe(undo)
    H.PaintHistory()
end

local function ResetHistory()
    wipe(undo)
    wipe(redo)
    lastNudged = nil
end

local function CanUndo() return #undo > 0 end
local function CanRedo() return #redo > 0 end

H.Moves, H.Snapshot, H.Checkpoint, H.Change, H.Restore = Moves, Snapshot, Checkpoint, Change, Restore
H.ResetHistory, H.CanUndo, H.CanRedo = ResetHistory, CanUndo, CanRedo
