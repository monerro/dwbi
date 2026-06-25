local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local mouse = player:GetMouse()
local camera = workspace.CurrentCamera

----------------------------------------------------------------------
-- CONFIG
----------------------------------------------------------------------
local cfg = {
	pixelMaxSpeed   = 40,
	textureMaxSpeed = 40,
	bhopBoost       = 3.0,
	jumpBugPower    = 80,
	longJumpPower   = 90,
	miniJumpPower   = 20,
	aimbotFOV       = 60,
	aimbotSmooth    = 6,
	aimbotButton    = Enum.UserInputType.MouseButton2,
	aimbotKeybind   = "MouseButton2",
	fogEnd          = 200,
	blurSize        = 10,
	spinSpeed       = 720,
	spinMode        = "Both",
	noSpreadMin     = 5,
	noSpreadMax     = 15,
}

local keybindOverrides = {
	AutoBhop   = { key = Enum.KeyCode.Space, mode = "auto" },
	PixelSurf  = { key = nil, mode = "auto" },
	TextureBug = { key = nil, mode = "auto" },
	MiniJump   = { key = Enum.KeyCode.C, mode = "hold" },
	LongJump   = { key = Enum.KeyCode.E, mode = "toggle" },
	JumpBug    = { key = Enum.KeyCode.Q, mode = "hold" },
}

local function getKeyNameFromEnum(keyEnum)
	if not keyEnum then return "auto" end
	return keyEnum.Name
end

-- NO-SPREAD SYSTEM
local noSpreadActive = false
local currentSpreadFolder = nil
local originalSpreadValuesNS = {}

local function getEquippedGunNameNS()
	local char = player.Character
	if not char then return nil end
	local gun = char:FindFirstChild("Gun")
	return gun and gun:GetAttribute("GunName")
end

local function getCurrentSpreadFolder()
	local gunName = getEquippedGunNameNS()
	if not gunName then return nil end
	local weapons = ReplicatedStorage:FindFirstChild("Weapons")
	if not weapons then return nil end
	local gunFolder = weapons:FindFirstChild(gunName)
	if not gunFolder then return nil end
	return gunFolder:FindFirstChild("Spread")
end

local function saveOriginalsNS(spreadFolder)
	if not spreadFolder then return end
	local gunName = getEquippedGunNameNS()
	if not gunName then return end
	if originalSpreadValuesNS[gunName] then return end
	originalSpreadValuesNS[gunName] = {}
	for _, v in ipairs(spreadFolder:GetChildren()) do
		if v:IsA("NumberValue") or v:IsA("IntValue") or v:IsA("FloatValue") then
			originalSpreadValuesNS[gunName][v] = v.Value
		end
	end
end

local function applyLowSpread(spreadFolder)
	if not spreadFolder then return end
	for _, v in ipairs(spreadFolder:GetChildren()) do
		if v:IsA("NumberValue") or v:IsA("IntValue") or v:IsA("FloatValue") then
			v.Value = math.random(cfg.noSpreadMin, cfg.noSpreadMax) / 100
		end
	end
end

local function restoreSpreadNS(spreadFolder)
	local gunName = getEquippedGunNameNS()
	if not gunName then return end
	if not originalSpreadValuesNS[gunName] then return end
	for v, originalVal in pairs(originalSpreadValuesNS[gunName]) do
		if v and v.Parent then v.Value = originalVal end
	end
end

local function toggleNoSpreadFunc(enabled)
	noSpreadActive = enabled
	if enabled then
		currentSpreadFolder = getCurrentSpreadFolder()
		if currentSpreadFolder then saveOriginalsNS(currentSpreadFolder) end
	else
		if currentSpreadFolder then restoreSpreadNS(currentSpreadFolder) end
		currentSpreadFolder = nil
	end
end

----------------------------------------------------------------------
-- ESP CONFIG
----------------------------------------------------------------------
local ESP_CFG = {
	skeleton_color          = Color3.fromRGB(0, 255, 0),
	crouch_color            = Color3.fromRGB(255, 0, 0),
	skeleton_thickness      = 2,
	skeleton_transparency   = 1,
	crouch_detection        = true,
	crouch_height_threshold = 2,
	box_enabled             = true,
	box_color               = Color3.fromRGB(255, 255, 255),
	box_thickness           = 2,
	box_filled              = false,
	box_fill_color          = Color3.fromRGB(255, 255, 255),
	box_fill_transparency   = 0.2,
	healthbar_enabled       = true,
	healthbar_color_high    = Color3.fromRGB(0, 255, 0),
	healthbar_color_low     = Color3.fromRGB(255, 0, 0),
	name_enabled            = true,
	name_color              = Color3.fromRGB(255, 255, 255),
	name_size               = 14,
	name_outline            = true,
	distance_enabled        = true,
	distance_color          = Color3.fromRGB(200, 200, 200),
	distance_size           = 12,
	tracer_enabled          = false,
	tracer_color            = Color3.fromRGB(255, 255, 255),
	tracer_thickness        = 1,
	tracer_transparency     = 1,
	tracer_from             = "Bottom",
}

----------------------------------------------------------------------
-- FEATURE STATE
----------------------------------------------------------------------
local features = {
	PixelSurf  = { enabled=false, conn=nil, surfing=false, glideDir=nil, glideSpeed=0 },
	TextureBug = { enabled=false, conn=nil, surfing=false, glideDir=nil, glideSpeed=0 },
	AutoBhop   = { enabled=false, conn=nil },
	JumpBug    = { enabled=false, conn=nil },
	LongJump   = { enabled=false, conn=nil },
	MiniJump   = { enabled=false, conn=nil },
	FakeAimbot = { enabled=false, conn=nil },
	Spinbot    = { enabled=false, bodyConn=nil, headConn=nil },
}

local espEnabled      = false
local espConn         = nil
local espObjects      = {}
local crouching       = {}
local skinSelections  = {}
local skinOriginals   = {}
local skinConn        = nil
local hudRemoved      = false
local hiddenHudItems  = {}

----------------------------------------------------------------------
-- KEY INPUT HELPERS
----------------------------------------------------------------------
local function getKeyName(inputType)
	if inputType == Enum.UserInputType.MouseButton1 then return "MouseButton1" end
	if inputType == Enum.UserInputType.MouseButton2 then return "MouseButton2" end
	if inputType == Enum.UserInputType.MouseButton3 then return "MouseButton3" end
	if inputType == Enum.UserInputType.Keyboard    then return "Keyboard" end
	return "Unknown"
end

local function isMouseButton(inputType)
	return inputType == Enum.UserInputType.MouseButton1
		or inputType == Enum.UserInputType.MouseButton2
		or inputType == Enum.UserInputType.MouseButton3
end

local waitingForKeybind = false
local keybindCallback   = nil

local function startKeybindCapture(callback)
	waitingForKeybind = true
	keybindCallback   = callback
end

UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe then return end
	if waitingForKeybind and keybindCallback then
		local inputType = input.UserInputType
		if inputType == Enum.UserInputType.Keyboard then
			keybindCallback("Keyboard", input.KeyCode.Name, input.KeyCode)
		elseif isMouseButton(inputType) then
			keybindCallback("Mouse", getKeyName(inputType), inputType)
		end
		waitingForKeybind = false
		keybindCallback   = nil
	end
end)

local contextMenu = nil

local function createContextMenu(featureKey, currentKey, currentMode, position)
	if contextMenu then contextMenu:Destroy(); contextMenu = nil end

	contextMenu = Instance.new("Frame")
	contextMenu.Name = "ContextMenu"
	contextMenu.Size = UDim2.new(0, 180, 0, 0)
	contextMenu.AutomaticSize = Enum.AutomaticSize.Y
	contextMenu.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
	contextMenu.BorderSizePixel = 0
	contextMenu.ZIndex = 100
	contextMenu.Parent = screenGui

	local absX = position.X; local absY = position.Y
	local viewportSize = camera.ViewportSize
	if absX + 180 > viewportSize.X then absX = viewportSize.X - 180 end
	if absY + 200 > viewportSize.Y then absY = viewportSize.Y - 200 end
	contextMenu.Position = UDim2.new(0, absX, 0, absY)

	local menuLayout = Instance.new("UIListLayout")
	menuLayout.FillDirection = Enum.FillDirection.Vertical
	menuLayout.SortOrder = Enum.SortOrder.LayoutOrder
	menuLayout.Padding = UDim.new(0, 2)
	menuLayout.Parent = contextMenu

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 6); pad.PaddingBottom = UDim.new(0, 6)
	pad.PaddingLeft = UDim.new(0, 8); pad.PaddingRight = UDim.new(0, 8)
	pad.Parent = contextMenu

	local title = Instance.new("TextLabel")
	title.Text = "Keybind Settings"; title.Font = Enum.Font.GothamBold
	title.TextSize = 12; title.TextColor3 = Color3.fromRGB(240,240,240)
	title.BackgroundTransparency = 1; title.Size = UDim2.new(1,0,0,22)
	title.LayoutOrder = 0; title.Parent = contextMenu

	local divider = Instance.new("Frame")
	divider.Size = UDim2.new(1,-10,0,1); divider.Position = UDim2.new(0,5,0,0)
	divider.BackgroundColor3 = Color3.fromRGB(38,38,38); divider.BorderSizePixel = 0
	divider.LayoutOrder = 1; divider.Parent = contextMenu

	local keyRow = Instance.new("Frame"); keyRow.Size = UDim2.new(1,0,0,28); keyRow.BackgroundTransparency=1; keyRow.LayoutOrder=2; keyRow.Parent=contextMenu
	local keyLabel = Instance.new("TextLabel"); keyLabel.Text="Key:"; keyLabel.Font=Enum.Font.Gotham; keyLabel.TextSize=11; keyLabel.TextColor3=Color3.fromRGB(150,150,150); keyLabel.BackgroundTransparency=1; keyLabel.Size=UDim2.new(0.4,0,1,0); keyLabel.TextXAlignment=Enum.TextXAlignment.Left; keyLabel.Parent=keyRow
	local keyButton = Instance.new("TextButton"); keyButton.Text=currentKey and getKeyNameFromEnum(currentKey) or "auto"; keyButton.Font=Enum.Font.Gotham; keyButton.TextSize=11; keyButton.TextColor3=Color3.fromRGB(240,240,240); keyButton.BackgroundColor3=Color3.fromRGB(18,18,18); keyButton.Size=UDim2.new(0.55,0,1,0); keyButton.Position=UDim2.new(0.45,0,0,0); keyButton.Parent=keyRow
	Instance.new("UICorner",keyButton).CornerRadius=UDim.new(0,4)

	local modeRow = Instance.new("Frame"); modeRow.Size=UDim2.new(1,0,0,28); modeRow.BackgroundTransparency=1; modeRow.LayoutOrder=3; modeRow.Parent=contextMenu
	local modeLabel = Instance.new("TextLabel"); modeLabel.Text="Mode:"; modeLabel.Font=Enum.Font.Gotham; modeLabel.TextSize=11; modeLabel.TextColor3=Color3.fromRGB(150,150,150); modeLabel.BackgroundTransparency=1; modeLabel.Size=UDim2.new(0.4,0,1,0); modeLabel.TextXAlignment=Enum.TextXAlignment.Left; modeLabel.Parent=modeRow
	local modeDropdown = Instance.new("TextButton"); modeDropdown.Text=currentMode or "auto"; modeDropdown.Font=Enum.Font.Gotham; modeDropdown.TextSize=11; modeDropdown.TextColor3=Color3.fromRGB(240,240,240); modeDropdown.BackgroundColor3=Color3.fromRGB(18,18,18); modeDropdown.Size=UDim2.new(0.55,0,1,0); modeDropdown.Position=UDim2.new(0.45,0,0,0); modeDropdown.Parent=modeRow
	Instance.new("UICorner",modeDropdown).CornerRadius=UDim.new(0,4)

	local modeOptions = Instance.new("Frame"); modeOptions.Size=UDim2.new(0.55,0,0,0); modeOptions.AutomaticSize=Enum.AutomaticSize.Y; modeOptions.BackgroundColor3=Color3.fromRGB(13,13,13); modeOptions.BorderSizePixel=0; modeOptions.Position=UDim2.new(0.45,0,0,28); modeOptions.ZIndex=101; modeOptions.Visible=false; modeOptions.Parent=modeRow
	Instance.new("UICorner",modeOptions).CornerRadius=UDim.new(0,4)
	local modeList=Instance.new("UIListLayout"); modeList.FillDirection=Enum.FillDirection.Vertical; modeList.Padding=UDim.new(0,1); modeList.Parent=modeOptions

	local override = keybindOverrides[featureKey]
	for _, mode in ipairs({"auto","toggle","hold"}) do
		local opt=Instance.new("TextButton"); opt.Text=mode; opt.Font=Enum.Font.Gotham; opt.TextSize=11
		opt.TextColor3=mode==currentMode and Color3.fromRGB(48,244,38) or Color3.fromRGB(150,150,150)
		opt.BackgroundColor3=Color3.fromRGB(18,18,18); opt.Size=UDim2.new(1,0,0,22); opt.ZIndex=102; opt.Parent=modeOptions
		opt.MouseButton1Click:Connect(function()
			if override then override.mode=mode end
			modeDropdown.Text=mode; modeOptions.Visible=false
			if contextMenu then contextMenu:Destroy(); contextMenu=nil end
		end)
	end

	modeDropdown.MouseButton1Click:Connect(function() modeOptions.Visible=not modeOptions.Visible end)

	keyButton.MouseButton1Click:Connect(function()
		keyButton.Text="Press key..."; keyButton.TextColor3=Color3.fromRGB(48,244,38)
		startKeybindCapture(function(inputType, displayName, enumValue)
			keyButton.Text=displayName; keyButton.TextColor3=Color3.fromRGB(240,240,240)
			if override then override.key=enumValue end
			if contextMenu then contextMenu:Destroy(); contextMenu=nil end
		end)
		task.delay(5, function()
			if keyButton.Text=="Press key..." then
				keyButton.Text=currentKey and getKeyNameFromEnum(currentKey) or "auto"
				keyButton.TextColor3=Color3.fromRGB(240,240,240)
			end
		end)
	end)

	local connection
	connection = UserInputService.InputBegan:Connect(function(input, gpe)
		if gpe then return end
		if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.MouseButton2 then
			local mousePos=Vector2.new(input.Position.X, input.Position.Y)
			if contextMenu and contextMenu.Parent then
				local absPos=contextMenu.AbsolutePosition; local size=contextMenu.AbsoluteSize
				if mousePos.X<absPos.X or mousePos.X>absPos.X+size.X or mousePos.Y<absPos.Y or mousePos.Y>absPos.Y+size.Y then
					if contextMenu then contextMenu:Destroy(); contextMenu=nil end
					connection:Disconnect()
				end
			end
		end
	end)
