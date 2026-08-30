-------------------------------------------------------------------------------
--  NaowhUI_SmartReminders_Core.lua -- theme, chrome primitives, DB and profile plumbing.
--
--  Standalone addon: no EllesmereUI dependency. The options window, widget kit and
--  profile system are all its own (Widgets and Window files).
-------------------------------------------------------------------------------
local ADDON_NAME = ...

-- Must match the addon folder; the DB and saved positions key off it.
-- Renamed with the addon (was NaowhUI_TankReminder).
local MODULE_KEY = "NaowhUI_SmartReminders"

local ns = {}
_G.NaowhUITankReminder = ns
ns.MODULE_KEY = MODULE_KEY

-- Naowh's own scheme: dark grey with his blue (#0091ed) as the single accent.
ns.THEME = {
    bg     = { r = 0x0e / 255, g = 0x0f / 255, b = 0x11 / 255 },  -- window backdrop
    panel  = { r = 0x1a / 255, g = 0x1c / 255, b = 0x1f / 255 },  -- panels, modals, controls
    line   = { r = 0x2e / 255, g = 0x31 / 255, b = 0x36 / 255 },  -- borders, dividers, tracks
    fg     = { r = 0xf0 / 255, g = 0xf1 / 255, b = 0xf3 / 255 },  -- primary text
    muted  = { r = 0x9a / 255, g = 0x9e / 255, b = 0xa6 / 255 },  -- secondary text
    grey   = { r = 0x34 / 255, g = 0x37 / 255, b = 0x3d / 255 },  -- selected-row neutral fill
    accent     = { r = 0x00 / 255, g = 0x91 / 255, b = 0xed / 255 },
    accentSoft = { r = 0x4d / 255, g = 0xb5 / 255, b = 0xf5 / 255 },
}

-- A secret-tainted message is DROPPED by the display, silently and with nothing logged, so
-- a diagnostic built from live combat data can vanish line by line while looking for all the
-- world like code that never ran. Caught here once rather than at every call site.
--
-- tostring() is not a way out: on a secret it returns a SECRET STRING rather than raising,
-- and the taint rides through format and concatenation to the display. issecretvalue() is
-- the only thing that answers plainly, and it must be asked BEFORE the value is coerced.
function ns.Print(msg)
    if issecretvalue and issecretvalue(msg) then
        msg = "|cff0091ed(withheld: this line contained a secret value)|r"
    end
    print("|cff0091edNaowhUI|r " .. tostring(msg))
end

-------------------------------------------------------------------------------
--  House chrome
-------------------------------------------------------------------------------
-- Every panel this addon draws is built from these primitives, so the whole look is
-- decided here and in ns.THEME. The widget factory in the Widgets file builds its rows
-- from the same pieces.

-- The UI font: the Naowh face when NaowhUI_Media (or anything else) has registered it
-- with LibSharedMedia, the client default otherwise. Resolved once -- media addons load
-- before us via OptionalDeps, and nothing builds UI before login.
local uiFontPath
function ns.UIFontPath()
    if not uiFontPath then
        local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
        uiFontPath = (LSM and LSM:Fetch("font", "Naowh", true)) or STANDARD_TEXT_FONT
    end
    return uiFontPath
end

function ns.Font(parent, size, flags, color)
    local c = color or ns.THEME.fg
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(ns.UIFontPath(), size, flags or "")
    fs:SetTextColor(c.r, c.g, c.b, 1)
    return fs
end

-- Four 1px edges on a child frame one level up, so the border draws over the panel's own
-- background but under its content. Returns { _frame, SetColor } -- _frame so a caller can
-- hide the whole border (the learn-tag does), SetColor for hover restyles.
function ns.Border(frame, color, alpha)
    local c = color or ns.THEME.line
    local a = alpha or 1
    local bf = CreateFrame("Frame", nil, frame)
    bf:SetAllPoints()
    bf:SetFrameLevel(math.min(frame:GetFrameLevel() + 1, 9999))
    local edges = {}
    for i = 1, 4 do
        local t = bf:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(c.r, c.g, c.b, a)
        edges[i] = t
    end
    edges[1]:SetPoint("TOPLEFT"); edges[1]:SetPoint("TOPRIGHT"); edges[1]:SetHeight(1)
    edges[2]:SetPoint("BOTTOMLEFT"); edges[2]:SetPoint("BOTTOMRIGHT"); edges[2]:SetHeight(1)
    edges[3]:SetPoint("TOPLEFT"); edges[3]:SetPoint("BOTTOMLEFT"); edges[3]:SetWidth(1)
    edges[4]:SetPoint("TOPRIGHT"); edges[4]:SetPoint("BOTTOMRIGHT"); edges[4]:SetWidth(1)
    return {
        _frame = bf,
        SetColor = function(_, r, g, b, a2)
            for i = 1, 4 do edges[i]:SetColorTexture(r, g, b, a2 or 1) end
        end,
    }
