--!nonstrict
-- Cancellation boundary for skill timers/casts and async engine work.
-- A token is server-local. Never accept generation/connection values from clients.
local Scope={};Scope.__index=Scope
function Scope.new() return setmetatable({epoch=0,connections={},nextConnection=0,cleanups={},errors={}},Scope) end
function Scope:join(id)
	self.nextConnection+=1;self.connections[id]=self.nextConnection;return self.nextConnection
end
function Scope:capture(id) return {epoch=self.epoch,id=id,connection=id~=nil and self.connections[id] or nil} end
function Scope:valid(token)
	return token~=nil and token.epoch==self.epoch and (token.id==nil or token.connection~=nil and self.connections[token.id]==token.connection)
end
function Scope:guard(token,fn)
	return function(...) if not self:valid(token) then return false,"stale_match_work" end;return fn(...) end
end
function Scope:track(id,cancel)
	local item={id=id,cancel=cancel,active=true};table.insert(self.cleanups,item)
	return function() item.active=false end
end
function Scope:_cancel(item)
	if not item.active then return end;item.active=false
	local ok,err=pcall(item.cancel)
	if not ok then table.insert(self.errors,tostring(err)) end
end
function Scope:leave(id)
	self.connections[id]=nil
	local keep={};for _,item in self.cleanups do if item.id==id then self:_cancel(item) elseif item.active then table.insert(keep,item) end end;self.cleanups=keep
end
function Scope:invalidate()
	self.epoch+=1
	local old=self.cleanups;self.cleanups={}
	for _,item in old do self:_cancel(item) end
end
return Scope
