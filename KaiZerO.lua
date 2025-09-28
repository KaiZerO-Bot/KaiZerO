-- Combined Auto Controller (Merged LOGIC + UXUI + Bridge)
-- Place this single file in a LocalScript environment (PlayerGui / StarterPlayerScripts) as needed.

-- SERVICES
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer
local playerGui = LocalPlayer:WaitForChild("PlayerGui")
local backpack = LocalPlayer:WaitForChild("Backpack")
local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")

-- MODULES (safe require as in original)
local Modules = ReplicatedStorage:WaitForChild("Modules")
local Utility = Modules:WaitForChild("Utility")
local BridgeNet2 = require(Utility:WaitForChild("BridgeNet2"))
local Util = (pcall(function() return require(Utility:WaitForChild("Util")) end) and require(Utility:WaitForChild("Util")) ) or nil
local Notification = (pcall(function() return require(Utility:WaitForChild("Notification")) end) and require(Utility:WaitForChild("Notification")) ) or nil

local PlayerDataModule = (pcall(function() return require(ReplicatedStorage:WaitForChild("PlayerData")) end) and require(ReplicatedStorage:WaitForChild("PlayerData")) ) or nil
local PlayerData = PlayerDataModule and PlayerDataModule:GetData()
local Data = PlayerData and PlayerData.Data

-- ASSETS / BRIDGES
local PlantsAssets = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Plants")
local SeedAssets = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Seeds")
local GearAssets = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Gears")

local PlaceItemEvent = BridgeNet2.ReferenceBridge("PlaceItem")
local BuyItem = BridgeNet2.ReferenceBridge("BuyItem")
local UpdStock = BridgeNet2.ReferenceBridge("UpdStock")
local UpdatePlantStocks = BridgeNet2.ReferenceBridge("UpdatePlantStocks")
local BuyGear = BridgeNet2.ReferenceBridge("BuyGear")
local UpdGearStock = BridgeNet2.ReferenceBridge("UpdGearStock")
local UpdateGearStocks = BridgeNet2.ReferenceBridge("UpdateGearStocks")
local EquipBestBridge = BridgeNet2.ReferenceBridge("EquipBestBrainrots")

-- CONFIG
local CONFIG = {
    PLANT_DELAY = 0.5,
    PURCHASE_DELAY = 0.5,
    WEBHOOK_URL = "",
    ON_COLOR = Color3.fromRGB(0, 170, 0),
    OFF_COLOR = Color3.fromRGB(170, 0, 0),
    RARITY_ON_COLOR = Color3.fromRGB(0, 150, 0),
    RARITY_OFF_COLOR = Color3.fromRGB(150, 0, 0),
    STATUS_NORMAL_COLOR = Color3.fromRGB(200, 200, 200),
    STATUS_ERROR_COLOR = Color3.fromRGB(255, 120, 120),
}

-- Rarity filters (Default)
local ALL_RARITIES = {"Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Godly", "Secret"}
local SeedRarityFilter = {
    ["Common"] = false, ["Uncommon"] = false, ["Rare"] = false, ["Epic"] = false,
    ["Legendary"] = true, ["Mythic"] = true, ["Godly"] = true, ["Secret"] = true
}
local GearRarityFilter = {
    ["Common"] = false, ["Uncommon"] = false, ["Rare"] = false, ["Epic"] = true,
    ["Legendary"] = true, ["Mythic"] = true, ["Godly"] = true, ["Secret"] = true
}

local NOTIFY_RARITIES_SEED = { ["Legendary"]=false, ["Mythic"]=false, ["Godly"]=false, ["Secret"]=false }
local NOTIFY_RARITIES_GEAR = { ["Legendary"]=false, ["Mythic"]=false, ["Godly"]=false, ["Secret"]=false }

-- STATE FLAGS
local State = {
    AutoPlantEnabled = false,
    IsPlanting = false,
    AutoBuySeedsEnabled = false,
    IsBuyingSeeds = false,
    AutoBuyGearEnabled = false,
    IsBuyingGear = false,
    AutoEquipEnabled = false,
    EquipLoopHandle = nil,
    EquipInterval = 60,
}

