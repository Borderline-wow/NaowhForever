-- CampReader.lua: the Campfire rules: which camp bonuses you have, read from their auras and Camp Benefits' tooltip.
local ns = _G.NaowhForever

local A = ns.AuraBuffs
local S = A.Settings
local D = A.CampData
local FEATURES, EFFECT_TAGS, SAMPLE_BONUSES = D.FEATURES, D.EFFECT_TAGS, D.SAMPLE_BONUSES

local BIT_BASE = 2
local THOUSANDS = 3
local FIRST_LINE = 2
local LINE = { PATTERN = "^%s*(.-)%s*:%s*(%S.-)%s*$", WIDE = "^%s*(.-)%s*\239\188\154%s*(%S.-)%s*$",
    NUMBER = "(%d+)([%.,]?)(%d*)", MAX_UNKNOWN = 4, SHORT_EFFECT = 28, RETRY = 5 }
local COLOR_CODE, COLOR_END = "|c%x%x%x%x%x%x%x%x", "|r"
local WHOLE, DECIMAL = "%d", "%.1f"

local FEATURE_BY_TAG, featureByName = {}, {}
for i, feature in ipairs(FEATURES) do
    feature.bit = BIT_BASE ^ (i - 1)
    feature.points = feature.points or 1
    feature.numbers = feature.numbers or feature.points
    feature.labels = {}
    FEATURE_BY_TAG[feature.tag] = feature
    for _, alias in ipairs(feature.aliases or {}) do featureByName[alias] = feature end
end

local bonusTags, bonusFeatures = {}, {}
local barLabels, barIcons, sampleLabels, sampleIcons = {}, {}, {}, {}
local joinedTags, numberTexts = {}, {}
local Reader = { gen = 0, unknown = 0, unknownTexts = {}, tryGen = 0, nextTry = 0 }

local Camp = { tags = bonusTags, features = bonusFeatures, count = 0, text = "",
    barLabels = barLabels, barIcons = barIcons, barCount = 0, sampleLabels = sampleLabels, sampleIcons = sampleIcons }
A.Camp = Camp

local function Secret(v)
    return issecretvalue ~= nil and issecretvalue(v) and true or false
end

local function Points(feature, aura)
    if not aura then return nil end
    local points = aura.points
    if Secret(points) or type(points) ~= "table" then return nil end
    for i = 1, feature.points do
        local v = points[i]
        if Secret(v) or type(v) ~= "number" then return nil end
    end
    return points
end

local function NumberText(v)
    local text = numberTexts[v]
    if not text then
        text = v == math.floor(v) and WHOLE:format(v) or DECIMAL:format(v)
        numberTexts[v] = text
    end
    return text
end

local function BonusLabel(feature, amount)
    if not amount then return feature.short end
    local text = feature.labels[amount]
    if not text then
        text = "+" .. NumberText(amount) .. (feature.unit or "") .. " " .. ns.Color("muted", feature.short)
        feature.labels[amount] = text
    end
    return text
end

local function FeatureIcon(feature)
    if feature.icon == nil then feature.icon = C_Spell.GetSpellTexture(feature.id) or false end
    return feature.icon
end

local function Hidden(feature)
    local hidden = S.Get("campHiddenBonuses")
    return feature and hidden and hidden[feature.id] and true or false
end

function Reader.Names()
    local GetSpellName = C_Spell and C_Spell.GetSpellName
    if Reader.named or not GetSpellName then return end
    local all = true
    for i = 1, #FEATURES do
        local feature = FEATURES[i]
        if not feature.localName then
            local name = GetSpellName(feature.id)
            if name ~= nil and not Secret(name) and type(name) == "string" and name ~= "" then
                feature.localName = name
                featureByName[name] = feature
            else
                all = false
            end
        end
    end
    Reader.named = all
end

function Reader.FeatureOf(label, effect)
    local feature = featureByName[label]
    if feature then return feature end
    local lower = effect:lower()
    for i = 1, #EFFECT_TAGS do
        local entry = EFFECT_TAGS[i]
        if lower:find(entry[1], 1, true) then return FEATURE_BY_TAG[entry[2]] end
    end
end