end

local function updateFeatureHint(featureKey)
	if activeCategory=="movement" then
		local sub=activeSub or "main"
		rebuildContent("movement", sub)
	end
end

----------------------------------------------------------------------
-- CHARACTER & MOVEMENT
----------------------------------------------------------------------
local character, humanoid, hrp
local function bindCharacter(char)
	character = char
	humanoid  = char:WaitForChild("Humanoid")
	hrp       = char:WaitForChild("HumanoidRootPart")
end
if player.Character then bindCharacter(player.Character) end
player.CharacterAdded:Connect(bindCharacter)

local WALL_RANGE  = 2.0
local W_ACCEL     = 14
local BASE_SPEED  = 40
local TRAIL_LIFE  = 1.8
local TRAIL_WIDTH = 0.06
local PARAMS = RaycastParams.new()
PARAMS.FilterType = Enum.RaycastFilterType.Exclude
local WALL_DIRS = {
	Vector3.new(1,0,0), Vector3.new(-1,0,0),
	Vector3.new(0,0,1), Vector3.new(0,0,-1),
	Vector3.new(1,0,1).Unit,  Vector3.new(-1,0,1).Unit,
	Vector3.new(1,0,-1).Unit, Vector3.new(-1,0,-1).Unit,
}

local function findWall(originOffset)
	PARAMS.FilterDescendantsInstances = {character}
	local up     = Vector3.new(0,1,0)
	local origin = hrp.Position + originOffset
	local vel    = hrp and hrp.AssemblyLinearVelocity or Vector3.zero
	local hVel   = Vector3.new(vel.X,0,vel.Z)
	for _, dir in ipairs(WALL_DIRS) do
		local hit = workspace:Raycast(origin, dir*WALL_RANGE, PARAMS)
		if not hit then continue end
		local n = hit.Normal
		if math.abs(n:Dot(up))>=0.43 then continue end
		local inst = hit.Instance
		if not inst:IsA("BasePart") then continue end
		if inst.Size.Y*0.5<2.0 then continue end
		if hVel.Magnitude>1 then if hVel.Unit:Dot(-n)<0.1 then continue end end
		return n
	end
	return nil
end

local trailFolder = Instance.new("Folder")
trailFolder.Name="DwbiTrail"; trailFolder.Parent=workspace
local segments = {}
local lastPos   = {PixelSurf=nil, TextureBug=nil}
local TRAIL_STEP = 1.2

local function spawnSegment(pos)
	local seg=Instance.new("Part"); seg.Anchored=true; seg.CanCollide=false; seg.CanQuery=false; seg.CastShadow=false
	seg.Size=Vector3.new(TRAIL_WIDTH,TRAIL_WIDTH,TRAIL_WIDTH); seg.CFrame=CFrame.new(pos); seg.Material=Enum.Material.Neon
	seg.Color=Color3.new(1,1,1); seg.Transparency=0; seg.Parent=trailFolder
	table.insert(segments,{part=seg,born=tick()})
end

local function updateTrail(pos, active, key)
	local now=tick()
	if active then
		if not lastPos[key] or (pos-lastPos[key]).Magnitude>=TRAIL_STEP then spawnSegment(pos); lastPos[key]=pos end
	else lastPos[key]=nil end
	local i=1
	while i<=#segments do
		local s=segments[i]; local age=now-s.born
		if age>=TRAIL_LIFE then s.part:Destroy(); table.remove(segments,i)
		else s.part.Transparency=age/TRAIL_LIFE; i=i+1 end
	end
end

local function makeSurf(key, originOffset, getMaxSpeed)
	local f=features[key]
	f.conn=RunService.Heartbeat:Connect(function(dt)
		if not hrp or not humanoid then return end
		local state=humanoid:GetState()
		local airborne=state==Enum.HumanoidStateType.Freefall or state==Enum.HumanoidStateType.Jumping
		if not airborne then f.surfing=false; f.glideDir=nil; f.glideSpeed=0; updateTrail(hrp.Position,false,key); return end
		local wNormal=findWall(originOffset)
		if not wNormal then f.surfing=false; f.glideDir=nil; f.glideSpeed=0; updateTrail(hrp.Position,false,key); return end
		if f.surfing and (UserInputService:IsKeyDown(Enum.KeyCode.A) or UserInputService:IsKeyDown(Enum.KeyCode.D) or UserInputService:IsKeyDown(Enum.KeyCode.Left) or UserInputService:IsKeyDown(Enum.KeyCode.Right)) then
			f.surfing=false; f.glideDir=nil; f.glideSpeed=0; updateTrail(hrp.Position,false,key); return
		end
		local maxSpd=getMaxSpeed()
		if not f.surfing then
			f.surfing=true
			local look=hrp.CFrame.LookVector
			local proj=look-wNormal*look:Dot(wNormal)
			proj=Vector3.new(proj.X,0,proj.Z)
			f.glideDir=proj.Magnitude>0.01 and proj.Unit or Vector3.new(-wNormal.Z,0,wNormal.X).Unit
			local vel=hrp.AssemblyLinearVelocity
			f.glideSpeed=math.min(math.max(Vector3.new(vel.X,0,vel.Z).Magnitude,BASE_SPEED),maxSpd)
		end
		f.glideSpeed=math.min(f.glideSpeed,maxSpd)
		if UserInputService:IsKeyDown(Enum.KeyCode.W) or UserInputService:IsKeyDown(Enum.KeyCode.Up) then
			f.glideSpeed=math.min(f.glideSpeed+W_ACCEL*dt,maxSpd)
		end
		hrp.AssemblyLinearVelocity=Vector3.new(f.glideDir.X*f.glideSpeed,0,f.glideDir.Z*f.glideSpeed)
		humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
		updateTrail(hrp.Position+originOffset,true,key)
	end)
end

local function bhop_start()
	features.AutoBhop.conn=RunService.RenderStepped:Connect(function()
		if not humanoid or not hrp then return end
		local override=keybindOverrides.AutoBhop
		local key=override and override.key or Enum.KeyCode.Space
		if not features.AutoBhop.enabled then return end
		if UserInputService:IsKeyDown(key) then
			if humanoid.FloorMaterial~=Enum.Material.Air then humanoid.Jump=true
			else local md=humanoid.MoveDirection; if md.Magnitude>0 then hrp.CFrame=hrp.CFrame+(md*cfg.bhopBoost) end end
		end
	end)
end

local function jumpbug_start()
	features.JumpBug.conn=humanoid.StateChanged:Connect(function(_,new)
		if new==Enum.HumanoidStateType.Jumping and UserInputService:IsKeyDown(Enum.KeyCode.Q) then
			task.defer(function() if hrp then local vel=hrp.AssemblyLinearVelocity; hrp.AssemblyLinearVelocity=Vector3.new(vel.X,vel.Y+cfg.jumpBugPower,vel.Z) end end)
		end
	end)
end

local lj_used=false
local function longjump_start()
	features.LongJump.conn=UserInputService.InputBegan:Connect(function(input,gpe)
		if gpe then return end
		if input.KeyCode~=Enum.KeyCode.E then return end
		if not humanoid or not hrp then return end
		if humanoid:GetState()~=Enum.HumanoidStateType.Running and humanoid:GetState()~=Enum.HumanoidStateType.RunningNoPhysics then return end
		if lj_used then return end
		lj_used=true
		local look=hrp.CFrame.LookVector; local vel=hrp.AssemblyLinearVelocity
		hrp.AssemblyLinearVelocity=Vector3.new(look.X*cfg.longJumpPower,vel.Y+25,look.Z*cfg.longJumpPower)
		humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
		local landConn; landConn=humanoid.StateChanged:Connect(function(_,new)
			if new==Enum.HumanoidStateType.Landed or new==Enum.HumanoidStateType.Running then lj_used=false; landConn:Disconnect() end
		end)
	end)
end

local mj_cd=0
local function minijump_start()
	features.MiniJump.conn=UserInputService.InputBegan:Connect(function(input,gpe)
		if gpe then return end
		if input.KeyCode~=Enum.KeyCode.C then return end
		if not humanoid or not hrp then return end
		local now=tick(); if now-mj_cd<0.3 then return end; mj_cd=now
		if humanoid:GetState()~=Enum.HumanoidStateType.Running and humanoid:GetState()~=Enum.HumanoidStateType.RunningNoPhysics then return end
		local vel=hrp.AssemblyLinearVelocity; hrp.AssemblyLinearVelocity=Vector3.new(vel.X,cfg.miniJumpPower,vel.Z)
		humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	end)
end

----------------------------------------------------------------------
-- SPINBOT
----------------------------------------------------------------------
local spinAngle   = 0
local headTimer   = 0
local HEAD_PERIOD = 0.5

local function getNeck()
	if not character then return nil end
	local upperTorso = character:FindFirstChild("UpperTorso")
	if upperTorso then
		local neck = upperTorso:FindFirstChild("Neck")
		if neck and neck:IsA("Motor6D") then return neck end
	end
	local torso = character:FindFirstChild("Torso")
	if torso then
		local neck = torso:FindFirstChild("Neck")
		if neck and neck:IsA("Motor6D") then return neck end
	end
	return nil
end

local originalNeckC0 = nil

local function spinbot_stop()
	local f = features.Spinbot
	if f.bodyConn then f.bodyConn:Disconnect(); f.bodyConn=nil end
	if f.headConn then f.headConn:Disconnect(); f.headConn=nil end
	if originalNeckC0 then
		local neck = getNeck()
		if neck then neck.C0 = originalNeckC0 end
		originalNeckC0 = nil
	end
	spinAngle = 0
	headTimer = 0
end

local function spinbot_start()
	local f = features.Spinbot
	spinAngle = 0
	headTimer = 0
	local mode = cfg.spinMode
	local neck = getNeck()
	if neck and not originalNeckC0 then originalNeckC0 = neck.C0 end
	if mode == "Body Only" or mode == "Both" then
		f.bodyConn = RunService.RenderStepped:Connect(function(dt)
			if not hrp then return end
			spinAngle = (spinAngle + cfg.spinSpeed * dt) % 360
			local vel = hrp.AssemblyLinearVelocity
			hrp.CFrame = CFrame.new(hrp.Position) * CFrame.Angles(0, math.rad(spinAngle), 0)
			hrp.AssemblyLinearVelocity = vel
		end)
	end
	if mode == "Head Only" or mode == "Both" then
		f.headConn = RunService.RenderStepped:Connect(function(dt)
			headTimer = headTimer + dt
			local neck2 = getNeck()
			if not neck2 or not originalNeckC0 then return end
			local cycle = (1 - math.cos(2 * math.pi * headTimer / HEAD_PERIOD)) / 2
			local pitch  = cycle * math.pi
			neck2.C0 = originalNeckC0 * CFrame.Angles(-pitch, 0, 0)
		end)
	end
end

----------------------------------------------------------------------
-- FAKE AIMBOT
----------------------------------------------------------------------
local function isEnemy(p)
	local myTeam=player.Team; if myTeam==nil then return true end; return p.Team~=myTeam
