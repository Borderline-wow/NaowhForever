local f = assert(io.open(arg[1], "rb"))
local source = f:read("*a"); f:close()
local chunk = assert(source:match("(local launcherEvents = CreateFrame.*)"))
for _, saved in ipairs({{}, {minimap={minimapPos=47,hide=true}}}) do
    local event, object, registered, clicked, opened
    local modules = {}
    local original = saved.minimap
    local ns = { AccountSettings=function() return saved end, L=function(t) return t end,
        ToggleOptionsWindow=function() clicked=true end }
    local frame = {
        SetScript=function(_,_,fn) event=fn end,
        RegisterEvent=function(_,name) assert(name=="PLAYER_LOGIN" and event) end,
        UnregisterEvent=function(_,name) assert(name=="PLAYER_LOGIN") end,
    }
    local libs = {
        ["LibDataBroker-1.1"]={NewDataObject=function(_,name,data)
            if name~="NaowhForever" then modules[name]={data=data}; return data end
            object=data; return data end},
        ["LibDBIcon-1.0"]={Register=function(_,name,data,db)
            if name~="NaowhForever" then assert(modules[name].data==data); modules[name].db=db; return end
            assert(data==object and db==saved.minimap)
            registered=true end},
    }
    local dq = { name="Dungeon Quests", command="dq", short="DQ", micro=true, icon="dq" }
    local gear = { name="Gear Sets", command="gear", short="Gear", icon="gear" }
    local env = setmetatable({ns=ns,CreateFrame=function() return frame end,
        LibStub=function(name) return assert(libs[name]) end, hooksecurefunc=function() end,
        MODULES={ {name="QoL"}, dq, gear },
        MinimapButtonOn=function(mod) return mod.micro==true end,
        ToggleModuleWindow=function(mod) opened=mod end}, {__index=_G})
    local launcher = assert(loadstring(chunk, "launcher")); setfenv(launcher, env); launcher()
    assert(not registered)
    event(frame)
    assert(registered and object.type=="launcher")
    if original then assert(saved.minimap==original and original.minimapPos==47 and original.hide)
    else assert(saved.minimap.minimapPos==220) end
    object.OnClick(); assert(clicked)
    local lines=0
    object.OnTooltipShow({AddLine=function(_,text) assert(type(text)=="string"); lines=lines+1 end})
    assert(lines==3)
    -- One launcher per module with a command, hidden while its minimap switch is off.
    assert(modules.NaowhForeverDQ and modules.NaowhForeverGear and not modules.NaowhForeverQoL)
    assert(modules.NaowhForeverDQ.data.icon=="dq" and modules.NaowhForeverDQ.db.hide==false)
    assert(modules.NaowhForeverGear.db.hide==true)
    assert(saved.moduleButtons["Dungeon Quests"]==modules.NaowhForeverDQ.db)
    modules.NaowhForeverGear.data.OnClick(); assert(opened==gear)
end
print("PASS: login registration, fresh/saved position, click and tooltip, module launchers")
