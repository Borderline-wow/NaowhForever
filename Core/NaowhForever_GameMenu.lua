-------------------------------------------------------------------------------
--  NaowhForever_GameMenu.lua -- a Naowh Forever button in the game menu (Esc), just before
--  EllesmereUI's when that is there, else under Options; it opens /nf. Switched with Game Menu
--  Button on the Settings page (account-wide, on by default).
-------------------------------------------------------------------------------
local ns = _G.NaowhForever

local SECTION = 20
local NUDGE = 0.001

local button

local function On()
    return ns.AccountSettings().gameMenuButton ~= false
end

local function Clicked()
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION)
    HideUIPanel(GameMenuFrame)
    ns.OpenOptionsWindow()
end

local function Label()
    return "Naowh " .. ns.Color("accent", "Forever")
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

local function IsEllesmere(text) return text:find("Ellesmere", 1, true) ~= nil end
local function IsOptions(text) return text == GAMEMENU_OPTIONS end

local function Added(menu)
    button = nil
    if not On() then return end
    button = menu:AddButton(Label(), Clicked)
end

local function Placed(menu)
    if not (button and button:IsShown()) then return end
    local before = Find(menu, IsEllesmere)
    if before then
        button.layoutIndex = before.layoutIndex - NUDGE
        button.topPadding, before.topPadding = before.topPadding, nil
    else
        local options = Find(menu, IsOptions)
        if not options then return end
        button.layoutIndex = options.layoutIndex + NUDGE
        button.topPadding = SECTION
    end
    menu:MarkDirty()
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:RegisterEvent("ADDON_LOADED")
boot:SetScript("OnEvent", function(self)
    if not (GameMenuFrame and GameMenuFrame.InitButtons and GameMenuFrame.AddButton) then return end
    self:UnregisterAllEvents()
    hooksecurefunc(GameMenuFrame, "InitButtons", Added)
    GameMenuFrame:HookScript("OnShow", Placed)
end)