-- =========================
-- UI <-> Logic bridge (sync with UXUI's getgenv().AutoUI)
-- =========================

getgenv().AutoUI = getgenv().AutoUI or {}
local UI = getgenv().AutoUI

UI.AutoPlantEnabled = UI.AutoPlantEnabled or false
UI.AutoBuySeedsEnabled = UI.AutoBuySeedsEnabled or false
UI.AutoBuyGearEnabled = UI.AutoBuyGearEnabled or false
UI.AutoEquipEnabled = UI.AutoEquipEnabled or false
UI.EquipInterval = UI.EquipInterval or State.EquipInterval or 60
UI.SeedRarityFilter = UI.SeedRarityFilter or { Epic=true, Legendary=true, Mythic=true, Godly=true, Secret=true }
UI.GearRarityFilter = UI.GearRarityFilter or { Epic=true, Legendary=true, Mythic=true, Godly=true, Secret=true }

local lastUI = {
    AutoPlantEnabled = UI.AutoPlantEnabled,
    AutoBuySeedsEnabled = UI.AutoBuySeedsEnabled,
    AutoBuyGearEnabled = UI.AutoBuyGearEnabled,
    AutoEquipEnabled = UI.AutoEquipEnabled,
    EquipInterval = UI.EquipInterval
}

-- =========================
-- CONFIG SAVE / LOAD
-- =========================
local CONFIG_FILE = "AutoControllerConfig.json"

local function saveConfig()
    local data = {
        AutoPlantEnabled = UI.AutoPlantEnabled,
        AutoBuySeedsEnabled = UI.AutoBuySeedsEnabled,
        AutoBuyGearEnabled = UI.AutoBuyGearEnabled,
        AutoEquipEnabled = UI.AutoEquipEnabled,
        EquipInterval = UI.EquipInterval,
        SeedRarityFilter = UI.SeedRarityFilter,
        GearRarityFilter = UI.GearRarityFilter
    }
    local encoded = HttpService:JSONEncode(data)
    pcall(function() writefile(CONFIG_FILE, encoded) end)
end

local function loadConfig()
    if isfile(CONFIG_FILE) then
        local ok, decoded = pcall(function()
            return HttpService:JSONDecode(readfile(CONFIG_FILE))
        end)
        if ok and decoded then
            for k,v in pairs(decoded) do
                UI[k] = v
            end
        end
    end
end

local function copyFiltersFromUI()
    for k,v in pairs(UI.SeedRarityFilter or {}) do
        if SeedRarityFilter[k] ~= nil then SeedRarityFilter[k] = v end
    end
    for k,v in pairs(UI.GearRarityFilter or {}) do
        if GearRarityFilter[k] ~= nil then GearRarityFilter[k] = v end
    end
end

local function writeStateToUI()
    if UI.AutoPlantEnabled ~= State.AutoPlantEnabled then UI.AutoPlantEnabled = State.AutoPlantEnabled end
    if UI.AutoBuySeedsEnabled ~= State.AutoBuySeedsEnabled then UI.AutoBuySeedsEnabled = State.AutoBuySeedsEnabled end
    if UI.AutoBuyGearEnabled ~= State.AutoBuyGearEnabled then UI.AutoBuyGearEnabled = State.AutoBuyGearEnabled end
    if UI.AutoEquipEnabled ~= State.AutoEquipEnabled then UI.AutoEquipEnabled = State.AutoEquipEnabled end
    if UI.EquipInterval ~= State.EquipInterval then UI.EquipInterval = State.EquipInterval end

    for k,_ in pairs(UI.SeedRarityFilter or {}) do UI.SeedRarityFilter[k] = SeedRarityFilter[k] end
    for k,_ in pairs(UI.GearRarityFilter or {}) do UI.GearRarityFilter[k] = GearRarityFilter[k] end
end

backpack.ChildAdded:Connect(function(child)
    if UI.AutoPlantEnabled and not State.IsPlanting and child:IsA("Tool") and child:GetAttribute("Plant") then
        task.wait(0.3)
        pcall(function() startPlantingProcess() end)
    end
end)

-- =========================
-- HELPER FUNCTIONS
-- =========================
local function safeLog(prefix, msg)
    print(string.format("[%s] %s", prefix, tostring(msg)))
end

local StatusLabels = {} -- placeholder used by UI below; updated by logic
local function updateStatusLabel(idx, text, isError)
    local lbl = StatusLabels[idx]
    if lbl then
        lbl.Text = "Status: " .. tostring(text)
        lbl.TextColor3 = isError and CONFIG.STATUS_ERROR_COLOR or CONFIG.STATUS_NORMAL_COLOR
    end
end

-- =========================
-- AUTOPLANT LOGIC
-- =========================
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
    updateStatusLabel(1, "Preparing to plant...", false)

    local plantableParts = collectPlantableParts(plot)
    if #plantableParts == 0 then
        updateStatusLabel(1, "No valid planting spots!", true)
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
                updateStatusLabel(1, "Cancelled.", false)
                humanoid:UnequipTools()
                State.IsPlanting = false
                return
            end

            updateStatusLabel(1, ("Planting %s (%d/%d)..."):format(seedName, i, seedAmount), false)
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
    updateStatusLabel(1, "All seeds planted!", false)
    State.IsPlanting = false
end

function startPlantingProcess()
    if State.IsPlanting then return end
    local playerPlot = getPlayerPlot(LocalPlayer)
    if not playerPlot then
        updateStatusLabel(1, "Your plot could not be found!", true)
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
        updateStatusLabel(1, "No non-Common seeds found.", true)
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

-- =========================
-- AUTOBUY SEEDS
-- =========================
local function CanBuyMoreItem(price)
    if not Data or not Util then return true end
    if Data.Money < price then return false end
    local maxSpace = Util:GetMaxInventorySpace(LocalPlayer)
    if #LocalPlayer.Backpack:GetChildren() >= maxSpace then return false end
    return true
end

function AutoBuySeeds()
    if not State.AutoBuySeedsEnabled then return end
    if State.IsBuyingSeeds then return end
    State.IsBuyingSeeds = true
    updateStatusLabel(2, "Checking seeds...", false)

    local itemsForNotification = {}

    for _, seedData in ipairs(SeedAssets:GetChildren()) do
        local price = seedData:GetAttribute("Price")
        local seedName = seedData.Name
        local plant = PlantsAssets:FindFirstChild(seedData:GetAttribute("Plant"))
        local rarity = plant and plant:GetAttribute("Rarity") or "Common"
        local stock = seedData:GetAttribute("Stock") or 0

        if SeedRarityFilter[rarity] and stock > 0 then 
            local purchasedCount = 0
            for i = 1, stock do
                if not CanBuyMoreItem(price) then break end
                pcall(function() BuyItem:Fire(seedName) end)
                purchasedCount = purchasedCount + 1
                safeLog("AutoBuySeeds", ("Bought 1x %s"):format(seedName))
                task.wait(CONFIG.PURCHASE_DELAY)
            end
            if purchasedCount > 0 and NOTIFY_RARITIES_SEED[rarity] then
                table.insert(itemsForNotification, {Name = seedName, Rarity = rarity, Quantity = purchasedCount})
            end
        end
    end

    State.IsBuyingSeeds = false
    updateStatusLabel(2, "Finished buy cycle", false)
end

UpdStock:Connect(function(seedName)
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

-- =========================
-- AUTOBUY GEAR
-- =========================
local function CanBuyMoreGear(price)
    if not Data or not Util then return true end
    if Data.Money < price then return false end
    local maxSpace = Util:GetMaxInventorySpace(LocalPlayer)
    if #LocalPlayer.Backpack:GetChildren() >= maxSpace then return false end
    return true
end

function AutoBuyGears()
    if not State.AutoBuyGearEnabled then return end
    if State.IsBuyingGear then return end
    State.IsBuyingGear = true
    updateStatusLabel(3, "Checking gears...", false)

    local itemsForNotification = {}

    for _, gear in ipairs(GearAssets:GetChildren()) do
        local price = gear:GetAttribute("Price")
        local rarity = gear:GetAttribute("Rarity")
        local stock = gear:GetAttribute("Stock") or 0
        local gearName = gear.Name

        if GearRarityFilter[rarity] and stock > 0 then
            local purchasedCount = 0
            for i = 1, stock do
                if not CanBuyMoreGear(price) then break end
                pcall(function() BuyGear:Fire(gearName) end)
                purchasedCount = purchasedCount + 1
                safeLog("AutoBuyGear", ("Bought 1x %s"):format(gearName))
                task.wait(CONFIG.PURCHASE_DELAY)
            end
            if purchasedCount > 0 and NOTIFY_RARITIES_GEAR[rarity] then
                table.insert(itemsForNotification, {Name = gearName, Rarity = rarity, Quantity = purchasedCount})
            end
        end
    end

    State.IsBuyingGear = false
    updateStatusLabel(3, "Finished buy cycle", false)
end

UpdGearStock:Connect(function(gearName)
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

-- =========================
-- AUTOEQUIPBEST
-- =========================
function startEquipLoop()
    if State.EquipLoopHandle then return end
    State.AutoEquipEnabled = true
    updateStatusLabel(4, "Equip loop running", false)
    State.EquipLoopHandle = task.spawn(function()
        while State.AutoEquipEnabled do
            pcall(function()
                EquipBestBridge:Fire()
            end)
            local timeWaited = State.EquipInterval
            while timeWaited > 0 and State.AutoEquipEnabled do
                task.wait(1)
                timeWaited = timeWaited - 1
                updateStatusLabel(4, "Equipped best gear. Next in " .. timeWaited .. "s", false)
            end
        end
        State.EquipLoopHandle = nil
        updateStatusLabel(4, "Equip loop stopped", false)
    end)
end

function stopEquipLoop()
    State.AutoEquipEnabled = false
    State.EquipLoopHandle = nil
    updateStatusLabel(4, "Stopped", false)
end


local function applyUIToState()
    if UI.AutoPlantEnabled ~= lastUI.AutoPlantEnabled then
        State.AutoPlantEnabled = UI.AutoPlantEnabled
        if State.AutoPlantEnabled then pcall(function() startPlantingProcess() end) else State.IsPlanting = false end
        lastUI.AutoPlantEnabled = UI.AutoPlantEnabled
    end

    if UI.AutoBuySeedsEnabled ~= lastUI.AutoBuySeedsEnabled then
        State.AutoBuySeedsEnabled = UI.AutoBuySeedsEnabled
        if State.AutoBuySeedsEnabled then pcall(function() AutoBuySeeds() end) end
        lastUI.AutoBuySeedsEnabled = UI.AutoBuySeedsEnabled
    end

    if UI.AutoBuyGearEnabled ~= lastUI.AutoBuyGearEnabled then
        State.AutoBuyGearEnabled = UI.AutoBuyGearEnabled
        if State.AutoBuyGearEnabled then pcall(function() AutoBuyGears() end) end
        lastUI.AutoBuyGearEnabled = UI.AutoBuyGearEnabled
    end

    if UI.AutoEquipEnabled ~= lastUI.AutoEquipEnabled then
        State.AutoEquipEnabled = UI.AutoEquipEnabled
        if State.AutoEquipEnabled then pcall(function() startEquipLoop() end) else pcall(function() stopEquipLoop() end) end
        lastUI.AutoEquipEnabled = UI.AutoEquipEnabled
    end

    if UI.EquipInterval ~= lastUI.EquipInterval then
        local v = tonumber(UI.EquipInterval)
        if v and v >= 1 then
            State.EquipInterval = math.floor(v)
            UI.EquipInterval = State.EquipInterval
            lastUI.EquipInterval = State.EquipInterval
        else
            UI.EquipInterval = State.EquipInterval
            lastUI.EquipInterval = State.EquipInterval
        end
    end

    copyFiltersFromUI()
end


spawn(function()
    while true do
        pcall(function()
            applyUIToState()
            writeStateToUI()
            saveConfig()
        end)
        task.wait(1)
    end
end)


-- =========================
-- UX / UI (derived from UXUI.txt, unchanged visuals & behavior)
-- =========================

-- Try to obtain bridges (safe)
local function safeRequireBridge(name)
    local ok, BridgeNet2_local = pcall(function()
        return require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Utility"):WaitForChild("BridgeNet2"))
    end)
    if not ok or not BridgeNet2_local then return nil end
    local ok2, ref = pcall(function() return BridgeNet2_local.ReferenceBridge(name) end)
    if ok2 then return ref end
    return nil
end

local PlaceItemEvent_UI = safeRequireBridge("PlaceItem")
local BuyItem_UI = safeRequireBridge("BuyItem")
local BuyGear_UI = safeRequireBridge("BuyGear")
local EquipBestBridge_UI = safeRequireBridge("EquipBestBrainrots")

-- Ensure shared config table (G = getgenv().AutoUI)
local G = getgenv().AutoUI

-- Helper: create UI instances
local function new(class, props)
    local obj = Instance.new(class)
    if props then
        for k,v in pairs(props) do obj[k] = v end
    end
    return obj
end

-- Root screen gui
local screen = new("ScreenGui", { Name = "AutoControllerUI", Parent = playerGui, ZIndexBehavior = Enum.ZIndexBehavior.Sibling })
-- Main card
local card = new("Frame", {
    Parent = screen,
    Size = UDim2.new(0, 520, 0, 500),
    Position = UDim2.new(0.5, -260, 0.15, 0),
    BackgroundColor3 = Color3.fromRGB(22, 22, 31),
})
new("UICorner", { Parent = card, CornerRadius = UDim.new(0,12) })

-- Title bar
local titleBar = new("Frame", { Parent = card, Size = UDim2.new(1,0,0,54), BackgroundColor3 = Color3.fromRGB(28,30,35) })
new("UICorner", { Parent = titleBar, CornerRadius = UDim.new(0, 12) })
local title = new("TextLabel", {
    Parent = titleBar,
    Size = UDim2.new(1,-20,1,0),
    Position = UDim2.new(0,10,0,0),
    BackgroundTransparency = 1,
    Text = "No Hack No Life",
    Font = Enum.Font.GothamBold,
    TextSize = 22,
    TextColor3 = Color3.fromRGB(235,235,240),
    TextXAlignment = Enum.TextXAlignment.Left
})

-- Close button
local CloseBtn = Instance.new("TextButton")
CloseBtn.Parent = titleBar
CloseBtn.Size = UDim2.new(0, 40, 0, 40)
CloseBtn.Position = UDim2.new(1, -48, 0.5, -20)
CloseBtn.BackgroundColor3 = Color3.fromRGB(45,45,50)
CloseBtn.Text = "X"
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.TextSize = 20
CloseBtn.TextColor3 = Color3.fromRGB(220,220,220)
CloseBtn.AutoButtonColor = false
Instance.new("UICorner", CloseBtn).CornerRadius = UDim.new(0, 8)

CloseBtn.MouseEnter:Connect(function()
    TweenService:Create(CloseBtn, TweenInfo.new(0.15), {BackgroundColor3 = Color3.fromRGB(200,80,80)}):Play()
end)
CloseBtn.MouseLeave:Connect(function()
    TweenService:Create(CloseBtn, TweenInfo.new(0.15), {BackgroundColor3 = Color3.fromRGB(45,45,50)}):Play()
end)
CloseBtn.MouseButton1Click:Connect(function()
    card.Visible = false
end)

UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == Enum.KeyCode.LeftAlt then
        card.Visible = not card.Visible
    end
end)

-- Content area
local content = new("Frame", { Parent = card, Position = UDim2.new(0, 16, 0, 64), Size = UDim2.new(1, -32, 1, -80), BackgroundTransparency = 1 })
local leftCol = new("Frame", { Parent = content, Size = UDim2.new(0.5, -8, 1, 0), BackgroundTransparency = 1 })
local rightCol = new("Frame", { Parent = content, Size = UDim2.new(0.5, -8, 1, 0), Position = UDim2.new(0.5, 16, 0, 0), BackgroundTransparency = 1 })

local ON_COLOR = Color3.fromRGB(60,179,135)
local OFF_COLOR = Color3.fromRGB(70, 78, 86)
local STAT_COLOR = Color3.fromRGB(230, 230, 235)

local function makeToggle(parent, name, y, initialState, onChange)
    local container = new("Frame", { Parent = parent, Size = UDim2.new(1,0,0,72), Position = UDim2.new(0,0,0,y), BackgroundTransparency = 1 })
    local label = new("TextLabel", {
        Parent = container,
        Size = UDim2.new(1,0,0,28),
        Position = UDim2.new(0,0,0,0),
        BackgroundTransparency = 1,
        Text = name,
        Font = Enum.Font.GothamSemibold,
        TextSize = 18,
        TextColor3 = Color3.fromRGB(255,255,255),
        TextXAlignment = Enum.TextXAlignment.Left
    })
    local status = new("TextLabel", {
        Parent = container,
        Size = UDim2.new(1,0,0,18),
        Position = UDim2.new(0,0,0,30),
        BackgroundTransparency = 1,
        Text = "Status: Disabled",
        Font = Enum.Font.Gotham,
        TextSize = 14,
        TextColor3 = STAT_COLOR,
        TextXAlignment = Enum.TextXAlignment.Left
    })
    local pill = new("TextButton", {
        Parent = container,
        Size = UDim2.new(0, 70, 0, 28),
        Position = UDim2.new(1, -80, 0, 4),
        BackgroundColor3 = initialState and ON_COLOR or OFF_COLOR,
        Text = initialState and "ON" or "OFF",
        Font = Enum.Font.GothamBold,
        TextSize = 14,
        TextColor3 = Color3.fromRGB(20,20,20),
    })
    new("UICorner", { Parent = pill, CornerRadius = UDim.new(0,14) })

    pill.MouseEnter:Connect(function() TweenService:Create(pill, TweenInfo.new(0.12), {Size = pill.Size + UDim2.new(0,8,0,4)}):Play() end)
    pill.MouseLeave:Connect(function() TweenService:Create(pill, TweenInfo.new(0.12), {Size = UDim2.new(0,70,0,28)}):Play() end)

    local state = initialState
    pill.MouseButton1Click:Connect(function()
        state = not state
        pill.BackgroundColor3 = state and ON_COLOR or OFF_COLOR
        pill.Text = state and "ON" or "OFF"
        status.Text = "Status: " .. (state and "Enabled" or "Disabled")
        if onChange then pcall(onChange, state) end
    end)

    table.insert(StatusLabels, status)
    return { Container = container, Label = label, Status = status, Pill = pill }
end

-- โหลด config ตอนเริ่ม
loadConfig()

-- Create toggles and bind to getgenv().AutoUI (G)
local t1 = makeToggle(leftCol, "AutoPlant", 0, G.AutoPlantEnabled, function(s) G.AutoPlantEnabled = s end)
local t2 = makeToggle(leftCol, "AutoBuy Seeds", 72, G.AutoBuySeedsEnabled, function(s) G.AutoBuySeedsEnabled = s end)
local t3 = makeToggle(rightCol, "AutoBuy Gear", 0, G.AutoBuyGearEnabled, function(s) G.AutoBuyGearEnabled = s end)
local t4 = makeToggle(rightCol, "AutoEquip Best", 72, G.AutoEquipEnabled, function(s)
    G.AutoEquipEnabled = s
    if s then pcall(function() if EquipBestBridge then EquipBestBridge:Fire() end end) end
end)


local function refreshUIFromConfig()
    -- Toggle states
    t1.Pill.BackgroundColor3 = G.AutoPlantEnabled and ON_COLOR or OFF_COLOR
    t1.Pill.Text = G.AutoPlantEnabled and "ON" or "OFF"
    t1.Status.Text = "Status: " .. (G.AutoPlantEnabled and "Enabled" or "Disabled")

    t2.Pill.BackgroundColor3 = G.AutoBuySeedsEnabled and ON_COLOR or OFF_COLOR
    t2.Pill.Text = G.AutoBuySeedsEnabled and "ON" or "OFF"
    t2.Status.Text = "Status: " .. (G.AutoBuySeedsEnabled and "Enabled" or "Disabled")

    t3.Pill.BackgroundColor3 = G.AutoBuyGearEnabled and ON_COLOR or OFF_COLOR
    t3.Pill.Text = G.AutoBuyGearEnabled and "ON" or "OFF"
    t3.Status.Text = "Status: " .. (G.AutoBuyGearEnabled and "Enabled" or "Disabled")

    t4.Pill.BackgroundColor3 = G.AutoEquipEnabled and ON_COLOR or OFF_COLOR
    t4.Pill.Text = G.AutoEquipEnabled and "ON" or "OFF"
    t4.Status.Text = "Status: " .. (G.AutoEquipEnabled and "Enabled" or "Disabled")
end

-- เรียกหลังสร้าง UI เสร็จ
refreshUIFromConfig()


-- Settings area
local settingsFrame = new("Frame", { Parent = content, Size = UDim2.new(1,0,0,160), Position = UDim2.new(0,0,0,150), BackgroundColor3 = Color3.fromRGB(24,26,30) })
new("UICorner", { Parent = settingsFrame, CornerRadius = UDim.new(0,8) })
local settingsTitle = new("TextLabel", { Parent = settingsFrame, Size = UDim2.new(1,0,0,28), BackgroundTransparency = 1, Text = "Rarity & Timing", Font = Enum.Font.GothamBold, TextSize = 16, TextColor3 = Color3.fromRGB(215,215,220) })

local intervalLabel = new("TextLabel", { Parent = settingsFrame, Size = UDim2.new(0,220,0,24), Position = UDim2.new(0,8,0,36), BackgroundTransparency = 1, Text = "AutoEquip Interval (seconds):", Font = Enum.Font.Gotham, TextSize = 14, TextColor3 = Color3.fromRGB(190,190,200), TextXAlignment = Enum.TextXAlignment.Left })
local intervalBox = new("TextBox", { Parent = settingsFrame, Size = UDim2.new(0,80,0,26), Position = UDim2.new(0, 240, 0, 34), BackgroundColor3 = Color3.fromRGB(255,255,255), Text = tostring(G.EquipInterval), Font = Enum.Font.Gotham, TextColor3 = Color3.fromRGB(0,0,0), TextSize = 15, ClearTextOnFocus = false })
new("UICorner", { Parent = intervalBox, CornerRadius = UDim.new(0,6) })

intervalBox.FocusLost:Connect(function(enter)
    if enter then
        local v = tonumber(intervalBox.Text)
        if v and v >= 1 then
            G.EquipInterval = math.floor(v)
            intervalBox.Text = tostring(G.EquipInterval)
        else
            intervalBox.Text = tostring(G.EquipInterval)
        end
    end
end)

local function rarityButton(rarity, filterTable)
    local btn = new("TextButton", { Size = UDim2.new(0,34,0,34), BackgroundColor3 = filterTable[rarity] and Color3.fromRGB(60,179,135) or Color3.fromRGB(70,80,90), Text = rarity:sub(1,1), Font = Enum.Font.GothamBold, TextSize = 16, TextColor3 = Color3.fromRGB(245,245,245), AutoButtonColor = false })
    new("UICorner", { Parent = btn, CornerRadius = UDim.new(1,0) })
    btn.MouseButton1Click:Connect(function()
        filterTable[rarity] = not filterTable[rarity]
        btn.BackgroundColor3 = filterTable[rarity] and Color3.fromRGB(60,179,135) or Color3.fromRGB(70,80,90)
    end)
    btn.MouseEnter:Connect(function() TweenService:Create(btn, TweenInfo.new(0.12), {Size = UDim2.new(0,38,0,38)}):Play() end)
    btn.MouseLeave:Connect(function() TweenService:Create(btn, TweenInfo.new(0.12), {Size = UDim2.new(0,34,0,34)}):Play() end)
    return btn
end

local seedLabel = new("TextLabel", { Parent = settingsFrame, Size = UDim2.new(0.4,0,0,21), Position = UDim2.new(0,8,0,69), BackgroundTransparency = 1, Text = "AutoBuy Seeds Filter:", Font = Enum.Font.Gotham, TextSize = 14, TextColor3 = Color3.fromRGB(190,190,200), TextXAlignment = Enum.TextXAlignment.Left })
local seedFlow = new("Frame", { Parent = settingsFrame, Size = UDim2.new(0.6, -16, 0, 34), Position = UDim2.new(0.4, 8, 0, 64), BackgroundTransparency = 1 })
local seedLayout = new("UIListLayout", { Parent = seedFlow, FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Left, Padding = UDim.new(0,8) })

local rarities = {"Epic","Legendary","Mythic","Godly","Secret"}
for _, r in ipairs(rarities) do
    local btn = rarityButton(r, G.SeedRarityFilter)
    btn.Parent = seedFlow
end

local gearLabel = new("TextLabel", { Parent = settingsFrame, Size = UDim2.new(0.4,0,0,29), Position = UDim2.new(0,8,0,120), BackgroundTransparency = 1, Text = "AutoBuy Gear Filter:", Font = Enum.Font.Gotham, TextSize = 14, TextColor3 = Color3.fromRGB(190,190,200), TextXAlignment = Enum.TextXAlignment.Left })
local gearFlow = new("Frame", { Parent = settingsFrame, Size = UDim2.new(0.6, -16, 0, 34), Position = UDim2.new(0.4, 8, 0, 116), BackgroundTransparency = 1 })
local gearLayout = new("UIListLayout", { Parent = gearFlow, FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Left, Padding = UDim.new(0,8) })

for _, r in ipairs(rarities) do
    local btn = rarityButton(r, G.GearRarityFilter)
    btn.Parent = gearFlow
end

-- Console panel (debug)
local console = new("TextLabel", { Parent = screen, Size = UDim2.new(0.28,0,0.18,0), Position = UDim2.new(0.5, 80, 0.015, 0), BackgroundColor3 = Color3.fromRGB(10,10,12), TextColor3 = Color3.fromRGB(190,190,200), Font = Enum.Font.Code, TextSize = 12, Text = "", Visible = false })
new("UICorner", { Parent = console, CornerRadius = UDim.new(0,6) })
local function refreshConsole()
    local lines = {
        ("Plant: %s"):format(tostring(G.AutoPlantEnabled)),
        ("BuySeeds: %s"):format(tostring(G.AutoBuySeedsEnabled)),
        ("BuyGear: %s"):format(tostring(G.AutoBuyGearEnabled)),
        ("Equip: %s (interval=%ss)"):format(tostring(G.AutoEquipEnabled), tostring(G.EquipInterval)),
        ("SeedFilter: "..table.concat((function()
            local t={} for k,v in pairs(G.SeedRarityFilter) do if v then table.insert(t,k:sub(1,1)) end end return t end)(),","))
    }
    console.Text = table.concat(lines, "\n")
end
refreshConsole()

UserInputService.InputBegan:Connect(function(inp, gpe)
    if gpe then return end
    if inp.KeyCode == Enum.KeyCode.RightControl then
        console.Visible = not console.Visible
        refreshConsole()
    end
end)

spawn(function()
    while task.wait(2) do
        refreshConsole()
    end
end)

-- Dragging the card
local dragging, dragStart, startPos = false, nil, nil
titleBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = true
        dragStart = input.Position
        startPos = card.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
            end
        end)
    end
end)
UserInputService.InputChanged:Connect(function(input)
    if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
        local delta = input.Position - dragStart
        card.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
end)

-- Initial status labels
for i=1,4 do updateStatusLabel(i, "Idle", false) end
safeLog("CombinedAuto", "Merged script loaded and ready.")
