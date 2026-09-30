-------------------------------------------------------------------------------
--  NaowhForever_Search.lua -- find a setting anywhere in the options window and jump to it.
--
--  Nothing is built or scanned until the player types. The first keystroke of a search
--  runs the page builders in scan mode (UI.searchScan, see the row widgets): each row says
--  what it is called and builds nothing. Pages marked `noscan` in Window.lua are the ones
--  whose builders do more than draw rows -- their own frames, writes, journal reads -- and
--  are found by module and tab name only. Rows that only exist under some settings are
--  found only while they exist.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local T = ns.THEME
local UI = ns.UI

local MAX_RESULTS, RESULT_H, PANEL_W = 12, 36, 400
local box, panel, active
local results = {}          -- the entries the panel shows right now
local failed = {}           -- pages whose builder errored in the last scan (for /dump)

-- A parent that answers every call with 0. A builder that does more than call the row
-- widgets fails on it before it can build anything, and that page stays out of the index.
local STUB = setmetatable({}, { __index = function() return function() return 0 end end })
local STATUS_WORDS = { "UNTESTED", "READY", "LIMITED", "NOT POSSIBLE YET" }

local function Trim(text)
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- A section header without its colour codes and the status tag the page appended.
local function Plain(text)
    text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
    text = text:gsub("|r", "")
    for _, word in ipairs(STATUS_WORDS) do text = text:gsub("%s+" .. word .. "$", "") end
    return Trim(text)
end

local function Crumb(page)
    if page.module then return ns.L(page.module.name) .. " > " .. ns.L(page.name) end
    return ns.L(page.title or page.name)
end

-- feature is the W:Feature the setting sits under, which the jump opens; its name joins
-- the breadcrumb.
local function Entry(page, crumb, label, section, tooltip, feature, featureName)
    if featureName and featureName ~= label then crumb = crumb .. " > " .. Plain(featureName) end
    return { key = page.key, crumb = crumb, crumbLower = crumb:lower(),
        label = label, labelLower = label and label:lower(),
        sectionLower = section and section ~= "" and section:lower() or nil,
        tipLower = tooltip and tooltip:lower() or nil, feature = feature }
end

