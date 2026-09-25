-------------------------------------------------------------------------------
--  NaowhForever_BlessingsPage.lua -- the Blessings pages: the bar's settings, and
--  the assignments grid, a row per paladin in the group and a column per class plus the aura.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.QoLSettings
local T = ns.THEME
local B = ns.Blessings

local CELL, GAP, NAME_WIDTH = 32, 6, 170
local EMPTY = 134400

function ns.BuildQoLBlessingsPage(parent, y)
    local UI = ns.UI
    local W = UI.Widgets
    local _, h
    _, h = W:Note(parent, "A button per class in your group. Left-click blesses the next member "
        .. "of that class who needs it: missing first, then whoever runs out soonest, skipping "
        .. "anyone dead or out of range. The red number is how many are missing it. Right-click "
        .. "a class to choose its blessing or open its player list, where each player can have "
        .. "their own. A Greater Blessing is only used while the whole class shares one.", y); y = y - h

    _, h = W:SectionHeader(parent, "BAR" .. UI.STATUS.untested, y); y = y - h
    _, h = W:DualRow(parent, y,
        S.Slider("blessBarSize", "Button Size", 20, 48, 1, nil, "blessings"),
        S.Toggle("blessTimers", "Minutes Left",
            "Minutes left on each class's shortest blessing, and on each player's.", "blessings")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("blessShowAura", "Aura Button",
            "Casts your aura. Right-click it to choose which.", "blessings"),
        S.Toggle("blessShowFury", "Righteous Fury Button", "Casts Righteous Fury on yourself.",
            "blessings")
    ); y = y - h
    return y
end

local function Cell(parent, x, y, icon, lit, title, body, onClick)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(CELL, CELL)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    local tex = btn:CreateTexture(nil, "ARTWORK")
    tex:SetPoint("TOPLEFT", 1, -1)
    tex:SetPoint("BOTTOMRIGHT", -1, 1)
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    tex:SetTexture(icon)
    tex:SetDesaturated(not lit)
    tex:SetAlpha(lit and 1 or 0.35)
    ns.Border(btn)
    if onClick then btn:SetScript("OnClick", onClick) end
    ns.Tooltip(btn, title, body)
    return btn
end

function ns.BuildBlessingAssignmentsPage(parent, y)
    local UI = ns.UI
    local W = UI.Widgets
    local _, h
    _, h = W:Note(parent, "Every paladin in your group running Naowh Forever, and the blessing "
        .. "they give each class. Click an icon to change it: your own row always, anyone's while "
        .. "you lead the group or are an assistant. Only what that paladin has learned is offered, "
        .. "and changes reach them straight away.", y); y = y - h
    _, h = W:SectionHeader(parent, "ASSIGNMENTS" .. UI.STATUS.untested, y); y = y - h

    local left = UI.CONTENT_PAD
    local columns = {}
    for _, class in ipairs(B.CLASSES) do columns[#columns + 1] = class end
    columns[#columns + 1] = "AURA"
    for i, column in ipairs(columns) do
        local aura = column == "AURA"
        Cell(parent, left + NAME_WIDTH + (i - 1) * (CELL + GAP), y,
            aura and B.SpellIcon("devotion") or "Interface\\Icons\\ClassIcon_" .. column, true,
            aura and "Aura" or B.ClassName(column))
    end
    y = y - CELL - 10

    local lead = B.CanAssign("player")
    local rows = {}
    if B.IsPaladin() then
        local store = B.Store()
        rows[1] = { who = UnitName("player"), you = true, plan = store, can = B.Learned, set = B.SetOwn }
    end
    local others = B.Others()
    local names = {}
    for who in pairs(others) do names[#names + 1] = who end
    table.sort(names)
    for _, who in ipairs(names) do
        local plan = others[who]
        rows[#rows + 1] = { who = who, plan = plan,
            can = function(entry) return plan.known[entry.key] end,
            set = lead and function(column, key)
                B.SetFor(who, column, key)
                UI:RefreshPage(true)
            end }
    end
    for _, member in ipairs(B.Roster()) do
        if member.class == "PALADIN" and not UnitIsUnit(member.unit, "player") and not others[member.who] then
            rows[#rows + 1] = { who = member.who }
        end
    end
    if #rows == 0 then
        _, h = W:Note(parent, "No paladins in your group.", y); y = y - h
        return y
    end

    for _, row in ipairs(rows) do
        local label = ns.Font(parent, 13, "OUTLINE", RAID_CLASS_COLORS.PALADIN)
        label:SetPoint("TOPLEFT", parent, "TOPLEFT", left, y - 9)
        label:SetWidth(NAME_WIDTH - 10)
        label:SetJustifyH("LEFT")
        label:SetText(Ambiguate(row.who, "short") .. (row.you and "  (you)" or ""))
        if not row.plan then
            local note = ns.Font(parent, 12, nil, T.muted)
            note:SetPoint("TOPLEFT", parent, "TOPLEFT", left + NAME_WIDTH, y - 10)
            note:SetText("Not running Naowh Forever")
        else
            for i, column in ipairs(columns) do
                local aura = column == "AURA"
                local key = aura and row.plan.aura or row.plan.classes[column]
                local title = aura and "Aura" or B.ClassName(column)
                local onClick = row.set and function(btn)
                    B.OpenMenu(btn, title, aura and B.AURAS or B.BLESSINGS,
                        function() return aura and row.plan.aura or row.plan.classes[column] end,
                        function(choice) row.set(column, choice) end, "None", row.can)
                end
                Cell(parent, left + NAME_WIDTH + (i - 1) * (CELL + GAP), y,
                    key and B.SpellIcon(key) or EMPTY, key ~= nil, title,
                    (key and B.SpellName(key) or "Nothing assigned")
                        .. (onClick and "\nClick to change." or ""), onClick)
            end
        end
        y = y - CELL - GAP
    end
    return y - 10
end
