-- ================================================================
-- dwbi | movement + ESP + SKINS  (Clarity menu)
-- Toggle menu: [INSERT]   |   Unload: hold U + O
-- ================================================================

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local mouse  = player:GetMouse()
local camera = workspace.CurrentCamera

local character, humanoid, hrp

local function bindCharacter(char)
    character = char
    humanoid  = char:WaitForChild("Humanoid")
    hrp       = char:WaitForChild("HumanoidRootPart")
end
if player.Character then bindCharacter(player.Character) end
player.CharacterAdded:Connect(bindCharacter)

-- ================================================================
-- CONFIG (movement + visuals)
-- ================================================================
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
    fogEnd          = 200,
    blurSize        = 10,
}

-- ESP defaults
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

local WALL_RANGE  = 2.0
local W_ACCEL     = 14
local BASE_SPEED  = 40
local TRAIL_LIFE  = 1.8
local TRAIL_WIDTH = 0.06

-- ================================================================
-- FEATURE STATE (movement)
-- ================================================================
local features = {
    PixelSurf  = { enabled=false, conn=nil, surfing=false, glideDir=nil, glideSpeed=0 },
    TextureBug = { enabled=false, conn=nil, surfing=false, glideDir=nil, glideSpeed=0 },
    AutoBhop   = { enabled=false, conn=nil },
    EdgeBug    = { enabled=false, conn=nil },
    JumpBug    = { enabled=false, conn=nil },
    LongJump   = { enabled=false, conn=nil },
    MiniJump   = { enabled=false, conn=nil },
    FakeAimbot = { enabled=false, conn=nil },
}

-- ESP state
local espEnabled = false
local espConn = nil
local espObjects = {}
local crouching = {}

-- ================================================================
-- SKINS STATE
-- ================================================================
local skinSelections = {}  -- skinSelections["P2000"] = "Ruby"
local skinOriginals  = {}  -- snapshot of original TextureIDs per gun
local skinEnabled = false
local skinConn = nil

-- ================================================================
-- RAYCAST (movement surf)
-- ================================================================
local PARAMS = RaycastParams.new()
PARAMS.FilterType = Enum.RaycastFilterType.Exclude

local WALL_DIRS = {
    Vector3.new( 1,0, 0), Vector3.new(-1,0, 0),
    Vector3.new( 0,0, 1), Vector3.new( 0,0,-1),
    Vector3.new( 1,0, 1).Unit, Vector3.new(-1,0, 1).Unit,
    Vector3.new( 1,0,-1).Unit, Vector3.new(-1,0,-1).Unit,
}

local function castDown(origin, dist)
    PARAMS.FilterDescendantsInstances = {character}
    return workspace:Raycast(origin, Vector3.new(0, -dist, 0), PARAMS)
end

local function findWall(originOffset)
    PARAMS.FilterDescendantsInstances = {character}
    local up     = Vector3.new(0, 1, 0)
    local origin = hrp.Position + originOffset
    local vel    = hrp and hrp.AssemblyLinearVelocity or Vector3.zero
    local hVel   = Vector3.new(vel.X, 0, vel.Z)

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

-- ================================================================
-- TRAIL (cosmetic)
-- ================================================================
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

-- ================================================================
-- SURF (PixelSurf + TextureBug)
-- ================================================================
local function makeSurf(key, originOffset, getMaxSpeed)
    local f = features[key]
    f.conn = RunService.Heartbeat:Connect(function(dt)
        if not hrp or not humanoid then return end
        local state = humanoid:GetState()
        local airborne = state == Enum.HumanoidStateType.Freefall
                      or state == Enum.HumanoidStateType.Jumping
        if not airborne then
            f.surfing = false; f.glideDir = nil; f.glideSpeed = 0
            updateTrail(hrp.Position, false, key); return
        end
        local wNormal = findWall(originOffset)
        if not wNormal then
            f.surfing = false; f.glideDir = nil; f.glideSpeed = 0
            updateTrail(hrp.Position, false, key); return
        end
        if f.surfing and (
            UserInputService:IsKeyDown(Enum.KeyCode.A) or
            UserInputService:IsKeyDown(Enum.KeyCode.D) or
            UserInputService:IsKeyDown(Enum.KeyCode.Left) or
            UserInputService:IsKeyDown(Enum.KeyCode.Right)) then
            f.surfing = false; f.glideDir = nil; f.glideSpeed = 0
            updateTrail(hrp.Position, false, key); return
        end
        local maxSpd = getMaxSpeed()
        if not f.surfing then
            f.surfing = true
            local look = hrp.CFrame.LookVector
            local proj = look - wNormal * look:Dot(wNormal)
            proj = Vector3.new(proj.X, 0, proj.Z)
            f.glideDir = proj.Magnitude > 0.01 and proj.Unit
                       or Vector3.new(-wNormal.Z, 0, wNormal.X).Unit
            local vel = hrp.AssemblyLinearVelocity
            f.glideSpeed = math.min(
                math.max(Vector3.new(vel.X, 0, vel.Z).Magnitude, BASE_SPEED),
                maxSpd)
        end
        f.glideSpeed = math.min(f.glideSpeed, maxSpd)
        if UserInputService:IsKeyDown(Enum.KeyCode.W) or UserInputService:IsKeyDown(Enum.KeyCode.Up) then
            f.glideSpeed = math.min(f.glideSpeed + W_ACCEL * dt, maxSpd)
        end
        hrp.AssemblyLinearVelocity = Vector3.new(
            f.glideDir.X * f.glideSpeed, 0, f.glideDir.Z * f.glideSpeed)
        humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
        updateTrail(hrp.Position + originOffset, true, key)
    end)
end

-- ================================================================
-- OTHER MOVEMENT FEATURES
-- ================================================================
local function bhop_start()
    features.AutoBhop.conn=RunService.RenderStepped:Connect(function()
        if not humanoid or not hrp then return end
        if not UserInputService:IsKeyDown(Enum.KeyCode.Space) then return end
        if humanoid.FloorMaterial~=Enum.Material.Air then
            humanoid.Jump=true
        else
            local md=humanoid.MoveDirection
            if md.Magnitude>0 then hrp.CFrame=hrp.CFrame+(md*cfg.bhopBoost) end
        end
    end)
end

local eb_wasGrounded=false
local function edgebug_start()
    features.EdgeBug.conn=RunService.Heartbeat:Connect(function()
        if not hrp or not humanoid then return end
        local state=humanoid:GetState()
        local onGround = state==Enum.HumanoidStateType.Running
                      or state==Enum.HumanoidStateType.RunningNoPhysics
        local moveDir=humanoid.MoveDirection
        local checkOrigin=hrp.Position+(moveDir.Magnitude>0 and moveDir or hrp.CFrame.LookVector)*1.8
        local floorAhead=castDown(checkOrigin,4.5)
        local floorBelow=castDown(hrp.Position,3.5)
        if onGround then
            eb_wasGrounded=true
            if floorBelow and not floorAhead then
                local vel=hrp.AssemblyLinearVelocity
                humanoid.Jump=true
                task.defer(function()
                    if hrp then
                        hrp.AssemblyLinearVelocity=Vector3.new(vel.X,hrp.AssemblyLinearVelocity.Y,vel.Z)
                    end
                end)
            end
        end
        if state==Enum.HumanoidStateType.Landed then eb_wasGrounded=false end
    end)
end

local function jumpbug_start()
    features.JumpBug.conn=humanoid.StateChanged:Connect(function(_,new)
        if new==Enum.HumanoidStateType.Jumping then
            if UserInputService:IsKeyDown(Enum.KeyCode.Q) then
                task.defer(function()
                    if hrp then
                        local vel=hrp.AssemblyLinearVelocity
                        hrp.AssemblyLinearVelocity=Vector3.new(vel.X,vel.Y+cfg.jumpBugPower,vel.Z)
                    end
                end)
            end
        end
    end)
end

local lj_used=false
local function longjump_start()
    features.LongJump.conn=UserInputService.InputBegan:Connect(function(input,gpe)
        if gpe then return end
        if input.KeyCode~=Enum.KeyCode.E then return end
        if not humanoid or not hrp then return end
        local state=humanoid:GetState()
        if state~=Enum.HumanoidStateType.Running and state~=Enum.HumanoidStateType.RunningNoPhysics then return end
        if lj_used then return end
        lj_used=true
        local look=hrp.CFrame.LookVector
        local vel=hrp.AssemblyLinearVelocity
        hrp.AssemblyLinearVelocity=Vector3.new(look.X*cfg.longJumpPower,vel.Y+25,look.Z*cfg.longJumpPower)
        humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
        local landConn
        landConn=humanoid.StateChanged:Connect(function(_,new)
            if new==Enum.HumanoidStateType.Landed or new==Enum.HumanoidStateType.Running then
                lj_used=false; landConn:Disconnect()
            end
        end)
    end)
end

local mj_cd=0
local function minijump_start()
    features.MiniJump.conn=UserInputService.InputBegan:Connect(function(input,gpe)
        if gpe then return end
        if input.KeyCode~=Enum.KeyCode.C then return end
        if not humanoid or not hrp then return end
        local now=tick()
        if now-mj_cd<0.3 then return end
        mj_cd=now
        local state=humanoid:GetState()
        if state~=Enum.HumanoidStateType.Running and state~=Enum.HumanoidStateType.RunningNoPhysics then return end
        local vel=hrp.AssemblyLinearVelocity
        hrp.AssemblyLinearVelocity=Vector3.new(vel.X,cfg.miniJumpPower,vel.Z)
        humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
    end)
end

-- ================================================================
-- FAKE AIMBOT (cosmetic)
-- ================================================================
local function isEnemy(p)
    local myTeam=player.Team
    if myTeam==nil then return true end
    return p.Team~=myTeam
end

local function getNearestHead()
    local closest,closestDist=nil,math.huge
    local camCF=camera.CFrame
    local camPos=camCF.Position
    local camLook=camCF.LookVector
    local fovRad=math.rad(cfg.aimbotFOV)
    for _,p in ipairs(Players:GetPlayers()) do
        if p==player then continue end
        if not isEnemy(p) then continue end
        local char=p.Character
        if not char then continue end
        local head=char:FindFirstChild("Head")
        local hum=char:FindFirstChildOfClass("Humanoid")
        if not head or not hum or hum.Health<=0 then continue end
        local toHead=(head.Position-camPos)
        local dist=toHead.Magnitude
        local angle=math.acos(math.clamp(camLook:Dot(toHead.Unit),-1,1))
        if angle>fovRad then continue end
        if dist<closestDist then closestDist=dist; closest=head end
    end
    return closest
end

local function fakeaimbot_start()
    features.FakeAimbot.conn=RunService.RenderStepped:Connect(function(dt)
        local held=false
        local btn=cfg.aimbotButton
        if typeof(btn)=="EnumItem" then
            if btn.EnumType==Enum.UserInputType then
                held=UserInputService:IsMouseButtonPressed(btn)
            elseif btn.EnumType==Enum.KeyCode then
                held=UserInputService:IsKeyDown(btn)
            end
        end
        if not held then return end
        local head=getNearestHead()
        if not head then return end
        local dir=(head.Position-camera.CFrame.Position).Unit
        camera.CFrame=camera.CFrame:Lerp(CFrame.lookAt(camera.CFrame.Position,camera.CFrame.Position+dir),
            math.min(dt*cfg.aimbotSmooth,1))
    end)