end
local function getNearestHead()
	local closest,closestDist=nil,math.huge
	local camCF=camera.CFrame; local camPos=camCF.Position; local camLook=camCF.LookVector; local fovRad=math.rad(cfg.aimbotFOV)
	for _,p in ipairs(Players:GetPlayers()) do
		if p==player or not isEnemy(p) then continue end
		local char=p.Character; if not char then continue end
		local head=char:FindFirstChild("Head"); local hum=char:FindFirstChildOfClass("Humanoid")
		if not head or not hum or hum.Health<=0 then continue end
		local toHead=head.Position-camPos; local dist=toHead.Magnitude; local angle=math.acos(math.clamp(camLook:Dot(toHead.Unit),-1,1))
		if angle>fovRad then continue end
		if dist<closestDist then closestDist=dist; closest=head end
	end
	return closest
end

local function fakeaimbot_start()
	features.FakeAimbot.conn=RunService.RenderStepped:Connect(function(dt)
		local held=false; local btn=cfg.aimbotButton
		if typeof(btn)=="EnumItem" then
			if btn.EnumType==Enum.UserInputType then held=UserInputService:IsMouseButtonPressed(btn)
			elseif btn.EnumType==Enum.KeyCode then held=UserInputService:IsKeyDown(btn) end
		end
		if not held then return end
		local head=getNearestHead(); if not head then return end
		local dir=(head.Position-camera.CFrame.Position).Unit
		camera.CFrame=camera.CFrame:Lerp(CFrame.lookAt(camera.CFrame.Position,camera.CFrame.Position+dir),math.min(dt*cfg.aimbotSmooth,1))
	end)
end

----------------------------------------------------------------------
-- HUD REMOVER
----------------------------------------------------------------------
local OUR_GUIS = {
	"ClarityMenu", "LarpWatermark", "ClarityMomentum",
	"VelocityGraph", "PlayerGui"
}
local function isOurGui(gui)
	for _, name in ipairs(OUR_GUIS) do
		if gui.Name == name then return true end
	end
	return false
end

local function setHudRemoved(enabled)
	hudRemoved = enabled
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then return end
	if enabled then
		hiddenHudItems = {}
		for _, gui in ipairs(playerGui:GetChildren()) do
			if gui:IsA("ScreenGui") or gui:IsA("GuiBase2d") then
				if not isOurGui(gui) and gui.Enabled then
					gui.Enabled = false
					table.insert(hiddenHudItems, gui)
				end
			end
		end
	else
		for _, gui in ipairs(hiddenHudItems) do
			if gui and gui.Parent then gui.Enabled = true end
		end
		hiddenHudItems = {}
	end
end

----------------------------------------------------------------------
-- STOP / TOGGLE FEATURES
----------------------------------------------------------------------
local function stopFeature(key)
	local f=features[key]
	if key=="Spinbot" then spinbot_stop(); return end
	if f.conn then f.conn:Disconnect(); f.conn=nil end
	if key=="PixelSurf" or key=="TextureBug" then f.surfing=false; f.glideDir=nil; f.glideSpeed=0; updateTrail(Vector3.zero,false,key) end
	if key=="LongJump" then lj_used=false end
end

local function toggleFeature(key)
	local f=features[key]; f.enabled=not f.enabled
	if f.enabled then
		if     key=="PixelSurf"  then makeSurf(key,Vector3.new(0,0,0),   function() return cfg.pixelMaxSpeed   end)
		elseif key=="TextureBug" then makeSurf(key,Vector3.new(0,2.5,0), function() return cfg.textureMaxSpeed end)
		elseif key=="AutoBhop"   then bhop_start()
		elseif key=="JumpBug"    then jumpbug_start()
		elseif key=="LongJump"   then longjump_start()
		elseif key=="MiniJump"   then minijump_start()
		elseif key=="FakeAimbot" then fakeaimbot_start()
		elseif key=="Spinbot"    then spinbot_start()
		end
	else stopFeature(key) end
	return f.enabled
end

----------------------------------------------------------------------
-- ESP SYSTEM
----------------------------------------------------------------------
local r15_bones = {
	{"Head","UpperTorso"},{"UpperTorso","LowerTorso"},
	{"UpperTorso","LeftUpperArm"},{"LeftUpperArm","LeftLowerArm"},{"LeftLowerArm","LeftHand"},
	{"UpperTorso","RightUpperArm"},{"RightUpperArm","RightLowerArm"},{"RightLowerArm","RightHand"},
	{"LowerTorso","LeftUpperLeg"},{"LeftUpperLeg","LeftLowerLeg"},{"LeftLowerLeg","LeftFoot"},
	{"LowerTorso","RightUpperLeg"},{"RightUpperLeg","RightLowerLeg"},{"RightLowerLeg","RightFoot"},
}
local r6_bones = {{"Head","Torso"},{"Torso","Left Arm"},{"Torso","Right Arm"},{"Torso","Left Leg"},{"Torso","Right Leg"}}
local custom_bones = {
	{"Head","Torso"},{"Torso","Left Upper Arm"},{"Left Upper Arm","Left Lower Arm"},{"Left Lower Arm","Left Hand"},
	{"Torso","Right Upper Arm"},{"Right Upper Arm","Right Lower Arm"},{"Right Lower Arm","Right Hand"},
	{"Torso","Left Upper Leg"},{"Left Upper Leg","Left Lower Leg"},{"Left Lower Leg","Left Foot"},
	{"Torso","Right Upper Leg"},{"Right Upper Leg","Right Lower Leg"},{"Right Lower Leg","Right Foot"},
}
local function w2s(pos) local vec,onscreen=camera:WorldToViewportPoint(pos); return Vector2.new(vec.X,vec.Y),onscreen end
local function create_line() local l=Drawing.new("Line"); l.Visible=false; l.Thickness=ESP_CFG.skeleton_thickness; l.Color=ESP_CFG.skeleton_color; l.Transparency=ESP_CFG.skeleton_transparency; return l end
local function create_text() local t=Drawing.new("Text"); t.Visible=false; t.Center=true; t.Outline=true; t.Font=2; return t end
local function create_square() local s=Drawing.new("Square"); s.Visible=false; s.Filled=false; return s end

local function cl(p)
	if espObjects[p] then
		if espObjects[p].lines then for _,bd in pairs(espObjects[p].lines) do if bd.line then bd.line:Remove() end end end
		if espObjects[p].box then espObjects[p].box:Remove() end
		if espObjects[p].box_outline then espObjects[p].box_outline:Remove() end
		if espObjects[p].box_fill then espObjects[p].box_fill:Remove() end
		if espObjects[p].healthbar_bg then espObjects[p].healthbar_bg:Remove() end
		if espObjects[p].healthbar then espObjects[p].healthbar:Remove() end
		if espObjects[p].name then espObjects[p].name:Remove() end
		if espObjects[p].distance then espObjects[p].distance:Remove() end
		if espObjects[p].tracer then espObjects[p].tracer:Remove() end
		if espObjects[p].tracer_outline then espObjects[p].tracer_outline:Remove() end
		espObjects[p]=nil
	end
	crouching[p]=nil
end

local function rig(c)
	local h=c:FindFirstChildOfClass("Humanoid")
	if h and h.RigType==Enum.HumanoidRigType.R15 then return r15_bones end
	if c:FindFirstChild("Left Upper Arm") then return custom_bones end
	return r6_bones
end

local function makeESP(p)
	if not p:IsA("Player") or not espEnabled then return end
	if p.Team==player.Team and p.Team~=nil then cl(p); return end
	cl(p); local c=p.Character; if not c then return end
	local h=c:FindFirstChildOfClass("Humanoid"); if not h or h.Health<=0 then return end
	local hrp2=c:FindFirstChild("HumanoidRootPart"); if not hrp2 then return end
	if ESP_CFG.crouch_detection then crouching[p]=h.HipHeight<ESP_CFG.crouch_height_threshold end
	local bones=rig(c); local lines={}
	for _,bone in pairs(bones) do
		local p1=c:FindFirstChild(bone[1]); local p2=c:FindFirstChild(bone[2])
		if p1 and p2 then local line=create_line(); table.insert(lines,{line=line,p1=p1,p2=p2}) end
	end
	local box=ESP_CFG.box_enabled and create_square() or nil
	local box_outline=(ESP_CFG.box_enabled and ESP_CFG.box_thickness>0) and create_square() or nil
	local box_fill=(ESP_CFG.box_enabled and ESP_CFG.box_filled) and create_square() or nil
	if box_outline then box_outline.Thickness=ESP_CFG.box_thickness+1; box_outline.Color=Color3.new(0,0,0) end
	if box_fill then box_fill.Filled=true; box_fill.Color=ESP_CFG.box_fill_color; box_fill.Transparency=ESP_CFG.box_fill_transparency end
	local hbg=ESP_CFG.healthbar_enabled and create_square() or nil
	local hb=ESP_CFG.healthbar_enabled and create_square() or nil
	if hbg then hbg.Filled=true; hbg.Color=Color3.new(0,0,0); hbg.Transparency=0.5 end
	if hb then hb.Filled=true end
	local name_text=ESP_CFG.name_enabled and create_text() or nil
	if name_text then name_text.Size=ESP_CFG.name_size; name_text.Color=ESP_CFG.name_color; name_text.Outline=ESP_CFG.name_outline end
	local distance_text=ESP_CFG.distance_enabled and create_text() or nil
	if distance_text then distance_text.Size=ESP_CFG.distance_size; distance_text.Color=ESP_CFG.distance_color; distance_text.Outline=true end
	local tracer=ESP_CFG.tracer_enabled and create_line() or nil
	local tracer_outline=(ESP_CFG.tracer_enabled and ESP_CFG.tracer_thickness>1) and create_line() or nil
	if tracer then tracer.Thickness=ESP_CFG.tracer_thickness; tracer.Color=ESP_CFG.tracer_color; tracer.Transparency=ESP_CFG.tracer_transparency end
	if tracer_outline then tracer_outline.Thickness=ESP_CFG.tracer_thickness+2; tracer_outline.Color=Color3.new(0,0,0); tracer_outline.Transparency=ESP_CFG.tracer_transparency*0.5 end
	espObjects[p]={lines=lines,character=c,humanoid=h,box=box,box_outline=box_outline,box_fill=box_fill,healthbar_bg=hbg,healthbar=hb,name=name_text,distance=distance_text,tracer=tracer,tracer_outline=tracer_outline}
end

local function get_character_bounds(c)
	local hrp2=c:FindFirstChild("HumanoidRootPart"); if not hrp2 then return nil end
	local corners={}; local size=hrp2.Size; local cf=hrp2.CFrame
	local offsets={
		Vector3.new(size.X/2,size.Y/2,size.Z/2),   Vector3.new(-size.X/2,size.Y/2,size.Z/2),
		Vector3.new(size.X/2,-size.Y/2,size.Z/2),  Vector3.new(-size.X/2,-size.Y/2,size.Z/2),
		Vector3.new(size.X/2,size.Y/2,-size.Z/2),  Vector3.new(-size.X/2,size.Y/2,-size.Z/2),
		Vector3.new(size.X/2,-size.Y/2,-size.Z/2), Vector3.new(-size.X/2,-size.Y/2,-size.Z/2),
	}
	for _,offset in ipairs(offsets) do
		local worldPos=cf:PointToWorldSpace(offset); local screenPos,onScreen=w2s(worldPos)
		if onScreen then table.insert(corners,screenPos) end
	end
	if #corners==0 then return nil end
	local minX,maxX=math.huge,-math.huge; local minY,maxY=math.huge,-math.huge
	for _,corner in pairs(corners) do minX=math.min(minX,corner.X); maxX=math.max(maxX,corner.X); minY=math.min(minY,corner.Y); maxY=math.max(maxY,corner.Y) end
	return {topLeft=Vector2.new(minX,minY),size=Vector2.new(maxX-minX,maxY-minY),center=Vector2.new((minX+maxX)/2,(minY+maxY)/2)}
end

