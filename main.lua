-- ================================================================
-- dwbi | movement module
-- Toggle menu: [INSERT] key
-- ================================================================

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local character, humanoid, hrp

local function bindCharacter(char)
    character = char
    humanoid  = char:WaitForChild("Humanoid")
    hrp       = char:WaitForChild("HumanoidRootPart")
end
if player.Character then bindCharacter(player.Character) end
player.CharacterAdded:Connect(bindCharacter)

-- ================================================================
-- CONFIG
-- ================================================================
local cfg = {
    pixelMaxSpeed   = 40,
    textureMaxSpeed = 40,
    bhopBoost       = 3.0,
    jumpBugPower    = 80,   -- extra Y velocity when jumpbug fires  [Q hold]
    longJumpPower   = 90,   -- horizontal burst on longjump         [E press]
    miniJumpPower   = 20,   -- Y velocity for minijump              [C press]
    aimbotFOV       = 60,   -- degrees radius to search for targets
    aimbotSmooth    = 6,    -- lerp speed (lower = snappier)
    aimbotButton    = Enum.UserInputType.MouseButton2,  -- default RMB
    fogEnd          = 200,
    fogStart        = 0,
    blurSize        = 10,
}

local WALL_RANGE  = 2.0
local W_ACCEL     = 14
local BASE_SPEED  = 40
local TRAIL_LIFE  = 1.8
local TRAIL_WIDTH = 0.06

-- ================================================================
-- FEATURE STATE
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

-- ================================================================
-- RAYCAST HELPERS
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
    PARAMS.FilterDescendantsInstances = { character }
    return workspace:Raycast(origin, Vector3.new(0, -dist, 0), PARAMS)
end

local function findWall(originOffset)
    PARAMS.FilterDescendantsInstances = { character }
    local up     = Vector3.new(0, 1, 0)
    local origin = hrp.Position + originOffset
    local vel    = hrp and hrp.AssemblyLinearVelocity or Vector3.zero
    local hVel   = Vector3.new(vel.X, 0, vel.Z)

    for _, dir in ipairs(WALL_DIRS) do
        local hit = workspace:Raycast(origin, dir * WALL_RANGE, PARAMS)
        if not hit then continue end

        local n = hit.Normal

        -- 1. Normal must be nearly horizontal (loosened from 0.43 to 0.55)
        if math.abs(n:Dot(up)) >= 0.55 then continue end

        -- 2. The hit surface must be a BasePart.
        --    Lowered halfH threshold from 2.0 to 0.8 to allow smaller wall segments.
        local inst = hit.Instance
        if not inst:IsA("BasePart") then continue end
        local halfH = inst.Size.Y * 0.5
        if halfH < 0.8 then continue end

        -- 3. We must not be actively moving away from the wall.
        --    Lowered threshold from 0.1 to -0.2 to allow shallow approach angles.
        if hVel.Magnitude > 1 then
            local toward = -n
            if hVel.Unit:Dot(toward) < -0.2 then continue end
        end

        -- 4. Confirm something exists above or below (not just same instance).
        --    Allows segmented/stacked walls to be detected properly.
        local hitPos = hit.Position
        local upCheck   = workspace:Raycast(hitPos + up * 0.1,   dir * (WALL_RANGE + 0.5), PARAMS)
        local downCheck = workspace:Raycast(hitPos - up * 0.1,   dir * (WALL_RANGE + 0.5), PARAMS)
        local wallContinues = (upCheck ~= nil) or (downCheck ~= nil)
        if not wallContinues then continue end

        return n
    end
    return nil
end

-- ================================================================
-- TRAIL
-- ================================================================
local trailFolder = Instance.new("Folder")
trailFolder.Name = "DwbiTrail"; trailFolder.Parent = workspace

local segments = {}
local lastPos  = { PixelSurf=nil, TextureBug=nil }
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
-- SURF (shared by PixelSurf + TextureBug)
-- ================================================================
local function makeSurf(key, originOffset, getMaxSpeed)
    local f=features[key]
    f.conn=RunService.Heartbeat:Connect(function(dt)
        if not hrp or not humanoid then return end
        local state=humanoid:GetState()
        local airborne=state==Enum.HumanoidStateType.Freefall
                    or state==Enum.HumanoidStateType.Jumping
        if not airborne then
            f.surfing=false; f.glideDir=nil; f.glideSpeed=0
            updateTrail(hrp.Position,false,key); return
        end
        local wNormal=findWall(originOffset)
        if not wNormal then
            f.surfing=false; f.glideDir=nil; f.glideSpeed=0
            updateTrail(hrp.Position,false,key); return
        end
        if f.surfing and (
            UserInputService:IsKeyDown(Enum.KeyCode.A) or
            UserInputService:IsKeyDown(Enum.KeyCode.D) or
            UserInputService:IsKeyDown(Enum.KeyCode.Left) or
            UserInputService:IsKeyDown(Enum.KeyCode.Right)) then
            f.surfing=false; f.glideDir=nil; f.glideSpeed=0
            updateTrail(hrp.Position,false,key); return
        end
        local maxSpd=getMaxSpeed()
        if not f.surfing then
            f.surfing=true
            local look=hrp.CFrame.LookVector
            local proj=look-wNormal*look:Dot(wNormal)
            proj=Vector3.new(proj.X,0,proj.Z)
            f.glideDir=proj.Magnitude>0.01 and proj.Unit
                       or Vector3.new(-wNormal.Z,0,wNormal.X).Unit
            local vel=hrp.AssemblyLinearVelocity
            -- clamp entry speed to the configured max immediately
            f.glideSpeed=math.min(
                math.max(Vector3.new(vel.X,0,vel.Z).Magnitude,BASE_SPEED),
                maxSpd)
        end
        -- always hard-clamp to maxSpd every frame
        f.glideSpeed=math.min(f.glideSpeed,maxSpd)
        if UserInputService:IsKeyDown(Enum.KeyCode.W)
        or UserInputService:IsKeyDown(Enum.KeyCode.Up) then
            f.glideSpeed=math.min(f.glideSpeed+W_ACCEL*dt,maxSpd)
        end
        hrp.AssemblyLinearVelocity=Vector3.new(
            f.glideDir.X*f.glideSpeed,0,f.glideDir.Z*f.glideSpeed)
        humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
        updateTrail(hrp.Position+originOffset,true,key)
    end)
end

-- ================================================================
-- AUTOBHOP  [hold SPACE]
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

-- ================================================================
-- EDGEBUG
-- ================================================================
local eb_wasGrounded = false
local eb_lastGroundHit = false

local function edgebug_start()
    features.EdgeBug.conn=RunService.Heartbeat:Connect(function()
        if not hrp or not humanoid then return end
        local state=humanoid:GetState()
        local onGround = state==Enum.HumanoidStateType.Running
                      or state==Enum.HumanoidStateType.RunningNoPhysics

        local moveDir=humanoid.MoveDirection
        local checkOrigin = hrp.Position + (moveDir.Magnitude>0 and moveDir or hrp.CFrame.LookVector) * 1.8
        local floorAhead  = castDown(checkOrigin, 4.5)
        local floorBelow  = castDown(hrp.Position, 3.5)

        if onGround then
            eb_wasGrounded = true
            if floorBelow and not floorAhead then
                local vel=hrp.AssemblyLinearVelocity
                humanoid.Jump=true
                task.defer(function()
                    if hrp then
                        hrp.AssemblyLinearVelocity=Vector3.new(vel.X, hrp.AssemblyLinearVelocity.Y, vel.Z)
                    end
                end)
            end
        end

        if state==Enum.HumanoidStateType.Landed then
            eb_wasGrounded=false
        end
    end)
