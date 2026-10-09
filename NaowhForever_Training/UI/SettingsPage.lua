-- SettingsPage.lua: the Training Planner settings page (Training Planner/Settings), declared as cards.
local ns = _G.NaowhForever

local Training = ns.Training
local S = Training.Settings
local Style = Training.Style
local Settings = ns.Shared.Settings

local PERCENT, ROUND = Training.C.PERCENT, Training.C.ROUND
local OPACITY_RANGE, PERCENT_SCALE = Style.OPACITY_RANGE, Style.PERCENT_SCALE
local ORDER_ON_THE_WAY, ORDER_WINDOW = 10, 20
local TEXT_OFF = "Turn on the Training Planner"
local TEXT_OPEN = "Open Training Planner"
local TEXT_TRAIN_NOW = "%d %s to train now, %s"
local TEXT_SPELL, TEXT_SPELLS = "spell", "spells"
local TEXT_NEW_AT = "New spells at level "
local TEXT_KNOW_ALL = "You know every spell your class trains"
local TEXT_DETAIL = "%s left to pay on the road to 60. %d talent %s for your class."
local TEXT_BUILD, TEXT_BUILDS = "build", "builds"
local TEXT_BOTH, TEXT_TOAST, TEXT_PANEL, TEXT_NOTHING =
    "Level-up toast and trainer panel", "Level-up toast", "Trainer panel", "Nothing on the way"
local TEXT_WINDOW = "%d%% opacity%s"
local TEXT_MINI_SHOWN = ", mini bar shown"

local function Headline(plan)
    if #plan.now > 0 then
        return TEXT_TRAIN_NOW:format(#plan.now, #plan.now == 1 and TEXT_SPELL or TEXT_SPELLS,
            Training.Coins(Training.Total(plan.now)))
    end
    if plan.soon[1] or plan.later[1] then return TEXT_NEW_AT .. (plan.soon[1] or plan.later[1])[1] end
    return TEXT_KNOW_ALL
end

local function CardLines()
    local plan = Training.Plan()
    local _, _, classID = UnitClass("player")
    local builds = #Training.Builds(classID)
    return Headline(plan), TEXT_DETAIL:format(Training.Coins(Training.ToSixty(plan)), builds,
        builds == 1 and TEXT_BUILD or TEXT_BUILDS)
end

local function CardHeadline()
    local headline = CardLines()
    return headline
end

local function CardDetail()
    local _, detail = CardLines()
    return detail
end

local function OpenPlanner()
    ns.OpenTrainingWindow()
end

local function OnTheWaySummary(store)
    local toast, panel = store.Get("levelUpToast"), store.Get("trainerPanel")
    if toast and panel then return TEXT_BOTH end
    if toast then return TEXT_TOAST end
    if panel then return TEXT_PANEL end
    return TEXT_NOTHING
end

local function WindowSummary(store)
    return TEXT_WINDOW:format(math.floor((store.Get("windowAlpha") or 1) * PERCENT + ROUND),
        store.Get("miniShown") and TEXT_MINI_SHOWN or "")
end

local page = Settings.Page("Training Planner/Settings", S)

page:Window({
    text = TEXT_OPEN,
    open = OpenPlanner,
    headline = CardHeadline,
    detail = CardDetail,
})

page:Card({
    id = "onTheWay", name = "On the Way", order = ORDER_ON_THE_WAY,
    help = "The Training Planner's help while you level: a toast when you level up with spells to train, "
        .. "and a panel beside your class trainer.",
    summary = OnTheWaySummary,
    rows = {
        { key = "levelUpToast", label = "Level-Up Toast", toggle = true, needs = Training.On,
          why = TEXT_OFF,
          help = "When you level up with new spells to train, a toast says how many and what they cost, with "
              .. "buttons to open the planner and to put a waypoint on your nearest trainer. Move it in the "
              .. "HUD Editor." },
        { key = "trainerPanel", label = "Panel at the Trainer", toggle = true,
          needs = Training.On, why = TEXT_OFF,
          help = "Beside your class trainer, the spells you can learn now, ticked, with their total and Learn "
              .. "All I Can Afford. Untick one to leave it." },
    },
})

page:Card({
    id = "window", name = "Window", order = ORDER_WINDOW,
    help = "The planner's own window, and a mini bar to leave up while you level.",
    summary = WindowSummary,
    rows = {
        { key = "miniShown", label = "Mini Bar", toggle = true, needs = Training.On,
          why = TEXT_OFF,
          help = "A small bar with your next trainer visit and your gold, to leave up while you level. Move it "
              .. "by dragging." },
        { key = "windowAlpha", label = "Window Opacity", slider = OPACITY_RANGE,
          unit = "%", scale = PERCENT_SCALE, help = "How solid the planner's window is, in percent. Also on its title bar." },
    },
})
