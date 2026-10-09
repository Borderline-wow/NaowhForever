-- Capture.lua: the bars, macros and keybinds as they are now, read into a set, and the macros this character has (ns.ActionBars.Capture).
local ns = _G.NaowhForever

local A = ns.ActionBars
local C = A.C

local KEYBOARD_SLOTS = C.KEYBOARD_SLOTS

local function Slots()
    local list = {}
    for slot = 1, KEYBOARD_SLOTS do list[#list + 1] = slot end
    local slot = math.max(C_GamepadUI.GetFirstGamepadActionStorageSlotIndex(), KEYBOARD_SLOTS + 1)
    while C_GamepadUI.IsValidGamepadActionStorageSlotIndex(slot) do
        list[#list + 1] = slot
        slot = slot + 1
    end
    return list
end

local function FirstCharacterMacro()
    return Constants.MacroConsts.MAX_ACCOUNT_MACROS
end

local function MacroIndices()
    local account, character = GetNumMacros()
    local list = {}
    for i = 1, account do list[#list + 1] = i end
    local first = FirstCharacterMacro()
    for i = first + 1, first + character do list[#list + 1] = i end
    return list
end

local function Body(body)
    return strtrim(((body or ""):gsub("\r", "")))
end

local function MacroKey(name, body)
    return name .. "\n" .. Body(body)
end

local function MacroIndex()
    local index = { text = {}, body = {} }
    for _, i in ipairs(MacroIndices()) do
        local name, _, body = GetMacroInfo(i)
        if name then
            local key, text = MacroKey(name, body), Body(body)
            index.text[key] = index.text[key] or i
            if text ~= "" then index.body[text] = index.body[text] or i end
        end
    end
    return index
end

local function Lookup(index, macro)
    local text = Body(macro.body)
    return index.text[MacroKey(macro.name, macro.body)] or (text ~= "" and index.body[text]) or nil
end

local function MacroSlot(slot)
    local name = C_ActionBar.GetActionText(slot)
    local index = name and GetMacroIndexByName(name) or 0
    if index <= 0 then return nil end
    local _, icon, body = GetMacroInfo(index)
    return { kind = "macro", name = name, icon = icon, body = body, perCharacter = index > FirstCharacterMacro() }
end

local function CaptureSlot(slot)
    local kind, id = GetActionInfo(slot)
    if kind == "spell" then return { kind = "spell", id = id, name = C_Spell.GetSpellName(id) } end
    if kind == "macro" then return MacroSlot(slot) end
    if kind then return { kind = kind, id = id } end
end

local function Capture()
    local slots = {}
    for _, slot in ipairs(Slots()) do slots[slot] = CaptureSlot(slot) end
    return slots
end

local function CaptureMacros()
    local macros = {}
    local first = FirstCharacterMacro()
    for _, i in ipairs(MacroIndices()) do
        local name, icon, body = GetMacroInfo(i)
        if name then
            macros[#macros + 1] = { name = name, icon = icon, body = body, perCharacter = i > first }
        end
    end
    return macros
end

local function CaptureBindings()
    local bindings = {}
    for i = 1, GetNumBindings() do
        local command, _, key1, key2 = GetBinding(i)
        if key1 then bindings[key1] = command end
        if key2 then bindings[key2] = command end
    end
    return bindings
end

local function KeptMacros(slots, macros, choices)
    local onBars, kept = {}, {}
    for _, entry in pairs(slots) do
        if entry.kind == "macro" then onBars[MacroKey(entry.name, entry.body)] = true end
    end
    for _, macro in ipairs(macros) do
        local key = MacroKey(macro.name, macro.body)
        if onBars[key] or (choices.macros ~= false and not choices.macroOff[key]) then
            kept[#kept + 1] = macro
        end
    end
    return kept
end

local function Snapshot(choices)
    local slots, macros, bindings = Capture(), CaptureMacros(), CaptureBindings()
    if choices then
        for slot in pairs(choices.skip) do slots[slot] = nil end
        macros = KeptMacros(slots, macros, choices)
        if not choices.keys then bindings = nil end
    end
    return { saved = time(), by = UnitName("player"), slots = slots, macros = macros, bindings = bindings,
        choices = choices }
end

A.Capture = { Slots = Slots, Body = Body, MacroKey = MacroKey, MacroIndex = MacroIndex, Lookup = Lookup,
    Capture = Capture, CaptureMacros = CaptureMacros, CaptureBindings = CaptureBindings, Snapshot = Snapshot }