end

-- ================================================================
-- JUMPBUG  [hold Q]
-- ================================================================
local function jumpbug_start()
    features.JumpBug.conn=humanoid.StateChanged:Connect(function(_, new)
        if new==Enum.HumanoidStateType.Jumping then
            if UserInputService:IsKeyDown(Enum.KeyCode.Q) then
                task.defer(function()
                    if hrp then
                        local vel=hrp.AssemblyLinearVelocity
                        hrp.AssemblyLinearVelocity=Vector3.new(
                            vel.X,
                            vel.Y + cfg.jumpBugPower,
                            vel.Z)
                    end
                end)
            end
        end
    end)
end

-- ================================================================
-- LONGJUMP  [press E on ground]
-- ================================================================
local lj_used = false

local function longjump_start()
    features.LongJump.conn=UserInputService.InputBegan:Connect(function(input, gpe)
        if gpe then return end
        if input.KeyCode~=Enum.KeyCode.E then return end
        if not humanoid or not hrp then return end
        local state=humanoid:GetState()
        if state~=Enum.HumanoidStateType.Running
        and state~=Enum.HumanoidStateType.RunningNoPhysics then return end
        if lj_used then return end
        lj_used=true

        local look=hrp.CFrame.LookVector
        local vel=hrp.AssemblyLinearVelocity
        hrp.AssemblyLinearVelocity=Vector3.new(
            look.X * cfg.longJumpPower,
            vel.Y + 25,
            look.Z * cfg.longJumpPower)
        humanoid:ChangeState(Enum.HumanoidStateType.Jumping)

        local landConn
        landConn=humanoid.StateChanged:Connect(function(_, new)
            if new==Enum.HumanoidStateType.Landed
            or new==Enum.HumanoidStateType.Running then
                lj_used=false
                landConn:Disconnect()
            end
        end)
    end)
end

-- ================================================================
-- MINIJUMP  [press C on ground]
-- ================================================================
local mj_cd = 0

local function minijump_start()
    features.MiniJump.conn=UserInputService.InputBegan:Connect(function(input, gpe)
        if gpe then return end
        if input.KeyCode~=Enum.KeyCode.C then return end
        if not humanoid or not hrp then return end
        local now=tick()
        if now-mj_cd<0.3 then return end
        mj_cd=now
        local state=humanoid:GetState()
        if state~=Enum.HumanoidStateType.Running
        and state~=Enum.HumanoidStateType.RunningNoPhysics then return end

        local vel=hrp.AssemblyLinearVelocity
        hrp.AssemblyLinearVelocity=Vector3.new(vel.X, cfg.miniJumpPower, vel.Z)
        humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
    end)
end

-- ================================================================
-- FAKE AIMBOT  [hold right mouse button]
-- ================================================================
local camera = workspace.CurrentCamera

local function isEnemy(p)
    local myTeam = player.Team
    if myTeam == nil then return true end
    return p.Team ~= myTeam
end

local function getNearestHead()
    local closest, closestDist = nil, math.huge
    local camCF   = camera.CFrame
    local camPos  = camCF.Position
    local camLook = camCF.LookVector
    local fovRad  = math.rad(cfg.aimbotFOV)

    for _, p in ipairs(Players:GetPlayers()) do
        if p == player then continue end
        if not isEnemy(p) then continue end
        local char = p.Character
        if not char then continue end
        local head = char:FindFirstChild("Head")
        local hum  = char:FindFirstChildOfClass("Humanoid")
        if not head or not hum or hum.Health <= 0 then continue end

        local toHead = (head.Position - camPos)
        local dist   = toHead.Magnitude
        local angle  = math.acos(math.clamp(camLook:Dot(toHead.Unit), -1, 1))
        if angle > fovRad then continue end

        if dist < closestDist then
            closestDist = dist
            closest = head
        end
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

        local targetPos = head.Position
        local camPos    = camera.CFrame.Position
        local direction = (targetPos - camPos).Unit

        local targetCF = CFrame.lookAt(camPos, camPos + direction)
        camera.CFrame  = camera.CFrame:Lerp(targetCF, math.min(dt * cfg.aimbotSmooth, 1))
    end)
end

-- ================================================================
-- STOP / TOGGLE
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
    refreshIndicators()
    return f.enabled
end

-- ================================================================
-- VISUALS
-- ================================================================
local Lighting = game:GetService("Lighting")

local origFogEnd   = Lighting.FogEnd
local origFogStart = Lighting.FogStart
local origFogColor = Lighting.FogColor

local blurEffect = nil
local fogConn = nil

local function setFog(enabled)
    if enabled then
        fogConn = RunService.Heartbeat:Connect(function()
            pcall(function()
                Lighting.FogEnd   = cfg.fogEnd
                Lighting.FogStart = math.max(0, cfg.fogEnd - 60)
                Lighting.FogColor = Color3.fromRGB(190, 190, 190)
            end)
        end)
    else
        if fogConn then fogConn:Disconnect(); fogConn=nil end
        pcall(function()
            Lighting.FogEnd   = origFogEnd
            Lighting.FogStart = origFogStart
            Lighting.FogColor = origFogColor
        end)
    end
end

local blurConn = nil
local prevCamPos = nil

local function setBlur(enabled)
    if enabled then
        if not blurEffect then
            blurEffect        = Instance.new("BlurEffect")
            blurEffect.Size   = 0
            blurEffect.Parent = Lighting
        end
        prevCamPos = camera.CFrame.Position
        blurConn = RunService.RenderStepped:Connect(function()
            if not blurEffect then return end
            local curPos  = camera.CFrame.Position
            local moved   = (curPos - prevCamPos).Magnitude
            local target  = math.clamp(moved * cfg.blurSize, 0, 56)
            blurEffect.Size = blurEffect.Size + (target - blurEffect.Size) * 0.3
            prevCamPos = curPos
        end)
    else
        if blurConn then blurConn:Disconnect(); blurConn=nil end
        if blurEffect then blurEffect:Destroy(); blurEffect=nil end
    end
end

local featureBinds = {}

-- ================================================================
-- INDICATORS
-- ================================================================
local INDICATOR_TAGS = {
    PixelSurf  = "ps",
    TextureBug = "tb",
    LongJump   = "lj",
    MiniJump   = "mj",
    JumpBug    = "jb",
    AutoBhop   = "bh",
    EdgeBug    = "eb",
    FakeAimbot = "amb",
}
local indicatorLabels = {}

local function refreshIndicators()
    for key, lbl in pairs(indicatorLabels) do
        local f = features[key]
        if not f then continue end
        if not f.enabled then
            lbl.TextColor3 = Color3.fromRGB(55,55,55)
        elseif (key=="PixelSurf" or key=="TextureBug") and f.surfing then
            lbl.TextColor3 = Color3.fromRGB(79,200,90)
        else
            lbl.TextColor3 = Color3.new(1,1,1)
        end
    end
end

RunService.Heartbeat:Connect(refreshIndicators)

-- ================================================================
-- UI
-- ================================================================
local BG        = Color3.fromRGB(12,  12,  12)
local SIDEBAR   = Color3.fromRGB(8,   8,   8)
local DIVIDER   = Color3.fromRGB(35,  35,  35)
local ROW_HOVER = Color3.fromRGB(22,  22,  22)
local TEXT_SEC  = Color3.fromRGB(130, 130, 130)
local TEXT_DIM  = Color3.fromRGB(60,  60,  60)
local WHITE     = Color3.fromRGB(255, 255, 255)
local CHECK_OFF = Color3.fromRGB(30,  30,  30)

