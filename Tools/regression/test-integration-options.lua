local root = arg[1] or "."
local function Fixture()
    local e = { buttons = {}, boxes = {}, controls = {}, rowToggles = {}, rawButtons = {}, scrolls = {},
        rules = {}, spec = 250 }
    local function Tab(self, name)
        for _, w in ipairs(self.rawButtons) do
            if w.title == name then return w end
        end
    end
    local function Widget(parent)
        return { parent = parent, SetPoint = function() end, SetSize = function(self, w, h) self.width = w; self.height = h end,
            SetWidth = function(self, w) self.width = w end, SetHeight = function() end,
            SetAllPoints = function() end, SetFontObject = function() end, SetAutoFocus = function() end,
            SetMaxLetters = function() end, SetJustifyH = function() end, SetWordWrap = function() end,
            SetScrollChild = function() end, ClearAllPoints = function() end, GetFrameLevel = function() return 1 end,
            GetHeight = function(self) return self.height or 0 end,
            UpdateScrollChildRect = function() end,
            SetVerticalScroll = function(self, v) self.vscroll = v end,
            HookScript = function(self, kind, fn) self.hooks = self.hooks or {}; self.hooks[kind] = fn end,
            SetText = function(self, v) self.text = v; if self.parent then self.parent.title = v end end,
            GetText = function(self) return self.text end, Hide = function() end, Show = function() end,
            SetShown = function(self, v) self.shown = v end, GetStringWidth = function() return 40 end,
            SetScript = function(self, kind, fn)
                if kind == "OnClick" then self.onClick = fn
                elseif kind == "OnEditFocusLost" then self.onCommit = fn end
            end,
            SetTexture = function() end, SetTexCoord = function() end, SetTextColor = function() end,
            SetTextInsets = function() end, ClearFocus = function() end,
            Enable = function(self) self.disabled = false end,
            Disable = function(self) self.disabled = true end }
    end
    local I = {
        Spec = function() return e.spec end, Rules = function() return e.rules end,
        Refresh = function() end, ValidRule = function() return true end,
        Preview = function(r) e.preview = r end,
        Save = function(uid, r) e.saved = r; uid = uid or "i1"; e.rules[uid] = r; return true, uid end,
    }
    local colour = { r = 1, g = 1, b = 1 }
    local ns = { Integrations = I, UI = { Widgets = {} },
        THEME = { accent = colour, muted = colour, fg = colour, panel = colour,
            bg = colour, line = colour, accentSoft = colour } }
    ns.Font = Widget; ns.Solid = Widget; ns.Tooltip = function() end
    ns.Border = function() local b = Widget(); b._frame = Widget(); return b end
    -- Kept rows are re-labelled and re-pointed through _onClick, so a row is found by the
    -- label it was last given.
    ns.SetButtonText = function(btn, text)
        btn.label:SetText(text)
        e.buttons[text] = function(...) return btn._onClick(...) end
    end
    ns.Button = function(_, text, _, _, callback)
        e.buttons[text] = callback; local w = Widget(); w.label = Widget(); return w
    end
    ns.UI.RefreshPage = function() e.render() end
    ns.UI.BuildAlertSoundTables = function() return {}, { test = "Test" }, { "test" } end
    ns.UI.AppendSharedMediaSounds = function() end
    -- Nothing here reuses its rows, so every kept element is made fresh, as on a first build.
    ns.UI.BeginReusableRows = function() end
    ns.UI.Keep = function(parent, _, create) return create(parent), true end
    ns.UI.KeepFont = function(parent, _, ...) return ns.Font(parent, ...) end
    ns.UI.KeepButton = function(parent, _, text, w, h, onClick)
        local b = ns.Button(parent, text, w, h, onClick); b._onClick = onClick; return b
    end
    ns.UI.KeepToggle = function(parent, _, get, set) return ns.UI.BuildToggleControl(parent, nil, get, set) end
    ns.UI.KeepDropdown = function(parent, _, width, values, order, get, set)
        return ns.UI.BuildDropdownControl(parent, width, nil, values, order, get, set)
    end
    ns.UI.BuildDropdownControl = function(parent, width, _, values, order, get, set)
        if parent.title then e.controls[parent.title] = { get = get, set = set, width = width,
            values = values, order = order } end
        return Widget()
    end
    -- Keyed by the label above it, and the reminder rows in the list have no label of their
    -- own -- those toggles are collected separately rather than indexed by nil.
    ns.UI.BuildToggleControl = function(parent, _, get, set)
        if parent.title then e.controls[parent.title] = { get = get, set = set }
        else e.rowToggles[#e.rowToggles + 1] = { get = get, set = set } end
        local t = Widget(); t._refreshValue = function() end
        return t
    end
    local env = setmetatable({ NaowhForever = ns, GameFontHighlight = {},
        CreateFrame = function(kind, _, parent)
            local w = Widget(); w.CreateTexture = Widget
            if kind == "ScrollFrame" then e.scrolls[#e.scrolls + 1] = w end
            if kind == "EditBox" then e.boxes[parent.title] = w end
            -- The editor's own tabs are raw Buttons, not ns.Button, so they are collected
            -- here and looked up by the label that names them.
            if kind == "Button" then e.rawButtons[#e.rawButtons + 1] = w end
            return w
        end,
    }, { __index = _G })
    env._G = env
    local c = assert(loadfile(root .. "/NaowhForever_SmartReminders/NaowhForever_IntegrationOptions.lua")); setfenv(c, env); c()
    e.tab = Tab
    -- There is no Save button any more. Committing every text box is what leaving the
    -- editor does, and every other control writes through the moment it changes.
    function e.commitAll()
        for _, box in pairs(e.boxes) do
            if box.onCommit then box.onCommit() end
        end
    end
    e.renders = 0
    function e.render()
        e.renders = e.renders + 1
        e.buttons = {}; e.boxes = {}; e.controls = {}; e.rowToggles = {}; e.rawButtons = {}
        e.scrolls = {}
        ns.BuildDebuffsPage(Widget(), 0)
    end
    e.render()
    return e
end
local e = Fixture(); e.buttons["+ Debuff Alert"]()
e.boxes["Debuff spell ID"]:SetText("456")
e.controls.When.set("Removed"); e.controls.Unit.set("party"); e.controls.Sound.set("test")
e.commitAll()
assert(e.saved.trigger.type == "auraSound" and e.saved.trigger.auraEvent == "Removed")
assert(e.saved.trigger.target == "party" and e.saved.trigger.mapID == 0
    and e.saved.display.sound == "test")
assert(e.buttons.Remove and not e.saved.display.tts and not e.saved.preset)
e.buttons.Remove(); assert(not next(e.rules))
for _, change in ipairs({ "profile", "spec" }) do
    e = Fixture(); e.buttons["+ Debuff Alert"]()
    e.boxes["Debuff spell ID"]:SetText("456")
    if change == "profile" then e.rules = {} else e.spec = 251 end
    e.commitAll(); assert(not e.saved)
end
e = Fixture(); e.buttons["+ Debuff Alert"]()
e.boxes["Debuff spell ID"]:SetText("21562")
e.controls.Sound.set("voice:stoneform-ready")
e.commitAll()
assert(e.saved.display.sound == "voice:stoneform-ready" and e.saved.trigger.target == "player")
assert(e.controls.Sound.get() == "voice:stoneform-ready")
e.buttons.Test(); assert(e.preview.display.sound == "voice:stoneform-ready")
print("PASS save/reselection, remove, preview and profile isolation")

for _, value in ipairs({ "", "invalid" }) do
    e = Fixture(); e.buttons["+ Debuff Alert"]()
    e.boxes["Debuff spell ID"]:SetText("21562")
    e.controls.Sound.set("test"); e.commitAll()
    e.boxes["Debuff spell ID"]:SetText(value); e.commitAll()
    assert(e.saved.trigger.spellID == nil, "invalid input fell back to saved ID")
end

-- An alert saved for an instance keeps that instance rather than being quietly moved to
-- everywhere.
e = Fixture()
e.rules.x1 = { name = "Odd", enabled = true,
    trigger = { type = "auraSound", spellID = 999, mapID = 424242, target = "player" },
    display = { type = "icon" } }
e.render(); e.buttons["Odd"]()
assert(e.controls.Dungeon.values[424242] == "Instance 424242")

-- One panel, two columns, no tabs.
e = Fixture(); e.buttons["+ Debuff Alert"]()
assert(e.boxes["Reminder name"] and e.boxes["Debuff spell ID"] and e.controls.Sound,
    "every control is built without a click")
assert(not e:tab("Cast") and not e:tab("Voice") and not e:tab("Text & Test"),
    "and there are no tabs left to click")
assert(e.controls["Enabled"].get() == true, "a new alert starts enabled")

-- The first change that makes a valid rule creates it, so the page rebuilds once to list it
-- and give it a Remove button. Every change after that updates in place, or a rebuild would
-- fight the keyboard while typing.
e.boxes["Debuff spell ID"]:SetText("456"); e.controls.Sound.set("test")
assert(e.rules.i1, "the first change wrote the rule")
local renders = e.renders
e.controls.When.set("Removed")
e.boxes["Reminder name"]:SetText("Typed")
assert(e.renders == renders, "a later change must not rebuild the page")
assert(e.boxes["Reminder name"]:GetText() == "Typed")
e.commitAll()
assert(e.buttons.Test and e.buttons.Remove)

-- "Another instance" brings the id field back.
e = Fixture(); e.buttons["+ Debuff Alert"]()
assert(e.controls["Dungeon"].values.other == "Another instance (by ID)")
assert(not e.boxes["Instance ID (0 = every dungeon or raid)"], "hidden until asked for")

-- Saved first, deliberately. The very first save creates the rule and rebuilds the page,
-- and that rebuild resets the editor back to the list -- so a sequence that switches to
-- the id field before the rule exists never reaches the transition below at all.
e.boxes["Debuff spell ID"]:SetText("21562"); e.controls.Sound.set("test"); e.commitAll()
e.controls["Dungeon"].set("other")
local idBox = e.boxes["Instance ID (0 = every dungeon or raid)"]
assert(idBox, "picking it brings the field back")
idBox:SetText("2657"); e.commitAll()
assert(e.saved.trigger.mapID == 2657, "and the typed id is what gets saved")

-- Picking from the list puts it back in charge. Value() prefers a box whenever one exists,
-- and the box outlives the pick by one rebuild, so the pick has to beat it.
e.controls["Dungeon"].set(0)
assert(e.saved.trigger.mapID == 0, "the pick wins, not the id left in the box")
assert(not e.boxes["Instance ID (0 = every dungeon or raid)"], "and the field goes away")

-- An ordinary pick does not rebuild the page. The dropdown repaints its own label, and a
-- rebuild throws away whatever is typed into an alert too incomplete to have saved yet.
e = Fixture(); e.buttons["+ Debuff Alert"]()
e.boxes["Debuff spell ID"]:SetText("21562"); e.controls.Sound.set("test"); e.commitAll()
renders = e.renders
e.controls["Dungeon"].set(0)
assert(e.renders == renders, "nothing appeared or disappeared, so nothing to redraw")
e.controls["Dungeon"].set("other")
assert(e.renders > renders, "the id field has to be drawn")

-- Debuff alerts are grouped by the instance they are set for, and a group folds away
-- without letting go of whatever is selected inside it.
e = Fixture()
for i = 1, 4 do
    e.rules["b" .. i] = { name = "Alert " .. i, enabled = true,
        trigger = { type = "auraSound", spellID = 200 + i,
            mapID = (i <= 2) and 1762 or 0 },
        display = { type = "icon" } }
end
e.render()
assert(#e.rowToggles == 4, "every alert is listed under the instance it names")
assert(e.buttons["-  Instance 1762  (2)"], "the instance names the group")
assert(e.buttons["-  Every dungeon or raid  (2)"], "and one set everywhere is its own")

e.buttons["Alert 1"]()
assert(e.buttons["Remove"], "picking an alert opens its editor")
e.buttons["-  Instance 1762  (2)"]()
assert(#e.rowToggles == 2, "a folded group stops drawing its rows")
assert(e.buttons["+  Instance 1762  (2)"], "and says it is folded")
assert(e.buttons["Remove"],
    "folding the group is not deselecting what is inside it")
e.buttons["+  Instance 1762  (2)"]()
assert(#e.rowToggles == 4, "and it comes back")

-- Trash rules saved before ExBoss support was dropped are not debuff alerts and stay out
-- of this list.
e.rules.t1 = { name = "Old trash", enabled = true,
    trigger = { type = "exboss", spellID = 999, mapID = 0 }, display = { type = "icon" } }
e.render()
assert(#e.rowToggles == 4 and not e.buttons["Old trash"])

-- Picking a rule rebuilds the page, and the list is rebuilt onto a new scroll frame with
-- it. Without the offset being carried across, choosing anything below the fold sent the
-- list back to the top, which is where you were not.
e = Fixture()
for i = 1, 30 do
    e.rules["a" .. i] = { name = "Alert " .. i, enabled = true,
        trigger = { type = "auraSound", spellID = 100 + i, target = "me" },
        display = { type = "icon" } }
end
e.render()
local list = e.scrolls[#e.scrolls]
assert(list.hooks and list.hooks.OnVerticalScroll, "the list has to report its own offset")
list.hooks.OnVerticalScroll(list, 120)
e.render()
assert(e.scrolls[#e.scrolls].vscroll == 120,
    "got " .. tostring(e.scrolls[#e.scrolls].vscroll))

-- Clamped to what the rebuilt list can actually show: deleting most of the rules while
-- scrolled to the bottom must not leave it parked past the end.
for i = 4, 30 do e.rules["a" .. i] = nil end
e.render()
assert(e.scrolls[#e.scrolls].vscroll == 0,
    "a list shorter than its frame has nowhere to scroll to")

print("PASS edited invalid IDs reach validation instead of falling back")
