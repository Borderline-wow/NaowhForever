-- Offline behavior tests. Does not emulate client rendering or security restrictions.
local checks = 0
local function check(name, value) assert(value, name); checks = checks + 1 end
local secret = setmetatable({}, { __tostring = function() error("formatted secret") end })
local settings = { enabled=true, tooltipDisplay=true, tooltipSpellID=true, tooltipItemID=true,
    tooltipNPCID=true, tooltipRestricted="hide", tooltipCopy=true, tooltipModifier="CTRL-SHIFT",
    tooltipKey="C", tooltipWowhead="classic", tooltipCopyFormat="url", copyModifier="CTRL", copyKey="C", copyTooltipIds=true }
local frames, callbacks, combat, focus, ctrl, shift, alt = {}, {}, false, nil, true, true, false
local lastPanel, lastDimmer
local function noop() end
local function Frame()
    local f = { scripts={}, events={}, shown=true, lines={}, cache={} }
    setmetatable(f,{__index=function() return noop end})
    function f:SetScript(k,v) self.scripts[k]=v end
    function f:HookScript(k,v) self.scripts[k]=v end
    function f:RegisterEvent(k) self.events[k]=true end
    function f:SetPropagateKeyboardInput(v) assert(not combat);self.propagate=v end
    function f:EnableKeyboard(v) self.keyboard=v end
    function f:SetText(v) assert(v~=secret);self.text=v end
    function f:GetText() return self.text end
    function f:SetTexture(v) self.texture=v end
    function f:IsForbidden() return self.forbidden==true end
    function f:IsShown() return self.shown end
    function f:Show() self.shown=true end
    function f:Hide() self.shown=false;if type(self.onClose)=='function' then self.onClose() end end
    function f:SetFocus() focus=self end
    function f:ClearFocus() if focus==self then focus=nil end end
    function f:GetPrimaryTooltipData() return self.data end
    function f:CreateTexture() return Frame() end
    function f:AddLine(...) self.lines[#self.lines+1]={...} end
    function f:AddDoubleLine(...) self.lines[#self.lines+1]={...} end
    frames[#frames+1]=f;return f
end
local ns={THEME={accent={r=0,g=.7,b=1},muted={r=.5,g=.6,b=.7},bg={}},UI={},Print=noop,Apply=noop}
ns.QoLSettings={Get=function(k) return settings[k] end,Set=function(k,v) settings[k]=v end}
ns.MakeModal=function() lastDimmer,lastPanel=Frame(),Frame();return lastDimmer,lastPanel end
ns.Solid=function() return Frame() end;ns.Border=noop
ns.UI.Keep=function(parent,key,fn) local f=fn(parent);parent.cache[key]=f;return f end
ns.UI.KeepFont=function(parent,key) local f=Frame();parent.cache[key]=f;return f end
ns.UI.KeepButton=function(parent,key,text,w,h,fn) local f=Frame();f.label=Frame();f.label:SetText(text);f.click=fn;parent.cache[key]=f;return f end
local tooltip=Frame();local title=Frame();title:SetText('Test name')
local env={_G={NaowhForever=ns},GameTooltip=tooltip,ItemRefTooltip=Frame(),ShoppingTooltip1=Frame(),ShoppingTooltip2=Frame(),GameTooltipTextLeft1=title,
    CreateFrame=Frame,Enum={TooltipDataType={Spell=1,Item=2,Unit=3}},SlashCmdList={},
    issecretvalue=function(v) return rawequal(v,secret) end,canaccessvalue=function(v) return not rawequal(v,secret) end,
    issecrettable=function(v) return rawequal(v,secret) end,
    TooltipDataProcessor={AddTooltipPostCall=function(k,v) callbacks[k]=v end},
    C_Spell={GetSpellTexture=function() return 135812 end},C_Item={GetItemIconByID=function() return 134400 end},
    InCombatLockdown=function() return combat end,GetCurrentKeyBoardFocus=function() return focus end,
    IsControlKeyDown=function() return ctrl end,IsShiftKeyDown=function() return shift end,IsAltKeyDown=function() return alt end,
    hooksecurefunc=function(t,k,fn) local old=t[k];t[k]=function(...) old(...);fn(...) end end,
    strsplit=function(delim,s) local a={};for part in s:gmatch('[^'..delim..']+') do a[#a+1]=part end;return unpack(a) end,
}
setmetatable(env,{__index=_G})
local chunk=assert(loadfile('QoL/NaowhForever_GlobalCopy.lua'));setfenv(chunk,env);chunk()
local function clear()
 tooltip.lines={};if tooltip.scripts.OnTooltipCleared then tooltip.scripts.OnTooltipCleared(tooltip) end
end
local function show(data)
 clear();tooltip.data=data;callbacks[data.type](tooltip,data)
end
local function boot(event) for _,f in ipairs(frames) do if f.events[event] then f.scripts.OnEvent(f,event) end end end
local function keyboard() for _,f in ipairs(frames) do if f.scripts.OnKeyDown then return f end end end
show({type=1,id=133});check('spell footer',tooltip.lines[2][1]=='Spell ID' and tooltip.lines[2][2]=='133')
callbacks[1](tooltip,tooltip.data);check('no duplicate footer',#tooltip.lines==3)
show({type=2,id=6948});check('item footer',tooltip.lines[2][2]=='6948')
show({type=3,guid='Creature-0-1-2-3-12345-0001'});check('NPC entry ID',tooltip.lines[2][2]=='12345')
show({type=3,guid='Vehicle-0-1-2-3-678-0001'});check('vehicle entry ID',tooltip.lines[2][2]=='678')
show({type=3,guid='Player-1-12345'});check('player GUID excluded',#tooltip.lines==0)
show({type=1,id=secret});check('secret hidden by default',#tooltip.lines==0)
settings.tooltipRestricted='hidden';show({type=1,id=secret});check('secret placeholder',tooltip.lines[2][2]=='Hidden' and #tooltip.lines==2)
show({type=3,guid=secret});check('secret GUID placeholder',tooltip.lines[2][2]=='Hidden')
clear();callbacks[1](tooltip,secret);check('secret table ignored',#tooltip.lines==0)
clear();callbacks[1](tooltip,{type=secret,id=133});check('secret type ignored',#tooltip.lines==0)
show({type=1,id=0});check('invalid ID ignored',#tooltip.lines==0)
settings.tooltipSpellID=false;show({type=1,id=133});check('spell toggle',#tooltip.lines==0);settings.tooltipSpellID=true
settings.tooltipDisplay=false;show({type=2,id=6948});check('master toggle',#tooltip.lines==0);settings.tooltipDisplay=true
boot('PLAYER_LOGIN');local k=keyboard();check('shortcut listener enabled',k.keyboard==true)
show({type=1,id=133});k.scripts.OnKeyDown(k,'C');check('classic spell URL',lastPanel.cache.value.text=='https://www.wowhead.com/classic/spell=133')
check('card gets focus',focus==lastPanel.cache.value);check('listener yields to card',k.keyboard==false)
lastPanel.cache.id.click();check('ID tab',lastPanel.cache.value.text=='133')
lastPanel.cache.link.click();check('URL tab',lastPanel.cache.value.text:find('spell=133',1,true)~=nil)
lastDimmer:Hide();check('close restores keyboard',focus==nil and k.keyboard==true)
local prior=lastPanel;focus={};k.scripts.OnKeyDown(k,'C');check('typing ignored',lastPanel==prior);focus=nil
shift=false;k.scripts.OnKeyDown(k,'C');check('exact modifier required',lastPanel==prior);shift=true
combat=true;k.scripts.OnKeyDown(k,'C');check('combat does not open card',lastPanel==prior);combat=false
show({type=1,id=secret});k.scripts.OnKeyDown(k,'C');check('secret never copied',lastPanel==prior)
settings.tooltipWowhead='retail';show({type=2,id=6948});k.scripts.OnKeyDown(k,'C');check('retail item URL',lastPanel.cache.value.text=='https://www.wowhead.com/item=6948');lastDimmer:Hide()
show({type=3,guid='Creature-0-1-2-3-12345-0001'});k.scripts.OnKeyDown(k,'C');check('NPC URL',lastPanel.cache.value.text=='https://www.wowhead.com/npc=12345');lastDimmer:Hide()
settings.tooltipItemID=false;show({type=2,id=6948});prior=lastPanel;k.scripts.OnKeyDown(k,'C');check('disabled type not copied',lastPanel==prior)
ns.QoLSettings.Set('enabled',false);check('disabled listener',k.keyboard==false)
combat=true;ns.QoLSettings.Set('enabled',true);check('combat settings deferred',k.keyboard==false);combat=false;boot('PLAYER_REGEN_ENABLED');check('deferred listener restored',k.keyboard==true)
ns.PreviewTooltipCopyCard();check('preview opens card',lastPanel.cache.name.text=='Fireball - Preview')
lastDimmer:Hide()
tooltip.forbidden=true;show({type=1,id=133});check('forbidden tooltip untouched',#tooltip.lines==0)
prior=lastPanel;k.scripts.OnKeyDown(k,'C');check('forbidden tooltip not copied',lastPanel==prior);tooltip.forbidden=false
show({type=1,id=133});title:SetText('Readable');title.text=secret;k.scripts.OnKeyDown(k,'C');check('secret title uses generic label',lastPanel.cache.name.text=='Spell ID');lastDimmer:Hide();title.text='Test name'
settings.globalCopy=true;shift=false;k.scripts.OnKeyDown(k,'C');check('legacy copy shortcut preserved',lastPanel.cache.scroll.box.text=='133');lastDimmer:Hide()
shift=true;settings.globalCopy=false;ns.QoLSettings.Set('tooltipCopy',false);check('copy disabled independently',k.keyboard==false)
show({type=1,id=133});check('IDs remain with copy disabled',tooltip.lines[2][2]=='133' and #tooltip.lines==2)
print(checks..' tooltip-display checks passed')