end

function ns.Solid(parent, layer, color, alpha)
    local c = color or ns.THEME.panel
    local t = parent:CreateTexture(nil, layer or "BACKGROUND")
    t:SetColorTexture(c.r, c.g, c.b, alpha or 1)
    return t
end

-- btn.label is exposed so a reused button can be re-labelled on each open.
function ns.Button(parent, text, w, h, onClick)
    local T = ns.THEME
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(w, h)
    local bg = ns.Solid(btn, "BACKGROUND", T.panel, 0.9)
    bg:SetAllPoints()
    local border = ns.Border(btn)
    local lbl = ns.Font(btn, 12, nil)
    lbl:SetPoint("CENTER")
    lbl:SetText(text)
    btn.label = lbl
    btn:SetScript("OnClick", function() if onClick then onClick() end end)
    btn:SetScript("OnEnter", function()
        bg:SetColorTexture(T.panel.r, T.panel.g, T.panel.b, 1)
        border:SetColor(T.accent.r, T.accent.g, T.accent.b, 1)
    end)
    btn:SetScript("OnLeave", function()
        bg:SetColorTexture(T.panel.r, T.panel.g, T.panel.b, 0.9)
        border:SetColor(T.line.r, T.line.g, T.line.b, 1)
    end)
    return btn
end

function ns.SetButtonText(btn, text)
    if not (btn and btn.label) then return end
    btn.label:SetText(text)
end

-- The house tooltip lives in the Widgets file (ns.UI); resolved at hover time since that
-- file loads after this one.
function ns.Tooltip(frame, title, body)
    -- Composed at HOVER time, not attach time: the tooltip accepts a function and
    -- resolves it on show, and a body that is itself a function can answer from data that
    -- did not exist yet when the row was built -- spell text loads async.
    local function Compose()
        local b = body
        if type(b) == "function" then b = b() end
        if b and b ~= "" then
            return "|cff0091ed" .. title .. "|r\n" .. b
        end
        return title
    end
    frame:SetScript("OnEnter", function(self)
        local UI = ns.UI
        if UI and UI.ShowWidgetTooltip then
            UI.ShowWidgetTooltip(self, Compose, { anchor = "cursor", justify = "LEFT" })
        end
    end)
    frame:SetScript("OnLeave", function()
        local UI = ns.UI
        if UI and UI.HideWidgetTooltip then UI.HideWidgetTooltip() end
    end)
end

-- Modals stack: the reminder editor opens from inside the instance modal, and with both
-- on the same strata, creation order decided who was on top. Frame:Raise() looks like the
-- fix, but it reorders a frame against ALL of UIParent's direct children -- the whole
-- client's addon ecosystem, not just our own popups -- so the level it lands on is
-- unbounded and can already sit well above any fixed number by the time a session has
-- opened a few dialogs elsewhere. A dropdown's own drop-down menu (built by the shared
-- widget factory) is one such fixed number: FULLSCREEN_DIALOG strata, level 200,
-- hardcoded, independent of whatever frame opened it. A Raise()'d modal that happens to
-- land above 200 wins the stacking fight against the OTHER modal, then promptly loses
-- its own dropdowns' menus to that exact same win. A private counter, incremented only by
-- our own modals and starting low, keeps every level this file ever hands out safely
-- under that ceiling while still making each newly opened modal outrank the last one.
local nextModalLevel = 10

