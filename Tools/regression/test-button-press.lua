-- The flat hover and pressed look on the bars' buttons (Parts.Press, Parts.Hover): a faint white
-- hover and a black press, both inside the 1px black edge and no game texture, the pushed one over
-- the icon, a down click pushes the button and an up click lets it go, and every bar's buttons go
-- through it after their OnClick is set. Run with Lua 5.1 from the repo root.
local checks = 0
local function check(label, ok) assert(ok, label); checks = checks + 1 end

local inset, made = {}, 0
local function Texture()
    local t = {}
    function t:SetColorTexture(r, g, b, a) self.rgba = { r, g, b, a } end
    function t:SetBlendMode(mode) self.blend = mode end
    function t:SetDrawLayer(layer, sublevel) self.layer, self.sublevel = layer, sublevel end
    return t
end
local ns = { THEME = { fg = { r = 1, g = 1, b = 1 } }, L = function(s) return s end,
    Solid = function(_, layer) made = made + 1; local t = Texture(); t.layer = layer; return t end,
    PixelInset = function(region, n) inset[region] = n end }
ns.Shared = { Style = dofile("Tools/regression/shared_style.lua"), Parts = {} }
local env = setmetatable({ NaowhForever = ns }, { __index = _G })
env._G = env
local chunk = assert(loadfile("Shared/UI/Parts.lua"))
setfenv(chunk, env)
chunk()
local Parts = ns.Shared.Parts

local function Button()
    local b = { hooks = {} }
    function b:SetHighlightTexture(t) self.highlight = t end
    function b:GetHighlightTexture() return self.highlight end
    function b:SetPushedTexture(t) self.pushed = t end
    function b:GetPushedTexture() return self.pushed end
    function b:SetButtonState(state) self.state = state end
    function b:HookScript(name, fn) self.hooks[name] = fn end
    return b
end

local button = Button()
Parts.Press(button)
local hover, pushed = button.highlight, button.pushed
check("hover is a faint flat white", hover.rgba[1] == 1 and hover.rgba[4] > 0 and hover.rgba[4] < 0.5
    and hover.blend == "BLEND")
check("pressed is a flat black shade, darker than the hover", pushed.rgba[1] == 0 and pushed.rgba[3] == 0
    and pushed.rgba[4] > hover.rgba[4] and pushed.blend == "BLEND")
check("both sit inside the 1px black edge", inset[hover] == 1 and inset[pushed] == 1)
check("the pushed look draws over the icon", pushed.layer == "ARTWORK" and pushed.sublevel == 1)
check("one texture each", made == 2)

local plain = Button()
Parts.Hover(plain)
check("a button that is never pressed gets the same hover", made == 3 and plain.highlight.rgba[4] == hover.rgba[4]
    and inset[plain.highlight] == 1 and plain.pushed == nil)
Parts.Hover(plain)
check("its hover is made once", made == 3)
button.hooks.OnClick(button, "LeftButton", true)
check("a key or mouse down pushes the button", button.state == "PUSHED")
button.hooks.OnClick(button, "LeftButton", false)
check("letting go releases it", button.state == "NORMAL")

local function Source(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a")
    f:close()
    return s
end
local parts = Source("Shared/UI/Parts.lua")
check("no game glow or depress is left", not parts:find("ButtonHilight", 1, true)
    and not parts:find("Quickslot", 1, true))
for path, count in pairs({ ["Shared/UI/ItemBar.lua"] = 1, ["NaowhForever_Combat/Blessings/UI/Recipient.lua"] = 1,
    ["NaowhForever_Combat/Blessings/UI/Bar.lua"] = 1, ["NaowhForever_Combat/GearSets/UI/Bar.lua"] = 1,
    ["NaowhForever_Combat/GearSets/UI/TrinketBar.lua"] = 2, ["NaowhForever_QoL/Questing/GroupButtons.lua"] = 1 }) do
    local source = Source(path)
    local _, found = source:gsub("Parts%.Press%(", "")
    check(path .. " dresses its buttons with Parts.Press", found == count)
    for at, name in source:gmatch("()Parts%.Press%(([%w_.]+)%)") do
        local rest = source:sub(at, (source:find("\nend", at, true)))
        check(path .. " sets no OnClick over the hook after Parts.Press(" .. name .. ")",
            not rest:find(name .. ':SetScript("OnClick"', 1, true))
    end
end

print("test-button-press: " .. checks .. " checks passed")
