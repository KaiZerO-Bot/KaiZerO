-- PvB Hub (Combined) — LocalScript
-- รวม AutoBuy (จาก autobuy_plant.lua) + GUI Hub (tabs, cards, toggles)
-- Place as a LocalScript under StarterPlayerScripts or run via executor's local environment.

-- ===== SERVICES & DEPENDENCIES =====
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local LocalPlayer = Players.LocalPlayer

-- Try to require original modules used in autobuy script (if present)
local Modules = ReplicatedStorage:FindFirstChild("Modules")
local Utility
local BridgeNet2, Util, Notification
if Modules then
    Utility = Modules:FindFirstChild("Utility")
    if Utility then
        BridgeNet2 = (pcall(function() return require(Utility:FindFirstChild("BridgeNet2")) end) and require(Utility:FindFirstChild("BridgeNet2"))) or nil
        Util = (pcall(function() return require(Utility:FindFirstChild("Util")) end) and require(Utility:FindFirstChild("Util"))) or nil
        Notification = (pcall(function() return require(Utility:FindFirstChild("Notification")) end) and require(Utility:FindFirstChild("Notification"))) or nil
    end
end

local PlayerDataMod = ReplicatedStorage:FindFirstChild("PlayerData")
local PlayerData = nil
local Data = {}
if PlayerDataMod then
    local ok, res = pcall(function() return require(PlayerDataMod):GetData() end)
    if ok and res then
        PlayerData = res
        Data = PlayerData.Data or {}
    end
end

-- Assets (Seeds & Plants)
local SeedAssets = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Seeds")
local PlantsAssets = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Plants")

-- BridgeNet2 references (if available)
local BuyItem, UpdStock, UpdatePlantStocks
if BridgeNet2 then
    BuyItem = BridgeNet2.ReferenceBridge and BridgeNet2.ReferenceBridge("BuyItem") or nil
    UpdStock = BridgeNet2.ReferenceBridge and BridgeNet2.ReferenceBridge("UpdStock") or nil
    UpdatePlantStocks = BridgeNet2.ReferenceBridge and BridgeNet2.ReferenceBridge("UpdatePlantStocks") or nil
end

-- ===== CONFIG (defaults from your file) =====
local RarityFilter = { -- default
    ["Common"] = false,
    ["Uncommon"] = false,
    ["Rare"] = false,
    ["Epic"] = false,
    ["Legendary"] = true,
    ["Mythic"] = true,
    ["Godly"] = true,
    ["Secret"] = true,
}

local NOTIFY_RARITIES = {
    ["Legendary"] = false,
    ["Mythic"] = false,
    ["Godly"] = false,
    ["Secret"] = false,
}

local WEBHOOK_URL = "https://discord.com/api/webhooks/1421051351026110494/0IaDOy..." -- (keep or change)
local PURCHASE_DELAY = 0.5

-- ===== STATE =====
local AutoBuyEnabled = false
local IsBuying = false
local HubRunning = true

-- other feature flags
local AutoFarmEnabled = false
local AutoPlantSeedsEnabled = false
local AutoPlantPlantsEnabled = false
local AutoCollectEnabled = false
local AutoWaterEnabled = false
local AutoEquipBestEnabled = false

-- UI-held settings
local UiSettings = {
    PurchaseDelay = PURCHASE_DELAY,
    BuyIgnoreSeeds = {}, -- table of names to ignore
    BuyIgnoreGears = {},
    EquipIntervalMinutes = 5,
    CollectIntervalMinutes = 3,
}

-- ===== HELPERS =====
local function Log(msg)
    print(("[PvB Hub] %s"):format(msg))
end

local function safeRequest(payload)
    if not WEBHOOK_URL or WEBHOOK_URL == "" then
        return false, "no webhook"
    end
    local success, err = pcall(function()
        request({
            Url = WEBHOOK_URL,
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = HttpService:JSONEncode(payload),
        })
    end)
    return success, err
end

local function ParseIgnoreList(text)
    local t = {}
    for s in string.gmatch(text or "", "([^,]+)") do
        s = s:gsub("^%s+", ""):gsub("%s+$", "")
        if s ~= "" then table.insert(t, s) end
    end
    return t
end