end

-- ================================================================
-- STOP / TOGGLE movement features
-- ================================================================
local function stopFeature(key)
    local f=features[key]
    if f.conn then f.conn:Disconnect(); f.conn=nil end
    if key=="PixelSurf" or key=="TextureBug" then
        f.surfing=false; f.glideDir=nil; f.glideSpeed=0
        updateTrail(Vector3.zero,false,key)
    end
    if key=="LongJump" then lj_used=false end
end

local refreshIndicators

local function toggleFeature(key)
    local f=features[key]
    f.enabled=not f.enabled
    if f.enabled then
        if     key=="PixelSurf"  then makeSurf(key,Vector3.new(0,0,0),   function() return cfg.pixelMaxSpeed   end)
        elseif key=="TextureBug" then makeSurf(key,Vector3.new(0,2.5,0), function() return cfg.textureMaxSpeed end)
        elseif key=="AutoBhop"   then bhop_start()
        elseif key=="EdgeBug"    then edgebug_start()
        elseif key=="JumpBug"    then jumpbug_start()
        elseif key=="LongJump"   then longjump_start()
        elseif key=="MiniJump"   then minijump_start()
        elseif key=="FakeAimbot" then fakeaimbot_start()
        end
    else stopFeature(key) end
    if refreshIndicators then refreshIndicators() end
    return f.enabled
end

-- ================================================================
-- ESP SYSTEM (Drawing library)
-- ================================================================

local r15_bones = {
    {"Head", "UpperTorso"},
    {"UpperTorso", "LowerTorso"},
    {"UpperTorso", "LeftUpperArm"},
    {"LeftUpperArm", "LeftLowerArm"},
    {"LeftLowerArm", "LeftHand"},
    {"UpperTorso", "RightUpperArm"},
    {"RightUpperArm", "RightLowerArm"},
    {"RightLowerArm", "RightHand"},
    {"LowerTorso", "LeftUpperLeg"},
    {"LeftUpperLeg", "LeftLowerLeg"},
    {"LeftLowerLeg", "LeftFoot"},
    {"LowerTorso", "RightUpperLeg"},
    {"RightUpperLeg", "RightLowerLeg"},
    {"RightLowerLeg", "RightFoot"}
}

local r6_bones = {
    {"Head", "Torso"},
    {"Torso", "Left Arm"},
    {"Torso", "Right Arm"},
    {"Torso", "Left Leg"},
    {"Torso", "Right Leg"}
}

local custom_bones = {
    {"Head", "Torso"},
    {"Torso", "Left Upper Arm"},
    {"Left Upper Arm", "Left Lower Arm"},
    {"Left Lower Arm", "Left Hand"},
    {"Torso", "Right Upper Arm"},
    {"Right Upper Arm", "Right Lower Arm"},
    {"Right Lower Arm", "Right Hand"},
    {"Torso", "Left Upper Leg"},
    {"Left Upper Leg", "Left Lower Leg"},
    {"Left Lower Leg", "Left Foot"},
    {"Torso", "Right Upper Leg"},
    {"Right Upper Leg", "Right Lower Leg"},
    {"Right Lower Leg", "Right Foot"}
}

local function w2s(pos)
    local vec, onscreen = camera:WorldToViewportPoint(pos)
    return Vector2.new(vec.X, vec.Y), onscreen
end

local function create_line()
    local line = Drawing.new("Line")
    line.Visible = false
    line.Thickness = ESP_CFG.skeleton_thickness
    line.Color = ESP_CFG.skeleton_color
    line.Transparency = ESP_CFG.skeleton_transparency
    return line
end

local function create_text()
    local text = Drawing.new("Text")
    text.Visible = false
    text.Center = true
    text.Outline = true
    text.Font = 2
    return text
end

local function create_square()
    local square = Drawing.new("Square")
    square.Visible = false
    square.Filled = false
    return square
end

local function cl(p)
    if espObjects[p] then
        if espObjects[p].lines then
            for _, bone_data in pairs(espObjects[p].lines) do
                if bone_data.line then bone_data.line:Remove() end
            end
        end
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

local function rig(c)
    local h = c:FindFirstChildOfClass("Humanoid")
    if h and h.RigType == Enum.HumanoidRigType.R15 then return r15_bones end
    if c:FindFirstChild("Left Upper Arm") then return custom_bones end
    return r6_bones
end

local function makeESP(p)
    if not p:IsA("Player") or not espEnabled then return end
    if p.Team == player.Team and p.Team ~= nil then
        cl(p); return
    end
    cl(p)
    local c = p.Character
    if not c then return end
    local h = c:FindFirstChildOfClass("Humanoid")
    if not h or h.Health <= 0 then return end
    local hrp = c:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    if ESP_CFG.crouch_detection then
        crouching[p] = h.HipHeight < ESP_CFG.crouch_height_threshold
    end
    local bones = rig(c)
    local lines = {}
    for _, bone in pairs(bones) do
        local part1 = c:FindFirstChild(bone[1])
        local part2 = c:FindFirstChild(bone[2])
        if part1 and part2 then
            local line = create_line()
            table.insert(lines, {line = line, p1 = part1, p2 = part2})
        end
    end
    local box = ESP_CFG.box_enabled and create_square() or nil
    local box_outline = (ESP_CFG.box_enabled and ESP_CFG.box_thickness > 0) and create_square() or nil
    local box_fill = (ESP_CFG.box_enabled and ESP_CFG.box_filled) and create_square() or nil
    if box_outline then
        box_outline.Thickness = ESP_CFG.box_thickness + 1
        box_outline.Color = Color3.new(0, 0, 0)
    end
    if box_fill then
        box_fill.Filled = true
        box_fill.Color = ESP_CFG.box_fill_color
        box_fill.Transparency = ESP_CFG.box_fill_transparency
    end
    local healthbar_bg = ESP_CFG.healthbar_enabled and create_square() or nil
    local healthbar = ESP_CFG.healthbar_enabled and create_square() or nil
    if healthbar_bg then
        healthbar_bg.Filled = true
        healthbar_bg.Color = Color3.new(0, 0, 0)
        healthbar_bg.Transparency = 0.5
    end
    if healthbar then healthbar.Filled = true end
    local name_text = ESP_CFG.name_enabled and create_text() or nil
    if name_text then
        name_text.Size = ESP_CFG.name_size
        name_text.Color = ESP_CFG.name_color
        name_text.Outline = ESP_CFG.name_outline
    end
    local distance_text = ESP_CFG.distance_enabled and create_text() or nil
    if distance_text then
        distance_text.Size = ESP_CFG.distance_size
        distance_text.Color = ESP_CFG.distance_color
        distance_text.Outline = true
    end
    local tracer = ESP_CFG.tracer_enabled and create_line() or nil
    local tracer_outline = (ESP_CFG.tracer_enabled and ESP_CFG.tracer_thickness > 1) and create_line() or nil
    if tracer then
        tracer.Thickness = ESP_CFG.tracer_thickness
        tracer.Color = ESP_CFG.tracer_color
        tracer.Transparency = ESP_CFG.tracer_transparency
    end
    if tracer_outline then
        tracer_outline.Thickness = ESP_CFG.tracer_thickness + 2
        tracer_outline.Color = Color3.new(0, 0, 0)
        tracer_outline.Transparency = ESP_CFG.tracer_transparency * 0.5
    end
    espObjects[p] = {
        lines = lines, character = c, humanoid = h,
        box = box, box_outline = box_outline, box_fill = box_fill,
        healthbar_bg = healthbar_bg, healthbar = healthbar,
        name = name_text, distance = distance_text,
        tracer = tracer, tracer_outline = tracer_outline
    }
end

local function get_character_bounds(c)
    local hrp = c:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end
    local corners = {}
    local size = hrp.Size
    local cf = hrp.CFrame
    local offsets = {
        Vector3.new(size.X/2, size.Y/2, size.Z/2),
        Vector3.new(-size.X/2, size.Y/2, size.Z/2),
        Vector3.new(size.X/2, -size.Y/2, size.Z/2),
        Vector3.new(-size.X/2, -size.Y/2, size.Z/2),
        Vector3.new(size.X/2, size.Y/2, -size.Z/2),
        Vector3.new(-size.X/2, size.Y/2, -size.Z/2),
        Vector3.new(size.X/2, -size.Y/2, -size.Z/2),
        Vector3.new(-size.X/2, -size.Y/2, -size.Z/2)
    }
    for _, offset in pairs(offsets) do
        local worldPos = cf:PointToWorldSpace(offset)
        local screenPos, onScreen = w2s(worldPos)
        if onScreen then table.insert(corners, screenPos) end
    end
    if #corners == 0 then return nil end
    local minX, maxX = math.huge, -math.huge
    local minY, maxY = math.huge, -math.huge
    for _, corner in pairs(corners) do
        minX = math.min(minX, corner.X)
        maxX = math.max(maxX, corner.X)
        minY = math.min(minY, corner.Y)
        maxY = math.max(maxY, corner.Y)
    end
    return {
        topLeft = Vector2.new(minX, minY),
        size = Vector2.new(maxX - minX, maxY - minY),
        center = Vector2.new((minX + maxX) / 2, (minY + maxY) / 2)
    }
end