local function updateESP()
	for p,data in pairs(espObjects) do
		local c=data.character; local h=data.humanoid
		if not c or not c.Parent or not h or h.Health<=0 then cl(p); continue end
		local hrp2=c:FindFirstChild("HumanoidRootPart"); if not hrp2 then cl(p); continue end
		if ESP_CFG.crouch_detection and h then crouching[p]=h.HipHeight<ESP_CFG.crouch_height_threshold end
		local is_crouching=crouching[p]; local skel_color=is_crouching and ESP_CFG.crouch_color or ESP_CFG.skeleton_color
		if data.lines then
			for _,bd in pairs(data.lines) do
				local line=bd.line; local p1=bd.p1; local p2=bd.p2
				if p1 and p1.Parent and p2 and p2.Parent then
					local pos1,on1=w2s(p1.Position); local pos2,on2=w2s(p2.Position)
					if on1 and on2 then line.From=pos1; line.To=pos2; line.Color=skel_color; line.Thickness=ESP_CFG.skeleton_thickness; line.Transparency=ESP_CFG.skeleton_transparency; line.Visible=true else line.Visible=false end
				else line.Visible=false end
			end
		end
		local bounds=get_character_bounds(c)
		if bounds then
			if ESP_CFG.box_enabled and data.box then
				if data.box_outline then data.box_outline.Position=bounds.topLeft-Vector2.new(1,1); data.box_outline.Size=bounds.size+Vector2.new(2,2); data.box_outline.Visible=true end
				if data.box_fill then data.box_fill.Position=bounds.topLeft; data.box_fill.Size=bounds.size; data.box_fill.Visible=true end
				data.box.Position=bounds.topLeft; data.box.Size=bounds.size; data.box.Color=ESP_CFG.box_color; data.box.Thickness=ESP_CFG.box_thickness; data.box.Visible=true
			else
				if data.box then data.box.Visible=false end; if data.box_outline then data.box_outline.Visible=false end; if data.box_fill then data.box_fill.Visible=false end
			end
			if ESP_CFG.healthbar_enabled and data.healthbar and data.healthbar_bg then
				local barWidth=3; local barHeight=bounds.size.Y; local healthPercent=h.Health/h.MaxHealth
				data.healthbar_bg.Position=Vector2.new(bounds.topLeft.X-barWidth-3,bounds.topLeft.Y); data.healthbar_bg.Size=Vector2.new(barWidth,barHeight); data.healthbar_bg.Visible=true
				local currentHeight=barHeight*healthPercent
				data.healthbar.Position=Vector2.new(bounds.topLeft.X-barWidth-3,bounds.topLeft.Y+barHeight-currentHeight); data.healthbar.Size=Vector2.new(barWidth,currentHeight)
				data.healthbar.Color=ESP_CFG.healthbar_color_high:Lerp(ESP_CFG.healthbar_color_low,1-healthPercent); data.healthbar.Visible=true
			else if data.healthbar then data.healthbar.Visible=false end; if data.healthbar_bg then data.healthbar_bg.Visible=false end end
			if ESP_CFG.name_enabled and data.name then data.name.Text=p.DisplayName; data.name.Position=Vector2.new(bounds.center.X,bounds.topLeft.Y-15); data.name.Color=ESP_CFG.name_color; data.name.Size=ESP_CFG.name_size; data.name.Visible=true else if data.name then data.name.Visible=false end end
			if ESP_CFG.distance_enabled and data.distance then local dist=(hrp2.Position-camera.CFrame.Position).Magnitude; data.distance.Text=string.format("%d studs",math.floor(dist)); data.distance.Position=Vector2.new(bounds.center.X,bounds.topLeft.Y+bounds.size.Y+2); data.distance.Color=ESP_CFG.distance_color; data.distance.Size=ESP_CFG.distance_size; data.distance.Visible=true else if data.distance then data.distance.Visible=false end end
		else
			if data.box then data.box.Visible=false end; if data.box_outline then data.box_outline.Visible=false end; if data.box_fill then data.box_fill.Visible=false end
			if data.healthbar then data.healthbar.Visible=false end; if data.healthbar_bg then data.healthbar_bg.Visible=false end
			if data.name then data.name.Visible=false end; if data.distance then data.distance.Visible=false end
		end
		if ESP_CFG.tracer_enabled and data.tracer then
			local pos,onscreen=w2s(hrp2.Position)
			if onscreen then
				local fromPos
				if ESP_CFG.tracer_from=="Bottom" then fromPos=Vector2.new(camera.ViewportSize.X/2,camera.ViewportSize.Y)
				elseif ESP_CFG.tracer_from=="Middle" then fromPos=Vector2.new(camera.ViewportSize.X/2,camera.ViewportSize.Y/2)
				elseif ESP_CFG.tracer_from=="Top" then fromPos=Vector2.new(camera.ViewportSize.X/2,0)
				elseif ESP_CFG.tracer_from=="Mouse" then fromPos=Vector2.new(mouse.X,mouse.Y) end
				if data.tracer_outline then data.tracer_outline.From=fromPos; data.tracer_outline.To=pos; data.tracer_outline.Visible=true end
				data.tracer.From=fromPos; data.tracer.To=pos; data.tracer.Color=ESP_CFG.tracer_color; data.tracer.Visible=true
			else data.tracer.Visible=false; if data.tracer_outline then data.tracer_outline.Visible=false end end
		else if data.tracer then data.tracer.Visible=false end; if data.tracer_outline then data.tracer_outline.Visible=false end end
	end
end

local function refreshESP()
	if not espEnabled then for _,p in pairs(Players:GetPlayers()) do cl(p) end; return end
	for _,p in pairs(Players:GetPlayers()) do if p~=player then makeESP(p) end end
end
local function toggleESP(enabled)
	espEnabled=enabled
	if enabled then refreshESP(); espConn=RunService.RenderStepped:Connect(updateESP)
	else if espConn then espConn:Disconnect(); espConn=nil end; for _,p in pairs(Players:GetPlayers()) do cl(p) end end
end
Players.PlayerAdded:Connect(function(p)
	if not espEnabled then return end
	p.CharacterAdded:Connect(function() task.wait(1); if p~=player and espEnabled then makeESP(p) end end)
end)
Players.PlayerRemoving:Connect(function(p) if espEnabled then cl(p) end end)

----------------------------------------------------------------------
-- SKINS SYSTEM
----------------------------------------------------------------------
local function resolvePartName(n) return n:gsub("%s+","") end
local function getEquippedGunName()
	local char=player.Character; if not char then return nil end
	local gun=char:FindFirstChild("Gun"); return gun and gun:GetAttribute("GunName")
end
local function getArms()
	local cam=workspace:FindFirstChild("Camera"); return cam and cam:FindFirstChild("Arms")
end
local function snapshotOriginals(gunName, arms)
	if skinOriginals[gunName] then return end
	local snap={}; for _,p in ipairs(arms:GetChildren()) do if p:IsA("MeshPart") then snap[p.Name]=p.TextureID end end
	skinOriginals[gunName]=snap
end
local skinMapCache={}
local function buildSkinMap(gunName, skinName)
	local gunSkins=ReplicatedStorage:FindFirstChild("Skins") and ReplicatedStorage.Skins:FindFirstChild(gunName)
	if not gunSkins then return nil end
	local skin=gunSkins:FindFirstChild(skinName); if not skin then return nil end
	local map={}
	local function add(sv) if sv:IsA("StringValue") then map[sv.Name]=sv.Value; map[resolvePartName(sv.Name)]=sv.Value end end
	local wm=skin:FindFirstChild("WorldModel"); if wm then for _,sv in ipairs(wm:GetChildren()) do add(sv) end end
	for _,sv in ipairs(skin:GetChildren()) do add(sv) end
	return map
end
local function startSkinLoop()
	if skinConn then skinConn:Disconnect() end
	skinConn=RunService.RenderStepped:Connect(function()
		local arms=getArms(); if not arms then return end
		local gunName=getEquippedGunName(); if not gunName then return end
		snapshotOriginals(gunName,arms)
		local sel=skinSelections[gunName]
		if sel then
			local cacheKey=gunName.."|"..sel; local map=skinMapCache[cacheKey]
			if map==nil then map=buildSkinMap(gunName,sel) or false; skinMapCache[cacheKey]=map end
			if map then for _,p in ipairs(arms:GetChildren()) do if p:IsA("MeshPart") then local tex=map[p.Name] or map[resolvePartName(p.Name)]; if tex and p.TextureID~=tex then p.TextureID=tex end end end end
		else
			local orig=skinOriginals[gunName]
			if orig then for _,p in ipairs(arms:GetChildren()) do if p:IsA("MeshPart") and orig[p.Name] and p.TextureID~=orig[p.Name] then p.TextureID=orig[p.Name] end end end
		end
	end)
end
local function stopSkinLoop() if skinConn then skinConn:Disconnect(); skinConn=nil end end

----------------------------------------------------------------------
-- VISUALS
----------------------------------------------------------------------
local Lighting = game:GetService("Lighting")
local origFogEnd=Lighting.FogEnd; local origFogStart=Lighting.FogStart; local origFogColor=Lighting.FogColor
local blurEffect=nil; local fogConn,blurConn=nil,nil
local function setFog(enabled)
	if enabled then
		fogConn=RunService.Heartbeat:Connect(function() pcall(function() Lighting.FogEnd=cfg.fogEnd; Lighting.FogStart=math.max(0,cfg.fogEnd-60); Lighting.FogColor=Color3.fromRGB(190,190,190) end) end)
	else if fogConn then fogConn:Disconnect(); fogConn=nil end; pcall(function() Lighting.FogEnd=origFogEnd; Lighting.FogStart=origFogStart; Lighting.FogColor=origFogColor end) end
end
local prevCamPos=nil
local function setBlur(enabled)
	if enabled then
		if not blurEffect then blurEffect=Instance.new("BlurEffect"); blurEffect.Size=0; blurEffect.Parent=Lighting end
		prevCamPos=camera.CFrame.Position
		blurConn=RunService.RenderStepped:Connect(function()
			if not blurEffect then return end; local curPos=camera.CFrame.Position; local moved=(curPos-prevCamPos).Magnitude; local target=math.clamp(moved*cfg.blurSize,0,56)
			blurEffect.Size=blurEffect.Size+(target-blurEffect.Size)*0.3; prevCamPos=curPos
		end)
	else if blurConn then blurConn:Disconnect(); blurConn=nil end; if blurEffect then blurEffect:Destroy(); blurEffect=nil end end
end

----------------------------------------------------------------------
-- LARP WATERMARK
----------------------------------------------------------------------
local larpWatermarkGui=nil; local larpWatermarkEnabled=false; local larpRenderConnection=nil
local function toggleLarpWatermark(enabled)
	larpWatermarkEnabled=enabled
	if enabled then
		if larpWatermarkGui then larpWatermarkGui:Destroy() end
		larpWatermarkGui=Instance.new("ScreenGui"); larpWatermarkGui.Name="LarpWatermark"; larpWatermarkGui.ResetOnSpawn=false; larpWatermarkGui.IgnoreGuiInset=true; larpWatermarkGui.Parent=player:WaitForChild("PlayerGui")
		local mainFrame=Instance.new("Frame"); mainFrame.Size=UDim2.new(0,149,0,28); mainFrame.AnchorPoint=Vector2.new(1,0); mainFrame.Position=UDim2.new(1,-15,0,38); mainFrame.BackgroundColor3=Color3.fromRGB(25,25,25); mainFrame.BorderSizePixel=0; mainFrame.ClipsDescendants=true; mainFrame.Parent=larpWatermarkGui
		local stroke2=Instance.new("UIStroke"); stroke2.Color=Color3.fromRGB(60,60,60); stroke2.Thickness=1.5; stroke2.ApplyStrokeMode=Enum.ApplyStrokeMode.Border; stroke2.Parent=mainFrame
		local corner2=Instance.new("UICorner"); corner2.CornerRadius=UDim.new(0,8); corner2.Parent=mainFrame
		local logoImage=Instance.new("ImageLabel"); logoImage.Size=UDim2.new(0,63,0,63); logoImage.Position=UDim2.new(0,-15,0.2,-25); logoImage.BackgroundTransparency=1; logoImage.Image="rbxassetid://133887132709020"; logoImage.ImageTransparency=0.7; logoImage.ScaleType=Enum.ScaleType.Fit; logoImage.ZIndex=1; logoImage.Parent=mainFrame
		local textLabel=Instance.new("TextLabel"); textLabel.Size=UDim2.new(1,-10,1,0); textLabel.Position=UDim2.new(0,8,0,0); textLabel.BackgroundTransparency=1; textLabel.Text="larp | user | 0 fps"; textLabel.TextColor3=Color3.fromRGB(255,255,255); textLabel.Font=Enum.Font.GothamMedium; textLabel.TextSize=13; textLabel.TextXAlignment=Enum.TextXAlignment.Left; textLabel.ZIndex=2; textLabel.RichText=true; textLabel.Parent=mainFrame
		local lastUpdate=tick(); local frameCount=0; local fps=0
		local function updateDisplay()
			frameCount=frameCount+1; if tick()-lastUpdate>=0.5 then fps=math.floor(frameCount/(tick()-lastUpdate)); frameCount=0; lastUpdate=tick()
			textLabel.Text=string.format('<font color="rgb(79,144,85)" face="GothamBold">larp</font> <font color="rgb(80,80,80)">|</font> <font color="rgb(150,150,150)">%s</font> <font color="rgb(80,80,80)">|</font> <font face="GothamBold">%d</font> <font color="rgb(150,150,150)">fps</font>',player.Name,fps) end
		end
		larpRenderConnection=RunService.RenderStepped:Connect(updateDisplay)
	else
		if larpRenderConnection then larpRenderConnection:Disconnect(); larpRenderConnection=nil end
		if larpWatermarkGui then larpWatermarkGui:Destroy(); larpWatermarkGui=nil end
	end
