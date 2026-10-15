-- The game's hover glow and pressed look on the bars' buttons (Parts.Press): the glow and pushed
-- textures are set, the pushed one draws over the icon, a down click pushes the button and an up
-- click lets it go, and every bar's buttons go through it after their OnClick is set. Run with
-- Lua 5.1 from the repo root.
local checks = 0
local function check(label, ok) assert(ok, label); checks = checks + 1 end

local ns = { THEME = {}, L = function(s) return s end }
ns.Shared = { Style = dofile("Tools/regression/shared_style.lua"), Parts = {} }
local env = setmetatable({ NaowhForever = ns }, { __index = _G })
env._G = env
local chunk = assert(loadfile("Shared/UI/Parts.lua"))
setfenv(chunk, env)
chunk()
local Parts = ns.Shared.Parts

local function Button()
    local b = { hooks = {} }
    local pushed = { SetDrawLayer = function(self, layer, sublevel) self.layer, self.sublevel = layer, sublevel end }
    function b:SetHighlightTexture(path, blend) self.highlight, self.blend = path, blend end
    function b:SetPushedTexture(path) self.pushedPath = path end
    function b:GetPushedTexture() return pushed end
    function b:SetButtonState(state) self.state = state end
    function b:HookScript(name, fn) self.hooks[name] = fn end
    b.pushedTexture = pushed
    return b
end

local button = Button()
Parts.Press(button)
check("the glow is the game's square highlight, added", button.highlight == "Interface\\Buttons\\ButtonHilight-Square"
    and button.blend == "ADD")
check("the pushed look is the game's quickslot depress", button.pushedPath == "Interface\\Buttons\\UI-Quickslot-Depress")
check("the pushed look draws over the icon", button.pushedTexture.layer == "ARTWORK" and button.pushedTexture.sublevel == 1)
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