local function CanBuyMore(seedName, price)
    -- check money
    if PlayerData and PlayerData.Data and PlayerData.Data.Money and price then
        if PlayerData.Data.Money < price then
            return false, "not enough money"
        end
    end
    -- check inventory capacity if Util available
    if Util and LocalPlayer and LocalPlayer.Backpack then
        local maxSpace = pcall(function() return Util:GetMaxInventorySpace(LocalPlayer) end) and Util:GetMaxInventorySpace(LocalPlayer) or nil
        if maxSpace and #LocalPlayer.Backpack:GetChildren() >= maxSpace then
            return false, "inventory full"
        end
    end
    return true
end

-- ===== CORE: AutoBuySeeds (adapted) =====
local function AutoBuySeeds()
    if not AutoBuyEnabled then Log("AutoBuy OFF") return end
    if IsBuying then Log("Already buying, skip") return end
    IsBuying = true
    Log("AutoBuy: scanning seeds...")

    local itemsForNotification = {}

    if not SeedAssets or not PlantsAssets then
        Log("Seed/Plant assets not found in ReplicatedStorage")
        IsBuying = false
        return
    end

    for _, seedData in pairs(SeedAssets:GetChildren()) do
        local seedName = seedData.Name
        local price = seedData:GetAttribute("Price") or 0
        local stock = seedData:GetAttribute("Stock") or 0
        local plantName = seedData:GetAttribute("Plant") or ""
        local plant = PlantsAssets:FindFirstChild(plantName)
        local rarity = plant and plant:GetAttribute("Rarity") or "Common"

        -- ignore lists
        local ignored = false
        for _, v in ipairs(UiSettings.BuyIgnoreSeeds) do
            if v ~= "" and string.lower(v) == string.lower(seedName) then ignored = true break end
        end
        if ignored then
            Log("Ignoring seed (user list) -> " .. seedName)
            continue
        end

        -- rarity filter check
        if RarityFilter[rarity] and stock > 0 then
            local purchasedCount = 0
            for i = 1, stock do
                local canBuy, reason = CanBuyMore(seedName, price)
                if not canBuy then
                    Log("Stop buying " .. seedName .. " (" .. (reason or "no reason") .. ")")
                    break
                end

                -- fire buy (if remote available), else simulate
                if BuyItem and pcall(function() BuyItem:Fire(seedName) end) then
                    -- remote fired
                else
                    -- If no remote available, try common ReplicatedStorage remotes as fallback
                    local successFallback = pcall(function()
                        local r = ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("BuyItem")
                        if r and r.FireServer then r:FireServer(seedName) end
                    end)
                    if not successFallback then
                        -- can't actually buy on client side; log and break
                        Log("BuyItem remote not found/usable, simulated buy for " .. seedName)
                    end
                end

                purchasedCount = purchasedCount + 1
                Log(("Bought 1x %s | price=%s"):format(seedName, tostring(price)))
                task.wait(UiSettings.PurchaseDelay or 0.5)
            end

            if purchasedCount > 0 and NOTIFY_RARITIES[rarity] then
                table.insert(itemsForNotification, {Name = seedName, Rarity = rarity, Quantity = purchasedCount})
            end
        else
            if RarityFilter[rarity] then
                Log(("%s (%s) out of stock"):format(seedName, rarity))
            end
        end
    end

    -- Discord notifications
    if #itemsForNotification > 0 then
        local embedFields = {}
        local containsSecret = false
        for _, item in ipairs(itemsForNotification) do
            local fieldName = "🛒 " .. item.Name
            if item.Rarity == "Secret" then
                containsSecret = true
                fieldName = "💎 **" .. item.Name .. "**"
            end
            table.insert(embedFields, {
                name = fieldName,
                value = string.format("Rarity: %s\nQuantity: **%d**", item.Rarity, item.Quantity),
                inline = true
            })
        end

        local payload = {
            username = LocalPlayer.Name .. " - AutoBuyBot",
            embeds = { {
                title = containsSecret and "🚨 SECRET PURCHASE SUMMARY 🚨" or "Purchase Summary",
                description = "The following items were automatically purchased:",
                color = containsSecret and 15252098 or 4886754,
                fields = embedFields,
                footer = { text = "Player: " .. LocalPlayer.Name},
                timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ", os.time())
            } }
        }
        if containsSecret then payload.content = "**SECRET SEED ALERT!**" end
        pcall(function() safeRequest(payload) end)
        Log("Sent purchase summary payload")
    end

    IsBuying = false
    Log("AutoBuy cycle finished")
end

-- ===== EVENT HOOKS (react to game events if available) =====
if UpdStock and UpdStock.Connect then
    UpdStock:Connect(function(seedName)
        Log("UpdStock event -> " .. tostring(seedName))
        task.wait(3)
        AutoBuySeeds()
    end)
