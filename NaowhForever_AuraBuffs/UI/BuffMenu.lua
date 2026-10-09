-- BuffMenu.lua: hovering a reminder lists the carried items it watches, as secure buttons to use one.
local ns = _G.NaowhForever

local A = ns.AuraBuffs
local St = A.Style

local COLS, CELL, STEP, PAD, GAP = St.MENU_COLS, St.MENU_CELL, St.MENU_STEP, St.MENU_PAD, St.MENU_GAP
local LEAVE_DELAY = 0.15

local popup
local seen = {}

local Menu = { unlocked = false }
A.BuffMenu = Menu

function Menu.Hide()
    if popup and not InCombatLockdown() then
        popup:Hide()
        popup:ClearAllPoints()
    end
end

local function LeftMenu()
    if popup and popup:IsShown() and not popup:IsMouseOver()
        and not (popup.owner and popup.owner:IsMouseOver()) then Menu.Hide() end
end

function Menu.Leave()
    C_Timer.After(LEAVE_DELAY, LeftMenu)
end

local function OnItemEnter(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(self.itemID)
    GameTooltip:Show()
end

local function OnItemLeave()
    GameTooltip:Hide()
    Menu.Leave()
end

local function Build()
    popup = CreateFrame("Frame", nil, UIParent)
    popup:SetFrameStrata("DIALOG")
    popup:SetClampedToScreen(true)
    popup:EnableMouse(true)
    popup:SetScript("OnLeave", Menu.Leave)
    ns.Solid(popup, "BACKGROUND", ns.THEME.bg, 1):SetAllPoints()
    ns.Border(popup)
    popup.buttons = {}
end

local function Button(count)
    local button = popup.buttons[count]
    if button then return button end
    button = CreateFrame("Button", nil, popup, "SecureActionButtonTemplate")
    button:SetSize(CELL, CELL)
    button:RegisterForClicks("AnyUp", "AnyDown")
    button:SetAttribute("type1", "item")
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetAllPoints()
    ns.Border(button, St.BLACK)
    button:SetScript("PostClick", Menu.Hide)
    button:SetScript("OnEnter", OnItemEnter)
    button:SetScript("OnLeave", OnItemLeave)
    popup.buttons[count] = button
    return button
end

local function Fill(items)
    local count = 0
    wipe(seen)
    for _, id in ipairs(items) do
        if not seen[id] and C_Item.GetItemCount(id) > 0 then
            seen[id] = true
            count = count + 1
            local button = Button(count)
            button.itemID = id
            button:SetAttribute("item1", "item:" .. id)
            button.icon:SetTexture(C_Item.GetItemIconByID(id))
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", PAD + ((count - 1) % COLS) * STEP, -PAD - math.floor((count - 1) / COLS) * STEP)
            button:Show()
        end
    end
    for i = count + 1, #popup.buttons do popup.buttons[i]:Hide() end
    return count
end

function Menu.Open(cell)
    if Menu.unlocked or InCombatLockdown() or C_Secrets.ShouldAurasBeSecret() or not cell.items then return end
    if not popup then Build() end
    popup.owner = cell
    local count = Fill(cell.items)
    popup:SetSize(math.max(1, math.min(count, COLS)) * STEP + PAD, math.max(1, math.ceil(count / COLS)) * STEP + PAD)
    popup:ClearAllPoints()
    popup:SetPoint("TOPLEFT", cell, "BOTTOMLEFT", 0, -GAP)
    popup:SetShown(count > 0)
end

function Menu.Owner()
    return popup and popup:IsShown() and popup.owner or nil
end

function Menu.OwnedBy(cell)
    return popup ~= nil and popup.owner == cell
end
