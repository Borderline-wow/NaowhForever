-- Offline checks for the Default Damage Meter card's preview (NaowhForever_QoL/Combat/DamageMeterPreview.lua) against
-- recording stand-ins for frames; they do not emulate the client. Run with Lua 5.1 from the repository root.
local checks = 0
local function check(label, ok) assert(ok, label); checks = checks + 1 end

local GAME_FONT, GAME_SIZE, GAME_FLAGS = "Fonts\\ARIALN.TTF", 14, "OUTLINE"
local THEME = { bg = { r = 0.1, g = 0.1, b = 0.1 }, line = { r = 0, g = 0, b = 0 }, muted = { r = 0.6, g = 0.6, b = 0.6 },
    fg = { r = 0.9, g = 0.9, b = 0.9 }, accent = { r = 0, g = 0.5, b = 1 } }
local CLASSES = { DEATHKNIGHT = { r = 0.77, g = 0.12, b = 0.23 }, MAGE = { r = 0.41, g = 0.8, b = 0.94 },
    WARLOCK = { r = 0.58, g = 0.51, b = 0.79 }, HUNTER = { r = 0.67, g = 0.83, b = 0.45 } }

-- Frames, textures and texts that keep what is done to them.
local function Object(kind, parent)
    local o = { kind = kind, parent = parent, points = {}, alpha = 1, shown = true, level = (parent and parent.level or 0) + 1,
        scale = 1, width = 0, height = 0, vertex = { 1, 1, 1 }, children = {} }
    if parent then parent.children[#parent.children + 1] = o end
    function o:SetPoint(point, relativeTo, relativePoint, x, y)
        if type(relativeTo) == "number" then relativeTo, relativePoint, x, y = nil, nil, relativeTo, relativePoint end
        self.points[#self.points + 1] = { point, relativeTo, relativePoint, x or 0, y or 0 }
    end
    function o:ClearAllPoints() self.points = {} end
    function o:SetAllPoints()
        self.allPoints = true
        if self.parent then self.width, self.height = self.parent.width, self.parent.height end
    end
    function o:SetSize(w, h) self.width, self.height = w, h end
    function o:SetWidth(w) self.width = w end
    function o:SetHeight(h) self.height = h end
    function o:GetWidth() return self.width end
    function o:GetHeight() return self.height end
    function o:SetAlpha(a) self.alpha = a end
    function o:Show() self.shown = true end
    function o:Hide() self.shown = false end
    function o:IsVisible() return self.shown end
    function o:SetShown(on) self.shown = on and true or false end
    function o:SetFrameLevel(l) self.level = l end
    function o:GetFrameLevel() return self.level end
    function o:SetScale(s) self.scale = s end
    function o:CreateTexture() return Object("Texture", self) end
    function o:CreateFontString(_, _, template)
        local fs = Object("FontString", self)
        fs.template = template
        fs.font = { GAME_FONT, GAME_SIZE, GAME_FLAGS }
        fs.color = { 1, 0.82, 0 }
        fs.shadowOffset, fs.shadowColor = { 1, -1 }, { 0, 0, 0, 0.5 }
        return fs
    end
    function o:SetAtlas(name) self.atlas, self.file, self.solid = name, nil, nil end
    function o:SetTexture(file) self.file, self.atlas, self.solid = file, nil, nil end
    function o:SetColorTexture(r, g, b, a) self.solid, self.atlas, self.file = { r, g, b, a }, nil, nil end
    function o:SetTexCoord(...) self.coords = { ... } end
    function o:SetVertexColor(r, g, b) self.vertex = { r, g, b } end
    function o:SetDesaturated(on) self.desaturated = on end
    function o:SetFont(path, size, flags) self.font = { path, size, flags } end
    function o:GetFont() return self.font[1], self.font[2], self.font[3] end
    function o:SetText(text) self.text = text end
    function o:GetStringWidth() return self.text and #self.text * 6 or 0 end
    function o:SetTextColor(r, g, b) self.color = { r, g, b } end
    function o:GetTextColor() return self.color[1], self.color[2], self.color[3] end
    function o:SetShadowOffset(x, y) self.shadowOffset = { x, y } end
    function o:GetShadowOffset() return self.shadowOffset[1], self.shadowOffset[2] end
    function o:SetShadowColor(r, g, b, a) self.shadowColor = { r, g, b, a } end
    function o:GetShadowColor() return self.shadowColor[1], self.shadowColor[2], self.shadowColor[3], self.shadowColor[4] end
    function o:SetJustifyH() end
    function o:SetTextScale(s) self.textScale = s end
    return o
end

local layout, look = {}, nil
local function Plain()
    return { on = false, title = true, arrow = true, timer = true, session = true, cog = true, minimize = true,
        barAlpha = 1, barBackgroundAlpha = 1, titleX = 0, timerX = 0, gap = 0 }
end

local borders, timers, listeners = {}, {}, {}
local ns = { THEME = THEME, QoLSettings = { OnChange = function(fn) listeners[#listeners + 1] = fn end }, L = dofile("Tools/regression/locale_stub.lua").L,
    Shared = { Parts = {
        HudFlags = function(outline)
            if outline == "NONE" then return "" end
            return outline
        end,
        HudText = function(fs, shadow)
            if shadow == false then fs.shadowOffset, fs.shadowColor, fs.house = { 0, 0 }, { 0, 0, 0, 0 }, false
            else fs.shadowOffset, fs.shadowColor, fs.house = { 2, -2 }, { 0, 0, 0, 0.8 }, true end
        end } },
    Border = function(frame, color)
        local border = { frame = frame, color = color, _frame = Object("Frame", frame) }
        function border:SetColor(r, g, b) self.color = { r = r, g = g, b = b } end
        borders[#borders + 1] = border
        return border
    end,
    Font = function(parent) return parent:CreateFontString(nil, nil, "NoteFont") end,
    DamageMeterLayout = { byName = setmetatable({}, { __index = function(_, name)
        if layout[name] == nil then return nil end
        return { get = function() return layout[name] end }
    end }) },
    DamageMeterLook = { Describe = function() return look or Plain() end } }

local env = { ipairs = ipairs, pairs = pairs, type = type, tostring = tostring, math = math, NaowhForever = ns,
    CreateFrame = function(_, _, parent) return Object("Frame", parent) end,
    C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end },
    Enum = { DamageMeterStyle = { Default = 0, Bordered = 1, Thin = 3 } }, RAID_CLASS_COLORS = CLASSES }
env._G = env
local chunk = assert(loadfile("NaowhForever_QoL/Combat/DamageMeterPreview.lua"))
setfenv(chunk, env)
chunk("NaowhForever")

local studio = ns.DamageMeterPreview
local function Fresh(settings, picked, width)
    layout = settings or {}
    look = picked
    borders = {}
    local stage = Object("Frame")
    stage.width = width or 600
    local preview = studio.new(stage)
    studio.paint(preview, "meter")
    return preview, preview.window
end

local function Same(c, t) return c and c[1] == t.r and c[2] == t.g and c[3] == t.b end

-- the card's stage
do
    check("one state, no tabs", #studio.states == 1 and studio.states[1].key == "meter")
    check("a height for the stage, which does not change with the bars", studio.height == 220)
end

-- nothing picked: the game's own look
do
    local preview, w = Fresh({}, nil)
    check("four sample bars, one for each class", #w.entries == 4 and #w.children > 0)
    check("the title bar and window are the game's art", w.header.atlas == "ui-damagemeters-header-bar"
        and w.header.solid == nil and w.back.atlas == "damagemeters-background" and w.back.alpha == 0)
    local first = w.entries[1]
    check("the bar is the game's art in the class color", first.fill.atlas == "UI-HUD-CoolDownManager-Bar"
        and Same(first.fill.vertex, CLASSES.DEATHKNIGHT) and first.fill.alpha == 1 and first.fill.width == 272)
    check("the bar's shadow and edge are the game's", first.shadow.atlas == "ui-damagemeters-bar-shadowbg"
        and first.shadow.alpha == 1 and first.edge.atlas == "ui-damagemeters-bar-shadowedge" and first.edge.alpha == 1
        and first.edge.shown == true)
    check("the others are shorter, each in its class color", w.entries[2].fill.width < first.fill.width
        and w.entries[4].fill.width < w.entries[3].fill.width and Same(w.entries[2].fill.vertex, CLASSES.MAGE)
        and Same(w.entries[4].fill.vertex, CLASSES.HUNTER))
    check("the texts keep the game's face, size and color", first.name.font[1] == GAME_FONT and first.name.font[2] == GAME_SIZE
        and first.name.font[3] == GAME_FLAGS and first.name.color[2] == 0.82 and first.value.font[1] == GAME_FONT
        and w.title.font[1] == GAME_FONT and first.name.text == "1. Aldric" and first.value.text == "5,214 (8.7)")
    check("the game's shadow is given back", first.name.shadowOffset[1] == 1 and first.name.shadowOffset[2] == -1)
    check("no border: the window's, the icons'", w.border._frame.shown == false and first.iconEdge._frame.shown == false)
    check("the buttons are as they are, none hidden", w.minimize.alpha == 1 and w.cog.alpha == 1 and w.session.alpha == 1
        and w.arrow.alpha == 1 and w.timer.alpha == 1 and w.title.alpha == 1 and w.cog.texture.desaturated == false
        and Same(w.cog.texture.vertex, { r = 1, g = 1, b = 1 }))
    check("the title after the arrow's art, the arrow after the timer", w.title.points[1][2] == w.arrow.texture
        and w.title.points[1][3] == "RIGHT" and w.title.points[1][4] == 0 and w.arrow.points[1][4] > 1)
    check("the buttons are the game's own art", w.arrow.texture.atlas == "common-dropdown-a-button-shadowless"
        and w.cog.texture.atlas == "common-dropdown-a-button-settings-shadowless"
        and w.session.texture.atlas == "common-dropdown-c-button"
        and w.minimize.texture.atlas == "ui-questtrackerbutton-collapse-all")
    check("each at its own size, the game's anchors: the mode button after the timer, the others from the right",
        w.arrow.width == 25 and w.cog.width == 27 and w.session.width == 18 and w.minimize.width == 18
        and w.cog.points[1][2] == w.minimize and w.session.points[1][2] == w.cog and w.session.points[1][5] == 3
        and w.arrow.points[1][5] == -3)
    check("the session's box reaches beyond its frame as the game's does", w.session.texture.points[1][4] == -7
        and w.session.texture.points[2][4] == 7)
    check("a note under it, and the window at the top", preview.note.text == "A sample: the meter in the game shows your fights."
        and w.points[1][1] == "TOP" and w.scale == 1)
end

-- picks
do
    local red, grey, green = { r = 0.9, g = 0.1, b = 0.1 }, { r = 0.4, g = 0.4, b = 0.4 }, { r = 0.1, g = 0.9, b = 0.1 }
    local _, w = Fresh({ BackgroundTransparency = 60, Transparency = 80 }, { on = true, title = true, arrow = true,
        timer = true, session = true, cog = true, minimize = true, titleX = 0, timerX = 0, gap = 0,
        header = red, window = grey, barBackground = green, barBackgroundAlpha = 0.5,
        barTexture = "Media\\Gradient.tga", barColor = THEME.accent, barAlpha = 0.6, font = "Fonts\\Exo.ttf",
        outline = "THICKOUTLINE", nameColor = red, nameSize = 18, valueColor = green, valueSize = 10, titleColor = grey,
        titleSize = 20, iconBorder = grey, border = red, buttons = green })
    local first = w.entries[1]
    check("a title bar color and a window color, as solid as the background setting", Same(w.header.solid, red)
        and Same(w.back.solid, grey) and w.back.alpha == 0.6 and w.alpha == 0.8)
    check("a bar texture, a bar color and an opacity", first.fill.file == "Media\\Gradient.tga" and first.fill.atlas == nil
        and Same(first.fill.vertex, THEME.accent) and first.fill.alpha == 0.6)
    check("a color behind each bar, and the game's edge gone", Same(first.shadow.solid, green) and first.shadow.alpha == 0.5
        and first.edge.alpha == 0)
    check("a font, an outline and no shadow", first.name.font[1] == "Fonts\\Exo.ttf" and first.name.font[3] == "THICKOUTLINE"
        and first.name.shadowOffset[1] == 0 and first.name.house == false)
    check("a size and a color for each text", first.name.font[2] == 18 and Same(first.name.color, red)
        and first.value.font[2] == 10 and Same(first.value.color, green) and w.title.font[2] == 20
        and Same(w.title.color, grey))
    check("the borders: the window's and each icon's", w.border._frame.shown == true and Same({ w.border.color.r,
        w.border.color.g, w.border.color.b }, red) and first.iconEdge._frame.shown == true
        and Same({ first.iconEdge.color.r, first.iconEdge.color.g, first.iconEdge.color.b }, grey))
    check("themed buttons: grey, in the button color, and the session's letter", w.cog.texture.desaturated == true
        and Same(w.cog.texture.vertex, green) and Same(w.minimize.texture.vertex, green)
        and Same(w.arrow.texture.vertex, green) and Same(w.session.letter.color, green))
    check("the face is remembered: it is not read back from a text it dressed", first.name.game.path == GAME_FONT)
end

-- the title bar's parts
do
    local _, w = Fresh({}, { on = true, title = false, arrow = false, timer = false, session = false, cog = false,
        minimize = false, titleX = 10, timerX = 7, gap = 0, barAlpha = 1, barBackgroundAlpha = 1 })
    check("each part switched off is see-through", w.title.alpha == 0 and w.arrow.alpha == 0 and w.timer.alpha == 0
        and w.session.alpha == 0 and w.cog.alpha == 0 and w.minimize.alpha == 0)
    check("a hidden timer is one pixel wide for the arrow", w.arrow.points[1][4] == 2)
    check("the offsets move the title and the timer", w.title.points[1][4] == 10 and w.timer.points[1][4] == 8)
    local _, shown = Fresh({}, { on = true, title = true, arrow = true, timer = true, session = true, cog = true,
        minimize = true, titleX = 10, timerX = 0, gap = 4, barAlpha = 1, barBackgroundAlpha = 1 })
    check("the gap off the arrow is added to the title's offset", shown.title.points[1][4] == 14)
    check("and a shown timer is as wide as its text, with the arrow after it", shown.arrow.points[1][4] > 2)
end

-- the game's own settings: the window, the bars, the text
do
    local _, w = Fresh({ FrameWidth = 400, BarHeight = 30, Padding = 6, ShowSpecIcon = false, ShowClassColor = false,
        TextSize = 120 }, nil)
    local first, second = w.entries[1], w.entries[2]
    check("the width and a bar's height", w.width == 400 and first.width == 400 and first.height == 30)
    check("the spacing between the bars", second.points[1][5] == first.points[1][5] - 36)
    check("no icons: the bar starts at the edge", first.iconFrame.shown == false and first.bar.points[1][2] == first)
    check("no class color: the game's default bar color", first.fill.vertex[1] == 0.78)
    check("the text size", first.name.textScale == 1.2)
    local _, bordered = Fresh({ Style = tostring(1) }, nil)
    check("the bordered style: its own shadow art, no edge, the bar kept off the icon",
        bordered.entries[1].shadow.atlas == "UI-HUD-CoolDownManager-Bar-BG" and bordered.entries[1].edge.shown == false
        and bordered.entries[1].bar.points[1][4] == 5)
    local _, thin = Fresh({ Style = tostring(3) }, nil)
    check("the thin style: the bar under the name", thin.entries[1].bar.points[2][1] == "TOP"
        and thin.entries[1].bar.points[2][2] == thin.entries[1].name)
    local _, small = Fresh({ FrameWidth = 600 }, nil, 300)
    check("a window wider than the stage is scaled down to it", small.scale < 1 and small.scale == 272 / 600)
end

-- the preview paints itself when a setting changes, as the page is not drawn again for every one
do
    layout, look = {}, nil
    local stage = Object("Frame")
    stage.width = 600
    local preview = studio.new(stage)
    studio.paint(preview, "meter")
    local w = preview.window
    check("it listens to the card's store, and the game's settings tell it too", #listeners == 1
        and type(studio.Refresh) == "function")
    timers = {}
    layout.BarHeight, layout.Padding = 30, 6
    listeners[1]()
    listeners[1]()
    studio.Refresh()
    check("a change is one repaint, a frame later", #timers == 1 and w.entries[1].height == 24)
    timers[1]()
    check("which has the new bar height and spacing", w.entries[1].height == 30
        and w.entries[2].points[1][5] == w.entries[1].points[1][5] - 36)
    timers = {}
    layout.BarHeight = 40
    studio.Refresh()
    preview:Hide()
    timers[1]()
    check("a preview that is not shown is left as it is", w.entries[1].height == 30)
    timers = {}
    studio.Refresh()
    check("and is not asked to repaint: no timer for a setting changed anywhere else", #timers == 0)
    preview:Show()
    timers = {}
    layout.BarHeight, layout.Padding = 40, 10
    studio.Refresh()
    timers[1]()
    check("shown again, it repaints, and a tall window is scaled down to the stage", w.entries[1].height == 40
        and w.scale < 1 and w.height * w.scale <= 220 - 28 - 20 + 0.001)
end

-- repainting
do
    layout, look = {}, nil
    local stage = Object("Frame")
    stage.width = 600
    local preview = studio.new(stage)
    local frames = #stage.children + #preview.children + #preview.window.children
    look = { on = true, title = true, arrow = true, timer = true, session = true, cog = true, minimize = true,
        titleX = 0, timerX = 0, gap = 0, barAlpha = 1, barBackgroundAlpha = 1, font = "Fonts\\Exo.ttf" }
    studio.paint(preview, "meter")
    local created = #borders
    look.font = nil
    studio.paint(preview, "meter")
    studio.paint(preview, "meter")
    check("painting again makes nothing new", #borders == created and #preview.window.children + #preview.children
        + #stage.children == frames)
    check("and the game's face is given back when the pick goes", preview.window.entries[1].name.font[1] == GAME_FONT)
end

print("PASS damage meter preview: " .. checks .. " checks")
