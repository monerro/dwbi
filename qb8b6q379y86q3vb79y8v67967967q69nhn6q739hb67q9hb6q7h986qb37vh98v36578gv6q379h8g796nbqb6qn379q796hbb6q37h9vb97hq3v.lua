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
	aimbotKeybind   = "MouseButton2", -- string representation for display
	fogEnd          = 200,
	blurSize        = 10,



}


local keybindOverrides = {
    AutoBhop   = { key = Enum.KeyCode.Space, mode = "auto" },    -- auto = always on when enabled
    PixelSurf  = { key = nil, mode = "auto" },                   -- auto = automatic
    TextureBug = { key = nil, mode = "auto" },
    MiniJump   = { key = Enum.KeyCode.C, mode = "hold" },        -- hold = only when key is held
    LongJump   = { key = Enum.KeyCode.E, mode = "toggle" },      -- toggle = press to toggle
    JumpBug    = { key = Enum.KeyCode.Q, mode = "hold" },
}

local function getKeyNameFromEnum(keyEnum)
    if not keyEnum then return "auto" end
    return keyEnum.Name
end


local ESP_CFG = {
	skeleton_color         = Color3.fromRGB(0, 255, 0),
	crouch_color           = Color3.fromRGB(255, 0, 0),
	skeleton_thickness     = 2,
	skeleton_transparency  = 1,
	crouch_detection       = true,
	crouch_height_threshold = 2,
	box_enabled            = true,
	box_color              = Color3.fromRGB(255, 255, 255),
	box_thickness          = 2,
	box_filled             = false,
	box_fill_color         = Color3.fromRGB(255, 255, 255),
	box_fill_transparency  = 0.2,
	healthbar_enabled      = true,
	healthbar_color_high   = Color3.fromRGB(0, 255, 0),
	healthbar_color_low    = Color3.fromRGB(255, 0, 0),
	name_enabled           = true,
	name_color             = Color3.fromRGB(255, 255, 255),
	name_size              = 14,
	name_outline           = true,
	distance_enabled       = true,
	distance_color         = Color3.fromRGB(200, 200, 200),
	distance_size          = 12,
	tracer_enabled         = false,
	tracer_color           = Color3.fromRGB(255, 255, 255),
	tracer_thickness       = 1,
	tracer_transparency    = 1,
	tracer_from            = "Bottom",
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
}
local espEnabled = false
local espConn = nil
local espObjects = {}
local crouching = {}
local skinSelections = {}
local skinOriginals = {}
local skinConn = nil

---- key inputs

local function getKeyName(inputType)
    if inputType == Enum.UserInputType.MouseButton1 then return "MouseButton1" end
    if inputType == Enum.UserInputType.MouseButton2 then return "MouseButton2" end
    if inputType == Enum.UserInputType.MouseButton3 then return "MouseButton3" end
    if inputType == Enum.UserInputType.Keyboard then return "Keyboard" end
    return "Unknown"
end

local function isMouseButton(inputType)
    return inputType == Enum.UserInputType.MouseButton1 or 
           inputType == Enum.UserInputType.MouseButton2 or 
           inputType == Enum.UserInputType.MouseButton3
end

local waitingForKeybind = false
local keybindCallback = nil

local function startKeybindCapture(callback)
    waitingForKeybind = true
    keybindCallback = callback
    -- Show a prompt or highlight the button
end

-- Add this to handle keybind capture
UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if waitingForKeybind and keybindCallback then
        local inputType = input.UserInputType
        if inputType == Enum.UserInputType.Keyboard then
            -- Keyboard key
            local keyName = input.KeyCode.Name
            keybindCallback("Keyboard", keyName, input.KeyCode)
        elseif isMouseButton(inputType) then
            -- Mouse button
            local keyName = getKeyName(inputType)
            keybindCallback("Mouse", keyName, inputType)
        end
        waitingForKeybind = false
        keybindCallback = nil
    end
end)

-- Add this after the keybind capture functions
local contextMenu = nil
local contextMenuTarget = nil

local function createContextMenu(featureKey, currentKey, currentMode, position)
    -- Destroy existing context menu
    if contextMenu then contextMenu:Destroy(); contextMenu = nil end
    
    contextMenu = Instance.new("Frame")
    contextMenu.Name = "ContextMenu"
    contextMenu.Size = UDim2.new(0, 180, 0, 0)
    contextMenu.AutomaticSize = Enum.AutomaticSize.Y
    contextMenu.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
    contextMenu.BorderSizePixel = 0
    contextMenu.ZIndex = 100
    contextMenu.Parent = screenGui
    corner(contextMenu, 6)
    stroke(contextMenu, Color3.fromRGB(40, 40, 50), 1)
    
    -- Position
    local absX = position.X
    local absY = position.Y
    local viewportSize = camera.ViewportSize
    if absX + 180 > viewportSize.X then absX = viewportSize.X - 180 end
    if absY + 200 > viewportSize.Y then absY = viewportSize.Y - 200 end
    contextMenu.Position = UDim2.new(0, absX, 0, absY)
    
    local menuLayout = Instance.new("UIListLayout")
    menuLayout.FillDirection = Enum.FillDirection.Vertical
    menuLayout.SortOrder = Enum.SortOrder.LayoutOrder
    menuLayout.Padding = UDim.new(0, 2)
    menuLayout.Parent = contextMenu
    
    local padding = Instance.new("UIPadding")
    padding.PaddingTop = UDim.new(0, 6)
    padding.PaddingBottom = UDim.new(0, 6)
    padding.PaddingLeft = UDim.new(0, 8)
    padding.PaddingRight = UDim.new(0, 8)
    padding.Parent = contextMenu
    
    -- Title
    local title = Instance.new("TextLabel")
    title.Text = "Keybind Settings"
    title.Font = FONTS.title
    title.TextSize = 12
    title.TextColor3 = COLORS.title
    title.BackgroundTransparency = 1
    title.Size = UDim2.new(1, 0, 0, 22)
    title.LayoutOrder = 0
    title.Parent = contextMenu
    
    -- Divider
    local divider = Instance.new("Frame")
    divider.Size = UDim2.new(1, -10, 0, 1)
    divider.Position = UDim2.new(0, 5, 0, 0)
    divider.BackgroundColor3 = COLORS.divider
    divider.BorderSizePixel = 0
    divider.LayoutOrder = 1
    divider.Parent = contextMenu
    
    -- Keybind row
    local keyRow = Instance.new("Frame")
    keyRow.Size = UDim2.new(1, 0, 0, 28)
    keyRow.BackgroundTransparency = 1
    keyRow.LayoutOrder = 2
    keyRow.Parent = contextMenu
    
    local keyLabel = Instance.new("TextLabel")
    keyLabel.Text = "Key:"
    keyLabel.Font = FONTS.label
    keyLabel.TextSize = 11
    keyLabel.TextColor3 = COLORS.labelOff
    keyLabel.BackgroundTransparency = 1
    keyLabel.Size = UDim2.new(0.4, 0, 1, 0)
    keyLabel.TextXAlignment = Enum.TextXAlignment.Left
    keyLabel.Parent = keyRow
    
    local keyButton = Instance.new("TextButton")
    keyButton.Text = currentKey and getKeyNameFromEnum(currentKey) or "auto"
    keyButton.Font = FONTS.label
    keyButton.TextSize = 11
    keyButton.TextColor3 = COLORS.title
    keyButton.BackgroundColor3 = COLORS.titleBox
    keyButton.Size = UDim2.new(0.55, 0, 1, 0)
    keyButton.Position = UDim2.new(0.45, 0, 0, 0)
    keyButton.Parent = keyRow
    corner(keyButton, 4)
    
    -- Mode row
    local modeRow = Instance.new("Frame")
    modeRow.Size = UDim2.new(1, 0, 0, 28)
    modeRow.BackgroundTransparency = 1
    modeRow.LayoutOrder = 3
    modeRow.Parent = contextMenu
    
    local modeLabel = Instance.new("TextLabel")
    modeLabel.Text = "Mode:"
    modeLabel.Font = FONTS.label
    modeLabel.TextSize = 11
    modeLabel.TextColor3 = COLORS.labelOff
    modeLabel.BackgroundTransparency = 1
    modeLabel.Size = UDim2.new(0.4, 0, 1, 0)
    modeLabel.TextXAlignment = Enum.TextXAlignment.Left
    modeLabel.Parent = modeRow
    
    local modeDropdown = Instance.new("TextButton")
    modeDropdown.Text = currentMode or "auto"
    modeDropdown.Font = FONTS.label
    modeDropdown.TextSize = 11
    modeDropdown.TextColor3 = COLORS.title
    modeDropdown.BackgroundColor3 = COLORS.titleBox
    modeDropdown.Size = UDim2.new(0.55, 0, 1, 0)
    modeDropdown.Position = UDim2.new(0.45, 0, 0, 0)
    modeDropdown.Parent = modeRow
    corner(modeDropdown, 4)
    
    -- Mode options (hidden by default)
    local modeOptions = Instance.new("Frame")
    modeOptions.Size = UDim2.new(0.55, 0, 0, 0)
    modeOptions.AutomaticSize = Enum.AutomaticSize.Y
    modeOptions.BackgroundColor3 = COLORS.panel
    modeOptions.BorderSizePixel = 0
    modeOptions.Position = UDim2.new(0.45, 0, 0, 28)
    modeOptions.ZIndex = 101
    modeOptions.Visible = false
    modeOptions.Parent = modeRow
    corner(modeOptions, 4)
    stroke(modeOptions, COLORS.divider, 1)
    
    local modeList = Instance.new("UIListLayout")
    modeList.FillDirection = Enum.FillDirection.Vertical
    modeList.Padding = UDim.new(0, 1)
    modeList.Parent = modeOptions
    
    local modes = {"auto", "toggle", "hold"}
    for _, mode in ipairs(modes) do
        local opt = Instance.new("TextButton")
        opt.Text = mode
        opt.Font = FONTS.label
        opt.TextSize = 11
        opt.TextColor3 = mode == currentMode and COLORS.accent or COLORS.labelOff
        opt.BackgroundColor3 = COLORS.titleBox
        opt.Size = UDim2.new(1, 0, 0, 22)
        opt.ZIndex = 102
        opt.Parent = modeOptions
        
        opt.MouseButton1Click:Connect(function()
            keybindOverrides[featureKey].mode = mode
            modeDropdown.Text = mode
            modeOptions.Visible = false
            -- Update the hint text in the UI
            updateFeatureHint(featureKey)
            if contextMenu then contextMenu:Destroy(); contextMenu = nil end
        end)
    end
    
    -- Toggle mode options visibility
    modeDropdown.MouseButton1Click:Connect(function()
        modeOptions.Visible = not modeOptions.Visible
        -- Resize context menu to fit
        contextMenu.AutomaticSize = Enum.AutomaticSize.Y
    end)
    
    -- Keybind capture
    keyButton.MouseButton1Click:Connect(function()
        keyButton.Text = "Press key..."
        keyButton.TextColor3 = COLORS.accent
        
        startKeybindCapture(function(inputType, displayName, enumValue)
            keyButton.Text = displayName
            keyButton.TextColor3 = COLORS.title
            keybindOverrides[featureKey].key = enumValue
            updateFeatureHint(featureKey)
            if contextMenu then contextMenu:Destroy(); contextMenu = nil end
        end)
        
        task.delay(5, function()
            if keyButton.Text == "Press key..." then
                keyButton.Text = currentKey and getKeyNameFromEnum(currentKey) or "auto"
                keyButton.TextColor3 = COLORS.title
            end
        end)
    end)
    
    -- Click outside to close
    local function closeMenu()
        if contextMenu then contextMenu:Destroy(); contextMenu = nil end
    end
    
    -- Close when clicking outside
    local connection
    connection = UserInputService.InputBegan:Connect(function(input, gpe)
        if gpe then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1 or 
           input.UserInputType == Enum.UserInputType.MouseButton2 then
            local mousePos = Vector2.new(input.Position.X, input.Position.Y)
            if contextMenu and contextMenu.Parent then
                local absPos = contextMenu.AbsolutePosition
                local size = contextMenu.AbsoluteSize
                if mousePos.X < absPos.X or mousePos.X > absPos.X + size.X or
                   mousePos.Y < absPos.Y or mousePos.Y > absPos.Y + size.Y then
                    closeMenu()
                    connection:Disconnect()
                end
            end
        end
    end)
end

-- Function to update feature hint text
local function updateFeatureHint(featureKey)
    -- Find the hint label for this feature and update it
    local override = keybindOverrides[featureKey]
    if not override then return end
    
    local keyName = override.key and getKeyNameFromEnum(override.key) or "auto"
    local mode = override.mode or "auto"
    
    -- Update the hint text in the UI
    -- We need to find the specific toggle row and update its hint
    for _, col in pairs(columns) do
        for _, panel in pairs(col:GetChildren()) do
            if panel:IsA("Frame") then
                for _, row in pairs(panel:GetDescendants()) do
                    if row:IsA("TextLabel") and row.Text and row.Text:match("^%[") then
                        -- This is a hint label, check if it belongs to our feature
                        -- We'll rebuild the content to refresh hints
                        if activeCategory then
                            local sub = activeSub or "main"
                            if activeCategory == "movement" then
                                rebuildContent("movement", sub)
                            end
                        end
                        return
                    end
                end
            end
        end
    end
    -- If we can't find the hint, just rebuild the content
    if activeCategory then
        local sub = activeSub or "main"
        if activeCategory == "movement" then
            rebuildContent("movement", sub)
        end
    end
