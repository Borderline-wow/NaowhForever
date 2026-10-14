-- Run with Lua 5.1 from the repository root: the HUD Editor on the Forever skin. Its toolbar and
-- Elements panel wear the game's bare metal frame with the title on the bar and the red close
-- button (the toolbar's closes the HUD Editor); every button is the red button, one height, with
-- the disabled art on Undo, Redo and Revert when there is nothing to take back and the pressed art
-- on Elements while the list is open; Layouts is a dropdown with the layouts and their actions;
-- each mover wears Edit Mode's selection (blue highlight, yellow when picked, the highlight again
-- under the mouse), made only once the HUD Editor opens; the list's groups are list bars that
-- fold; guides are lighter. Without the art every part is drawn, and Naowh and Classic+ are as before.
local checks = 0
local function check(label, value) assert(value, label); checks = checks + 1 end

local function Read(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a"); f:close()
    return s
end

local ATLAS_W, ATLAS_H = 64, 32
local SCREEN_W, SCREEN_H = 1920, 1080
local present, missingFiles, atlasCalls, layouts, applied
local frames, timers, opened, prompt

local function New(kind, parent)
    local o = { kind = kind, parent = parent, points = {}, scripts = {}, events = {}, children = {},
        shown = true, w = 0, h = 0 }
    if parent and rawget(parent, "children") then table.insert(parent.children, o) end
    return setmetatable(o, { __index = function(_, k)
        if not k:match("^%u") then return nil end
        return function(self, ...)
            local args = { ... }
            if k == "SetScript" then self.scripts[args[1]] = args[2]
            elseif k == "GetScript" then return self.scripts[args[1]]
            elseif k == "HookScript" then
                local old = self.scripts[args[1]]
                local fn = args[2]
                self.scripts[args[1]] = function(...) if old then old(...) end return fn(...) end
            elseif k == "SetPoint" then self.points[#self.points + 1] = args
            elseif k == "ClearAllPoints" then self.points = {}
            elseif k == "SetAllPoints" then self.points = { { "ALL", args[1] } }
            elseif k == "RegisterEvent" then self.events[args[1]] = true
            elseif k == "SetGradient" then self.gradient = { args[2], args[3] }
            elseif k == "SetColorTexture" or k == "SetTextColor" or k == "SetVertexColor" then self.color = args
            elseif k == "SetTexture" then
                self.texture = args[1]
                return not missingFiles[args[1]]
            elseif k == "SetAtlas" then
                atlasCalls[#atlasCalls + 1] = args[1]
                self.atlas = args[1]
                if args[2] then self.w, self.h = ATLAS_W, ATLAS_H end
            elseif k == "SetNormalAtlas" then atlasCalls[#atlasCalls + 1] = args[1]; self.normalAtlas = args[1]
            elseif k == "SetPushedAtlas" then atlasCalls[#atlasCalls + 1] = args[1]; self.pushedAtlas = args[1]
            elseif k == "SetHighlightAtlas" then atlasCalls[#atlasCalls + 1] = args[1]; self.highlightAtlas = args[1]
            elseif k == "SetHighlightTexture" then
                self.highlight = New("Texture", self)
                self.highlight.texture = args[1]
            elseif k == "GetHighlightTexture" then return self.highlight
            elseif k == "SetTexCoord" then self.coords = args
            elseif k == "SetRotation" then self.rotation = args[1]
            elseif k == "SetBlendMode" then self.blend = args[1]
            elseif k == "SetShown" then self.shown = args[1] and true or false
            elseif k == "Show" then self.shown = true
            elseif k == "Hide" then self.shown = false
            elseif k == "IsShown" or k == "IsVisible" then return self.shown
            elseif k == "SetEnabled" or k == "Enable" or k == "Disable" then
                local on = k == "Enable" or (k == "SetEnabled" and args[1] and true or false)
                if (self.enabled ~= false) ~= on then
                    self.enabled = on
                    local fn = self.scripts[on and "OnEnable" or "OnDisable"]
                    if fn then fn(self) end
                end
            elseif k == "IsEnabled" then return self.enabled ~= false
            elseif k == "SetMotionScriptsWhileDisabled" then self.motionWhileDisabled = args[1]
            elseif k == "EnableMouse" then self.mouse = args[1]
            elseif k == "SetSize" then self.w, self.h = args[1], args[2]
            elseif k == "SetHeight" then self.h = args[1]
            elseif k == "SetWidth" then self.w = args[1]
            elseif k == "GetHeight" then return self.h
            elseif k == "GetWidth" then return self.w
            elseif k == "GetText" then return self.text or ""
            elseif k == "SetText" then self.text = args[1]
            elseif k == "SetFont" then self.font = args[1]
            elseif k == "GetTextColor" then
                local c = self.color or { 1, 1, 1, 1 }
                return c[1], c[2], c[3], c[4]
            elseif k == "SetAlpha" then self.alpha = args[1]
            elseif k == "SetFrameStrata" then self.strata = args[1]
            elseif k == "GetFrameLevel" then return rawget(self, "level") or 1
            elseif k == "GetPoint" then local p = self.points[1]; if p then return unpack(p) end
            elseif k == "SetNormalTexture" then self.normal = args[1]
            elseif k == "SetPushedTexture" then self.pushed = args[1]
            elseif k == "SetFrameLevel" then self.level = args[1]
            elseif k == "SetParent" then self.parent = args[1]
            elseif k == "GetParent" then return self.parent
            elseif k == "GetStringWidth" then return 20
            elseif k == "GetStringHeight" then return 12
            elseif k == "GetEffectiveScale" then return 1
            elseif k == "GetObjectType" then return self.kind
            elseif k == "AddMaskTexture" then self.mask = args[1]
            elseif k == "CreateTexture" then return New("Texture", self)
            elseif k == "CreateMaskTexture" then return New("MaskTexture", self)
            elseif k == "CreateFontString" then return New("FontString", self)
            end
        end
    end })
end

local function Desc()
    local desc = { entries = {} }
    local function Add(e) desc.entries[#desc.entries + 1] = e end
    function desc.CreateTitle(_, text) Add({ kind = "title", text = text }) end
    function desc.CreateDivider() Add({ kind = "divider" }) end
    function desc.CreateButton(_, text, fn) Add({ kind = "button", text = text, fn = fn }) end
    function desc.CreateRadio(_, text, isSel, setSel, data)
        Add({ kind = "radio", text = text, on = isSel(data), fn = function() setSel(data) end })
    end
    function desc.SetScrollMode() end
    return desc
end

local SHARED = { "Core/Core.lua", "Shared/Shared.lua", "Shared/Style.lua", "Core/Options/Widgets.lua",
    "Shared/UI/Parts.lua", "Shared/UI/Marks.lua", "Shared/UI/Text.lua", "Shared/UI/Hud.lua", "Shared/UI/Timer.lua",
    "Shared/UI/Share.lua", "Shared/UI/Panels.lua", "Shared/UI/Window.lua", "Shared/UI/Forever.lua",
    "Shared/UI/Tabs.lua", "Shared/UI/SettingsCard.lua" }
local UNLOCK = dofile("Tools/regression/toc_files.lua")("^Core/Unlock/.-%.lua$")

local function ApplyLayout(container, layout, kit)
    applied[#applied + 1] = kit
    container.kit = kit
    for slot, piece in pairs(layout) do
        local tex = rawget(container, slot) or New("Texture", container)
        rawset(container, slot, tex)
        tex.atlas = piece.atlas:format(kit)
        tex.offsets = { piece.x, piece.y, piece.x1, piece.y1 }
    end
end

local function Load(account, atlases, files)
    frames, atlasCalls, layouts, applied, timers = {}, {}, {}, {}, {}
    present, missingFiles = atlases or {}, files or {}
    local uiParent = New("Frame")
    uiParent.w, uiParent.h = SCREEN_W, SCREEN_H
    local env = setmetatable({
        NaowhForeverDB = { account = account, profiles = {}, charActive = {} },
        C_AddOns = { IsAddOnLoaded = function() return true end, GetAddOnMetadata = function() return "test" end,
            GetAddOnEnableState = function() return 2 end },
        C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end },
        InCombatLockdown = function() return false end,
        IsShiftKeyDown = function() return false end,
        IsAltKeyDown = function() return false end,
        IsControlKeyDown = function() return false end,
        GetCurrentKeyBoardFocus = function() return nil end,
        GameTooltip = New("Frame"),
        Mixin = function(object, ...)
            for i = 1, select("#", ...) do
                for k, v in pairs((select(i, ...))) do object[k] = v end
            end
            return object
        end,
        wipe = function(t) for k in pairs(t) do t[k] = nil end return t end,
        strtrim = function(text) return (text:gsub("^%s+", ""):gsub("%s+$", "")) end,
        hooksecurefunc = function(tbl, name, fn)
            local orig = tbl[name]
            rawset(tbl, name, function(...) orig(...); fn(...) end)
        end,
        CreateFrame = function(kind, _, parent)
            local f = New(kind, parent)
            frames[#frames + 1] = f
            return f
        end,
        CreateColor = function(r, g, b, a)
            return { r = r, g = g, b = b, a = a, SetRGBA = function(c, ...) c.r, c.g, c.b, c.a = ... end }
        end,
        PixelUtil = { GetPixelToUIUnitFactor = function() return 1 end,
            GetNearestPixelSize = function(v) return v end },
        UIParent = uiParent,
        GetCursorPosition = function() return 100, 100 end,
        C_Texture = { GetAtlasInfo = function(name) return present[name] and { width = ATLAS_W, height = ATLAS_H } or nil end },
        NineSliceUtil = {
            ApplyLayoutByName = function(container, name)
                container.layout = name
                layouts[#layouts + 1] = name
            end,
            ApplyLayout = ApplyLayout,
        },
        MenuUtil = { CreateRootMenuDescription = Desc, CreateContextMenu = function(owner, gen)
            opened = { owner = owner, desc = Desc() }
            gen(owner, opened.desc)
        end },
        MenuVariants = { GetDefaultMenuMixin = function() return {} end },
        Menu = { GetManager = function()
            return { OpenMenu = function(_, owner, desc)
                opened = { owner = owner, desc = desc }
                return { IsShown = function() return false end, Close = function() end }
            end }
        end },
        AnchorUtil = { CreateAnchor = function() return {} end },
    }, { __index = _G })
    env._G = env
    local paths = {}
    for _, path in ipairs(SHARED) do paths[#paths + 1] = path end
    for _, path in ipairs(UNLOCK) do paths[#paths + 1] = path end
    local ns
    for _, path in ipairs(paths) do
        local chunk = assert(loadstring(Read(path), path))
        setfenv(chunk, env)
        chunk("NaowhForever", env.NaowhForever)
        ns = env.NaowhForever
    end
    for _, f in ipairs(frames) do
        if f.events.ADDON_LOADED and f.scripts.OnEvent then f.scripts.OnEvent(f, "ADDON_LOADED", "NaowhForever") end
    end
    local settings = {}
    ns.UnlockModeSettings = { DB = function() return settings end, Get = function(k) return settings[k] end,
        Set = function(k, v) settings[k] = v end, Default = function() return {} end }
    rawset(ns, "PromptText", function(_, _, _, accept) prompt = accept end)
    rawset(ns, "Confirm", function(_, yes) yes() end)
    return ns, env
end

local function Flush()
    for _ = 1, 10 do
        if #timers == 0 then return end
        local run = timers
        timers = {}
        for _, fn in ipairs(run) do fn() end
    end
end

local function Find(list, test)
    for _, x in ipairs(list) do if test(x) then return x end end
end

local function Holds(frame, test)
    for _, c in ipairs(frame.children) do
        if test(c) then return c end
        local deeper = Holds(c, test)
        if deeper then return deeper end
    end
end

local function Fire(f, name, ...)
    local fn = f.scripts[name]
    if fn then fn(f, ...) end
end

local function AllAtlases(St)
    local set = {}
    local function Add(name) set[name] = true end
    for _, list in ipairs({ St.FOREVER_FRAME_ATLASES, St.FOREVER_BARE_ATLASES, St.FOREVER_INSET_ATLASES }) do
        for _, name in ipairs(list) do Add(name) end
    end
    for _, group in ipairs({ St.FOREVER_CLOSE_ATLAS, St.FOREVER_TAB_ATLAS, St.FOREVER_ACTIVE_TAB_ATLAS,
        St.FOREVER_SIDE_TAB_ATLAS, St.FOREVER_SEARCH_ATLAS }) do
        for _, name in pairs(group) do Add(name) end
    end
    for _, name in ipairs({ St.FOREVER_PILL_ATLAS, St.FOREVER_BAND_ATLAS, St.FOREVER_BAR_ATLAS, St.FOREVER_PLUS_ATLAS,
        St.FOREVER_MINUS_ATLAS, St.FOREVER_DROPDOWN_ATLAS }) do Add(name) end
    local red = St.FOREVER_RED_BUTTON_ATLAS
    for _, suffix in ipairs(St.FOREVER_RED_BUTTON_STATES) do
        Add(red.left .. suffix); Add(red.center .. suffix); Add(red.right .. suffix)
    end
    Add(red.highlight)
    for _, kit in pairs(St.FOREVER_SELECTION_KIT) do
        for _, piece in pairs(St.FOREVER_SELECTION_PIECES) do Add(piece:format(kit)) end
    end
    return set
end

local redAtlas
local function RedPieces(btn, suffix)
    local red, art = redAtlas, btn.redArt
    return art ~= nil and art[1].atlas == red.left .. suffix and art[2].atlas == red.center .. suffix
        and art[3].atlas == red.right .. suffix
end

local function Element(ns, label)
    local frame = New("Frame")
    frame:SetPoint("CENTER", nil, "CENTER", 0, 0)
    local mover = ns.UI.AttachMover(frame, label, function() end, "QoL/Combat", nil)
    return mover, frame
end

local function Toolbar()
    return Find(frames, function(f) return rawget(f, "_undo") ~= nil end)
end

local function Panel()
    return Find(frames, function(f) return rawget(f, "search") ~= nil and rawget(f, "rows") ~= nil end)
end

local function Open(ns)
    ns.ShowUnlockMode()
    ns.HudEditor.RefreshPanel()
    Flush()
    return Toolbar(), Panel()
end

local Probe = Load({})
local St = Probe.Shared.Style
redAtlas = St.FOREVER_RED_BUTTON_ATLAS
local ALL = AllAtlases(St)
local KIT = St.FOREVER_SELECTION_KIT

-- Forever, on a client with all of the game's art.
do
    local ns = Load({ skin = "forever" }, ALL)
    local H = ns.HudEditor
    local mover = Element(ns, "Combat Timer")
    check("a mover is not dressed until the HUD Editor opens", mover.editGlow == nil and #applied == 0)
    mover:Show()
    local bar, panel = Open(ns)
    local chrome = bar.forever
    check("the toolbar wears the game's bare metal frame", chrome and chrome.art
        and chrome.layout == St.FOREVER_BARE_LAYOUT and chrome.portrait == nil and chrome.rings == nil)
    check("its title on the bar, in gold", chrome.title.text == "HUD Editor"
        and chrome.title.color[1] == St.FOREVER_GOLD_RGB.r and chrome.title.points[2][4] == St.FOREVER_TITLE_RIGHT)
    check("the game's red close button", chrome.close.normalAtlas == St.FOREVER_CLOSE_ATLAS.normal)
    check("no Exit Config button and no extra icon", not Find(frames, function(f)
        return f.label and f.label.text == "Exit Config" end) and not Holds(bar, function(x) return x.texture == St.LOGO end))
    check("the buttons start under the title bar", bar._undo.points[1][3] == -10)

    local buttons = { bar._undo, bar._redo, bar._revert, bar._elements }
    local same = true
    for _, b in ipairs(buttons) do same = same and b._forever and b.h == 22 end
    check("Undo, Redo, Revert and Elements: the red button, one height, the Layouts picker too", same
        and bar._layout.h == 22)
    check("nothing to take back: Undo, Redo and Revert disabled, the grey art and text", RedPieces(bar._undo, "-Disabled")
        and RedPieces(bar._redo, "-Disabled") and RedPieces(bar._revert, "-Disabled")
        and bar._undo.label.color[1] == St.FOREVER_DISABLED_TEXT_RGB.r and bar._undo.alpha ~= 0.4)
    check("their tooltips still show while disabled", bar._undo.motionWhileDisabled == true)
    H.Checkpoint()
    check("a change: Undo and Revert lit, Redo still grey", RedPieces(bar._undo, "") and RedPieces(bar._revert, "")
        and RedPieces(bar._redo, "-Disabled") and bar._undo.label.color[2] == St.FOREVER_GOLD_RGB.g)
    ns.UI.UndoMove()
    check("undone: Redo lit, Undo and Revert grey", RedPieces(bar._redo, "") and RedPieces(bar._undo, "-Disabled")
        and RedPieces(bar._revert, "-Disabled"))
    check("the list open: Elements shows the pressed art", RedPieces(bar._elements, "-Pressed") and panel.shown)
    Fire(bar._elements, "OnClick")
    check("the list closed: Elements plain again", RedPieces(bar._elements, "") and not panel.shown)
    Fire(bar._elements, "OnClick")
    Flush()

    local tick = bar._guides
    check("Guides is the game's check box", tick.checkArt and tick.checkArt.texture == St.FOREVER_CHECKBOX.up
        and tick.w == St.FOREVER_CHECK_SIZE)
    local picker = bar._layout
    check("Layouts is a dropdown with the game's arrow, showing Layouts", Holds(picker, function(x)
        return x.atlas == St.FOREVER_DROPDOWN_ATLAS end) and picker.label.text == "Layouts")
    local function Menu()
        picker._menu = nil
        Fire(picker, "OnMouseDown")
        local out = {}
        for _, e in ipairs(opened.desc.entries) do out[#out + 1] = e.text or "-" end
        return table.concat(out, ", "), opened
    end
    local texts, menu = Menu()
    check("it opens under itself with the layouts' actions", menu.owner == picker and texts == "Layouts, -, Save as New Layout")
    menu.desc.entries[3].fn()
    prompt("Raid")
    texts, menu = Menu()
    check("a saved layout is listed, ticked and named on the picker", picker.label.text == "Raid"
        and texts == "Layouts, Raid, -, Save to Raid, Save as New Layout, Rename Raid, Delete Raid"
        and menu.desc.entries[2].on)

    check("the mover dressed when the HUD Editor opens: Edit Mode's blue highlight", mover.editArt
        and mover.TopLeftCorner.atlas == KIT.highlight .. "-NineSlice-Corner"
        and mover.TopEdge.atlas == "_" .. KIT.highlight .. "-NineSlice-EdgeTop"
        and mover.Center.atlas == KIT.highlight .. "-NineSlice-Center")
    check("its corners out by the template's offset", mover.TopLeftCorner.offsets[1] == -St.FOREVER_SELECTION_OUT
        and mover.TopLeftCorner.offsets[2] == St.FOREVER_SELECTION_OUT)
    check("the old plate stood down, the name still centred", not mover._fill.shown and not mover._strip.shown
        and not mover._border._frame.shown and mover.text.text == "Combat Timer" and mover.text.points[1][1] == "CENTER")
    check("no glow at rest", not mover.editGlow.shown)
    Fire(mover, "OnEnter")
    local glow = mover.editGlow
    check("under the mouse the highlight again, added at 0.4, as Edit Mode's", glow.shown
        and glow.alpha == St.FOREVER_SELECTION_GLOW_ALPHA and glow.kit == KIT.highlight and glow.Center.blend == "ADD")
    Fire(mover, "OnLeave")
    check("and gone again", not glow.shown)
    ns.UI.SelectMover(mover)
    Flush()
    check("picked: the yellow selected art", mover.TopLeftCorner.atlas == KIT.selected .. "-NineSlice-Corner"
        and mover.Center.atlas == KIT.selected .. "-NineSlice-Center")

    local pchrome = panel.forever
    check("the Elements list wears the same frame, its title on the bar", pchrome and pchrome.art
        and pchrome.layout == St.FOREVER_BARE_LAYOUT and pchrome.title.text == "Elements")
    local groupBar = panel.titles[1]
    check("a group is a list bar on the game's art, its name in gold, open", groupBar.barArt.atlas == St.FOREVER_BAR_ATLAS
        and groupBar.name.text == "QoL" and groupBar.name.color[1] == ns.THEME.accent.r
        and groupBar.sign.atlas == St.FOREVER_MINUS_ATLAS and groupBar.sign.shown)
    local row = panel.rows[1]
    check("the picked element's row lit with the game's highlight, no strip", row.shown and row.item.handle == mover
        and row.fill.shown and row.fill.texture == St.FOREVER_HIGHLIGHT and not row.mark.shown)
    check("its eye and padlock a readable size", row.eye.w == 16 and row.lock.w == 16)
    Fire(groupBar, "OnClick")
    Flush()
    check("a click folds the group: its rows go, the plus shows", not row.shown and groupBar.sign.atlas == St.FOREVER_PLUS_ATLAS)
    panel.search:SetText("combat")
    Fire(panel.search, "OnTextChanged")
    Flush()
    check("a search shows every match, folded or not", row.shown and not groupBar.sign.shown)
    panel.search:SetText("")
    Fire(panel.search, "OnTextChanged")
    Fire(groupBar, "OnClick")
    Flush()
    check("open again", row.shown and groupBar.sign.atlas == St.FOREVER_MINUS_ATLAS)
    Fire(pchrome.close, "OnClick")
    check("the list's close button closes it and lets Elements up", not panel.shown
        and ns.UnlockModeSettings.Get("elementsPanel") == false and RedPieces(bar._elements, ""))

    local item = mover._placement
    rawset(mover, "GetLeft", function() return SCREEN_W / 2 - 50 end)
    rawset(mover, "GetRight", function() return SCREEN_W / 2 + 50 end)
    rawset(mover, "GetTop", function() return SCREEN_H / 2 + 20 end)
    rawset(mover, "GetBottom", function() return SCREEN_H / 2 - 20 end)
    rawset(item.frame, "GetLeft", mover.GetLeft)
    rawset(item.frame, "GetRight", mover.GetRight)
    rawset(item.frame, "GetTop", mover.GetTop)
    rawset(item.frame, "GetBottom", mover.GetBottom)
    H.DrawGuides(item)
    local line = H.dragLayer.lines[1]
    check("a guide lighter: the light gold, not the orange, and see-through", line and line.shown
        and line.color[1] == St.FOREVER_GUIDE_RGB.r and line.color[4] == St.FOREVER_GUIDE_ALPHA)
    H.Clear(H.dragLayer)

    Fire(chrome.close, "OnClick")
    check("the toolbar's close button leaves the HUD Editor", not ns.IsUnlockModeActive() and not bar.shown)
end

-- Forever on a client with none of the art: everything drawn, nothing missing.
do
    local ns = Load({ skin = "forever" }, {}, { [St.FOREVER_CHECKBOX.up] = true })
    local mover = Element(ns, "Combat Timer")
    mover:Show()
    local bar, panel = Open(ns)
    check("no art: both frames drawn", bar.forever and not bar.forever.art and #bar.forever.rings == 5
        and panel.forever and not panel.forever.art and #layouts == 0)
    check("drawn buttons, Undo drawn grey", bar._undo.redArt == nil
        and bar._undo._bg.gradient[2].r == St.FOREVER_RED_DISABLED_RGB[1].r)
    check("Elements drawn pressed", bar._elements._bg.gradient[1].r == St.FOREVER_RED_RGB[1].r)
    check("a drawn arrow on the Layouts picker", bar._layout.arrowPlate ~= nil)
    local fill = St.FOREVER_SELECTION_RGB
    check("a mover drawn: a see-through blue fill in a light blue edge", not mover.editArt
        and mover.editFill.color[3] == fill.b and mover.editFill.color[4] == St.FOREVER_SELECTION_ALPHA
        and mover.editEdge ~= nil and #applied == 0)
    ns.UI.SelectMover(mover)
    Flush()
    check("picked: drawn yellow", mover.editFill.color[1] == St.FOREVER_SELECTED_RGB.r)
    local groupBar = panel.titles[1]
    check("a drawn list bar with a gold minus", groupBar.barRim ~= nil and groupBar.signText.text == "-")
    check("no atlas asked for that the client lacks", #atlasCalls == 0)
    ns.HideUnlockMode()
end

-- Naowh and Classic+: the HUD Editor as before, nothing of Forever.
for _, skin in ipairs({ "", "classic" }) do
    local ns = Load({ skin = skin }, ALL)
    local mover = Element(ns, "Combat Timer")
    mover:Show()
    local bar, panel = Open(ns)
    local name = skin == "" and "Naowh" or "Classic+"
    check(name .. ": no Forever frame, the Exit Config button and the logo", bar.forever == nil and panel.forever == nil
        and Find(frames, function(f) return f.label and f.label.text == "Exit Config" end)
        and Holds(bar, function(x) return x.texture == St.LOGO end))
    check(name .. ": Undo faded when there is nothing to take back", bar._undo.alpha == 0.4 and bar._undo.mouse == false
        and not bar._undo._forever)
    check(name .. ": Layouts a button", bar._layout.arrowPlate == nil and not Holds(bar._layout, function(x)
        return x.atlas == St.FOREVER_DROPDOWN_ATLAS end))
    check(name .. ": the mover keeps its plate", mover.editGlow == nil and mover._fill.shown and mover._strip.shown)
    check(name .. ": group titles, not bars", panel.titles[1] and panel.titles[1].kind == "FontString")
    check(name .. ": no atlas asked for", #atlasCalls == 0 and #layouts == 0 and #applied == 0)
    ns.HideUnlockMode()
end

print("forever unlock: " .. checks .. " checks passed")
