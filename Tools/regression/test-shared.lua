-- Run with Lua 5.1 from the repository root: what the modules share (Shared/), loaded from the
-- files Shared.xml loads, in order, against stubs. Checks that nothing is made or listened to
-- at load, the item helpers, the Forever mark, and the row engine a page is drawn with: rows
-- pooled and reused, a burst of events making one redraw and none while hidden, a redraw that
-- makes no garbage, and a tracker's window (Parts.TrackerPanel).
local Load = dofile("Tools/regression/load_files.lua")
local TocFiles = dofile("Tools/regression/toc_files.lua")
local Measure = dofile("Tools/regression/measure.lua")

local checks = 0
local function check(label, value) assert(value, label); checks = checks + 1 end

-------------------------------------------------------------------------------
--  Stubs: a frame keeps its scripts, events, size, text and shown state; every other method
--  is one shared do-nothing function, so the stubs make no garbage of their own.
-------------------------------------------------------------------------------
local NOTHING = function() end
local Frame
local made = 0   -- frames made, all told
local METHODS = {
    SetScript = function(f, script, fn) f.scripts[script] = fn end,
    GetScript = function(f, script) return f.scripts[script] end,
    HookScript = function(f, script, fn) f.scripts[script] = fn end,
    RegisterEvent = function(f, event) f.events[event] = true end,
    UnregisterAllEvents = function(f) for event in pairs(f.events) do f.events[event] = nil end end,
    GetParent = function(f) return rawget(f, "parent") end,
    SetWidth = function(f, w) f.w = w end,
    SetHeight = function(f, h) f.h = h end,
    SetSize = function(f, w, h) f.w, f.h = w, h end,
    GetWidth = function(f) return rawget(f, "w") or 600 end,
    GetHeight = function(f) return rawget(f, "h") or 24 end,
    SetText = function(f, text) f.text = text end,
    SetTextColor = function(f, r, g, b) f.r, f.g, f.b = r, g, b end,
    GetText = function(f) return rawget(f, "text") or "" end,
    GetStringWidth = function() return 40 end,
    GetStringHeight = function() return 12 end,
    Show = function(f) f.shown = true end,
    Hide = function(f) f.shown = false end,
    SetShown = function(f, shown) f.shown = shown and true or false end,
    IsShown = function(f) return rawget(f, "shown") ~= false end,
    IsVisible = function(f) return rawget(f, "shown") ~= false end,
    GetEffectiveScale = function() return 1 end,
    CreateTexture = function(f) return Frame(f) end,
    CreateFontString = function(f) return Frame(f) end,
    CreateAnimationGroup = function(f) return Frame(f) end,
    CreateAnimation = function(f) return Frame(f) end,
}
local META = { __index = function(_, key)
    if METHODS[key] then return METHODS[key] end
    if type(key) == "string" and key:find("^%u") then return NOTHING end
end }
function Frame(parent)
    made = made + 1
    return setmetatable({ scripts = {}, events = {}, parent = parent }, META)
end

local WHITE = { r = 1, g = 1, b = 1 }
local timers = {}
local tooltip = Frame()
tooltip.GetOwner = function() return nil end

local ns = {
    THEME = setmetatable({}, { __index = function() return WHITE end }),
    Color = function(_, text) return tostring(text) end,
    Font = function(parent) return Frame(parent) end,
    Solid = function(parent, _, color)
        local solid = Frame(parent)
        solid.color = color
        return solid
    end,
    ThemeTint = function(_, literal) return literal end,
    -- As ns.Hairline and ns.PixelInset: whole-pixel sizing has no effect on these stubs.
    Hairline = function(region) return region end,
    PixelInset = function(region) return region end,
    Border = function() return { SetColor = NOTHING } end,
    AllowOffscreen = NOTHING,
    AccentBorder = function() return { SetColor = NOTHING } end,
    Button = function(parent) return Frame(parent) end,
    UIFontPath = function() return "font" end,
    AccountSettings = function() return {} end,
    UI = { Keep = function(parent, key, make)
        local kept = rawget(parent, key)
        if not kept then kept = make(parent); parent[key] = kept end
        return kept
    end },
}
local env = setmetatable({
    NaowhForever = ns,
    CreateFrame = function(_, _, parent) return Frame(parent) end,
    Mixin = function(target, ...)
        for i = 1, select("#", ...) do
            for k, v in pairs((select(i, ...))) do target[k] = v end
        end
        return target
    end,
    wipe = function(t) for k in pairs(t) do t[k] = nil end return t end,
    C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end },
    C_Item = {
        GetItemInfoInstant = function(id)
            if id == 19019 then return id, "", "", "INVTYPE_WEAPONMAINHAND", 135349, 2, 7 end
            if id == 18348 then return id, "", "", "INVTYPE_2HWEAPON", 135349, 2, 8 end
        end,
        GetItemNameByID = function(id) return id == 19019 and "Thunderfury" or nil end,
        GetItemQualityByID = function(id) return id == 19019 and 5 or nil end,
        GetItemCount = function() return 0 end,
        IsItemDataCachedByID = function() return true end,
        IsEquippedItem = function() return false end,
    },
    ITEM_QUALITY_COLORS = { [5] = { hex = "|cffff8000", r = 1, g = 0.5, b = 0 } },
    GameTooltip = tooltip,
    GameTooltip_Hide = NOTHING,
    InCombatLockdown = function() return false end,
    CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end,
    UIParent = Frame(),
}, { __index = _G })
env._G = env