end

----------------------------------------------------------------------
-- CHARACTER & MOVEMENT LOGIC
----------------------------------------------------------------------
local character, humanoid, hrp
local function bindCharacter(char)
	character = char
	humanoid = char:WaitForChild("Humanoid")
	hrp = char:WaitForChild("HumanoidRootPart")
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
	Vector3.new( 1,0, 0), Vector3.new(-1,0, 0),
	Vector3.new( 0,0, 1), Vector3.new( 0,0,-1),
	Vector3.new( 1,0, 1).Unit, Vector3.new(-1,0, 1).Unit,
	Vector3.new( 1,0,-1).Unit, Vector3.new(-1,0,-1).Unit,
}

local function findWall(originOffset)
	PARAMS.FilterDescendantsInstances = {character}
	local up     = Vector3.new(0,1,0)
	local origin = hrp.Position + originOffset
	local vel    = hrp and hrp.AssemblyLinearVelocity or Vector3.zero
	local hVel   = Vector3.new(vel.X,0,vel.Z)
	for _, dir in ipairs(WALL_DIRS) do
		local hit = workspace:Raycast(origin, dir * WALL_RANGE, PARAMS)
		if not hit then continue end
		local n = hit.Normal
		if math.abs(n:Dot(up)) >= 0.43 then continue end
		local inst = hit.Instance
		if not inst:IsA("BasePart") then continue end
		if inst.Size.Y * 0.5 < 2.0 then continue end
		if hVel.Magnitude > 1 then
			if hVel.Unit:Dot(-n) < 0.1 then continue end
		end
		return n
	end
	return nil
end

-- Trail
local trailFolder = Instance.new("Folder")
trailFolder.Name = "DwbiTrail"; trailFolder.Parent = workspace
local segments = {}
local lastPos  = {PixelSurf=nil, TextureBug=nil}
local TRAIL_STEP = 1.2
local function spawnSegment(pos)
	local seg = Instance.new("Part")
	seg.Anchored=true; seg.CanCollide=false; seg.CanQuery=false; seg.CastShadow=false
	seg.Size=Vector3.new(TRAIL_WIDTH,TRAIL_WIDTH,TRAIL_WIDTH)
	seg.CFrame=CFrame.new(pos); seg.Material=Enum.Material.Neon
	seg.Color=Color3.new(1,1,1); seg.Transparency=0; seg.Parent=trailFolder
	table.insert(segments,{part=seg,born=tick()})
end
local function updateTrail(pos, active, key)
	local now=tick()
	if active then
		if not lastPos[key] or (pos-lastPos[key]).Magnitude>=TRAIL_STEP then
			spawnSegment(pos); lastPos[key]=pos
		end
	else lastPos[key]=nil end
	local i=1
	while i<=#segments do
		local s=segments[i]; local age=now-s.born
		if age>=TRAIL_LIFE then s.part:Destroy(); table.remove(segments,i)
		else s.part.Transparency=age/TRAIL_LIFE; i=i+1 end
	end
end

-- Surf
local function makeSurf(key, originOffset, getMaxSpeed)
	local f = features[key]
	f.conn = RunService.Heartbeat:Connect(function(dt)
		if not hrp or not humanoid then return end
		local state = humanoid:GetState()
		local airborne = state == Enum.HumanoidStateType.Freefall or state == Enum.HumanoidStateType.Jumping
		if not airborne then f.surfing=false; f.glideDir=nil; f.glideSpeed=0; updateTrail(hrp.Position, false, key); return end
		local wNormal = findWall(originOffset)
		if not wNormal then f.surfing=false; f.glideDir=nil; f.glideSpeed=0; updateTrail(hrp.Position, false, key); return end
		if f.surfing and (UserInputService:IsKeyDown(Enum.KeyCode.A) or UserInputService:IsKeyDown(Enum.KeyCode.D) or UserInputService:IsKeyDown(Enum.KeyCode.Left) or UserInputService:IsKeyDown(Enum.KeyCode.Right)) then
			f.surfing=false; f.glideDir=nil; f.glideSpeed=0; updateTrail(hrp.Position, false, key); return
		end
		local maxSpd = getMaxSpeed()
		if not f.surfing then
			f.surfing = true
			local look = hrp.CFrame.LookVector
			local proj = look - wNormal * look:Dot(wNormal)
			proj = Vector3.new(proj.X,0,proj.Z)
			f.glideDir = proj.Magnitude > 0.01 and proj.Unit or Vector3.new(-wNormal.Z,0,wNormal.X).Unit
			local vel = hrp.AssemblyLinearVelocity
			f.glideSpeed = math.min(math.max(Vector3.new(vel.X,0,vel.Z).Magnitude, BASE_SPEED), maxSpd)
		end
		f.glideSpeed = math.min(f.glideSpeed, maxSpd)
		if UserInputService:IsKeyDown(Enum.KeyCode.W) or UserInputService:IsKeyDown(Enum.KeyCode.Up) then
			f.glideSpeed = math.min(f.glideSpeed + W_ACCEL * dt, maxSpd)
		end
		hrp.AssemblyLinearVelocity = Vector3.new(f.glideDir.X * f.glideSpeed, 0, f.glideDir.Z * f.glideSpeed)
		humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
		updateTrail(hrp.Position + originOffset, true, key)
	end)
end

-- Bhop
-- Bhop
local function bhop_start()
    features.AutoBhop.conn = RunService.RenderStepped:Connect(function()
        if not humanoid or not hrp then return end
        
        local override = keybindOverrides.AutoBhop
        local mode = override and override.mode or "auto"
        local key = override and override.key or Enum.KeyCode.Space
        
        if not features.AutoBhop.enabled then return end
        
        if mode == "auto" then
            -- Auto mode: bhop works when holding space (normal bhop behavior)
            if UserInputService:IsKeyDown(key) then
                if humanoid.FloorMaterial ~= Enum.Material.Air then
                    humanoid.Jump = true
                else
                    local md = humanoid.MoveDirection
                    if md.Magnitude > 0 then
                        hrp.CFrame = hrp.CFrame + (md * cfg.bhopBoost)
                    end
                end
            end
        elseif mode == "hold" then
            -- Hold mode: only works when key is held (same as auto for bhop)
            if UserInputService:IsKeyDown(key) then
                if humanoid.FloorMaterial ~= Enum.Material.Air then
                    humanoid.Jump = true
                else
                    local md = humanoid.MoveDirection
                    if md.Magnitude > 0 then
                        hrp.CFrame = hrp.CFrame + (md * cfg.bhopBoost)
                    end
                end
            end
        elseif mode == "toggle" then
            -- Toggle mode: press key to toggle bhop on/off
            -- For simplicity, we'll keep it as hold for now
            if UserInputService:IsKeyDown(key) then
                if humanoid.FloorMaterial ~= Enum.Material.Air then
                    humanoid.Jump = true
                else
                    local md = humanoid.MoveDirection
                    if md.Magnitude > 0 then
                        hrp.CFrame = hrp.CFrame + (md * cfg.bhopBoost)
                    end
                end
            end
        end
    end)
end

-- JumpBug
local function jumpbug_start()
	features.JumpBug.conn=humanoid.StateChanged:Connect(function(_,new)
		if new==Enum.HumanoidStateType.Jumping and UserInputService:IsKeyDown(Enum.KeyCode.Q) then
			task.defer(function() if hrp then local vel=hrp.AssemblyLinearVelocity; hrp.AssemblyLinearVelocity=Vector3.new(vel.X,vel.Y+cfg.jumpBugPower,vel.Z) end end)
		end
	end)
end

-- LongJump
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

-- MiniJump
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

-- Fake Aimbot
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
    features.FakeAimbot.conn = RunService.RenderStepped:Connect(function(dt)
        local held = false
        local btn = cfg.aimbotButton
        
        if typeof(btn) == "EnumItem" then
            if btn.EnumType == Enum.UserInputType then
                held = UserInputService:IsMouseButtonPressed(btn)
            elseif btn.EnumType == Enum.KeyCode then
                held = UserInputService:IsKeyDown(btn)
            end
        end
        
        if not held then return end
        
        local head = getNearestHead()
        if not head then return end
        
        local dir = (head.Position - camera.CFrame.Position).Unit
        camera.CFrame = camera.CFrame:Lerp(
            CFrame.lookAt(camera.CFrame.Position, camera.CFrame.Position + dir), 
            math.min(dt * cfg.aimbotSmooth, 1)
        )
    end)
end
-- Stop/Toggle features
local function stopFeature(key)
	local f=features[key]; if f.conn then f.conn:Disconnect(); f.conn=nil end
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
		end
	else stopFeature(key) end
	refreshIndicators()
	return f.enabled
end

----------------------------------------------------------------------
-- ESP SYSTEM (Drawing library)
----------------------------------------------------------------------
local r15_bones = {
	{"Head", "UpperTorso"}, {"UpperTorso", "LowerTorso"},
	{"UpperTorso", "LeftUpperArm"}, {"LeftUpperArm", "LeftLowerArm"}, {"LeftLowerArm", "LeftHand"},
	{"UpperTorso", "RightUpperArm"}, {"RightUpperArm", "RightLowerArm"}, {"RightLowerArm", "RightHand"},
	{"LowerTorso", "LeftUpperLeg"}, {"LeftUpperLeg", "LeftLowerLeg"}, {"LeftLowerLeg", "LeftFoot"},
	{"LowerTorso", "RightUpperLeg"}, {"RightUpperLeg", "RightLowerLeg"}, {"RightLowerLeg", "RightFoot"}
}
local r6_bones = {
	{"Head", "Torso"}, {"Torso", "Left Arm"}, {"Torso", "Right Arm"},
	{"Torso", "Left Leg"}, {"Torso", "Right Leg"}
}
local custom_bones = {
	{"Head", "Torso"}, {"Torso", "Left Upper Arm"}, {"Left Upper Arm", "Left Lower Arm"}, {"Left Lower Arm", "Left Hand"},
	{"Torso", "Right Upper Arm"}, {"Right Upper Arm", "Right Lower Arm"}, {"Right Lower Arm", "Right Hand"},
	{"Torso", "Left Upper Leg"}, {"Left Upper Leg", "Left Lower Leg"}, {"Left Lower Leg", "Left Foot"},
	{"Torso", "Right Upper Leg"}, {"Right Upper Leg", "Right Lower Leg"}, {"Right Lower Leg", "Right Foot"}
}
local function w2s(pos) local vec, onscreen = camera:WorldToViewportPoint(pos); return Vector2.new(vec.X, vec.Y), onscreen end
local function create_line() local line = Drawing.new("Line"); line.Visible = false; line.Thickness = ESP_CFG.skeleton_thickness; line.Color = ESP_CFG.skeleton_color; line.Transparency = ESP_CFG.skeleton_transparency; return line end
local function create_text() local text = Drawing.new("Text"); text.Visible = false; text.Center = true; text.Outline = true; text.Font = 2; return text end
local function create_square() local square = Drawing.new("Square"); square.Visible = false; square.Filled = false; return square end
local function cl(p)
	if espObjects[p] then
		if espObjects[p].lines then for _, bone_data in pairs(espObjects[p].lines) do if bone_data.line then bone_data.line:Remove() end end end
		if espObjects[p].box then espObjects[p].box:Remove() end
		if espObjects[p].box_outline then espObjects[p].box_outline:Remove() end
		if espObjects[p].box_fill then espObjects[p].box_fill:Remove() end
		if espObjects[p].healthbar_bg then espObjects[p].healthbar_bg:Remove() end
		if espObjects[p].healthbar then espObjects[p].healthbar:Remove() end
		if espObjects[p].name then espObjects[p].name:Remove() end
		if espObjects[p].distance then espObjects[p].distance:Remove() end
		if espObjects[p].tracer then espObjects[p].tracer:Remove() end
		if espObjects[p].tracer_outline then espObjects[p].tracer_outline:Remove() end
		espObjects[p] = nil
	end
	crouching[p] = nil
