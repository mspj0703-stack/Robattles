-- Restricted GUI API mock: catches runtime construction/callback errors only.
-- This is NOT Roblox Studio, an engine emulator or visual verification.
local M={created=0,time=100}
local function signal()
	local s={listeners={}}
	function s:Connect(fn) local c={fn=fn,active=true}; function c:Disconnect() self.active=false end; table.insert(self.listeners,c); return c end
	function s:Fire(...) for _,c in self.listeners do if c.active then c.fn(...) end end end
	return s
end
local enum=setmetatable({},{__index=function(t,k)
	local group=setmetatable({},{__index=function(g,name) local e={Name=name}; rawset(g,name,e);return e end});rawset(t,k,group);return group
end})
M.Enum=enum
M.Color3={fromHex=function(hex) return {hex=hex} end,fromRGB=function(...) return {...} end,new=function(...) return {...} end}
M.Vector2={new=function(x,y) return {X=x,Y=y} end}
M.Vector3={new=function(x,y,z) return {X=x,Y=y,Z=z} end}
M.UDim={new=function(s,o) return {Scale=s,Offset=o} end}
M.UDim2={new=function(xs,xo,ys,yo) return {X={Scale=xs or 0,Offset=xo or 0},Y={Scale=ys or 0,Offset=yo or 0}} end}
M.UDim2.fromOffset=function(x,y) return M.UDim2.new(0,x,0,y) end
M.UDim2.fromScale=function(x,y) return M.UDim2.new(x,0,y,0) end
M.CFrame={new=function(...) return {...} end,lookAt=function(...) return {...} end}
M.TweenInfo={new=function(...) return {...} end}
local methods={}
function methods:GetChildren() return table.clone(self._children) end
function methods:FindFirstChild(name) for _,v in self._children do if v.Name==name then return v end end end
function methods:WaitForChild(name) return assert(self:FindFirstChild(name),"Mock missing child "..name) end
function methods:GetPropertyChangedSignal(key) if not self._signals[key] then self._signals[key]=signal() end;return self._signals[key] end
function methods:Destroy() self._props.Destroyed=true;for _,v in self._children do v:Destroy() end; for _,s in self._events do for _,c in s.listeners do c:Disconnect() end end end
M.Instance={}
function M.Instance.new(kind)
	M.created+=1
	local events={};for _,name in {"MouseEnter","MouseLeave","MouseButton1Down","MouseButton1Up","Activated","Destroying"} do events[name]=signal() end
	local obj=setmetatable({_props={ClassName=kind,Name=kind,Visible=true,Text="",AbsoluteSize={X=1280,Y=720}},_children={},_events=events,_signals={}}, {
		__index=function(t,k) return methods[k] or t._events[k] or t._props[k] end,
		__newindex=function(t,k,v)
			if k=="Text" then assert(type(v)=="string","Text must be string: "..tostring(v)) end
			if k=="Parent" and v then table.insert(v._children,t) end
			t._props[k]=v
		end,
	})
	return obj
end
local pg=M.Instance.new("PlayerGui")
local localPlayer={UserId=7,DisplayName="Me"}
function localPlayer:WaitForChild(name) assert(name=="PlayerGui"); return pg end
local others={{UserId=7,DisplayName="Me"},{UserId=8,DisplayName="Enemy"}}
local players={LocalPlayer=localPlayer,PlayerRemoving=signal()}
function players:GetPlayers() return others end
function players:GetPlayerByUserId(id) for _,p in others do if p.UserId==id then return p end end end
local starter={enabled=true}
function starter:GetCoreGuiEnabled() return self.enabled end
function starter:SetCoreGuiEnabled(_,v) self.enabled=v end
local cas={bound={}}
function cas:BindActionAtPriority(name,callback) self.bound[name]=callback end
function cas:UnbindAction(name) self.bound[name]=nil end
local tween={}
function tween:Create(obj,info,goal) return {Play=function() for k,v in goal do obj[k]=v end end,Cancel=function() end} end
M.services={Players=players,StarterGui=starter,SoundService=M.Instance.new("SoundService"),ContextActionService=cas,TweenService=tween}
M.game={GetService=function(_,name) return assert(M.services[name],"Mock missing service "..name) end}
M.workspace={GetServerTimeNow=function() return M.time end}
M.playerGui=pg
return M
