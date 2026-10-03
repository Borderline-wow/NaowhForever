-- Settings > COLORS section: the Theme dropdown, the Reset button, the Custom swatches, and
-- when the "Reload UI" hint shows. The section is sliced out of Window.lua and run against the
-- real Core; running it again on the same environment stands in for a page rebuild. Run from
-- the repository root.
local function Read(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a"):gsub("\r\n", "\n"); f:close()
    return s
end
local coreSource = Read("Core/NaowhForever_Core.lua")
local source = Read("Core/NaowhForever_Window.lua")
local first = assert(source:find('_, h = W:SectionHeader(parent, "COLORS", y)', 1, true))
local last = assert(source:find('_, h = W:ReloadButton(parent, y)', first, true))
local section = source:sub(first, last - 1)
local chunk = assert(loadstring("local parent, y = ...; local _, h; " .. section .. " return y"))

-- The pending flag has to outlive a rebuild, so it lives at file scope, above the builder.
local flag = assert(source:find("\nlocal colorsPending = false\n", 1, true))
assert(flag < assert(source:find("function ns.BuildSettingsPage", 1, true)), "flag is file scope")

local HINT = "Reload UI to apply your color changes."
local cases = 0
local function Check(ok, label) assert(ok, label); cases = cases + 1 end
Check(not section:find("ReloadUI", 1, true), "the section never calls ReloadUI itself")

local function RealCore(account)
    local frame = setmetatable({}, { __index = function() return function() end end })
    function frame:SetScript() end
    local env = { CreateFrame = function() return frame end,
        NaowhForeverDB = { account = account, profiles = {}, charActive = {} } }
    env._G = env
    setmetatable(env, { __index = _G })
    local core = assert(loadstring(coreSource, "Core"))
    setfenv(core, env)
    core("NaowhForever")
    return env.NaowhForever
end

local function Page(account)
    local e = { confirms = {}, refreshes = 0, account = account }
    local ns = RealCore(account)
    ns.Confirm = function(text, onYes) e.confirms[#e.confirms + 1] = { text = text, yes = onYes } end
    local env = { ns = ns, W = {}, colorsPending = false,
        UI = { RefreshPage = function() e.refreshes = e.refreshes + 1 end } }
    function env.W:SectionHeader() return nil, 0 end
    function env.W:DualRow(_, _, left, right)
        e.rows[#e.rows + 1] = { left, right }
        return nil, 0
    end
    function env.W:Note(_, text)
        e.notes[#e.notes + 1] = text
        return nil, 0
    end
    setmetatable(env, { __index = _G })
    setfenv(chunk, env)
    function e.build()
        e.rows, e.notes = {}, {}
        chunk({}, 0)
        e.theme = e.rows[1][1]
    end
    e.build()
    return e
end
local function Texts(e)
    local out = {}
    for i = 3, #e.rows do
        for _, cfg in ipairs(e.rows[i]) do if cfg.text ~= "" then out[#out + 1] = cfg.text end end
    end
    return out
end

-- The dropdown: Naowh (default) first, the presets, Custom last.
do
    local e = Page({})
    local t = e.theme
    Check(t.type == "dropdown" and t.text == "Theme", "a Theme dropdown")
    Check(t.order[1] == "" and t.values[""] == "Naowh (default)", "the default comes first")
    Check(t.order[#t.order] == "custom" and t.values.custom == "Custom", "Custom comes last")
    local names = {}
    for i = 2, #t.order - 1 do names[#names + 1] = t.values[t.order[i]] end
    Check(table.concat(names, ",") == "Midnight,Slate,Obsidian,Aubergine,Forest,Crimson,Rose Noir,Cotton Candy", "the presets in order")
    Check(#t.order == 10, "ten options")
    Check(t.getValue() == "", "the default is selected when nothing is saved")
    for _, word in ipairs({ "Theme presets", "windows and HUD frames", "Custom", "Naowh (default)", "/reload" }) do
        Check(t.tooltip:find(word, 1, true), "tooltip mentions " .. word)
    end
    Check(e.rows[1][2].type == "palette" and #e.rows[1][2].colors() == 6, "a six-chip preview beside the Theme dropdown")
    Check(not t.tooltip:find("Reset", 1, true), "no reset any more")
end

-- Swatches show for Custom and for nothing else.
do
    Check(#Page({}).rows == 1, "no swatches for the default theme")
    for _, key in ipairs({ "midnight", "slate", "obsidian", "aubergine", "forest", "crimson", "rosenoir", "cottoncandy" }) do
        local e = Page({ themePreset = key })
        Check(#e.rows == 1 and e.theme.getValue() == key, "no swatches for " .. key)
    end
    for _, bad in ipairs({ "bogus", "order", 5 }) do
        local e = Page({ themePreset = bad })
        Check(#e.rows == 1 and e.theme.getValue() == "", "an invalid preset reads as the default, no swatches")
    end
    local e = Page({ themePreset = "custom" })
    Check(#e.rows == 5, "Custom shows the Start From row and three swatch rows")
    Check(e.rows[2][1].text == "Start From" and e.rows[2][1].type == "dropdown", "the Start From dropdown")
    Check(table.concat(Texts(e), ",") == "Background,Panels,Borders & Lines,Text,Secondary Text,Accent",
        "the six swatches, in order")
    for i = 3, 5 do
        for _, cfg in ipairs(e.rows[i]) do
            if cfg.text ~= "" then Check(cfg.type == "colorpicker" and cfg.hasAlpha == false, cfg.text .. " is a swatch") end
        end
    end
    Check(#Page({}).notes == 0, "no hint before any change")
end

-- Picking from the dropdown redraws the page and brings the hint up, with no dialog.
do
    local a = {}
    local e = Page(a)
    e.theme.setValue("midnight")
    Check(a.themePreset == "midnight" and e.refreshes == 1 and #e.confirms == 0, "a preset is stored and the page redraws")
    e.build()
    Check(#e.notes == 1 and e.notes[1] == HINT and #e.rows == 1, "the hint shows, still no swatches")
    e.theme.setValue("")
    e.build()
    Check(a.themePreset == nil and #e.notes == 1, "the default is stored as nothing, and the hint stays")
end

-- Custom starts from the palette the player was looking at, and only then shows swatches.
do
    local a = { themePreset = "slate" }
    local e = Page(a)
    e.theme.setValue("custom")
    Check(a.themePreset == "custom" and a.themeColors.bg.r == 0x12 / 255, "Custom is prefilled from the selected preset")
    e.build()
    Check(#e.rows == 5 and #e.notes == 1, "the swatches appear once Custom is selected")
    local bg = e.rows[3][1]
    local r = bg.getValue()
    Check(r == 0x12 / 255, "the swatch shows the prefilled color")
end

-- A swatch drag calls setValue on every tick: one redraw, never a dialog.
do
    local a = { themePreset = "custom", themeColors = { bg = { r = 0.1, g = 0.1, b = 0.1 } } }
    local e = Page(a)
    local swatch = e.rows[3][1]
    Check(#e.notes == 0, "no hint before a swatch changes")
    for i = 1, 50 do swatch.setValue(i / 50, 0, 0) end
    Check(e.refreshes == 1, "only the first tick redraws the page")
    Check(#e.confirms == 0, "dragging never opens a dialog")
    Check(a.themeColors.bg.r == 1, "the last pick is saved")
    e.build()
    Check(#e.notes == 1 and e.notes[1] == HINT, "hint shows after a swatch change")
end

-- Start From: an action that always reads the placeholder, asks first, then replaces the picks.
do
    local a = { themePreset = "custom", themeColors = { bg = { r = 1, g = 0, b = 0 } } }
    local e = Page(a)
    local start = e.rows[2][1]
    Check(start.order[1] == "" and start.values[""] == "Choose a theme...", "the placeholder comes first")
    Check(start.order[2] == "default" and start.values.default == "Naowh (default)", "the default is offered")
    Check(#start.order == 10 and start.values.custom == nil, "the eight presets, and not Custom itself")
    Check(start.getValue() == "", "it always shows the placeholder")
    start.setValue("")
    Check(#e.confirms == 0, "the placeholder does nothing")
    start.setValue("slate")
    Check(#e.confirms == 1 and e.confirms[1].text == "Replace your custom colors with Slate?", "it asks first")
    Check(a.themeColors.bg.r == 1 and e.refreshes == 0, "nothing is replaced before Yes")
    e.build()
    Check(#e.notes == 0, "no hint if it is declined")
    e.confirms[1].yes()
    Check(a.themePreset == "custom" and a.themeColors.bg.r == 0x12 / 255 and e.refreshes == 1,
        "Yes replaces the picks with Slate's and redraws")
    Check(#e.confirms == 1, "no second dialog")
    e.build()
    Check(#e.notes == 1 and e.notes[1] == HINT, "the hint shows")
    start.setValue("default")
    e.confirms[2].yes()
    Check(a.themeColors.bg.r == 0x0e / 255 and a.themeColors.accent.b == 0xed / 255, "the default theme's colors")
end

-- The preview follows the selection.
do
    local function Chips(account) return Page(account).rows[1][2].colors() end
    local function Hex(c)
        return ("%02x%02x%02x"):format(math.floor(c.r * 255 + 0.5), math.floor(c.g * 255 + 0.5), math.floor(c.b * 255 + 0.5))
    end
    local default, midnight = Chips({}), Chips({ themePreset = "midnight" })
    Check(Hex(default[1]) == "0e0f11" and Hex(default[6]) == "0091ed", "default: the shipped background and accent")
    Check(Hex(midnight[1]) == "0b1020" and Hex(midnight[4]) == "eef2ff" and Hex(midnight[6]) == "5b8cff",
        "a preset: its own background, text and accent")
    local custom = Chips({ themePreset = "custom", themeColors = { bg = { r = 1, g = 0, b = 0 } } })
    Check(Hex(custom[1]) == "ff0000" and Hex(custom[2]) == "1a1c1f", "custom: the saved pick, the shipped color for the rest")
    local invalid = Chips({ themePreset = "bogus" })
    Check(Hex(invalid[1]) == "0e0f11", "an invalid preset previews the default")
end

-- The chips themselves: the control is cut out of Widgets.lua and run with stub frames.
do
    local widgets = Read("Core/NaowhForever_Widgets.lua")
    local from = assert(widgets:find('    elseif cfg.type == "palette" then', 1, true))
    local upTo = assert(widgets:find('    elseif cfg.type == "colorpicker" then', from, true))
    local branch = widgets:sub(from, upTo - 1):gsub('^    elseif cfg%.type == "palette" then', "")
    local code = "local cfg, rgn = ...\n" .. branch
    local paletteChunk = assert(loadstring(code))
    local frames, painted = {}, {}
    local function Frame()
        local f = { shown = true }
        function f.Show() f.shown = true end
        function f.Hide() f.shown = false end
        frames[#frames + 1] = f
        return setmetatable(f, { __index = function() return function() end end })
    end
    local function Build(colors)
        frames, painted = {}, {}
        local count = 0
        local env = { CreateFrame = Frame, T = { bg = {}, muted = {} },
            ns = { Solid = function()
                count = count + 1
                local index = count
                return { SetAllPoints = function() end,
                    SetColorTexture = function(_, r, g, b, a) painted[index] = { r, g, b, a } end }
            end, Border = function() end } }
        setfenv(paletteChunk, setmetatable(env, { __index = _G }))
        local cfg = { colors = colors }
        local control = paletteChunk(cfg, Frame())
        return control, cfg
    end
    local function Shown()
        local n = 0
        for i = 3, #frames do if frames[i].shown then n = n + 1 end end
        return n
    end
    local function List(count, r)
        local out = {}
        for i = 1, count do out[i] = { r = r, g = 0, b = 0 } end
        return out
    end
    local control, cfg = Build(function() return List(6, 1) end)
    Check(#frames == 8 and control._refreshValue, "the rgn, one frame for the row of chips and one for each chip")
    Check(#painted == 6 and painted[1][1] == 1 and painted[6][4] == 1, "every chip is painted from cfg.colors()")
    cfg.colors = function() return List(2, 0.5) end
    control._refreshValue()
    Check(painted[1][1] == 0.5 and painted[2][1] == 0.5 and painted[3][1] == 1, "a refresh repaints from the current colors")
    Check(#frames == 8 and Shown() == 2, "fewer colors hide the extra chips and build nothing")
    cfg.colors = function() return List(8, 0.25) end
    control._refreshValue()
    Check(#frames == 10 and Shown() == 8 and #painted == 8 and painted[8][1] == 0.25, "more colors build only the missing chips and show them all")
    Check(Build(function() return List(3, 1) end) and #frames == 5 and Shown() == 3, "one chip per color from the start")
    Check(Build(function() return {} end) and #frames == 2 and Shown() == 0, "no colors, no chips")
end

print("PASS custom colors page: " .. cases .. " checks")