local W, H   = 480, 540
local SIDE_W = 120
local TRACK_W = 110

local screenGui=Instance.new("ScreenGui")
screenGui.Name="DwbiMenu"; screenGui.ResetOnSpawn=false
screenGui.ZIndexBehavior=Enum.ZIndexBehavior.Global
screenGui.DisplayOrder=9999
screenGui.IgnoreGuiInset=true
screenGui.Parent=player:WaitForChild("PlayerGui")

-- Watermark
local watermark=Instance.new("Frame")
watermark.Size=UDim2.new(0,52,0,22)
watermark.Position=UDim2.new(1,-6,0,6)
watermark.AnchorPoint=Vector2.new(1,0)
watermark.BackgroundColor3=Color3.fromRGB(0,0,0)
watermark.BorderSizePixel=0
watermark.ZIndex=10
watermark.Parent=screenGui
Instance.new("UICorner",watermark).CornerRadius=UDim.new(0,4)

local wmStroke=Instance.new("UIStroke",watermark)
wmStroke.Color=Color3.fromRGB(50,50,50)
wmStroke.Thickness=1

local wmLabel=Instance.new("TextLabel")
wmLabel.Size=UDim2.new(1,0,1,0)
wmLabel.BackgroundTransparency=1
wmLabel.Text="dwbi"
wmLabel.TextColor3=Color3.new(1,1,1)
wmLabel.Font=Enum.Font.Code
wmLabel.TextSize=12
wmLabel.ZIndex=11
wmLabel.Parent=watermark

-- Indicator bar
local indicatorBar=Instance.new("Frame")
indicatorBar.Size=UDim2.new(0,0,0,22)
indicatorBar.Position=UDim2.new(0.5,0,1,-10)
indicatorBar.AnchorPoint=Vector2.new(0.5,1)
indicatorBar.BackgroundTransparency=1
indicatorBar.BorderSizePixel=0
indicatorBar.AutomaticSize=Enum.AutomaticSize.X
indicatorBar.ZIndex=10
indicatorBar.Parent=screenGui

local ibLayout=Instance.new("UIListLayout",indicatorBar)
ibLayout.FillDirection=Enum.FillDirection.Horizontal
ibLayout.Padding=UDim.new(0,4)
ibLayout.SortOrder=Enum.SortOrder.LayoutOrder

local ibPad=Instance.new("UIPadding",indicatorBar)
ibPad.PaddingLeft=UDim.new(0,6); ibPad.PaddingRight=UDim.new(0,6)
ibPad.PaddingTop=UDim.new(0,2); ibPad.PaddingBottom=UDim.new(0,2)

local INDICATOR_ORDER = {"ps","tb","lj","mj","jb","bh","eb","amb"}
local INDICATOR_KEY_MAP = {
    ps="PixelSurf", tb="TextureBug", lj="LongJump",
    mj="MiniJump",  jb="JumpBug",   bh="AutoBhop",
    eb="EdgeBug",   amb="FakeAimbot"
}

for i, tag in ipairs(INDICATOR_ORDER) do
    local key = INDICATOR_KEY_MAP[tag]
    local lbl=Instance.new("TextLabel")
    lbl.Size=UDim2.new(0,0,1,0)
    lbl.AutomaticSize=Enum.AutomaticSize.X
    lbl.BackgroundTransparency=1
    lbl.Text=tag
    lbl.TextColor3=Color3.fromRGB(60,60,60)
    lbl.Font=Enum.Font.GothamBold
    lbl.TextSize=13
    lbl.LayoutOrder=i
    lbl.ZIndex=11
    lbl.Parent=indicatorBar
    indicatorLabels[key]=lbl
end

local win=Instance.new("Frame")
win.Name="Window"; win.Size=UDim2.new(0,W,0,H)
win.Position=UDim2.new(0.5,-W/2,0.5,-H/2)
win.BackgroundColor3=BG; win.BorderSizePixel=0
win.ZIndex=1; win.Visible=false; win.Parent=screenGui
Instance.new("UICorner",win).CornerRadius=UDim.new(0,5)
local winStroke=Instance.new("UIStroke",win)
winStroke.Color=DIVIDER; winStroke.Thickness=1

local titleBar=Instance.new("Frame")
titleBar.Size=UDim2.new(1,0,0,28); titleBar.BackgroundColor3=SIDEBAR
titleBar.BorderSizePixel=0; titleBar.ZIndex=2; titleBar.Parent=win
Instance.new("UICorner",titleBar).CornerRadius=UDim.new(0,5)
local tbPatch=Instance.new("Frame")
tbPatch.Size=UDim2.new(1,0,0,6); tbPatch.Position=UDim2.new(0,0,1,-6)
tbPatch.BackgroundColor3=SIDEBAR; tbPatch.BorderSizePixel=0; tbPatch.ZIndex=2; tbPatch.Parent=titleBar
local titleBorder=Instance.new("Frame")
titleBorder.Size=UDim2.new(1,0,0,1); titleBorder.Position=UDim2.new(0,0,1,0)
titleBorder.BackgroundColor3=DIVIDER; titleBorder.BorderSizePixel=0; titleBorder.ZIndex=3; titleBorder.Parent=titleBar

local titleLbl=Instance.new("TextLabel")
titleLbl.Size=UDim2.new(1,-40,1,0); titleLbl.Position=UDim2.new(0,12,0,0)
titleLbl.BackgroundTransparency=1; titleLbl.Text="dwbi"
titleLbl.TextColor3=WHITE; titleLbl.Font=Enum.Font.Code; titleLbl.TextSize=12
titleLbl.TextXAlignment=Enum.TextXAlignment.Left; titleLbl.ZIndex=3; titleLbl.Parent=titleBar

local subLbl=Instance.new("TextLabel")
subLbl.Size=UDim2.new(0,80,1,0); subLbl.Position=UDim2.new(0,38,0,0)
subLbl.BackgroundTransparency=1; subLbl.Text="movement"
subLbl.TextColor3=TEXT_DIM; subLbl.Font=Enum.Font.Code; subLbl.TextSize=11
subLbl.TextXAlignment=Enum.TextXAlignment.Left; subLbl.ZIndex=3; subLbl.Parent=titleBar

local closeBtn=Instance.new("TextButton")
closeBtn.Size=UDim2.new(0,28,1,0); closeBtn.Position=UDim2.new(1,-28,0,0)
closeBtn.BackgroundTransparency=1; closeBtn.Text="×"
closeBtn.TextColor3=TEXT_DIM; closeBtn.Font=Enum.Font.Code; closeBtn.TextSize=16
closeBtn.ZIndex=3; closeBtn.Parent=titleBar
closeBtn.MouseEnter:Connect(function() closeBtn.TextColor3=WHITE end)
closeBtn.MouseLeave:Connect(function() closeBtn.TextColor3=TEXT_DIM end)
closeBtn.MouseButton1Click:Connect(function() win.Visible=false end)

local dragging,dragStart,dragOrigin=false,nil,nil
titleBar.InputBegan:Connect(function(i)
    if i.UserInputType==Enum.UserInputType.MouseButton1 then
        dragging=true; dragStart=i.Position; dragOrigin=win.Position
    end
end)
titleBar.InputEnded:Connect(function(i)
    if i.UserInputType==Enum.UserInputType.MouseButton1 then dragging=false end
end)
UserInputService.InputChanged:Connect(function(i)
    if dragging and i.UserInputType==Enum.UserInputType.MouseMovement then
        local d=i.Position-dragStart
        win.Position=UDim2.new(dragOrigin.X.Scale,dragOrigin.X.Offset+d.X,
                               dragOrigin.Y.Scale,dragOrigin.Y.Offset+d.Y)
    end
end)

