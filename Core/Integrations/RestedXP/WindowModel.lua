-- WindowModel.lua: what RestedXP is showing, as plain data: the heading, the progress, the active steps and the steps after.
local ns = _G.NaowhForever
local Safe = ns.RXPSafe
local Has, Dig, Run = Safe.Has, Safe.Dig, Safe.Run

local ACTIVE_SHOWN = 3
local UPCOMING_MAX = select(2, ns.RXPWindowStepsRange())
local PERCENT, ROUND = 100, 0.5
local COUNT_PATTERN = "(%d+)%s*/%s*(%d+)"
local LEAD_ICON, LEAD_PLAIN = "^%s*(|T[^|]*|t)%s*", "^|T([^|:]+):%d+|t$"
local LEAD_PATH, CONTENT_ID, CONTENT_DIR = "^|T([^|:]+)", "^%d+$", "interface[/\\]icons[/\\]"
local TEXT_STEP = ns.L("Step %d")
local TEXT_NO_GUIDE = ns.L("No guide selected")

local function SplitRange(text)
    local range, place = text:match("^(%d+%-%d+)%s+(.+)$")
    if range then return place, range end
    place, range = text:match("^(.-)%s+(%d+%-%d+)$")
    if place then return place, range end
    return text
end

local function Plain(text)
    text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
    text = text:gsub("|r", "")
    text = text:gsub("|T[^|]*|t", "")
    text = text:gsub("|A[^|]*|a", "")
    text = text:gsub("|H[^|]*|h", "")
    text = text:gsub("|h", "")
    return (text:gsub("^%s+", ""))
end

local function Heading(rxp, guide)
    local title = guide.title or guide.subgroup or Run("WindowGuideName", rxp.GetGuideName, guide) or guide.name
    if not title then return "" end
    local place, range = SplitRange(title)
    return range and (place .. " " .. ns.RXPWindowTint("accent", range)) or place
end

local function Counted(element, shown)
    local tag = element.tag
    if type(tag) == "string" and tag:find("^buy") and type(element.id) == "number"
            and type(element.qty) == "number" then
        return C_Item.GetItemCount(element.id), element.qty, true
    end
    local have, need = Plain(shown):match(COUNT_PATTERN)
    return tonumber(have), tonumber(need), false
end

local function Lifted(shown, glyph)
    if glyph ~= "" then return shown, glyph, false end
    local lead = shown:match(LEAD_ICON)
    if not lead then return shown, glyph, false end
    local path = lead:match(LEAD_PLAIN)
    local named = lead:match(LEAD_PATH) or ""
    local content = named:match(CONTENT_ID) or named:lower():find(CONTENT_DIR)
    return (shown:gsub(LEAD_ICON, "", 1)), path and ("|T" .. path .. ":0|t") or lead, content and true or false
end

local function Row(rxp, element)
    local frame = element.frame
    local text = Dig(frame, "text")
    local shown = Has(text, "GetText") and text:GetText()
    if type(shown) ~= "string" or shown == "" or shown == " " then
        local raw = element.text ~= " " and element.text or element.tooltipText or element.rawtext
        shown = type(raw) == "string" and raw or ""
        shown = Run("WindowNpc", rxp.ReplaceNpcIds, shown, element) or shown
    end
    shown = ns.RXPIconText(shown)
    local icon = Dig(frame, "icon")
    local glyph = Has(icon, "GetText") and icon:GetText()
    if Has(icon, "IsShown") and icon:IsShown() == false then glyph = "" end
    if type(glyph) ~= "string" then glyph = element.icon or rxp.icons[element.tag] or "" end
    local nested
    shown, glyph, nested = Lifted(shown, glyph)
    local note = element.textOnly == true and glyph == ""
    local button = Dig(frame, "button")
    local done = Has(button, "GetChecked") and button:GetChecked() or element.completed or element.skip
    local have, need, bags = Counted(element, shown)
    return { text = shown, icon = glyph, done = done and true or false, button = button, source = text,
        have = have, need = need, bags = bags, nested = nested, note = note }
end

local function ActiveSteps(rxp)
    local out = {}
    for _, step in ipairs(rxp.RXPFrame.activeSteps) do
        if step.active and not step.hidewindow and not step.hidetip then
            out[#out + 1] = step
            if #out == ACTIVE_SHOWN then break end
        end
    end
    return out
end

local function StepLabel(step)
    if step.title and step.title ~= "" then return step.title end
    return TEXT_STEP:format(step.index)
end

local kept

function ns.RXPWindowStale()
    kept = nil
end

local function Listed(v2, after)
    local snapshot = Run("WindowSteps", v2.BuildGuideStepsSnapshot, v2, true)
    if not snapshot then return nil end
    local list = {}
    for _, row in ipairs(snapshot.rows) do
        if row.index > after and not row.hidden and not row.complete then
            list[#list + 1] = { index = row.index, text = Plain(row.text:match("^[^\n]*")) }
            if #list == UPCOMING_MAX then break end
        end
    end
    return list
end

local function Upcoming(rxp, after, count)
    local out = {}
    local v2 = rxp.v2
    if count == 0 or not v2.BuildGuideStepsSnapshot then return out end
    local guide = rxp.currentGuide
    if not (kept and kept.guide == guide and kept.after == after) then
        local list = Listed(v2, after)
        if not list then return out end
        kept = { guide = guide, after = after, list = list }
    end
    for i = 1, math.min(count, #kept.list) do out[i] = kept.list[i] end
    return out
end

function ns.RXPWindowNoGuide()
    return { heading = TEXT_NO_GUIDE, steps = {}, upcoming = {}, empty = true }
end

function ns.RXPWindowRead(steps)
    local rxp = _G.RXP
    local guide = rxp.currentGuide
    if not guide or guide.empty then return nil end
    local model = { heading = Heading(rxp, guide), steps = {} }
    local step = Run("WindowProgress", rxp.GetGuideProgress)
    local total = #guide.steps
    if step and total > 0 then
        model.step, model.total = step, total
        model.fraction = math.min(1, math.max(0, step / total))
        model.percent = math.floor(model.fraction * PERCENT + ROUND)
    end
    local after = step or 0
    for _, activeStep in ipairs(ActiveSteps(rxp)) do
        local rows = {}
        for _, element in ipairs(activeStep.elements or {}) do
            if element.text or element.rawtext or element.tooltipText then
                local row = Row(rxp, element)
                row.step = activeStep
                rows[#rows + 1] = row
            end
        end
        model.steps[#model.steps + 1] = { label = StepLabel(activeStep), rows = rows, source = activeStep }
        if activeStep.index > after then after = activeStep.index end
    end
    model.upcoming = Upcoming(rxp, after, steps or ns.RXPWindowSteps())
    return model
end
