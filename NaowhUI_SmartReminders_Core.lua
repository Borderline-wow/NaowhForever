-------------------------------------------------------------------------------
--  NaowhUI_SmartReminders_Core.lua -- DB, settings-page injection, profile plumbing.
--
--  Standalone: EllesmereUI is the only hard dependency. NaowhUI_EUI is optional and only
--  changes WHERE the settings land -- with it we add a section to the existing NaowhUI
--  group's Gameplay page, without it we register that group ourselves. Either way the
--  settings live under our OWN profile key, so uninstalling the companion never orphans
--  them and a profile string carries this addon on its own.
-------------------------------------------------------------------------------
local ADDON_NAME = ...

-- Must match the addon folder: EllesmereUI's sidebar and profile map both key off it.
-- Renamed with the addon (was NaowhUI_TankReminder); RunMigrations moves the old key.
local MODULE_KEY = "NaowhUI_SmartReminders"

local NAOWH_BLUE = { r = 0x00 / 255, g = 0xCF / 255, b = 0xFF / 255 }

local ns = {}
_G.NaowhUITankReminder = ns
ns.MODULE_KEY = MODULE_KEY
ns.BLUE = NAOWH_BLUE

-- naowh.gg's own palette (lifted from its live stylesheet tokens), so everything this addon
-- draws reads as his brand: navy panels, gold primary accent, blue secondary.
ns.THEME = {
    bg    = { r = 0x07 / 255, g = 0x10 / 255, b = 0x1e / 255 },   -- --bg
    panel = { r = 0x0d / 255, g = 0x18 / 255, b = 0x28 / 255 },   -- --bg-elev
    line  = { r = 0x1c / 255, g = 0x2a / 255, b = 0x44 / 255 },   -- --line
    fg    = { r = 0xe7 / 255, g = 0xec / 255, b = 0xf5 / 255 },   -- --fg
    muted = { r = 0x8a / 255, g = 0x99 / 255, b = 0xb5 / 255 },   -- --muted
    gold  = { r = 0xf0 / 255, g = 0xa8 / 255, b = 0x30 / 255 },   -- --gold
    goldSoft = { r = 0xff / 255, g = 0xc7 / 255, b = 0x69 / 255 },-- --gold-soft
    blue  = { r = 0x2d / 255, g = 0xa6 / 255, b = 0xff / 255 },   -- --blue
    grey  = { r = 0x46 / 255, g = 0x4c / 255, b = 0x58 / 255 },   -- neutral, not a stylesheet token: for a selected-row fill that reads against blue text
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
        msg = "|cffF0A830(withheld: this line contained a secret value)|r"
    end
    print("|cff00cfffNaowhUI|r " .. tostring(msg))
end

-- Set at login. Companion mode rides NaowhUI_EUI's page; standalone mode owns one.
ns.companionMode = false

-------------------------------------------------------------------------------
--  House chrome
-------------------------------------------------------------------------------
-- Everything this addon draws outside EllesmereUI's own options rows is built from ITS
-- primitives -- MakeFont, MakeBorder, SolidTex, MakeStyledButton, ShowWidgetTooltip -- rather
-- than hand-rolled frames. That is what makes a panel of ours read as part of the same UI
-- instead of a lookalike, and it means an EllesmereUI theme or accent change carries here for
-- free. The one exception is a text input: the widget factory has none, so the EditBox is
-- ours, dressed in the same border and font.
function ns.Font(parent, size, flags, color)
    local EUI = _G.EllesmereUI
    local c = color or ns.THEME.fg
    if EUI and EUI.MakeFont then
        return EUI.MakeFont(parent, size, flags, c.r, c.g, c.b, 1)
    end
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(STANDARD_TEXT_FONT, size, flags or "")
    fs:SetTextColor(c.r, c.g, c.b, 1)
    return fs
end

function ns.Border(frame, color, alpha)
    local EUI = _G.EllesmereUI
    local c = color or ns.THEME.line
    if EUI and EUI.MakeBorder then
        return EUI.MakeBorder(frame, c.r, c.g, c.b, alpha or 1, EUI.PanelPP)
    end
end

function ns.Solid(parent, layer, color, alpha)
    local EUI = _G.EllesmereUI
    local c = color or ns.THEME.panel
    if EUI and EUI.SolidTex then
        return EUI.SolidTex(parent, layer, c.r, c.g, c.b, alpha or 1)
    end
    local t = parent:CreateTexture(nil, layer or "BACKGROUND")
    t:SetColorTexture(c.r, c.g, c.b, alpha or 1)
    return t
end

-- btn.label is exposed so a reused button can be re-labelled on each open. Calling
-- MakeStyledButton again would not do it: it builds a fresh background, border and
-- fontstring every time and overwrites OnClick.
function ns.Button(parent, text, w, h, onClick)
    local EUI = _G.EllesmereUI
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(w, h)
    if EUI and EUI.MakeStyledButton and EUI.WB_COLOURS then
        local _, _, lbl = EUI.MakeStyledButton(btn, text, 12, EUI.WB_COLOURS, onClick)
        btn.label = lbl
    else
        local bg = ns.Solid(btn, "BACKGROUND", ns.THEME.line, 0.6)
        bg:SetAllPoints()
        local lbl = ns.Font(btn, 12, nil)
        lbl:SetPoint("CENTER"); lbl:SetText(text)
        btn.label = lbl
        btn:SetScript("OnClick", function() if onClick then onClick() end end)
    end
    return btn
end

-- Re-label a button built by ns.Button, going through EllesmereUI's localiser the same way
-- MakeStyledButton does.
function ns.SetButtonText(btn, text)
    if not (btn and btn.label) then return end
    local EUI = _G.EllesmereUI
    btn.label:SetText((EUI and EUI.L and EUI.L(text)) or text)
end

-- Tooltips go through EllesmereUI's own, per its contributing rules -- never GameTooltip
-- directly, so ours look and dismiss like every other tooltip in the suite.
-- The house tooltip's real signature is (frame, TEXT, OPTS) -- one string, no title/body
-- pair. The old call here put the body where opts belongs, and indexing a string for
-- option fields quietly yields nothing, so every tooltip in this addon rendered its title
-- alone and nobody got an error to notice. The two lines are now one string, and the
-- cursor anchor is the house option made for hover-to-read rows.
function ns.Tooltip(frame, title, body)
    local EUI = _G.EllesmereUI
    if not (EUI and EUI.ShowWidgetTooltip) then return end
    -- Composed at HOVER time, not attach time: the house tooltip accepts a function and
    -- resolves it on show, and a body that is itself a function can answer from data that
    -- did not exist yet when the row was built -- spell text loads async.
    local function Compose()
        local b = body
        if type(b) == "function" then b = b() end
        if b and b ~= "" then
            return "|cffF0A830" .. title .. "|r\n" .. b
        end
        return title
    end
    frame:SetScript("OnEnter", function(self)
        EUI.ShowWidgetTooltip(self, Compose, { anchor = "cursor", justify = "LEFT" })
    end)
    frame:SetScript("OnLeave", function() EUI.HideWidgetTooltip() end)
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
    dimmer:EnableKeyboard(true)
    dimmer:SetPropagateKeyboardInput(true)
    dimmer:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            self:Hide()
            self:SetPropagateKeyboardInput(false)
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)

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
--  EllesmereUI registration
-------------------------------------------------------------------------------
-- RegisterModule whitelists callers by their "AddOns/<folder>/" path via debugstack, and
-- only EllesmereUI's own folders are on the list. From a loadstring chunk the caller reads
-- as `[string ...]`, so the match fails and the guard falls through -- the same route the
-- suite already uses. EllesmereUI expects external pages: it marks them non-core and hides
-- the core-only toolbar controls for them.
local function RegisterModule(config)
    local EUI = _G.EllesmereUI
    if not (EUI and EUI.RegisterModule) then return end

    _G.__NaowhUITR_pendingReg = { key = MODULE_KEY, config = config }
    local trampoline = loadstring([[
        local r = _G.__NaowhUITR_pendingReg
        if r and EllesmereUI and EllesmereUI.RegisterModule then
            EllesmereUI:RegisterModule(r.key, r.config)
        end
    ]], "NaowhUITR-register")
    local ok = trampoline and pcall(trampoline)
    _G.__NaowhUITR_pendingReg = nil

    if not ok then
        pcall(function() EUI:RegisterModule(MODULE_KEY, config) end)
    end