local body=Instance.new("Frame")
body.Size=UDim2.new(1,0,1,-28); body.Position=UDim2.new(0,0,0,28)
body.BackgroundTransparency=1; body.ZIndex=2; body.Parent=win

local sidebar=Instance.new("Frame")
sidebar.Size=UDim2.new(0,SIDE_W,1,0); sidebar.BackgroundColor3=SIDEBAR
sidebar.BorderSizePixel=0; sidebar.ZIndex=2; sidebar.Parent=body
Instance.new("UICorner",sidebar).CornerRadius=UDim.new(0,5)
local sbPatchTop=Instance.new("Frame")
sbPatchTop.Size=UDim2.new(1,0,0,6); sbPatchTop.BackgroundColor3=SIDEBAR
sbPatchTop.BorderSizePixel=0; sbPatchTop.ZIndex=2; sbPatchTop.Parent=sidebar
local sbPatchRight=Instance.new("Frame")
sbPatchRight.Size=UDim2.new(0,6,1,0); sbPatchRight.Position=UDim2.new(1,-6,0,0)
sbPatchRight.BackgroundColor3=SIDEBAR; sbPatchRight.BorderSizePixel=0
sbPatchRight.ZIndex=2; sbPatchRight.Parent=sidebar
local sbBorder=Instance.new("Frame")
sbBorder.Size=UDim2.new(0,1,1,0); sbBorder.Position=UDim2.new(1,-1,0,0)
sbBorder.BackgroundColor3=DIVIDER; sbBorder.BorderSizePixel=0
sbBorder.ZIndex=3; sbBorder.Parent=sidebar

Instance.new("UIListLayout",sidebar).Padding=UDim.new(0,0)
local sbPad=Instance.new("UIPadding"); sbPad.PaddingTop=UDim.new(0,10); sbPad.Parent=sidebar

local activeTab = "movement"

local function makeNavTab(labelTxt, isActive)
    local btn=Instance.new("TextButton")
    btn.Size=UDim2.new(1,-1,0,26); btn.BackgroundColor3=isActive and Color3.fromRGB(22,22,22) or SIDEBAR
    btn.BorderSizePixel=0; btn.Text=""; btn.AutoButtonColor=false
    btn.ZIndex=3; btn.Parent=sidebar

    local accent=Instance.new("Frame")
    accent.Size=UDim2.new(0,2,0.6,0); accent.Position=UDim2.new(0,0,0.2,0)
    accent.BackgroundColor3=WHITE; accent.BorderSizePixel=0; accent.ZIndex=4
    accent.Visible=isActive; accent.Parent=btn

    local lbl=Instance.new("TextLabel")
    lbl.Size=UDim2.new(1,-12,1,0); lbl.Position=UDim2.new(0,10,0,0)
    lbl.BackgroundTransparency=1; lbl.Text=labelTxt
    lbl.TextColor3=isActive and WHITE or TEXT_SEC
    lbl.Font=Enum.Font.Code; lbl.TextSize=11
    lbl.TextXAlignment=Enum.TextXAlignment.Left; lbl.ZIndex=4; lbl.Parent=btn

    return btn, accent, lbl
end

local movBtn, movAccent, movLbl = makeNavTab("movement", true)
local visBtn, visAccent, visLbl = makeNavTab("visuals",  false)

local function makeContentPanel(visible)
    local panel=Instance.new("ScrollingFrame")
    panel.Size=UDim2.new(1,-SIDE_W,1,0); panel.Position=UDim2.new(0,SIDE_W,0,0)
    panel.BackgroundTransparency=1; panel.BorderSizePixel=0
    panel.ScrollBarThickness=3; panel.ScrollBarImageColor3=DIVIDER
    panel.CanvasSize=UDim2.new(0,0,0,0); panel.AutomaticCanvasSize=Enum.AutomaticSize.Y
    panel.ZIndex=2; panel.Visible=visible; panel.Parent=body
    local list=Instance.new("UIListLayout")
    list.Padding=UDim.new(0,0); list.SortOrder=Enum.SortOrder.LayoutOrder; list.Parent=panel
    local pad=Instance.new("UIPadding")
    pad.PaddingTop=UDim.new(0,6); pad.PaddingBottom=UDim.new(0,6)
    pad.PaddingLeft=UDim.new(0,14); pad.PaddingRight=UDim.new(0,14); pad.Parent=panel
    return panel
end

local content     = makeContentPanel(true)
local visContent  = makeContentPanel(false)

local function switchTab(tab)
    activeTab       = tab
    content.Visible    = tab=="movement"
    visContent.Visible = tab=="visuals"

    movBtn.BackgroundColor3  = tab=="movement" and Color3.fromRGB(22,22,22) or SIDEBAR
    movAccent.Visible        = tab=="movement"
    movLbl.TextColor3        = tab=="movement" and WHITE or TEXT_SEC

    visBtn.BackgroundColor3  = tab=="visuals" and Color3.fromRGB(22,22,22) or SIDEBAR
    visAccent.Visible        = tab=="visuals"
    visLbl.TextColor3        = tab=="visuals" and WHITE or TEXT_SEC
end

movBtn.MouseButton1Click:Connect(function() switchTab("movement") end)
visBtn.MouseButton1Click:Connect(function() switchTab("visuals") end)

