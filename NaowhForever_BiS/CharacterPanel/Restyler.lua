-- Restyler.lua: fades, tints and restyles the game's art and text, remembering each piece to put it back (CP.Restyler, CP.PanelArt).
local ns = _G.NaowhForever

local T = ns.THEME
local CP = ns.CharacterPanel
local C = CP.C

local TEXTURE = C.TEXTURE
local TAB_RGB, HOVER_ALPHA = C.TAB_RGB, C.HOVER_ALPHA

local function Textures(frame, each, ...)
    for _, region in ipairs({ frame:GetRegions() }) do
        if region:GetObjectType() == TEXTURE then each(region, ...) end
    end
end

function CP.Restyler()
    local r = {}
    local faded, tinted, fonts = {}, {}, {}

    function r.Fade(region)
        if type(region) == "table" and region.SetAlpha then
            region:SetAlpha(0)
            faded[region] = true
        end
    end

    function r.FadeRegions(frame)
        if not frame then return end
        for _, region in ipairs({ frame:GetRegions() }) do r.Fade(region) end
    end

    function r.FadeTree(frame)
        if not frame then return end
        Textures(frame, r.Fade)
        for _, child in ipairs({ frame:GetChildren() }) do r.FadeTree(child) end
    end

    function r.Tint(region, color, alpha)
        if not (type(region) == "table" and region.SetDesaturated) then return end
        region:SetDesaturated(true)
        region:SetVertexColor(color.r, color.g, color.b, alpha or 1)
        tinted[region] = true
    end

    function r.TintTree(frame, color)
        if not frame then return end
        Textures(frame, r.Tint, color)
        for _, child in ipairs({ frame:GetChildren() }) do r.TintTree(child, color) end
    end

    function r.Restyle(fontString, size, color)
        if not fontString then return end
        if not fonts[fontString] then fonts[fontString] = fontString:GetFontObject() or GameFontNormal end
        fontString:SetFont(ns.UIFontPath(), size, "")
        fontString:SetTextColor(color.r, color.g, color.b, 1)
    end

    function r.TintSideTab(tab)
        if not tab then return end
        r.Tint(tab.Background, TAB_RGB)
        r.Tint(tab.SelectedTexture, T.accent)
        r.Tint(tab.HighlightTexture, T.accent, HOVER_ALPHA)
        r.Fade(tab.TabGlow)
    end

    function r.FadeClose(close)
        if not close then return end
        r.Fade(close:GetNormalTexture())
        r.Fade(close:GetPushedTexture())
        r.Fade(close:GetHighlightTexture())
        r.Fade(close:GetDisabledTexture())
    end

    function r.Restore()
        for region in pairs(faded) do region:SetAlpha(1) end
        wipe(faded)
        for region in pairs(tinted) do
            region:SetDesaturated(false)
            region:SetVertexColor(1, 1, 1, 1)
        end
        wipe(tinted)
        for fontString, object in pairs(fonts) do fontString:SetFontObject(object) end
        wipe(fonts)
    end

    return r
end

CP.PanelArt = CP.Restyler()