end

-- Standalone only. With the companion loaded, its own row already carries our section and a
-- second one would just be a duplicate NaowhUI entry in the sidebar.
local function InjectSidebar()
    local EUI = _G.EllesmereUI
    if not EUI then return end

    -- alwaysLoaded hides the power toggle and marks the row loaded and clickable.
    EUI._addonInfoByFolder = EUI._addonInfoByFolder or {}
    EUI._addonInfoByFolder[MODULE_KEY] = EUI._addonInfoByFolder[MODULE_KEY] or {
        folder       = MODULE_KEY,
        display      = "NaowhUI",
        search_name  = "NaowhUI Naowh Smart Reminders Boss Defensive Tank",
        alwaysLoaded = true,
    }

    EUI._syncExempt = EUI._syncExempt or {}
    EUI._syncExempt[MODULE_KEY] = true   -- no cross-module profile sync

    -- Guard against double-insertion on reload, and against the companion having already
    -- made the group -- in which case we join it rather than add a second NaowhUI heading.
    EUI.ADDON_GROUPS = EUI.ADDON_GROUPS or {}
    for _, group in ipairs(EUI.ADDON_GROUPS) do
        if group.key == "naowhui" then
            for _, member in ipairs(group.members) do
                if member == MODULE_KEY then return end
            end
            group.members[#group.members + 1] = MODULE_KEY
            return
        end
    end
    table.insert(EUI.ADDON_GROUPS, 1, {
        key     = "naowhui",
        label   = "NaowhUI",
        members = { MODULE_KEY },
    })
end

-- Our settings already sit in the profile blob via Lite.NewDB, so they switch with profiles
-- for free. Export/import, though, walks EllesmereUI's own _ADDON_DB_MAP rather than the DB
-- registry, so an external addon is skipped unless it registers here. Both modes need this:
-- the DB is ours in either one.
local function InjectProfileAddon()
    local EUI = _G.EllesmereUI
    local map = EUI and EUI._ADDON_DB_MAP
    if type(map) ~= "table" then return end
    for _, e in ipairs(map) do
        if e.folder == MODULE_KEY then return end   -- guard against a reload re-inserting us
    end
    map[#map + 1] = { folder = MODULE_KEY, display = "NaowhUI Smart Reminders" }
end

-------------------------------------------------------------------------------
--  Boot
-------------------------------------------------------------------------------
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")

    local EUI = _G.EllesmereUI
    if not (EUI and EUI.RegisterModule) then
        ns.Print("|cffff6060EllesmereUI not found.|r NaowhUI Smart Reminders requires EllesmereUI "
            .. "to be installed and enabled.")
        return
    end

    -- Core is first in the toc and registers PLAYER_LOGIN first, so this runs before the
    -- runtime's own handler and before anything has called SettingsRoot.
    ns.RunMigrations()

    InjectProfileAddon()

    -- The companion resolves its page builders at call time and guards every one, so handing
    -- it ours is the whole integration: its Gameplay page picks the section up and its
    -- ResetAll picks the reset up. Nothing in NaowhUI_EUI has to change.
    -- The builders are handed over whenever the companion exists at all -- harmless on an
    -- old one, forward-compatible on a new one. Page OWNERSHIP is the separate question:
    -- only a companion that declares SUPPORTS_SMART_REMINDERS actually has a page entry
    -- that will call these. Trusting mere presence was a live failure: an installed but
    -- older companion made this addon defer to a page that did not exist, so it loaded
    -- fine and appeared nowhere. No handshake means we own our own sidebar entry.
    local companion = _G.NaowhUIEUI
    if companion then
        companion.BuildTankReminderPage = ns.BuildPage
        companion.ResetTankReminder = ns.Reset
    end
    if companion and companion.SUPPORTS_SMART_REMINDERS then
        ns.companionMode = true
    else
        InjectSidebar()
        RegisterModule({
            title       = "Naowh Smart Reminders",
            description = "Naowh's boss ability reminder for EllesmereUI.",
            -- Three real tabs -- EllesmereUI's own module system renders these as the top
            -- tab strip (BuildTabs) and calls buildPage once per tab, lazily, on first
            -- visit. pageName is genuinely read now, not just accepted and ignored.
            -- Raid/Dungeon Reminders used to be their own tabs here, each with its own
            -- boss picker duplicating the one already on Dungeon/Raid Bosses -- folded
            -- into that page's boss-detail cog instead (ns.ShowBossReminderPicker), so a
            -- boss is only ever picked once.
            pages       = { "Setup", "Dungeon Bosses", "Raid Bosses" },
            buildPage   = function(pageName, parent, yOffset)
                if pageName == "Dungeon Bosses" then
                    return ns.BuildBossTabPage and ns.BuildBossTabPage(parent, yOffset, false)
                        or math.abs(yOffset)
                elseif pageName == "Raid Bosses" then
                    return ns.BuildBossTabPage and ns.BuildBossTabPage(parent, yOffset, true)
                        or math.abs(yOffset)
                else -- "Setup"
                    return ns.BuildSetupPage and ns.BuildSetupPage(parent, yOffset)
                        or math.abs(yOffset)
                end
            end,
            onReset     = ns.Reset,
        })
    end

    -- Anything that swaps the active settings out from under us. The companion runs its own
    -- reapply chain, but ours is a different DB and it does not know about it.
    if EUI.SwitchProfile then hooksecurefunc(EUI, "SwitchProfile", ns.QueueReapply) end
    if EUI.OnSpecSwitchComplete then hooksecurefunc(EUI, "OnSpecSwitchComplete", ns.QueueReapply) end
    if EUI.ApplyProfileData then hooksecurefunc(EUI, "ApplyProfileData", ns.QueueReapply) end
end)
