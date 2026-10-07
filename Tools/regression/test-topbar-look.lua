-- Top Bar text: the clock keeps its own font with no outline, the FPS / MS readout and the online
-- counts keep the outlined Addon Font, until Font, Outline or Clock Outline is picked; and the card's
-- rows in the standard groups. Cut out of TopBar.lua and run on stubs. Run from the repo root.
local f = assert(io.open(arg[1] or "TopBar/NaowhForever_TopBar.lua", "rb"))
local source = f:read("*a"):gsub("\r\n", "\n"); f:close()
local checks = 0
local function check(label, ok) assert(ok, label); checks = checks + 1 end

local function Slice(a, b)
    local first = assert(source:find(a, 1, true), a)
    return source:sub(first, assert(source:find(b, first + #a, true), b) - 1)
end

local code = table.concat({
    "local S, Parts, UI, ns, Group, ResetLayout = ...",
    "local BADGE_SIZE, BTN_PAD, GAP = 10, 8, 4",
    "local function Tone() return 1, 1, 1, 1 end",
    "local function IconColor() return 1, 1, 1 end",
    "local function BtnSize() return S.Get('iconSize') + BTN_PAD end",
    "local Look = {}",
    Slice("function Look.ClockFont(clock)", "\nfunction Look.ClockText()"),
    Slice("function Look.Row(group, list, n)", "\nfunction Look.Fit("),
    Slice("function Look.SystemFont(text)", "\nlocal SYSTEM_TEXT"),
    Slice("local ROWS = {", "\nns.Shared.Settings.Page("),
    "return { Look = Look, ROWS = ROWS }",
}, "\n")

local defaults = {}
for key, value in source:match("UI%.ModuleSettings%(\"topBar\", (%b{})"):gmatch("(%w+) = (\"[^\"]*\")") do
    defaults[key] = loadstring("return " .. value)()
end
defaults.iconSize, defaults.sysSize, defaults.clockSize = 22, 13, 27
local settings = {}
local S = { Get = function(k) if settings[k] == nil then return defaults[k] end return settings[k] end }

local OUTLINES = { { NONE = "None", [""] = "Shadow", OUTLINE = "Outline", THICKOUTLINE = "Thick Outline" },
    { "NONE", "", "OUTLINE", "THICKOUTLINE" } }
local Parts = { HUD_OUTLINES = OUTLINES }
function Parts.HudText(fs, shadow) fs.shadow = shadow; return fs end
function Parts.HudFont(fs, font, size, outline, background)
    fs:SetFont("path:" .. font, size, outline)
    fs.shadow = outline == "" and (background or "card") or false
    return fs
end
local UI = { FontPath = function(name) return "path:" .. name end }
local ns = { UIFontPath = function() return "path:" end }

local function Text()
    return {
        SetFont = function(self, path, size, flags) self.path, self.size, self.flags = path, size, flags; return true end,
        SetTextColor = function() end,
    }
end
local function Button()
    local b = { icon = { SetSize = function() end, SetVertexColor = function() end }, badge = Text() }
    function b.SetSize() end
    function b.ClearAllPoints() end
    function b.SetPoint() end
    function b.Show() end
    return b
end

local chunk = assert(loadstring(code))
local api = chunk(S, Parts, UI, ns, function(name) return { group = name } end, function() end)
local Look = api.Look
local clock, sys = Text(), Text()
local group = { SetSize = function() end }
local friends, journal = Button(), Button()
journal.badge = nil
local function Paint()
    Look.ClockFont(clock)
    Look.SystemFont(sys)
    Look.Row(group, { friends, journal }, 2)
end

Paint()
check("today's clock: its own font, no outline", clock.path == "path:Gotham Narrow Ultra" and clock.size == 27
    and clock.flags == "")
check("today's readout: the Addon Font, outlined, no shadow", sys.path == "path:" and sys.size == 13
    and sys.flags == "OUTLINE" and sys.shadow == false)
check("today's counts: the Addon Font at 10, outlined", friends.badge.path == "path:" and friends.badge.size == 10
    and friends.badge.flags == "OUTLINE" and friends.badge.shadow == false)

settings.font, settings.outline = "Expressway", "THICKOUTLINE"
Paint()
check("Font and Outline reach the readout", sys.path == "path:Expressway" and sys.flags == "THICKOUTLINE")
check("and the counts", friends.badge.path == "path:Expressway" and friends.badge.flags == "THICKOUTLINE")
check("not the clock", clock.path == "path:Gotham Narrow Ultra" and clock.flags == "" and clock.shadow == false)
settings.outline = ""
Paint()
check("Shadow: the HUD shadow on the readout and counts", sys.flags == "" and sys.shadow == "card"
    and friends.badge.shadow == "card")
settings.clockOutline, settings.sysSize = "OUTLINE", 16
Paint()
check("Clock Outline outlines the clock", clock.flags == "OUTLINE")
check("FPS / MS Size sizes the readout", sys.size == 16)

local rows, groupOf, groups, current = {}, {}, {}, nil
for _, row in ipairs(api.ROWS) do
    if row.group then
        current = row.group
        groups[#groups + 1] = current
    elseif row.key then
        rows[row.key], groupOf[row.key] = row, current
    end
end
check("the standard groups after its own", table.concat(groups, ", ")
    == "Clock, Buttons, FPS / MS, Size, Text, Background, Colours, Visibility")
check("Font, Outline and the clock's under Text", groupOf.font == "Text" and groupOf.outline == "Text"
    and groupOf.clockFont == "Text" and groupOf.clockSize == "Text" and groupOf.clockOutline == "Text"
    and groupOf.sysSize == "Text")
check("Outline is the shared choice", rows.outline.choice == OUTLINES)
check("Clock Outline is the shared choice too", rows.clockOutline.choice == OUTLINES)
check("Hide In Combat and the mouseover fade under Visibility", groupOf.hideInCombat == "Visibility"
    and groupOf.mouseover == "Visibility" and groupOf.mouseoverAlpha == "Visibility")
check("the defaults are today's look", defaults.font == "" and defaults.outline == "OUTLINE"
    and defaults.clockOutline == "NONE")

print("PASS top bar look: " .. checks .. " checks")