local function updateESP()
    for p, data in pairs(espObjects) do
        local c = data.character
        local h = data.humanoid
        if not c or not c.Parent or not h or h.Health <= 0 then cl(p); continue end
        local hrp = c:FindFirstChild("HumanoidRootPart")
        if not hrp then cl(p); continue end
        if ESP_CFG.crouch_detection and h then
            crouching[p] = h.HipHeight < ESP_CFG.crouch_height_threshold
        end
        local is_crouching = crouching[p]
        local skel_color = is_crouching and ESP_CFG.crouch_color or ESP_CFG.skeleton_color
        if data.lines then
            for _, bone_data in pairs(data.lines) do
                local line = bone_data.line
                local p1 = bone_data.p1
                local p2 = bone_data.p2
                if p1 and p1.Parent and p2 and p2.Parent then
                    local pos1, on1 = w2s(p1.Position)
                    local pos2, on2 = w2s(p2.Position)
                    if on1 and on2 then
                        line.From = pos1; line.To = pos2
                        line.Color = skel_color
                        line.Thickness = ESP_CFG.skeleton_thickness
                        line.Transparency = ESP_CFG.skeleton_transparency
                        line.Visible = true
                    else line.Visible = false end
                else line.Visible = false end
            end
        end
        local bounds = get_character_bounds(c)
        if bounds then
            if ESP_CFG.box_enabled and data.box then
                if data.box_outline then
                    data.box_outline.Position = bounds.topLeft - Vector2.new(1, 1)
                    data.box_outline.Size = bounds.size + Vector2.new(2, 2)
                    data.box_outline.Visible = true
                end
                if data.box_fill then
                    data.box_fill.Position = bounds.topLeft
                    data.box_fill.Size = bounds.size
                    data.box_fill.Visible = true
                end
                data.box.Position = bounds.topLeft
                data.box.Size = bounds.size
                data.box.Color = ESP_CFG.box_color
                data.box.Thickness = ESP_CFG.box_thickness
                data.box.Visible = true
            else
                if data.box then data.box.Visible = false end
                if data.box_outline then data.box_outline.Visible = false end
                if data.box_fill then data.box_fill.Visible = false end
            end
            if ESP_CFG.healthbar_enabled and data.healthbar and data.healthbar_bg then
                local barWidth = 3
                local barHeight = bounds.size.Y
                local healthPercent = h.Health / h.MaxHealth
                data.healthbar_bg.Position = Vector2.new(bounds.topLeft.X - barWidth - 3, bounds.topLeft.Y)
                data.healthbar_bg.Size = Vector2.new(barWidth, barHeight)
                data.healthbar_bg.Visible = true
                local currentHeight = barHeight * healthPercent
                data.healthbar.Position = Vector2.new(bounds.topLeft.X - barWidth - 3, bounds.topLeft.Y + barHeight - currentHeight)
                data.healthbar.Size = Vector2.new(barWidth, currentHeight)
                data.healthbar.Color = ESP_CFG.healthbar_color_high:Lerp(ESP_CFG.healthbar_color_low, 1 - healthPercent)
                data.healthbar.Visible = true
            else
                if data.healthbar then data.healthbar.Visible = false end
                if data.healthbar_bg then data.healthbar_bg.Visible = false end
            end
            if ESP_CFG.name_enabled and data.name then
                data.name.Text = p.DisplayName
                data.name.Position = Vector2.new(bounds.center.X, bounds.topLeft.Y - 15)
                data.name.Color = ESP_CFG.name_color
                data.name.Size = ESP_CFG.name_size
                data.name.Visible = true
            else
                if data.name then data.name.Visible = false end
            end
            if ESP_CFG.distance_enabled and data.distance then
                local dist = (hrp.Position - camera.CFrame.Position).Magnitude
                data.distance.Text = string.format("%d studs", math.floor(dist))
                data.distance.Position = Vector2.new(bounds.center.X, bounds.topLeft.Y + bounds.size.Y + 2)
                data.distance.Color = ESP_CFG.distance_color
                data.distance.Size = ESP_CFG.distance_size
                data.distance.Visible = true
            else
                if data.distance then data.distance.Visible = false end
            end
        else
            if data.box then data.box.Visible = false end
            if data.box_outline then data.box_outline.Visible = false end
            if data.box_fill then data.box_fill.Visible = false end
            if data.healthbar then data.healthbar.Visible = false end
            if data.healthbar_bg then data.healthbar_bg.Visible = false end
            if data.name then data.name.Visible = false end
            if data.distance then data.distance.Visible = false end
        end
        if ESP_CFG.tracer_enabled and data.tracer then
            local pos, onscreen = w2s(hrp.Position)
            if onscreen then
                local fromPos
                if ESP_CFG.tracer_from == "Bottom" then fromPos = Vector2.new(camera.ViewportSize.X / 2, camera.ViewportSize.Y)
                elseif ESP_CFG.tracer_from == "Middle" then fromPos = Vector2.new(camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2)
                elseif ESP_CFG.tracer_from == "Top" then fromPos = Vector2.new(camera.ViewportSize.X / 2, 0)
                elseif ESP_CFG.tracer_from == "Mouse" then fromPos = Vector2.new(mouse.X, mouse.Y) end
                if data.tracer_outline then
                    data.tracer_outline.From = fromPos; data.tracer_outline.To = pos
                    data.tracer_outline.Visible = true
                end
                data.tracer.From = fromPos; data.tracer.To = pos
                data.tracer.Color = ESP_CFG.tracer_color
                data.tracer.Visible = true
            else
                data.tracer.Visible = false
                if data.tracer_outline then data.tracer_outline.Visible = false end
            end
        else
            if data.tracer then data.tracer.Visible = false end
            if data.tracer_outline then data.tracer_outline.Visible = false end
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
    else if espConn then espConn:Disconnect(); espConn = nil end
        for _, p in pairs(Players:GetPlayers()) do cl(p) end end
end

Players.PlayerAdded:Connect(function(p)
    if not espEnabled then return end
    p.CharacterAdded:Connect(function() task.wait(1); if p ~= player and espEnabled then makeESP(p) end end)
end)
Players.PlayerRemoving:Connect(function(p) if espEnabled then cl(p) end end)

-- ================================================================
-- SKINS SYSTEM
-- ================================================================

local function resolvePartName(skinEntryName)
    return skinEntryName:gsub("%s+", "")
end

local function getEquippedGunName()
    local char = player.Character
    if not char then return nil end
    local gun = char:FindFirstChild("Gun")
    if not gun then return nil end
    return gun:GetAttribute("GunName")
end

local function getArms()
    local cam = workspace:FindFirstChild("Camera")
    return cam and cam:FindFirstChild("Arms") or nil
end

local function snapshotOriginals(gunName, arms)
    if skinOriginals[gunName] then return end
    local snap = {}
    for _, p in ipairs(arms:GetChildren()) do
        if p:IsA("MeshPart") then snap[p.Name] = p.TextureID end
    end
    skinOriginals[gunName] = snap
end

local skinMapCache = {}
local function buildSkinMap(gunName, skinName)
    local gunSkins = ReplicatedStorage:FindFirstChild("Skins") and ReplicatedStorage.Skins:FindFirstChild(gunName)
    if not gunSkins then return nil end
    local skin = gunSkins:FindFirstChild(skinName)
    if not skin then return nil end
    local map = {}
    local function add(sv)
        if sv:IsA("StringValue") then
            map[sv.Name] = sv.Value
            map[resolvePartName(sv.Name)] = sv.Value
        end
    end
    local wm = skin:FindFirstChild("WorldModel")
    if wm then for _, sv in ipairs(wm:GetChildren()) do add(sv) end end
    for _, sv in ipairs(skin:GetChildren()) do add(sv) end
    return map
end

local function startSkinLoop()
    if skinConn then skinConn:Disconnect() end
    skinConn = RunService.RenderStepped:Connect(function()
        local arms = getArms()
        if not arms then return end
        local gunName = getEquippedGunName()
        if not gunName then return end
        snapshotOriginals(gunName, arms)
        local sel = skinSelections[gunName]
        if sel then
            local cacheKey = gunName .. "|" .. sel
            local map = skinMapCache[cacheKey]
            if map == nil then map = buildSkinMap(gunName, sel) or false; skinMapCache[cacheKey] = map end
            if map then
                for _, p in ipairs(arms:GetChildren()) do
                    if p:IsA("MeshPart") then
                        local tex = map[p.Name] or map[resolvePartName(p.Name)]
                        if tex and p.TextureID ~= tex then p.TextureID = tex end
                    end
                end
            end
        else
            local orig = skinOriginals[gunName]
            if orig then
                for _, p in ipairs(arms:GetChildren()) do
                    if p:IsA("MeshPart") and orig[p.Name] and p.TextureID ~= orig[p.Name] then
                        p.TextureID = orig[p.Name]
                    end
                end
            end
        end
    end)
end

local function stopSkinLoop()
    if skinConn then skinConn:Disconnect(); skinConn = nil end
end

-- ================================================================
-- VISUALS (fog, blur)
-- ================================================================
local Lighting = game:GetService("Lighting")
local origFogEnd   = Lighting.FogEnd
local origFogStart = Lighting.FogStart
local origFogColor = Lighting.FogColor
local blurEffect = nil
local fogConn, blurConn = nil, nil

local function setFog(enabled)
    if enabled then
        fogConn = RunService.Heartbeat:Connect(function()
            pcall(function() Lighting.FogEnd = cfg.fogEnd; Lighting.FogStart = math.max(0, cfg.fogEnd - 60); Lighting.FogColor = Color3.fromRGB(190, 190, 190) end)
        end)
    else
        if fogConn then fogConn:Disconnect(); fogConn = nil end
        pcall(function() Lighting.FogEnd = origFogEnd; Lighting.FogStart = origFogStart; Lighting.FogColor = origFogColor end)
    end
end

local prevCamPos = nil
local function setBlur(enabled)
    if enabled then
        if not blurEffect then blurEffect = Instance.new("BlurEffect"); blurEffect.Size = 0; blurEffect.Parent = Lighting end
        prevCamPos = camera.CFrame.Position
        blurConn = RunService.RenderStepped:Connect(function()
            if not blurEffect then return end
            local curPos = camera.CFrame.Position
            local moved = (curPos - prevCamPos).Magnitude
            local target = math.clamp(moved * cfg.blurSize, 0, 56)
            blurEffect.Size = blurEffect.Size + (target - blurEffect.Size) * 0.3
            prevCamPos = curPos
        end)
    else
        if blurConn then blurConn:Disconnect(); blurConn = nil end
        if blurEffect then blurEffect:Destroy(); blurEffect = nil end
    end
end

-- ================================================================
-- LARP WATERMARK
-- ================================================================
local larpWatermarkGui = nil
local larpWatermarkEnabled = false
local larpRenderConnection = nil

local function toggleLarpWatermark(enabled)
    larpWatermarkEnabled = enabled
    if enabled then
        if larpWatermarkGui then larpWatermarkGui:Destroy() end
        larpWatermarkGui = Instance.new("ScreenGui")
        larpWatermarkGui.Name = "LarpWatermark"; larpWatermarkGui.ResetOnSpawn = false
        larpWatermarkGui.IgnoreGuiInset = true; larpWatermarkGui.Parent = player:WaitForChild("PlayerGui")
        local mainFrame = Instance.new("Frame")
        mainFrame.Size = UDim2.new(0, 149, 0, 28); mainFrame.AnchorPoint = Vector2.new(1, 0)
        mainFrame.Position = UDim2.new(1, -15, 0, 38)
        mainFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 25); mainFrame.BorderSizePixel = 0
        mainFrame.ClipsDescendants = true; mainFrame.Parent = larpWatermarkGui
        local stroke = Instance.new("UIStroke"); stroke.Color = Color3.fromRGB(60, 60, 60)
        stroke.Thickness = 1.5; stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; stroke.Parent = mainFrame
        local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 8); corner.Parent = mainFrame
        local logoImage = Instance.new("ImageLabel")
        logoImage.Size = UDim2.new(0, 63, 0, 63); logoImage.Position = UDim2.new(0, -15, 0.2, -25)
        logoImage.BackgroundTransparency = 1; logoImage.Image = "rbxassetid://133887132709020"
        logoImage.ImageTransparency = 0.7; logoImage.ScaleType = Enum.ScaleType.Fit
        logoImage.ZIndex = 1; logoImage.Parent = mainFrame
        local textLabel = Instance.new("TextLabel")
        textLabel.Size = UDim2.new(1, -10, 1, 0); textLabel.Position = UDim2.new(0, 8, 0, 0)
        textLabel.BackgroundTransparency = 1; textLabel.Text = "larp | user | 0 fps"
        textLabel.TextColor3 = Color3.fromRGB(255, 255, 255); textLabel.Font = Enum.Font.GothamMedium
        textLabel.TextSize = 13; textLabel.TextXAlignment = Enum.TextXAlignment.Left
        textLabel.ZIndex = 2; textLabel.RichText = true; textLabel.Parent = mainFrame
        local lastUpdate = tick(); local frameCount = 0; local fps = 0
        local function updateDisplay()
            frameCount = frameCount + 1
            if tick() - lastUpdate >= 0.5 then
                fps = math.floor(frameCount / (tick() - lastUpdate)); frameCount = 0; lastUpdate = tick()
                textLabel.Text = string.format('<font color="rgb(79,144,85)" face="GothamBold">larp</font> <font color="rgb(80,80,80)">|</font> <font color="rgb(150,150,150)">%s</font> <font color="rgb(80,80,80)">|</font> <font face="GothamBold">%d</font> <font color="rgb(150,150,150)">fps</font>', player.Name, fps)
            end
        end
        larpRenderConnection = RunService.RenderStepped:Connect(updateDisplay)
    else
        if larpRenderConnection then larpRenderConnection:Disconnect(); larpRenderConnection = nil end
        if larpWatermarkGui then larpWatermarkGui:Destroy(); larpWatermarkGui = nil end
    end