end

----------------------------------------------------------------------
-- MOMENTUM TRACKER
----------------------------------------------------------------------
local momentumGui=nil; local momentumEnabled=false; local momentumConnection=nil; local jumpConnection=nil; local charConnection=nil
local function toggleMomentum(enabled)
	momentumEnabled=enabled
	if enabled then
		if momentumGui then momentumGui:Destroy() end
		momentumGui=Instance.new("ScreenGui"); momentumGui.Name="ClarityMomentum"; momentumGui.ResetOnSpawn=false; momentumGui.IgnoreGuiInset=true; momentumGui.Parent=player:WaitForChild("PlayerGui")
		local textLabel=Instance.new("TextLabel"); textLabel.Size=UDim2.new(0,400,0,50); textLabel.Position=UDim2.new(0.5,-200,0.85,0); textLabel.BackgroundTransparency=1; textLabel.Text="0 (0)"; textLabel.Font=Enum.Font.Nunito; textLabel.TextSize=30; textLabel.TextColor3=Color3.fromRGB(255,255,255); textLabel.ZIndex=2; textLabel.RichText=true; textLabel.Parent=momentumGui
		local lastJumpSpeed=0
		local function bindJump(char)
			if jumpConnection then jumpConnection:Disconnect() end; local hum=char:WaitForChild("Humanoid",10)
			if hum then jumpConnection=hum.StateChanged:Connect(function(old,new) if new==Enum.HumanoidStateType.Jumping then local hrp2=char:FindFirstChild("HumanoidRootPart"); if hrp2 then lastJumpSpeed=math.floor(Vector3.new(hrp2.AssemblyLinearVelocity.X,0,hrp2.AssemblyLinearVelocity.Z).Magnitude) end end end) end
		end
		if player.Character then bindJump(player.Character) end; charConnection=player.CharacterAdded:Connect(bindJump)
		momentumConnection=RunService.RenderStepped:Connect(function()
			if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
				local hrp2=player.Character.HumanoidRootPart; local vel=hrp2.AssemblyLinearVelocity; local speed=math.floor(Vector3.new(vel.X,0,vel.Z).Magnitude)
				local targetTransparency=1-math.clamp(speed/15,0,1); if speed<2 then targetTransparency=1 end
				textLabel.TextTransparency=textLabel.TextTransparency+(targetTransparency-textLabel.TextTransparency)*0.1
				textLabel.Text=string.format("%d (%d)",speed,lastJumpSpeed)
			end
		end)
	else
		if momentumConnection then momentumConnection:Disconnect(); momentumConnection=nil end; if jumpConnection then jumpConnection:Disconnect(); jumpConnection=nil end; if charConnection then charConnection:Disconnect(); charConnection=nil end
		if momentumGui then momentumGui:Destroy(); momentumGui=nil end
	end
end

----------------------------------------------------------------------
-- SCREEN GUI & WATERMARK
----------------------------------------------------------------------
local screenGui = Instance.new("ScreenGui")
screenGui.Name="ClarityMenu"; screenGui.ResetOnSpawn=false; screenGui.ZIndexBehavior=Enum.ZIndexBehavior.Global
screenGui.DisplayOrder=9999; screenGui.IgnoreGuiInset=true; screenGui.Parent=player:WaitForChild("PlayerGui")

local wmFrame=Instance.new("Frame"); wmFrame.Size=UDim2.new(0,0,0,22); wmFrame.AutomaticSize=Enum.AutomaticSize.X; wmFrame.Position=UDim2.new(1,0,0,8); wmFrame.AnchorPoint=Vector2.new(1,0); wmFrame.BackgroundColor3=Color3.fromRGB(10,10,12); wmFrame.BorderSizePixel=0; wmFrame.ZIndex=10; wmFrame.Parent=screenGui
Instance.new("UICorner",wmFrame).CornerRadius=UDim.new(0,4)
Instance.new("UIStroke",wmFrame).Color=Color3.fromRGB(30,30,38)
local wmPad=Instance.new("UIPadding",wmFrame); wmPad.PaddingLeft=UDim.new(0,8); wmPad.PaddingRight=UDim.new(0,8)
local wmLayout=Instance.new("UIListLayout",wmFrame); wmLayout.FillDirection=Enum.FillDirection.Horizontal; wmLayout.VerticalAlignment=Enum.VerticalAlignment.Center; wmLayout.Padding=UDim.new(0,0)
local function wmPart(txt,col) local l=Instance.new("TextLabel"); l.Size=UDim2.new(0,0,1,0); l.AutomaticSize=Enum.AutomaticSize.X; l.BackgroundTransparency=1; l.Text=txt; l.TextColor3=col; l.Font=Enum.Font.GothamMedium; l.TextSize=11; l.ZIndex=11; l.Parent=wmFrame; return l end
local wmName=wmPart("clarity",Color3.fromRGB(76,210,96)); local wmSep1=wmPart(" | ",Color3.fromRGB(45,45,55)); local wmUser=wmPart(player.Name,Color3.fromRGB(230,230,230)); local wmSep2=wmPart(" | ",Color3.fromRGB(45,45,55)); local wmFps=wmPart("0 fps",Color3.fromRGB(90,90,105))
local lastGunNameNS = nil
local fpsCounter=0; RunService.RenderStepped:Connect(function(dt) 
	fpsCounter=fpsCounter+1; if fpsCounter>=10 then fpsCounter=0; wmFps.Text=math.floor(1/math.max(dt,0.001)+0.5).." fps" end
	-- No-spread override with gun change detection
	if noSpreadActive then
		local currentGun = getEquippedGunNameNS()
		if currentGun ~= lastGunNameNS then
			-- Gun changed! Rescan
			if currentSpreadFolder then restoreSpreadNS(currentSpreadFolder) end
			currentSpreadFolder = getCurrentSpreadFolder()
			if currentSpreadFolder then saveOriginalsNS(currentSpreadFolder) end
			lastGunNameNS = currentGun
		end
		if currentSpreadFolder then applyLowSpread(currentSpreadFolder) end
	end
end)

----------------------------------------------------------------------
-- LUCIDE + UI HELPERS
----------------------------------------------------------------------
local LUCIDE_MODULE=nil
local function findLucideModule()
	if LUCIDE_MODULE then return LUCIDE_MODULE end
	local rs=game:GetService("ReplicatedStorage")
	local direct=rs:FindFirstChild("Lucide") or rs:FindFirstChild("lucide-roblox")
	if direct and direct:IsA("ModuleScript") then return direct end
	for _,d in ipairs(rs:GetDescendants()) do if d:IsA("ModuleScript") and (d.Name=="Lucide" or d.Name=="lucide-roblox") then return d end end
	return nil
end
local LOAD_LUCIDE_FROM_WEB=true
local LUCIDE_LUAU_URL="https://github.com/latte-soft/lucide-roblox/releases/download/0.1.3/lucide-roblox.luau"
local Lucide=nil
do
	local module=findLucideModule()
	if module then local ok,mod=pcall(require,module); if ok and type(mod)=="table" and mod.GetAsset then Lucide=mod end end
	if not Lucide and LOAD_LUCIDE_FROM_WEB then local ok,mod=pcall(function() return loadstring(game:HttpGet(LUCIDE_LUAU_URL))() end); if ok and type(mod)=="table" and mod.GetAsset then Lucide=mod end end
	if not Lucide then warn("[MenuUI] No Lucide source - using text glyph fallback.") end
end

local ICON_NAMES={movement="move",aimbot="crosshair",visuals="eye",misc="settings-2",inventory="sword",config="cog"}
local GLYPH={movement="\u{2725}",aimbot="\u{25CE}",visuals="\u{25C9}",misc="\u{2261}",inventory="\u{25A6}",config="\u{2699}"}

local function new(class,props)
	local obj=Instance.new(class); local parent=props.Parent; props.Parent=nil
	for k,v in pairs(props) do obj[k]=v end; if parent then obj.Parent=parent end; return obj
end
local function corner(parent,radius) new("UICorner",{CornerRadius=UDim.new(0,radius),Parent=parent}) end
local function stroke(parent,color,thickness) return new("UIStroke",{Color=color,Thickness=thickness or 1,ApplyStrokeMode=Enum.ApplyStrokeMode.Border,Parent=parent}) end
local function padding(parent,all) new("UIPadding",{PaddingTop=UDim.new(0,all),PaddingBottom=UDim.new(0,all),PaddingLeft=UDim.new(0,all),PaddingRight=UDim.new(0,all),Parent=parent}) end
local function vlist(parent,gap) new("UIListLayout",{FillDirection=Enum.FillDirection.Vertical,SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,gap),Parent=parent}) end

local function makeIcon(name,color,size)
	local iconName=ICON_NAMES[name]
	if Lucide and iconName then
		local ok,asset=pcall(Lucide.GetAsset,iconName,48)
		if ok and asset then return new("ImageLabel",{BackgroundTransparency=1,Image=asset.Url,ImageRectSize=asset.ImageRectSize,ImageRectOffset=asset.ImageRectOffset,ImageColor3=color,Size=UDim2.fromOffset(size,size)}) end
	end
	return new("TextLabel",{BackgroundTransparency=1,Text=GLYPH[name] or "\u{2022}",TextColor3=color,Font=Enum.Font.GothamBold,TextSize=size,Size=UDim2.fromOffset(size,size),TextXAlignment=Enum.TextXAlignment.Center,TextYAlignment=Enum.TextYAlignment.Center})
end

local COLORS={
	background=Color3.fromRGB(0,0,0),sidebar=Color3.fromRGB(0,0,0),panel=Color3.fromRGB(13,13,13),
	panelStroke=Color3.fromRGB(26,26,26),windowStroke=Color3.fromRGB(22,22,22),accent=Color3.fromRGB(48,244,38),
	sidebarSelBg=Color3.fromRGB(28,28,28),divider=Color3.fromRGB(38,38,38),titleBox=Color3.fromRGB(18,18,18),
	title=Color3.fromRGB(240,240,240),labelOn=Color3.fromRGB(226,226,226),labelOff=Color3.fromRGB(150,150,150),
	sidebarText=Color3.fromRGB(160,160,160),checkOff=Color3.fromRGB(22,22,22),checkOffStroke=Color3.fromRGB(50,50,50),
	check=Color3.fromRGB(8,12,8),keybind=Color3.fromRGB(95,95,95),
	dropdownBg=Color3.fromRGB(18,18,22),dropdownHover=Color3.fromRGB(28,28,35),
}
local SIZES={
	window=Vector2.new(900,635),sidebarW=168,contentPad=16,colGap=16,colWidth=330,
	rowH=25,rowGap=6,panelPad=12,panelGap=16,titleH=28,checkbox=18,labelStartX=24,corner=8,logoAreaH=84,
}
local FONTS={title=Enum.Font.GothamBold,label=Enum.Font.Gotham,sidebar=Enum.Font.GothamMedium,glyph=Enum.Font.GothamBold}
local LOGO_IMAGE="rbxassetid://136135909152944"

----------------------------------------------------------------------
-- MAIN WINDOW
----------------------------------------------------------------------
local win=Instance.new("Frame")
win.Name="Window"; win.AnchorPoint=Vector2.new(0.5,0.5); win.Position=UDim2.fromScale(0.5,0.5)
win.Size=UDim2.fromOffset(SIZES.window.X,SIZES.window.Y); win.BackgroundColor3=COLORS.background; win.BorderSizePixel=0
win.ClipsDescendants=true; win.Visible=false; win.Parent=screenGui
corner(win,SIZES.corner); stroke(win,COLORS.windowStroke,1)

local sidebar=Instance.new("Frame"); sidebar.Size=UDim2.new(0,SIZES.sidebarW,1,0); sidebar.BackgroundColor3=COLORS.sidebar; sidebar.BorderSizePixel=0; sidebar.Parent=win
new("UIPadding",{PaddingTop=UDim.new(0,20),PaddingLeft=UDim.new(0,14),PaddingRight=UDim.new(0,14),Parent=sidebar})

local logoHolder=Instance.new("Frame"); logoHolder.Size=UDim2.new(1,0,0,SIZES.logoAreaH); logoHolder.BackgroundTransparency=1; logoHolder.LayoutOrder=0; logoHolder.Parent=sidebar
local logo=Instance.new("ImageLabel"); logo.BackgroundTransparency=1; logo.Image=LOGO_IMAGE; logo.ScaleType=Enum.ScaleType.Fit; logo.AnchorPoint=Vector2.new(0.5,0.5); logo.Position=UDim2.fromScale(0.5,0.5); logo.Size=UDim2.fromOffset(64,64); logo.Parent=logoHolder

local nav=Instance.new("Frame"); nav.Size=UDim2.new(1,0,1,-SIZES.logoAreaH); nav.Position=UDim2.new(0,0,0,SIZES.logoAreaH); nav.BackgroundTransparency=1; nav.Parent=sidebar
vlist(nav,3)