end
local function rig(c) local h = c:FindFirstChildOfClass("Humanoid"); if h and h.RigType == Enum.HumanoidRigType.R15 then return r15_bones end; if c:FindFirstChild("Left Upper Arm") then return custom_bones end; return r6_bones end
local function makeESP(p)
	if not p:IsA("Player") or not espEnabled then return end
	if p.Team == player.Team and p.Team ~= nil then cl(p); return end
	cl(p); local c = p.Character; if not c then return end; local h = c:FindFirstChildOfClass("Humanoid"); if not h or h.Health <= 0 then return end; local hrp = c:FindFirstChild("HumanoidRootPart"); if not hrp then return end
	if ESP_CFG.crouch_detection then crouching[p] = h.HipHeight < ESP_CFG.crouch_height_threshold end
	local bones = rig(c); local lines = {}
	for _, bone in pairs(bones) do
		local part1 = c:FindFirstChild(bone[1]); local part2 = c:FindFirstChild(bone[2])
		if part1 and part2 then local line = create_line(); table.insert(lines, {line = line, p1 = part1, p2 = part2}) end
	end
	local box = ESP_CFG.box_enabled and create_square() or nil
	local box_outline = (ESP_CFG.box_enabled and ESP_CFG.box_thickness > 0) and create_square() or nil
	local box_fill = (ESP_CFG.box_enabled and ESP_CFG.box_filled) and create_square() or nil
	if box_outline then box_outline.Thickness = ESP_CFG.box_thickness + 1; box_outline.Color = Color3.new(0, 0, 0) end
	if box_fill then box_fill.Filled = true; box_fill.Color = ESP_CFG.box_fill_color; box_fill.Transparency = ESP_CFG.box_fill_transparency end
	local healthbar_bg = ESP_CFG.healthbar_enabled and create_square() or nil
	local healthbar = ESP_CFG.healthbar_enabled and create_square() or nil
	if healthbar_bg then healthbar_bg.Filled = true; healthbar_bg.Color = Color3.new(0, 0, 0); healthbar_bg.Transparency = 0.5 end
	if healthbar then healthbar.Filled = true end
	local name_text = ESP_CFG.name_enabled and create_text() or nil
	if name_text then name_text.Size = ESP_CFG.name_size; name_text.Color = ESP_CFG.name_color; name_text.Outline = ESP_CFG.name_outline end
	local distance_text = ESP_CFG.distance_enabled and create_text() or nil
	if distance_text then distance_text.Size = ESP_CFG.distance_size; distance_text.Color = ESP_CFG.distance_color; distance_text.Outline = true end
	local tracer = ESP_CFG.tracer_enabled and create_line() or nil
	local tracer_outline = (ESP_CFG.tracer_enabled and ESP_CFG.tracer_thickness > 1) and create_line() or nil
	if tracer then tracer.Thickness = ESP_CFG.tracer_thickness; tracer.Color = ESP_CFG.tracer_color; tracer.Transparency = ESP_CFG.tracer_transparency end
	if tracer_outline then tracer_outline.Thickness = ESP_CFG.tracer_thickness + 2; tracer_outline.Color = Color3.new(0, 0, 0); tracer_outline.Transparency = ESP_CFG.tracer_transparency * 0.5 end
	espObjects[p] = { lines = lines, character = c, humanoid = h, box = box, box_outline = box_outline, box_fill = box_fill, healthbar_bg = healthbar_bg, healthbar = healthbar, name = name_text, distance = distance_text, tracer = tracer, tracer_outline = tracer_outline }
end
local function get_character_bounds(c)
	local hrp = c:FindFirstChild("HumanoidRootPart"); if not hrp then return nil end
	local corners = {}; local size = hrp.Size; local cf = hrp.CFrame
	local offsets = {
		Vector3.new(size.X/2, size.Y/2, size.Z/2), Vector3.new(-size.X/2, size.Y/2, size.Z/2),
		Vector3.new(size.X/2, -size.Y/2, size.Z/2), Vector3.new(-size.X/2, -size.Y/2, size.Z/2),
		Vector3.new(size.X/2, size.Y/2, -size.Z/2), Vector3.new(-size.X/2, size.Y/2, -size.Z/2),
		Vector3.new(size.X/2, -size.Y/2, -size.Z/2), Vector3.new(-size.X/2, -size.Y/2, -size.Z/2)
	}
	for _, offset in ipairs(offsets) do
		local worldPos = cf:PointToWorldSpace(offset)
		local screenPos, onScreen = w2s(worldPos)
		if onScreen then table.insert(corners, screenPos) end
	end
	if #corners == 0 then return nil end
	local minX, maxX = math.huge, -math.huge; local minY, maxY = math.huge, -math.huge
	for _, corner in pairs(corners) do minX = math.min(minX, corner.X); maxX = math.max(maxX, corner.X); minY = math.min(minY, corner.Y); maxY = math.max(maxY, corner.Y) end
	return { topLeft = Vector2.new(minX, minY), size = Vector2.new(maxX - minX, maxY - minY), center = Vector2.new((minX + maxX) / 2, (minY + maxY) / 2) }
end
local function updateESP()
	for p, data in pairs(espObjects) do
		local c = data.character; local h = data.humanoid
		if not c or not c.Parent or not h or h.Health <= 0 then cl(p); continue end
		local hrp = c:FindFirstChild("HumanoidRootPart"); if not hrp then cl(p); continue end
		if ESP_CFG.crouch_detection and h then crouching[p] = h.HipHeight < ESP_CFG.crouch_height_threshold end
		local is_crouching = crouching[p]; local skel_color = is_crouching and ESP_CFG.crouch_color or ESP_CFG.skeleton_color
		if data.lines then
			for _, bone_data in pairs(data.lines) do
				local line = bone_data.line; local p1 = bone_data.p1; local p2 = bone_data.p2
				if p1 and p1.Parent and p2 and p2.Parent then
					local pos1, on1 = w2s(p1.Position); local pos2, on2 = w2s(p2.Position)
					if on1 and on2 then line.From = pos1; line.To = pos2; line.Color = skel_color; line.Thickness = ESP_CFG.skeleton_thickness; line.Transparency = ESP_CFG.skeleton_transparency; line.Visible = true else line.Visible = false end
				else line.Visible = false end
			end
		end
		local bounds = get_character_bounds(c)
		if bounds then
			if ESP_CFG.box_enabled and data.box then
				if data.box_outline then data.box_outline.Position = bounds.topLeft - Vector2.new(1, 1); data.box_outline.Size = bounds.size + Vector2.new(2, 2); data.box_outline.Visible = true end
				if data.box_fill then data.box_fill.Position = bounds.topLeft; data.box_fill.Size = bounds.size; data.box_fill.Visible = true end
				data.box.Position = bounds.topLeft; data.box.Size = bounds.size; data.box.Color = ESP_CFG.box_color; data.box.Thickness = ESP_CFG.box_thickness; data.box.Visible = true
			else
				if data.box then data.box.Visible = false end; if data.box_outline then data.box_outline.Visible = false end; if data.box_fill then data.box_fill.Visible = false end
			end
			if ESP_CFG.healthbar_enabled and data.healthbar and data.healthbar_bg then
				local barWidth = 3; local barHeight = bounds.size.Y; local healthPercent = h.Health / h.MaxHealth
				data.healthbar_bg.Position = Vector2.new(bounds.topLeft.X - barWidth - 3, bounds.topLeft.Y); data.healthbar_bg.Size = Vector2.new(barWidth, barHeight); data.healthbar_bg.Visible = true
				local currentHeight = barHeight * healthPercent
				data.healthbar.Position = Vector2.new(bounds.topLeft.X - barWidth - 3, bounds.topLeft.Y + barHeight - currentHeight); data.healthbar.Size = Vector2.new(barWidth, currentHeight)
				data.healthbar.Color = ESP_CFG.healthbar_color_high:Lerp(ESP_CFG.healthbar_color_low, 1 - healthPercent); data.healthbar.Visible = true
			else
				if data.healthbar then data.healthbar.Visible = false end; if data.healthbar_bg then data.healthbar_bg.Visible = false end
			end
			if ESP_CFG.name_enabled and data.name then data.name.Text = p.DisplayName; data.name.Position = Vector2.new(bounds.center.X, bounds.topLeft.Y - 15); data.name.Color = ESP_CFG.name_color; data.name.Size = ESP_CFG.name_size; data.name.Visible = true else if data.name then data.name.Visible = false end end
			if ESP_CFG.distance_enabled and data.distance then local dist = (hrp.Position - camera.CFrame.Position).Magnitude; data.distance.Text = string.format("%d studs", math.floor(dist)); data.distance.Position = Vector2.new(bounds.center.X, bounds.topLeft.Y + bounds.size.Y + 2); data.distance.Color = ESP_CFG.distance_color; data.distance.Size = ESP_CFG.distance_size; data.distance.Visible = true else if data.distance then data.distance.Visible = false end end
		else
			if data.box then data.box.Visible = false end; if data.box_outline then data.box_outline.Visible = false end; if data.box_fill then data.box_fill.Visible = false end
			if data.healthbar then data.healthbar.Visible = false end; if data.healthbar_bg then data.healthbar_bg.Visible = false end
			if data.name then data.name.Visible = false end; if data.distance then data.distance.Visible = false end
		end
		if ESP_CFG.tracer_enabled and data.tracer then
			local pos, onscreen = w2s(hrp.Position)
			if onscreen then
				local fromPos
				if ESP_CFG.tracer_from == "Bottom" then fromPos = Vector2.new(camera.ViewportSize.X / 2, camera.ViewportSize.Y)
				elseif ESP_CFG.tracer_from == "Middle" then fromPos = Vector2.new(camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2)
				elseif ESP_CFG.tracer_from == "Top" then fromPos = Vector2.new(camera.ViewportSize.X / 2, 0)
				elseif ESP_CFG.tracer_from == "Mouse" then fromPos = Vector2.new(mouse.X, mouse.Y) end
				if data.tracer_outline then data.tracer_outline.From = fromPos; data.tracer_outline.To = pos; data.tracer_outline.Visible = true end
				data.tracer.From = fromPos; data.tracer.To = pos; data.tracer.Color = ESP_CFG.tracer_color; data.tracer.Visible = true
			else
				data.tracer.Visible = false; if data.tracer_outline then data.tracer_outline.Visible = false end
			end
		else
			if data.tracer then data.tracer.Visible = false end; if data.tracer_outline then data.tracer_outline.Visible = false end
		end
	end
end
local function refreshESP()
	if not espEnabled then for _, p in pairs(Players:GetPlayers()) do cl(p) end return end
	for _, p in pairs(Players:GetPlayers()) do if p ~= player then makeESP(p) end end
end
local function toggleESP(enabled)
	espEnabled = enabled
	if enabled then refreshESP(); espConn = RunService.RenderStepped:Connect(updateESP)
	else if espConn then espConn:Disconnect(); espConn = nil end; for _, p in pairs(Players:GetPlayers()) do cl(p) end end
end
Players.PlayerAdded:Connect(function(p)
	if not espEnabled then return end
	p.CharacterAdded:Connect(function() task.wait(1); if p ~= player and espEnabled then makeESP(p) end end)
end)
Players.PlayerRemoving:Connect(function(p) if espEnabled then cl(p) end end)








----------------------------------------------------------------------
-- SKINS SYSTEM
----------------------------------------------------------------------
local function resolvePartName(skinEntryName) return skinEntryName:gsub("%s+", "") end
local function getEquippedGunName()
	local char = player.Character; if not char then return nil end
	local gun = char:FindFirstChild("Gun"); return gun and gun:GetAttribute("GunName")
end
local function getArms()
	local cam = workspace:FindFirstChild("Camera"); return cam and cam:FindFirstChild("Arms")
end
local function snapshotOriginals(gunName, arms)
	if skinOriginals[gunName] then return end
	local snap = {}; for _, p in ipairs(arms:GetChildren()) do if p:IsA("MeshPart") then snap[p.Name] = p.TextureID end end
	skinOriginals[gunName] = snap
end
local skinMapCache = {}
local function buildSkinMap(gunName, skinName)
	local gunSkins = ReplicatedStorage:FindFirstChild("Skins") and ReplicatedStorage.Skins:FindFirstChild(gunName)
	if not gunSkins then return nil end
	local skin = gunSkins:FindFirstChild(skinName); if not skin then return nil end
	local map = {}
	local function add(sv) if sv:IsA("StringValue") then map[sv.Name] = sv.Value; map[resolvePartName(sv.Name)] = sv.Value end end
	local wm = skin:FindFirstChild("WorldModel"); if wm then for _, sv in ipairs(wm:GetChildren()) do add(sv) end end
	for _, sv in ipairs(skin:GetChildren()) do add(sv) end
	return map
end
local function startSkinLoop()
	if skinConn then skinConn:Disconnect() end
	skinConn = RunService.RenderStepped:Connect(function()
		local arms = getArms(); if not arms then return end
		local gunName = getEquippedGunName(); if not gunName then return end
		snapshotOriginals(gunName, arms)
		local sel = skinSelections[gunName]
		if sel then
			local cacheKey = gunName .. "|" .. sel; local map = skinMapCache[cacheKey]
			if map == nil then map = buildSkinMap(gunName, sel) or false; skinMapCache[cacheKey] = map end
			if map then for _, p in ipairs(arms:GetChildren()) do if p:IsA("MeshPart") then local tex = map[p.Name] or map[resolvePartName(p.Name)]; if tex and p.TextureID ~= tex then p.TextureID = tex end end end end
		else
			local orig = skinOriginals[gunName]
			if orig then for _, p in ipairs(arms:GetChildren()) do if p:IsA("MeshPart") and orig[p.Name] and p.TextureID ~= orig[p.Name] then p.TextureID = orig[p.Name] end end end
		end
	end)
end
local function stopSkinLoop() if skinConn then skinConn:Disconnect(); skinConn = nil end end

----------------------------------------------------------------------
-- VISUALS (fog, blur)
----------------------------------------------------------------------
local Lighting = game:GetService("Lighting")
local origFogEnd   = Lighting.FogEnd
local origFogStart = Lighting.FogStart
local origFogColor = Lighting.FogColor
local blurEffect = nil
local fogConn, blurConn = nil, nil
local function setFog(enabled)
	if enabled then
		fogConn = RunService.Heartbeat:Connect(function() pcall(function() Lighting.FogEnd = cfg.fogEnd; Lighting.FogStart = math.max(0, cfg.fogEnd - 60); Lighting.FogColor = Color3.fromRGB(190, 190, 190) end) end)
	else
		if fogConn then fogConn:Disconnect(); fogConn = nil end; pcall(function() Lighting.FogEnd = origFogEnd; Lighting.FogStart = origFogStart; Lighting.FogColor = origFogColor end)
	end
