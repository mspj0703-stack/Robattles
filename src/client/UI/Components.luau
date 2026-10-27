--!nonstrict
local TweenService = game:GetService("TweenService")
local T = require(script.Parent.Tokens)
local C = {}
function C.new(kind, parent, props)
	local obj = Instance.new(kind)
	for k, v in props or {} do obj[k] = v end
	obj.Parent = parent
	return obj
end
function C.outline(obj, color, width)
	C.new("UIStroke", obj, {Color = color or T.Outline, Thickness = width or 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border})
	C.new("UICorner", obj, {CornerRadius = UDim.new(0, 5)})
end
function C.panel(parent, name, x, y, w, h, color)
	local f = C.new("Frame", parent, {Name = name, Position = UDim2.fromOffset(x,y), Size = UDim2.fromOffset(w,h), BackgroundColor3 = color or T.Panel, BorderSizePixel = 0})
	C.outline(f)
	return f
end
function C.text(parent, name, text, x,y,w,h,size,color)
	return C.new("TextLabel", parent, {Name=name, Text=text, Position=UDim2.fromOffset(x,y), Size=UDim2.fromOffset(w,h), BackgroundTransparency=1,
		TextColor3=color or T.Text, Font=T.BodyFont, TextSize=size or 18, TextWrapped=true, TextXAlignment=Enum.TextXAlignment.Left})
end
function C.button(parent, name, text, x,y,w,h, callback, color)
	local b = C.new("TextButton", parent, {Name=name, Text=text, Position=UDim2.fromOffset(x,y), Size=UDim2.fromOffset(w,h), BackgroundColor3=color or T.Action,
		TextColor3=T.Outline, Font=T.Font, TextSize=20, AutoButtonColor=false, BorderSizePixel=0, TextWrapped=true})
	C.outline(b)
	local scale = C.new("UIScale", b, {Scale=1})
	local tween
	local function animate(v)
		if tween then tween:Cancel() end
		tween = TweenService:Create(scale, TweenInfo.new(0.09), {Scale=v})
		tween:Play()
	end
	b.MouseEnter:Connect(function() animate(1.025) end)
	b.MouseLeave:Connect(function() animate(1) end)
	b.MouseButton1Down:Connect(function() animate(0.97) end)
	b.MouseButton1Up:Connect(function() animate(1) end)
	b.Activated:Connect(callback)
	return b
end
function C.scroll(parent,name,x,y,w,h)
	local f = C.new("ScrollingFrame",parent,{Name=name,Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h),BackgroundTransparency=1,
		BorderSizePixel=0,ScrollBarThickness=6,ScrollBarImageColor3=T.Action,CanvasSize=UDim2.new(),AutomaticCanvasSize=Enum.AutomaticSize.Y,ScrollingDirection=Enum.ScrollingDirection.Y})
	return f
end
function C.bar(parent,name,x,y,w,h,color)
	local track=C.panel(parent,name,x,y,w,h,T.Outline)
	local fill=C.new("Frame",track,{Name="Fill",Size=UDim2.fromScale(0,1),BackgroundColor3=color,BorderSizePixel=0})
	C.new("UICorner",fill,{CornerRadius=UDim.new(0,3)})
	return fill
end
function C.set(label, text)
	if label.Text ~= text then label.Text=text end
end
return C
