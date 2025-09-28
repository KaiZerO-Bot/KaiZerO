-- ============================
-- SERVICES
-- ============================
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer
local playerGui = LocalPlayer:WaitForChild("PlayerGui")
local backpack = LocalPlayer:WaitForChild("Backpack")
local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")

-- ============================
-- MODULES (Safe loading)
-- ============================
local Modules = ReplicatedStorage:WaitForChild("Modules")
local Utility = Modules:WaitForChild("Utility")
local BridgeNet2 = require(Utility:WaitForChild("BridgeNet2"))
local Util = (pcall(function() return require(Utility:WaitForChild("Util")) end) and require(Utility:WaitForChild("Util")) ) or nil
local Notification = (pcall(function() return require(Utility:WaitForChild("Notification")) end) and require(Utility:WaitForChild("Notification")) ) or nil

local PlayerDataModule = (pcall(function() return require(ReplicatedStorage:WaitForChild("PlayerData")) end) and require(ReplicatedStorage:WaitForChild("PlayerData")) ) or nil
local PlayerData = PlayerDataModule and PlayerDataModule:GetData()
local Data = PlayerData and PlayerData.Data

-- ============================
-- ASSETS / BRIDGES
-- ============================
local PlantsAssets = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Plants")
local SeedAssets = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Seeds")
local GearAssets = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Gears")

-- Bridges (ensure names match your setup)
local PlaceItemEvent = BridgeNet2.ReferenceBridge("PlaceItem")
local BuyItem = BridgeNet2.ReferenceBridge("BuyItem")
local UpdStock = BridgeNet2.ReferenceBridge("UpdStock")
local UpdatePlantStocks = BridgeNet2.ReferenceBridge("UpdatePlantStocks")

local BuyGear = BridgeNet2.ReferenceBridge("BuyGear")
local UpdGearStock = BridgeNet2.ReferenceBridge("UpdGearStock")
local UpdateGearStocks = BridgeNet2.ReferenceBridge("UpdateGearStocks")

local EquipBestBridge = BridgeNet2.ReferenceBridge("EquipBestBrainrots")

-- ============================
-- CONFIG
-- ============================
local CONFIG = {
    PLANT_DELAY = 0.5,
    PURCHASE_DELAY = 0.5,
    ON_COLOR = Color3.fromRGB(0, 170, 0),
    OFF_COLOR = Color3.fromRGB(170, 0, 0),
}

-- ============================
-- FILTERS / STATE
-- ============================
local ALL_RARITIES = {"Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Godly", "Secret"}
local RARITIES_TO_SHOW = {"Epic", "Legendary", "Mythic", "Godly", "Secret"}

local SeedRarityFilter = {
    ["Common"] = false, ["Uncommon"] = false, ["Rare"] = false, ["Epic"] = false,
    ["Legendary"] = false, ["Mythic"] = false, ["Godly"] = false, ["Secret"] = false
}
local GearRarityFilter = {
    ["Common"] = false, ["Uncommon"] = false, ["Rare"] = false, ["Epic"] = false,
    ["Legendary"] = false, ["Mythic"] = false, ["Godly"] = false, ["Secret"] = false
}

local NOTIFY_RARITIES_SEED = { ["Legendary"]=false, ["Mythic"]=false, ["Godly"]=false, ["Secret"]=false }
local NOTIFY_RARITIES_GEAR = { ["Legendary"]=false, ["Mythic"]=false, ["Godly"]=false, ["Secret"]=false }

local State = {
    AutoPlantEnabled = false,
    IsPlanting = false,
    AutoBuySeedsEnabled = false,
    IsBuyingSeeds = false,
    AutoBuyGearEnabled = false,
    IsBuyingGear = false,
    AutoEquipEnabled = false,
    EquipLoopHandle = nil,
    EquipInterval = 60, -- seconds
}

-- ============================
-- HELPERS
-- ============================
local function safeLog(prefix, msg)
    print(string.format("[%s] %s", prefix, tostring(msg)))
end

local function notify(title, content, duration)
    -- Fallback to in-game notifications if available, else print
    if Notification and Notification.Notify then
        pcall(function()
            Notification:Notify({Title = title, Text = content, Duration = duration or 3})
        end)
    else
        safeLog(title, content)
    end
end

