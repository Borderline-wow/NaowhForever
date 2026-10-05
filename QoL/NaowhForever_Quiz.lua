-------------------------------------------------------------------------------
--  NaowhForever_Quiz.lua -- a WoW quiz for campfires and, when Flight Games picks it
--  (NaowhForever_Flight.lua), flights; also opened by /naowh quiz.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.QoLSettings
local T = ns.THEME

-- Forever's "Welcoming Campfire" aura: present only while seated at a camp fire (probed
-- 2026-09-24). "Campfire Nearby" (1283391) is an area aura from simply walking past one.
local CAMPFIRE_SEATED = 1229739

local RIGHT, WRONG = { r = 0.30, g = 0.82, b = 0.48 }, { r = 0.97, g = 0.44, b = 0.44 }

local quiz, deck, current
local openedFor         -- "flight", "camp", or nil when opened by hand
local atCamp
local asked, correct, streak = 0, 0, 0

local function Best()
    return ns.AccountSettings().quizBest or 0
end

local function Shuffled(n)
    local out = {}
    for i = 1, n do out[i] = i end
    for i = n, 2, -1 do
        local j = math.random(i)
        out[i], out[j] = out[j], out[i]
    end
    return out
end

local function UpdateScore()
    quiz.score:SetText(("%d / %d right   |   streak %d   |   best %d"):format(correct, asked,
        streak, Best()))
end

local function NextQuestion()
    local bank = ns.QUIZ_QUESTIONS
    if not deck or #deck == 0 then deck = Shuffled(#bank) end
    local q = bank[table.remove(deck)]
    local order = Shuffled(#q.a)
    current = { answer = nil }
    quiz.question:SetText(q.q)
    for i, btn in ipairs(quiz.answers) do
        local pick = order[i]
        btn.label:SetText(q.a[pick])
        btn.label:SetTextColor(T.fg.r, T.fg.g, T.fg.b)
        btn.right = pick == 1
        btn:Enable()
        if btn.right then current.answer = btn end
    end
    quiz.result:SetText("")
    quiz.next:Hide()
end

local function Answer(btn)
    if not current or current.done then return end
    current.done = true
    asked = asked + 1
    for _, b in ipairs(quiz.answers) do b:Disable() end
    local c = current.answer
    c.label:SetTextColor(RIGHT.r, RIGHT.g, RIGHT.b)
    if btn.right then
        correct, streak = correct + 1, streak + 1
        if streak > Best() then ns.AccountSettings().quizBest = streak end
        quiz.result:SetText("|cff4dd17aCorrect!|r")
    else
        streak = 0
        btn.label:SetTextColor(WRONG.r, WRONG.g, WRONG.b)
        quiz.result:SetText("|cfff87171Not quite.|r")
    end
    UpdateScore()
    quiz.next:Show()
end

local function Build()
    quiz = CreateFrame("Frame", "NaowhForeverQuiz", UIParent)
    quiz:SetSize(400, 330)
    quiz:SetFrameStrata("MEDIUM")
    quiz:SetMovable(true)
    quiz:SetClampedToScreen(true)
    ns.AllowOffscreen(quiz)
    quiz:EnableMouse(true)
    quiz:RegisterForDrag("LeftButton")
    quiz:SetScript("OnDragStart", quiz.StartMoving)
    quiz:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        S.Set("quizPos", { point = point, relPoint = relPoint, x = x, y = y })
    end)
    ns.Solid(quiz, "BACKGROUND", T.bg, 0.95):SetAllPoints()
    ns.Border(quiz)

    local logo = quiz:CreateTexture(nil, "ARTWORK")
    logo:SetTexture("Interface\\AddOns\\NaowhForever\\Media\\LogoSmall.tga", nil, nil, "TRILINEAR")
    logo:SetSize(26, 26)
    logo:SetPoint("TOPLEFT", 12, -8)

    local title = ns.Font(quiz, 16, "OUTLINE", T.accent)
    title:SetPoint("LEFT", logo, "RIGHT", 8, 0)
    title:SetText("Naowh Quiz")

    local close = ns.Button(quiz, "X", 22, 22, function() ns.QuizDismiss() end)
    close:SetPoint("TOPRIGHT", -10, -10)

    quiz.question = ns.Font(quiz, 14, nil)
    quiz.question:SetPoint("TOPLEFT", 16, -48)
    quiz.question:SetPoint("RIGHT", -16, 0)
    quiz.question:SetJustifyH("LEFT")
    quiz.question:SetWordWrap(true)
    quiz.question:SetHeight(44)
    quiz.question:SetJustifyV("TOP")

    quiz.answers = {}
    for i = 1, 4 do
        local btn = ns.Button(quiz, "", 368, 30)
        btn:SetPoint("TOPLEFT", 16, -100 - (i - 1) * 36)
        btn:SetScript("OnClick", Answer)
        btn:SetMotionScriptsWhileDisabled(true)
        quiz.answers[i] = btn
    end

    quiz.result = ns.Font(quiz, 14, "OUTLINE")
    quiz.result:SetPoint("TOPLEFT", 16, -250)

    quiz.next = ns.Button(quiz, "Next Question", 130, 26, NextQuestion)
    quiz.next:SetPoint("TOPRIGHT", -16, -246)

    quiz.score = ns.Font(quiz, 11, nil, T.muted)
    quiz.score:SetPoint("BOTTOMLEFT", 16, 14)
    quiz:Hide()
