-- Offline behavior checks; these do not emulate client taint or rendering.
local checks = 0
local function check(label, ok) assert(ok, label); checks = checks + 1 end
local function fixture(settings)
    local s = { now = 0, frames = {}, named = {}, timers = {}, tickers = {}, sounds = 0,
        combat = false, secret = false, reads = 0, group = true, raid = false,
        units = {
            player = { name = 'You', class = 'PALADIN', threat = { false, 1, 81.8, 90, 900 } },
            party1 = { name = 'Tank', class = 'WARRIOR', threat = { true, 3, 100, 100, 1000 } },
            party2 = { name = 'Healer', class = 'PRIEST', threat = { false, 0, 20, 22, 220 } },
            pet = { name = 'Pet', threat = { false, 0, 10, 11, 110 } },
            target = { name = 'Target', guid = 'mob-a', hostile = true },
            focus = { name = 'Focus', guid = 'mob-b', hostile = true },
        }, settings = settings or {} }
    local function frame(kind, name, parent)
        local f = { kind = kind, scripts = {}, events = {}, shown = true, w = 280, h = 240, parent = parent }
        setmetatable(f, { __index = function() return function() end end })
        function f:SetScript(k, fn) self.scripts[k] = fn end
        function f:RegisterEvent(k) self.events[k] = true end
        function f:RegisterUnitEvent(k) self.events[k] = true end
        function f:UnregisterEvent(k) self.events[k] = nil end
        function f:UnregisterAllEvents() self.events = {} end
        function f:Show() self.shown = true end
        function f:Hide() self.shown = false; if self.scripts.OnHide then self.scripts.OnHide(self) end end
        function f:SetShown(v) if v then self:Show() else self:Hide() end end
        function f:IsShown() return self.shown end
        function f:SetSize(w,h) assert(type(w)=='number' and type(h)=='number'); self.w,self.h=w,h end
        function f:GetWidth() return self.w end
        function f:GetHeight() return self.h end
        function f:GetEffectiveScale() return 1 end
        function f:GetFrameLevel() return 1 end
        function f:GetLeft() return 100 end
        function f:GetTop() return 600 end
        function f:SetPoint(...) self.point={...} end
        function f:SetText(t) assert(type(t)~='boolean','boolean passed to SetText'); self.text=t end
        function f:SetFont(path,size) assert(type(path)=='string' and type(size)=='number'); self.fontSize=size end
        function f:SetTexture(t) self.texture=t end
        function f:SetDesaturated(v) self.desaturated=v end
        function f:SetStatusBarColor(...) self.color={...} end
        function f:SetColorTexture(...) self.colorTexture={...} end
        function f:SetValue(v) self.valueNumber=v end
        function f:CreateTexture() return frame('Texture',nil,self) end
        s.frames[#s.frames+1]=f; if name then s.named[name]=f end
        return f
    end
    local ns={ THEME={bg={},muted={},accent={r=0,g=0.7,b=1}},
        UIFontPath=function() return 'font.ttf' end, Print=function() end,
        Apply=function() end, ShowRaidReminderAnchorConfig=function() end, HideRaidReminderAnchorConfig=function() end,
        Font=function() return frame('FontString') end,
        Border=function(_,color) local b=frame('Border'); b.edge=color; return b end,
        Solid=function(_,_,color,alpha) local t=frame('Texture'); t.solid={color=color,alpha=alpha}; return t end,
        ThemeTint=function(_,literal) return literal end, Tooltip=function() end,
        Button=function(parent,text,w,h,fn) local b=frame('Button',nil,parent); b.label=frame('FontString'); b.label:SetText(text); b.scripts.OnClick=fn; return b end,
        OpenOptionsWindow=function(name) s.opened=name end,
        UI={STATUS={},FontPath=function() return 'font.ttf' end,AttachMover=function() return frame('Mover') end,
            SoundPathFor=function() return 'sound' end,_PlayLSMSound=function() s.sounds=s.sounds+1 end},
    }
    ns.UI.ModuleSettings=function(_, defaults)
        return {Get=function(k) if s.settings[k]~=nil then return s.settings[k] end return defaults[k] end,
            Set=function(k,v) s.settings[k]=v end}
    end
    local env={_G={NaowhForever=ns},MAX_RAID_MEMBERS=40,MAX_PARTY_MEMBERS=4,
        UIParent=frame('Parent'),CreateFrame=frame,
        RAID_CLASS_COLORS={PALADIN={r=1,g=0.5,b=0.8},WARRIOR={r=0.8,g=0.6,b=0.4},PRIEST={r=1,g=1,b=1},HUNTER={r=0.5,g=0.9,b=0.5}},
        UnitExists=function(u) return s.units[u]~=nil end,
        UnitCanAttack=function(_,u) return s.units[u] and s.units[u].hostile or false end,
        UnitName=function(u) return s.units[u] and s.units[u].name end,
        UnitGUID=function(u) return s.units[u] and s.units[u].guid end,
        UnitClass=function(u) return 'class',s.units[u] and s.units[u].class end,
        UnitIsUnit=function(a,b) return a==b end,
        UnitDetailedThreatSituation=function(u,mob)
            s.reads=s.reads+1; s.readMob=mob
            if s.secret then local v={secret=true};return v,v,v,v,v end
            return unpack(s.units[u].threat or {})
        end,
        UnitAffectingCombat=function() return s.combat end,InCombatLockdown=function() return s.combat end,
        IsInGroup=function() return s.group end,IsInRaid=function() return s.raid end,
        GetNumGroupMembers=function() return s.raid and 12 or 3 end,
        GetNumSubgroupMembers=function() return s.group and 2 or 0 end,
        UnitGroupRolesAssigned=function() return s.role or 'DAMAGER' end,
        GetShapeshiftFormID=function() return nil end,
        issecretvalue=function(v) return type(v)=='table' and v.secret==true end,
        C_Timer={After=function(delay,fn) s.timers[#s.timers+1]={at=s.now+delay,fn=fn} end,
            NewTicker=function(delay,fn) local t={fn=fn,cancelled=false};function t:Cancel() self.cancelled=true end;s.tickers[#s.tickers+1]=t;return t end},
        hooksecurefunc=function(t,k,fn) local old=t[k];t[k]=function(...) old(...);fn(...) end end,
    }
    setmetatable(env,{__index=_G})
    local chunk=assert(loadfile('ThreatMeter/NaowhForever_ThreatMeter.lua'));setfenv(chunk,env);chunk()
    s.ns=ns
    function s.fire(event,unit)
        local all={};for i,f in ipairs(s.frames) do all[i]=f end
        for _,f in ipairs(all) do if f.events[event] then f.scripts.OnEvent(f,event,unit) end end
    end
    function s.advance(dt)
        s.now=s.now+dt
        local again=true
        while again do
            again=false
            for i,t in ipairs(s.timers) do if t.at<=s.now then table.remove(s.timers,i);t.fn();again=true;break end end
        end
    end
    function s.set(k,v) ns.ThreatMeterSettings.Set(k,v);s.advance(0.21) end
    function s.bars()
        local out={};for _,f in ipairs(s.frames) do if f.kind=='StatusBar' and f.shown then out[#out+1]=f end end;return out
    end
    function s.bar(name) for _,f in ipairs(s.bars()) do if f.name.text==name then return f end end end
    function s.listens(event) for _,f in ipairs(s.frames) do if f.events[event] then return true end end return false end
    s.fire('PLAYER_LOGIN');s.window=s.named.NaowhForeverThreatMeter
    return s
end

do
 local s=fixture()
 check('disabled allocates no meter',not s.window)
 check('disabled registers no threat events',not s.listens('UNIT_THREAT_LIST_UPDATE'))
 s.set('fontSize',14);check('disabled does not queue updates',#s.timers==0)
end
do
 local s=fixture({enabled=true})
 check('target resolves',s.readMob=='target')
 check('pull line sorts before tank',s.bars()[1].name.text=='Pull Aggro')
 check('pull line does not consume a rank',s.bar('Tank').rank.text=='1')
 check('player percent uses pull threshold',s.bar('You').percent.text=='82%')
 s.set('percentMode','tank');check('tank-relative percent is distinct',s.bar('You').percent.text=='90%')
 check('pet inherits owner class icon',s.bar('Pet').icon.texture:find('PALADIN',1,true)~=nil)
 check('pet icon is desaturated',s.bar('Pet').icon.desaturated)
 s.set('ignorePets',true);check('pet filter removes row',not s.bar('Pet'))
 s.set('showValue',false);check('value column hides independently',s.bar('You').value.text=='')
 s.set('showPercent',false);check('percent column hides independently',s.bar('You').percent.text=='')
 s.set('focusEnabled',true);s.set('source','focus');check('focus source selected',s.readMob=='focus')
 s.units.focus.hostile=false;s.units.focustarget={name='Tank target',guid='mob-c',hostile=true};s.combat=true
 s.fire('UNIT_TARGET','focus');s.advance(0.21)
 check('friendly focus follows its target',s.readMob=='focustarget')
 check('derived source starts follow ticker',#s.tickers>0 and not s.tickers[#s.tickers].cancelled)
 s.set('enabled',false);check('disable cancels follow ticker',s.tickers[#s.tickers].cancelled)
 check('disable hides meter',not s.window.shown)
 check('disable unregisters threat events',not s.listens('UNIT_THREAT_LIST_UPDATE'))
end
do
 local s=fixture({enabled=true,warnSound=true,warnSoundKey='test'})
 check('threshold warns once',s.sounds==1)
 s.fire('UNIT_THREAT_LIST_UPDATE','target');s.advance(0.21);check('same target does not repeat',s.sounds==1)
 s.units.target.guid='new-mob';s.fire('PLAYER_TARGET_CHANGED');s.advance(0.21)
 check('new target rearms warning',s.sounds==2)
 s.units.player.threat[3]=50;s.fire('UNIT_THREAT_LIST_UPDATE','target');s.advance(0.21)
 s.units.player.threat[3]=85;s.fire('UNIT_THREAT_LIST_UPDATE','target');s.advance(0.21)
 check('dropping below threshold rearms warning',s.sounds==3)
 s.role='TANK';s.units.target.guid='third-mob';s.fire('PLAYER_TARGET_CHANGED');s.advance(0.21)
 check('tank role suppresses warning',s.sounds==3)
end
do
 local s=fixture({enabled=true});local reads=s.reads
 s.secret=true;s.fire('UNIT_THREAT_LIST_UPDATE','target');s.advance(0.21)
 check('secret threat values are read without error',s.reads>reads)
 check('restricted data hides when empty',not s.window.shown)
 s.set('onlyWithThreat',false);check('empty window can remain visible',s.window.shown and s.window.empty.shown)
 s.units.target=nil;s.fire('PLAYER_TARGET_CHANGED');s.advance(0.21)
 check('no mob unregisters threat events',not s.listens('UNIT_THREAT_LIST_UPDATE'))
 s.set('visibility','combat');check('combat visibility hides idle window',not s.window.shown)
 s.set('visibility','group');s.group=false;s.fire('GROUP_ROSTER_UPDATE');s.advance(0.21)
 check('group visibility hides solo window',not s.window.shown)
end
do
 local s=fixture({enabled=true,height=120,pullBar=false})
 check('fixed height limits visible rows',#s.bars()==1)
 local first=s.bars()[1].name.text;s.window.scripts.OnMouseWheel(s.window,-1)
 check('mouse wheel scrolls to next entry',s.bars()[1].name.text~=first)
 s.units.target.guid='new';s.fire('PLAYER_TARGET_CHANGED');s.advance(0.21)
 check('target switch resets scroll',s.bars()[1].name.text==first)
 local downY=s.bars()[1].point[5]
 s.set('statusPos','top');check('status line moves under the title bar',s.window.footer.point[1]=='TOPRIGHT')
 check('rows start below a top status line',s.bars()[1].point[5]==downY-24)
 check('locked grip hides with a top status line',not s.window.grip.shown)
 s.set('locked',false);check('unlocked grip shows with a top status line',s.window.grip.shown)
 s.set('locked',true)
 s.set('statusPos','bottom');check('status line returns to the bottom',s.window.footer.point[1]=='BOTTOMRIGHT')
 s.set('growUp',true);check('grow up anchors rows above footer',s.bars()[1].point[1]=='BOTTOMLEFT')
 s.ns.PreviewThreatMeter();check('preview displays synthetic title',s.window.header.text.text=='Training Dummy')
 s.advance(10);check('preview returns to live target',s.window.header.text.text=='Target')
 s.fire('UNIT_THREAT_LIST_UPDATE','target');s.set('enabled',false);s.advance(1)
 check('stale queued update cannot reshow disabled meter',not s.window.shown)
end
do
 local s=fixture({enabled=true})
 s.window.grip.scripts.OnMouseDown(s.window.grip,'LeftButton')
 check('locked window cannot resize',s.window.sizing~=true)
 s.set('locked',false)
 s.window.grip.scripts.OnMouseDown(s.window.grip,'LeftButton')
 check('unlocked window starts resizing',s.window.sizing==true)
 local oldHeight=s.bar('You'):GetHeight()
 local oldFont=s.bar('You').name.fontSize
 local readsBeforeResize=s.reads
 s.window:SetSize(350,310)
 s.window.scripts.OnSizeChanged(s.window)
 check('resizing reuses collected threat',s.reads==readsBeforeResize)
 check('bars grow during drag',s.bar('You'):GetHeight()>oldHeight)
 check('text grows during drag',s.bar('You').name.fontSize>oldFont)
 s.window.grip.scripts.OnMouseUp(s.window.grip)
 s.advance(0.21)
 check('resize saves dimensions',s.settings.width==350 and s.settings.height==310)
 check('resize saves position',s.settings.threatPos.point=='TOPLEFT')
 local large=s.settings.barHeight
 check('resize persists larger bars',large>oldHeight)
 s.window.grip.scripts.OnMouseDown(s.window.grip,'LeftButton')
 s.window:SetSize(280,240);s.window.scripts.OnSizeChanged(s.window)
 check('bars shrink during drag',s.bar('You'):GetHeight()<large)
 s.window.grip.scripts.OnMouseUp(s.window.grip);s.advance(0.21)
 check('resize back restores bar height',math.abs(s.settings.barHeight-oldHeight)<0.001)
 s.combat=true
 s.window.grip.scripts.OnMouseDown(s.window.grip,'LeftButton')
 check('combat prevents resizing',s.window.sizing~=true)
end
do
 local s=fixture({enabled=true,width=240,barHeight=72,fontSize=24,height=400})
 local row=s.bar('You')
 check('large row icons stay compact',row.icon.w==32)
 check('narrow window reduces rendered font',row.name.fontSize<24)
 local nameSpace=row.w-16-18-38-5-99*row.name.fontSize/12
 check('narrow window reserves readable names',nameSpace>=47.99)
 check('render fit preserves font preference',s.settings.fontSize==24)
end
do
 -- With Custom Colors off the window paints exactly the surfaces it always did.
 local s=fixture({enabled=true})
 local function solid(r,g,b) for _,f in ipairs(s.frames) do local sd=rawget(f,'solid'); local c=sd and sd.color
     if c and c.r==r and c.g==g and c.b==b and sd.alpha==1 then return true end end end
 local function edge(r,g,b) for _,f in ipairs(s.frames) do local c=rawget(f,'edge')
     if c and c.r==r and c.g==g and c.b==b then return true end end end
 local function rowBg(r,g,b) for _,f in ipairs(s.frames) do local c=rawget(f,'colorTexture')
     if c and c[1]==r and c[2]==g and c[3]==b and c[4]==1 then return true end end end
 check('window background is unchanged',solid(0.025,0.04,0.055))
 check('header background is unchanged',solid(0.04,0.075,0.095))
 check('window border is unchanged',edge(0.10,0.19,0.24))
 check('row background is unchanged',rowBg(0.065,0.085,0.105))
end
print(checks..' threat-meter checks passed')