end

-- ================================================================
-- MOMENTUM TRACKER
-- ================================================================
local momentumGui = nil
local momentumEnabled = false
local momentumConnection = nil
local jumpConnection = nil
local charConnection = nil

local function toggleMomentum(enabled)
    momentumEnabled = enabled
    if enabled then
        if momentumGui then momentumGui:Destroy() end
        momentumGui = Instance.new("ScreenGui"); momentumGui.Name = "ClarityMomentum"
        momentumGui.ResetOnSpawn = false; momentumGui.IgnoreGuiInset = true
        momentumGui.Parent = player:WaitForChild("PlayerGui")
        local textLabel = Instance.new("TextLabel")
        textLabel.Size = UDim2.new(0, 400, 0, 50); textLabel.Position = UDim2.new(0.5, -200, 0.85, 0)
        textLabel.BackgroundTransparency = 1; textLabel.Text = "0 (0)"
        textLabel.Font = Enum.Font.Nunito; textLabel.TextSize = 30
        textLabel.TextColor3 = Color3.fromRGB(255, 255, 255); textLabel.ZIndex = 2
        textLabel.RichText = true; textLabel.Parent = momentumGui
        local lastJumpSpeed = 0
        local function bindJump(char)
            if jumpConnection then jumpConnection:Disconnect() end
            local hum = char:WaitForChild("Humanoid", 10)
            if hum then
                jumpConnection = hum.StateChanged:Connect(function(old, new)
                    if new == Enum.HumanoidStateType.Jumping then
                        local hrp = char:FindFirstChild("HumanoidRootPart")
                        if hrp then lastJumpSpeed = math.floor(Vector3.new(hrp.AssemblyLinearVelocity.X, 0, hrp.AssemblyLinearVelocity.Z).Magnitude) end
                    end
                end)
            end
        end
        if player.Character then bindJump(player.Character) end
        charConnection = player.CharacterAdded:Connect(bindJump)
        momentumConnection = RunService.RenderStepped:Connect(function()
            if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
                local hrp = player.Character.HumanoidRootPart
                local vel = hrp.AssemblyLinearVelocity
                local speed = math.floor(Vector3.new(vel.X, 0, vel.Z).Magnitude)
                local targetTransparency = 1 - math.clamp(speed / 15, 0, 1)
                if speed < 2 then targetTransparency = 1 end
                textLabel.TextTransparency = textLabel.TextTransparency + (targetTransparency - textLabel.TextTransparency) * 0.1
                textLabel.Text = string.format("%d (%d)", speed, lastJumpSpeed)
            end
        end)
    else
        if momentumConnection then momentumConnection:Disconnect(); momentumConnection = nil end
        if jumpConnection then jumpConnection:Disconnect(); jumpConnection = nil end
        if charConnection then charConnection:Disconnect(); charConnection = nil end
        if momentumGui then momentumGui:Destroy(); momentumGui = nil end
    end
end

-- ================================================================
-- RESTART features after respawn
-- ================================================================
local function restartFeature(key)
    local f = features[key]
    if f.conn then f.conn:Disconnect(); f.conn = nil end
    if     key == "PixelSurf"  then makeSurf(key, Vector3.new(0,0,0),   function() return cfg.pixelMaxSpeed   end)
    elseif key == "TextureBug" then makeSurf(key, Vector3.new(0,2.5,0), function() return cfg.textureMaxSpeed end)
    elseif key == "AutoBhop"   then bhop_start()
    elseif key == "EdgeBug"    then edgebug_start()
    elseif key == "JumpBug"    then jumpbug_start()
    elseif key == "LongJump"   then longjump_start()
    elseif key == "MiniJump"   then minijump_start()
    elseif key == "FakeAimbot" then fakeaimbot_start()
    end
end

player.CharacterAdded:Connect(function(char)
    bindCharacter(char); task.wait(0.5)
    for key, f in pairs(features) do if f.enabled then restartFeature(key) end end
    if espEnabled then refreshESP() end
    if momentumEnabled then toggleMomentum(false); toggleMomentum(true) end
end)

-- ================================================================
-- UI – Clarity style
-- ================================================================

local G = {
    BG        = Color3.fromRGB(13, 13, 15),
    SIDEBAR   = Color3.fromRGB(10, 10, 12),
    PANEL     = Color3.fromRGB(18, 18, 22),
    DIV       = Color3.fromRGB(30, 30, 38),
    ROW_HVR   = Color3.fromRGB(20, 20, 26),
    GREEN     = Color3.fromRGB(76, 210, 96),
    GREEN_DIM = Color3.fromRGB(30,  80,  40),
    WHITE     = Color3.fromRGB(230, 230, 230),
    DIM       = Color3.fromRGB(90,  90, 105),
    MUTE      = Color3.fromRGB(45,  45,  55),
    CB_OFF    = Color3.fromRGB(25,  25,  32),
    TRACK_BG  = Color3.fromRGB(32,  32,  42),
}

local WIN_W, WIN_H = 500, 580
local SB_W = 118
local TW   = 110

local featureBinds    = {}
local indicatorLabels = {}

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "DwbiMenu"; screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Global
screenGui.DisplayOrder = 9999; screenGui.IgnoreGuiInset = true
screenGui.Parent = player:WaitForChild("PlayerGui")

-- Watermark
local wmFrame = Instance.new("Frame")
wmFrame.Size = UDim2.new(0,0,0,22); wmFrame.AutomaticSize = Enum.AutomaticSize.X
wmFrame.Position = UDim2.new(1,0,0,8); wmFrame.AnchorPoint = Vector2.new(1,0)
wmFrame.BackgroundColor3 = G.SIDEBAR; wmFrame.BorderSizePixel = 0; wmFrame.ZIndex = 10
wmFrame.Parent = screenGui
Instance.new("UICorner", wmFrame).CornerRadius = UDim.new(0,4)
local wmStroke = Instance.new("UIStroke", wmFrame); wmStroke.Color = G.DIV; wmStroke.Thickness = 1
local wmPad = Instance.new("UIPadding", wmFrame); wmPad.PaddingLeft = UDim.new(0,8); wmPad.PaddingRight = UDim.new(0,8)
local wmLayout = Instance.new("UIListLayout", wmFrame)
wmLayout.FillDirection = Enum.FillDirection.Horizontal
wmLayout.VerticalAlignment = Enum.VerticalAlignment.Center; wmLayout.Padding = UDim.new(0,0)
local function wmPart(txt, col)
    local l = Instance.new("TextLabel"); l.Size = UDim2.new(0,0,1,0); l.AutomaticSize = Enum.AutomaticSize.X
    l.BackgroundTransparency = 1; l.Text = txt; l.TextColor3 = col
    l.Font = Enum.Font.GothamMedium; l.TextSize = 11; l.ZIndex = 11; l.Parent = wmFrame
    return l
end
local wmName  = wmPart("dwbi", G.GREEN)
local wmSep1  = wmPart(" | ", G.MUTE)
local wmUser  = wmPart(player.Name, G.WHITE)
local wmSep2  = wmPart(" | ", G.MUTE)
local wmFps   = wmPart("0 fps", G.DIM)
local fpsCounter = 0
RunService.RenderStepped:Connect(function(dt)
    fpsCounter = fpsCounter + 1
    if fpsCounter >= 10 then fpsCounter = 0; wmFps.Text = math.floor(1 / math.max(dt, 0.001) + 0.5).." fps" end
end)

-- Indicator bar
local indBar = Instance.new("Frame")
indBar.Size = UDim2.new(0,0,0,22); indBar.AutomaticSize = Enum.AutomaticSize.X
indBar.Position = UDim2.new(0.5,0,1,-10); indBar.AnchorPoint = Vector2.new(0.5,1)
indBar.BackgroundColor3 = G.SIDEBAR; indBar.BorderSizePixel = 0; indBar.ZIndex = 10
indBar.Parent = screenGui
Instance.new("UICorner", indBar).CornerRadius = UDim.new(0,4)
local ibStroke = Instance.new("UIStroke", indBar); ibStroke.Color = G.DIV; ibStroke.Thickness = 1
local ibLayout = Instance.new("UIListLayout", indBar); ibLayout.FillDirection = Enum.FillDirection.Horizontal; ibLayout.Padding = UDim.new(0,6)
local ibPad = Instance.new("UIPadding", indBar); ibPad.PaddingLeft = UDim.new(0,8); ibPad.PaddingRight = UDim.new(0,8); ibPad.PaddingTop = UDim.new(0,3); ibPad.PaddingBottom = UDim.new(0,3)
local IND_ORDER = {"ps","tb","lj","mj","jb","bh","eb","amb"}
local IND_MAP   = {ps="PixelSurf",tb="TextureBug",lj="LongJump", mj="MiniJump",jb="JumpBug",bh="AutoBhop", eb="EdgeBug",amb="FakeAimbot"}
for i,tag in ipairs(IND_ORDER) do
    local key = IND_MAP[tag]
    local l = Instance.new("TextLabel"); l.Size = UDim2.new(0,0,1,0); l.AutomaticSize = Enum.AutomaticSize.X
    l.BackgroundTransparency = 1; l.Text = tag; l.TextColor3 = G.MUTE
    l.Font = Enum.Font.GothamMedium; l.TextSize = 11; l.LayoutOrder = i; l.ZIndex = 11; l.Parent = indBar
    indicatorLabels[key] = l
end
refreshIndicators = function()
    for key, lbl in pairs(indicatorLabels) do
        local f = features[key]; if not f then continue end
        if not f.enabled then lbl.TextColor3 = G.MUTE
        elseif (key == "PixelSurf" or key == "TextureBug") and f.surfing then lbl.TextColor3 = G.GREEN
        else lbl.TextColor3 = G.WHITE end
    end
end
RunService.Heartbeat:Connect(refreshIndicators)