local SIDEBAR={
	{name="aimbot",    icon="aimbot",    defaultSub="main"},
	{name="movement",  icon="movement",  subs={"main","recorder"}},
	{name="visuals",   icon="visuals",   defaultSub="enemy"},
	{name="misc",      icon="misc",      defaultSub="hud"},
	{name="inventory", icon="inventory", defaultSub="skinchanger"},
	{name="config",    icon="config",    defaultSub="soon"},
}

local categoryButtons={}; local subButtons={}
local activeCategory=nil; local activeSub=nil

local function selectCategory(name)
	activeCategory=name
	for cat,ctrl in pairs(categoryButtons) do ctrl.setSelected(cat==name) end
	local showSubs=(name=="movement")
	for _,ctrl in pairs(subButtons) do ctrl.btn.Visible=showSubs end
	if showSubs then
		if activeSub~="main" and activeSub~="recorder" then activeSub="main" end
		for subName,ctrl in pairs(subButtons) do ctrl.setSelected(subName==activeSub) end
		rebuildContent("movement",activeSub)
	else
		local entry=nil; for _,e in ipairs(SIDEBAR) do if e.name==name then entry=e; break end end
		if entry and entry.defaultSub then rebuildContent(name,entry.defaultSub) end
	end
end

local function selectSub(name)
	if activeCategory~="movement" then return end
	activeSub=name
	for subName,ctrl in pairs(subButtons) do ctrl.setSelected(subName==name) end
	rebuildContent("movement",name)
end

local function buildCategory(entry,order)
	local row=Instance.new("Frame"); row.Name=entry.name; row.Size=UDim2.new(1,0,0,30); row.BackgroundColor3=COLORS.sidebarSelBg; row.BackgroundTransparency=1; row.LayoutOrder=order; row.Parent=nav
	corner(row,6)
	new("UIPadding",{PaddingLeft=UDim.new(0,8),Parent=row})
	local icon=makeIcon(entry.icon,COLORS.accent,17); icon.AnchorPoint=Vector2.new(0,0.5); icon.Position=UDim2.new(0,0,0.5,0); icon.Parent=row
	local label=Instance.new("TextLabel"); label.BackgroundTransparency=1; label.Text=entry.name; label.Font=FONTS.sidebar; label.TextSize=14; label.TextColor3=COLORS.sidebarText; label.TextXAlignment=Enum.TextXAlignment.Left; label.Position=UDim2.new(0,26,0,0); label.Size=UDim2.new(1,-26,1,0); label.Parent=row
	local button=Instance.new("TextButton"); button.Text=""; button.BackgroundTransparency=1; button.Size=UDim2.fromScale(1,1); button.AutoButtonColor=false; button.Parent=row
	local tweenInfo=TweenInfo.new(0.15,Enum.EasingStyle.Quad,Enum.EasingDirection.Out)
	categoryButtons[entry.name]={setSelected=function(sel) TweenService:Create(row,tweenInfo,{BackgroundTransparency=sel and 0 or 1}):Play(); TweenService:Create(label,tweenInfo,{TextColor3=sel and COLORS.accent or COLORS.sidebarText}):Play() end}
	button.MouseButton1Click:Connect(function() selectCategory(entry.name) end)
end

local function buildSubButtons()
	local order=20; local tweenInfo=TweenInfo.new(0.15,Enum.EasingStyle.Quad,Enum.EasingDirection.Out)
	for _,subName in ipairs({"main","recorder"}) do
		local row=Instance.new("Frame"); row.Name=subName; row.Size=UDim2.new(1,0,0,24); row.BackgroundColor3=COLORS.sidebarSelBg; row.BackgroundTransparency=1; row.LayoutOrder=order; row.Parent=nav; row.Visible=false; order+=1
		corner(row,6); new("UIPadding",{PaddingLeft=UDim.new(0,34),Parent=row})
		local label=Instance.new("TextLabel"); label.BackgroundTransparency=1; label.Text=subName; label.Font=FONTS.sidebar; label.TextSize=13; label.TextColor3=COLORS.sidebarText; label.TextXAlignment=Enum.TextXAlignment.Left; label.Position=UDim2.new(0,0,0,0); label.Size=UDim2.new(1,0,1,0); label.Parent=row
		local button=Instance.new("TextButton"); button.Text=""; button.BackgroundTransparency=1; button.Size=UDim2.fromScale(1,1); button.AutoButtonColor=false; button.Parent=row
		subButtons[subName]={btn=row,setSelected=function(sel) TweenService:Create(row,tweenInfo,{BackgroundTransparency=sel and 0 or 1}):Play(); TweenService:Create(label,tweenInfo,{TextColor3=sel and COLORS.accent or COLORS.sidebarText}):Play() end}
		button.MouseButton1Click:Connect(function() selectSub(subName) end)
	end
end

do local order=0; for _,entry in ipairs(SIDEBAR) do order+=10; buildCategory(entry,order) end; buildSubButtons() end

local content=Instance.new("Frame"); content.Name="Content"; content.Position=UDim2.new(0,SIZES.sidebarW,0,0); content.Size=UDim2.new(1,-SIZES.sidebarW,1,0); content.BackgroundTransparency=1; content.Parent=win
padding(content,SIZES.contentPad)
local columnList=Instance.new("UIListLayout"); columnList.FillDirection=Enum.FillDirection.Horizontal; columnList.SortOrder=Enum.SortOrder.LayoutOrder; columnList.Padding=UDim.new(0,SIZES.colGap); columnList.HorizontalAlignment=Enum.HorizontalAlignment.Left; columnList.VerticalAlignment=Enum.VerticalAlignment.Top; columnList.Parent=content

local columns={}
local function clearContent() for _,col in pairs(columns) do col:Destroy() end; columns={} end
local function makeColumn(order)
	local col=Instance.new("Frame"); col.Size=UDim2.new(0,SIZES.colWidth,0,0); col.AutomaticSize=Enum.AutomaticSize.Y; col.BackgroundTransparency=1; col.LayoutOrder=order; col.Parent=content
	vlist(col,SIZES.panelGap); return col
end

----------------------------------------------------------------------
-- DROPDOWN BUILDER
----------------------------------------------------------------------
local function buildDropdown(parent, labelTxt, options, currentValue, onChange)
	local DROPDOWN_H = 26
	local wrapper = Instance.new("Frame")
	wrapper.Size = UDim2.new(1, 0, 0, 0)
	wrapper.AutomaticSize = Enum.AutomaticSize.Y
	wrapper.BackgroundTransparency = 1
	wrapper.Parent = parent
	local labelRow = Instance.new("Frame")
	labelRow.Size = UDim2.new(1, 0, 0, DROPDOWN_H)
	labelRow.BackgroundTransparency = 1
	labelRow.Parent = wrapper
	local lbl = Instance.new("TextLabel")
	lbl.Text = labelTxt; lbl.Font = FONTS.label; lbl.TextSize = 13; lbl.TextColor3 = COLORS.labelOff
	lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.TextYAlignment = Enum.TextYAlignment.Center
	lbl.BackgroundTransparency = 1; lbl.Size = UDim2.new(0.45, 0, 1, 0); lbl.Parent = labelRow
	local btn = Instance.new("TextButton")
	btn.Text = currentValue; btn.Font = FONTS.label; btn.TextSize = 12; btn.TextColor3 = COLORS.title
	btn.BackgroundColor3 = COLORS.dropdownBg; btn.Size = UDim2.new(0.55, -4, 1, -4)
	btn.Position = UDim2.new(0.45, 4, 0, 2); btn.AutoButtonColor = false; btn.Parent = labelRow
	corner(btn, 5); stroke(btn, COLORS.divider, 1)
	local arrow = Instance.new("TextLabel")
	arrow.Text = "▾"; arrow.Font = FONTS.label; arrow.TextSize = 12; arrow.TextColor3 = COLORS.labelOff
	arrow.BackgroundTransparency = 1; arrow.Size = UDim2.new(0, 16, 1, 0)
	arrow.Position = UDim2.new(1, -18, 0, 0); arrow.TextXAlignment = Enum.TextXAlignment.Center; arrow.Parent = btn
	local optFrame = Instance.new("Frame")
	optFrame.Size = UDim2.new(0.55, -4, 0, 0); optFrame.AutomaticSize = Enum.AutomaticSize.Y
	optFrame.Position = UDim2.new(0.45, 4, 0, DROPDOWN_H + 2); optFrame.BackgroundColor3 = COLORS.dropdownBg
	optFrame.BorderSizePixel = 0; optFrame.ZIndex = 50; optFrame.Visible = false; optFrame.Parent = wrapper
	corner(optFrame, 5); stroke(optFrame, COLORS.divider, 1)
	local optList = Instance.new("UIListLayout")
	optList.FillDirection = Enum.FillDirection.Vertical; optList.Padding = UDim.new(0, 1); optList.Parent = optFrame
	local optPad = Instance.new("UIPadding")
	optPad.PaddingTop = UDim.new(0, 3); optPad.PaddingBottom = UDim.new(0, 3)
	optPad.PaddingLeft = UDim.new(0, 4); optPad.PaddingRight = UDim.new(0, 4); optPad.Parent = optFrame
	local isOpen = false
	local function setOpen(open)
		isOpen = open; optFrame.Visible = open; arrow.Text = open and "▴" or "▾"
	end
	for _, opt in ipairs(options) do
		local optBtn = Instance.new("TextButton")
		optBtn.Text = opt; optBtn.Font = FONTS.label; optBtn.TextSize = 12
		optBtn.TextColor3 = opt == currentValue and COLORS.accent or COLORS.labelOff
		optBtn.BackgroundColor3 = COLORS.dropdownBg; optBtn.BackgroundTransparency = 1
		optBtn.Size = UDim2.new(1, 0, 0, 22); optBtn.TextXAlignment = Enum.TextXAlignment.Left
		optBtn.AutoButtonColor = false; optBtn.ZIndex = 51; optBtn.Parent = optFrame
		optBtn.MouseEnter:Connect(function()
			TweenService:Create(optBtn, TweenInfo.new(0.1), {BackgroundTransparency = 0.5, BackgroundColor3 = COLORS.dropdownHover}):Play()
		end)
		optBtn.MouseLeave:Connect(function()
			TweenService:Create(optBtn, TweenInfo.new(0.1), {BackgroundTransparency = 1}):Play()
		end)
		optBtn.MouseButton1Click:Connect(function()
			btn.Text = opt
			for _, child in ipairs(optFrame:GetChildren()) do
				if child:IsA("TextButton") then child.TextColor3 = COLORS.labelOff end
			end
			optBtn.TextColor3 = COLORS.accent
			setOpen(false)
			onChange(opt)
		end)
	end
	btn.MouseButton1Click:Connect(function() setOpen(not isOpen) end)
	UserInputService.InputBegan:Connect(function(input, gpe)
		if gpe then return end
		if not isOpen then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			local mp = Vector2.new(input.Position.X, input.Position.Y)
			local absPos = optFrame.AbsolutePosition; local sz = optFrame.AbsoluteSize
			if mp.X < absPos.X or mp.X > absPos.X + sz.X or mp.Y < absPos.Y or mp.Y > absPos.Y + sz.Y then
				setOpen(false)
			end
		end
	end)
	return wrapper
end

----------------------------------------------------------------------
-- SLIDER BUILDER
----------------------------------------------------------------------
local function buildSlider(parent,xOff,yOff,labelTxt,minV,maxV,initV,trackW,onCh)
	local row=Instance.new("Frame"); row.Size=UDim2.new(1,-xOff,0,14); row.Position=UDim2.new(0,xOff,0,yOff); row.BackgroundTransparency=1; row.ZIndex=6; row.Parent=parent
	local sLbl=Instance.new("TextLabel"); sLbl.Size=UDim2.new(0,34,1,0); sLbl.BackgroundTransparency=1; sLbl.Text=labelTxt; sLbl.TextColor3=COLORS.labelOff; sLbl.Font=FONTS.label; sLbl.TextSize=9; sLbl.TextXAlignment=Enum.TextXAlignment.Left; sLbl.ZIndex=7; sLbl.Parent=row
	local track=Instance.new("Frame"); track.Size=UDim2.new(0,trackW,0,2); track.Position=UDim2.new(0,36,0.5,-1); track.BackgroundColor3=COLORS.checkOff; track.BorderSizePixel=0; track.ZIndex=7; track.Parent=row; corner(track,1)
	local frac=math.clamp((initV-minV)/(maxV-minV),0,1)
	local fill=Instance.new("Frame"); fill.Size=UDim2.new(frac,0,1,0); fill.BackgroundColor3=COLORS.accent; fill.BorderSizePixel=0; fill.ZIndex=8; fill.Parent=track; corner(fill,1)
	local knob=Instance.new("Frame"); knob.Size=UDim2.new(0,8,0,8); knob.AnchorPoint=Vector2.new(0.5,0.5); knob.Position=UDim2.new(frac,0,0.5,0); knob.BackgroundColor3=COLORS.title; knob.BorderSizePixel=0; knob.ZIndex=9; knob.Parent=track; corner(knob,4)
	local valLbl=Instance.new("TextLabel"); valLbl.Size=UDim2.new(0,32,1,0); valLbl.Position=UDim2.new(0,trackW+40,0,0); valLbl.BackgroundTransparency=1; valLbl.Text=tostring(initV); valLbl.TextColor3=COLORS.title; valLbl.Font=FONTS.label; valLbl.TextSize=9; valLbl.TextXAlignment=Enum.TextXAlignment.Left; valLbl.ZIndex=7; valLbl.Parent=row
	local sd=false
	local function apply(ax) local t=math.clamp((ax-track.AbsolutePosition.X)/trackW,0,1); local v=math.floor(minV+t*(maxV-minV)+0.5); local f2=(v-minV)/(maxV-minV); fill.Size=UDim2.new(f2,0,1,0); knob.Position=UDim2.new(f2,0,0.5,0); valLbl.Text=tostring(v); onCh(v) end
	track.InputBegan:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 then sd=true; apply(i.Position.X) end end)
	UserInputService.InputEnded:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 then sd=false end end)
	UserInputService.InputChanged:Connect(function(i) if sd and i.UserInputType==Enum.UserInputType.MouseMovement then apply(i.Position.X) end end)