local function makeRow(feat)
    local hasSlider = feat.minVal ~= nil
    local rowH = hasSlider and 50 or 32

    local wrap=Instance.new("Frame")
    wrap.Size=UDim2.new(1,0,0,rowH); wrap.BackgroundColor3=BG
    wrap.BorderSizePixel=0; wrap.ZIndex=3; wrap.Parent=content

    local rowDiv=Instance.new("Frame")
    rowDiv.Size=UDim2.new(1,0,0,1); rowDiv.Position=UDim2.new(0,0,1,-1)
    rowDiv.BackgroundColor3=DIVIDER; rowDiv.BorderSizePixel=0; rowDiv.ZIndex=4; rowDiv.Parent=wrap

    local cb=Instance.new("Frame")
    cb.Size=UDim2.new(0,10,0,10); cb.Position=UDim2.new(0,0,0,10)
    cb.BackgroundColor3=CHECK_OFF; cb.BorderSizePixel=0; cb.ZIndex=4; cb.Parent=wrap
    Instance.new("UICorner",cb).CornerRadius=UDim.new(0,2)
    local cbStroke=Instance.new("UIStroke",cb)
    cbStroke.Color=DIVIDER; cbStroke.Thickness=1

    local lbl=Instance.new("TextLabel")
    lbl.Size=UDim2.new(1,-80,0,20); lbl.Position=UDim2.new(0,16,0,4)
    lbl.BackgroundTransparency=1; lbl.Text=feat.label
    lbl.TextColor3=TEXT_SEC; lbl.Font=Enum.Font.Code; lbl.TextSize=12
    lbl.TextXAlignment=Enum.TextXAlignment.Left; lbl.ZIndex=4; lbl.Parent=wrap

    if feat.hint then
        local hintLbl=Instance.new("TextLabel")
        hintLbl.Size=UDim2.new(0,60,0,20); hintLbl.Position=UDim2.new(1,-62,0,4)
        hintLbl.BackgroundTransparency=1; hintLbl.Text=feat.hint
        hintLbl.TextColor3=TEXT_DIM; hintLbl.Font=Enum.Font.Code; hintLbl.TextSize=9
        hintLbl.TextXAlignment=Enum.TextXAlignment.Right; hintLbl.ZIndex=4; hintLbl.Parent=wrap
    end

    local clickZone=Instance.new("TextButton")
    clickZone.Size=UDim2.new(1,0,0,hasSlider and 26 or rowH)
    clickZone.BackgroundTransparency=1; clickZone.Text=""
    clickZone.ZIndex=5; clickZone.Parent=wrap

    if hasSlider then
        local sliderRow=Instance.new("Frame")
        sliderRow.Size=UDim2.new(1,-16,0,14); sliderRow.Position=UDim2.new(0,16,0,28)
        sliderRow.BackgroundTransparency=1; sliderRow.ZIndex=4; sliderRow.Parent=wrap

        local spLbl=Instance.new("TextLabel")
        spLbl.Size=UDim2.new(0,30,1,0); spLbl.BackgroundTransparency=1
        spLbl.Text=feat.sliderLabel or "power"
        spLbl.TextColor3=TEXT_DIM; spLbl.Font=Enum.Font.Code; spLbl.TextSize=9
        spLbl.TextXAlignment=Enum.TextXAlignment.Left; spLbl.ZIndex=5; spLbl.Parent=sliderRow

        local track=Instance.new("Frame")
        track.Size=UDim2.new(0,TRACK_W,0,2); track.Position=UDim2.new(0,32,0.5,-1)
        track.BackgroundColor3=DIVIDER; track.BorderSizePixel=0; track.ZIndex=5; track.Parent=sliderRow
        Instance.new("UICorner",track).CornerRadius=UDim.new(1,0)

        local initFrac=(feat.initVal-feat.minVal)/(feat.maxVal-feat.minVal)

        local fill=Instance.new("Frame")
        fill.Size=UDim2.new(initFrac,0,1,0); fill.BackgroundColor3=WHITE
        fill.BorderSizePixel=0; fill.ZIndex=6; fill.Parent=track
        Instance.new("UICorner",fill).CornerRadius=UDim.new(1,0)

        local knob=Instance.new("Frame")
        knob.Size=UDim2.new(0,7,0,7); knob.AnchorPoint=Vector2.new(0.5,0.5)
        knob.Position=UDim2.new(initFrac,0,0.5,0); knob.BackgroundColor3=WHITE
        knob.BorderSizePixel=0; knob.ZIndex=7; knob.Parent=track
        Instance.new("UICorner",knob).CornerRadius=UDim.new(1,0)

        local valLbl=Instance.new("TextLabel")
        valLbl.Size=UDim2.new(0,30,1,0); valLbl.Position=UDim2.new(0,TRACK_W+36,0,0)
        valLbl.BackgroundTransparency=1; valLbl.Text=tostring(feat.initVal)
        valLbl.TextColor3=TEXT_SEC; valLbl.Font=Enum.Font.Code; valLbl.TextSize=9
        valLbl.TextXAlignment=Enum.TextXAlignment.Left; valLbl.ZIndex=5; valLbl.Parent=sliderRow

        local sDragging=false
        local function applySlider(absX)
            local t=math.clamp((absX-track.AbsolutePosition.X)/TRACK_W,0,1)
            local val=math.floor(feat.minVal+t*(feat.maxVal-feat.minVal)+0.5)
            local f=(val-feat.minVal)/(feat.maxVal-feat.minVal)
            fill.Size=UDim2.new(f,0,1,0); knob.Position=UDim2.new(f,0,0.5,0)
            valLbl.Text=tostring(val); feat.onChange(val)
        end
        track.InputBegan:Connect(function(i)
            if i.UserInputType==Enum.UserInputType.MouseButton1 then
                sDragging=true; applySlider(i.Position.X)
            end
        end)
        UserInputService.InputEnded:Connect(function(i)
            if i.UserInputType==Enum.UserInputType.MouseButton1 then sDragging=false end
        end)
        UserInputService.InputChanged:Connect(function(i)
            if sDragging and i.UserInputType==Enum.UserInputType.MouseMovement then
                applySlider(i.Position.X)
            end
        end)
    end

    local on=false
    local function setOn(v)
        on=v
        if v then
            cb.BackgroundColor3=WHITE; cbStroke.Color=WHITE; lbl.TextColor3=WHITE
        else
            cb.BackgroundColor3=CHECK_OFF; cbStroke.Color=DIVIDER; lbl.TextColor3=TEXT_SEC
        end
        toggleFeature(feat.key)
    end
    clickZone.MouseButton1Click:Connect(function() setOn(not on) end)
    clickZone.MouseEnter:Connect(function() wrap.BackgroundColor3=ROW_HOVER end)
    clickZone.MouseLeave:Connect(function() wrap.BackgroundColor3=BG end)

    local ctxOpen = false
    local ctxFrame = nil

    local function closeCtx()
        if ctxFrame then ctxFrame:Destroy(); ctxFrame=nil end
        ctxOpen=false
    end

    local function openCtx()
        if ctxOpen then closeCtx(); return end
        ctxOpen=true

        local bind = featureBinds[feat.key] or {}

        ctxFrame=Instance.new("Frame")
        ctxFrame.Size=UDim2.new(0,160,0,0)
        ctxFrame.AutomaticSize=Enum.AutomaticSize.Y
        ctxFrame.Position=UDim2.new(1,4,0,0)
        ctxFrame.BackgroundColor3=Color3.fromRGB(18,18,18)
        ctxFrame.BorderSizePixel=0
        ctxFrame.ZIndex=20
        ctxFrame.Parent=wrap
        Instance.new("UICorner",ctxFrame).CornerRadius=UDim.new(0,4)
        local cs=Instance.new("UIStroke",ctxFrame); cs.Color=DIVIDER; cs.Thickness=1

        local ctxList=Instance.new("UIListLayout",ctxFrame)
        ctxList.Padding=UDim.new(0,0); ctxList.SortOrder=Enum.SortOrder.LayoutOrder

        local function ctxRow(txt, order, onClick)
            local r=Instance.new("TextButton")
            r.Size=UDim2.new(1,0,0,24); r.BackgroundColor3=Color3.fromRGB(18,18,18)
            r.BorderSizePixel=0; r.Text=txt; r.TextColor3=TEXT_SEC
            r.Font=Enum.Font.GothamBold; r.TextSize=10
            r.TextXAlignment=Enum.TextXAlignment.Left
            r.LayoutOrder=order; r.ZIndex=21; r.Parent=ctxFrame
            local rPad=Instance.new("UIPadding",r)
            rPad.PaddingLeft=UDim.new(0,8)
            r.MouseEnter:Connect(function() r.BackgroundColor3=Color3.fromRGB(30,30,30); r.TextColor3=WHITE end)
            r.MouseLeave:Connect(function() r.BackgroundColor3=Color3.fromRGB(18,18,18); r.TextColor3=TEXT_SEC end)
            r.MouseButton1Click:Connect(function() onClick(); closeCtx() end)
            return r
        end

        local bindTxt = bind.keyCode
            and "bind: "..tostring(bind.keyCode):gsub("Enum.KeyCode.","")
            or  "set bind key"
        ctxRow(bindTxt, 1, function()
            local pickFrame=Instance.new("Frame")
            pickFrame.Size=UDim2.new(0,180,0,36)
            pickFrame.Position=UDim2.new(0.5,-90,0.5,-18)
            pickFrame.BackgroundColor3=Color3.fromRGB(10,10,10)
            pickFrame.BorderSizePixel=0; pickFrame.ZIndex=30
            pickFrame.Parent=screenGui
            Instance.new("UICorner",pickFrame).CornerRadius=UDim.new(0,5)
            local ps2=Instance.new("UIStroke",pickFrame); ps2.Color=DIVIDER; ps2.Thickness=1
            local pl=Instance.new("TextLabel",pickFrame)
            pl.Size=UDim2.new(1,0,1,0); pl.BackgroundTransparency=1
            pl.Text="press a key..."; pl.TextColor3=TEXT_SEC
            pl.Font=Enum.Font.GothamBold; pl.TextSize=11; pl.ZIndex=31

            local pconn
            pconn=UserInputService.InputBegan:Connect(function(inp,gpe)
                if gpe then return end
                if inp.UserInputType==Enum.UserInputType.Keyboard then
                    if not featureBinds[feat.key] then featureBinds[feat.key]={} end
                    featureBinds[feat.key].keyCode=inp.KeyCode
                    pickFrame:Destroy()
                    if pconn then pconn:Disconnect() end
                end
            end)
        end)

        local holdTxt = (bind.holdMode) and "mode: hold ✓" or "mode: hold"
        ctxRow(holdTxt, 2, function()
            if not featureBinds[feat.key] then featureBinds[feat.key]={} end
            local b=featureBinds[feat.key]
            b.holdMode = not b.holdMode
            if b.holdMode then
                if b.keyCode then
                    if b.holdConn then b.holdConn:Disconnect() end
                    b.holdConn=UserInputService.InputBegan:Connect(function(inp,gpe)
                        if not gpe and inp.KeyCode==b.keyCode then
                            if not on then setOn(true) end
                        end
                    end)
                    if b.holdEndConn then b.holdEndConn:Disconnect() end
                    b.holdEndConn=UserInputService.InputEnded:Connect(function(inp)
                        if inp.KeyCode==b.keyCode then
                            if on then setOn(false) end
                        end
                    end)
                end
            else
                if b.holdConn then b.holdConn:Disconnect(); b.holdConn=nil end
                if b.holdEndConn then b.holdEndConn:Disconnect(); b.holdEndConn=nil end
            end
        end)

        ctxRow("clear bind", 3, function()
            local b=featureBinds[feat.key]
            if b then
                if b.holdConn then b.holdConn:Disconnect() end
                if b.holdEndConn then b.holdEndConn:Disconnect() end
            end
            featureBinds[feat.key]=nil
        end)
    end

    RunService.Heartbeat:Connect(function()
        local b=featureBinds[feat.key]
        if not b or not b.keyCode or b.holdMode then return end
    end)

    UserInputService.InputBegan:Connect(function(inp,gpe)
        if gpe then return end
        local b=featureBinds[feat.key]
        if b and b.keyCode and not b.holdMode and inp.KeyCode==b.keyCode then
            setOn(not on)
        end
    end)

    clickZone.MouseButton2Click:Connect(openCtx)

    UserInputService.InputBegan:Connect(function(inp)
        if ctxOpen and inp.UserInputType==Enum.UserInputType.MouseButton1 then
            task.defer(closeCtx)
        end
    end)