-- WASD indicators
local WASD_KEY_SIZE = 20; local WASD_GAP = 2
local wasdBar = Instance.new("Frame"); wasdBar.AutomaticSize = Enum.AutomaticSize.XY
wasdBar.Position = UDim2.new(0.5, 0, 1, -38); wasdBar.AnchorPoint = Vector2.new(0.5, 1)
wasdBar.BackgroundColor3 = G.SIDEBAR; wasdBar.BorderSizePixel = 0; wasdBar.ZIndex = 10
wasdBar.Parent = screenGui
Instance.new("UICorner", wasdBar).CornerRadius = UDim.new(0, 4)
local wasdStroke = Instance.new("UIStroke", wasdBar); wasdStroke.Color = G.DIV; wasdStroke.Thickness = 1
local wasdPad = Instance.new("UIPadding", wasdBar); wasdPad.PaddingTop = UDim.new(0, 4); wasdPad.PaddingBottom = UDim.new(0, 4); wasdPad.PaddingLeft = UDim.new(0, 4); wasdPad.PaddingRight = UDim.new(0, 4)
local WASD_ROW_W = 3 * WASD_KEY_SIZE + 2 * WASD_GAP
local wasdRow1 = Instance.new("Frame", wasdBar); wasdRow1.Size = UDim2.new(0, WASD_ROW_W, 0, WASD_KEY_SIZE); wasdRow1.BackgroundTransparency = 1; wasdRow1.BorderSizePixel = 0; wasdRow1.ZIndex = 10
local wasdRow2 = Instance.new("Frame", wasdBar); wasdRow2.Size = UDim2.new(0, WASD_ROW_W, 0, WASD_KEY_SIZE); wasdRow2.Position = UDim2.new(0, 0, 0, WASD_KEY_SIZE + WASD_GAP); wasdRow2.BackgroundTransparency = 1; wasdRow2.BorderSizePixel = 0; wasdRow2.ZIndex = 10
local function makeKeyBox(parent, label, xOffset)
    local box = Instance.new("Frame", parent); box.Size = UDim2.new(0, WASD_KEY_SIZE, 0, WASD_KEY_SIZE); box.Position = UDim2.new(0, xOffset, 0, 0)
    box.BackgroundColor3 = G.CB_OFF; box.BorderSizePixel = 0; box.ZIndex = 11
    Instance.new("UICorner", box).CornerRadius = UDim.new(0, 3)
    local stroke = Instance.new("UIStroke", box); stroke.Color = G.DIV; stroke.Thickness = 1
    local lbl = Instance.new("TextLabel", box); lbl.Size = UDim2.new(1, 0, 1, 0); lbl.BackgroundTransparency = 1
    lbl.Text = label; lbl.TextColor3 = G.MUTE; lbl.Font = Enum.Font.GothamMedium; lbl.TextSize = 10; lbl.ZIndex = 12
    return box, lbl, stroke
end
local wBox, wLbl, wStroke = makeKeyBox(wasdRow1, "w", WASD_KEY_SIZE + WASD_GAP)
local aBox, aLbl, aStroke = makeKeyBox(wasdRow2, "a", 0)
local sBox, sLbl, sStroke = makeKeyBox(wasdRow2, "s", WASD_KEY_SIZE + WASD_GAP)
local dBox, dLbl, dStroke = makeKeyBox(wasdRow2, "d", (WASD_KEY_SIZE + WASD_GAP) * 2)
local function setKeyLit(box, lbl, stroke, lit)
    if lit then box.BackgroundColor3 = G.GREEN_DIM; stroke.Color = G.GREEN; lbl.TextColor3 = G.GREEN
    else box.BackgroundColor3 = G.CB_OFF; stroke.Color = G.DIV; lbl.TextColor3 = G.MUTE end
end
RunService.RenderStepped:Connect(function()
    setKeyLit(wBox, wLbl, wStroke, UserInputService:IsKeyDown(Enum.KeyCode.W) or UserInputService:IsKeyDown(Enum.KeyCode.Up))
    setKeyLit(aBox, aLbl, aStroke, UserInputService:IsKeyDown(Enum.KeyCode.A) or UserInputService:IsKeyDown(Enum.KeyCode.Left))
    setKeyLit(sBox, sLbl, sStroke, UserInputService:IsKeyDown(Enum.KeyCode.S) or UserInputService:IsKeyDown(Enum.KeyCode.Down))
    setKeyLit(dBox, dLbl, dStroke, UserInputService:IsKeyDown(Enum.KeyCode.D) or UserInputService:IsKeyDown(Enum.KeyCode.Right))
end)

-- Main window
local win = Instance.new("Frame"); win.Size = UDim2.new(0, WIN_W, 0, WIN_H)
win.Position = UDim2.new(0.5, -WIN_W/2, 0.5, -WIN_H/2)
win.BackgroundColor3 = G.BG; win.BorderSizePixel = 0; win.ZIndex = 1; win.Visible = false; win.Parent = screenGui
Instance.new("UICorner", win).CornerRadius = UDim.new(0,6)
local winStroke = Instance.new("UIStroke", win); winStroke.Color = G.DIV; winStroke.Thickness = 1

-- Title bar
local titleBar = Instance.new("Frame", win); titleBar.Size = UDim2.new(1,0,0,30)
titleBar.BackgroundColor3 = G.SIDEBAR; titleBar.BorderSizePixel = 0; titleBar.ZIndex = 2
Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0,6)
local tbFill = Instance.new("Frame", titleBar); tbFill.Size = UDim2.new(1,0,0,8); tbFill.Position = UDim2.new(0,0,1,-8)
tbFill.BackgroundColor3 = G.SIDEBAR; tbFill.BorderSizePixel = 0; tbFill.ZIndex = 2
local tbBorder = Instance.new("Frame", titleBar); tbBorder.Size = UDim2.new(1,0,0,1); tbBorder.Position = UDim2.new(0,0,1,0)
tbBorder.BackgroundColor3 = G.DIV; tbBorder.BorderSizePixel = 0; tbBorder.ZIndex = 3
local tbLeft = Instance.new("Frame", titleBar); tbLeft.Size = UDim2.new(1,-40,1,0); tbLeft.Position = UDim2.new(0,12,0,0)
tbLeft.BackgroundTransparency = 1; tbLeft.ZIndex = 3
local tbLL = Instance.new("UIListLayout", tbLeft); tbLL.FillDirection = Enum.FillDirection.Horizontal; tbLL.VerticalAlignment = Enum.VerticalAlignment.Center; tbLL.Padding = UDim.new(0,0)
local tbA = Instance.new("TextLabel", tbLeft); tbA.Text = "dwbi"; tbA.TextColor3 = G.GREEN; tbA.Font = Enum.Font.GothamMedium; tbA.TextSize = 12; tbA.BackgroundTransparency = 1; tbA.ZIndex = 3
local tbB = Instance.new("TextLabel", tbLeft); tbB.Text = " movement"; tbB.TextColor3 = G.MUTE; tbB.Font = Enum.Font.GothamMedium; tbB.TextSize = 11; tbB.BackgroundTransparency = 1; tbB.ZIndex = 3
local closeBtn = Instance.new("TextButton", titleBar); closeBtn.Size = UDim2.new(0,30,1,0); closeBtn.Position = UDim2.new(1,-30,0,0)
closeBtn.BackgroundTransparency = 1; closeBtn.Text = "x"; closeBtn.TextColor3 = G.DIM
closeBtn.Font = Enum.Font.GothamMedium; closeBtn.TextSize = 16; closeBtn.ZIndex = 3
closeBtn.MouseEnter:Connect(function() closeBtn.TextColor3 = G.WHITE end)
closeBtn.MouseLeave:Connect(function() closeBtn.TextColor3 = G.DIM end)
closeBtn.MouseButton1Click:Connect(function() win.Visible = false end)

-- Drag
local dragging, dragStart, dragOrigin = false, nil, nil
titleBar.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 then dragging = true; dragStart = i.Position; dragOrigin = win.Position end
end)
titleBar.InputEnded:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end end)
UserInputService.InputChanged:Connect(function(i)
    if dragging and i.UserInputType == Enum.UserInputType.MouseMovement then
        local d = i.Position - dragStart
        win.Position = UDim2.new(dragOrigin.X.Scale, dragOrigin.X.Offset + d.X, dragOrigin.Y.Scale, dragOrigin.Y.Offset + d.Y)
    end
end)

-- Body
local body = Instance.new("Frame", win); body.Size = UDim2.new(1,0,1,-30); body.Position = UDim2.new(0,0,0,30)
body.BackgroundTransparency = 1; body.ZIndex = 2

-- Sidebar
local sidebar = Instance.new("Frame", body); sidebar.Size = UDim2.new(0, SB_W, 1, 0)
sidebar.BackgroundColor3 = G.SIDEBAR; sidebar.BorderSizePixel = 0; sidebar.ZIndex = 2
Instance.new("UICorner", sidebar).CornerRadius = UDim.new(0,6)
local sbPT = Instance.new("Frame", sidebar); sbPT.Size = UDim2.new(1,0,0,8); sbPT.BackgroundColor3 = G.SIDEBAR; sbPT.BorderSizePixel = 0; sbPT.ZIndex = 2
local sbPR = Instance.new("Frame", sidebar); sbPR.Size = UDim2.new(0,8,1,0); sbPR.Position = UDim2.new(1,-8,0,0); sbPR.BackgroundColor3 = G.SIDEBAR; sbPR.BorderSizePixel = 0; sbPR.ZIndex = 2
local sbBord = Instance.new("Frame", sidebar); sbBord.Size = UDim2.new(0,1,1,0); sbBord.Position = UDim2.new(1,-1,0,0); sbBord.BackgroundColor3 = G.DIV; sbBord.BorderSizePixel = 0; sbBord.ZIndex = 3

local function makeSbLabel(txt, yPos)
    local f = Instance.new("Frame", sidebar); f.Size = UDim2.new(1,-1,0,18); f.Position = UDim2.new(0,0,0,yPos)
    f.BackgroundTransparency = 1; f.ZIndex = 3
    local l = Instance.new("TextLabel", f); l.Size = UDim2.new(1,-8,1,0); l.Position = UDim2.new(0,8,0,0)
    l.BackgroundTransparency = 1; l.Text = txt; l.TextColor3 = G.MUTE
    l.Font = Enum.Font.GothamMedium; l.TextSize = 8; l.TextXAlignment = Enum.TextXAlignment.Left; l.ZIndex = 4
end

local TAB_DEFS = {
    {id="movement", label="movement", icon="", y=18},
    {id="visuals",  label="visuals",  icon="", y=50},
    {id="skins",    label="skins",    icon="", y=82},
}
local activeTab = "movement"
local navTabs = {}
local contentPanels = {}

local function makeNavTab(def)
    local isActive = (def.id == activeTab)
    local btn = Instance.new("TextButton", sidebar); btn.Size = UDim2.new(1,-1,0,28); btn.Position = UDim2.new(0,0,0,def.y)
    btn.BackgroundColor3 = isActive and G.PANEL or G.SIDEBAR; btn.BorderSizePixel = 0; btn.Text = ""; btn.AutoButtonColor = false; btn.ZIndex = 3
    local accent = Instance.new("Frame", btn); accent.Size = UDim2.new(0,2,0.6,0); accent.Position = UDim2.new(0,0,0.2,0)
    accent.BackgroundColor3 = G.GREEN; accent.BorderSizePixel = 0; accent.ZIndex = 4; accent.Visible = isActive
    local lbl = Instance.new("TextLabel", btn); lbl.Size = UDim2.new(1,-12,1,0); lbl.Position = UDim2.new(0,10,0,0)
    lbl.BackgroundTransparency = 1; lbl.Text = def.label
    lbl.TextColor3 = isActive and G.WHITE or G.DIM; lbl.Font = Enum.Font.GothamMedium; lbl.TextSize = 11
    lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.ZIndex = 4
    navTabs[def.id] = {btn=btn,accent=accent,lbl=lbl}
    return btn
