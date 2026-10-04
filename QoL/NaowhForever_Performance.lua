-------------------------------------------------------------------------------
--  NaowhForever_Performance.lua -- the QoL Performance page: NaowhQOL's recommended game settings.
--  The game keeps those per computer, so the values they replaced live in the account store.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local UI = ns.UI

local CATEGORIES = {
    { name = "Render & Display", cvars = {
        { "renderScale", "1", "Render Scale", "100%, native resolution" },
        { "VSync", "0", "VSync", "Off, for the highest frame rate" },
        { "MSAAQuality", "0", "Multisampling", "None" },
        { "LowLatencyMode", "3", "Low Latency Mode", "Reflex + Boost" },
        { "ffxAntiAliasingMode", "4", "Anti-Aliasing", "Advanced (CMAA2)" },
    } },
    { name = "Graphics Quality", cvars = {
        { "graphicsShadowQuality", "1", "Shadow Quality", "Fair" },
        { "graphicsLiquidDetail", "2", "Liquid Detail", "Good" },
        { "graphicsParticleDensity", "3", "Particle Density", "Good" },
        { "graphicsSSAO", "0", "SSAO", "Off" },
        { "graphicsDepthEffects", "0", "Depth Effects", "Off" },
        { "graphicsComputeEffects", "0", "Compute Effects", "Off" },
        { "graphicsOutlineMode", "2", "Outline Mode", "High" },
        { "graphicsTextureResolution", "2", "Texture Resolution", "High" },
        { "graphicsSpellDensity", "0", "Spell Density", "Essential" },
        { "graphicsProjectedTextures", "1", "Projected Textures", "On" },
    } },
    { name = "View Distance & Detail", cvars = {
        { "graphicsViewDistance", "3", "View Distance", "Level 4" },
        { "graphicsEnvironmentDetail", "3", "Environment Detail", "Level 4" },
        { "graphicsGroundClutter", "0", "Ground Clutter", "Level 1" },
    } },
    { name = "Raid Graphics", cvars = {
        { "RAIDsettingsEnabled", "1", "Separate Raid Settings", "On" },
        { "raidGraphicsShadowQuality", "0", "Raid Shadow Quality", "Low" },
        { "raidGraphicsLiquidDetail", "0", "Raid Liquid Detail", "Low" },
        { "raidGraphicsParticleDensity", "3", "Raid Particle Density", "Good" },
        { "raidGraphicsSSAO", "0", "Raid SSAO", "Off" },
        { "raidGraphicsDepthEffects", "0", "Raid Depth Effects", "Off" },
        { "raidGraphicsComputeEffects", "0", "Raid Compute Effects", "Off" },
        { "raidGraphicsOutlineMode", "2", "Raid Outline Mode", "High" },
        { "raidGraphicsTextureResolution", "2", "Raid Texture Resolution", "High" },
        { "raidGraphicsSpellDensity", "0", "Raid Spell Density", "Essential" },
        { "raidGraphicsProjectedTextures", "1", "Raid Projected Textures", "On" },
        { "raidGraphicsViewDistance", "0", "Raid View Distance", "Level 1" },
        { "raidGraphicsEnvironmentDetail", "0", "Raid Environment Detail", "Level 1" },
        { "raidGraphicsGroundClutter", "0", "Raid Ground Clutter", "Level 1" },
    } },
    { name = "Advanced", cvars = {
        { "GxMaxFrameLatency", "2", "Triple Buffering", "Off" },
        { "TextureFilteringMode", "5", "Texture Filtering", "16x Anisotropic" },
        { "shadowRt", "0", "Ray Traced Shadows", "Off" },
        { "ResampleQuality", "3", "Resample Quality", "FidelityFX SR 1.0" },
        { "GxApi", "D3D12", "Graphics API", "DirectX 12, after a game restart" },
        { "physicsLevel", "1", "Physics Integration", "Player Only" },
    } },
    { name = "Frame Rate Limits", cvars = {
        { "useMaxFPS", "1", "Frame Rate Cap", "On" },
        { "maxFPS", "200", "Max Frame Rate", "200" },
        { "useTargetFPS", "0", "Target Frame Rate", "Off" },
        { "useMaxFPSBk", "1", "Background Frame Rate Cap", "On" },
        { "maxFPSBk", "30", "Background Frame Rate", "30, while the game is not in focus" },
        { "maxFPSLoading", "30", "Loading Screen Frame Rate", "30" },
    } },
    { name = "Post Processing & Effects", cvars = {
        { "ResampleSharpness", "0", "Resample Sharpness", "0, neutral" },
        { "ResampleAlwaysSharpen", "1", "Always Sharpen", "On" },
        { "cameraShake", "0", "Camera Shake", "Off" },
        { "ffxDeath", "0", "Death Effect", "Off" },
        { "ffxGlow", "0", "Glow Effect", "Off" },
        { "overrideScreenFlash", "1", "Override Screen Flash", "On" },
        { "ShakeStrengthCamera", "0", "Camera Shake Strength", "Off" },
        { "ShakeStrengthUI", "0", "UI Shake Strength", "Off" },
    } },
    { name = "Network, Logging & Interface", cvars = {
        { "advancedCombatLogging", "1", "Advanced Combat Logging", "On" },
        { "disableServerNagle", "1", "Disable Server Nagle", "On, for lower latency" },
        { "AutoPushSpellToActionBar", "0", "Auto Push Spells to Bars", "Off" },
        { "cameraDistanceMaxZoomFactor", "2.6", "Max Camera Zoom", "2.6x" },
        { "nameplateShowFriendlyClassColor", "1", "Friendly Class Colours", "On" },
        { "UnitNameFriendlyPlayerName", "1", "Friendly Player Names", "On" },
    } },
}