end
local prevCamPos = nil
local function setBlur(enabled)
	if enabled then
		if not blurEffect then blurEffect = Instance.new("BlurEffect"); blurEffect.Size = 0; blurEffect.Parent = Lighting end
		prevCamPos = camera.CFrame.Position
		blurConn = RunService.RenderStepped:Connect(function()
			if not blurEffect then return end; local curPos = camera.CFrame.Position; local moved = (curPos - prevCamPos).Magnitude; local target = math.clamp(moved * cfg.blurSize, 0, 56)
			blurEffect.Size = blurEffect.Size + (target - blurEffect.Size) * 0.3; prevCamPos = curPos
		end)
	else
		if blurConn then blurConn:Disconnect(); blurConn = nil end; if blurEffect then blurEffect:Destroy(); blurEffect = nil end
	end
end

----------------------------------------------------------------------
-- LARP WATERMARK
----------------------------------------------------------------------
local larpWatermarkGui = nil; local larpWatermarkEnabled = false; local larpRenderConnection = nil
local function toggleLarpWatermark(enabled)
	larpWatermarkEnabled = enabled
	if enabled then
		if larpWatermarkGui then larpWatermarkGui:Destroy() end
		larpWatermarkGui = Instance.new("ScreenGui"); larpWatermarkGui.Name = "LarpWatermark"; larpWatermarkGui.ResetOnSpawn = false; larpWatermarkGui.IgnoreGuiInset = true; larpWatermarkGui.Parent = player:WaitForChild("PlayerGui")
		local mainFrame = Instance.new("Frame"); mainFrame.Size = UDim2.new(0, 149, 0, 28); mainFrame.AnchorPoint = Vector2.new(1, 0); mainFrame.Position = UDim2.new(1, -15, 0, 38); mainFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 25); mainFrame.BorderSizePixel = 0; mainFrame.ClipsDescendants = true; mainFrame.Parent = larpWatermarkGui
		local stroke = Instance.new("UIStroke"); stroke.Color = Color3.fromRGB(60, 60, 60); stroke.Thickness = 1.5; stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; stroke.Parent = mainFrame
		local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 8); corner.Parent = mainFrame
		local logoImage = Instance.new("ImageLabel"); logoImage.Size = UDim2.new(0, 63, 0, 63); logoImage.Position = UDim2.new(0, -15, 0.2, -25); logoImage.BackgroundTransparency = 1; logoImage.Image = "rbxassetid://133887132709020"; logoImage.ImageTransparency = 0.7; logoImage.ScaleType = Enum.ScaleType.Fit; logoImage.ZIndex = 1; logoImage.Parent = mainFrame
		local textLabel = Instance.new("TextLabel"); textLabel.Size = UDim2.new(1, -10, 1, 0); textLabel.Position = UDim2.new(0, 8, 0, 0); textLabel.BackgroundTransparency = 1; textLabel.Text = "larp | user | 0 fps"; textLabel.TextColor3 = Color3.fromRGB(255, 255, 255); textLabel.Font = Enum.Font.GothamMedium; textLabel.TextSize = 13; textLabel.TextXAlignment = Enum.TextXAlignment.Left; textLabel.ZIndex = 2; textLabel.RichText = true; textLabel.Parent = mainFrame
		local lastUpdate = tick(); local frameCount = 0; local fps = 0
		local function updateDisplay()
			frameCount = frameCount + 1; if tick() - lastUpdate >= 0.5 then fps = math.floor(frameCount / (tick() - lastUpdate)); frameCount = 0; lastUpdate = tick()
			textLabel.Text = string.format('<font color="rgb(79,144,85)" face="GothamBold">larp</font> <font color="rgb(80,80,80)">|</font> <font color="rgb(150,150,150)">%s</font> <font color="rgb(80,80,80)">|</font> <font face="GothamBold">%d</font> <font color="rgb(150,150,150)">fps</font>', player.Name, fps) end
		end
		larpRenderConnection = RunService.RenderStepped:Connect(updateDisplay)
	else
		if larpRenderConnection then larpRenderConnection:Disconnect(); larpRenderConnection = nil end
		if larpWatermarkGui then larpWatermarkGui:Destroy(); larpWatermarkGui = nil end
	end
end

----------------------------------------------------------------------
-- MOMENTUM TRACKER
----------------------------------------------------------------------
local momentumGui = nil; local momentumEnabled = false; local momentumConnection = nil; local jumpConnection = nil; local charConnection = nil
local function toggleMomentum(enabled)
	momentumEnabled = enabled
	if enabled then
		if momentumGui then momentumGui:Destroy() end
		momentumGui = Instance.new("ScreenGui"); momentumGui.Name = "ClarityMomentum"; momentumGui.ResetOnSpawn = false; momentumGui.IgnoreGuiInset = true; momentumGui.Parent = player:WaitForChild("PlayerGui")
		local textLabel = Instance.new("TextLabel"); textLabel.Size = UDim2.new(0, 400, 0, 50); textLabel.Position = UDim2.new(0.5, -200, 0.85, 0); textLabel.BackgroundTransparency = 1; textLabel.Text = "0 (0)"; textLabel.Font = Enum.Font.Nunito; textLabel.TextSize = 30; textLabel.TextColor3 = Color3.fromRGB(255, 255, 255); textLabel.ZIndex = 2; textLabel.RichText = true; textLabel.Parent = momentumGui
		local lastJumpSpeed = 0
		local function bindJump(char)
			if jumpConnection then jumpConnection:Disconnect() end; local hum = char:WaitForChild("Humanoid", 10)
			if hum then jumpConnection = hum.StateChanged:Connect(function(old, new) if new == Enum.HumanoidStateType.Jumping then local hrp = char:FindFirstChild("HumanoidRootPart"); if hrp then lastJumpSpeed = math.floor(Vector3.new(hrp.AssemblyLinearVelocity.X, 0, hrp.AssemblyLinearVelocity.Z).Magnitude) end end end) end
		end
		if player.Character then bindJump(player.Character) end; charConnection = player.CharacterAdded:Connect(bindJump)
		momentumConnection = RunService.RenderStepped:Connect(function()
			if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
				local hrp = player.Character.HumanoidRootPart; local vel = hrp.AssemblyLinearVelocity; local speed = math.floor(Vector3.new(vel.X, 0, vel.Z).Magnitude)
				local targetTransparency = 1 - math.clamp(speed / 15, 0, 1); if speed < 2 then targetTransparency = 1 end
				textLabel.TextTransparency = textLabel.TextTransparency + (targetTransparency - textLabel.TextTransparency) * 0.1
				textLabel.Text = string.format("%d (%d)", speed, lastJumpSpeed)
			end
		end)
	else
		if momentumConnection then momentumConnection:Disconnect(); momentumConnection = nil end; if jumpConnection then jumpConnection:Disconnect(); jumpConnection = nil end; if charConnection then charConnection:Disconnect(); charConnection = nil end
		if momentumGui then momentumGui:Destroy(); momentumGui = nil end
	end
end

----------------------------------------------------------------------
-- INDICATORS & WASD (outside menu)
----------------------------------------------------------------------
local screenGui = Instance.new("ScreenGui"); screenGui.Name = "ClarityMenu"; screenGui.ResetOnSpawn = false; screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Global; screenGui.DisplayOrder = 9999; screenGui.IgnoreGuiInset = true; screenGui.Parent = player:WaitForChild("PlayerGui")

-- Watermark
local wmFrame = Instance.new("Frame"); wmFrame.Size = UDim2.new(0,0,0,22); wmFrame.AutomaticSize = Enum.AutomaticSize.X; wmFrame.Position = UDim2.new(1,0,0,8); wmFrame.AnchorPoint = Vector2.new(1,0); wmFrame.BackgroundColor3 = Color3.fromRGB(10,10,12); wmFrame.BorderSizePixel = 0; wmFrame.ZIndex = 10; wmFrame.Parent = screenGui
Instance.new("UICorner", wmFrame).CornerRadius = UDim.new(0,4)
Instance.new("UIStroke", wmFrame).Color = Color3.fromRGB(30,30,38); Instance.new("UIStroke", wmFrame).Thickness = 1
local wmPad = Instance.new("UIPadding", wmFrame); wmPad.PaddingLeft = UDim.new(0,8); wmPad.PaddingRight = UDim.new(0,8)
local wmLayout = Instance.new("UIListLayout", wmFrame); wmLayout.FillDirection = Enum.FillDirection.Horizontal; wmLayout.VerticalAlignment = Enum.VerticalAlignment.Center; wmLayout.Padding = UDim.new(0,0)
local function wmPart(txt, col) local l = Instance.new("TextLabel"); l.Size = UDim2.new(0,0,1,0); l.AutomaticSize = Enum.AutomaticSize.X; l.BackgroundTransparency = 1; l.Text = txt; l.TextColor3 = col; l.Font = Enum.Font.GothamMedium; l.TextSize = 11; l.ZIndex = 11; l.Parent = wmFrame; return l end
local wmName  = wmPart("clarity", Color3.fromRGB(76,210,96)); local wmSep1 = wmPart(" | ", Color3.fromRGB(45,45,55)); local wmUser = wmPart(player.Name, Color3.fromRGB(230,230,230)); local wmSep2 = wmPart(" | ", Color3.fromRGB(45,45,55)); local wmFps = wmPart("0 fps", Color3.fromRGB(90,90,105))
local fpsCounter = 0; RunService.RenderStepped:Connect(function(dt) fpsCounter = fpsCounter + 1; if fpsCounter >= 10 then fpsCounter = 0; wmFps.Text = math.floor(1 / math.max(dt, 0.001) + 0.5).." fps" end end)

-- Indicator bar
local indBar = Instance.new("Frame"); indBar.Size = UDim2.new(0,0,0,22); indBar.AutomaticSize = Enum.AutomaticSize.X; indBar.Position = UDim2.new(0.5,0,1,-10); indBar.AnchorPoint = Vector2.new(0.5,1); indBar.BackgroundColor3 = Color3.fromRGB(10,10,12); indBar.BorderSizePixel = 0; indBar.ZIndex = 10; indBar.Parent = screenGui
Instance.new("UICorner", indBar).CornerRadius = UDim.new(0,4); Instance.new("UIStroke", indBar).Color = Color3.fromRGB(30,30,38); Instance.new("UIStroke", indBar).Thickness = 1
local ibLayout = Instance.new("UIListLayout", indBar); ibLayout.FillDirection = Enum.FillDirection.Horizontal; ibLayout.Padding = UDim.new(0,6)
local ibPad = Instance.new("UIPadding", indBar); ibPad.PaddingLeft = UDim.new(0,8); ibPad.PaddingRight = UDim.new(0,8); ibPad.PaddingTop = UDim.new(0,3); ibPad.PaddingBottom = UDim.new(0,3)
local IND_ORDER = {"ps","tb","lj","mj","jb","bh","amb"}
local IND_MAP   = {ps="PixelSurf",tb="TextureBug",lj="LongJump", mj="MiniJump",jb="JumpBug",bh="AutoBhop", amb="FakeAimbot"}
local indicatorLabels = {}
for i,tag in ipairs(IND_ORDER) do
	local key = IND_MAP[tag]; local l = Instance.new("TextLabel"); l.Size = UDim2.new(0,0,1,0); l.AutomaticSize = Enum.AutomaticSize.X; l.BackgroundTransparency = 1; l.Text = tag; l.TextColor3 = Color3.fromRGB(45,45,55); l.Font = Enum.Font.GothamMedium; l.TextSize = 11; l.LayoutOrder = i; l.ZIndex = 11; l.Parent = indBar; indicatorLabels[key] = l
end
refreshIndicators = function()
	for key, lbl in pairs(indicatorLabels) do
		local f = features[key]; if not f then continue end
		if not f.enabled then lbl.TextColor3 = Color3.fromRGB(45,45,55)
		elseif (key == "PixelSurf" or key == "TextureBug") and f.surfing then lbl.TextColor3 = Color3.fromRGB(76,210,96)
		else lbl.TextColor3 = Color3.fromRGB(230,230,230) end
	end
end
RunService.Heartbeat:Connect(refreshIndicators)