end
makeSbLabel("TABS", 4)
for _, def in ipairs(TAB_DEFS) do makeNavTab(def) end

-- Content panels
local function makePanel(visible)
    local p = Instance.new("ScrollingFrame", body); p.Size = UDim2.new(1,-SB_W,1,0); p.Position = UDim2.new(0,SB_W,0,0)
    p.BackgroundTransparency = 1; p.BorderSizePixel = 0; p.ScrollBarThickness = 3; p.ScrollBarImageColor3 = G.DIV
    p.CanvasSize = UDim2.new(0,0,0,0); p.AutomaticCanvasSize = Enum.AutomaticSize.Y; p.ZIndex = 2; p.Visible = visible
    local list = Instance.new("UIListLayout", p); list.Padding = UDim.new(0,0); list.SortOrder = Enum.SortOrder.LayoutOrder
    local pad = Instance.new("UIPadding", p); pad.PaddingTop = UDim.new(0,8); pad.PaddingBottom = UDim.new(0,10); pad.PaddingLeft = UDim.new(0,10); pad.PaddingRight = UDim.new(0,10)
    return p
end
local movPanel = makePanel(true)
local visPanel = makePanel(false)
local skinPanel = makePanel(false)
contentPanels["movement"] = movPanel
contentPanels["visuals"] = visPanel
contentPanels["skins"] = skinPanel

local function switchTab(tab)
    activeTab = tab
    for id, p in pairs(contentPanels) do p.Visible = (id == tab) end
    for id, t in pairs(navTabs) do
        local act = (id == tab)
        t.btn.BackgroundColor3 = act and G.PANEL or G.SIDEBAR
        t.accent.Visible = act; t.lbl.TextColor3 = act and G.WHITE or G.DIM
    end
end
for _, def in ipairs(TAB_DEFS) do navTabs[def.id].btn.MouseButton1Click:Connect(function() switchTab(def.id) end) end

-- Section header
local function makeSectionHeader(parent, txt)
    local wrap = Instance.new("Frame", parent); wrap.Size = UDim2.new(1,0,0,24); wrap.BackgroundTransparency = 1; wrap.BorderSizePixel = 0; wrap.ZIndex = 3
    local lbl = Instance.new("TextLabel", wrap); lbl.Size = UDim2.new(1,0,0,16); lbl.Position = UDim2.new(0,0,0,6)
    lbl.BackgroundTransparency = 1; lbl.Text = txt; lbl.TextColor3 = G.GREEN; lbl.Font = Enum.Font.GothamMedium; lbl.TextSize = 9; lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.ZIndex = 4
    local div = Instance.new("Frame", wrap); div.Size = UDim2.new(1,0,0,1); div.Position = UDim2.new(0,0,1,-1); div.BackgroundColor3 = G.DIV; div.BorderSizePixel = 0; div.ZIndex = 4
end

-- Slider builder
local function buildSlider(parent, xOff, yOff, labelTxt, minV, maxV, initV, trackW, onCh)
    local row = Instance.new("Frame", parent); row.Size = UDim2.new(1,-xOff,0,14); row.Position = UDim2.new(0,xOff,0,yOff); row.BackgroundTransparency = 1; row.ZIndex = 6
    local sLbl = Instance.new("TextLabel", row); sLbl.Size = UDim2.new(0,34,1,0); sLbl.BackgroundTransparency = 1; sLbl.Text = labelTxt
    sLbl.TextColor3 = G.MUTE; sLbl.Font = Enum.Font.GothamMedium; sLbl.TextSize = 9; sLbl.TextXAlignment = Enum.TextXAlignment.Left; sLbl.ZIndex = 7
    local track = Instance.new("Frame", row); track.Size = UDim2.new(0, trackW, 0, 2); track.Position = UDim2.new(0,36,0.5,-1)
    track.BackgroundColor3 = G.TRACK_BG; track.BorderSizePixel = 0; track.ZIndex = 7
    Instance.new("UICorner", track).CornerRadius = UDim.new(1,0)
    local frac = math.clamp((initV - minV) / (maxV - minV), 0, 1)
    local fill = Instance.new("Frame", track); fill.Size = UDim2.new(frac, 0, 1, 0); fill.BackgroundColor3 = G.GREEN; fill.BorderSizePixel = 0; fill.ZIndex = 8
    Instance.new("UICorner", fill).CornerRadius = UDim.new(1,0)
    local knob = Instance.new("Frame", track); knob.Size = UDim2.new(0,8,0,8); knob.AnchorPoint = Vector2.new(0.5,0.5); knob.Position = UDim2.new(frac,0,0.5,0)
    knob.BackgroundColor3 = G.WHITE; knob.BorderSizePixel = 0; knob.ZIndex = 9
    Instance.new("UICorner", knob).CornerRadius = UDim.new(1,0)
    local valLbl = Instance.new("TextLabel", row); valLbl.Size = UDim2.new(0,32,1,0); valLbl.Position = UDim2.new(0, trackW + 40, 0, 0)
    valLbl.BackgroundTransparency = 1; valLbl.Text = tostring(initV); valLbl.TextColor3 = G.WHITE; valLbl.Font = Enum.Font.GothamMedium; valLbl.TextSize = 9; valLbl.TextXAlignment = Enum.TextXAlignment.Left; valLbl.ZIndex = 7
    local sd = false
    local function apply(ax)
        local t = math.clamp((ax - track.AbsolutePosition.X) / trackW, 0, 1)
        local v = math.floor(minV + t * (maxV - minV) + 0.5); local f2 = (v - minV) / (maxV - minV)
        fill.Size = UDim2.new(f2, 0, 1, 0); knob.Position = UDim2.new(f2, 0, 0.5, 0); valLbl.Text = tostring(v); onCh(v)
    end
    track.InputBegan:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 then sd = true; apply(i.Position.X) end end)
    UserInputService.InputEnded:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 then sd = false end end)
    UserInputService.InputChanged:Connect(function(i) if sd and i.UserInputType == Enum.UserInputType.MouseMovement then apply(i.Position.X) end end)
end

-- Row builder
local function makeRow(feat, parent)
    local hasSlider = (feat.minVal ~= nil); local ROW_H = hasSlider and 50 or 30
    local wrap = Instance.new("Frame", parent); wrap.Size = UDim2.new(1,0,0,ROW_H); wrap.BackgroundColor3 = G.BG; wrap.BorderSizePixel = 0; wrap.ZIndex = 3
    local rowDiv = Instance.new("Frame", wrap); rowDiv.Size = UDim2.new(1,0,0,1); rowDiv.Position = UDim2.new(0,0,1,-1); rowDiv.BackgroundColor3 = G.DIV; rowDiv.BorderSizePixel = 0; rowDiv.ZIndex = 4
    local cb = Instance.new("Frame", wrap); cb.Size = UDim2.new(0,11,0,11); cb.Position = UDim2.new(0,0,0,10); cb.BackgroundColor3 = G.CB_OFF; cb.BorderSizePixel = 0; cb.ZIndex = 4
    Instance.new("UICorner", cb).CornerRadius = UDim.new(0,2)
    local cbS = Instance.new("UIStroke", cb); cbS.Color = G.DIV; cbS.Thickness = 1
    local lbl = Instance.new("TextLabel", wrap); lbl.Size = UDim2.new(1,-80,0,20); lbl.Position = UDim2.new(0,16,0,5)
    lbl.BackgroundTransparency = 1; lbl.Text = feat.label; lbl.TextColor3 = G.DIM; lbl.Font = Enum.Font.GothamMedium; lbl.TextSize = 12; lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.ZIndex = 4
    if feat.hint then
        local hint = Instance.new("TextLabel", wrap); hint.Size = UDim2.new(0,60,0,20); hint.Position = UDim2.new(1,-62,0,5)
        hint.BackgroundTransparency = 1; hint.Text = feat.hint; hint.TextColor3 = G.MUTE; hint.Font = Enum.Font.GothamMedium; hint.TextSize = 9; hint.TextXAlignment = Enum.TextXAlignment.Right; hint.ZIndex = 4
    end
    local cz = Instance.new("TextButton", wrap); cz.Size = UDim2.new(1,0,0, hasSlider and 28 or ROW_H); cz.BackgroundTransparency = 1; cz.Text = ""; cz.ZIndex = 5
    if hasSlider then buildSlider(wrap, 16, 30, feat.sliderLabel or "power", feat.minVal, feat.maxVal, feat.initVal, TW, feat.onChange) end
    local on = false
    local function setOn(v)
        on = v
        if v then cb.BackgroundColor3 = G.GREEN; cbS.Color = G.GREEN; lbl.TextColor3 = G.WHITE
        else cb.BackgroundColor3 = G.CB_OFF; cbS.Color = G.DIV; lbl.TextColor3 = G.DIM end
        toggleFeature(feat.key)
    end
    cz.MouseButton1Click:Connect(function() setOn(not on) end)
    cz.MouseEnter:Connect(function() wrap.BackgroundColor3 = G.ROW_HVR end)
    cz.MouseLeave:Connect(function() wrap.BackgroundColor3 = G.BG end)
    -- Context menu (bind)
    local ctxOpen = false; local ctxFrame = nil
    local function closeCtx() if ctxFrame then ctxFrame:Destroy(); ctxFrame = nil end; ctxOpen = false end
    local function openCtx()
        if ctxOpen then closeCtx(); return end; ctxOpen = true
        local bind = featureBinds[feat.key] or {}
        ctxFrame = Instance.new("Frame", wrap); ctxFrame.Size = UDim2.new(0,158,0,0); ctxFrame.AutomaticSize = Enum.AutomaticSize.Y; ctxFrame.Position = UDim2.new(1,4,0,0)
        ctxFrame.BackgroundColor3 = G.PANEL; ctxFrame.BorderSizePixel = 0; ctxFrame.ZIndex = 20
        Instance.new("UICorner", ctxFrame).CornerRadius = UDim.new(0,5)
        local cs = Instance.new("UIStroke", ctxFrame); cs.Color = G.DIV; cs.Thickness = 1
        local ctxList = Instance.new("UIListLayout", ctxFrame); ctxList.Padding = UDim.new(0,0); ctxList.SortOrder = Enum.SortOrder.LayoutOrder
        local function ctxRow(txt, order, onClick)
            local r = Instance.new("TextButton", ctxFrame); r.Size = UDim2.new(1,0,0,24); r.BackgroundColor3 = G.PANEL; r.BorderSizePixel = 0
            r.Text = txt; r.TextColor3 = G.DIM; r.Font = Enum.Font.GothamMedium; r.TextSize = 10; r.TextXAlignment = Enum.TextXAlignment.Left; r.LayoutOrder = order; r.ZIndex = 21
            local rp = Instance.new("UIPadding", r); rp.PaddingLeft = UDim.new(0,10)
            r.MouseEnter:Connect(function() r.BackgroundColor3 = G.ROW_HVR; r.TextColor3 = G.GREEN end)
            r.MouseLeave:Connect(function() r.BackgroundColor3 = G.PANEL; r.TextColor3 = G.DIM end)
            r.MouseButton1Click:Connect(function() onClick(); closeCtx() end)
        end
        local bindName = bind.keyCode and tostring(bind.keyCode):gsub("Enum.KeyCode.","") or "none"
        ctxRow("bind: "..bindName, 1, function()
            local pf = Instance.new("Frame", screenGui); pf.Size = UDim2.new(0,180,0,36); pf.Position = UDim2.new(0.5,-90,0.5,-18)
            pf.BackgroundColor3 = G.PANEL; pf.BorderSizePixel = 0; pf.ZIndex = 30
            Instance.new("UICorner", pf).CornerRadius = UDim.new(0,6)
            local ps = Instance.new("UIStroke", pf); ps.Color = G.DIV; ps.Thickness = 1
            local pl = Instance.new("TextLabel", pf); pl.Size = UDim2.new(1,0,1,0); pl.BackgroundTransparency = 1
            pl.Text = "press a key..."; pl.TextColor3 = G.DIM; pl.Font = Enum.Font.GothamMedium; pl.TextSize = 11; pl.ZIndex = 31
            local pc; pc = UserInputService.InputBegan:Connect(function(inp, gpe)
                if gpe then return end
                if inp.UserInputType == Enum.UserInputType.Keyboard then
                    if not featureBinds[feat.key] then featureBinds[feat.key] = {} end
                    featureBinds[feat.key].keyCode = inp.KeyCode; pf:Destroy(); if pc then pc:Disconnect() end
                end
            end)
        end)
        local holdTxt = (bind.holdMode and "mode: hold [on]" or "mode: hold [off]")
        ctxRow(holdTxt, 2, function()
            if not featureBinds[feat.key] then featureBinds[feat.key] = {} end
            local b = featureBinds[feat.key]; b.holdMode = not b.holdMode
            if b.holdMode and b.keyCode then
                if b.holdConn then b.holdConn:Disconnect() end
                b.holdConn = UserInputService.InputBegan:Connect(function(inp, gpe) if not gpe and inp.KeyCode == b.keyCode and not on then setOn(true) end end)
                if b.holdEndConn then b.holdEndConn:Disconnect() end
                b.holdEndConn = UserInputService.InputEnded:Connect(function(inp) if inp.KeyCode == b.keyCode and on then setOn(false) end end)
            else if b.holdConn then b.holdConn:Disconnect(); b.holdConn = nil end; if b.holdEndConn then b.holdEndConn:Disconnect(); b.holdEndConn = nil end end
        end)
        ctxRow("clear bind", 3, function()
            local b = featureBinds[feat.key]
            if b then if b.holdConn then b.holdConn:Disconnect() end; if b.holdEndConn then b.holdEndConn:Disconnect() end end
            featureBinds[feat.key] = nil
        end)
    end
    UserInputService.InputBegan:Connect(function(inp, gpe) if gpe then return end; local b = featureBinds[feat.key]; if b and b.keyCode and not b.holdMode and inp.KeyCode == b.keyCode then setOn(not on) end end)
    cz.MouseButton2Click:Connect(openCtx)
    UserInputService.InputBegan:Connect(function(inp) if ctxOpen and inp.UserInputType == Enum.UserInputType.MouseButton1 then task.defer(closeCtx) end end)