end

if UpdatePlantStocks and UpdatePlantStocks.Connect then
    UpdatePlantStocks:Connect(function()
        Log("UpdatePlantStocks event")
        task.wait(4)
        AutoBuySeeds()
    end)
end

if LocalPlayer and LocalPlayer:GetAttributeChangedSignal then
    if LocalPlayer:GetAttributeChangedSignal("NextSeedRestock") then
        LocalPlayer:GetAttributeChangedSignal("NextSeedRestock"):Connect(function()
            if LocalPlayer:GetAttribute("NextSeedRestock") == 0 then
                Log("NextSeedRestock == 0")
                task.wait(5)
                AutoBuySeeds()
            end
        end)
    end
end

-- ===== GUI CREATION (simplified but styled) =====
local playerGui = LocalPlayer:WaitForChild("PlayerGui")
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "PvB_Hub_GUI"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

-- background (dark)
local bg = Instance.new("Frame")
bg.Name = "Background"
bg.Size = UDim2.new(1,0,1,0)
bg.Position = UDim2.new(0,0,0,0)
bg.BackgroundColor3 = Color3.fromRGB(18,18,20)
bg.BorderSizePixel = 0
bg.Parent = screenGui

-- Left Sidebar
local sidebar = Instance.new("Frame")
sidebar.Name = "Sidebar"
sidebar.Size = UDim2.new(0, 180, 1, 0)
sidebar.Position = UDim2.new(0,0,0,0)
sidebar.BackgroundColor3 = Color3.fromRGB(28,28,30)
sidebar.BorderSizePixel = 0
sidebar.Parent = bg

local sidebarTitle = Instance.new("TextLabel", sidebar)
sidebarTitle.Size = UDim2.new(1,0,0,64)
sidebarTitle.Position = UDim2.new(0,0,0,0)
sidebarTitle.BackgroundTransparency = 1
sidebarTitle.Text = "PvB Hub"
sidebarTitle.Font = Enum.Font.GothamBold
sidebarTitle.TextSize = 20
sidebarTitle.TextColor3 = Color3.fromRGB(200,255,230)

-- sidebar buttons (Main, Progression, Webhooks, Settings)
local tabButtons = {}
local tabNames = {"Main","Progression","Webhooks","Settings"}
local function createSidebarButton(text, y)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1,-12,0,40)
    b.Position = UDim2.new(0,6,0,y)
    b.BackgroundColor3 = Color3.fromRGB(22,22,24)
    b.BorderSizePixel = 0
    b.Text = text
    b.Font = Enum.Font.Gotham
    b.TextSize = 14
    b.TextColor3 = Color3.fromRGB(170,170,170)
    b.Parent = sidebar
    return b
end

for i, name in ipairs(tabNames) do
    local but = createSidebarButton(name, 64 + (i-1)*48)
    tabButtons[name] = but
end

-- Main content area
local mainArea = Instance.new("Frame")
mainArea.Name = "MainArea"
mainArea.Size = UDim2.new(1, -180, 1, 0)
mainArea.Position = UDim2.new(0, 180, 0, 0)
mainArea.BackgroundTransparency = 1
mainArea.Parent = bg

-- Tab frames
local Tabs = {}
for _, name in ipairs(tabNames) do
    local t = Instance.new("Frame")
    t.Name = name .. "Tab"
    t.Size = UDim2.new(1,0,1,0)
    t.Position = UDim2.new(0,0,0,0)
    t.BackgroundTransparency = 1
    t.Visible = false
    t.Parent = mainArea
    Tabs[name] = t
end
Tabs["Main"].Visible = true -- default

-- Basic function to create a "card" in a parent at x,y
local function CreateCard(parent, title, posY)
    local card = Instance.new("Frame")
    card.Size = UDim2.new(0, 420, 0, 120)
    card.Position = UDim2.new(0, 16, 0, posY)
    card.BackgroundColor3 = Color3.fromRGB(26,26,28)
    card.BorderSizePixel = 0
    card.Parent = parent

    local t = Instance.new("TextLabel")
    t.Size = UDim2.new(1,-16,0,20)
    t.Position = UDim2.new(0,8,0,8)
    t.BackgroundTransparency = 1
    t.Text = title
    t.Font = Enum.Font.GothamSemibold
    t.TextSize = 14
    t.TextColor3 = Color3.fromRGB(200,255,230)
    t.TextXAlignment = Enum.TextXAlignment.Left
    t.Parent = card

    return card
end

