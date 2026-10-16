-- Parts.lua: Naowh's Forge's small parts: its text, pooled rows, icons, section titles and banded list rows (ns.Macros.Parts).
local ns = _G.NaowhForever
local T = ns.THEME

local M = ns.Macros
local St = M.Style

local PAD = St.PAD
local SECTION_H = St.SECTION_H
local STRIPE, HOVER, PICKED = St.STRIPE, St.HOVER, 0.10
local SELECTED_BAR = 2
local SHADOW_X, SHADOW_Y, SHADOW_ALPHA = 1, -1, 0.85
local ICON_EDGE, ICON_CROP = 1, St.ICON_CROP
local TITLE_SIZE = St.NOTE_SIZE
local SECTION_BASELINE = 5
local COUNT_GAP = "   "

local Parts = {}
M.Parts = Parts

local function RowEnter(row)
    if not row.picked then row.band:SetAlpha(HOVER) end
end

local function RowLeave(row)
    if not row.picked then row.band:SetAlpha(0) end
end

function Parts.Text(parent, size, color)
    local fs = ns.Font(parent, size or St.TEXT_SIZE, nil, color)
    fs:SetShadowOffset(SHADOW_X, SHADOW_Y)
    fs:SetShadowColor(0, 0, 0, SHADOW_ALPHA)
    return fs
end

function Parts.Paint(fs, c)
    fs:SetTextColor(c.r, c.g, c.b, 1)
end

function Parts.Pool(make)
    local pool = { list = {}, used = 0 }
    function pool.Take()
        pool.used = pool.used + 1
        local f = pool.list[pool.used]
        if not f then
            f = make()
            pool.list[pool.used] = f
        end
        f:ClearAllPoints()
        f:Show()
        return f
    end
    function pool.Release()
        for i = 1, #pool.list do pool.list[i]:Hide() end
        pool.used = 0
    end
    return pool
end

function Parts.Icon(parent, size)
    local edge = parent:CreateTexture(nil, "BORDER")
    edge:SetColorTexture(0, 0, 0, 1)
    edge:SetSize(size + 2 * ICON_EDGE, size + 2 * ICON_EDGE)
    local icon = parent:CreateTexture(nil, "ARTWORK")
    ns.PixelInset(icon, ICON_EDGE, edge)
    icon:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
    icon.edge = edge
    return icon
end

function Parts.NewSection(parent)
    local h = CreateFrame("Frame", nil, parent)
    h:SetHeight(SECTION_H)
    h.title = Parts.Text(h, TITLE_SIZE, T.accentSoft)
    h.title:SetPoint("BOTTOMLEFT", PAD, SECTION_BASELINE)
    h.note = Parts.Text(h, St.SMALL_SIZE, T.muted)
    h.note:SetPoint("BOTTOMRIGHT", -PAD, SECTION_BASELINE)
    local rule = ns.Solid(h, "ARTWORK", T.line, 1)
    rule:SetPoint("BOTTOMLEFT")
    rule:SetPoint("BOTTOMRIGHT")
    ns.Hairline(rule, "h")
    return h
end

function Parts.SetSection(h, title, count, note)
    h.title:SetText(title:upper() .. (count and note and (COUNT_GAP .. ns.Color("muted", count)) or ""))
    h.note:SetText(note or count or "")
end

function Parts.ListRow(b)
    b.stripe = ns.Solid(b, "BACKGROUND", T.fg, STRIPE)
    b.stripe:SetAllPoints()
    b.band = ns.Solid(b, "BACKGROUND", T.fg, 1)
    b.band:SetAllPoints()
    b.band:SetAlpha(0)
    b.bar = ns.Solid(b, "ARTWORK", T.accent, 1)
    b.bar:SetPoint("TOPLEFT")
    b.bar:SetPoint("BOTTOMLEFT")
    b.bar:SetWidth(SELECTED_BAR)
    b:SetScript("OnEnter", RowEnter)
    b:SetScript("OnLeave", RowLeave)
end

function Parts.Pick(b, picked)
    b.picked = picked
    b.bar:SetShown(picked)
    b.band:SetAlpha(picked and PICKED or 0)
end
