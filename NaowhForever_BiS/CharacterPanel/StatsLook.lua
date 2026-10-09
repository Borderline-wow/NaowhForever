-- StatsLook.lua: the game's stats rows in the BiS List's look, styled as its list makes them (CP.StatsLook).
local ns = _G.NaowhForever

local T = ns.THEME
local CP = ns.CharacterPanel
local C = CP.C

local STAT_SIZE, CATEGORY_SIZE = C.TEXT_SIZE, C.SECTION_SIZE
local CATEGORY_X, CATEGORY_Y = 8, 8
local RULE_X, RULE_Y = 8, 4
local GAME_TITLE_Y = 1

local game = CP.PanelArt
local uppers = {}
local styled = setmetatable({}, { __mode = "k" })

local function Upper(text)
    local upper = uppers[text]
    if not upper then
        upper = text:upper()
        uppers[text], uppers[upper] = upper, upper
    end
    return upper
end

local function CategoryRule(frame)
    local line = styled[frame]
    if type(line) == "table" then return line end
    line = ns.Solid(frame, "ARTWORK", T.line, 1)
    line:SetPoint("BOTTOMLEFT", RULE_X, RULE_Y)
    line:SetPoint("BOTTOMRIGHT", -RULE_X, RULE_Y)
    ns.Hairline(line, "h")
    styled[frame] = line
    return line
end

local function StyleCategory(frame)
    local title = frame.Title
    game.Restyle(title, CATEGORY_SIZE, T.accentSoft)
    local text = title:GetText()
    if text then title:SetText(Upper(text)) end
    title:ClearAllPoints()
    title:SetPoint("BOTTOMLEFT", CATEGORY_X, CATEGORY_Y)
    CategoryRule(frame):Show()
end

local function StyleStat(_, frame)
    if not CP.On() then return end
    if frame.Background then frame.Background:SetAlpha(0) end
    if frame.Title then return StyleCategory(frame) end
    game.Restyle(frame.Label, STAT_SIZE, T.muted)
    game.Restyle(frame.Value, STAT_SIZE, T.fg)
    styled[frame] = styled[frame] or true
end

local function StyleFrame(frame)
    StyleStat(nil, frame)
end

local StatsLook = {}
CP.StatsLook = StatsLook

StatsLook.Style = StyleStat

function StatsLook.StyleAll(list)
    if list and list.ForEachFrame then list:ForEachFrame(StyleFrame) end
end

function StatsLook.Unstyle()
    for frame, line in pairs(styled) do
        if frame.Background then frame.Background:SetAlpha(1) end
        if type(line) == "table" then
            line:Hide()
            frame.Title:ClearAllPoints()
            frame.Title:SetPoint("CENTER", 0, GAME_TITLE_Y)
        end
    end
end