local function Backups()
    local account = ns.AccountSettings()
    account.cvarBackups = account.cvarBackups or {}
    return account.cvarBackups
end

local function Exists(cvar)
    return C_CVar.GetCVar(cvar) ~= nil
end

local function AtValue(cvar, value)
    local current = C_CVar.GetCVar(cvar)
    local a, b = tonumber(current), tonumber(value)
    if a and b then return math.abs(a - b) < 0.001 end
    return current == value
end

local function CanChange()
    if InCombatLockdown() then
        ns.Print("Game settings can only be changed out of combat.")
        return false
    end
    return true
end

local function SetRecommended(cvar, value)
    if AtValue(cvar, value) then return false end
    local backups = Backups()
    if backups[cvar] == nil then backups[cvar] = C_CVar.GetCVar(cvar) end
    return C_CVar.SetCVar(cvar, value)
end

local function Restore(cvar)
    local backups = Backups()
    if backups[cvar] == nil then return false end
    C_CVar.SetCVar(cvar, backups[cvar])
    backups[cvar] = nil
    return true
end

local function OfferReload()
    ns.ConfirmReload("Some settings only take effect after a reload. Reload UI now?")
end

local function ApplyAll()
    if not CanChange() then return end
    local count = 0
    for _, cat in ipairs(CATEGORIES) do
        for _, c in ipairs(cat.cvars) do
            if Exists(c[1]) and SetRecommended(c[1], c[2]) then count = count + 1 end
        end
    end
    ns.Print(("Applied %d recommended setting%s. Restore All puts yours back."):format(count, count == 1 and "" or "s"))
    UI:RefreshPage(true)
    if count > 0 then OfferReload() end
end

local function RestoreAll()
    if not CanChange() then return end
    local count = 0
    for cvar in pairs(Backups()) do
        if Restore(cvar) then count = count + 1 end
    end
    ns.Print(("Restored %d setting%s."):format(count, count == 1 and "" or "s"))
    UI:RefreshPage(true)
    if count > 0 then OfferReload() end
end

local function SetOne(cvar, value, name, on)
    if CanChange() then
        if on then
            SetRecommended(cvar, value)
        elseif not Restore(cvar) then
            ns.Print(name .. " was already at this value before, so there is nothing to put back.")
        end
    end
    UI:RefreshPage(true)
end

local function SpellQueueGet()
    return tonumber(C_CVar.GetCVar("SpellQueueWindow")) or 400
end

local function SpellQueueSet(v)
    C_CVar.SetCVar("SpellQueueWindow", v)
end

local function ConfirmRestoreAll()
    ns.Confirm("Put back every setting this page has changed?", RestoreAll)
end

local Group = ns.Shared.Settings.Group
local HEAD = {
    Group("Recommended"),
    { label = "Apply All Recommended", buttonText = "Apply All", button = ApplyAll,
      help = "Sets every recommended setting below. Your own value is saved first, so Restore All can put "
          .. "it back." },
    { label = "Restore All", buttonText = "Restore All", button = ConfirmRestoreAll,
      help = "Puts back every setting this page has changed, to the value you had before." },
    Group("Spell Queue"),
    { label = "Spell Queue Window", slider = { 0, 400, 1 }, unit = "ms", get = SpellQueueGet, set = SpellQueueSet,
      help = "How early you can press your next spell before the current one finishes, in milliseconds. "
          .. "100 to 400 suits most: lower is more responsive, higher is more forgiving of latency. Melee "
          .. "around your ping + 100, ranged around your ping + 150." },
    { label = "Reload UI", buttonText = "Reload UI", button = OfferReload,
      help = "Some settings only take effect after a reload." },
}
for _, cat in ipairs(CATEGORIES) do cat.group = Group(cat.name) end

local cvarRows, rows = {}, {}

local function CVarRow(c)
    local row = cvarRows[c]
    if not row then
        local cvar, value, name = c[1], c[2], c[3]
        row = { label = name, toggle = true,
            get = function() return AtValue(cvar, value) end,
            set = function(on) SetOne(cvar, value, name, on) end }
        cvarRows[c] = row
    end
    row.help = ("Recommended: %s.|n|nOn sets it; off puts back the value you had before. Now: %s."):format(
        c[4], tostring(C_CVar.GetCVar(c[1])))
    return row
end

local function Rows()
    wipe(rows)
    for i = 1, #HEAD do rows[i] = HEAD[i] end
    for _, cat in ipairs(CATEGORIES) do
        local grouped = false
        for _, c in ipairs(cat.cvars) do
            if Exists(c[1]) then
                if not grouped then
                    rows[#rows + 1] = cat.group
                    grouped = true
                end
                rows[#rows + 1] = CVarRow(c)
            end
        end
    end
    return rows
end

local function Summary()
    local on, total = 0, 0
    for _, cat in ipairs(CATEGORIES) do
        for _, c in ipairs(cat.cvars) do
            if Exists(c[1]) then
                total = total + 1
                if AtValue(c[1], c[2]) then on = on + 1 end
            end
        end
    end
    return ("%d of %d recommended settings in use"):format(on, total)
end

ns.Shared.Settings.Page("QoL/System", ns.QoLSettings):Card({
    id = "performance", name = "Performance", order = 10,
    help = "NaowhQOL's recommended graphics, frame rate and network settings for a high, steady frame rate. "
        .. "Your own value is saved the first time each one changes, on this computer, and Restore All or "
        .. "turning a setting back off puts it back.",
    summary = Summary,
    rows = Rows,
})
