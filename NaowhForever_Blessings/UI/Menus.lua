-- Menus.lua: the right-click menus: a class's blessing, your aura, a player's own blessing, and your plan's setter.
local ns = _G.NaowhForever

local B = ns.Blessings
local BLESSINGS, AURAS = B.BLESSINGS, B.AURAS
local Store, Learned, SpellName, ClassName = B.Store, B.Learned, B.SpellName, B.ClassName

local AURA_COLUMN = B.AURA_COLUMN
local TEXT_AURA, TEXT_DEFAULT, TEXT_NONE = "Aura", "Default", "None"
local TEXT_PLAYERS, TEXT_ASSIGNMENTS = "Players", "Assignments"

local function OwnAura()
    return Store().aura
end

local function OpenWindow()
    ns.OpenBlessingsWindow()
end

function B.SetOwn(column, key)
    local store = Store()
    if column == AURA_COLUMN then store.aura = key else store.classes[column] = key end
    B.BroadcastSoon()
    B.Changed()
end

function B.OpenMenu(owner, title, list, current, choose, noneText, can)
    can = can or Learned
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(title)
        for _, entry in ipairs(list) do
            if can(entry) then
                root:CreateRadio(SpellName(entry.key), function() return current() == entry.key end,
                    function() choose(entry.key) end)
            end
        end
        root:CreateRadio(noneText, function() return current() == nil end, function() choose(nil) end)
    end)
end

local function SetAura(key)
    B.SetOwn(AURA_COLUMN, key)
end

function B.AuraMenu(owner)
    B.OpenMenu(owner, TEXT_AURA, AURAS, OwnAura, SetAura, TEXT_DEFAULT)
end

function B.ClassMenu(owner, class, inSettings)
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(ClassName(class))
        for _, entry in ipairs(BLESSINGS) do
            if Learned(entry) then
                root:CreateRadio(SpellName(entry.key), function() return Store().classes[class] == entry.key end,
                    function() B.SetOwn(class, entry.key) end)
            end
        end
        root:CreateRadio(TEXT_NONE, function() return Store().classes[class] == nil end,
            function() B.SetOwn(class, nil) end)
        root:CreateDivider()
        if not inSettings then
            root:CreateCheckbox(TEXT_PLAYERS, function() return B.PlayerList.Showing() == class end,
                function() B.PlayerList.Toggle(class) end)
        end
        root:CreateButton(TEXT_ASSIGNMENTS, OpenWindow)
    end)
end