-------------------------------------------------------------------------------
--  Loading: everything Shared.xml lists, in its order, and nothing made or listened to.
-------------------------------------------------------------------------------
local files = TocFiles("^Shared/.*%.lua$")
check("the TOC loads Shared.xml, and it lists the files", #files >= 9 and files[1] == "Shared/Shared.lua")
local before = made
Load(files, env)
local Shared = ns.Shared
check("everything there: Style, Items, Parts, View, Kinds", Shared.Style and Shared.Items and Shared.Parts
    and Shared.View and Shared.Kinds and Shared.ForeverNew)
check("nothing made at load", made == before and #timers == 0)

-------------------------------------------------------------------------------
--  Items
-------------------------------------------------------------------------------
local Items = Shared.Items
check("an ID from a number, a link, a Wowhead URL or its digits",
    Items.IDFrom(19019) == 19019 and Items.IDFrom("|cffff8000|Hitem:19019::::|h[Thunderfury]|h|r") == 19019
    and Items.IDFrom("https://www.wowhead.com/forever/item=19019/thunderfury") == 19019
    and Items.IDFrom(" 19019 ") == 19019)
check("nothing from what names no item", Items.IDFrom("Thunderfury") == nil)
check("a name, or what it is while it loads", Items.Name(19019) == "Thunderfury" and Items.Name(1) == "item 1")
check("its quality's colour, white while unknown", Items.QualityHex(19019) == "|cffff8000"
    and Items.QualityHex(1) == "|cffffffff")
check("a two-hander is one; a one-hander is not", Items.IsTwoHand(18348) and not Items.IsTwoHand(19019))

-------------------------------------------------------------------------------
--  The Forever mark: what is new in Forever, by kind and ID.
-------------------------------------------------------------------------------
local Parts = Shared.Parts
local newItem = next(Shared.ForeverNew.items)
check("an item new in Forever has the mark; one from the original game not", Parts.IsForever("items", newItem)
    and not Parts.IsForever("items", 19019))

-------------------------------------------------------------------------------
--  The row engine: a page of rows of its own kind, under a shared section title.
-------------------------------------------------------------------------------
local View = Shared.View
local kinds = View.NewKinds()
local madeRows = 0
kinds.line = {
    New = function(view)
        madeRows = madeRows + 1
        local row = Frame(view)
        row.label = Frame(row)
        return row
    end,
    Set = function(row, text, waiting)
        row.label:SetText(text)
        return 20, waiting
    end,
}
local TEXTS = {}
for i = 1, 50 do TEXTS[i] = "line " .. i end
local EVENTS = { "BAG_UPDATE_DELAYED" }
local page = { count = 50, waitOn = nil }
function page:Redraw()
    self:Clear()
    self:Section("Loot", self.count)
    for i = 1, self.count do self:Add("line", TEXTS[i], i == self.waitOn) end
    if self.waitOn then self.waitingFor[self.waitOn] = true end
    self:Fit(EVENTS)
end
local view = View.New(Frame(), kinds, page)
view:Redraw()
check("a page drawn: each row under the last, as tall as all of them", madeRows == 50
    and view.h == view.cursor and view.cursor > 50 * 20)
check("listening for what it asked for", view.events.BAG_UPDATE_DELAYED
    and not view.events.GET_ITEM_INFO_RECEIVED)
view.count = 10
view:Redraw()
local shownRows = 0
for i = 1, view.pools.line.used do if view.pools.line[i]:IsShown() then shownRows = shownRows + 1 end end
check("drawn again shorter: rows reused, none made, the rest hidden", madeRows == 50 and shownRows == 10
    and view.pools.line[11].shown == false)
local row = view:Find("line", function(r, text) return r.label.text == text end, "line 7")
check("a drawn row found by what it shows", row and row.top == view.pools.line[7].top)
view.waitOn = 3
view:Redraw()
check("a row waiting on an item's name: listened for", view.events.GET_ITEM_INFO_RECEIVED)
view:OnEvent("GET_ITEM_INFO_RECEIVED", 999)
check("another item's name is not its business", #timers == 0)
view:OnEvent("GET_ITEM_INFO_RECEIVED", 3)
view:OnEvent("BAG_UPDATE_DELAYED")
view:OnEvent("BAG_UPDATE_DELAYED")
check("a burst of events: one redraw queued", #timers == 1)
view.waitOn = nil
local drawn = 0
local redraw = view.Redraw
view.Redraw = function(self) drawn = drawn + 1; redraw(self) end
timers[1](); timers[1] = nil
check("and drawn once", drawn == 1)
view.waitOn = 4
redraw(view)
view:OnEvent("GET_ITEM_INFO_RECEIVED", 4, false)
check("an item the server will not send: no redraw for it", #timers == 0)
check("nor waited on any more", view.waitingFor[4] == nil)
check("and remembered for the session, alone", Items.Refused(4) and not Items.Refused(3))
view:OnEvent("GET_ITEM_INFO_RECEIVED", 4, false)
check("told again: still nothing to do", #timers == 0)
view.waitOn = nil
view:Hide()
view.scripts.OnHide(view)
check("hidden: listening to nothing", next(view.events) == nil)
view:QueueRedraw()
timers[1](); timers[1] = nil
check("and not drawn while hidden", drawn == 1)
view:Show()

local columns, width = View.Columns(600)
check("cards across: as many as fit, each as wide as shares the width", columns >= 1
    and width * columns <= 600 and View.Columns(10) == 1)

-- A module's window opened from /nf the first time, as the game does it: a frame is made
-- shown, Show() runs OnShow only on a hidden frame and Hide() runs OnHide only on a shown one.
local function GameShow(f)
    if f:IsShown() then return end
    f.shown = true
    if f.scripts.OnShow then f.scripts.OnShow(f) end
end
local function GameHide(f)
    if not f:IsShown() then return end
    f.shown = false
    if f.scripts.OnHide then f.scripts.OnHide(f) end
end
local window
local function OpenWindow()
    if not window then window = Parts.Window(400, 300, "testWindow") end
    GameShow(window)
end
local backs = 0
Parts.OpenWithBack(OpenWindow, Frame(), function() backs = backs + 1 end, "Back to Settings")
check("a window opened from another one the first time knows its way back", window.onBack ~= nil)
GameHide(window)
check("and closing it brings that one back", backs == 1)
Parts.OpenWithBack(OpenWindow, Frame(), function() backs = backs + 1 end, "Back to Settings")
GameHide(window)
check("the second time too", backs == 2)

view.Redraw = redraw
view.count = 50
Measure(check)("a page of 50 rows redrawn", 1, function() view:Redraw() end)

-------------------------------------------------------------------------------
--  A tracker's window (Parts.TrackerPanel): built only when asked, its parts where the
--  options ask for them, rows pooled, the body scrolling past its height, its place kept.
-------------------------------------------------------------------------------
local opened, wentTo, titled, saved, moved
ns.OpenOptionsWindow = function(name) opened = name end
ns.UI.GoToSetting = function(_, _, feature) wentTo = feature end
ns.UI.COGS_ICON = "cog"
ns.UI.SlimScroll = function(parent) return Frame(parent) end
ns.UI.BuildDropdownControl = function(parent) return Frame(parent) end
env.Menu = { GetManager = function() return { IsAnyMenuOpen = function() return false end } end }
local createFrame = env.CreateFrame
local function Level() return 1 end
env.CreateFrame = function(kind, name, parent)
    local frame = createFrame(kind, name, parent)
    frame.GetFrameLevel = Level
    return frame
end
local where
local tracker = Parts.TrackerPanel("BOOKS", {
    width = 320, titleRoom = 74, maxHeight = function() return 300 end,
    onTitle = function() titled = true end, titleTip = "Books", titleHint = "Click for its settings.",
    bar = true,
    picker = { values = {}, order = {}, get = NOTHING, set = NOTHING },
    settings = { page = "Discovery/Library Books", card = "tracker", tip = "Settings" },
    load = function() if where then return where[1], where[2], where[3], where[4] end end,
    save = function(point, relativePoint, x, y) saved = { point, relativePoint, x, y } end,
    place = { "RIGHT", "RIGHT", -60, 60 },
    mover = function(frame, onMoved) moved = onMoved; return Frame(frame) end,
})
check("a tracker: its bar, dropdown, cog, body and mover", tracker.bar and tracker.picker and tracker.settings
    and tracker.body and tracker.mover and tracker.footer > 0)
check("its body starts under the title, the bar and the dropdown", tracker:Top() == 30 + 4 + 24 + 6 + 24 + 6)
tracker.picker:Hide()
check("a hidden dropdown leaves no room", tracker:Top() == 30 + 4 + 24 + 6)
tracker.picker:Show()
check("as wide as asked, its body inside the padding", tracker.w == 320 and tracker.body.w == 300)
tracker.settings.scripts.OnClick(tracker.settings)
check("its cog opens its settings, at its card", opened == "Discovery/Library Books"
    and wentTo == "Discovery/Library Books:tracker")
tracker.titleButton.scripts.OnClick(tracker.titleButton)
check("its title is clicked through to the module", titled)
tracker.GetPoint = function() return "TOP", nil, "TOP", 5, -7 end
tracker.scripts.OnDragStop(tracker)
check("dragged, its place is saved", saved and saved[1] == "TOP" and saved[4] == -7)
moved({ point = "LEFT", relPoint = "LEFT", x = 1, y = 2 })
check("and Unlock Mode's mover saves through the same", saved[1] == "LEFT" and saved[4] == 2)
local placed
tracker.SetPoint = function(_, point, _, _, x) placed = { point, x } end
tracker:Place()
check("placed at its default before it has a place", placed[1] == "RIGHT" and placed[2] == -60)
where = { "TOP", "TOP", 9, 9 }
tracker:Place()
check("then where it was left", placed[1] == "TOP" and placed[2] == 9)

check("its bar on the tracker bar's shade, the theme's panel once changed",
    tracker.bar.bg.color == Shared.Style.TRACKER_BAR_RGB)

local pinned, pinnedEntry = 0, nil
local function Waypoint(entry) pinned, pinnedEntry = pinned + 1, entry end
local GREY = { r = 0.5, g = 0.5, b = 0.5 }
local ENTRIES = {
    { text = "Book one", sub = "In a crate", waypoint = Waypoint },
    { text = "Book two", waypoint = Waypoint },
    { text = "Book three", done = true, color = GREY },
}
local height = tracker:SetRows(ENTRIES)
local rows = tracker.rows
check("a row each, every other one striped", #rows == 3 and rows[2].stripe:IsShown()
    and not rows[1].stripe:IsShown())
check("a pin where there is a waypoint, a tick once done", rows[1].pin:IsShown() and not rows[3].pin:IsShown()
    and rows[3].tick:IsShown() and not rows[1].tick:IsShown())
check("a line under each but the last", rows[1].divider:IsShown() and not rows[3].divider:IsShown())
check("as tall as its rows", height == (6 + 12 + 8) * 3 + 3 + 12 and tracker.body.h == height)
rows[1].pin.scripts.OnClick(rows[1].pin)
check("a pin's click is the row's waypoint, handed its entry", pinned == 1 and pinnedEntry == ENTRIES[1])
check("a row's text in its colour, else the theme's text", rows[3].text.r == 0.5 and rows[1].text.r == 1)
local madeBefore = made
tracker:SetRows({ ENTRIES[1], ENTRIES[2] })
check("fewer rows: reused, none made, the rest hidden", made == madeBefore and #rows == 3 and rows[3].shown == false)
check("short: no scrollbar", tracker:Fit(100) == false and tracker.h == tracker:Top() + 100 + tracker.footer + 10
    and tracker:ScrollGap() == 0)
check("past its height it scrolls, and says so once", tracker:Fit(1000) == true and tracker.h == 300
    and tracker:ScrollGap() == 20 and tracker:Fit(1000) == false)
tracker:SetTrackerWidth(320)
check("its body leaves the scrollbar room", tracker.body.w == 280)
check("and stops", tracker:Fit(100) == true and tracker:ScrollGap() == 0)
Measure(check)("a tracker's rows laid out", 1, function() tracker:SetRows(ENTRIES) end)

local plain = Parts.TrackerPanel("PLAIN", {})
check("with no options: no bar, dropdown or cog, its body under the title", not plain.bar and not plain.picker
    and not plain.settings and plain.footer == 0 and plain:Top() == 34 and plain:Fit(100) == false)
check("and a tracker's width", plain.w == Shared.Style.TRACKER_W)

print(("test-shared: %d checks passed"):format(checks))