function Reader.Number(whole, mark, part)
    if mark ~= "" and part ~= "" then
        if #part == THOUSANDS then return tonumber(whole .. part) end
        return tonumber(whole .. "." .. part)
    end
    return tonumber(whole)
end

function Reader.Numbers(feature, effect)
    feature.t1, feature.t2, feature.t3 = nil, nil, nil
    local want, k = feature.numbers, 0
    if want == 0 then return end
    for whole, mark, part in effect:gmatch(LINE.NUMBER) do
        k = k + 1
        local v = Reader.Number(whole, mark, part)
        if k == 1 then feature.t1 = v elseif k == 2 then feature.t2 = v else feature.t3 = v end
        if k >= want then break end
    end
    local period = feature.period
    if period and feature.t1 == period and feature.t2 and feature.t2 ~= period then
        feature.t1, feature.t2 = feature.t2, feature.t1
    end
end

function Reader.Unknown(text)
    local texts = Reader.unknownTexts
    for i = 1, Reader.unknown do
        if texts[i] == text then return end
    end
    if Reader.unknown < LINE.MAX_UNKNOWN then
        Reader.unknown = Reader.unknown + 1
        texts[Reader.unknown] = text
    end
end

function Reader.Line(row)
    local label, effect = row:match(LINE.PATTERN)
    if not label then label, effect = row:match(LINE.WIDE) end
    if not label or label == "" or label:find("[%d|]") or label:find("ID$") then return false end
    local feature = Reader.FeatureOf(label, effect)
    if not feature then
        Reader.Unknown(#effect <= LINE.SHORT_EFFECT and effect or label)
    elseif feature.tipGen ~= Reader.gen then
        feature.tipGen, feature.lineName = Reader.gen, label
        Reader.Numbers(feature, effect)
    end
    return true
end

function Reader.Settle()
    Reader.tryInstance, Reader.tryExpiry, Reader.tryGen = nil, nil, Reader.tryGen + 1
end

function Reader.Retry()
    Reader.armed = false
    if Reader.armedGen ~= Reader.tryGen or not Reader.tryInstance then return end
    local wait = Reader.nextTry - GetTime()
    if wait > 0 then
        Reader.armed = true
        C_Timer.After(wait, Reader.Retry)
        return
    end
    Camp.Refresh()
end

function Reader.Again(instance, expiry)
    if instance ~= Reader.tryInstance or expiry ~= Reader.tryExpiry then
        Reader.tryInstance, Reader.tryExpiry, Reader.tryGen = instance, expiry, Reader.tryGen + 1
    end
    Reader.nextTry, Reader.armedGen = GetTime() + LINE.RETRY, Reader.tryGen
    if not Reader.armed then
        Reader.armed = true
        C_Timer.After(LINE.RETRY, Reader.Retry)
    end
end

function Reader.Tooltip(lines)
    local found = false
    for i = FIRST_LINE, #lines do
        local text = lines[i] and lines[i].leftText
        if text ~= nil and not Secret(text) and type(text) == "string" then
            text = text:gsub(COLOR_CODE, ""):gsub(COLOR_END, "")
            for row in text:gmatch("[^\n]+") do
                if Reader.Line(row) then found = true end
            end
        end
    end
    return found
end

function Reader.Camp(aura)
    local instance, expiry = aura.auraInstanceID, aura.expirationTime
    if Secret(instance) or Secret(expiry) then
        Reader.gen, Reader.instance, Reader.unknown = Reader.gen + 1, nil, 0
        Reader.Settle()
        return
    end
    if instance ~= nil and instance == Reader.instance and expiry == Reader.expiry then return end
    if instance ~= nil and instance == Reader.tryInstance and expiry == Reader.tryExpiry
        and GetTime() < Reader.nextTry then return end
    Reader.Names()
    Reader.gen, Reader.instance, Reader.expiry, Reader.unknown = Reader.gen + 1, nil, nil, 0
    local data = instance and C_TooltipInfo.GetUnitBuffByAuraInstanceID("player", instance)
    local lines = data and data.lines
    local found = type(lines) == "table" and Reader.Tooltip(lines)
    if found then
        Reader.instance, Reader.expiry = instance, expiry
        Reader.Settle()
    elseif instance ~= nil then
        Reader.Again(instance, expiry)
    end
end

function Reader.Add(n, feature, a1, a2, a3)
    n = n + 1
    if feature.period and a1 and not a2 then a2 = feature.period end
    feature.a1, feature.a2, feature.a3 = a1, a2, a3
    bonusTags[n], bonusFeatures[n] = feature.tag, feature
    return n
end

function Reader.Merge(tip)
    local n, mask = 0, 0
    for i = 1, #FEATURES do
        local feature = FEATURES[i]
        local found = C_UnitAuras.GetPlayerAuraBySpellID(feature.id)
        if found then
            local p, count = feature.amount and Points(feature, found), feature.points
            n = Reader.Add(n, feature, p and p[1] or nil, p and count >= 2 and p[2] or nil,
                p and count >= 3 and p[3] or nil)
            mask = mask + feature.bit
        elseif tip and feature.tipGen == Reader.gen then
            n = Reader.Add(n, feature, feature.t1, feature.t2, feature.t3)
            mask = mask + feature.bit
        end
    end
    if not tip then return n, mask end
    local texts = Reader.unknownTexts
    for i = 1, Reader.unknown do
        n = n + 1
        bonusTags[n], bonusFeatures[n] = texts[i], false
    end
    return n, mask
end

function Reader.Join(n, mask, unknown)
    if unknown then
        if Reader.joinedGen ~= Reader.gen or Reader.joinedMask ~= mask then
            Reader.joined = table.concat(bonusTags, "\n", 1, n)
            Reader.joinedGen, Reader.joinedMask = Reader.gen, mask
        end
        return Reader.joined
    end
    local text = joinedTags[mask]
    if not text then
        text = table.concat(bonusTags, "\n", 1, n)
        joinedTags[mask] = text
    end
    return text
end

Camp.Secret = Secret
Camp.Hidden = Hidden
Camp.BonusLabel = BonusLabel

function Camp.Refresh() end

function Camp.Simple()
    return S.Get("campStyle") == "simple"
end

function Camp.InOpenWorld()
    local inInstance = IsInInstance()
    return not inInstance
end

function Camp.BonusWords(feature)
    local a1, a2, a3, count = feature.a1, feature.a2, feature.a3, feature.numbers
    if not (feature.amount and a1) then return feature.stat or feature.short end
    if count == 1 or (count == 2 and a2) or (count == 3 and a2 and a3) then
        return feature.amount:format(NumberText(a1), a2 and NumberText(a2), a3 and NumberText(a3))
    end
    return "+" .. NumberText(a1) .. (feature.unit or "") .. " " .. feature.stat
end

function Camp.FeatureName(feature)
    Reader.Names()
    return feature.lineName or feature.localName or feature.name or ""
end

function Camp.FilterBar()
    local icons, n = S.Get("campBonusIcons"), 0
    for i = 1, Camp.count do
        local feature = bonusFeatures[i]
        if not Hidden(feature) then
            n = n + 1
            barLabels[n] = feature and BonusLabel(feature, feature.a1) or bonusTags[i]
            barIcons[n] = icons and feature and FeatureIcon(feature) or false
        end
    end
    Camp.barCount = n
end

function Camp.FillSamples(filter)
    local icons, n = S.Get("campBonusIcons"), 0
    for i = 1, #SAMPLE_BONUSES do
        local feature, amount = SAMPLE_BONUSES[i][1], SAMPLE_BONUSES[i][2]
        if not (filter and Hidden(feature)) then
            n = n + 1
            sampleLabels[n] = BonusLabel(feature, amount)
            sampleIcons[n] = icons and FeatureIcon(feature) or false
        end
    end
    return n
end

function Camp.ReadBonuses(aura)
    if aura then Reader.Camp(aura) end
    local tip = aura ~= nil and Reader.instance ~= nil
    local n, mask = Reader.Merge(tip)
    if n == 0 and not aura then return false end
    Camp.text = Reader.Join(n, mask, tip and Reader.unknown > 0)
    Camp.count = n
    if Camp.Simple() then Camp.FilterBar() end
    return n > 0
end
