-- Place.lua: where the planner's window and mini bar sit: on whole pixels, kept account-wide.
local ns = _G.NaowhForever

local Training = ns.Training

local Place = {}
Training.Place = Place

function Place.Snap(frame, w, h)
    local left, top = frame:GetLeft(), frame:GetTop()
    if not left then return end
    frame:ClearAllPoints()
    PixelUtil.SetPoint(frame, "TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    PixelUtil.SetSize(frame, w, h)
end

function Place.Save(frame, w, h, key)
    Place.Snap(frame, w, h)
    local point, _, relPoint, x, y = frame:GetPoint()
    ns.AccountSettings()[key] = { point, relPoint, x, y }
end

function Place.Restore(frame, key, default)
    local saved = ns.AccountSettings()[key]
    if type(saved) == "table" then
        frame:SetPoint(saved[1], UIParent, saved[2], saved[3], saved[4])
    else
        frame:SetPoint(unpack(default))
    end
end