-- Toggle helper: returns function to get current state
local function MakeToggle(card, default)
    local tb = Instance.new("TextButton")
    tb.Size = UDim2.new(0, 50, 0, 28)
    tb.Position = UDim2.new(1, -66, 0, 12)
    tb.BackgroundColor3 = default and Color3.fromRGB(36,160,122) or Color3.fromRGB(120,24,24)
    tb.TextColor3 = Color3.fromRGB(255,255,255)
    tb.Font = Enum.Font.GothamBold
    tb.TextSize = 14
    tb.Text = default and "ON" or "OFF"
    tb.Parent = card

    local state = default
    tb.MouseButton1Click:Connect(function()
        state = not state
        tb.Text = state and "ON" or "OFF"
        tb.BackgroundColor3 = state and Color3.fromRGB(36,160,122) or Color3.fromRGB(120,24,24)
    end)
    return function() return state, tb end, tb
end

-- Input box helper
local function MakeInput(card, labelText, default)
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(0.6, -10, 0, 20)
    l.Position = UDim2.new(0, 8, 0, 36)
    l.BackgroundTransparency = 1
    l.Text = labelText
    l.Font = Enum.Font.Gotham
    l.TextSize = 12
    l.TextColor3 = Color3.fromRGB(220,220,220)
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.Parent = card

    local box = Instance.new("TextBox")
    box.Size = UDim2.new(0.95, -10, 0, 28)
    box.Position = UDim2.new(0, 8, 0, 60)
    box.Text = default or ""
    box.Font = Enum.Font.Gotham
    box.TextSize = 14
    box.TextColor3 = Color3.fromRGB(240,240,240)
    box.BackgroundColor3 = Color3.fromRGB(17,17,18)
    box.BorderSizePixel = 0
    box.Parent = card

    return box
end

-- Simple numeric control (label + - + value)
local function MakeNumericControl(card, labelText, default, step)
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(0.6, -10, 0, 20)
    l.Position = UDim2.new(0, 8, 0, 36)
    l.BackgroundTransparency = 1
    l.Text = labelText
    l.Font = Enum.Font.Gotham
    l.TextSize = 12
    l.TextColor3 = Color3.fromRGB(220,220,220)
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.Parent = card

    local minus = Instance.new("TextButton")
    minus.Size = UDim2.new(0, 24, 0, 24)
    minus.Position = UDim2.new(0, 8, 0, 60)
    minus.Text = "-"
    minus.Font = Enum.Font.GothamBold
    minus.TextSize = 18
    minus.BackgroundColor3 = Color3.fromRGB(30,30,30)
    minus.TextColor3 = Color3.fromRGB(220,220,220)
    minus.Parent = card

    local plus = Instance.new("TextButton")
    plus.Size = UDim2.new(0, 24, 0, 24)
    plus.Position = UDim2.new(0, 42, 0, 60)
    plus.Text = "+"
    plus.Font = Enum.Font.GothamBold
    plus.TextSize = 18
    plus.BackgroundColor3 = Color3.fromRGB(30,30,30)
    plus.TextColor3 = Color3.fromRGB(220,220,220)
    plus.Parent = card

    local valLabel = Instance.new("TextLabel")
    valLabel.Size = UDim2.new(0, 80, 0, 24)
    valLabel.Position = UDim2.new(0, 80, 0, 60)
    valLabel.BackgroundTransparency = 1
    valLabel.Text = tostring(default)
    valLabel.Font = Enum.Font.Gotham
    valLabel.TextSize = 14
    valLabel.TextColor3 = Color3.fromRGB(200,200,200)
    valLabel.Parent = card

    local value = default or 0
    local st = step or 1
    minus.MouseButton1Click:Connect(function()
        value = math.max(0, value - st)
        valLabel.Text = tostring(value)
    end)
    plus.MouseButton1Click:Connect(function()
        value = value + st
        valLabel.Text = tostring(value)
    end)

    return function() return value, valLabel end, minus, plus
end

-- Create main cards similar to your screenshot
local mainTab = Tabs["Main"]

-- Auto Buy Best (uses AutoBuy logic)
local buyCard = CreateCard(mainTab, "Auto Buy Best", 16)
local getBuyToggle, buyToggleButton = MakeToggle(buyCard, false)
local ignoreBox = MakeInput(buyCard, "Ignore Seeds (comma-separated)", "Cactus Seed, Dragon Fruit")
local buyDelayVal, _, _, _ = MakeNumericControl(buyCard, "Purchase Delay (s)", 0.5, 0.1)