-- WASD keys
local WASD_KEY_SIZE = 20; local WASD_GAP = 2
local wasdBar = Instance.new("Frame"); wasdBar.AutomaticSize = Enum.AutomaticSize.XY; wasdBar.Position = UDim2.new(0.5, 0, 1, -38); wasdBar.AnchorPoint = Vector2.new(0.5, 1); wasdBar.BackgroundColor3 = Color3.fromRGB(10,10,12); wasdBar.BorderSizePixel = 0; wasdBar.ZIndex = 10; wasdBar.Parent = screenGui
Instance.new("UICorner", wasdBar).CornerRadius = UDim.new(0, 4); Instance.new("UIStroke", wasdBar).Color = Color3.fromRGB(30,30,38); Instance.new("UIStroke", wasdBar).Thickness = 1
local wasdPad = Instance.new("UIPadding", wasdBar); wasdPad.PaddingTop = UDim.new(0, 4); wasdPad.PaddingBottom = UDim.new(0, 4); wasdPad.PaddingLeft = UDim.new(0, 4); wasdPad.PaddingRight = UDim.new(0, 4)
local WASD_ROW_W = 3 * WASD_KEY_SIZE + 2 * WASD_GAP
local wasdRow1 = Instance.new("Frame", wasdBar); wasdRow1.Size = UDim2.new(0, WASD_ROW_W, 0, WASD_KEY_SIZE); wasdRow1.BackgroundTransparency = 1; wasdRow1.BorderSizePixel = 0; wasdRow1.ZIndex = 10
local wasdRow2 = Instance.new("Frame", wasdBar); wasdRow2.Size = UDim2.new(0, WASD_ROW_W, 0, WASD_KEY_SIZE); wasdRow2.Position = UDim2.new(0, 0, 0, WASD_KEY_SIZE + WASD_GAP); wasdRow2.BackgroundTransparency = 1; wasdRow2.BorderSizePixel = 0; wasdRow2.ZIndex = 10
local function makeKeyBox(parent, label, xOffset)
	local box = Instance.new("Frame", parent); box.Size = UDim2.new(0, WASD_KEY_SIZE, 0, WASD_KEY_SIZE); box.Position = UDim2.new(0, xOffset, 0, 0); box.BackgroundColor3 = Color3.fromRGB(25,25,32); box.BorderSizePixel = 0; box.ZIndex = 11; Instance.new("UICorner", box).CornerRadius = UDim.new(0, 3)
	local stroke = Instance.new("UIStroke", box); stroke.Color = Color3.fromRGB(30,30,38); stroke.Thickness = 1
	local lbl = Instance.new("TextLabel", box); lbl.Size = UDim2.new(1, 0, 1, 0); lbl.BackgroundTransparency = 1; lbl.Text = label; lbl.TextColor3 = Color3.fromRGB(45,45,55); lbl.Font = Enum.Font.GothamMedium; lbl.TextSize = 10; lbl.ZIndex = 12
	return box, lbl, stroke
end
local wBox, wLbl, wStroke = makeKeyBox(wasdRow1, "w", WASD_KEY_SIZE + WASD_GAP)
local aBox, aLbl, aStroke = makeKeyBox(wasdRow2, "a", 0)
local sBox, sLbl, sStroke = makeKeyBox(wasdRow2, "s", WASD_KEY_SIZE + WASD_GAP)
local dBox, dLbl, dStroke = makeKeyBox(wasdRow2, "d", (WASD_KEY_SIZE + WASD_GAP) * 2)
local function setKeyLit(box, lbl, stroke, lit)
	if lit then box.BackgroundColor3 = Color3.fromRGB(30,80,40); stroke.Color = Color3.fromRGB(76,210,96); lbl.TextColor3 = Color3.fromRGB(76,210,96)
	else box.BackgroundColor3 = Color3.fromRGB(25,25,32); stroke.Color = Color3.fromRGB(30,30,38); lbl.TextColor3 = Color3.fromRGB(45,45,55) end
end
RunService.RenderStepped:Connect(function()
	setKeyLit(wBox, wLbl, wStroke, UserInputService:IsKeyDown(Enum.KeyCode.W) or UserInputService:IsKeyDown(Enum.KeyCode.Up))
	setKeyLit(aBox, aLbl, aStroke, UserInputService:IsKeyDown(Enum.KeyCode.A) or UserInputService:IsKeyDown(Enum.KeyCode.Left))
	setKeyLit(sBox, sLbl, sStroke, UserInputService:IsKeyDown(Enum.KeyCode.S) or UserInputService:IsKeyDown(Enum.KeyCode.Down))
	setKeyLit(dBox, dLbl, dStroke, UserInputService:IsKeyDown(Enum.KeyCode.D) or UserInputService:IsKeyDown(Enum.KeyCode.Right))
end)

----------------------------------------------------------------------
-- LUCIDE ICONS & UI HELPERS
----------------------------------------------------------------------
local LUCIDE_MODULE: Instance? = nil
local function findLucideModule(): Instance?
	if LUCIDE_MODULE then return LUCIDE_MODULE end
	local rs = game:GetService("ReplicatedStorage")
	local direct = rs:FindFirstChild("Lucide") or rs:FindFirstChild("lucide-roblox")
	if direct and direct:IsA("ModuleScript") then return direct end
	for _, d in ipairs(rs:GetDescendants()) do
		if d:IsA("ModuleScript") and (d.Name == "Lucide" or d.Name == "lucide-roblox") then return d end
	end
	return nil
end
local LOAD_LUCIDE_FROM_WEB = true
local LUCIDE_LUAU_URL = "https://github.com/latte-soft/lucide-roblox/releases/download/0.1.3/lucide-roblox.luau"
local Lucide: any = nil
do
	local module = findLucideModule()
	if module then
		local ok, mod = pcall(require, module :: any)
		if ok and type(mod) == "table" and mod.GetAsset then Lucide = mod end
	end
	if not Lucide and LOAD_LUCIDE_FROM_WEB then
		local ok, mod = pcall(function() return loadstring(game:HttpGet(LUCIDE_LUAU_URL))() end)
		if ok and type(mod) == "table" and mod.GetAsset then Lucide = mod end
	end
	if not Lucide then warn("[MenuUI] No Lucide source - using text glyph fallback.") end
end

local ICON_NAMES: { [string]: string } = {
	movement = "move", aimbot = "crosshair", visuals = "eye", misc = "settings-2",
	inventory = "sword", config = "cog",
}
local GLYPH: { [string]: string } = {
	movement="\u{2725}", aimbot="\u{25CE}", visuals="\u{25C9}", misc="\u{2261}",
	inventory="\u{25A6}", config="\u{2699}",
}

local function new(class: string, props: { [string]: any }): any
	local obj = Instance.new(class)
	local parent = props.Parent; props.Parent = nil
	for k, v in pairs(props) do (obj :: any)[k] = v end
	if parent then obj.Parent = parent end
	return obj
end
local function corner(parent: Instance, radius: number)
	new("UICorner", { CornerRadius = UDim.new(0, radius), Parent = parent })
end
local function stroke(parent: Instance, color: Color3, thickness: number?)
	return new("UIStroke", { Color = color, Thickness = thickness or 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = parent })
end
local function padding(parent: Instance, all: number)
	new("UIPadding", { PaddingTop = UDim.new(0, all), PaddingBottom = UDim.new(0, all), PaddingLeft = UDim.new(0, all), PaddingRight = UDim.new(0, all), Parent = parent })
end
local function vlist(parent: Instance, gap: number)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Vertical, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, gap), Parent = parent })
end

local function makeIcon(name: string, color: Color3, size: number): Instance
	local iconName = ICON_NAMES[name]
	if Lucide and iconName then
		local ok, asset = pcall(Lucide.GetAsset, iconName, 48)
		if ok and asset then
			return new("ImageLabel", {
				BackgroundTransparency = 1, Image = asset.Url, ImageRectSize = asset.ImageRectSize,
				ImageRectOffset = asset.ImageRectOffset, ImageColor3 = color, Size = UDim2.fromOffset(size, size)
			})
		end
	end
	return new("TextLabel", {
		BackgroundTransparency = 1, Text = GLYPH[name] or "\u{2022}", TextColor3 = color,
		Font = Enum.Font.GothamBold, TextSize = size, Size = UDim2.fromOffset(size, size),
		TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center
	})
end

-- COLORS & SIZES
local COLORS = {
	background     = Color3.fromRGB(0,0,0), sidebar = Color3.fromRGB(0,0,0), panel = Color3.fromRGB(13,13,13),
	panelStroke    = Color3.fromRGB(26,26,26), windowStroke = Color3.fromRGB(22,22,22), accent = Color3.fromRGB(48,244,38),
	sidebarSelBg   = Color3.fromRGB(28,28,28), divider = Color3.fromRGB(38,38,38), titleBox = Color3.fromRGB(18,18,18),
	title          = Color3.fromRGB(240,240,240), labelOn = Color3.fromRGB(226,226,226), labelOff = Color3.fromRGB(150,150,150),
	sidebarText    = Color3.fromRGB(160,160,160), checkOff = Color3.fromRGB(22,22,22), checkOffStroke = Color3.fromRGB(50,50,50),
	check          = Color3.fromRGB(8,12,8), keybind = Color3.fromRGB(95,95,95)
}
local SIZES = {
	window      = Vector2.new(900, 635),  -- wider for two columns
	sidebarW    = 168,
	contentPad  = 16,
	colGap      = 16,
	colWidth    = 330,   -- each column width
	rowH        = 25,
	rowGap      = 6,
	panelPad    = 12,
	panelGap    = 16,
	titleH      = 28,
	checkbox    = 18,
	labelStartX = 24,
	corner      = 8,
	logoAreaH   = 84,
}
local FONTS = { title=Enum.Font.GothamBold, label=Enum.Font.Gotham, sidebar=Enum.Font.GothamMedium, glyph=Enum.Font.GothamBold }
local LOGO_IMAGE = "rbxassetid://136135909152944"

----------------------------------------------------------------------
-- MAIN WINDOW
----------------------------------------------------------------------
local win = Instance.new("Frame")
win.Name = "Window"; win.AnchorPoint = Vector2.new(0.5,0.5); win.Position = UDim2.fromScale(0.5,0.5)
win.Size = UDim2.fromOffset(SIZES.window.X, SIZES.window.Y); win.BackgroundColor3 = COLORS.background; win.BorderSizePixel = 0
win.ClipsDescendants = true; win.Visible = false; win.Parent = screenGui
corner(win, SIZES.corner); stroke(win, COLORS.windowStroke, 1)

-- Sidebar
local sidebar = Instance.new("Frame")
sidebar.Size = UDim2.new(0, SIZES.sidebarW, 1, 0); sidebar.BackgroundColor3 = COLORS.sidebar; sidebar.BorderSizePixel = 0; sidebar.Parent = win
new("UIPadding", { PaddingTop=UDim.new(0,20), PaddingLeft=UDim.new(0,14), PaddingRight=UDim.new(0,14), Parent=sidebar })

-- Logo
local logoHolder = Instance.new("Frame"); logoHolder.Size = UDim2.new(1,0,0, SIZES.logoAreaH); logoHolder.BackgroundTransparency = 1; logoHolder.LayoutOrder = 0; logoHolder.Parent = sidebar
local logo = Instance.new("ImageLabel"); logo.BackgroundTransparency = 1; logo.Image = LOGO_IMAGE; logo.ScaleType = Enum.ScaleType.Fit
logo.AnchorPoint = Vector2.new(0.5,0.5); logo.Position = UDim2.fromScale(0.5,0.5); logo.Size = UDim2.fromOffset(64,64); logo.Parent = logoHolder

local nav = Instance.new("Frame"); nav.Size = UDim2.new(1,0,1,-SIZES.logoAreaH); nav.Position = UDim2.new(0,0,0, SIZES.logoAreaH); nav.BackgroundTransparency = 1; nav.Parent = sidebar
vlist(nav, 3)

-- SIDEBAR DATA – only movement has subs
local SIDEBAR = {
	{ name="aimbot",    icon="aimbot",    defaultSub="main" }, 
	{ name="movement",  icon="movement",  subs={"main","recorder"} },
	{ name="visuals",   icon="visuals",   defaultSub="enemy" },
	{ name="misc",      icon="misc",      defaultSub="hud" },
	{ name="inventory", icon="inventory", defaultSub="skinchanger" },
	{ name="config",    icon="config",    defaultSub="soon" },
}

-- Category buttons + movement sub-buttons
local categoryButtons = {}
local subButtons = {}
local activeCategory = nil
local activeSub = nil

local function selectCategory(name)
	activeCategory = name
	for cat, ctrl in pairs(categoryButtons) do
		ctrl.setSelected(cat == name)
	end
	local showSubs = (name == "movement")
	for _, ctrl in pairs(subButtons) do
		ctrl.btn.Visible = showSubs
	end
	if showSubs then
		if activeSub ~= "main" and activeSub ~= "recorder" then activeSub = "main" end
		for subName, ctrl in pairs(subButtons) do
			ctrl.setSelected(subName == activeSub)
		end
		rebuildContent("movement", activeSub)
	else
		local entry = nil
		for _, e in ipairs(SIDEBAR) do if e.name == name then entry = e; break end end
		if entry and entry.defaultSub then
			rebuildContent(name, entry.defaultSub)
		end
	end
end

local function selectSub(name)
	if activeCategory ~= "movement" then return end
	activeSub = name
	for subName, ctrl in pairs(subButtons) do
		ctrl.setSelected(subName == name)
	end
	rebuildContent("movement", name)
end

