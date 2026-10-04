-------------------------------------------------------------------------------
--  UI/Actions.lua -- what you can do with your lists (ns.BiS.Actions), the same from the
--  window's title bar and list menu as from the settings page.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local B = ns.BiS
local L = B.Lists

local A = {}
B.Actions = A

local function NamePrompt(title, text, save)
    ns.PromptText(title, text, 40, function(name)
        local ok, err = save(name)
        if not ok then ns.Print("BiS list not saved: " .. err .. ".") end
    end)
end

function A.New()
    NamePrompt("Name the new BiS list", "", ns.NewBisList)
end

function A.Rename()
    NamePrompt("Rename this BiS list", (L.List().name:gsub("||", "|")), ns.RenameBisList)
end

function A.Delete()
    ns.Confirm(("Delete the BiS list %s? Every character of your class using it moves to another list.")
        :format(L.List().name), ns.DeleteBisList)
end

function A.Import()
    ns.PromptText("Paste a Naowh BiS list", "", 0, function(text) ns.ImportBisList(text) end)
end

function A.StatWeights()
    ns.OpenOptionsWindow("BiS List/Stat Weights")
end

function A.Export()
    ns.ShowCopyBox("Copy this to share your list", ns.ExportBisList())
end

-- Drop Alert as it would go for your first BiS: up for a roll, dropped, then yours.
function A.TestAlert()
    if not B.Alerts.Test() then ns.Print("Pick your BiS first: the test plays with your list's first one.") end
end

-- The lists of your class to switch between, then making, renaming and deleting one.
function A.ListMenu(owner)
    local values, order, active = ns.BisListChoices()
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle("Your class's BiS lists")
        for _, id in ipairs(order) do
            root:CreateRadio(values[id], function() return id == active end, function() ns.SelectBisList(id) end)
        end
        root:CreateDivider()
        root:CreateButton("New List", A.New)
        root:CreateButton("Rename This List", A.Rename)
        root:CreateButton("Delete This List", A.Delete)
    end)
end