end

local FEATURES = {
    {
        key="PixelSurf", label="pixel surf", hint="auto",
        sliderLabel="speed", minVal=20, maxVal=200, initVal=cfg.pixelMaxSpeed,
        onChange=function(v) cfg.pixelMaxSpeed=v end,
    },
    {
        key="TextureBug", label="texture bug", hint="auto",
        sliderLabel="speed", minVal=20, maxVal=200, initVal=cfg.textureMaxSpeed,
        onChange=function(v) cfg.textureMaxSpeed=v end,
    },
    {
        key="AutoBhop", label="bunny hop", hint="[space]",
        sliderLabel="boost", minVal=1, maxVal=100, initVal=math.floor(cfg.bhopBoost*10+0.5),
        onChange=function(v) cfg.bhopBoost=v/10 end,
    },
    {
        key="EdgeBug", label="edge bug", hint="auto",
    },
    {
        key="JumpBug", label="jump bug", hint="[q]",
        sliderLabel="power", minVal=10, maxVal=200, initVal=cfg.jumpBugPower,
        onChange=function(v) cfg.jumpBugPower=v end,
    },
    {
        key="LongJump", label="long jump", hint="[e]",
        sliderLabel="power", minVal=20, maxVal=200, initVal=cfg.longJumpPower,
        onChange=function(v) cfg.longJumpPower=v end,
    },
    {
        key="MiniJump", label="mini jump", hint="[c]",
        sliderLabel="power", minVal=5, maxVal=80, initVal=cfg.miniJumpPower,
        onChange=function(v) cfg.miniJumpPower=v end,
    },
}

for _, feat in ipairs(FEATURES) do makeRow(feat) end