local function buildCategory(entry, order)
	local row = Instance.new("Frame"); row.Name = entry.name; row.Size = UDim2.new(1,0,0,30); row.BackgroundColor3 = COLORS.sidebarSelBg; row.BackgroundTransparency = 1; row.LayoutOrder = order; row.Parent = nav
	corner(row, 6)
	new("UIPadding", { PaddingLeft=UDim.new(0,8), Parent=row })
	local icon = makeIcon(entry.icon, COLORS.accent, 17)
	icon.AnchorPoint = Vector2.new(0,0.5); icon.Position = UDim2.new(0,0,0.5,0); icon.Parent = row
	local label = Instance.new("TextLabel"); label.BackgroundTransparency = 1; label.Text = entry.name; label.Font = FONTS.sidebar; label.TextSize = 14; label.TextColor3 = COLORS.sidebarText; label.TextXAlignment = Enum.TextXAlignment.Left; label.Position = UDim2.new(0,26,0,0); label.Size = UDim2.new(1,-26,1,0); label.Parent = row
	local button = Instance.new("TextButton"); button.Text = ""; button.BackgroundTransparency = 1; button.Size = UDim2.fromScale(1,1); button.AutoButtonColor = false; button.Parent = row

	local tweenInfo = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	categoryButtons[entry.name] = {
		setSelected = function(sel)
			TweenService:Create(row, tweenInfo, { BackgroundTransparency = sel and 0 or 1 }):Play()
			TweenService:Create(label, tweenInfo, { TextColor3 = sel and COLORS.accent or COLORS.sidebarText }):Play()
		end
	}
	button.MouseButton1Click:Connect(function()
		selectCategory(entry.name)
	end)
end

local function buildSubButtons()
	local order = 20
	local tweenInfo = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	for _, subName in ipairs({"main","recorder"}) do
		local row = Instance.new("Frame"); row.Name = subName; row.Size = UDim2.new(1,0,0,24); row.BackgroundColor3 = COLORS.sidebarSelBg; row.BackgroundTransparency = 1; row.LayoutOrder = order; row.Parent = nav; row.Visible = false
		order += 1
		corner(row, 6)
		new("UIPadding", { PaddingLeft=UDim.new(0,34), Parent=row })
		local label = Instance.new("TextLabel"); label.BackgroundTransparency = 1; label.Text = subName; label.Font = FONTS.sidebar; label.TextSize = 13; label.TextColor3 = COLORS.sidebarText; label.TextXAlignment = Enum.TextXAlignment.Left; label.Position = UDim2.new(0,0,0,0); label.Size = UDim2.new(1,0,1,0); label.Parent = row
		local button = Instance.new("TextButton"); button.Text = ""; button.BackgroundTransparency = 1; button.Size = UDim2.fromScale(1,1); button.AutoButtonColor = false; button.Parent = row

		subButtons[subName] = {
			btn = row,
			setSelected = function(sel)
				TweenService:Create(row, tweenInfo, { BackgroundTransparency = sel and 0 or 1 }):Play()
				TweenService:Create(label, tweenInfo, { TextColor3 = sel and COLORS.accent or COLORS.sidebarText }):Play()
			end
		}
		button.MouseButton1Click:Connect(function() selectSub(subName) end)
	end
end

do
	local order = 0
	for _, entry in ipairs(SIDEBAR) do
		order += 10
		buildCategory(entry, order)
	end
	buildSubButtons()
end

-- Content area – two columns side-by-side
local content = Instance.new("Frame"); content.Name = "Content"; content.Position = UDim2.new(0, SIZES.sidebarW, 0, 0); content.Size = UDim2.new(1, -SIZES.sidebarW, 1, 0); content.BackgroundTransparency = 1; content.Parent = win
padding(content, SIZES.contentPad)
local columnList = Instance.new("UIListLayout"); columnList.FillDirection = Enum.FillDirection.Horizontal; columnList.SortOrder = Enum.SortOrder.LayoutOrder; columnList.Padding = UDim.new(0, SIZES.colGap); columnList.HorizontalAlignment = Enum.HorizontalAlignment.Left; columnList.VerticalAlignment = Enum.VerticalAlignment.Top; columnList.Parent = content

local columns = {}
local function clearContent()
	for _, col in pairs(columns) do col:Destroy() end
	columns = {}
end

local function makeColumn(order)
	local col = Instance.new("Frame"); col.Size = UDim2.new(0, SIZES.colWidth, 0,0); col.AutomaticSize = Enum.AutomaticSize.Y; col.BackgroundTransparency = 1; col.LayoutOrder = order; col.Parent = content
	vlist(col, SIZES.panelGap)
	return col
end

-- Slider builder
-- Slider builder
local function buildSlider(parent, xOff, yOff, labelTxt, minV, maxV, initV, trackW, onCh)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, -xOff, 0, 14)
    row.Position = UDim2.new(0, xOff, 0, yOff)
    row.BackgroundTransparency = 1
    row.ZIndex = 6
    row.Parent = parent
    
    local sLbl = Instance.new("TextLabel")
    sLbl.Size = UDim2.new(0,34,1,0)
    sLbl.BackgroundTransparency = 1
    sLbl.Text = labelTxt
    sLbl.TextColor3 = COLORS.labelOff
    sLbl.Font = FONTS.label
    sLbl.TextSize = 9
    sLbl.TextXAlignment = Enum.TextXAlignment.Left
    sLbl.ZIndex = 7
    sLbl.Parent = row
    
    local track = Instance.new("Frame")
    track.Size = UDim2.new(0, trackW, 0, 2)
    track.Position = UDim2.new(0,36,0.5,-1)
    track.BackgroundColor3 = COLORS.checkOff
    track.BorderSizePixel = 0
    track.ZIndex = 7
    track.Parent = row
    corner(track, 1)
    
    local frac = math.clamp((initV - minV) / (maxV - minV), 0, 1)
    local fill = Instance.new("Frame")
    fill.Size = UDim2.new(frac,0,1,0)
    fill.BackgroundColor3 = COLORS.accent
    fill.BorderSizePixel = 0
    fill.ZIndex = 8
    fill.Parent = track
    corner(fill, 1)
    
    local knob = Instance.new("Frame")
    knob.Size = UDim2.new(0,8,0,8)
    knob.AnchorPoint = Vector2.new(0.5,0.5)
    knob.Position = UDim2.new(frac,0,0.5,0)
    knob.BackgroundColor3 = COLORS.title
    knob.BorderSizePixel = 0
    knob.ZIndex = 9
    knob.Parent = track
    corner(knob, 4)
    
    local valLbl = Instance.new("TextLabel")
    valLbl.Size = UDim2.new(0,32,1,0)
    valLbl.Position = UDim2.new(0, trackW + 40, 0, 0)
    valLbl.BackgroundTransparency = 1
    valLbl.Text = tostring(initV)
    valLbl.TextColor3 = COLORS.title
    valLbl.Font = FONTS.label
    valLbl.TextSize = 9
    valLbl.TextXAlignment = Enum.TextXAlignment.Left
    valLbl.ZIndex = 7
    valLbl.Parent = row
    
    local sd = false
    local function apply(ax)
        local t = math.clamp((ax - track.AbsolutePosition.X) / trackW, 0, 1)
        local v = math.floor(minV + t * (maxV - minV) + 0.5)
        local f2 = (v - minV) / (maxV - minV)
        fill.Size = UDim2.new(f2, 0, 1, 0)
        knob.Position = UDim2.new(f2, 0, 0.5, 0)
        valLbl.Text = tostring(v)
        onCh(v)
    end
    
    track.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 then
            sd = true
            apply(i.Position.X)
        end
    end)
    
    UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 then
            sd = false
        end
    end)
    
    UserInputService.InputChanged:Connect(function(i)
        if sd and i.UserInputType == Enum.UserInputType.MouseMovement then
            apply(i.Position.X)
        end
    end)
end


local function buildKeybind(parent, labelText, currentKey, onChange)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 28)
    row.BackgroundTransparency = 1
    row.Parent = parent
    
    -- Label
    local label = Instance.new("TextLabel")
    label.Text = labelText
    label.Font = FONTS.label
    label.TextSize = 12
    label.TextColor3 = COLORS.labelOff
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextYAlignment = Enum.TextYAlignment.Center
    label.BackgroundTransparency = 1
    label.Size = UDim2.new(0.5, -5, 1, 0)
    label.Parent = row
    
    -- Keybind button
    local keyButton = Instance.new("TextButton")
    keyButton.Text = currentKey or "Click to bind"
    keyButton.Font = FONTS.label
    keyButton.TextSize = 11
    keyButton.TextColor3 = COLORS.title
    keyButton.BackgroundColor3 = COLORS.titleBox
    keyButton.Size = UDim2.new(0.4, 0, 1, 0)
    keyButton.Position = UDim2.new(0.5, 5, 0, 0)
    keyButton.Parent = row
    corner(keyButton, 4)
    stroke(keyButton, COLORS.divider, 1)
    
    local isListening = false
    
    keyButton.MouseButton1Click:Connect(function()
        if isListening then return end
        isListening = true
        keyButton.Text = "Press any key..."
        keyButton.TextColor3 = COLORS.accent
        
        startKeybindCapture(function(inputType, displayName, enumValue)
            isListening = false
            if inputType == "Mouse" then
                keyButton.Text = displayName
                cfg.aimbotButton = enumValue
                cfg.aimbotKeybind = displayName
            elseif inputType == "Keyboard" then
                keyButton.Text = displayName
                cfg.aimbotButton = enumValue
                cfg.aimbotKeybind = displayName
            end
            keyButton.TextColor3 = COLORS.title
            
            -- Restart aimbot if enabled
            if features.FakeAimbot.enabled then
                stopFeature("FakeAimbot")
                fakeaimbot_start()
                features.FakeAimbot.conn = features.FakeAimbot.conn
            end
            
            if onChange then onChange() end
        end)
        
        -- Reset if not changed after 5 seconds
        task.delay(5, function()
            if isListening then
                isListening = false
                keyButton.Text = currentKey or "Click to bind"
                keyButton.TextColor3 = COLORS.title
            end
        end)
    end)
    
    return keyButton
end



-- Panel builder
-- Panel builder
-- Panel builder
function makePanel(colIndex, def)
    local col = columns[colIndex]
    local panel = Instance.new("Frame")
    panel.Size = UDim2.new(1,0,0,0)
    panel.AutomaticSize = Enum.AutomaticSize.Y
    panel.BackgroundColor3 = COLORS.panel
    panel.BorderSizePixel = 0
    panel.Parent = col
    corner(panel, SIZES.corner)
    stroke(panel, COLORS.panelStroke, 1)
    vlist(panel, 10)

    -- Header
    local header = Instance.new("Frame")
    header.BackgroundColor3 = COLORS.titleBox
    header.BorderSizePixel = 0
    header.Size = UDim2.new(1,0,0, SIZES.titleH)
    header.LayoutOrder = 1
    header.Parent = panel
    stroke(header, COLORS.divider, 1)
    new("UIPadding", { PaddingLeft=UDim.new(0,10), Parent=header })
    local headerLabel = Instance.new("TextLabel")
    headerLabel.Text = def.title
    headerLabel.Font = FONTS.title
    headerLabel.TextSize = 14
    headerLabel.TextColor3 = COLORS.title
    headerLabel.TextXAlignment = Enum.TextXAlignment.Left
    headerLabel.TextYAlignment = Enum.TextYAlignment.Center
    headerLabel.BackgroundTransparency = 1
    headerLabel.Size = UDim2.fromScale(1,1)
    headerLabel.Parent = header

    -- Rows container
    local rows = Instance.new("Frame")
    rows.Size = UDim2.new(1,0,0,0)
    rows.AutomaticSize = Enum.AutomaticSize.Y
    rows.BackgroundTransparency = 1
    rows.LayoutOrder = 2
    rows.Parent = panel
    padding(rows, SIZES.panelPad)
    vlist(rows, SIZES.rowGap)

    for i, item in ipairs(def.items) do
        -- Calculate row height
        local rowH = SIZES.rowH
        if item.slider then rowH = SIZES.rowH + 28 end
        if item.type == "keybind" then rowH = 28 end
        
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1,0,0,rowH)
        row.BackgroundTransparency = 1
        row.Parent = rows

        if item.type == "toggle" then
            -- Toggle row (top part)
            local toggleRow = Instance.new("Frame")
            toggleRow.Size = UDim2.new(1,0,0,SIZES.rowH)
            toggleRow.BackgroundTransparency = 1
            toggleRow.Parent = row
            
            -- Checkbox
            local box = Instance.new("Frame")
            box.AnchorPoint = Vector2.new(0,0.5)
            box.Position = UDim2.new(0,0,0.5,0)
            box.Size = UDim2.fromOffset(SIZES.checkbox, SIZES.checkbox)
            box.BackgroundColor3 = COLORS.checkOff
            box.BorderSizePixel = 0
            box.Parent = toggleRow
            corner(box, 5)
            local boxStroke = stroke(box, COLORS.checkOffStroke, 1)
            
            local check = Instance.new("TextLabel")
            check.Text = "\u{2714}"
            check.Font = Enum.Font.GothamBlack
            check.TextSize = 14
            check.TextColor3 = COLORS.check
            check.BackgroundTransparency = 1
            check.Size = UDim2.fromScale(1,1)
            check.Parent = box
            
            -- Label
            local label = Instance.new("TextLabel")
            label.Text = item.label
            label.Font = FONTS.label
            label.TextSize = 14
            label.TextColor3 = COLORS.labelOff
            label.TextXAlignment = Enum.TextXAlignment.Left
            label.TextYAlignment = Enum.TextYAlignment.Center
            label.BackgroundTransparency = 1
            label.Position = UDim2.new(0, SIZES.labelStartX, 0,0)
            label.Size = UDim2.new(1, -SIZES.labelStartX - 22, 1, 0)
            label.Parent = toggleRow
            
            -- Hint (keybind info with right-click support)
            if item.hint then
                -- Get the override for this feature
                local override = keybindOverrides[item.key]
                local keyName = "auto"
                local mode = "auto"
                if override then
                    if override.key then
                        keyName = getKeyNameFromEnum(override.key)
                    end
                    mode = override.mode or "auto"
                end
                
                local hint = Instance.new("TextLabel")
                hint.Text = string.format("[%s|%s]", keyName, mode)
                hint.Font = FONTS.label
                hint.TextSize = 11
                hint.TextColor3 = COLORS.keybind
                hint.TextXAlignment = Enum.TextXAlignment.Right
                hint.TextYAlignment = Enum.TextYAlignment.Center
                hint.BackgroundTransparency = 1
                hint.Position = UDim2.new(1, -80, 0, 0)
                hint.Size = UDim2.new(0, 70, 1, 0)
                hint.Parent = toggleRow
                hint.ZIndex = 20
                
                -- Make hint clickable with right-click
                local hintButton = Instance.new("TextButton")
                hintButton.Text = ""
                hintButton.BackgroundTransparency = 1
                hintButton.Size = UDim2.fromScale(1,1)
                hintButton.AutoButtonColor = false
                hintButton.Parent = hint
                hintButton.ZIndex = 21
                
                hintButton.MouseButton2Click:Connect(function(x, y)
                    local currentKey = override and override.key
                    local currentMode = override and override.mode or "auto"
                    createContextMenu(item.key, currentKey, currentMode, Vector2.new(x, y))
                end)
            end
            
            -- Click button for toggle
            local button = Instance.new("TextButton")
            button.Text = ""
            button.BackgroundTransparency = 1
            button.Size = UDim2.fromScale(1,1)
            button.AutoButtonColor = false
            button.Parent = toggleRow

            local localState = item.init == true
            local function getState()
                if item.key and features[item.key] then return features[item.key].enabled end
                return localState
            end
            
            local function render()
                local on = getState()
                box.BackgroundColor3 = on and COLORS.accent or COLORS.checkOff
                boxStroke.Enabled = not on
                check.Visible = on
                check.TextColor3 = Color3.fromRGB(255, 255, 255)
                label.TextColor3 = on and COLORS.labelOn or COLORS.labelOff
            end
            
            local function setState(on)
                if item.key and features[item.key] then
                    if features[item.key].enabled ~= on then toggleFeature(item.key) end
                else
                    localState = on
                end
                render()
                if item.onToggle then item.onToggle(on) end
            end
            render()

            button.MouseButton1Click:Connect(function()
                setState(not getState())
            end)

            -- Slider (bottom part) - only if this toggle has a slider
            if item.slider then
                buildSlider(row, 0, SIZES.rowH + 2, item.sliderLabel or "value", item.min, item.max, item.init, 90, item.onChange)
            end
            
        elseif item.type == "keybind" then
            buildKeybind(row, item.label, item.currentKey or "MouseButton2")
        elseif item.type == "label" then
            local l = Instance.new("TextLabel")
            l.Text = item.text
            l.Font = FONTS.label
            l.TextSize = 14
            l.TextColor3 = COLORS.labelOff
            l.BackgroundTransparency = 1
            l.Size = UDim2.new(1,0,0,20)
            l.Parent = row
        end
    end
