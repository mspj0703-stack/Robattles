--!nonstrict
-- Roblox 전용(Studio 미검증): 스코어보드/결과표. 순위·정렬·동점 처리는 전부 서버 행(rank)을 따른다.
-- 12행을 미리 만들어 재사용하고, 서버가 더 많은 행을 보내면 풀을 늘려 스크롤로 보여준다.
local Players=game:GetService("Players")
local C=require(script.Parent.UI.Components)
local T=require(script.Parent.UI.Tokens)
local Board={}; Board.__index=Board
local ROW_H,ROW_STEP=32,38
local function makeRow(parent,i)
	local row=C.panel(parent,"Row"..i,2,(i-1)*ROW_STEP,676,ROW_H,i%2==0 and T.Surface or T.Secondary)
	local cell={root=row,rank=C.text(row,"Rank",tostring(i),10,0,52,ROW_H,18),name=C.text(row,"Player","",75,0,398,ROW_H,17),kills=C.text(row,"KO","",492,0,80,ROW_H,18),deaths=C.text(row,"Deaths","",578,0,85,ROW_H,18)}
	cell.name.TextTruncate=Enum.TextTruncate.AtEnd; cell.name.TextWrapped=false
	return cell
end
function Board.new(parent)
	local root=C.panel(parent,"Scoreboard",270,64,740,592)
	local self=setmetatable({root=root,rows={},cells={}},Board)
	self.title=C.text(root,"Title","SCOREBOARD",24,16,690,36,30,T.Action)
	C.text(root,"Head","RANK        PLAYER                                         KO       DEATHS",24,62,690,32,17,T.Muted)
	self.list=C.scroll(root,"Rows",22,101,696,478)
	self.list.AutomaticCanvasSize=Enum.AutomaticSize.None
	for i=1,12 do self.cells[i]=makeRow(self.list,i) end
	self.list.CanvasSize=UDim2.fromOffset(0,12*ROW_STEP)
	root.Visible=false
	return self
end
function Board:setRows(rows)
	self.rows=rows
	for i=#self.cells+1,#rows do self.cells[i]=makeRow(self.list,i) end -- only grows when the server reports more than 12 rows
	self.list.CanvasSize=UDim2.fromOffset(0,math.max(12,#rows)*ROW_STEP)
	local me=Players.LocalPlayer.UserId
	for i,cell in self.cells do
		local r=rows[i]; cell.root.Visible=r~=nil
		if r then
			local mine=r.id==me
			C.set(cell.rank,tostring(r.rank or i))
			C.set(cell.name,(mine and "YOU · " or "")..tostring(r.name)..(r.connected==false and "  (퇴장)" or ""))
			C.set(cell.kills,tostring(r.kills)); C.set(cell.deaths,tostring(r.deaths))
			cell.root.BackgroundColor3=mine and T.Action or (i%2==0 and T.Surface or T.Secondary)
			local color=mine and T.Outline or (r.connected==false and T.Muted or T.Text)
			for _,label in {cell.rank,cell.name,cell.kills,cell.deaths} do label.TextColor3=color end
		end
	end
end
function Board:setVisible(v) self.root.Visible=v end
return Board