-- Fake aimbot special row
do
    local rowH = 110
    local wrap=Instance.new("Frame")
    wrap.Size=UDim2.new(1,0,0,rowH); wrap.BackgroundColor3=BG
    wrap.BorderSizePixel=0; wrap.ZIndex=3; wrap.Parent=content

    local rowDiv=Instance.new("Frame")
    rowDiv.Size=UDim2.new(1,0,0,1); rowDiv.Position=UDim2.new(0,0,1,-1)
    rowDiv.BackgroundColor3=DIVIDER; rowDiv.BorderSizePixel=0; rowDiv.ZIndex=4; rowDiv.Parent=wrap

    local cb=Instance.new("Frame")
    cb.Size=UDim2.new(0,10,0,10); cb.Position=UDim2.new(0,0,0,10)
    cb.BackgroundColor3=CHECK_OFF; cb.BorderSizePixel=0; cb.ZIndex=4; cb.Parent=wrap
    Instance.new("UICorner",cb).CornerRadius=UDim.new(0,2)
    local cbStroke=Instance.new("UIStroke",cb); cbStroke.Color=DIVIDER; cbStroke.Thickness=1

    local lbl=Instance.new("TextLabel")
    lbl.Size=UDim2.new(1,-80,0,20); lbl.Position=UDim2.new(0,16,0,4)
    lbl.BackgroundTransparency=1; lbl.Text="fake aimbot"
    lbl.TextColor3=TEXT_SEC; lbl.Font=Enum.Font.Code; lbl.TextSize=12
    lbl.TextXAlignment=Enum.TextXAlignment.Left; lbl.ZIndex=4; lbl.Parent=wrap

    local clickZone=Instance.new("TextButton")
    clickZone.Size=UDim2.new(1,0,0,26); clickZone.BackgroundTransparency=1
    clickZone.Text=""; clickZone.ZIndex=5; clickZone.Parent=wrap

    local function miniSlider(yOff, labelTxt, minV, maxV, initV, onCh)
        local row=Instance.new("Frame")
        row.Size=UDim2.new(1,-16,0,14); row.Position=UDim2.new(0,16,0,yOff)
        row.BackgroundTransparency=1; row.ZIndex=4; row.Parent=wrap

        local sl=Instance.new("TextLabel")
        sl.Size=UDim2.new(0,52,1,0); sl.BackgroundTransparency=1; sl.Text=labelTxt
        sl.TextColor3=TEXT_DIM; sl.Font=Enum.Font.Code; sl.TextSize=9
        sl.TextXAlignment=Enum.TextXAlignment.Left; sl.ZIndex=5; sl.Parent=row

        local TW=90
        local track=Instance.new("Frame")
        track.Size=UDim2.new(0,TW,0,2); track.Position=UDim2.new(0,54,0.5,-1)
        track.BackgroundColor3=DIVIDER; track.BorderSizePixel=0; track.ZIndex=5; track.Parent=row
        Instance.new("UICorner",track).CornerRadius=UDim.new(1,0)

        local frac=(initV-minV)/(maxV-minV)
        local fill=Instance.new("Frame")
        fill.Size=UDim2.new(frac,0,1,0); fill.BackgroundColor3=WHITE
        fill.BorderSizePixel=0; fill.ZIndex=6; fill.Parent=track
        Instance.new("UICorner",fill).CornerRadius=UDim.new(1,0)

        local knob=Instance.new("Frame")
        knob.Size=UDim2.new(0,7,0,7); knob.AnchorPoint=Vector2.new(0.5,0.5)
        knob.Position=UDim2.new(frac,0,0.5,0); knob.BackgroundColor3=WHITE
        knob.BorderSizePixel=0; knob.ZIndex=7; knob.Parent=track
        Instance.new("UICorner",knob).CornerRadius=UDim.new(1,0)

        local valL=Instance.new("TextLabel")
        valL.Size=UDim2.new(0,28,1,0); valL.Position=UDim2.new(0,TW+58,0,0)
        valL.BackgroundTransparency=1; valL.Text=tostring(initV)
        valL.TextColor3=TEXT_SEC; valL.Font=Enum.Font.Code; valL.TextSize=9
        valL.TextXAlignment=Enum.TextXAlignment.Left; valL.ZIndex=5; valL.Parent=row

        local sd=false
        local function apply(ax)
            local t=math.clamp((ax-track.AbsolutePosition.X)/TW,0,1)
            local v=math.floor(minV+t*(maxV-minV)+0.5)
            local f2=(v-minV)/(maxV-minV)
            fill.Size=UDim2.new(f2,0,1,0); knob.Position=UDim2.new(f2,0,0.5,0)
            valL.Text=tostring(v); onCh(v)
        end
        track.InputBegan:Connect(function(i)
            if i.UserInputType==Enum.UserInputType.MouseButton1 then sd=true; apply(i.Position.X) end
        end)
        UserInputService.InputEnded:Connect(function(i)
            if i.UserInputType==Enum.UserInputType.MouseButton1 then sd=false end
        end)
        UserInputService.InputChanged:Connect(function(i)
            if sd and i.UserInputType==Enum.UserInputType.MouseMovement then apply(i.Position.X) end
        end)
    end

    miniSlider(28,  "fov",    10, 120, cfg.aimbotFOV,    function(v) cfg.aimbotFOV=v end)
    miniSlider(46,  "smooth",  1,  20, cfg.aimbotSmooth, function(v) cfg.aimbotSmooth=v end)

    local pickRow=Instance.new("Frame")
    pickRow.Size=UDim2.new(1,-16,0,18); pickRow.Position=UDim2.new(0,16,0,64)
    pickRow.BackgroundTransparency=1; pickRow.ZIndex=4; pickRow.Parent=wrap

    local pickLbl=Instance.new("TextLabel")
    pickLbl.Size=UDim2.new(0,52,1,0); pickLbl.BackgroundTransparency=1; pickLbl.Text="aim key"
    pickLbl.TextColor3=TEXT_DIM; pickLbl.Font=Enum.Font.Code; pickLbl.TextSize=9
    pickLbl.TextXAlignment=Enum.TextXAlignment.Left; pickLbl.ZIndex=5; pickLbl.Parent=pickRow

    local pickBtn=Instance.new("TextButton")
    pickBtn.Size=UDim2.new(0,90,1,0); pickBtn.Position=UDim2.new(0,54,0,0)
    pickBtn.BackgroundColor3=Color3.fromRGB(28,28,28); pickBtn.BorderSizePixel=0
    pickBtn.Text="rmb"; pickBtn.TextColor3=WHITE
    pickBtn.Font=Enum.Font.Code; pickBtn.TextSize=9; pickBtn.ZIndex=5; pickBtn.Parent=pickRow
    Instance.new("UICorner",pickBtn).CornerRadius=UDim.new(0,3)

    local listening=false
    local pickConn=nil

    pickBtn.MouseButton1Click:Connect(function()
        if listening then return end
        listening=true
        pickBtn.Text="[ press key ]"
        pickBtn.TextColor3=TEXT_DIM

        pickConn=UserInputService.InputBegan:Connect(function(input, gpe)
            if gpe then return end
            local name
            if input.UserInputType==Enum.UserInputType.MouseButton1 then
                cfg.aimbotButton=Enum.UserInputType.MouseButton1; name="lmb"
            elseif input.UserInputType==Enum.UserInputType.MouseButton2 then
                cfg.aimbotButton=Enum.UserInputType.MouseButton2; name="rmb"
            elseif input.UserInputType==Enum.UserInputType.MouseButton3 then
                cfg.aimbotButton=Enum.UserInputType.MouseButton3; name="mmb"
            elseif input.UserInputType==Enum.UserInputType.Keyboard then
                cfg.aimbotButton=input.KeyCode
                name=tostring(input.KeyCode):gsub("Enum.KeyCode.",""):lower()
            else
                return
            end
            pickBtn.Text=name
            pickBtn.TextColor3=WHITE
            listening=false
            if pickConn then pickConn:Disconnect(); pickConn=nil end
        end)
    end)

    local on=false
    local function setOn(v)
        on=v
        if v then
            cb.BackgroundColor3=WHITE; cbStroke.Color=WHITE; lbl.TextColor3=WHITE
        else
            cb.BackgroundColor3=CHECK_OFF; cbStroke.Color=DIVIDER; lbl.TextColor3=TEXT_SEC
        end
        toggleFeature("FakeAimbot")
    end
    clickZone.MouseButton1Click:Connect(function() setOn(not on) end)
    clickZone.MouseEnter:Connect(function() wrap.BackgroundColor3=ROW_HOVER end)
    clickZone.MouseLeave:Connect(function() wrap.BackgroundColor3=BG end)
end

