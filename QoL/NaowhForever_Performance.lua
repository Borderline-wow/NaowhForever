-------------------------------------------------------------------------------
--  NaowhForever_Performance.lua -- the QoL Performance page: NaowhQOL's recommended
--  graphics, frame rate and network settings, applied all at once or one at a time, and the
--  spell queue window.
--
--  These are the game's own settings, which it keeps per computer, so the values they
--  replaced are kept in the account store rather than the profile. The first change to a
--  setting records what it was; restoring puts that back and forgets it. A setting the
--  Forever client does not have is left off the page.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local UI = ns.UI
local STATUS = UI.STATUS

local CATEGORIES = {
    { name = "RENDER & DISPLAY", cvars = {
        { "renderScale", "1", "Render Scale", "100%, native resolution" },
        { "VSync", "0", "VSync", "Off, for the highest frame rate" },
        { "MSAAQuality", "0", "Multisampling", "None" },
        { "LowLatencyMode", "3", "Low Latency Mode", "Reflex + Boost" },
        { "ffxAntiAliasingMode", "4", "Anti-Aliasing", "Advanced (CMAA2)" },
    } },
    { name = "GRAPHICS QUALITY", cvars = {
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
    { name = "VIEW DISTANCE & DETAIL", cvars = {
        { "graphicsViewDistance", "3", "View Distance", "Level 4" },
        { "graphicsEnvironmentDetail", "3", "Environment Detail", "Level 4" },
        { "graphicsGroundClutter", "0", "Ground Clutter", "Level 1" },
    } },
    { name = "RAID GRAPHICS", cvars = {
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
    { name = "ADVANCED", cvars = {
        { "GxMaxFrameLatency", "2", "Triple Buffering", "Off" },
        { "TextureFilteringMode", "5", "Texture Filtering", "16x Anisotropic" },
        { "shadowRt", "0", "Ray Traced Shadows", "Off" },
        { "ResampleQuality", "3", "Resample Quality", "FidelityFX SR 1.0" },
        { "GxApi", "D3D12", "Graphics API", "DirectX 12, after a game restart" },
        { "physicsLevel", "1", "Physics Integration", "Player Only" },
    } },
    { name = "FRAME RATE LIMITS", cvars = {
        { "useMaxFPS", "1", "Frame Rate Cap", "On" },
        { "maxFPS", "200", "Max Frame Rate", "200" },
        { "useTargetFPS", "0", "Target Frame Rate", "Off" },
        { "useMaxFPSBk", "1", "Background Frame Rate Cap", "On" },
        { "maxFPSBk", "30", "Background Frame Rate", "30, while the game is not in focus" },
        { "maxFPSLoading", "30", "Loading Screen Frame Rate", "30" },
    } },
    { name = "POST PROCESSING & EFFECTS", cvars = {
        { "ResampleSharpness", "0", "Resample Sharpness", "0, neutral" },
        { "ResampleAlwaysSharpen", "1", "Always Sharpen", "On" },
        { "cameraShake", "0", "Camera Shake", "Off" },
        { "ffxDeath", "0", "Death Effect", "Off" },
        { "ffxGlow", "0", "Glow Effect", "Off" },
        { "overrideScreenFlash", "1", "Override Screen Flash", "On" },
        { "ShakeStrengthCamera", "0", "Camera Shake Strength", "Off" },
        { "ShakeStrengthUI", "0", "UI Shake Strength", "Off" },
    } },
    { name = "NETWORK, LOGGING & INTERFACE", cvars = {
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
    ns.Confirm("Some settings only take effect after a reload. Reload UI now?", ReloadUI)
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

local function CVarRow(c)
    if not c then return { type = "label", text = "" } end
    local cvar, value, name, desc = c[1], c[2], c[3], c[4]
    return { type = "toggle", text = name,
        tooltip = ("Recommended: %s.|n|nOn sets it; off puts back the value you had before. "
            .. "Now: %s."):format(desc, tostring(C_CVar.GetCVar(cvar))),
        getValue = function() return AtValue(cvar, value) end,
        setValue = function(v)
            if CanChange() then
                if v then
                    SetRecommended(cvar, value)
                elseif not Restore(cvar) then
                    ns.Print(name .. " was already at this value before, so there is nothing to put back.")
                end
            end
            UI:RefreshPage(true)
        end }
end

function ns.BuildQoLPerformancePage(parent, y)
    local W = UI.Widgets
    local _, h

    _, h = W:SectionHeader(parent, "RECOMMENDED SETTINGS" .. STATUS.untested, y); y = y - h
    _, h = W:Note(parent, "NaowhQOL's recommended graphics, frame rate and network settings for "
        .. "a high, steady frame rate. Your own value is saved the first time each one changes, "
        .. "on this computer, and Restore All or turning a setting back off puts it back.", y); y = y - h
    _, h = W:Button(parent, "Apply All Recommended", y, ApplyAll); y = y - h
    _, h = W:Button(parent, "Restore All", y, function()
        ns.Confirm("Put back every setting this page has changed?", RestoreAll)
    end); y = y - h

    _, h = W:SectionHeader(parent, "SPELL QUEUE WINDOW", y); y = y - h
    _, h = W:DualRow(parent, y,
        { type = "slider", text = "Spell Queue Window (ms)", min = 0, max = 400, step = 1,
          tooltip = "How early you can press your next spell before the current one finishes. "
              .. "100 to 400 suits most: lower is more responsive, higher is more forgiving of "
              .. "latency. Melee around your ping + 100, ranged around your ping + 150.",
          getValue = function() return tonumber(C_CVar.GetCVar("SpellQueueWindow")) or 400 end,
          setValue = function(v) C_CVar.SetCVar("SpellQueueWindow", v) end },
        { type = "label", text = "" }
    ); y = y - h
    _, h = W:Button(parent, "Reload UI", y, ReloadUI); y = y - h

    _, h = W:SectionHeader(parent, "INDIVIDUAL SETTINGS", y); y = y - h
    for _, cat in ipairs(CATEGORIES) do
        local rows = {}
        for _, c in ipairs(cat.cvars) do
            if Exists(c[1]) then rows[#rows + 1] = c end
        end
        if #rows > 0 then
            _, h = W:Feature(parent, y, { type = "label", text = cat.name }); y = y - h
            for i = 1, #rows, 2 do
                _, h = W:DualRow(parent, y, CVarRow(rows[i]), CVarRow(rows[i + 1])); y = y - h
            end
        end
    end

    return y
end
