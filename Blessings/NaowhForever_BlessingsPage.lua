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
local MODIFIER_KEYS = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true }

-- A key field for one binding action, saved in the same place as the Key Bindings screen.
-- Click it and press a key to bind, Escape to cancel; right-click clears it.
-- The page reuses its rows, so a region that already has its key button keeps it.
local function KeyField(rgn, action, label)
    if rgn._keyField then return end
    rgn._keyField = true
    local btn = ns.Button(rgn, "", 150, 26)
    btn:SetPoint("RIGHT", rgn, "RIGHT", -20, 0)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local capturing
    local function Show()
        local key = GetBindingKey(action)
        btn.label:SetText(capturing and "Press a key..." or key and GetBindingText(key) or "|cff808080Not bound|r")
        btn:SetAlpha(InCombatLockdown() and 0.4 or 1)
    end
    local function Stop()
        capturing = false
        btn:EnableKeyboard(false)
        Show()
    end
    local function Save()
        SaveBindings(GetCurrentBindingSet())
    end
    btn:SetScript("OnClick", function(_, button)
        if InCombatLockdown() then return end
        if button == "RightButton" then
            for _, key in ipairs({ GetBindingKey(action) }) do SetBinding(key) end
            Save()
            Stop()
            return
        end
        capturing = true
        btn:EnableKeyboard(true)
        btn:SetPropagateKeyboardInput(false)
        Show()
    end)
    btn:SetScript("OnKeyDown", function(_, key)
        if MODIFIER_KEYS[key] then return end
        if key == "ESCAPE" or InCombatLockdown() then
            Stop()
            return
        end
        local combo = (IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "")
            .. (IsShiftKeyDown() and "SHIFT-" or "") .. key
        local previous = GetBindingAction(combo)
        for _, old in ipairs({ GetBindingKey(action) }) do SetBinding(old) end
        SetBinding(combo, action)
        Save()
        if previous ~= "" and previous ~= action then
            ns.Print(("%s is now bound to %s instead of %s."):format(GetBindingText(combo), label,
                GetBindingName(previous)))
        end
        Stop()
    end)
    -- Setting an OnKeyDown script turns keyboard input on; it stays off until the field is clicked.
    btn:EnableKeyboard(false)
    btn:SetScript("OnShow", Show)
    btn:SetScript("OnHide", function() if capturing then Stop() end end)
    ns.Tooltip(btn, label, "Click, then press a key to bind it. Escape cancels; right-click clears. "
        .. "The same binding as in Key Bindings > Naowh Forever.")
    Show()
end
ns.KeyField = KeyField

function ns.BuildQoLBlessingsPage(parent, y)
    local UI = ns.UI
    local W = UI.Widgets
    local _, h
    _, h = W:Note(parent, "A button per class in your group. Left-click blesses the next member "
        .. "of that class who needs it: missing first, then whoever runs out soonest, skipping "
        .. "anyone dead or out of range. The red number is how many are missing it. Right-click "
        .. "a class to choose its blessing or open its player list, where each player can have "
        .. "their own. A Greater Blessing is only used while the whole class shares one and you "
        .. "carry Symbols of Kings. In combat a class button keeps the member it had when the "
        .. "fight began.|n|nNext Blessing and Next Greater Blessing can be bound below, or in Key "
        .. "Bindings > AddOns > Naowh Forever. Each press blesses the next player who needs it, most urgent "
        .. "first; in combat a key steps through the players who needed it when the fight began.", y); y = y - h

    _, h = W:SectionHeader(parent, "KEYBINDS" .. UI.STATUS.untested, y); y = y - h
    local row
    row, h = W:DualRow(parent, y,
        { type = "label", text = "Next Blessing" },
        { type = "label", text = "Next Greater Blessing" }
    ); y = y - h
    KeyField(row._leftRegion, "CLICK NaowhForeverBlessNext:LeftButton", "Next Blessing")
    KeyField(row._rightRegion, "CLICK NaowhForeverBlessNextGreater:LeftButton", "Next Greater Blessing")

    _, h = W:SectionHeader(parent, "BLESSING BAR", y); y = y - h
    _, h = W:Feature(parent, y, { type = "label", text = "Bar" .. UI.STATUS.untested }); y = y - h
    _, h = W:DualRow(parent, y,
        S.Slider("blessBarSize", "Button Size", 20, 70, 1, nil, "blessings"),
        S.Toggle("blessTimers", "Minutes Left",
            "Minutes left on each class's shortest blessing, and on each player's.", "blessings")
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Toggle("blessShowAura", "Aura Button",
            "Casts your aura. Right-click it to choose which.", "blessings"),
        S.Toggle("blessShowFury", "Righteous Fury Button", "Casts Righteous Fury on yourself.",
            "blessings")
    ); y = y - h

    _, h = W:DualRow(parent, y,
        S.Slider("blessSpacing", "Button Spacing", 0, 30, 1),
        S.Slider("blessGroupSpacing", "Aura / Class Gap", 0, 40, 1)
    ); y = y - h
    _, h = W:DualRow(parent, y,
        S.Slider("blessTimerSize", "Timer Text Size", 8, 24, 1),
        S.Toggle("blessShowLabels", "Class Labels")
    ); y = y - h
    return y
end

local function NewCell(parent)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(CELL, CELL)
    btn.tex = btn:CreateTexture(nil, "ARTWORK")
    btn.tex:SetPoint("TOPLEFT", 1, -1)
    btn.tex:SetPoint("BOTTOMRIGHT", -1, 1)
    btn.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    ns.Border(btn)
    return btn
end

local function Cell(parent, x, y, icon, lit, title, body, onClick)
    local btn = ns.UI.Keep(parent, "cell", NewCell)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    local tex = btn.tex
    tex:SetTexture(icon)
    tex:SetDesaturated(not lit)
    tex:SetAlpha(lit and 1 or 0.35)
    btn:SetScript("OnClick", onClick)
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
        if member.class == "PALADIN" and member.guid ~= UnitGUID("player") and not others[member.who] then
            rows[#rows + 1] = { who = member.who }
        end
    end
    if #rows == 0 then
        _, h = W:Note(parent, "No paladins in your group.", y); y = y - h
        return y
    end

    for _, row in ipairs(rows) do
        local label = UI.KeepFont(parent, "name", 13, "OUTLINE", RAID_CLASS_COLORS.PALADIN)
        label:SetPoint("TOPLEFT", parent, "TOPLEFT", left, y - 9)
        label:SetWidth(NAME_WIDTH - 10)
        label:SetJustifyH("LEFT")
        label:SetText(Ambiguate(row.who, "short") .. (row.you and "  (you)" or ""))
        if not row.plan then
            local note = UI.KeepFont(parent, "noAddon", 12, nil, T.muted)
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