-- Visuals rows
do
    local function makeVisRow(labelTxt, sliderLbl, minV, maxV, initV, onToggle, onSlide)
        local rowH = 50
        local wrap=Instance.new("Frame")
        wrap.Size=UDim2.new(1,0,0,rowH); wrap.BackgroundColor3=BG
        wrap.BorderSizePixel=0; wrap.ZIndex=3; wrap.Parent=visContent

        local rowDiv=Instance.new("Frame")
        rowDiv.Size=UDim2.new(1,0,0,1); rowDiv.Position=UDim2.new(0,0,1,-1)
        rowDiv.BackgroundColor3=DIVIDER; rowDiv.BorderSizePixel=0; rowDiv.ZIndex=4; rowDiv.Parent=wrap

        local cb=Instance.new("Frame")
        cb.Size=UDim2.new(0,10,0,10); cb.Position=UDim2.new(0,0,0,10)
        cb.BackgroundColor3=CHECK_OFF; cb.BorderSizePixel=0; cb.ZIndex=4; cb.Parent=wrap
        Instance.new("UICorner",cb).CornerRadius=UDim.new(0,2)
        local cbS=Instance.new("UIStroke",cb); cbS.Color=DIVIDER; cbS.Thickness=1

        local lbl=Instance.new("TextLabel")
        lbl.Size=UDim2.new(1,-80,0,20); lbl.Position=UDim2.new(0,16,0,4)
        lbl.BackgroundTransparency=1; lbl.Text=labelTxt
        lbl.TextColor3=TEXT_SEC; lbl.Font=Enum.Font.Code; lbl.TextSize=12
        lbl.TextXAlignment=Enum.TextXAlignment.Left; lbl.ZIndex=4; lbl.Parent=wrap

        local click=Instance.new("TextButton")
        click.Size=UDim2.new(1,0,0,26); click.BackgroundTransparency=1
        click.Text=""; click.ZIndex=5; click.Parent=wrap

        local sRow=Instance.new("Frame")
        sRow.Size=UDim2.new(1,-16,0,14); sRow.Position=UDim2.new(0,16,0,28)
        sRow.BackgroundTransparency=1; sRow.ZIndex=4; sRow.Parent=wrap

        local sLbl=Instance.new("TextLabel")
        sLbl.Size=UDim2.new(0,30,1,0); sLbl.BackgroundTransparency=1; sLbl.Text=sliderLbl
        sLbl.TextColor3=TEXT_DIM; sLbl.Font=Enum.Font.Code; sLbl.TextSize=9
        sLbl.TextXAlignment=Enum.TextXAlignment.Left; sLbl.ZIndex=5; sLbl.Parent=sRow

        local TW=TRACK_W
        local track=Instance.new("Frame")
        track.Size=UDim2.new(0,TW,0,2); track.Position=UDim2.new(0,32,0.5,-1)
        track.BackgroundColor3=DIVIDER; track.BorderSizePixel=0; track.ZIndex=5; track.Parent=sRow
        Instance.new("UICorner",track).CornerRadius=UDim.new(1,0)

        local frac=(initV-minV)/(maxV-minV)
        local fill=Instance.new("Frame")
        fill.Size=UDim2.new(frac,0,1,0); fill.BackgroundColor3=WHITE
        fill.BorderSizePixel=0; fill.ZIndex=6; fill.Parent=track
        Instance.new("UICorner",fill).CornerRadius=UDim.new(1,0)

        local knob=Instance.new("Frame")
        knob.Size=UDim2.new(0,7,0,7); knob.AnchorPoint=Vector2.new(0.5,0.5)
        knob.Position=UDim2.new(frac,0,0.5,0); knob.BackgroundColor3=WHITE
        knob.BorderSizePixel=0; knob.ZIndex=7; knob.Parent=track
        Instance.new("UICorner",knob).CornerRadius=UDim.new(1,0)

        local valL=Instance.new("TextLabel")
        valL.Size=UDim2.new(0,30,1,0); valL.Position=UDim2.new(0,TW+36,0,0)
        valL.BackgroundTransparency=1; valL.Text=tostring(initV)
        valL.TextColor3=TEXT_SEC; valL.Font=Enum.Font.Code; valL.TextSize=9
        valL.TextXAlignment=Enum.TextXAlignment.Left; valL.ZIndex=5; valL.Parent=sRow

        local sd=false
        local function applyS(ax)
            local t=math.clamp((ax-track.AbsolutePosition.X)/TW,0,1)
            local v=math.floor(minV+t*(maxV-minV)+0.5)
            local f2=(v-minV)/(maxV-minV)
            fill.Size=UDim2.new(f2,0,1,0); knob.Position=UDim2.new(f2,0,0.5,0)
            valL.Text=tostring(v); onSlide(v)
        end
        track.InputBegan:Connect(function(i)
            if i.UserInputType==Enum.UserInputType.MouseButton1 then sd=true; applyS(i.Position.X) end
        end)
        UserInputService.InputEnded:Connect(function(i)
            if i.UserInputType==Enum.UserInputType.MouseButton1 then sd=false end
        end)
        UserInputService.InputChanged:Connect(function(i)
            if sd and i.UserInputType==Enum.UserInputType.MouseMovement then applyS(i.Position.X) end
        end)

        local on=false
        local function setOn(v)
            on=v
            if v then cb.BackgroundColor3=WHITE; cbS.Color=WHITE; lbl.TextColor3=WHITE
            else cb.BackgroundColor3=CHECK_OFF; cbS.Color=DIVIDER; lbl.TextColor3=TEXT_SEC end
            onToggle(v)
        end
        click.MouseButton1Click:Connect(function() setOn(not on) end)
        click.MouseEnter:Connect(function() wrap.BackgroundColor3=ROW_HOVER end)
        click.MouseLeave:Connect(function() wrap.BackgroundColor3=BG end)
    end

    makeVisRow("fog", "distance", 20, 500, cfg.fogEnd,
        function(on) setFog(on) end,
        function(v) cfg.fogEnd=v end)

    makeVisRow("motion blur", "intensity", 1, 40, cfg.blurSize,
        function(on) setBlur(on) end,
        function(v) cfg.blurSize=v end)
end

-- ================================================================
-- RESTART
-- ================================================================
local function restartFeature(key)
    local f=features[key]
    if f.conn then f.conn:Disconnect(); f.conn=nil end

    if     key=="PixelSurf"  then makeSurf(key,Vector3.new(0,0,0),   function() return cfg.pixelMaxSpeed   end)
    elseif key=="TextureBug" then makeSurf(key,Vector3.new(0,2.5,0), function() return cfg.textureMaxSpeed end)
    elseif key=="AutoBhop"   then bhop_start()
    elseif key=="EdgeBug"    then edgebug_start()
    elseif key=="JumpBug"    then jumpbug_start()
    elseif key=="LongJump"   then longjump_start()
    elseif key=="MiniJump"   then minijump_start()
    elseif key=="FakeAimbot" then fakeaimbot_start()
    end
end

-- ================================================================
-- MENU TOGGLE  [INSERT]
-- ================================================================
local menuOpen=false

local function setMenuOpen(open)
    menuOpen      = open
    win.Visible   = open
    if open then
        UserInputService.MouseBehavior  = Enum.MouseBehavior.Default
        UserInputService.MouseIconEnabled = true
    else
        UserInputService.MouseBehavior  = Enum.MouseBehavior.Default
    end
end

RunService.RenderStepped:Connect(function()
    if menuOpen then
        UserInputService.MouseBehavior    = Enum.MouseBehavior.Default
        UserInputService.MouseIconEnabled = true
    end
end)

local unloadHeld = {}
UserInputService.InputBegan:Connect(function(input,gpe)
    if not gpe and input.KeyCode==Enum.KeyCode.Insert then
        setMenuOpen(not menuOpen)
    end

    if not gpe then
        unloadHeld[input.KeyCode] = true
        if unloadHeld[Enum.KeyCode.U] and unloadHeld[Enum.KeyCode.O] then
            for key in pairs(features) do stopFeature(key) end
            setFog(false); setBlur(false)
            if fogConn then fogConn:Disconnect(); fogConn=nil end
            if blurConn then blurConn:Disconnect(); blurConn=nil end
            trailFolder:Destroy()
            screenGui:Destroy()
            UserInputService.MouseBehavior    = Enum.MouseBehavior.Default
            UserInputService.MouseIconEnabled = true
        end
    end
end)

UserInputService.InputEnded:Connect(function(input)
    unloadHeld[input.KeyCode] = nil
end)

-- ================================================================
-- RESPAWN
-- ================================================================
player.CharacterAdded:Connect(function(char)
    bindCharacter(char)
    task.wait(0.5)
    for key,f in pairs(features) do
        if f.enabled then
            restartFeature(key)
        end
    end
end)
