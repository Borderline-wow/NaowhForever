-- SleepingBag.lua: the Cozy Sleeping Bag chain's rules: your steps, the one to do now, names and places (ns.SleepingBagChain).
local ns = _G.NaowhForever

local Discovery = ns.Discovery
local Library = Discovery.Library

local TEXT_WHERE = "%s, %s (%.1f, %.1f)"
local TEXT_NAMED = "%s (%s)"
local TEXT_SUB = "%s, %s"
local TEXT_NOTE = " (%s)"

local names, subs, nowSubs = {}, {}, {}

local Bag = {}
ns.SleepingBagChain = Bag
Discovery.Bag = Bag

local function SharesName(step, other)
    return other ~= step and other.object == step.object and other.map ~= step.map
end

local function NameOf(step)
    for _, other in ipairs(Bag.Steps()) do
        if SharesName(step, other) then return TEXT_NAMED:format(step.object, Library.ZoneName(step.map)) end
    end
    return step.object
end

function Bag.Steps()
    return ns.SleepingBag.steps[Library.Side()]
end

function Bag.StepDone(step)
    if step.started then
        return C_QuestLog.IsQuestFlaggedCompleted(step.started) or C_QuestLog.IsOnQuest(step.started)
    end
    return C_QuestLog.IsQuestFlaggedCompleted(step.done)
end

function Bag.Current()
    for i, step in ipairs(Bag.Steps()) do
        if not Bag.StepDone(step) then return step, i end
    end
end

function Bag.Level()
    return UnitLevel("player") >= ns.SleepingBag.level
end

function Bag.Where(step)
    return TEXT_WHERE:format(Library.ZoneName(step.map), step.place, step.x, step.y)
end

function Bag.Name(step)
    local name = names[step]
    if name then return name end
    name = NameOf(step)
    names[step] = name
    return name
end

function Bag.Sub(step, now)
    local cache = now and step.tip and nowSubs or subs
    local sub = cache[step]
    if sub then return sub end
    sub = TEXT_SUB:format(Library.ZoneName(step.map), step.place)
    if cache == nowSubs then sub = sub .. "\n" .. step.tip end
    cache[step] = sub
    return sub
end

function Bag.Waypoint(step)
    Library.Waypoint(step.object, step.map, step.x, step.y, TEXT_NOTE:format(step.place))
end
