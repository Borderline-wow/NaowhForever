-- Keys.lua: the key that uses each entry on the Consumable Bar: its own button's binding, or an action button holding it or its macro.
local ns = _G.NaowhForever

local CB = ns.ConsumableBar
local S = CB.S
local ActionKeys = ns.Shared.ActionKeys

local function MacroNamed(name)
    if not ns.ConsumableMacros then return end
    if not name then return end
    for key, info in pairs(ns.ConsumableMacros) do
        if info.name == name then return CB.MacroEntry(key) end
    end
end

function CB.EntryOf(kind, id)
    if kind == "item" and type(id) == "number" then return id end
    if kind == "macro" and type(id) == "number" then return MacroNamed(GetMacroInfo(id)) end
end

local function SlotEntry(slot)
    local kind, id = GetActionInfo(slot)
    if kind == "macro" then return MacroNamed(GetActionText(slot)) end
    return CB.EntryOf(kind, id)
end

local function EntryOfSlot(slot, item)
    if slot then return SlotEntry(slot) end
    return item
end

local keyMap = ActionKeys.NewMap(EntryOfSlot)

local function OwnBindings(keys)
    for _, entry in ipairs(CB.Items()) do
        keys[entry] = ActionKeys.Bound(CB.BindAction(entry))
    end
end

function CB.KeyMap()
    if not S.Get("consumableBarKeybinds") then return keyMap.Clear() end
    return keyMap.Read(OwnBindings)
end

function CB.KeyFor(cell, map)
    return cell.entry ~= nil and (map[cell.entry] or (cell.itemID and map[cell.itemID])) or nil
end
