-- Watch.lua: Blizzard's managed aura display over a button, showing a buff and its time left, in combat too.
local ns = _G.NaowhForever

local B = ns.Blessings
local S = B.Settings
local Parts = ns.Shared.Parts
local IDS = B.IDS

local AURA_ADDON = "Blizzard_AuraContainer"
local LEVEL_ABOVE = 2
local ICON_CROP = B.Look.ICON_CROP
local TEXT_Y = 1

local watchUnavailable

local function Container(frame)
    C_AddOns.LoadAddOn(AURA_ADDON)
    local c = CreateFrame("AuraContainer", nil, frame, "CustomAuraContainerTemplate")
    c:SetAllPoints(frame)
    c:SetFrameLevel(frame:GetFrameLevel() + LEVEL_ABOVE)
    c:EnableMouse(false)
    c:AddAuraSlot("buff", "HELPFUL", {
        candidateFilters = { includeSpellIDs = {} },
        initializeFrame = function(button)
            button:SetAllPoints(frame.icon)
            button:EnableMouse(false)
            local icon = button:CreateTexture(nil, "ARTWORK")
            icon:SetAllPoints()
            icon:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
            button:SetIcon(icon)
            local text = button:CreateFontString(nil, "OVERLAY")
            Parts.HudFont(text, S.Get("blessFont"), S.Get("blessTimerSize"), S.Get("blessOutline"))
            frame.watchText = text
            text:SetPoint("BOTTOM", 0, TEXT_Y)
            button:SetDurationText(text, {})
        end,
    })
    c:SetEnabled(false)
    return c
end

function B.Watch(frame)
    if watchUnavailable then return end
    local ok, container = pcall(Container, frame)
    if not ok then
        watchUnavailable = true
        return
    end
    frame.watch = container
end

function B.SetWatch(frame, unit, key)
    local c = frame.watch
    if not c or (frame.watchUnit == unit and frame.watchKey == key) then return end
    frame.watchUnit, frame.watchKey = unit, key
    c:SetUnit(unit or "none")
    c:SetAuraSlotCandidateFilters("buff", { includeSpellIDs = key and IDS[key] or {} })
    c:SetEnabled(unit ~= nil and key ~= nil)
end