end

-- ================================================================
-- POPULATE MOVEMENT PANEL
-- ================================================================
makeSectionHeader(movPanel, "SURF")
makeRow({key="PixelSurf",  label="pixel surf",  hint="auto", sliderLabel="speed", minVal=20, maxVal=200, initVal=cfg.pixelMaxSpeed, onChange=function(v) cfg.pixelMaxSpeed=v end}, movPanel)
makeRow({key="TextureBug", label="texture bug", hint="auto", sliderLabel="speed", minVal=20, maxVal=200, initVal=cfg.textureMaxSpeed, onChange=function(v) cfg.textureMaxSpeed=v end}, movPanel)
makeSectionHeader(movPanel, "MOVEMENT")
makeRow({key="AutoBhop", label="bunny hop", hint="[space]", sliderLabel="boost", minVal=1, maxVal=100, initVal=math.floor(cfg.bhopBoost*10+0.5), onChange=function(v) cfg.bhopBoost=v/10 end}, movPanel)
makeRow({key="EdgeBug",  label="edge bug",  hint="auto"}, movPanel)
makeRow({key="JumpBug",  label="jump bug",  hint="[q]", sliderLabel="power", minVal=10, maxVal=200, initVal=cfg.jumpBugPower, onChange=function(v) cfg.jumpBugPower=v end}, movPanel)
makeRow({key="LongJump", label="long jump", hint="[e]", sliderLabel="power", minVal=20, maxVal=200, initVal=cfg.longJumpPower, onChange=function(v) cfg.longJumpPower=v end}, movPanel)
makeRow({key="MiniJump", label="mini jump", hint="[c]", sliderLabel="power", minVal=5, maxVal=80, initVal=cfg.miniJumpPower, onChange=function(v) cfg.miniJumpPower=v end}, movPanel)

-- Fake aimbot row
makeSectionHeader(movPanel, "AIMBOT")
do
    local ROW_H = 112
    local wrap = Instance.new("Frame", movPanel); wrap.Size = UDim2.new(1,0,0,ROW_H); wrap.BackgroundColor3 = G.BG; wrap.BorderSizePixel = 0; wrap.ZIndex = 3
    local rowDiv = Instance.new("Frame", wrap); rowDiv.Size = UDim2.new(1,0,0,1); rowDiv.Position = UDim2.new(0,0,1,-1); rowDiv.BackgroundColor3 = G.DIV; rowDiv.BorderSizePixel = 0; rowDiv.ZIndex = 4
    local cb = Instance.new("Frame", wrap); cb.Size = UDim2.new(0,11,0,11); cb.Position = UDim2.new(0,0,0,10); cb.BackgroundColor3 = G.CB_OFF; cb.BorderSizePixel = 0; cb.ZIndex = 4
    Instance.new("UICorner", cb).CornerRadius = UDim.new(0,2); local cbS = Instance.new("UIStroke", cb); cbS.Color = G.DIV; cbS.Thickness = 1
    local lbl = Instance.new("TextLabel", wrap); lbl.Size = UDim2.new(1,-80,0,20); lbl.Position = UDim2.new(0,16,0,5); lbl.BackgroundTransparency = 1
    lbl.Text = "fake aimbot"; lbl.TextColor3 = G.DIM; lbl.Font = Enum.Font.GothamMedium; lbl.TextSize = 12; lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.ZIndex = 4
    local cz = Instance.new("TextButton", wrap); cz.Size = UDim2.new(1,0,0,28); cz.BackgroundTransparency = 1; cz.Text = ""; cz.ZIndex = 5
    buildSlider(wrap, 16, 30, "fov", 10, 120, cfg.aimbotFOV, 90, function(v) cfg.aimbotFOV = v end)
    buildSlider(wrap, 16, 48, "smooth", 1, 20, cfg.aimbotSmooth, 90, function(v) cfg.aimbotSmooth = v end)
    local pkRow = Instance.new("Frame", wrap); pkRow.Size = UDim2.new(1,-16,0,18); pkRow.Position = UDim2.new(0,16,0,66); pkRow.BackgroundTransparency = 1; pkRow.ZIndex = 4
    local pkLbl = Instance.new("TextLabel", pkRow); pkLbl.Size = UDim2.new(0,38,1,0); pkLbl.BackgroundTransparency = 1; pkLbl.Text = "aim key"; pkLbl.TextColor3 = G.MUTE; pkLbl.Font = Enum.Font.GothamMedium; pkLbl.TextSize = 9; pkLbl.TextXAlignment = Enum.TextXAlignment.Left; pkLbl.ZIndex = 5
    local pkBtn = Instance.new("TextButton", pkRow); pkBtn.Size = UDim2.new(0,82,1,-2); pkBtn.Position = UDim2.new(0,40,0,1); pkBtn.BackgroundColor3 = G.PANEL; pkBtn.BorderSizePixel = 0
    pkBtn.Text = "rmb"; pkBtn.TextColor3 = G.WHITE; pkBtn.Font = Enum.Font.GothamMedium; pkBtn.TextSize = 9; pkBtn.ZIndex = 5
    Instance.new("UICorner", pkBtn).CornerRadius = UDim.new(0,3); local pkS = Instance.new("UIStroke", pkBtn); pkS.Color = G.DIV; pkS.Thickness = 1
    pkBtn.MouseEnter:Connect(function() pkBtn.BackgroundColor3 = G.ROW_HVR end); pkBtn.MouseLeave:Connect(function() pkBtn.BackgroundColor3 = G.PANEL end)
    local listening = false; local pkConn = nil
    pkBtn.MouseButton1Click:Connect(function()
        if listening then return end; listening = true; pkBtn.Text = "..."; pkBtn.TextColor3 = G.MUTE
        pkConn = UserInputService.InputBegan:Connect(function(input, gpe)
            if gpe then return end; local name
            if input.UserInputType == Enum.UserInputType.MouseButton1 then cfg.aimbotButton = Enum.UserInputType.MouseButton1; name = "lmb"
            elseif input.UserInputType == Enum.UserInputType.MouseButton2 then cfg.aimbotButton = Enum.UserInputType.MouseButton2; name = "rmb"
            elseif input.UserInputType == Enum.UserInputType.MouseButton3 then cfg.aimbotButton = Enum.UserInputType.MouseButton3; name = "mmb"
            elseif input.UserInputType == Enum.UserInputType.Keyboard then cfg.aimbotButton = input.KeyCode; name = tostring(input.KeyCode):gsub("Enum.KeyCode.",""):lower()
            else return end
            pkBtn.Text = name; pkBtn.TextColor3 = G.WHITE; listening = false; if pkConn then pkConn:Disconnect(); pkConn = nil end
        end)
    end)
    local on = false
    local function setOn(v) on = v; if v then cb.BackgroundColor3 = G.GREEN; cbS.Color = G.GREEN; lbl.TextColor3 = G.WHITE else cb.BackgroundColor3 = G.CB_OFF; cbS.Color = G.DIV; lbl.TextColor3 = G.DIM end; toggleFeature("FakeAimbot") end
    cz.MouseButton1Click:Connect(function() setOn(not on) end); cz.MouseEnter:Connect(function() wrap.BackgroundColor3 = G.ROW_HVR end); cz.MouseLeave:Connect(function() wrap.BackgroundColor3 = G.BG end)
end