-- One live modal per key. Callers build their contents fresh on every open, so without
-- an identity the same button pressed twice leaves two live copies stacked on screen --
-- reported on the pack importer, but true of every dialog here. Retiring the previous
-- copy under the same key is all that is needed: WoW frames cannot be destroyed, and
-- hiding an orphaned one is as close to releasing it as the API allows.
--
-- Nested dialogs keep DIFFERENT keys (the reminder editor opens from inside the instance
-- modal and both must stay up), so this never closes a parent to open its child.
local liveModals = {}

-- A dimmed modal shell: click-off to dismiss, house border and panel fill. Returns the
-- dimmer (show/hide this) and the panel to fill. `key` names the dialog; pass one unless
-- several copies are genuinely meant to coexist.
function ns.MakeModal(width, height, key)
    if key and liveModals[key] then
        liveModals[key]:Hide()
        liveModals[key] = nil
    end
    local dimmer = CreateFrame("Frame", nil, UIParent)
    dimmer:SetAllPoints(UIParent)
    dimmer:SetFrameStrata("FULLSCREEN_DIALOG")
    -- A floating panel, not a screen-blocking modal: mouse stays off the full-screen
    -- anchor so the Dungeon Journal and everything else underneath is still clickable and
    -- undimmed while this is open. Only the panel itself (below) captures the mouse.
    dimmer:EnableMouse(false)
    local panel = CreateFrame("Frame", nil, dimmer)
    panel:SetSize(width, height)
    panel:SetPoint("CENTER")
    panel:SetFrameStrata("FULLSCREEN_DIALOG")
    panel:EnableMouse(true)
    local bg = ns.Solid(panel, "BACKGROUND", ns.THEME.panel, 1)
    bg:SetAllPoints()
    ns.Border(panel)

    -- Draggable from any empty background area, the same way EllesmereUI's own windows
    -- move -- a click that lands on a button or edit box is intercepted by that child
    -- first, so this only ever engages on the parts of the panel nothing else claimed.
    -- Not saved: most of these popups are rebuilt fresh on every open (see their own
    -- comments), so there is nowhere sensible to persist a position across that, and it
    -- would look odd for a small popup to inherit wherever a much larger one was dragged.
    panel:SetMovable(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", function(self) self:StartMoving() end)
    panel:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

    -- Escape closes the topmost open modal, same as any other WoW window. Not
    -- UISpecialFrames -- that needs a fixed global name per frame, and MakeModal hands out
    -- a fresh nameless one on every call, with several stacking at once (the reminder
    -- editor opens from inside the instance modal). Each dimmer's own OnKeyDown instead:
    -- ESCAPE hides this one and stops there (SetPropagateKeyboardInput(false)), so a
    -- second ESC press reaches whatever modal is stacked underneath rather than closing
    -- both at once. Any other key falls through untouched.
    -- SetPropagateKeyboardInput is protected, so a modal opened in combat is refused it and
    -- the addon is flagged for calling a protected function. The keyboard is not taken at
    -- all there rather than taken without propagation control, which would swallow every
    -- keybind for as long as the modal stayed open. The cost is that ESC will not close a
    -- modal opened mid-fight; its close button still does.
    if not InCombatLockdown() then
        dimmer:EnableKeyboard(true)
        dimmer:SetPropagateKeyboardInput(true)
        dimmer:SetScript("OnKeyDown", function(self, key)
            if InCombatLockdown() then return end
            if key == "ESCAPE" then
                self:Hide()
                self:SetPropagateKeyboardInput(false)
            else
                self:SetPropagateKeyboardInput(true)
            end
        end)
    end

    dimmer:SetScript("OnShow", function(self)
        -- The counter only ever climbed, so the panel level (this + 5) crossed 200 on the
        -- nineteenth modal opened in a session -- and 200 is the hardcoded dropdown level
        -- the comment above is about. Past that, dropdowns render BEHIND the panel that
        -- opened them, which is the exact failure the counter exists to prevent. Stacking
        -- only needs to order the modals currently on screen, and nesting never gets deep,
        -- so winding back to the base is safe: anything still open sits below, and the one
        -- being shown goes above it.
        if nextModalLevel > 150 then nextModalLevel = 10 end
        nextModalLevel = nextModalLevel + 10
        self:SetFrameLevel(nextModalLevel)
        panel:SetFrameLevel(nextModalLevel + 5)
    end)
    dimmer:Hide()

    if key then liveModals[key] = dimmer end
    return dimmer, panel
end

-------------------------------------------------------------------------------
--  SavedVariables
-------------------------------------------------------------------------------
-- Going through EllesmereUI's NewDB lands us in profiles[name].addons[MODULE_KEY], so our
-- settings switch with profiles for free and stay ours rather than the companion's.
local _settingsDB

function ns.SettingsRoot()
    if _settingsDB and type(_settingsDB.profile) == "table" then
        return _settingsDB.profile
    end
    local L = _G.EllesmereUI and _G.EllesmereUI.Lite
    if L and L.NewDB then
        -- svName minus the trailing "DB" is the folder, so this lands under MODULE_KEY.
        _settingsDB = L.NewDB(MODULE_KEY .. "DB", { profile = {} })
        if _settingsDB and type(_settingsDB.profile) == "table" then
            return _settingsDB.profile
        end
    end
    -- EllesmereUI absent or too old: degrade to the account table rather than error.
    if type(_G.NaowhUITankReminderDB) ~= "table" then _G.NaowhUITankReminderDB = {} end
    return _G.NaowhUITankReminderDB
end

-------------------------------------------------------------------------------
--  Reaching EllesmereUI's stored profiles
-------------------------------------------------------------------------------
-- The active profile's blob IS the table SettingsRoot hands back, so a write here is live.
function ns.ForEachProfile(fn)
    local euidb = _G.EllesmereUIDB
    if not (euidb and type(euidb.profiles) == "table") then return end
    for name, root in pairs(euidb.profiles) do
        if type(root) == "table" then fn(name, root) end
    end
end

-------------------------------------------------------------------------------
--  Folder rename migration
-------------------------------------------------------------------------------
-- The profile map keys by addon folder, so the NaowhUI_TankReminder rename left every
-- existing list under a key nothing reads. Every profile is walked, not just the active one:
-- an untouched profile would otherwise keep its lists in the dead key and export empty.
local OLD_KEY = "NaowhUI_TankReminder"

function ns.RunMigrations()
    ns.ForEachProfile(function(_, root)
        local addons = root.addons
        local src = type(addons) == "table" and addons[OLD_KEY]
        if type(src) ~= "table" then return end

        -- An empty blob is what the old lazy lookup created for itself: it read through
        -- NewDB, which vivifies what it reads.
        if next(src) == nil then
            addons[OLD_KEY] = nil
            return
        end

        -- Only into an untouched blob, so a migrated-then-edited profile is not handed its
        -- deleted entries back. Filled in place: SettingsRoot may already hold this table.
        local dst = addons[MODULE_KEY]
        if type(dst) ~= "table" then dst = {}; addons[MODULE_KEY] = dst end
        if next(dst) == nil then
            for k, v in pairs(src) do dst[k] = v end
        end
    end)
end

-------------------------------------------------------------------------------
--  Re-apply on anything that swaps the active settings out from under us
-------------------------------------------------------------------------------
-- Coalesced: a profile switch can fire several of these hooks in one go, and re-running the
-- rebuild per hook would rebuild the slot list three times for one user action.
local reapplyPending

function ns.QueueReapply()
    if reapplyPending then return end
    reapplyPending = true
    C_Timer.After(0, function()
        reapplyPending = false
        if ns.Apply then ns.Apply() end
    end)
end

-------------------------------------------------------------------------------
--  Boot
-------------------------------------------------------------------------------
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")

    -- Core is first in the toc and registers PLAYER_LOGIN first, so this runs before the
    -- runtime's own handler and before anything has called SettingsRoot.
    ns.RunMigrations()

    -- Until the addon owns its DB, the settings still live in EllesmereUI's profiles, so
    -- anything that swaps the active profile swaps our settings out from under us.
    local EUI = _G.EllesmereUI
    if EUI then
        if EUI.SwitchProfile then hooksecurefunc(EUI, "SwitchProfile", ns.QueueReapply) end
        if EUI.OnSpecSwitchComplete then hooksecurefunc(EUI, "OnSpecSwitchComplete", ns.QueueReapply) end
        if EUI.ApplyProfileData then hooksecurefunc(EUI, "ApplyProfileData", ns.QueueReapply) end
    end
end)