end

local function buildKeybind(parent,labelText,currentKey,onChange)
	local row=Instance.new("Frame"); row.Size=UDim2.new(1,0,0,28); row.BackgroundTransparency=1; row.Parent=parent
	local label=Instance.new("TextLabel"); label.Text=labelText; label.Font=FONTS.label; label.TextSize=12; label.TextColor3=COLORS.labelOff; label.TextXAlignment=Enum.TextXAlignment.Left; label.TextYAlignment=Enum.TextYAlignment.Center; label.BackgroundTransparency=1; label.Size=UDim2.new(0.5,-5,1,0); label.Parent=row
	local keyButton=Instance.new("TextButton"); keyButton.Text=currentKey or "Click to bind"; keyButton.Font=FONTS.label; keyButton.TextSize=11; keyButton.TextColor3=COLORS.title; keyButton.BackgroundColor3=COLORS.titleBox; keyButton.Size=UDim2.new(0.4,0,1,0); keyButton.Position=UDim2.new(0.5,5,0,0); keyButton.Parent=row; corner(keyButton,4); stroke(keyButton,COLORS.divider,1)
	local isListening=false
	keyButton.MouseButton1Click:Connect(function()
		if isListening then return end; isListening=true; keyButton.Text="Press any key..."; keyButton.TextColor3=COLORS.accent
		startKeybindCapture(function(inputType,displayName,enumValue)
			isListening=false
			if inputType=="Mouse" then keyButton.Text=displayName; cfg.aimbotButton=enumValue; cfg.aimbotKeybind=displayName
			elseif inputType=="Keyboard" then keyButton.Text=displayName; cfg.aimbotButton=enumValue; cfg.aimbotKeybind=displayName end
			keyButton.TextColor3=COLORS.title
			if features.FakeAimbot.enabled then stopFeature("FakeAimbot"); fakeaimbot_start() end
			if onChange then onChange() end
		end)
		task.delay(5,function() if isListening then isListening=false; keyButton.Text=currentKey or "Click to bind"; keyButton.TextColor3=COLORS.title end end)
	end)
	return keyButton
end

----------------------------------------------------------------------
-- PANEL BUILDER
----------------------------------------------------------------------
function makePanel(colIndex,def)
	local col=columns[colIndex]
	local panel=Instance.new("Frame"); panel.Size=UDim2.new(1,0,0,0); panel.AutomaticSize=Enum.AutomaticSize.Y; panel.BackgroundColor3=COLORS.panel; panel.BorderSizePixel=0; panel.Parent=col
	corner(panel,SIZES.corner); stroke(panel,COLORS.panelStroke,1); vlist(panel,10)
	local header=Instance.new("Frame"); header.BackgroundColor3=COLORS.titleBox; header.BorderSizePixel=0; header.Size=UDim2.new(1,0,0,SIZES.titleH); header.LayoutOrder=1; header.Parent=panel
	stroke(header,COLORS.divider,1); new("UIPadding",{PaddingLeft=UDim.new(0,10),Parent=header})
	local headerLabel=Instance.new("TextLabel"); headerLabel.Text=def.title; headerLabel.Font=FONTS.title; headerLabel.TextSize=14; headerLabel.TextColor3=COLORS.title; headerLabel.TextXAlignment=Enum.TextXAlignment.Left; headerLabel.TextYAlignment=Enum.TextYAlignment.Center; headerLabel.BackgroundTransparency=1; headerLabel.Size=UDim2.fromScale(1,1); headerLabel.Parent=header
	local rows=Instance.new("Frame"); rows.Size=UDim2.new(1,0,0,0); rows.AutomaticSize=Enum.AutomaticSize.Y; rows.BackgroundTransparency=1; rows.LayoutOrder=2; rows.Parent=panel
	padding(rows,SIZES.panelPad); vlist(rows,SIZES.rowGap)
	for i,item in ipairs(def.items) do
		local rowH=SIZES.rowH
		if item.slider then rowH=SIZES.rowH+28 end
		if item.type=="keybind" then rowH=28 end
		if item.type=="dropdown" then rowH=30 end
		local row=Instance.new("Frame"); row.Size=UDim2.new(1,0,0,rowH); row.BackgroundTransparency=1; row.Parent=rows
		if item.type=="toggle" then
			local toggleRow=Instance.new("Frame"); toggleRow.Size=UDim2.new(1,0,0,SIZES.rowH); toggleRow.BackgroundTransparency=1; toggleRow.Parent=row
			local box=Instance.new("Frame"); box.AnchorPoint=Vector2.new(0,0.5); box.Position=UDim2.new(0,0,0.5,0); box.Size=UDim2.fromOffset(SIZES.checkbox,SIZES.checkbox); box.BackgroundColor3=COLORS.checkOff; box.BorderSizePixel=0; box.Parent=toggleRow; corner(box,5)
			local boxStroke=stroke(box,COLORS.checkOffStroke,1)
			local check=Instance.new("TextLabel"); check.Text="\u{2714}"; check.Font=Enum.Font.GothamBlack; check.TextSize=14; check.TextColor3=COLORS.check; check.BackgroundTransparency=1; check.Size=UDim2.fromScale(1,1); check.Parent=box
			local label=Instance.new("TextLabel"); label.Text=item.label; label.Font=FONTS.label; label.TextSize=14; label.TextColor3=COLORS.labelOff; label.TextXAlignment=Enum.TextXAlignment.Left; label.TextYAlignment=Enum.TextYAlignment.Center; label.BackgroundTransparency=1; label.Position=UDim2.new(0,SIZES.labelStartX,0,0); label.Size=UDim2.new(1,-SIZES.labelStartX-22,1,0); label.Parent=toggleRow
			if item.hint then
				local override=keybindOverrides[item.key]
				local keyName="auto"; local mode="auto"
				if override then if override.key then keyName=getKeyNameFromEnum(override.key) end; mode=override.mode or "auto" end
				local hint=Instance.new("TextLabel"); hint.Text=string.format("[%s|%s]",keyName,mode); hint.Font=FONTS.label; hint.TextSize=11; hint.TextColor3=COLORS.keybind; hint.TextXAlignment=Enum.TextXAlignment.Right; hint.TextYAlignment=Enum.TextYAlignment.Center; hint.BackgroundTransparency=1; hint.Position=UDim2.new(1,-80,0,0); hint.Size=UDim2.new(0,70,1,0); hint.Parent=toggleRow; hint.ZIndex=20
				local hintButton=Instance.new("TextButton"); hintButton.Text=""; hintButton.BackgroundTransparency=1; hintButton.Size=UDim2.fromScale(1,1); hintButton.AutoButtonColor=false; hintButton.Parent=hint; hintButton.ZIndex=21
				hintButton.MouseButton2Click:Connect(function(x,y)
					local currentKey=override and override.key; local currentMode=override and override.mode or "auto"
					createContextMenu(item.key,currentKey,currentMode,Vector2.new(x,y))
				end)
			end
			local button=Instance.new("TextButton"); button.Text=""; button.BackgroundTransparency=1; button.Size=UDim2.fromScale(1,1); button.AutoButtonColor=false; button.Parent=toggleRow
			local localState=item.init==true
			local function getState() if item.key and features[item.key] then return features[item.key].enabled end; return localState end
			local function render()
				local on=getState(); box.BackgroundColor3=on and COLORS.accent or COLORS.checkOff; boxStroke.Enabled=not on; check.Visible=on; check.TextColor3=Color3.fromRGB(255,255,255); label.TextColor3=on and COLORS.labelOn or COLORS.labelOff
			end
			local function setState(on)
				if item.key and features[item.key] then if features[item.key].enabled~=on then toggleFeature(item.key) end else localState=on end
				render(); if item.onToggle then item.onToggle(on) end
			end
			render()
			button.MouseButton1Click:Connect(function() setState(not getState()) end)
			if item.slider then buildSlider(row,0,SIZES.rowH+2,item.sliderLabel or "value",item.min,item.max,item.init,90,item.onChange) end
		elseif item.type=="dropdown" then
			buildDropdown(row, item.label, item.options, item.default, function(val)
				if item.onChange then item.onChange(val) end
			end)
			row.Size = UDim2.new(1, 0, 0, 0)
			row.AutomaticSize = Enum.AutomaticSize.Y
		elseif item.type=="keybind" then
			buildKeybind(row,item.label,item.currentKey or "MouseButton2")
		elseif item.type=="label" then
			local l=Instance.new("TextLabel"); l.Text=item.text; l.Font=FONTS.label; l.TextSize=14; l.TextColor3=COLORS.labelOff; l.BackgroundTransparency=1; l.Size=UDim2.new(1,0,0,20); l.Parent=row
		end
	end
end

----------------------------------------------------------------------
-- TAB PANEL DEFINITIONS
----------------------------------------------------------------------
local MOVEMENT_MAIN_SECTIONS = {
	{col=1, title="general", items={
		{type="toggle",label="auto bunnyhop",  key="AutoBhop",   hint="[space]",slider=true,sliderLabel="boost",min=1,max=100,init=math.floor(cfg.bhopBoost*10+0.5),onChange=function(v) cfg.bhopBoost=v/10 end},
		{type="toggle",label="auto pixelsurf", key="PixelSurf",  hint="auto",   slider=true,sliderLabel="speed",min=20,max=200,init=cfg.pixelMaxSpeed,onChange=function(v) cfg.pixelMaxSpeed=v end},
		{type="toggle",label="auto texturebug",key="TextureBug", hint="auto",   slider=true,sliderLabel="speed",min=20,max=200,init=cfg.textureMaxSpeed,onChange=function(v) cfg.textureMaxSpeed=v end},
		{type="toggle",label="mini jump",      key="MiniJump",   hint="[c]",    slider=true,sliderLabel="power",min=5,max=80,init=cfg.miniJumpPower,onChange=function(v) cfg.miniJumpPower=v end},
		{type="toggle",label="long jump",      key="LongJump",   hint="[e]",    slider=true,sliderLabel="power",min=20,max=200,init=cfg.longJumpPower,onChange=function(v) cfg.longJumpPower=v end},
		{type="toggle",label="jump bug",       key="JumpBug",    hint="[q]",    slider=true,sliderLabel="power",min=10,max=200,init=cfg.jumpBugPower,onChange=function(v) cfg.jumpBugPower=v end},
	}},
	{col=1, title="strafe", items={{type="label",text="coming soon.."}}},
	{col=2, title="other",   items={{type="toggle",label="auto wallstuck",key="dummy1"},{type="toggle",label="auto wallhop",key="dummy2"}}},
	{col=2, title="utility", items={{type="label",text="venthop assist (soon)"}}},
}
local RECORDER_SOON={{col=1,title="recorder",items={{type="label",text="soon"}}}}

