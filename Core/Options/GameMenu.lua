-- GameMenu.lua: the Naowh Forever button in the game menu, which opens /nf.
local ns = _G.NaowhForever

local F = ns.FEATURES.account

local SECTION = 20
local NUDGE = 0.001
local ELLESMERE = "Ellesmere"
local TEXT_NAOWH, TEXT_FOREVER = "Naowh ", "Forever"

local button

local function On()
    local on = ns.AccountSettings().gameMenuButton
    if on == nil then return F.gameMenuButton end
    return on ~= false
end

local function Clicked()
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION)
    HideUIPanel(GameMenuFrame)
    ns.OpenOptionsWindow()
end

local function Label()
    return TEXT_NAOWH .. ns.Color("accent", TEXT_FOREVER)
end

local function ButtonText(b)
    local text = b.GetText and b:GetText()
    return type(text) == "string" and text or ""
end

local function Find(menu, test)
    for _, child in ipairs({ menu:GetChildren() }) do
        if child ~= button and child:IsShown() and child.layoutIndex and test(ButtonText(child)) then
            return child
        end
    end
end

local function IsEllesmere(text) return text:find(ELLESMERE, 1, true) ~= nil end
local function IsOptions(text) return text == GAMEMENU_OPTIONS end

local function Added(menu)
    button = nil
    if not On() then return end
    button = menu:AddButton(Label(), Clicked)
end

local function PlaceAfterOptions(menu)
    local options = Find(menu, IsOptions)
    if not options then return false end
    button.layoutIndex = options.layoutIndex + NUDGE
    button.topPadding = SECTION
    return true
end

local function Placed(menu)
    if not (button and button:IsShown()) then return end
    local before = Find(menu, IsEllesmere)
    if before then
        button.layoutIndex = before.layoutIndex - NUDGE
        button.topPadding, before.topPadding = before.topPadding, nil
    elseif not PlaceAfterOptions(menu) then
        return
    end
    menu:MarkDirty()
end

local function OnBoot(self)
    if not (GameMenuFrame and GameMenuFrame.InitButtons and GameMenuFrame.AddButton) then return end
    self:UnregisterAllEvents()
    hooksecurefunc(GameMenuFrame, "InitButtons", Added)
    GameMenuFrame:HookScript("OnShow", Placed)
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:RegisterEvent("ADDON_LOADED")
boot:SetScript("OnEvent", OnBoot)