-- ================================================================
-- POPULATE VISUALS PANEL
-- ================================================================
makeSectionHeader(visPanel, "EFFECTS")
local function makeVisRow(labelTxt, sliderLbl, minV, maxV, initV, onToggle, onSlide)
    local ROW_H = 50
    local wrap = Instance.new("Frame", visPanel); wrap.Size = UDim2.new(1,0,0,ROW_H); wrap.BackgroundColor3 = G.BG; wrap.BorderSizePixel = 0; wrap.ZIndex = 3
    local rowDiv = Instance.new("Frame", wrap); rowDiv.Size = UDim2.new(1,0,0,1); rowDiv.Position = UDim2.new(0,0,1,-1); rowDiv.BackgroundColor3 = G.DIV; rowDiv.BorderSizePixel = 0; rowDiv.ZIndex = 4
    local cb = Instance.new("Frame", wrap); cb.Size = UDim2.new(0,11,0,11); cb.Position = UDim2.new(0,0,0,10); cb.BackgroundColor3 = G.CB_OFF; cb.BorderSizePixel = 0; cb.ZIndex = 4
    Instance.new("UICorner", cb).CornerRadius = UDim.new(0,2); local cbS = Instance.new("UIStroke", cb); cbS.Color = G.DIV; cbS.Thickness = 1
    local lbl = Instance.new("TextLabel", wrap); lbl.Size = UDim2.new(1,-80,0,20); lbl.Position = UDim2.new(0,16,0,5); lbl.BackgroundTransparency = 1
    lbl.Text = labelTxt; lbl.TextColor3 = G.DIM; lbl.Font = Enum.Font.GothamMedium; lbl.TextSize = 12; lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.ZIndex = 4
    local cz = Instance.new("TextButton", wrap); cz.Size = UDim2.new(1,0,0,28); cz.BackgroundTransparency = 1; cz.Text = ""; cz.ZIndex = 5
    buildSlider(wrap, 16, 30, sliderLbl, minV, maxV, initV, TW, onSlide)
    local on = false
    local function setOn(v) on = v; if v then cb.BackgroundColor3 = G.GREEN; cbS.Color = G.GREEN; lbl.TextColor3 = G.WHITE else cb.BackgroundColor3 = G.CB_OFF; cbS.Color = G.DIV; lbl.TextColor3 = G.DIM end; onToggle(v) end
    cz.MouseButton1Click:Connect(function() setOn(not on) end); cz.MouseEnter:Connect(function() wrap.BackgroundColor3 = G.ROW_HVR end); cz.MouseLeave:Connect(function() wrap.BackgroundColor3 = G.BG end)
end
makeVisRow("fog", "distance", 20, 500, cfg.fogEnd, setFog, function(v) cfg.fogEnd = v end)
makeVisRow("motion blur", "intensity", 1, 40, cfg.blurSize, setBlur, function(v) cfg.blurSize = v end)

makeSectionHeader(visPanel, "ESP")
local function makeToggleRow(parent, labelTxt, initOn, onToggle)
    local ROW_H = 30
    local wrap = Instance.new("Frame", parent); wrap.Size = UDim2.new(1,0,0,ROW_H); wrap.BackgroundColor3 = G.BG; wrap.BorderSizePixel = 0; wrap.ZIndex = 3
    local rowDiv = Instance.new("Frame", wrap); rowDiv.Size = UDim2.new(1,0,0,1); rowDiv.Position = UDim2.new(0,0,1,-1); rowDiv.BackgroundColor3 = G.DIV; rowDiv.BorderSizePixel = 0; rowDiv.ZIndex = 4
    local cb = Instance.new("Frame", wrap); cb.Size = UDim2.new(0,11,0,11); cb.Position = UDim2.new(0,0,0,10); cb.BackgroundColor3 = G.CB_OFF; cb.BorderSizePixel = 0; cb.ZIndex = 4
    Instance.new("UICorner", cb).CornerRadius = UDim.new(0,2); local cbS = Instance.new("UIStroke", cb); cbS.Color = G.DIV; cbS.Thickness = 1
    local lbl = Instance.new("TextLabel", wrap); lbl.Size = UDim2.new(1,-16,0,20); lbl.Position = UDim2.new(0,16,0,5); lbl.BackgroundTransparency = 1
    lbl.Text = labelTxt; lbl.TextColor3 = G.DIM; lbl.Font = Enum.Font.GothamMedium; lbl.TextSize = 12; lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.ZIndex = 4
    local cz = Instance.new("TextButton", wrap); cz.Size = UDim2.new(1,0,0,ROW_H); cz.BackgroundTransparency = 1; cz.Text = ""; cz.ZIndex = 5
    local on = initOn
    local function setOn(v) on = v; if v then cb.BackgroundColor3 = G.GREEN; cbS.Color = G.GREEN; lbl.TextColor3 = G.WHITE else cb.BackgroundColor3 = G.CB_OFF; cbS.Color = G.DIV; lbl.TextColor3 = G.DIM end; onToggle(v) end
    setOn(initOn); cz.MouseButton1Click:Connect(function() setOn(not on) end); cz.MouseEnter:Connect(function() wrap.BackgroundColor3 = G.ROW_HVR end); cz.MouseLeave:Connect(function() wrap.BackgroundColor3 = G.BG end)
end
makeToggleRow(visPanel, "enable esp", false, toggleESP)

makeSectionHeader(visPanel, "HUD")
makeToggleRow(visPanel, "watermark", true, function(v) wmFrame.Visible = v end)
makeToggleRow(visPanel, "larp watermark", false, toggleLarpWatermark)
makeToggleRow(visPanel, "momentum", false, toggleMomentum)
makeToggleRow(visPanel, "indicators", true, function(v) indBar.Visible = v end)
makeToggleRow(visPanel, "wasd keys", true, function(v) wasdBar.Visible = v end)

-- ================================================================
-- POPULATE SKINS PANEL
-- ================================================================
makeSectionHeader(skinPanel, "SKIN SELECTOR")

local skinRefreshBtn = Instance.new("TextButton", skinPanel)
skinRefreshBtn.Size = UDim2.new(1, -20, 0, 28); skinRefreshBtn.BackgroundColor3 = G.PANEL; skinRefreshBtn.BorderSizePixel = 0
skinRefreshBtn.Text = "refresh"; skinRefreshBtn.TextColor3 = G.WHITE; skinRefreshBtn.Font = Enum.Font.GothamMedium; skinRefreshBtn.TextSize = 11; skinRefreshBtn.ZIndex = 5
Instance.new("UICorner", skinRefreshBtn).CornerRadius = UDim.new(0, 4)

local skinListHolder = Instance.new("Frame", skinPanel)
skinListHolder.Size = UDim2.new(1, 0, 0, 0); skinListHolder.AutomaticSize = Enum.AutomaticSize.Y
skinListHolder.BackgroundTransparency = 1; skinListHolder.LayoutOrder = 2
local slhList = Instance.new("UIListLayout", skinListHolder); slhList.SortOrder = Enum.SortOrder.LayoutOrder

local currentGunLabel = Instance.new("TextLabel", skinPanel)
currentGunLabel.Size = UDim2.new(1, -20, 0, 22); currentGunLabel.BackgroundTransparency = 1
currentGunLabel.Text = "no weapon equipped"; currentGunLabel.TextColor3 = G.MUTE
currentGunLabel.Font = Enum.Font.GothamMedium; currentGunLabel.TextSize = 10
currentGunLabel.TextXAlignment = Enum.TextXAlignment.Left; currentGunLabel.ZIndex = 4

local function refreshSkinList()
    for _, c in ipairs(skinListHolder:GetChildren()) do if c:IsA("Frame") then c:Destroy() end end
    local gunName = getEquippedGunName()
    if not gunName then currentGunLabel.Text = "no weapon equipped"; return end
    currentGunLabel.Text = "current: " .. gunName
    local gunSkins = ReplicatedStorage:FindFirstChild("Skins") and ReplicatedStorage.Skins:FindFirstChild(gunName)
    if not gunSkins then currentGunLabel.Text = gunName .. " (no skins)"; return end

    -- Default row
    local defWrap = Instance.new("Frame", skinListHolder); defWrap.Size = UDim2.new(1, 0, 0, 28); defWrap.BackgroundColor3 = G.BG; defWrap.BorderSizePixel = 0; defWrap.ZIndex = 3
    local defDiv = Instance.new("Frame", defWrap); defDiv.Size = UDim2.new(1,0,0,1); defDiv.Position = UDim2.new(0,0,1,-1); defDiv.BackgroundColor3 = G.DIV; defDiv.BorderSizePixel = 0; defDiv.ZIndex = 4
    local defLbl = Instance.new("TextLabel", defWrap); defLbl.Size = UDim2.new(1, -16, 1, 0); defLbl.Position = UDim2.new(0, 8, 0, 0); defLbl.BackgroundTransparency = 1
    defLbl.Text = "default"; defLbl.TextColor3 = (skinSelections[gunName] == nil) and G.GREEN or G.DIM
    defLbl.Font = Enum.Font.GothamMedium; defLbl.TextSize = 11; defLbl.TextXAlignment = Enum.TextXAlignment.Left; defLbl.ZIndex = 4
    local defBtn = Instance.new("TextButton", defWrap); defBtn.Size = UDim2.new(1, 0, 1, 0); defBtn.BackgroundTransparency = 1; defBtn.Text = ""; defBtn.ZIndex = 5
    defBtn.MouseButton1Click:Connect(function()
        skinSelections[gunName] = nil; startSkinLoop(); refreshSkinList()
    end)
    defBtn.MouseEnter:Connect(function() defWrap.BackgroundColor3 = G.ROW_HVR end)
    defBtn.MouseLeave:Connect(function() defWrap.BackgroundColor3 = G.BG end)

    for _, skin in ipairs(gunSkins:GetChildren()) do
        local wrap = Instance.new("Frame", skinListHolder); wrap.Size = UDim2.new(1, 0, 0, 28); wrap.BackgroundColor3 = G.BG; wrap.BorderSizePixel = 0; wrap.ZIndex = 3
        local div = Instance.new("Frame", wrap); div.Size = UDim2.new(1,0,0,1); div.Position = UDim2.new(0,0,1,-1); div.BackgroundColor3 = G.DIV; div.BorderSizePixel = 0; div.ZIndex = 4
        local sel = skinSelections[gunName]
        local isSelected = (sel == skin.Name)
        local lbl = Instance.new("TextLabel", wrap); lbl.Size = UDim2.new(1, -16, 1, 0); lbl.Position = UDim2.new(0, 8, 0, 0); lbl.BackgroundTransparency = 1
        lbl.Text = skin.Name; lbl.TextColor3 = isSelected and G.GREEN or G.DIM
        lbl.Font = Enum.Font.GothamMedium; lbl.TextSize = 11; lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.ZIndex = 4
        local btn = Instance.new("TextButton", wrap); btn.Size = UDim2.new(1, 0, 1, 0); btn.BackgroundTransparency = 1; btn.Text = ""; btn.ZIndex = 5
        btn.MouseButton1Click:Connect(function()
            skinSelections[gunName] = skin.Name; startSkinLoop(); refreshSkinList()
        end)
        btn.MouseEnter:Connect(function() wrap.BackgroundColor3 = G.ROW_HVR end)
        btn.MouseLeave:Connect(function() wrap.BackgroundColor3 = G.BG end)
    end
end

skinRefreshBtn.MouseButton1Click:Connect(refreshSkinList)

-- Refresh when switching to skins tab
navTabs["skins"].btn.MouseButton1Click:Connect(function() switchTab("skins"); refreshSkinList() end)

-- ================================================================
-- MENU TOGGLE & UNLOAD
-- ================================================================
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
            toggleESP(false); stopSkinLoop()
            toggleLarpWatermark(false); toggleMomentum(false)
            setFog(false); setBlur(false)
            if fogConn then fogConn:Disconnect() end; if blurConn then blurConn:Disconnect() end
            trailFolder:Destroy(); screenGui:Destroy()
            UserInputService.MouseBehavior = Enum.MouseBehavior.Default; UserInputService.MouseIconEnabled = true
        end
    end
end)
UserInputService.InputEnded:Connect(function(input) unloadHeld[input.KeyCode] = nil end)
