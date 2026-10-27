--!nonstrict
-- Safe local ViewportFrame scene: anchored blocks, no scripts or external assets.
local C=require(script.Parent.Components)
local T=require(script.Parent.Tokens)
local Preview={}
local function part(world,name,size,pos,color)
	return C.new("Part",world,{Name=name,Size=size,CFrame=CFrame.new(pos),Color=color,Anchored=true,CanCollide=false,CanTouch=false,CanQuery=false,Material=Enum.Material.SmoothPlastic})
end
function Preview.new(parent,x,y,w,h,characterId)
	local viewport=C.new("ViewportFrame",parent,{Name="ArcadePreview",Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h),BackgroundColor3=T.Secondary,Ambient=Color3.fromRGB(180,180,180),LightColor=Color3.new(1,1,1)})
	C.outline(viewport)
	local world=C.new("WorldModel",viewport,{Name="PreviewWorld"})
	local camera=C.new("Camera",viewport,{CFrame=CFrame.lookAt(Vector3.new(11,9,16),Vector3.new(0,2,0)),FieldOfView=38})
	viewport.CurrentCamera=camera
	part(world,"Platform",Vector3.new(12,1,10),Vector3.new(0,-0.5,0),T.Panel)
	for i=1,4 do
		part(world,"Brick"..i,Vector3.new(2,1+i%2,2),Vector3.new(-6+i*2.5,i%2*0.5,-3),i%2==0 and T.Action or T.Danger)
	end
	local body={}
	for _,d in {{"Torso",Vector3.new(2,2,1),Vector3.new(0,3,0)},{"Head",Vector3.new(2,1,1),Vector3.new(0,4.5,0)},{"Left Arm",Vector3.new(1,2,1),Vector3.new(-1.5,3,0)},{"Right Arm",Vector3.new(1,2,1),Vector3.new(1.5,3,0)},{"Left Leg",Vector3.new(1,2,1),Vector3.new(-0.5,1,0)},{"Right Leg",Vector3.new(1,2,1),Vector3.new(0.5,1,0)}} do
		body[d[1]]=part(world,d[1],d[2],d[3],d[1]=="Head" and T.Action or T.Themes[characterId] or T.Action)
	end
	return {root=viewport,setCharacter=function(_,id) for name,p in body do if name~="Head" then p.Color=T.Themes[id] or T.Action end end end}
end
-- Isolate preview construction failures: selection must remain available without 3D.
function Preview.safeNew(parent,x,y,w,h,id)
	local holder=C.new("Frame",parent,{Name="PreviewHost",Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h),BackgroundTransparency=1})
	local ok,view=pcall(Preview.new,holder,0,0,w,h,id)
	if ok then
		return {root=holder,setCharacter=function(_,nextId) view:setCharacter(nextId) end}
	end
	for _,child in holder:GetChildren() do child:Destroy() end
	local panel=C.panel(holder,"StaticPreview",0,0,w,h,T.Secondary)
	local pieces={}
	for _,d in {{0.42,0.16,0.16,0.14},{0.35,0.32,0.30,0.27},{0.20,0.32,0.12,0.27},{0.68,0.32,0.12,0.27},{0.35,0.62,0.13,0.23},{0.52,0.62,0.13,0.23}} do
		table.insert(pieces,C.panel(panel,"Silhouette",w*d[1],h*d[2],w*d[3],h*d[4],T.Themes[id] or T.Action))
	end
	return {root=holder,setCharacter=function(_,nextId) for _,piece in pieces do piece.BackgroundColor3=T.Themes[nextId] or T.Action end end}
end
return Preview