end

local function Place()
    local pos = S.Get("quizPos")
    quiz:ClearAllPoints()
    if pos then
        quiz:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    else
        quiz:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
    end
end

local function Open(reason)
    if not ns.QUIZ_QUESTIONS or #ns.QUIZ_QUESTIONS == 0 then return end
    if not quiz then Build() end
    if quiz:IsShown() then return end
    openedFor = reason
    Place()
    NextQuestion()
    UpdateScore()
    quiz:Show()
end

-- A reason-less dismiss is the close button; a reason closes only what that reason opened,
-- so landing never shuts a quiz opened by hand.
function ns.QuizDismiss(reason)
    if not (quiz and quiz:IsShown()) then return end
    if reason and openedFor ~= reason then return end
    quiz:Hide()
end

function ns.QuizOffer(reason)
    if not S.Get("enabled") or InCombatLockdown() then return end
    if reason == "camp" and not S.Get("quizCamp") then return end
    Open(reason)
end

function ns.QuizPlay(reason)
    if not S.Get("enabled") or InCombatLockdown() then return end
    Open(reason)
end

function ns.ToggleQuiz()
    if quiz and quiz:IsShown() then quiz:Hide() else Open(nil) end
end

-- Auras cannot be read in combat, so the camp check pauses there rather than reading a
-- missing aura as having walked away.
local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        ns.QuizDismiss(openedFor)
        return
    end
    if InCombatLockdown() then return end
    local here = C_UnitAuras.GetPlayerAuraBySpellID(CAMPFIRE_SEATED) ~= nil
    if here == atCamp then return end
    atCamp = here
    if here then ns.QuizOffer("camp") else ns.QuizDismiss("camp") end
end)

local function Apply()
    events:UnregisterAllEvents()
    if not S.Get("enabled") then
        ns.QuizDismiss(openedFor)
        return
    end
    events:RegisterEvent("PLAYER_REGEN_DISABLED")
    if S.Get("quizCamp") then
        events:RegisterUnitEvent("UNIT_AURA", "player")
    else
        atCamp = nil
    end
end

hooksecurefunc(S, "Set", function(key)
    if key == "enabled" or key == "quizCamp" then Apply() end
end)
hooksecurefunc(ns, "Apply", Apply)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", Apply)

local function Summary(store)
    local flight, camp = store.Get("flightGame") == "quiz", store.Get("quizCamp")
    if flight and camp then return "While flying and at the campfire" end
    if flight then return "While flying" end
    if camp then return "At the campfire" end
    return "Only when you open it"
end

ns.Shared.Settings.Page("QoL/Travel", S):Card({
    id = "quiz", name = "Quiz", order = 20,
    help = "A WoW quiz for campfires and flights, or any time with /naowh quiz.",
    summary = Summary,
    rows = {
        { key = "quizCamp", label = "Quiz at the Campfire", toggle = true,
          help = "The quiz opens when you sit down at a campfire and closes when you stand up." },
        { label = "Open the Quiz", buttonText = "Open", button = ns.ToggleQuiz,
          help = "Opens the quiz now, or closes it." },
    },
})