end

-- Add this function near the other UI builder functions




----------------------------------------------------------------------
-- VELOCITY GRAPH
----------------------------------------------------------------------
local velocityGraphGui = nil
local velocityGraphEnabled = false
local velocityGraphConnection = nil
local velocityHistory = {}
local MAX_VELOCITY_POINTS = 200
local GRAPH_WIDTH = 200
local GRAPH_HEIGHT = 60
local MAX_SPEED = 80 -- Maximum speed to display on graph

local function toggleVelocityGraph(enabled)
    velocityGraphEnabled = enabled
    
    if enabled then
        if velocityGraphGui then velocityGraphGui:Destroy() end
        
        velocityGraphGui = Instance.new("ScreenGui")
        velocityGraphGui.Name = "VelocityGraph"
        velocityGraphGui.ResetOnSpawn = false
        velocityGraphGui.IgnoreGuiInset = true
        velocityGraphGui.Parent = player:WaitForChild("PlayerGui")
        
        -- Main container
        local container = Instance.new("Frame")
        container.Size = UDim2.new(0, GRAPH_WIDTH + 20, 0, GRAPH_HEIGHT + 30)
        container.Position = UDim2.new(0, 15, 0.85, -50)
        container.BackgroundColor3 = Color3.fromRGB(10, 10, 12)
        container.BorderSizePixel = 0
        container.ZIndex = 10
        container.Parent = velocityGraphGui
        corner(container, 4)
        stroke(container, Color3.fromRGB(30, 30, 38), 1)
        
        -- Title
        local title = Instance.new("TextLabel")
        title.Size = UDim2.new(1, 0, 0, 16)
        title.Position = UDim2.new(0, 0, 0, 2)
        title.BackgroundTransparency = 1
        title.Text = "Velocity"
        title.TextColor3 = Color3.fromRGB(150, 150, 150)
        title.Font = Enum.Font.GothamMedium
        title.TextSize = 10
        title.TextXAlignment = Enum.TextXAlignment.Center
        title.Parent = container
        
        -- Graph background
        local graphBg = Instance.new("Frame")
        graphBg.Size = UDim2.new(1, -12, 1, -26)
        graphBg.Position = UDim2.new(0, 6, 0, 20)
        graphBg.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
        graphBg.BorderSizePixel = 0
        graphBg.Parent = container
        corner(graphBg, 2)
        
        -- Graph canvas (where we draw)
        local graphCanvas = Instance.new("Frame")
        graphCanvas.Size = UDim2.new(1, 0, 1, 0)
        graphCanvas.BackgroundTransparency = 1
        graphCanvas.ClipsDescendants = true
        graphCanvas.Parent = graphBg
        
        -- Speed label (current speed)
        local speedLabel = Instance.new("TextLabel")
        speedLabel.Size = UDim2.new(1, 0, 0, 14)
        speedLabel.Position = UDim2.new(0, 0, 1, -14)
        speedLabel.BackgroundTransparency = 1
        speedLabel.Text = "0"
        speedLabel.TextColor3 = Color3.fromRGB(76, 210, 96)
        speedLabel.Font = Enum.Font.GothamBold
        speedLabel.TextSize = 11
        speedLabel.TextXAlignment = Enum.TextXAlignment.Right
        speedLabel.Parent = container
        
        -- Peak speed label
        local peakLabel = Instance.new("TextLabel")
        peakLabel.Size = UDim2.new(0.5, 0, 0, 14)
        peakLabel.Position = UDim2.new(0, 6, 1, -14)
        peakLabel.BackgroundTransparency = 1
        peakLabel.Text = "peak: 0"
        peakLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
        peakLabel.Font = Enum.Font.GothamMedium
        peakLabel.TextSize = 9
        peakLabel.TextXAlignment = Enum.TextXAlignment.Left
        peakLabel.Parent = container
        
        -- Grid lines (horizontal)
        for i = 1, 3 do
            local line = Instance.new("Frame")
            line.Size = UDim2.new(1, 0, 0, 1)
            line.Position = UDim2.new(0, 0, i / 4, 0)
            line.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
            line.BorderSizePixel = 0
            line.BackgroundTransparency = 0.5
            line.Parent = graphCanvas
        end
        
        -- Store references
        velocityGraphGui._canvas = graphCanvas
        velocityGraphGui._speedLabel = speedLabel
        velocityGraphGui._peakLabel = peakLabel
        velocityGraphGui._container = container
        
        -- Clear history when enabling
        velocityHistory = {}
        
        velocityGraphConnection = RunService.RenderStepped:Connect(function()
            if not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") then
                speedLabel.Text = "0"
                peakLabel.Text = "peak: 0"
                return
            end
            
            local hrp = player.Character.HumanoidRootPart
            local vel = hrp.AssemblyLinearVelocity
            local speed = math.floor(Vector3.new(vel.X, 0, vel.Z).Magnitude)
            
            -- Update labels
            speedLabel.Text = tostring(speed)
            
            -- Track peak
            local peak = 0
            for _, v in ipairs(velocityHistory) do
                if v > peak then peak = v end
            end
            peakLabel.Text = "peak: " .. tostring(peak)
            
            -- Add to history
            table.insert(velocityHistory, speed)
            if #velocityHistory > MAX_VELOCITY_POINTS then
                table.remove(velocityHistory, 1)
            end
            
            -- Draw graph
            drawVelocityGraph(graphCanvas, velocityHistory, MAX_SPEED)
        end)
        
    else
        if velocityGraphConnection then
            velocityGraphConnection:Disconnect()
            velocityGraphConnection = nil
        end
        if velocityGraphGui then
            velocityGraphGui:Destroy()
            velocityGraphGui = nil
        end
        velocityHistory = {}
    end
end