TAB_PANELS = {
	aimbot = {
		main = {
			{col=1, title="aimbot", items={
				{type="toggle",label="aimbot",key="FakeAimbot",slider=true,sliderLabel="smooth",min=1,max=100,init=cfg.aimbotSmooth,onChange=function(v) cfg.aimbotSmooth=v end},
				{type="toggle",label="fov",key="fovToggle",slider=true,sliderLabel="fov",min=1,max=360,init=cfg.aimbotFOV,onChange=function(v) cfg.aimbotFOV=v end},
				{type="keybind",label="keybind",currentKey=cfg.aimbotKeybind or "MouseButton2"},
				{type="toggle",label="fov view",key="fovView"},
				{type="label",text="change aimbot part (soon)"},
			}},
			{col=2, title="no spread", items={
				{type="toggle",label="no-spread",key="noSpread",onToggle=function(v) toggleNoSpreadFunc(v) end},
				{type="toggle",label="min spread",key="_nsMin",slider=true,sliderLabel="min",min=1,max=20,init=cfg.noSpreadMin,onChange=function(v) cfg.noSpreadMin=v end},
				{type="toggle",label="max spread",key="_nsMax",slider=true,sliderLabel="max",min=5,max=50,init=cfg.noSpreadMax,onChange=function(v) cfg.noSpreadMax=v end},
			}},
		}
	},
	visuals = {
		enemy = {
			{col=1, title="enemy", items={{type="toggle",label="esp",key="espToggle",onToggle=function(v) toggleESP(v) end}}}
		}
	},
	misc = {
		hud = {
			{col=1, title="hud", items={
				{type="toggle",label="watermark",      key="wm",       init=true, onToggle=function(v) wmFrame.Visible=v end},
				{type="toggle",label="larp watermark", key="larp",                onToggle=function(v) toggleLarpWatermark(v) end},
				{type="toggle",label="momentum",       key="mom",                 onToggle=function(v) toggleMomentum(v) end},
			}},
			{col=2, title="random", items={
				{type="toggle", label="spinbot", key="Spinbot"},
				{type="dropdown", label="mode", options={"Body Only","Head Only","Both"}, default=cfg.spinMode, onChange=function(val)
					cfg.spinMode = val
					if features.Spinbot.enabled then
						spinbot_stop()
						spinbot_start()
					end
				end},
				{type="toggle", label="speed", key="_spinSpeed", slider=true, sliderLabel="deg/s", min=60, max=2000, init=cfg.spinSpeed, onChange=function(v) cfg.spinSpeed = v end},
				{type="toggle", label="hud remover", key="hudRemove", onToggle=function(v) setHudRemoved(v) end},
			}},
		}
	},
	inventory = {
		skinchanger={{col=1,title="skinchanger",items={}}}
	},
	config = {
		soon={{col=1,title="soon",items={{type="label",text="soon"}}}}
	},
}

----------------------------------------------------------------------
-- SKIN PANEL
----------------------------------------------------------------------
local function refreshSkinList(skinListHolder, currentGunLabel)
	for _,child in ipairs(skinListHolder:GetChildren()) do if child:IsA("Frame") then child:Destroy() end end
	local gunName=getEquippedGunName()
	if gunName then currentGunLabel.Text="current: "..gunName else currentGunLabel.Text="no weapon equipped"; return end
	local gunSkins=ReplicatedStorage:FindFirstChild("Skins") and ReplicatedStorage.Skins:FindFirstChild(gunName)
	if not gunSkins then currentGunLabel.Text=gunName.." (no skins)"; return end
	local defWrap=Instance.new("Frame"); defWrap.Size=UDim2.new(1,0,0,28); defWrap.BackgroundColor3=COLORS.panel; defWrap.BorderSizePixel=0; defWrap.ZIndex=3; defWrap.Parent=skinListHolder
	local defLbl=Instance.new("TextLabel"); defLbl.Text="default"; defLbl.Font=FONTS.label; defLbl.TextSize=11; defLbl.TextColor3=(skinSelections[gunName]==nil) and COLORS.accent or COLORS.labelOff; defLbl.TextXAlignment=Enum.TextXAlignment.Left; defLbl.BackgroundTransparency=1; defLbl.Size=UDim2.new(1,-16,1,0); defLbl.Position=UDim2.new(0,8,0,0); defLbl.ZIndex=4; defLbl.Parent=defWrap
	local defBtn=Instance.new("TextButton"); defBtn.Text=""; defBtn.BackgroundTransparency=1; defBtn.Size=UDim2.fromScale(1,1); defBtn.AutoButtonColor=false; defBtn.Parent=defWrap
	defBtn.MouseButton1Click:Connect(function() skinSelections[gunName]=nil; startSkinLoop(); refreshSkinList(skinListHolder,currentGunLabel) end)
	for _,skin in ipairs(gunSkins:GetChildren()) do
		local wrap=Instance.new("Frame"); wrap.Size=UDim2.new(1,0,0,28); wrap.BackgroundColor3=COLORS.panel; wrap.BorderSizePixel=0; wrap.ZIndex=3; wrap.Parent=skinListHolder
		local sel=skinSelections[gunName]; local isSelected=(sel==skin.Name)
		local lbl=Instance.new("TextLabel"); lbl.Text=skin.Name; lbl.Font=FONTS.label; lbl.TextSize=11; lbl.TextColor3=isSelected and COLORS.accent or COLORS.labelOff; lbl.TextXAlignment=Enum.TextXAlignment.Left; lbl.BackgroundTransparency=1; lbl.Size=UDim2.new(1,-16,1,0); lbl.Position=UDim2.new(0,8,0,0); lbl.ZIndex=4; lbl.Parent=wrap
		local btn=Instance.new("TextButton"); btn.Text=""; btn.BackgroundTransparency=1; btn.Size=UDim2.fromScale(1,1); btn.AutoButtonColor=false; btn.Parent=wrap
		btn.MouseButton1Click:Connect(function() skinSelections[gunName]=skin.Name; startSkinLoop(); refreshSkinList(skinListHolder,currentGunLabel) end)
	end
end

local function buildSkinPanel(colIndex)
	local col=columns[colIndex]
	local panel=Instance.new("Frame"); panel.Size=UDim2.new(1,0,0,0); panel.AutomaticSize=Enum.AutomaticSize.Y; panel.BackgroundColor3=COLORS.panel; panel.BorderSizePixel=0; panel.Parent=col
	corner(panel,SIZES.corner); stroke(panel,COLORS.panelStroke,1); vlist(panel,10)
	local header=Instance.new("Frame"); header.BackgroundColor3=COLORS.titleBox; header.BorderSizePixel=0; header.Size=UDim2.new(1,0,0,SIZES.titleH); header.LayoutOrder=1; header.Parent=panel
	stroke(header,COLORS.divider,1); new("UIPadding",{PaddingLeft=UDim.new(0,10),Parent=header})
	local headerLabel=Instance.new("TextLabel"); headerLabel.Text="skinchanger"; headerLabel.Font=FONTS.title; headerLabel.TextSize=14; headerLabel.TextColor3=COLORS.title; headerLabel.TextXAlignment=Enum.TextXAlignment.Left; headerLabel.TextYAlignment=Enum.TextYAlignment.Center; headerLabel.BackgroundTransparency=1; headerLabel.Size=UDim2.fromScale(1,1); headerLabel.Parent=header
	local rows=Instance.new("Frame"); rows.Size=UDim2.new(1,0,0,0); rows.AutomaticSize=Enum.AutomaticSize.Y; rows.BackgroundTransparency=1; rows.LayoutOrder=2; rows.Parent=panel; padding(rows,SIZES.panelPad); vlist(rows,SIZES.rowGap)
	local currentGunLabel=Instance.new("TextLabel"); currentGunLabel.Text="no weapon equipped"; currentGunLabel.Font=FONTS.label; currentGunLabel.TextSize=11; currentGunLabel.TextColor3=COLORS.labelOff; currentGunLabel.BackgroundTransparency=1; currentGunLabel.Size=UDim2.new(1,0,0,20); currentGunLabel.Parent=rows
	local skinListHolder=Instance.new("Frame"); skinListHolder.Size=UDim2.new(1,0,0,0); skinListHolder.AutomaticSize=Enum.AutomaticSize.Y; skinListHolder.BackgroundTransparency=1; skinListHolder.Parent=rows; vlist(skinListHolder,2)
	local refreshBtn=Instance.new("TextButton"); refreshBtn.Text="refresh"; refreshBtn.Font=FONTS.label; refreshBtn.TextSize=11; refreshBtn.TextColor3=COLORS.title; refreshBtn.BackgroundColor3=COLORS.titleBox; refreshBtn.Size=UDim2.new(1,-20,0,28); refreshBtn.ZIndex=5; refreshBtn.Parent=rows; corner(refreshBtn,4)
	refreshBtn.MouseButton1Click:Connect(function() refreshSkinList(skinListHolder,currentGunLabel) end)
	refreshSkinList(skinListHolder,currentGunLabel)
end

----------------------------------------------------------------------
-- REBUILD CONTENT
----------------------------------------------------------------------
function rebuildContent(catName, subName)
	clearContent()
	columns[1]=makeColumn(1); columns[2]=makeColumn(2)
	if catName=="movement" then
		local sections; if subName=="main" then sections=MOVEMENT_MAIN_SECTIONS elseif subName=="recorder" then sections=RECORDER_SOON else return end
		for _,sec in ipairs(sections) do makePanel(sec.col,sec) end
	elseif catName=="inventory" and subName=="skinchanger" then
		buildSkinPanel(1)
	else
		local defs=TAB_PANELS[catName] and TAB_PANELS[catName][subName]
		if defs then for _,def in ipairs(defs) do makePanel(def.col,def) end end
	end
end

----------------------------------------------------------------------
-- DRAG
----------------------------------------------------------------------
local dragging,dragStart,dragOrigin=false,nil,nil
win.InputBegan:Connect(function(input)
	if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
		dragging=true; dragStart=input.Position; dragOrigin=win.Position
		input.Changed:Connect(function() if input.UserInputState==Enum.UserInputState.End then dragging=false end end)
	end
end)
UserInputService.InputChanged:Connect(function(input)
	if dragging and (input.UserInputType==Enum.UserInputType.MouseMovement or input.UserInputType==Enum.UserInputType.Touch) then
		local delta=input.Position-dragStart; win.Position=UDim2.new(dragOrigin.X.Scale,dragOrigin.X.Offset+delta.X,dragOrigin.Y.Scale,dragOrigin.Y.Offset+delta.Y)
	end
end)

----------------------------------------------------------------------
-- MENU TOGGLE & UNLOAD
----------------------------------------------------------------------
local menuOpen=false
local function setMenuOpen(open)
	menuOpen=open; win.Visible=open
	if open then UserInputService.MouseBehavior=Enum.MouseBehavior.Default; UserInputService.MouseIconEnabled=true
	else UserInputService.MouseBehavior=Enum.MouseBehavior.Default end
end
RunService.RenderStepped:Connect(function() if menuOpen then UserInputService.MouseBehavior=Enum.MouseBehavior.Default; UserInputService.MouseIconEnabled=true end end)

local unloadHeld={}
UserInputService.InputBegan:Connect(function(input,gpe)
	if not gpe and input.KeyCode==Enum.KeyCode.Insert then setMenuOpen(not menuOpen) end
	if not gpe then
		unloadHeld[input.KeyCode]=true
		if unloadHeld[Enum.KeyCode.U] and unloadHeld[Enum.KeyCode.O] then
			for key in pairs(features) do stopFeature(key) end
			toggleESP(false); stopSkinLoop(); toggleLarpWatermark(false); toggleMomentum(false)
			setHudRemoved(false)
			setFog(false); setBlur(false)
			if fogConn then fogConn:Disconnect() end; if blurConn then blurConn:Disconnect() end
			if noSpreadActive and currentSpreadFolder then restoreSpreadNS(currentSpreadFolder) end
			trailFolder:Destroy(); screenGui:Destroy()
			UserInputService.MouseBehavior=Enum.MouseBehavior.Default; UserInputService.MouseIconEnabled=true
		end
	end
end)
UserInputService.InputEnded:Connect(function(input) unloadHeld[input.KeyCode]=nil end)

----------------------------------------------------------------------
-- RESPAWN
----------------------------------------------------------------------
player.CharacterAdded:Connect(function(char)
	bindCharacter(char); task.wait(0.5)
	if noSpreadActive then
		if currentSpreadFolder then restoreSpreadNS(currentSpreadFolder) end
		currentSpreadFolder = getCurrentSpreadFolder()
		if currentSpreadFolder then saveOriginalsNS(currentSpreadFolder) end
	end
	originalNeckC0=nil
	for key,f in pairs(features) do if f.enabled then
		local restart=nil
		if     key=="PixelSurf"  then restart=function() makeSurf(key,Vector3.new(0,0,0),   function() return cfg.pixelMaxSpeed   end) end
		elseif key=="TextureBug" then restart=function() makeSurf(key,Vector3.new(0,2.5,0), function() return cfg.textureMaxSpeed end) end
		elseif key=="AutoBhop"   then restart=bhop_start
		elseif key=="JumpBug"    then restart=jumpbug_start
		elseif key=="LongJump"   then restart=longjump_start
		elseif key=="MiniJump"   then restart=minijump_start
		elseif key=="FakeAimbot" then restart=fakeaimbot_start
		elseif key=="Spinbot"    then restart=spinbot_start
		end
		if restart then if key=="Spinbot" then spinbot_stop(); spinbot_start() else f.conn=restart() end end
	end end
	if espEnabled then refreshESP() end
	if momentumEnabled then toggleMomentum(false); toggleMomentum(true) end
	if hudRemoved then
		task.wait(1)
		setHudRemoved(true)
	end
end)

----------------------------------------------------------------------
-- INIT
----------------------------------------------------------------------
selectCategory("movement")
startSkinLoop()