-- Every page by name, and every scannable page's settings.
local function BuildIndex()
    local index = {}
    for i = #failed, 1, -1 do failed[i] = nil end
    for _, page in ipairs(UI.SearchPages()) do
        local crumb = Crumb(page)
        index[#index + 1] = Entry(page, crumb)
        if not (page.noscan or page.soon) and ns[page.build] then
            local scan = { section = "", items = {}, page = page.key }
            UI.searchScan = scan
            local ok = pcall(ns[page.build], STUB, -6, page.arg)
            UI.searchScan = nil
            -- What a page said before it failed still counts.
            for _, item in ipairs(scan.items) do
                index[#index + 1] = Entry(page, crumb, item.label, Plain(item.section), item.tooltip,
                    item.feature, item.featureName)
            end
            if not ok then failed[#failed + 1] = page.key end
        end
    end
    return index
end

-- Every word has to appear: in the setting's name (3), its section, tab or module (2), or
-- its tooltip (1). A page by name ranks just under a setting that scores the same.
local function Score(entry, words)
    local score = 0
    for _, word in ipairs(words) do
        if entry.labelLower and entry.labelLower:find(word, 1, true) then
            score = score + 3
        elseif entry.crumbLower:find(word, 1, true)
            or (entry.sectionLower and entry.sectionLower:find(word, 1, true)) then
            score = score + 2
        elseif entry.tipLower and entry.tipLower:find(word, 1, true) then
            score = score + 1
        else
            return nil
        end
    end
    return entry.label and score or score - 0.5
end

local function Match(index, query, limit)
    local words = {}
    for word in query:lower():gmatch("%S+") do words[#words + 1] = word end
    if #words == 0 then return {} end
    local found = {}
    for i, entry in ipairs(index) do
        local score = Score(entry, words)
        if score then found[#found + 1] = { entry = entry, score = score, order = i } end
    end
    table.sort(found, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return a.order < b.order
    end)
    local out = {}
    for i = 1, math.min(#found, limit or MAX_RESULTS) do out[i] = found[i].entry end
    return out
end

UI.Search = { Build = BuildIndex, Match = Match, Plain = Plain, failed = failed }

-------------------------------------------------------------------------------
--  The box and its results
-------------------------------------------------------------------------------
local function HidePanel()
    if panel then panel:Hide() end
    results = {}
end

-- The search's marks go first, so the jump measures the page as it will stay; pages marked
-- while typing are drawn again once it has landed.
local function Jump(entry)
    UI.searchWords, UI.searchOpen = nil, nil
    if box then box:SetText(""); box:ClearFocus() end
    UI.GoToSetting(entry.key, entry.label, entry.feature)
    UI:RefreshPage(true)
end

local function NewPanel()
    panel = CreateFrame("Frame", nil, box)
    panel:SetFrameLevel(math.min(box:GetFrameLevel() + 100, 9999))
    panel:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -2)
    panel:SetWidth(PANEL_W)
    panel:EnableMouse(true)
    ns.Solid(panel, "BACKGROUND", T.panel, 0.98):SetAllPoints()
    ns.Border(panel)
    panel.rows = {}
    for i = 1, MAX_RESULTS do
        local row = CreateFrame("Button", nil, panel)
        row:SetHeight(RESULT_H)
        row:SetPoint("TOPLEFT", panel, "TOPLEFT", 1, -1 - (i - 1) * RESULT_H)
        row:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -1, -1 - (i - 1) * RESULT_H)
        row.hover = ns.Solid(row, "BACKGROUND", T.grey, 0.5)
        row.hover:SetAllPoints()
        row.hover:Hide()
        row.label = ns.Font(row, 13, nil)
        row.label:SetPoint("TOPLEFT", 10, -5)
        row.label:SetPoint("RIGHT", -10, 0)
        row.label:SetJustifyH("LEFT")
        row.label:SetWordWrap(false)
        row.crumb = ns.Font(row, 10, nil, T.muted)
        row.crumb:SetPoint("TOPLEFT", row.label, "BOTTOMLEFT", 0, -2)
        row.crumb:SetPoint("RIGHT", -10, 0)
        row.crumb:SetJustifyH("LEFT")
        row.crumb:SetWordWrap(false)
        row:SetScript("OnEnter", function(self) self.hover:Show() end)
        row:SetScript("OnLeave", function(self) self.hover:Hide() end)
        row:SetScript("OnClick", function(self) if self.entry then Jump(self.entry) end end)
        panel.rows[i] = row
    end
    panel.none = ns.Font(panel, 12, nil, T.muted)
    panel.none:SetPoint("TOPLEFT", 10, -10)
    panel.none:SetText(ns.L("No setting matches."))
end

local function ShowResults(found)
    if not panel then NewPanel() end
    results = found
    for i, row in ipairs(panel.rows) do
        local entry = found[i]
        row.entry = entry
        row:SetShown(entry ~= nil)
        if entry then
            row.label:SetText(entry.label or entry.crumb)
            row.crumb:SetText(entry.label and entry.crumb or ns.L("Page"))
        end
    end
    panel.none:SetShown(#found == 0)
    panel:SetHeight(math.max(#found, 1) * RESULT_H + 2)
    panel:Show()
end

-- While a search is typed, the page on show marks the rows that match and opens the
-- features holding one; clearing it puts the page back.
-- A setting holding every word in its own name or tooltip: what gets marked, and whose
-- feature opens. A hit on the page or section name alone does neither.
local function RowHit(entry, words)
    if not entry.labelLower then return false end
    for _, word in ipairs(words) do
        if not (entry.labelLower:find(word, 1, true) or (entry.tipLower and entry.tipLower:find(word, 1, true))) then
            return false
        end
    end
    return true
end

local function MarkPage(text)
    local words
    for word in text:lower():gmatch("%S+") do
        words = words or {}
        words[#words + 1] = word
    end
    if not (words or UI.searchWords) then return end
    local open
    for _, entry in ipairs(words and UI.searchIndex or {}) do
        if entry.feature and RowHit(entry, words) then
            open = open or {}
            open[entry.feature] = true
        end
    end
    UI.searchWords, UI.searchOpen = words, open
    -- Clearing redraws every page that was marked; typing only the one on show.
    if words then UI.RefreshSearchMarks() else UI:RefreshPage(true) end
end

local function OnText(text)
    text = Trim(text)
    if text == "" then
        active = false
        HidePanel()
        MarkPage("")
        return
    end
    -- The index is rebuilt at the start of every search, so it matches the settings as
    -- they are now.
    if not active then
        active = true
        UI.searchIndex = BuildIndex()
    end
    ShowResults(Match(UI.searchIndex, text))
    MarkPage(text)
end

-- Called once, when the window is made.
function UI.AttachSearch(sidebar, top)
    box = ns.NewSearchBox(sidebar, "Search settings", OnText)
    box:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 14, -top)
    box:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", -14, -top)
    box:SetHeight(24)
    box:SetScript("OnEnterPressed", function(self)
        if results[1] then Jump(results[1]) else self:ClearFocus() end
    end)
    UI:RegisterOnHide(function() box:SetText("") end)
end