-- Function to draw the velocity graph using UI elements
local function drawVelocityGraph(canvas, history, maxSpeed)
    -- Clear existing graph lines (keep grid lines)
    for _, child in ipairs(canvas:GetChildren()) do
        -- Skip grid lines (they're the ones with Position Y at 0.25, 0.5, 0.75)
        if child:IsA("Frame") and child.Size.Y.Offset == 1 then
            -- Keep grid lines
        else
            child:Destroy()
        end
    end
    
    local canvasSize = canvas.AbsoluteSize
    if canvasSize.X <= 0 or canvasSize.Y <= 0 then return end
    
    local width = canvasSize.X
    local height = canvasSize.Y
    local count = #history
    
    if count < 2 then return end
    
    -- Calculate points
    local points = {}
    local maxVal = maxSpeed
    
    -- Find actual max if it's higher than our max
    local actualMax = 0
    for _, v in ipairs(history) do
        if v > actualMax then actualMax = v end
    end
    if actualMax > maxVal then maxVal = actualMax end
    if maxVal < 1 then maxVal = 1 end
    
    for i = 1, count do
        local x = (i - 1) / (count - 1) * width
        local y = height - (history[i] / maxVal * height)
        table.insert(points, {x = x, y = math.clamp(y, 0, height)})
    end
    
    -- Draw the graph line using multiple small frames
    for i = 1, #points - 1 do
        local p1 = points[i]
        local p2 = points[i + 1]
        
        local dx = p2.x - p1.x
        local dy = p2.y - p1.y
        local dist = math.sqrt(dx * dx + dy * dy)
        
        if dist > 0.5 then
            local line = Instance.new("Frame")
            line.Size = UDim2.new(0, dist, 0, 1.5)
            
            -- Calculate midpoint for positioning
            local midX = (p1.x + p2.x) / 2
            local midY = (p1.y + p2.y) / 2
            
            line.Position = UDim2.new(0, midX - dist/2, 0, midY - 0.75)
            
            -- Calculate rotation
            local angle = math.atan2(dy, dx)
            line.Rotation = math.deg(angle)
            
            -- Color based on speed (green to red)
            local speed = history[i + 1] or 0
            local ratio = math.clamp(speed / maxSpeed, 0, 1)
            local color = Color3.fromRGB(
                255 * ratio,
                255 * (1 - ratio),
                0
            )
            
            line.BackgroundColor3 = color
            line.BackgroundTransparency = 0.3
            line.BorderSizePixel = 0
            line.Parent = canvas
        end
    end
    
    -- Add a glow effect (thicker line behind)
    for i = 1, #points - 1 do
        local p1 = points[i]
        local p2 = points[i + 1]
        
        local dx = p2.x - p1.x
        local dy = p2.y - p1.y
        local dist = math.sqrt(dx * dx + dy * dy)
        
        if dist > 0.5 then
            local glow = Instance.new("Frame")
            glow.Size = UDim2.new(0, dist, 0, 4)
            
            local midX = (p1.x + p2.x) / 2
            local midY = (p1.y + p2.y) / 2
            
            glow.Position = UDim2.new(0, midX - dist/2, 0, midY - 2)
            
            local angle = math.atan2(dy, dx)
            glow.Rotation = math.deg(angle)
            
            local speed = history[i + 1] or 0
            local ratio = math.clamp(speed / maxSpeed, 0, 1)
            local color = Color3.fromRGB(
                255 * ratio,
                255 * (1 - ratio),
                0
            )
            
            glow.BackgroundColor3 = color
            glow.BackgroundTransparency = 0.8
            glow.BorderSizePixel = 0
            glow.Parent = canvas
        end
    end
end




-- Movement sections (distributed across two columns)
local MOVEMENT_MAIN_SECTIONS = {
	-- left column (col 1)
	{ col=1, title="general", items={
		{ type="toggle", label="auto bunnyhop",   key="AutoBhop",   hint="[space]", slider=true, sliderLabel="boost", min=1, max=100, init=math.floor(cfg.bhopBoost*10+0.5), onChange=function(v) cfg.bhopBoost=v/10 end },
		{ type="toggle", label="auto pixelsurf",  key="PixelSurf",  hint="auto",    slider=true, sliderLabel="speed", min=20, max=200, init=cfg.pixelMaxSpeed, onChange=function(v) cfg.pixelMaxSpeed=v end },
		{ type="toggle", label="auto texturebug", key="TextureBug", hint="auto",    slider=true, sliderLabel="speed", min=20, max=200, init=cfg.textureMaxSpeed, onChange=function(v) cfg.textureMaxSpeed=v end },
		{ type="toggle", label="mini jump",        key="MiniJump",   hint="[c]",     slider=true, sliderLabel="power", min=5, max=80, init=cfg.miniJumpPower, onChange=function(v) cfg.miniJumpPower=v end },
		{ type="toggle", label="long jump",        key="LongJump",   hint="[e]",     slider=true, sliderLabel="power", min=20, max=200, init=cfg.longJumpPower, onChange=function(v) cfg.longJumpPower=v end },
		{ type="toggle", label="jump bug",         key="JumpBug",    hint="[q]",     slider=true, sliderLabel="power", min=10, max=200, init=cfg.jumpBugPower, onChange=function(v) cfg.jumpBugPower=v end },
	}},
	-- left column (col 1) strafe
	{ col=1, title="strafe", items={ { type="label", text="coming soon.." } } },
	-- right column (col 2) other
	{ col=2, title="other", items={
		{ type="toggle", label="auto wallstuck", key="dummy1" },
		{ type="toggle", label="auto wallhop", key="dummy2" }
	}},
	-- right column (col 2) utility
	{ col=2, title="utility", items={ { type="label", text="venthop assist (soon)" } } },
}

local RECORDER_SOON = { { col=1, title="recorder", items={ { type="label", text="soon" } } } }

-- Other tab panels
TAB_PANELS = {
    aimbot = {
        main = {
            { col=1, title="main", items={
                -- Toggle with slider (handles the aimbot toggle + smooth slider)
                { type="toggle", label="aimbot", key="FakeAimbot", 
                  slider=true, sliderLabel="smooth", min=1, max=100, 
                  init=cfg.aimbotSmooth, 
                  onChange=function(v) cfg.aimbotSmooth=v end },
                -- These should be "toggle" type with slider=true, not "slider" type
                { type="toggle", label="fov", key="fovToggle",
                  slider=true, sliderLabel="fov", min=1, max=360,
                  init=cfg.aimbotFOV,
                  onChange=function(v) cfg.aimbotFOV=v end },
                -- Keybind for aimbot button
                { type="keybind", label="keybind", currentKey=cfg.aimbotKeybind or "MouseButton2" },
                { type="toggle", label="fov view", key="fovView" },
                { type="label", text="change aimbot part (soon)" },
            }}
        }
    },
	visuals = {
		enemy = {
			{ col=1, title="enemy", items={ { type="toggle", label="esp", key="espToggle", onToggle=function(v) toggleESP(v) end } } }
		}
	},
misc = {
    hud = {
        { col=1, title="hud", items={
            { type="toggle", label="watermark", key="wm", init=true, onToggle=function(v) wmFrame.Visible=v end },
            { type="toggle", label="larp watermark", key="larp", onToggle=function(v) toggleLarpWatermark(v) end },
            { type="toggle", label="velocity graph", key="velGraph", onToggle=function(v) toggleVelocityGraph(v) end },
            { type="toggle", label="momentum", key="mom", onToggle=function(v) toggleMomentum(v) end },
            { type="toggle", label="indicators", key="ind", init=true, onToggle=function(v) indBar.Visible=v; wasdBar.Visible=v end },
        }}
    }
},
	inventory = {
		skinchanger = { col=1, title="skinchanger", items={} }
	},
	config = {
		soon = { { col=1, title="soon", items={ { type="label", text="soon" } } } }
	},
}

-- Skin list
local function refreshSkinList(skinListHolder, currentGunLabel)
	for _, child in ipairs(skinListHolder:GetChildren()) do if child:IsA("Frame") then child:Destroy() end end
	local gunName = getEquippedGunName()
	if gunName then currentGunLabel.Text = "current: " .. gunName else currentGunLabel.Text = "no weapon equipped"; return end
	local gunSkins = ReplicatedStorage:FindFirstChild("Skins") and ReplicatedStorage.Skins:FindFirstChild(gunName)
	if not gunSkins then currentGunLabel.Text = gunName .. " (no skins)"; return end

	local defWrap = Instance.new("Frame"); defWrap.Size = UDim2.new(1,0,0,28); defWrap.BackgroundColor3 = COLORS.panel; defWrap.BorderSizePixel = 0; defWrap.ZIndex = 3; defWrap.Parent = skinListHolder
	local defLbl = Instance.new("TextLabel"); defLbl.Text = "default"; defLbl.Font = FONTS.label; defLbl.TextSize = 11; defLbl.TextColor3 = (skinSelections[gunName]==nil) and COLORS.accent or COLORS.labelOff; defLbl.TextXAlignment = Enum.TextXAlignment.Left; defLbl.BackgroundTransparency = 1; defLbl.Size = UDim2.new(1,-16,1,0); defLbl.Position = UDim2.new(0,8,0,0); defLbl.ZIndex = 4; defLbl.Parent = defWrap
	local defBtn = Instance.new("TextButton"); defBtn.Text = ""; defBtn.BackgroundTransparency = 1; defBtn.Size = UDim2.fromScale(1,1); defBtn.AutoButtonColor = false; defBtn.Parent = defWrap
	defBtn.MouseButton1Click:Connect(function() skinSelections[gunName]=nil; startSkinLoop(); refreshSkinList(skinListHolder, currentGunLabel) end)

	for _, skin in ipairs(gunSkins:GetChildren()) do
		local wrap = Instance.new("Frame"); wrap.Size = UDim2.new(1,0,0,28); wrap.BackgroundColor3 = COLORS.panel; wrap.BorderSizePixel = 0; wrap.ZIndex = 3; wrap.Parent = skinListHolder
		local sel = skinSelections[gunName]; local isSelected = (sel == skin.Name)
		local lbl = Instance.new("TextLabel"); lbl.Text = skin.Name; lbl.Font = FONTS.label; lbl.TextSize = 11; lbl.TextColor3 = isSelected and COLORS.accent or COLORS.labelOff; lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.BackgroundTransparency = 1; lbl.Size = UDim2.new(1,-16,1,0); lbl.Position = UDim2.new(0,8,0,0); lbl.ZIndex = 4; lbl.Parent = wrap
		local btn = Instance.new("TextButton"); btn.Text = ""; btn.BackgroundTransparency = 1; btn.Size = UDim2.fromScale(1,1); btn.AutoButtonColor = false; btn.Parent = wrap
		btn.MouseButton1Click:Connect(function() skinSelections[gunName]=skin.Name; startSkinLoop(); refreshSkinList(skinListHolder, currentGunLabel) end)
	end
end

local function buildSkinPanel(colIndex)
	local col = columns[colIndex]
	local panel = Instance.new("Frame"); panel.Size = UDim2.new(1,0,0,0); panel.AutomaticSize = Enum.AutomaticSize.Y; panel.BackgroundColor3 = COLORS.panel; panel.BorderSizePixel = 0; panel.Parent = col
	corner(panel, SIZES.corner); stroke(panel, COLORS.panelStroke, 1)
	vlist(panel, 10)

	local header = Instance.new("Frame"); header.BackgroundColor3 = COLORS.titleBox; header.BorderSizePixel = 0; header.Size = UDim2.new(1,0,0, SIZES.titleH); header.LayoutOrder = 1; header.Parent = panel
	stroke(header, COLORS.divider, 1)
	new("UIPadding", { PaddingLeft=UDim.new(0,10), Parent=header })
	local headerLabel = Instance.new("TextLabel"); headerLabel.Text = "skinchanger"; headerLabel.Font = FONTS.title; headerLabel.TextSize = 14; headerLabel.TextColor3 = COLORS.title; headerLabel.TextXAlignment = Enum.TextXAlignment.Left; headerLabel.TextYAlignment = Enum.TextYAlignment.Center; headerLabel.BackgroundTransparency = 1; headerLabel.Size = UDim2.fromScale(1,1); headerLabel.Parent = header

	local rows = Instance.new("Frame"); rows.Size = UDim2.new(1,0,0,0); rows.AutomaticSize = Enum.AutomaticSize.Y; rows.BackgroundTransparency = 1; rows.LayoutOrder = 2; rows.Parent = panel
	padding(rows, SIZES.panelPad)
	vlist(rows, SIZES.rowGap)

	local currentGunLabel = Instance.new("TextLabel"); currentGunLabel.Text = "no weapon equipped"; currentGunLabel.Font = FONTS.label; currentGunLabel.TextSize = 11; currentGunLabel.TextColor3 = COLORS.labelOff; currentGunLabel.BackgroundTransparency = 1; currentGunLabel.Size = UDim2.new(1,0,0,20); currentGunLabel.Parent = rows
	local skinListHolder = Instance.new("Frame"); skinListHolder.Size = UDim2.new(1,0,0,0); skinListHolder.AutomaticSize = Enum.AutomaticSize.Y; skinListHolder.BackgroundTransparency = 1; skinListHolder.Parent = rows
	vlist(skinListHolder, 2)

	local refreshBtn = Instance.new("TextButton"); refreshBtn.Text = "refresh"; refreshBtn.Font = FONTS.label; refreshBtn.TextSize = 11; refreshBtn.TextColor3 = COLORS.title; refreshBtn.BackgroundColor3 = COLORS.titleBox; refreshBtn.Size = UDim2.new(1,-20,0,28); refreshBtn.ZIndex = 5; refreshBtn.Parent = rows
	corner(refreshBtn, 4)
	refreshBtn.MouseButton1Click:Connect(function() refreshSkinList(skinListHolder, currentGunLabel) end)

	refreshSkinList(skinListHolder, currentGunLabel)
	return panel
end

function rebuildContent(catName, subName)
	clearContent()
	columns[1] = makeColumn(1)
	columns[2] = makeColumn(2)

	if catName == "movement" then
		local sections
		if subName == "main" then sections = MOVEMENT_MAIN_SECTIONS
		elseif subName == "recorder" then sections = RECORDER_SOON
		else return end
		for _, sec in ipairs(sections) do
			makePanel(sec.col, sec)
		end
	elseif catName == "inventory" and subName == "skinchanger" then
		buildSkinPanel(1)
	else
		local defs = TAB_PANELS[catName] and TAB_PANELS[catName][subName]
		if defs then
			for _, def in ipairs(defs) do
				makePanel(def.col, def)
			end
		end
	end
end

-- Drag
local dragging, dragStart, dragOrigin = false, nil, nil
win.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		dragging = true; dragStart = input.Position; dragOrigin = win.Position
		input.Changed:Connect(function() if input.UserInputState == Enum.UserInputState.End then dragging = false end end)
	end
end)
UserInputService.InputChanged:Connect(function(input)
	if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
		local delta = input.Position - dragStart
		win.Position = UDim2.new(dragOrigin.X.Scale, dragOrigin.X.Offset + delta.X, dragOrigin.Y.Scale, dragOrigin.Y.Offset + delta.Y)
	end
end)

-- Menu toggle & unload
local menuOpen = false
local function setMenuOpen(open)
	menuOpen = open; win.Visible = open
	if open then UserInputService.MouseBehavior = Enum.MouseBehavior.Default; UserInputService.MouseIconEnabled = true
	else UserInputService.MouseBehavior = Enum.MouseBehavior.Default end
end
RunService.RenderStepped:Connect(function() if menuOpen then UserInputService.MouseBehavior = Enum.MouseBehavior.Default; UserInputService.MouseIconEnabled = true end end)
local unloadHeld = {}
UserInputService.InputBegan:Connect(function(input, gpe)
	if not gpe and input.KeyCode == Enum.KeyCode.Insert then setMenuOpen(not menuOpen) end
	if not gpe then
		unloadHeld[input.KeyCode] = true
		if unloadHeld[Enum.KeyCode.U] and unloadHeld[Enum.KeyCode.O] then
			for key in pairs(features) do stopFeature(key) end
			toggleESP(false); stopSkinLoop(); toggleLarpWatermark(false); toggleMomentum(false)
			setFog(false); setBlur(false)
			if fogConn then fogConn:Disconnect() end; if blurConn then blurConn:Disconnect() end
			trailFolder:Destroy(); screenGui:Destroy()
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default; UserInputService.MouseIconEnabled = true
		end
	end
end)
UserInputService.InputEnded:Connect(function(input) unloadHeld[input.KeyCode] = nil end)

-- Respawn
player.CharacterAdded:Connect(function(char)
	bindCharacter(char); task.wait(0.5)
	for key, f in pairs(features) do if f.enabled then
		local restart = nil
		if key=="PixelSurf" then restart=function() makeSurf(key,Vector3.new(0,0,0),   function() return cfg.pixelMaxSpeed   end) end
		elseif key=="TextureBug" then restart=function() makeSurf(key,Vector3.new(0,2.5,0), function() return cfg.textureMaxSpeed end) end
		elseif key=="AutoBhop" then restart=bhop_start
		elseif key=="JumpBug" then restart=jumpbug_start
		elseif key=="LongJump" then restart=longjump_start
		elseif key=="MiniJump" then restart=minijump_start
		elseif key=="FakeAimbot" then restart=fakeaimbot_start
		end
		if restart then f.conn = restart() end
	end end
	if espEnabled then refreshESP() end
	if momentumEnabled then toggleMomentum(false); toggleMomentum(true) end
end)

-- Initial state
selectCategory("movement")

startSkinLoop()
