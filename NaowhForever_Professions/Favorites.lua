-- Favorites.lua: favourite recipes, learned or not, kept in the profile by spell ID (ns.ProfFavorites).
local ns = _G.NaowhForever

local P = ns.Professions
local S = P.Settings

local Favorites = {}
P.Favorites = Favorites
ns.ProfFavorites = Favorites

function Favorites.Store()
    local db = S.DB()
    if type(db.craftFavorites) ~= "table" then db.craftFavorites = {} end
    return db.craftFavorites
end

function Favorites.Is(info)
    if not info then return false end
    local own = Favorites.Store()[info.recipeID or info.spell]
    if own ~= nil then return own end
    return info.favorite == true
end

function Favorites.Toggle(info)
    if not info then return end
    local on = not Favorites.Is(info)
    Favorites.Store()[info.recipeID or info.spell] = on
    if not info.recipeID then return end
    info.favorite = on
    if C_TradeSkillUI.SetRecipeFavorite then pcall(C_TradeSkillUI.SetRecipeFavorite, info.recipeID, on) end
end
