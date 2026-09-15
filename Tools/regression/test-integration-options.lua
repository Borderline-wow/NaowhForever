local root = arg[1] or "."
local function Fixture()
    local e = { buttons = {}, boxes = {}, controls = {}, rules = {}, spec = 250 }
    local function Widget(parent)
        return { parent = parent, SetPoint = function() end, SetSize = function(self, w, h) self.width = w; self.height = h end,
            SetWidth = function(self, w) self.width = w end, SetHeight = function() end,
            SetAllPoints = function() end, SetFontObject = function() end, SetAutoFocus = function() end,
            SetMaxLetters = function() end, SetJustifyH = function() end, SetWordWrap = function() end,
            SetScrollChild = function() end, ClearAllPoints = function() end, GetFrameLevel = function() return 1 end,
            SetText = function(self, v) self.text = v; if self.parent then self.parent.title = v end end,
            GetText = function(self) return self.text end, Hide = function() end, SetTexture = function() end }
    end
    local I = {
        Spec = function() return e.spec end, Rules = function() return e.rules end,
        Refresh = function() end, ValidRule = function() return true end,
        Preview = function(r) e.preview = r end,
        Save = function(uid, r) e.saved = r; uid = uid or "i1"; e.rules[uid] = r; return true, uid end,
        Catalogue = function() return { { id = 1762, name = "Kings Rest", abilities = {
            { spellID = 123, name = "Slam", mob = "Guard" } } } } end,
    }
    local ns = { Integrations = I, THEME = {}, UI = { Widgets = {} } }
    ns.Font = Widget; ns.Solid = Widget; ns.Border = Widget; ns.Tooltip = function() end
    ns.Button = function(_, text, _, _, callback)
        e.buttons[text] = callback; local w = Widget(); w.label = Widget(); return w
    end
    ns.ListPresets = function() return { { key = "p1", name = "Defensives" } } end
    ns.UI.RefreshPage = function() e.render() end
    ns.UI.BuildAlertSoundTables = function() return {}, { test = "Test" }, { "test" } end
    ns.UI.AppendSharedMediaSounds = function() end
    ns.UI.BuildDropdownControl = function(parent, width, _, _, _, get, set)
        e.controls[parent.title] = { get = get, set = set, width = width }; return Widget()
    end
    ns.UI.BuildToggleControl = function(parent, _, get, set)
        e.controls[parent.title] = { get = get, set = set }; return Widget()
    end
    local env = setmetatable({ NaowhUITankReminder = ns, GameFontHighlight = {},
        CreateFrame = function(kind, _, parent)
            local w = Widget(); w.CreateTexture = Widget
            if kind == "EditBox" then e.boxes[parent.title] = w end
            return w
        end,
    }, { __index = _G })
    env._G = env
    local c = assert(loadfile(root .. "/NaowhUI_SmartReminders_IntegrationOptions.lua")); setfenv(c, env); c()
    function e.render() e.buttons = {}; e.boxes = {}; e.controls = {}; ns.BuildIntegrationsPage(Widget(), 0) end
    e.render()
    return e
end
local function SelectTrash(e)
    e.controls.Dungeon.set(1762); e.buttons.Slam()
end
local e = Fixture(); SelectTrash(e)
assert(e.controls["Defensive preset"].width >= 260)
e.controls["Defensive preset"].set("p1")
e.controls["Healer Reminder"].set(true); e.controls["Speak callout"].set(true)
e.boxes["Callout text"]:SetText("Spread")
e.buttons["Test Reminder"](); assert(e.preview.display.text == "Spread")
e.buttons.Save()
assert(e.saved.trigger.type == "exboss" and e.saved.trigger.spellID == 123 and e.saved.trigger.mapID == 1762)
assert(e.saved.preset == "p1" and e.saved.healerReminder and e.saved.display.tts)
assert(e.buttons.Remove, "saved rule did not stay selected")
e.buttons.Save(); assert(e.rules.i1 and not e.rules.i2)
e.buttons.Remove(); assert(not next(e.rules))
e = Fixture(); e.buttons["+ Debuff Sound"]()
e.boxes["Debuff spell ID"]:SetText("456")
e.controls.When.set("Removed"); e.controls.Unit.set("party"); e.controls.Sound.set("test")
e.buttons.Save()
assert(e.saved.trigger.type == "auraSound" and e.saved.trigger.auraEvent == "Removed")
assert(e.saved.trigger.target == "party" and e.saved.trigger.mapID == 0 and e.saved.display.sound == "test")
assert(e.buttons.Remove and not e.saved.display.tts and not e.saved.preset)
for _, change in ipairs({ "profile", "spec" }) do
    e = Fixture(); SelectTrash(e)
    if change == "profile" then e.rules = {} else e.spec = 251 end
    e.buttons.Save(); assert(not e.saved)
end
e = Fixture(); e.buttons["+ Debuff Sound"]()
e.boxes["Debuff spell ID"]:SetText("21562")
e.controls.Sound.set("voice:stoneform-ready")
e.buttons.Save()
assert(e.saved.display.sound == "voice:stoneform-ready" and e.saved.trigger.target == "player")
assert(e.controls.Sound.get() == "voice:stoneform-ready")
e.buttons["Test Reminder"](); assert(e.preview.display.sound == "voice:stoneform-ready")
print("PASS dungeon selection, wide preset control, preview, save/reselection, remove, debuff and profile isolation")

for _, field in ipairs({ "Debuff spell ID", "Instance ID (0 = every dungeon / raid)" }) do
    for _, value in ipairs({ "", "invalid" }) do
        e = Fixture(); e.buttons["+ Debuff Sound"]()
        e.boxes["Debuff spell ID"]:SetText("21562")
        e.controls.Sound.set("test"); e.buttons.Save()
        e.boxes[field]:SetText(value); e.buttons.Save()
        local key = field == "Debuff spell ID" and "spellID" or "mapID"
        assert(e.saved.trigger[key] == nil, "invalid input fell back to saved ID")
    end
end
print("PASS edited invalid IDs reach validation instead of falling back")
