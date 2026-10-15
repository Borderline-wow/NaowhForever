-- Search.lua: the search box at the top of the options window's sidebar.
local ns = _G.NaowhForever
local UI = ns.UI

local TEXT_SEARCH_HINT = ns.L("Search settings")
local INDEX_ADDON = "NaowhForever_SearchIndex"
local NONE = {}
local NOT_LETTERS, LETTER, WORD = "[^%w\128-\255]+", "[%w\128-\255]", "()([%w\128-\255]+)"
local FUZZY_MIN, FUZZY_SHARE, MAX_CAPTURES = 3, 0.5, 32

local carries = {}
local spreads = {}

local function Words(text)
    return " " .. ns.Lower(text):gsub(NOT_LETTERS, " ") .. " "
end

local function Both(text)
    if not text or text == "" then return "" end
    local shown = ns.L(text)
    return shown == text and text or (text .. " " .. shown)
end

local function Typed(query)
    local typed = {}
    for word in Words(query):gmatch("%S+") do typed[#typed + 1] = word end
    return typed
end

local function Place(page, cardName)
    local parts = {}
    local mod = page.module
    if mod and #mod.tabs > 1 then parts[#parts + 1] = ns.L(page.name) end
    if cardName then parts[#parts + 1] = ns.L(cardName) end
    return mod and ns.Options.DisplayName(mod) or ns.L(page.title or page.name), table.concat(parts, " / ")
end

local function Entry(page, card, label, help, cardName, group, scope)
    local t, where = Place(page, cardName)
    return { page = page.key, card = card, label = label, tag = t, trail = where,
        isCard = cardName == nil, scope = scope, name = Words(Both(label or cardName)),
        words = Words(table.concat({ Both(label), Both(help), Both(group), Both(cardName) }, " ")) }
end

local function IndexInto(list, page, scope, Settings, settingsKey)
    Settings.Index(settingsKey, function(card, label, help, cardName, group)
        list[#list + 1] = Entry(page, card, label, help, cardName, group, scope)
    end)
end

local function AddTerms(list, page, tag, scope)
    local terms = page.terms and ns[page.terms]
    if not terms then return end
    terms(function(label, help, section, off)
        list[#list + 1] = { page = page.key, label = label, tag = tag, trail = section, scope = scope, off = off,
            name = Words(Both(label)), words = Words(table.concat({ Both(label), Both(help), Both(section) }, " ")) }
    end)
end

local function PageTarget(list, page, off)
    local tag, trail = Place(page)
    local pageWords = Words(table.concat({ tag, trail, page.module and page.module.name or "" }, " "))
    list[#list + 1] = { page = page.key, tag = tag, trail = trail, name = pageWords, words = pageWords,
        offPage = off }
    return tag, pageWords
end

local function IndexOff(list, page, pageWords)
    for _, e in ipairs(ns.SEARCH_INDEX and ns.SEARCH_INDEX[page.key] or NONE) do
        local t = Entry(page, page.key .. ":" .. e[1], e[2] or e[4], e[3], e[2] and e[4] or nil, e[5], pageWords)
        t.offPage = true
        list[#list + 1] = t
    end
end

local function Collect()
    local list = {}
    local Settings = ns.Shared and ns.Shared.Settings
    for _, page in ipairs(UI.SearchPages()) do
        local tag, pageWords = PageTarget(list, page)
        AddTerms(list, page, tag, pageWords)
        if Settings then
            IndexInto(list, page, pageWords, Settings, page.key)
            for _, settingsKey in ipairs(carries[page.key] or NONE) do
                IndexInto(list, page, pageWords, Settings, settingsKey)
            end
        end
    end
    local off = UI.SearchOffPages()
    if off[1] and not ns.SEARCH_INDEX then C_AddOns.LoadAddOn(INDEX_ADDON) end
    for _, page in ipairs(off) do
        local _, pageWords = PageTarget(list, page, true)
        IndexOff(list, page, pageWords)
    end
    return list
end

local function Spread(word)
    local pattern = spreads[word]
    if not pattern then
        pattern = "^" .. word:gsub(".", "()%0.-")
        spreads[word] = pattern
    end
    return pattern
end

local function Close(word, w)
    return #word >= FUZZY_MIN and #word <= MAX_CAPTURES and #word >= #w * FUZZY_SHARE
        and w:find(Spread(word)) ~= nil
end

local function NameWords(target)
    local words = {}
    for _, w in target.name:gmatch(WORD) do words[#words + 1] = w end
    target.nameWords = words
    return words
end

local function Fuzzy(word, target)
    local best
    for _, w in ipairs(target.nameWords or NameWords(target)) do
        if Close(word, w) and (not best or #word / #w > best) then best = #word / #w end
    end
    return best
end

local function Matched(target, typed)
    local own, fuzzy, score = false, 0, 0
    for _, word in ipairs(typed) do
        local start = " " .. word
        if target.words:find(start, 1, true) then
            own = true
        elseif not (target.scope and target.scope:find(start, 1, true)) then
            local s = Fuzzy(word, target)
            if not s then return false end
            own, fuzzy, score = true, fuzzy + 1, score + s
        end
    end
    return own, fuzzy, score
end

local function Better(a, b)
    if a.fuzzy ~= b.fuzzy then return a.fuzzy < b.fuzzy end
    if a.score ~= b.score then return a.score > b.score end
    return a.at < b.at
end

local function Matches(list, typed)
    local out = {}
    if #typed == 0 then return out end
    local anyFuzzy = false
    for i, target in ipairs(list) do
        local own, fuzzy, score = Matched(target, typed)
        if own then
            target.fuzzy, target.score, target.at = fuzzy, score, i
            out[#out + 1] = target
            anyFuzzy = anyFuzzy or fuzzy > 0
        end
    end
    if anyFuzzy then table.sort(out, Better) end
    return out
end

local function Find(list, query)
    return Matches(list, Typed(query))
end

local function AddMatch(f, t)
    local key = t.page
    if not f.count[key] then
        f.count[key] = 0
        f.order[#f.order + 1] = key
    end
    if not t.card then
        f.all[key] = true
        if t.label then f.count[key] = f.count[key] + 1 end
        if t.off then f.off[#f.off + 1] = t.off end
        return
    end
    f.count[key] = f.count[key] + 1
    f.first[key] = f.first[key] or t.card
    if t.offPage then
        local hits = f.hits[key] or {}
        hits[#hits + 1] = t
        f.hits[key] = hits
    end
    if t.isCard then
        f.cards[t.card] = true
    elseif f.cards[t.card] ~= true then
        local labels = f.cards[t.card] or {}
        labels[t.label] = true
        f.cards[t.card] = labels
    end
end

local function Build(list, query)
    local typed = Typed(query)
    if #typed == 0 then return nil end
    local f = { typed = typed, count = {}, all = {}, cards = {}, order = {}, first = {}, off = {}, hits = {},
        list = list }
    for _, t in ipairs(Matches(list, typed)) do AddMatch(f, t) end
    return f
end

local function OffRows(filter, pageKey)
    if not filter.all[pageKey] then return filter.hits[pageKey] or NONE end
    local rows = {}
    for _, t in ipairs(filter.list) do
        if t.page == pageKey and t.card then rows[#rows + 1] = t end
    end
    return rows
end

local function StartsWord(lower, s)
    return s == 1 or not lower:sub(s - 1, s - 1):find(LETTER)
end

local function LitClose(lower, word, lit)
    for at, w in lower:gmatch(WORD) do
        if Close(word, w) then
            lit = lit or {}
            for _, p in ipairs({ w:match(Spread(word)) }) do lit[at + p - 1] = true end
        end
    end
    return lit
end

local function LitLetters(filter, lower)
    local lit
    for _, word in ipairs(filter.typed) do
        local from, found = 1, false
        while true do
            local s, e = lower:find(word, from, true)
            if not s then break end
            if StartsWord(lower, s) then
                lit, found = lit or {}, true
                for i = s, e do lit[i] = true end
            end
            from = s + 1
        end
        if not found then lit = LitClose(lower, word, lit) end
    end
    return lit
end

local function Paint(text, lit)
    local out, i = {}, 1
    while i <= #text do
        local on, j = lit[i] == true, i
        while j < #text and (lit[j + 1] == true) == on do j = j + 1 end
        local piece = text:sub(i, j)
        out[#out + 1] = on and ns.Color("accent", piece) or piece
        i = j + 1
    end
    return table.concat(out)
end

local function Mark(filter, text)
    if not (filter and text) then return text end
    local lit = LitLetters(filter, ns.Lower(text))
    if not lit then return text end
    return Paint(text, lit)
end

local function Narrowing(filter, pageKey)
    if filter and not filter.all[pageKey] and (filter.count[pageKey] or 0) > 0 then return filter end
    return nil
end

local function Narrowed(pageKey)
    return Narrowing(UI.filter, pageKey)
end

local function CarriedChanged(before, after)
    for pageKey in pairs(carries) do
        if Narrowing(before, pageKey) or Narrowing(after, pageKey) then return true end
    end
    return false
end

UI.Search = { Collect = Collect, Find = Find, Build = Build, Mark = Mark, Narrowed = Narrowed, OffRows = OffRows }

function UI.SearchCarries(pageKey, settingsKey)
    local keys = carries[pageKey] or {}
    keys[#keys + 1] = settingsKey
    carries[pageKey] = keys
end

local box, list, onFilter

local function OnText(text)
    local before = UI.filter
    if text:find("%S") then
        list = list or Collect()
        UI.filter = Build(list, text)
    else
        list, UI.filter = nil, nil
    end
    onFilter()
    if CarriedChanged(before, UI.filter) then UI:RefreshPage(true) end
end

function UI.FocusSearch()
    box:SetFocus()
    box:HighlightText()
end

function UI.SearchTyped()
    return box:GetText() ~= ""
end

function UI.ClearSearch()
    if box:GetText() ~= "" then box:SetText("") end
    box:ClearFocus()
end

function UI.AttachSearchBox(parent, onChange, columns)
    onFilter = onChange
    box = ns.Shared.Parts.SearchBox(parent, TEXT_SEARCH_HINT, OnText, columns)
    UI:RegisterOnHide(UI.ClearSearch)
    return box
end
