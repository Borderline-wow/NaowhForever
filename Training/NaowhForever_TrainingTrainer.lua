-------------------------------------------------------------------------------
--  NaowhForever_TrainingTrainer.lua -- the Training Planner on the way to the trainer and at
--  it. Level-Up Toast: on a level-up with spells to train, a toast says how many, what they
--  cost and whether you can afford them, with a button to open the planner. Panel at the
--  Trainer: beside your class trainer's window, what it offers you now, ticked, with the
--  total and Learn All I Can Afford; after learning, a button to put the new ranks on your
--  bars (the Trainer popup's rank check).
--
--  Both register nothing while their switch, or the module, is off.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local T = ns.THEME
local UI = ns.UI
local Training = ns.Training
local S = ns.TrainingSettings

local LOGO = "Interface\\AddOns\\NaowhForever\\Media\\LogoAddon.tga"
local BLACK = { r = 0, g = 0, b = 0 }
local WARN = { r = 0.94, g = 0.70, b = 0.29 }

local TOAST_W, TOAST_PAD = 440, 18
local TOAST_ICON, TOAST_ICONS = 30, 10
local TOAST_SECONDS = 20       -- how long it stays unless dismissed
local LEARN_SETTLE = 1         -- seconds after the level-up for spells learned with it to land

local PANEL_W, PANEL_PAD = 380, 10
local PANEL_HEADER = 40
local OFFER_H, OFFER_ICON, MAX_OFFERS = 34, 26, 10
local CHECK = 16
local FOOTER_H = 92        -- the total, the note and Learn All
local BARS_H = 32          -- the bars button over it, once something is learned
local EMPTY_H = 44         -- the line saying there is nothing to train

local function ToastOn()
    return Training.On() and S.Get("levelUpToast")
end

local function PanelOn()
    return Training.On() and S.Get("trainerPanel")
end

-------------------------------------------------------------------------------
--  Level-up toast
-------------------------------------------------------------------------------
local toast, toastGen, unlocked = nil, 0, false

local function PlaceToast()
    local pos = S.Get("toastPos")
    toast:ClearAllPoints()
    if pos then
        toast:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    else
        toast:SetPoint("TOP", UIParent, "TOP", 0, -140)
    end
end

local function BuildToast()
    toast = CreateFrame("Frame", "NaowhForeverTrainingToast", UIParent)
    toast:SetWidth(TOAST_W)
    toast:SetFrameStrata("DIALOG")
    toast:SetClampedToScreen(true)
    toast:SetMovable(true)
    toast:EnableMouse(true)
    ns.Solid(toast, "BACKGROUND", T.bg, 0.97):SetAllPoints()
    ns.Border(toast, T.accent)
    local logo = toast:CreateTexture(nil, "ARTWORK")
    logo:SetTexture(LOGO, nil, nil, "TRILINEAR")
    logo:SetSize(26, 26)
    logo:SetPoint("TOPLEFT", TOAST_PAD, -TOAST_PAD)
    toast.title = ns.Font(toast, 22, nil)
    toast.title:SetPoint("LEFT", logo, "RIGHT", 10, 0)
    toast.line = ns.Font(toast, 14, nil)
    toast.line:SetPoint("TOPLEFT", logo, "BOTTOMLEFT", 0, -12)
    toast.line:SetWidth(TOAST_W - 2 * TOAST_PAD)
    toast.line:SetJustifyH("LEFT")
    toast.line:SetWordWrap(true)
    toast.icons = {}
    for i = 1, TOAST_ICONS do
        local icon = toast:CreateTexture(nil, "ARTWORK")
        icon:SetSize(TOAST_ICON, TOAST_ICON)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        toast.icons[i] = icon
    end
    toast.open = ns.AccentBorder(ns.Button(toast, "Open Planner", 140, 28, function()
        toast:Hide()
        ns.OpenTrainingWindow()
    end))
    toast.dismiss = ns.Button(toast, "Dismiss", 90, 28, function() toast:Hide() end)
    toast.mover = UI.AttachMover(toast, "Level-Up Toast", function(pos) S.Set("toastPos", pos) end, "Training Planner/Settings", "Training Planner/Settings:onTheWay")
    PlaceToast()
    toast:Hide()
end

local function FillToast(level, plan)
    local cost, gold = Training.Total(plan.now), GetMoney()
    local afford, budget = 0, gold
    for _, entry in ipairs(plan.now) do
        local price = Training.Price(entry)
        if price <= budget then
            afford = afford + 1
            budget = budget - price
        end
    end
    toast.title:SetText("Level " .. level)
    local count = #plan.now == 1 and "1 spell" or (#plan.now .. " spells")
    toast.line:SetText(("%s to train, %s in all. %s"):format(count, Training.Coins(cost),
        afford == #plan.now and "You can afford every one." or ("You can afford " .. afford .. " of them.")))
    local y = -(TOAST_PAD + 26 + 12 + math.ceil(toast.line:GetStringHeight()) + 12)
    for i, icon in ipairs(toast.icons) do
        local entry = plan.now[i]
        icon:SetShown(entry ~= nil)
        if entry then
            icon:SetTexture(C_Spell.GetSpellTexture(entry[2]))
            icon:ClearAllPoints()
            icon:SetPoint("TOPLEFT", TOAST_PAD + (i - 1) * (TOAST_ICON + 6), y)
        end
    end
    y = y - TOAST_ICON - 14
    toast.open:ClearAllPoints()
    toast.open:SetPoint("TOPLEFT", TOAST_PAD, y)
    toast.dismiss:ClearAllPoints()
    toast.dismiss:SetPoint("LEFT", toast.open, "RIGHT", 8, 0)
    toast:SetHeight(-y + 28 + TOAST_PAD)
end

local function ShowToast(level)
    local plan = Training.Plan(level)
    if #plan.now == 0 then return end
    if not toast then BuildToast() end
    FillToast(level, plan)
    toast:Show()
    toastGen = toastGen + 1
    local gen = toastGen
    C_Timer.After(TOAST_SECONDS, function()
        if gen == toastGen and not unlocked then toast:Hide() end
    end)
end

-------------------------------------------------------------------------------
--  Panel at the trainer
-------------------------------------------------------------------------------
local panel
local unpicked = {}        -- name|level -> true for the offers unticked at this visit
local learned = 0          -- spells learned from the panel at this visit

local function Key(offer)
    return offer.name .. "|" .. offer.level
end

-- What the trainer offers you now, in its own order: the services it can teach you, with the
-- class spell each one is where the planner knows it. Forever's service kind can be missing
-- (seen at profession trainers); then it is offered when its level is reached.
local function Offers()
    local byKey = Training.SpellsByService()
    local out, myLevel = {}, UnitLevel("player")
    for i = 1, GetNumTrainerServices() do
        local name, kind, icon = ns.TrainerServiceInfo(i)
        local level = select(4, GetTrainerServiceInfo(i)) or 0
        local spell = Training.ServiceSpell(byKey, i)
        local open = kind == "available"
            or kind == nil and level <= myLevel and not (spell and C_SpellBook.IsSpellKnown(spell))
        if name and level > 0 and open then
            out[#out + 1] = { index = i, name = name, level = level, icon = icon, spell = spell,
                cost = GetTrainerServiceCost(i) or 0 }
        end
    end
    return out
end

-- The ticked offers you can pay for: in the trainer's order, each while the gold lasts.
local function Affordable(offers)
    local out, budget = {}, GetMoney()
    for _, offer in ipairs(offers) do
        if not unpicked[Key(offer)] and offer.cost <= budget then
            out[#out + 1] = offer
            budget = budget - offer.cost
        end
    end
    return out
end

local RenderPanel

-- Last index first: buying a service can renumber the ones after it, and one whose index now
-- names another service is skipped.
local function LearnAll()
    local buy = Affordable(panel.offers)
    table.sort(buy, function(a, b) return a.index > b.index end)
    for _, offer in ipairs(buy) do
        if ns.TrainerServiceInfo(offer.index) == offer.name then
            BuyTrainerService(offer.index)
            learned = learned + 1
        end
    end
    RenderPanel()
end

local function CheckPaint(row)
    local on = not unpicked[Key(row.offer)]
    row.tick:SetShown(on)
    row.box:SetColor(on and T.accent.r or T.line.r, on and T.accent.g or T.line.g, on and T.accent.b or T.line.b, 1)
    row:SetAlpha(on and 1 or 0.55)
end

local function NewOffer(i)
    local row = CreateFrame("Button", nil, panel)
    row:SetSize(PANEL_W - 2 * PANEL_PAD, OFFER_H - 2)
    row:SetPoint("TOPLEFT", PANEL_PAD, -(PANEL_HEADER + 4 + (i - 1) * OFFER_H))
    local check = CreateFrame("Frame", nil, row)
    check:SetSize(CHECK, CHECK)
    check:SetPoint("LEFT", 4, 0)
    ns.Solid(check, "BACKGROUND", T.panel, 1):SetAllPoints()
    row.box = ns.Border(check, T.line)
    row.tick = ns.Solid(check, "ARTWORK", T.accent, 1)
    row.tick:SetPoint("TOPLEFT", 4, -4)
    row.tick:SetPoint("BOTTOMRIGHT", -4, 4)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(OFFER_ICON, OFFER_ICON)
    row.icon:SetPoint("LEFT", check, "RIGHT", 10, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.price = ns.Font(row, 13, nil)
    row.price:SetPoint("RIGHT", -4, 0)
    row.name = ns.Font(row, 13, nil)
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, 0)
    row.name:SetPoint("RIGHT", row.price, "LEFT", -8, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.rank = ns.Font(row, 11, nil, T.muted)
    row.rank:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, 0)
    row:SetScript("OnClick", function(self)
        local key = Key(self.offer)
        unpicked[key] = not unpicked[key] or nil
        RenderPanel()
    end)
    row:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetTrainerService(self.offer.index)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Click to leave it out of Learn All.", T.muted.r, T.muted.g, T.muted.b, true)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)
    panel.rows[i] = row
    return row
end

local function BuildPanel()
    panel = CreateFrame("Frame", nil, UIParent)
    panel:SetWidth(PANEL_W)
    panel:SetFrameStrata("DIALOG")
    panel:EnableMouse(true)
    panel:SetClampedToScreen(true)
    ns.Solid(panel, "BACKGROUND", T.bg, 0.97):SetAllPoints()
    ns.Border(panel, BLACK)
    local logo = panel:CreateTexture(nil, "ARTWORK")
    logo:SetTexture(LOGO, nil, nil, "TRILINEAR")
    logo:SetSize(20, 20)
    logo:SetPoint("LEFT", panel, "TOPLEFT", PANEL_PAD, -PANEL_HEADER / 2)
    local title = ns.Font(panel, 15, nil)
    title:SetPoint("LEFT", logo, "RIGHT", 8, 0)
    title:SetText("Train Now")
    panel.close = ns.Button(panel, "x", 20, 20, function()
        panel.dismissed = true
        panel:Hide()
    end)
    panel.close:SetPoint("RIGHT", panel, "TOPRIGHT", -PANEL_PAD, -PANEL_HEADER / 2)
    panel.count = ns.Font(panel, 12, nil, T.muted)
    panel.count:SetPoint("RIGHT", panel.close, "LEFT", -10, 0)
    local rule = ns.Solid(panel, "ARTWORK", T.line, 1)
    rule:SetPoint("TOPLEFT", 0, -PANEL_HEADER)
    rule:SetPoint("TOPRIGHT", 0, -PANEL_HEADER)
    ns.Hairline(rule, "h")
    panel.rows = {}

    panel.footer = CreateFrame("Frame", nil, panel)
    panel.footer:SetPoint("BOTTOMLEFT")
    panel.footer:SetPoint("BOTTOMRIGHT")
    panel.footer:SetHeight(FOOTER_H)
    local footRule = ns.Solid(panel.footer, "ARTWORK", T.line, 1)
    footRule:SetPoint("TOPLEFT")
    footRule:SetPoint("TOPRIGHT")
    ns.Hairline(footRule, "h")
    panel.total = ns.Font(panel.footer, 13, nil)
    panel.total:SetPoint("TOPLEFT", PANEL_PAD, -12)
    panel.note = ns.Font(panel.footer, 12, nil, T.muted)
    panel.note:SetPoint("TOPRIGHT", -PANEL_PAD, -12)
    panel.learn = ns.AccentBorder(ns.Button(panel.footer, "Learn All", PANEL_W - 2 * PANEL_PAD, 30, LearnAll))
    panel.learn:SetPoint("BOTTOMLEFT", PANEL_PAD, PANEL_PAD)
    panel.bars = ns.Button(panel.footer, "Put the New Ranks on My Bars", PANEL_W - 2 * PANEL_PAD, 26, function()
        if ns.TrainerRankCheck then ns.TrainerRankCheck() end
    end)
    panel.done = ns.Font(panel, 13, nil, T.muted)
    panel.done:SetPoint("TOPLEFT", PANEL_PAD, -(PANEL_HEADER + 14))
    panel.done:SetWidth(PANEL_W - 2 * PANEL_PAD)
    panel.done:SetJustifyH("LEFT")
    panel:Hide()
end

RenderPanel = function()
    local frame = _G.ClassTrainerFrame
    if not (PanelOn() and frame and frame:IsShown()) or IsTradeskillTrainer() then
        return panel and panel:Hide()
    end
    if not panel then BuildPanel() end
    if panel.dismissed then return end
    local offers = Offers()
    panel.offers = offers
    local shown = math.min(#offers, MAX_OFFERS)
    for i = 1, shown do
        local row = panel.rows[i] or NewOffer(i)
        local offer = offers[i]
        row.offer = offer
        row.icon:SetTexture(offer.icon or offer.spell and C_Spell.GetSpellTexture(offer.spell))
        row.name:SetText(offer.name)
        row.rank:SetText(offer.spell and C_Spell.GetSpellSubtext(offer.spell) or ("Level " .. offer.level))
        row.price:SetText(Training.Coins(offer.cost))
        CheckPaint(row)
        row:Show()
    end
    for i = shown + 1, #panel.rows do panel.rows[i]:Hide() end

    local picked, pickedCost = 0, 0
    for _, offer in ipairs(offers) do
        if not unpicked[Key(offer)] then
            picked = picked + 1
            pickedCost = pickedCost + offer.cost
        end
    end
    local buy = Affordable(offers)
    local buyCost = 0
    for _, offer in ipairs(buy) do buyCost = buyCost + offer.cost end
    panel.count:SetText(#offers > 0 and (picked .. " of " .. #offers .. " picked") or "")
    panel.total:SetText("Picked  " .. Training.Coins(pickedCost))
    local gold = GetMoney()
    panel.note:SetText(gold >= pickedCost and ("Leaves " .. Training.Coins(gold - pickedCost))
        or (Training.Coins(pickedCost - gold) .. " short"))
    local c = gold >= pickedCost and T.muted or WARN
    panel.note:SetTextColor(c.r, c.g, c.b, 1)
    ns.SetButtonText(panel.learn, #buy > 0
        and ("Learn All I Can Afford (%d)  %s"):format(#buy, Training.Coins(buyCost)) or "Nothing You Can Afford")
    panel.learn:SetEnabled(#buy > 0)
    panel.learn:SetAlpha(#buy > 0 and 1 or 0.45)

    local any, hasBars = #offers > 0, learned > 0 and ns.TrainerRankCheck ~= nil
    panel.done:SetShown(not any)
    panel.done:SetText(learned > 0 and ("Learned " .. learned .. " spells. Nothing else to train here for now.")
        or "Nothing to train here for now.")
    panel.total:SetShown(any)
    panel.note:SetShown(any)
    panel.learn:SetShown(any)
    panel.bars:SetShown(hasBars)
    panel.bars:ClearAllPoints()
    if any then
        panel.bars:SetPoint("BOTTOMLEFT", panel.learn, "TOPLEFT", 0, 6)
    else
        panel.bars:SetPoint("BOTTOMLEFT", PANEL_PAD, PANEL_PAD)
    end
    local footer = (any and FOOTER_H or PANEL_PAD) + (hasBars and BARS_H or 0)
    panel.footer:SetHeight(footer)
    panel:SetHeight(PANEL_HEADER + (any and (shown * OFFER_H + 8) or EMPTY_H) + footer)
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", frame, "TOPRIGHT", 8, 0)
    panel:Show()
end

-------------------------------------------------------------------------------
--  Events
-------------------------------------------------------------------------------
local panelQueued = false
local function QueuePanel()
    if panelQueued then return end
    panelQueued = true
    C_Timer.After(0, function()
        panelQueued = false
        RenderPanel()
    end)
end

local hookedTrainer
local function HookTrainerFrame()
    local frame = _G.ClassTrainerFrame
    if hookedTrainer or not frame then return end
    hookedTrainer = true
    frame:HookScript("OnShow", function() if PanelOn() then QueuePanel() end end)
    frame:HookScript("OnHide", function() if panel then panel:Hide() end end)
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, arg1)
    if event == "PLAYER_LEVEL_UP" then
        C_Timer.After(LEARN_SETTLE, function() if ToastOn() then ShowToast(arg1) end end)
    elseif event == "ADDON_LOADED" then
        if arg1 == "Blizzard_TrainerUI" then HookTrainerFrame() end
    elseif event == "TRAINER_SHOW" then
        wipe(unpicked)
        learned = 0
        if panel then panel.dismissed = nil end
        HookTrainerFrame()
        QueuePanel()
    elseif event == "TRAINER_CLOSED" then
        if panel then panel:Hide() end
    else
        QueuePanel()
    end
end)

local function Apply()
    events:UnregisterAllEvents()
    if toast and not ToastOn() and not unlocked then toast:Hide() end
    if panel and not PanelOn() then panel:Hide() end
    if ToastOn() then events:RegisterEvent("PLAYER_LEVEL_UP") end
    if PanelOn() then
        for _, event in ipairs({ "TRAINER_SHOW", "TRAINER_UPDATE", "TRAINER_CLOSED", "PLAYER_MONEY", "ADDON_LOADED" }) do
            events:RegisterEvent(event)
        end
        HookTrainerFrame()
    end
end

S.OnChange(function(key)
    if key == "enabled" or key == "levelUpToast" or key == "trainerPanel" then Apply() end
end)
hooksecurefunc(ns, "Apply", Apply)

-- Unlock Mode shows the toast as it would look now, to place it.
hooksecurefunc(ns, "ShowRaidReminderAnchorConfig", function()
    if not ToastOn() then return end
    unlocked = true
    if not toast then BuildToast() end
    local level = UnitLevel("player")
    FillToast(level, Training.Plan(level))
    toast.mover:Show()
    toast:Show()
end)
hooksecurefunc(ns, "HideRaidReminderAnchorConfig", function()
    if not unlocked then return end
    unlocked = false
    toast.mover:Hide()
    toast:Hide()
end)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    Apply()
end)