-- ============================
-- AUTOPLANT LOGIC
-- ============================
local function getPlayerPlot(player)
    local Plots = workspace:FindFirstChild("Plots")
    if not Plots then return nil end
    for i = 1, 6 do
        local plot = Plots:FindFirstChild(tostring(i))
        local playerSign = plot and plot:FindFirstChild("PlayerSign")
        local displayLabel = playerSign and playerSign:FindFirstChild("BillboardGui") and playerSign.BillboardGui:FindFirstChild("TextLabel")
        if displayLabel and displayLabel.Text == player.DisplayName then
            return plot
        end
    end
    return nil
end

local function collectPlantableParts(plot)
    local rows = plot:FindFirstChild("Rows")
    if not rows then return {} end
    local plantableParts = {}
    for _, part in pairs(rows:GetDescendants()) do
        if part:IsA("BasePart") and part.BrickColor == BrickColor.new("Parsley green") and part.Parent.Name == "Grass" then
            table.insert(plantableParts, part)
        end
    end
    return plantableParts
end

local function plantSeedsCoroutine(plot, seedsToPlant)
    State.IsPlanting = true
    notify("AutoPlant", "Starting planting...", 2)

    local plantableParts = collectPlantableParts(plot)
    if #plantableParts == 0 then
        notify("AutoPlant", "No valid planting spots!", 3)
        State.IsPlanting = false
        return
    end

    for _, tool in ipairs(seedsToPlant) do
        local seedName = tool:GetAttribute("Plant")
        local seedAmount = tool:GetAttribute("Uses") or 1

        humanoid:EquipTool(tool)
        task.wait(0.2)

        for i = 1, seedAmount do
            if not State.AutoPlantEnabled then
                notify("AutoPlant", "Cancelled.", 2)
                humanoid:UnequipTools()
                State.IsPlanting = false
                return
            end

            local randomPart = plantableParts[math.random(#plantableParts)]
            local size = randomPart.Size
            local randomPosition = randomPart.Position + Vector3.new(
                math.random(-size.X / 2, size.X / 2),
                0,
                math.random(-size.Z / 2, size.Z / 2)
            )

            pcall(function()
                PlaceItemEvent:Fire({
                    ["Item"] = seedName,
                    ["CFrame"] = CFrame.new(randomPosition),
                    ["ID"] = tool:GetAttribute("ID"),
                    ["Floor"] = randomPart
                })
            end)

            task.wait(CONFIG.PLANT_DELAY)
        end

        task.wait(0.5)
    end

    humanoid:UnequipTools()
    notify("AutoPlant", "All seeds planted!", 3)
    State.IsPlanting = false
end

local function startPlantingProcess()
    if State.IsPlanting then return end
    local playerPlot = getPlayerPlot(LocalPlayer)
    if not playerPlot then
        notify("AutoPlant", "Your plot could not be found!", 3)
        return
    end

    local seedsInBackpack = {}
    for _, item in ipairs(backpack:GetChildren()) do
        if item and item:IsA("Tool") and item:GetAttribute("Plant") then
            local plant = PlantsAssets:FindFirstChild(item:GetAttribute("Plant"))
            local rarity = plant and plant:GetAttribute("Rarity") or "Common"
            if string.lower(rarity) ~= "common" then
                table.insert(seedsInBackpack, item)
            end
        end
    end

    if #seedsInBackpack == 0 then
        notify("AutoPlant", "No non-Common seeds found.", 3)
        return
    end

    coroutine.wrap(function() plantSeedsCoroutine(playerPlot, seedsInBackpack) end)()
end

backpack.ChildAdded:Connect(function(child)
    if State.AutoPlantEnabled and not State.IsPlanting and child:IsA("Tool") and child:GetAttribute("Plant") then
        task.wait(0.5)
        startPlantingProcess()
    end
end)

-- ============================
-- AUTOBUY SEEDS LOGIC
-- ============================
local function CanBuyMoreItem(price)
    if not Data or not Util then return true end
    if Data.Money < price then return false end
    local maxSpace = Util:GetMaxInventorySpace(LocalPlayer)
    if #LocalPlayer.Backpack:GetChildren() >= maxSpace then return false end
    return true
end

local function AutoBuySeeds()
    if not State.AutoBuySeedsEnabled or State.IsBuyingSeeds then return end
    State.IsBuyingSeeds = true
    safeLog("AutoBuySeeds", "Checking seeds...")

    for _, seedData in ipairs(SeedAssets:GetChildren()) do
        local price = seedData:GetAttribute("Price")
        local seedName = seedData.Name
        local plant = PlantsAssets:FindFirstChild(seedData:GetAttribute("Plant"))
        local rarity = plant and plant:GetAttribute("Rarity") or "Common"
        local stock = seedData:GetAttribute("Stock") or 0

        if SeedRarityFilter[rarity] and stock > 0 then 
            for i = 1, stock do
                if not CanBuyMoreItem(price) then break end
                pcall(function() BuyItem:Fire(seedName) end)
                safeLog("AutoBuySeeds", ("Bought 1x %s"):format(seedName))
                task.wait(CONFIG.PURCHASE_DELAY)
            end
        end
    end

    State.IsBuyingSeeds = false
    safeLog("AutoBuySeeds", "Finished buy cycle")
end

UpdStock:Connect(function()
    if State.AutoBuySeedsEnabled then task.wait(3); AutoBuySeeds() end
end)
UpdatePlantStocks:Connect(function()
    if State.AutoBuySeedsEnabled then task.wait(4); AutoBuySeeds() end
end)
LocalPlayer:GetAttributeChangedSignal("NextSeedRestock"):Connect(function()
    if State.AutoBuySeedsEnabled and LocalPlayer:GetAttribute("NextSeedRestock") == 0 then
        task.wait(5); AutoBuySeeds()
    end
end)

-- ============================
-- AUTOBUY GEAR LOGIC
-- ============================
local function CanBuyMoreGear(price)
    if not Data or not Util then return true end
    if Data.Money < price then return false end
    local maxSpace = Util:GetMaxInventorySpace(LocalPlayer)
    if #LocalPlayer.Backpack:GetChildren() >= maxSpace then return false end
    return true
end

local function AutoBuyGears()
    if not State.AutoBuyGearEnabled or State.IsBuyingGear then return end
    State.IsBuyingGear = true
    safeLog("AutoBuyGear", "Checking gears...")

    for _, gear in ipairs(GearAssets:GetChildren()) do
        local price = gear:GetAttribute("Price")
        local rarity = gear:GetAttribute("Rarity")
        local stock = gear:GetAttribute("Stock") or 0
        local gearName = gear.Name

        if GearRarityFilter[rarity] and stock > 0 then
            for i = 1, stock do
                if not CanBuyMoreGear(price) then break end
                pcall(function() BuyGear:Fire(gearName) end)
                safeLog("AutoBuyGear", ("Bought 1x %s"):format(gearName))
                task.wait(CONFIG.PURCHASE_DELAY)
            end
        end
    end

    State.IsBuyingGear = false
    safeLog("AutoBuyGear", "Finished buy cycle")
end

UpdGearStock:Connect(function()
    if State.AutoBuyGearEnabled then task.wait(3); AutoBuyGears() end
end)
UpdateGearStocks:Connect(function()
    if State.AutoBuyGearEnabled then task.wait(4); AutoBuyGears() end
end)
LocalPlayer:GetAttributeChangedSignal("NextGearRestock"):Connect(function()
    if State.AutoBuyGearEnabled and LocalPlayer:GetAttribute("NextGearRestock") == 0 then
        task.wait(5); AutoBuyGears()
    end
end)

-- ============================
-- AUTOEQUIPBEST LOGIC
-- ============================
local function startEquipLoop()
    if State.EquipLoopHandle then return end
    safeLog("AutoEquip", "Equip loop running")
    State.EquipLoopHandle = task.spawn(function()
        while State.AutoEquipEnabled do
            pcall(function()
                EquipBestBridge:Fire()
            end)
            safeLog("AutoEquip", "Equipped best gear. Next in " .. State.EquipInterval .. "s")
            local timeWaited = 0
            while timeWaited < State.EquipInterval and State.AutoEquipEnabled do
                task.wait(1)
                timeWaited += 1
            end
        end
        State.EquipLoopHandle = nil
        safeLog("AutoEquip", "Equip loop stopped")
    end)
end

local function stopEquipLoop()
    State.AutoEquipEnabled = false
    if State.EquipLoopHandle then
        task.cancel(State.EquipLoopHandle)
    end
    State.EquipLoopHandle = nil
    safeLog("AutoEquip", "Stopped")
end

-- ============================
-- RAYFIELD UI (Integrated)
-- ============================

-- Load Rayfield
local Rayfield = loadstring(game:HttpGet('https://raw.githubusercontent.com/KaiZerO-Bot/KaiZerO/refs/heads/main/UxUii.lua'))()

-- Window
local Window = Rayfield:CreateWindow({
    Name = "No Hack No Life",
    LoadingTitle = "Loading. . .",
    LoadingSubtitle = "by King",
    ConfigurationSaving = {
        Enabled = true,
        FolderName = "NoHackNoLife",
        FileName = "MainConfig"
    },
    KeySystem = false,
})

-- Tab
local MainTab = Window:CreateTab("Main", 4483362458)

-- Section: Core toggles
MainTab:CreateSection("Automation (Select rarity before trun on automatic)")

MainTab:CreateToggle({
    Name = "Auto Plant",
    CurrentValue = false,
    Flag = "AutoPlant",
    Callback = function(Value)
        State.AutoPlantEnabled = Value
        if Value then
            startPlantingProcess()
        else
            State.IsPlanting = false
        end
    end,
})

MainTab:CreateToggle({
    Name = "Auto Buy Seeds",
    CurrentValue = false,
    Flag = "AutoBuySeeds",
    Callback = function(Value)
        State.AutoBuySeedsEnabled = Value
        if Value then AutoBuySeeds() end
    end,
})

MainTab:CreateToggle({
    Name = "Auto Buy Gear",
    CurrentValue = false,
    Flag = "AutoBuyGear",
    Callback = function(Value)
        State.AutoBuyGearEnabled = Value
        if Value then AutoBuyGears() end
    end,
})

MainTab:CreateToggle({
    Name = "Auto Equip Best",
    CurrentValue = false,
    Flag = "AutoEquipBest",
    Callback = function(Value)
        State.AutoEquipEnabled = Value
        if Value then
            startEquipLoop()
        else
            stopEquipLoop()
        end
    end,
})

-- Section: Timing
MainTab:CreateSection("Timing")

-- Optional convenience slider mirroring interval
MainTab:CreateSlider({
    Name = "Auto Equip Timing",
    Range = {5, 300},
    Increment = 5,
    Suffix = "s",
    CurrentValue = State.EquipInterval,
    Flag = "EquipIntervalSlider",
    Callback = function(Value)
        State.EquipInterval = Value
        safeLog("AutoEquip", "Interval set to: " .. Value .. "s")
    end,
})

-- Section: Rarity filters
MainTab:CreateSection("Rarity filters")

-- Seeds rarity multiselect
MainTab:CreateDropdown({
    Name = "Seed rarities to buy",
    Options = RARITIES_TO_SHOW,
    CurrentOption = (function()
        local defaults = {}
        for _, r in ipairs(RARITIES_TO_SHOW) do
            if SeedRarityFilter[r] then table.insert(defaults, r) end
        end
        return defaults
    end)(),
    MultipleOptions = true,
    Flag = "SeedRarityDropdown",
    Callback = function(selected)
        -- Reset display rarities to false, then enable selected
        for _, r in ipairs(RARITIES_TO_SHOW) do
            SeedRarityFilter[r] = false
        end
        for _, r in ipairs(selected) do
            SeedRarityFilter[r] = true
        end
        safeLog("RarityFilter", "Seed: " .. table.concat(selected, ", "))
    end,
})

-- Gear rarity multiselect
MainTab:CreateDropdown({
    Name = "Gear rarities to buy",
    Options = RARITIES_TO_SHOW,
    CurrentOption = (function()
        local defaults = {}
        for _, r in ipairs(RARITIES_TO_SHOW) do
            if GearRarityFilter[r] then table.insert(defaults, r) end
        end
        return defaults
    end)(),
    MultipleOptions = true,
    Flag = "GearRarityDropdown",
    Callback = function(selected)
        for _, r in ipairs(RARITIES_TO_SHOW) do
            GearRarityFilter[r] = false
        end
        for _, r in ipairs(selected) do
            GearRarityFilter[r] = true
        end
        safeLog("RarityFilter", "Gear: " .. table.concat(selected, ", "))
    end,
})

-- Section: Manual actions
MainTab:CreateSection("Manual actions")

MainTab:CreateButton({
    Name = "Run seed buying cycle now",
    Callback = function()
        AutoBuySeeds()
    end,
})

MainTab:CreateButton({
    Name = "Run gear buying cycle now",
    Callback = function()
        AutoBuyGears()
    end,
})

MainTab:CreateButton({
    Name = "Equip best now",
    Callback = function()
        pcall(function()
            EquipBestBridge:Fire()
        end)
        notify("AutoEquip", "Equipped best", 2)
    end,
})

-- Final log
safeLog("CombinedAuto", "No Hack No Life loaded.")