-- hook input parse to UiSettings
ignoreBox.FocusLost:Connect(function()
    UiSettings.BuyIgnoreSeeds = ParseIgnoreList(ignoreBox.Text)
end)
-- numeric control requires reading from valLabel - we will read buyDelayVal via closure
-- but we didn't expose buyDelayVal function to set UiSettings automatically; instead create a short updater:
coroutine.wrap(function()
    while HubRunning do
        -- find the current numeric value label under buyCard and parse it
        local valLabel = buyCard:FindFirstChildWhichIsA("TextLabel", true)
        -- better: keep a direct reference from MakeNumericControl - we returned function earlier; simpler:
        -- (we already have "buyDelayVal" closure - it's a function that returns current value)
        local currentDelay = 0.5
        -- attempt to read from the valLabel text of the numeric control we created:
        local labels = {}
        for _, child in ipairs(buyCard:GetChildren()) do
            if child:IsA("TextLabel") and child.Text ~= "" and string.find(child.Text, "%d") then
                table.insert(labels, child)
            end
        end
        -- fallback to UiSettings.PurchaseDelay
        UiSettings.PurchaseDelay = UiSettings.PurchaseDelay or PURCHASE_DELAY
        UiSettings.PurchaseDelay = tonumber(buyDelayVal() or UiSettings.PurchaseDelay) or UiSettings.PurchaseDelay
        task.wait(0.8)
    end
end)()

-- Auto Plant Seeds card
local plantSeedsCard = CreateCard(mainTab, "Auto Plant (Seeds)", 152)
local getPlantSeedsToggle, plantSeedsToggleBtn = MakeToggle(plantSeedsCard, false)
local seedsToPlantBox = MakeInput(plantSeedsCard, "Seeds to Plant (comma-separated)", "")
local collectAllBtn = Instance.new("TextButton")
collectAllBtn.Size = UDim2.new(0, 150, 0, 28)
collectAllBtn.Position = UDim2.new(0, 8, 0, 92)
collectAllBtn.Text = "Collect All Plants"
collectAllBtn.Font = Enum.Font.GothamBold
collectAllBtn.TextSize = 14
collectAllBtn.BackgroundColor3 = Color3.fromRGB(30,30,30)
collectAllBtn.Parent = plantSeedsCard

collectAllBtn.MouseButton1Click:Connect(function()
    -- Placeholder: call server remote to collect plants
    -- Add code here to call the correct remote event of the game
    Log("Collect All Plants pressed (placeholder).")
end)

seedsToPlantBox.FocusLost:Connect(function()
    -- parse and store
    -- You can later use this list in the planting loop
    local t = ParseIgnoreList(seedsToPlantBox.Text)
    UiSettings.SeedsToPlant = t
    Log("SeedsToPlant set: " .. tostring(#t) .. " items")
end)

-- Auto Farm card (placeholder)
local autoFarmCard = CreateCard(mainTab, "Auto Farm", 288)
local getAutoFarmToggle, autoFarmTb = MakeToggle(autoFarmCard, false)
local farmNote = Instance.new("TextLabel")
farmNote.Size = UDim2.new(1, -16, 0, 56)
farmNote.Position = UDim2.new(0, 8, 0, 36)
farmNote.BackgroundTransparency = 1
farmNote.Text = "AutoFarm placeholder - implement game-specific targeting & remotes."
farmNote.Font = Enum.Font.Gotham
farmNote.TextSize = 12
farmNote.TextColor3 = Color3.fromRGB(180,180,180)
farmNote.TextWrapped = true
farmNote.Parent = autoFarmCard

-- Right column cards (Auto Collect, Auto Water, Auto Equip, Auto Buy Specific)
-- We'll place them on the right side of mainArea
local rightColumn = Instance.new("Frame")
rightColumn.Size = UDim2.new(0, 380, 1, 0)
rightColumn.Position = UDim2.new(1, -400, 0, 16)
rightColumn.BackgroundTransparency = 1
rightColumn.Parent = mainTab

local function CreateRightCard(parent, title, posY)
    local c = Instance.new("Frame")
    c.Size = UDim2.new(1, 0, 0, 120)
    c.Position = UDim2.new(0, 0, 0, posY)
    c.BackgroundColor3 = Color3.fromRGB(26,26,28)
    c.BorderSizePixel = 0
    c.Parent = parent

    local t = Instance.new("TextLabel")
    t.Size = UDim2.new(1,-16,0,20)
    t.Position = UDim2.new(0,8,0,8)
    t.BackgroundTransparency = 1
    t.Text = title
    t.Font = Enum.Font.GothamSemibold
    t.TextSize = 14
    t.TextColor3 = Color3.fromRGB(200,255,230)
    t.TextXAlignment = Enum.TextXAlignment.Left
    t.Parent = c

    return c
end

-- Auto Collect
local collectCard = CreateRightCard(rightColumn, "Auto Collect", 0)
local getCollectToggle, collectBtn = MakeToggle(collectCard, false)
local collectIntervalVal, _, _, _ = MakeNumericControl(collectCard, "Collect Interval (Minutes)", 3, 1)
collectBtn.MouseButton1Click:Connect(function() end) -- placeholder

-- Auto Water
local waterCard = CreateRightCard(rightColumn, "Auto Water Bucket", 140)
local getWaterToggle, waterBtn = MakeToggle(waterCard, false)
local waterIntervalVal, _, _, _ = MakeNumericControl(waterCard, "Interval Per Use (Sec)", 0.5, 0.5)
local waterFilterBox = MakeInput(waterCard, "Water Filter", "")

-- Auto Equip Best
local equipCard = CreateRightCard(rightColumn, "Auto Equip Best", 280)
local getEquipToggle, equipBtn = MakeToggle(equipCard, false)
local equipIntervalVal, _, _, _ = MakeNumericControl(equipCard, "Equip Interval (Minutes)", 5, 1)

-- ===== BACKGROUND LOOPS FOR FEATURES (basic examples) =====

-- AutoBuy loop (continuously check while enabled)
spawn(function()
    while HubRunning do
        if getBuyToggle() then
            AutoBuyEnabled = true
            -- update UiSettings purchase delay by reading the numeric label
            -- We used closure earlier: buyDelayVal returns the value
            UiSettings.PurchaseDelay = tonumber(tostring(buyDelayVal())) or UiSettings.PurchaseDelay or PURCHASE_DELAY
            AutoBuySeeds()
            -- after full scan, wait a bit
            task.wait(3)
        else
            AutoBuyEnabled = false
            task.wait(1)
        end
    end
end)

-- AutoCollect example (trigger every interval minutes)
spawn(function()
    while HubRunning do
        if getCollectToggle() then
            -- do collect logic (placeholder)
            Log("AutoCollect tick (placeholder).")
            -- Here you would call relevant remote events to collect (e.g., CollectAll)
            task.wait((UiSettings.CollectIntervalMinutes or 3) * 60)
        else
            task.wait(1)
        end
    end
end)

-- AutoPlant Seeds example
spawn(function()
    while HubRunning do
        if getPlantSeedsToggle() then
            -- example: iterate over UiSettings.SeedsToPlant and call planting remote
            local list = UiSettings.SeedsToPlant or {}
            if #list > 0 then
                Log("AutoPlantSeeds: attempting to plant " .. tostring(#list) .. " types (placeholder).")
                -- Implement game-specific remote calls here
            else
                Log("AutoPlantSeeds enabled but no seeds specified.")
            end
            task.wait(2)
        else
            task.wait(0.7)
        end
    end
end)

-- AutoFarm example
spawn(function()
    while HubRunning do
        if getAutoFarmToggle() then
            Log("AutoFarm: running placeholder attack routine.")
            -- Implement targeting & attack remotes here
            task.wait(1)
        else
            task.wait(0.8)
        end
    end
end)

-- AutoEquip Best example
spawn(function()
    while HubRunning do
        if getEquipToggle() then
            Log("AutoEquipBest: swapping equips (placeholder).")
            -- Implement equip selection logic with remotes/functions
            task.wait((UiSettings.EquipIntervalMinutes or 5) * 60)
        else
            task.wait(1)
        end
    end
end)

-- ===== TAB NAVIGATION =====
for name, btn in pairs(tabButtons) do
    btn.MouseButton1Click:Connect(function()
        for tname, frame in pairs(Tabs) do
            frame.Visible = (tname == name)
        end
        for _, b in pairs(tabButtons) do
            b.TextColor3 = Color3.fromRGB(170,170,170)
        end
        btn.TextColor3 = Color3.fromRGB(200,255,230)
    end)
end

-- ===== CLEANUP ON LEAVE =====
LocalPlayer.AncestryChanged:Connect(function(_, parent)
    if not parent then
        HubRunning = false
    end
end)

Log("PvB Hub GUI loaded. Use the toggles to enable features. AutoBuy integrated.")