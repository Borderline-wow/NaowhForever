-------------------------------------------------------------------------------
--  NaowhUI_TankReminder_Core.lua -- DB, settings-page injection, profile plumbing.
--
--  Standalone: EllesmereUI is the only hard dependency. NaowhUI_EUI is optional and only
--  changes WHERE the settings land -- with it we add a section to the existing NaowhUI
--  group's Gameplay page, without it we register that group ourselves. Either way the
--  settings live under our OWN profile key, so uninstalling the companion never orphans
--  them and a profile string carries this addon on its own.
-------------------------------------------------------------------------------
local ADDON_NAME = ...

-- Must match the addon folder: EllesmereUI's sidebar and profile map both key off it.
-- Renamed with the addon (was NaowhUI_TankReminder); SettingsRoot migrates the old
-- profile key so nobody's lists are lost to the rename.
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

function ns.Button(parent, text, w, h, onClick)
    local EUI = _G.EllesmereUI
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(w, h)
    if EUI and EUI.MakeStyledButton and EUI.WB_COLOURS then
        EUI.MakeStyledButton(btn, text, 12, EUI.WB_COLOURS, onClick)
    else
        local bg = ns.Solid(btn, "BACKGROUND", ns.THEME.line, 0.6)
        bg:SetAllPoints()
        local lbl = ns.Font(btn, 12, nil)
        lbl:SetPoint("CENTER"); lbl:SetText(text)
        btn:SetScript("OnClick", function() if onClick then onClick() end end)
    end
    return btn
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

-- A dimmed modal shell: click-off to dismiss, house border and panel fill. Returns the
-- dimmer (show/hide this) and the panel to fill.
function ns.MakeModal(width, height)
    local dimmer = CreateFrame("Frame", nil, UIParent)
    dimmer:SetAllPoints(UIParent)
    dimmer:SetFrameStrata("FULLSCREEN_DIALOG")
    dimmer:EnableMouse(true)
    -- Modals stack: the reminder editor opens from inside the instance modal, and with
    -- both on the same strata, creation order decided who was on top -- an editor built
    -- before the modal sat invisibly behind it. Raising on every show makes the newest
    -- opened modal the visible one, whatever order they were built in.
    dimmer:SetScript("OnShow", function(self) self:Raise() end)
    dimmer:Hide()
    local dim = ns.Solid(dimmer, "BACKGROUND", ns.THEME.bg, 0.55)
    dim:SetAllPoints()
    dimmer:SetScript("OnMouseDown", function(self) self:Hide() end)

    local panel = CreateFrame("Frame", nil, dimmer)
    panel:SetSize(width, height)
    panel:SetPoint("CENTER")
    panel:SetFrameStrata("FULLSCREEN_DIALOG")
    panel:SetFrameLevel(dimmer:GetFrameLevel() + 10)
    panel:EnableMouse(true)
    local bg = ns.Solid(panel, "BACKGROUND", ns.THEME.panel, 1)
    bg:SetAllPoints()
    ns.Border(panel)

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
            -- The addon shipped for a while as NaowhUI_TankReminder, and the profile map
            -- keys by module, so a fresh key means every existing list would look wiped.
            -- One-way copy, old left in place: harmless, and a downgrade still works.
            if next(_settingsDB.profile) == nil then
                local ok, old = pcall(L.NewDB, "NaowhUI_TankReminderDB", { profile = {} })
                if ok and old and type(old.profile) == "table" and next(old.profile) ~= nil then
                    for k, v in pairs(old.profile) do _settingsDB.profile[k] = v end
                end
            end
            return _settingsDB.profile
        end
    end
    -- EllesmereUI absent or too old: degrade to the account table rather than error.
    if type(_G.NaowhUITankReminderDB) ~= "table" then _G.NaowhUITankReminderDB = {} end
    return _G.NaowhUITankReminderDB
end

-------------------------------------------------------------------------------
--  Combat deferral
-------------------------------------------------------------------------------
-- Frames are never garbage collected, so share one rather than make one per deferral.
local deferFrame, deferQueue

function ns.RunOutOfCombat(fn)
    if not InCombatLockdown() then return fn() end

    if not deferFrame then
        deferQueue = {}
        deferFrame = CreateFrame("Frame")
        deferFrame:SetScript("OnEvent", function(self)
            self:UnregisterEvent("PLAYER_REGEN_ENABLED")
            -- Swap the queue out first: a deferred call can queue another one.
            local q = deferQueue
            deferQueue = {}
            for i = 1, #q do
                local ok, err = pcall(q[i])
                if not ok then ns.Print("deferred call failed: " .. tostring(err)) end
            end
        end)
    end

    deferQueue[#deferQueue + 1] = fn
    deferFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
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
        ns.Print("|cffff6060EllesmereUI not found.|r NaowhUI_TankReminder requires EllesmereUI "
            .. "to be installed and enabled.")
        return
    end

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
            title       = "NaowhUI",
            description = "Naowh's boss ability reminder for EllesmereUI.",
            pages       = { "Smart Reminders" },
            buildPage   = function(_, parent, yOffset)
                return ns.BuildPage and ns.BuildPage(parent, yOffset) or math.abs(yOffset)
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
