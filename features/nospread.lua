-- No-Spread Standalone (Press Right Shift to toggle)
local player = game:GetService("Players").LocalPlayer
local rep = game:GetService("ReplicatedStorage")
local rs = game:GetService("RunService")
local uis = game:GetService("UserInputService")

local noSpreadActive = false
local currentSpreadFolder = nil
local originalSpreadValues = {}

local function getEquippedGunName()
    local char = player.Character
    if not char then return nil end
    local gun = char:FindFirstChild("Gun")
    return gun and gun:GetAttribute("GunName")
end

local function getCurrentSpreadFolder()
    local gunName = getEquippedGunName()
    if not gunName then return nil end
    local weapons = rep:FindFirstChild("Weapons")
    if not weapons then return nil end
    local gunFolder = weapons:FindFirstChild(gunName)
    if not gunFolder then return nil end
    return gunFolder:FindFirstChild("Spread")
end

local function saveOriginals(spreadFolder)
    if not spreadFolder then return end
    local gunName = getEquippedGunName()
    if not gunName then return end
    if originalSpreadValues[gunName] then return end
    
    originalSpreadValues[gunName] = {}
    for _, v in ipairs(spreadFolder:GetChildren()) do
        if v:IsA("NumberValue") or v:IsA("IntValue") or v:IsA("FloatValue") then
            originalSpreadValues[gunName][v] = v.Value
        end
    end
end

local function applyLowSpread(spreadFolder)
    if not spreadFolder then return end
    for _, v in ipairs(spreadFolder:GetChildren()) do
        if v:IsA("NumberValue") or v:IsA("IntValue") or v:IsA("FloatValue") then
            v.Value = math.random(5, 15) / 100
        end
    end
end

local function restoreSpread(spreadFolder)
    local gunName = getEquippedGunName()
    if not gunName then return end
    if not originalSpreadValues[gunName] then return end
    for v, originalVal in pairs(originalSpreadValues[gunName]) do
        if v and v.Parent then
            v.Value = originalVal
        end
    end
end

-- Right Shift toggle
uis.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == Enum.KeyCode.RightShift then
        noSpreadActive = not noSpreadActive
        
        if noSpreadActive then
            currentSpreadFolder = getCurrentSpreadFolder()
            if currentSpreadFolder then
                saveOriginals(currentSpreadFolder)
            end
            print("No-Spread: ON")
        else
            if currentSpreadFolder then
                restoreSpread(currentSpreadFolder)
            end
            currentSpreadFolder = nil
            print("No-Spread: OFF")
        end
    end
end)

-- Override on Heartbeat
rs.Heartbeat:Connect(function()
    if noSpreadActive and currentSpreadFolder then
        local newFolder = getCurrentSpreadFolder()
        if newFolder ~= currentSpreadFolder then
            if currentSpreadFolder then restoreSpread(currentSpreadFolder) end
            currentSpreadFolder = newFolder
            if currentSpreadFolder then saveOriginals(currentSpreadFolder) end
        end
        applyLowSpread(currentSpreadFolder)
    end
end)

-- Override on RenderStepped (double force)
rs.RenderStepped:Connect(function()
    if noSpreadActive and currentSpreadFolder then
        applyLowSpread(currentSpreadFolder)
    end
end)

-- Handle respawn
player.CharacterAdded:Connect(function()
    task.wait(1)
    if noSpreadActive then
        if currentSpreadFolder then restoreSpread(currentSpreadFolder) end
        currentSpreadFolder = getCurrentSpreadFolder()
        if currentSpreadFolder then saveOriginals(currentSpreadFolder) end
    end
end)

print("No-Spread loaded! Press RIGHT SHIFT to toggle")
print("Spread: 0.05 - 0.15")
