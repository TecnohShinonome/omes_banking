-- Framework Detection and Compatibility Layer
local Framework = nil
local FrameworkName = Config.Framework

if FrameworkName == 'esx' then
    Framework = exports['es_extended']:getSharedObject()
elseif FrameworkName == 'qb' then
    Framework = exports['qb-core']:GetCoreObject()
end

-- Framework compatibility functions
local function ShowNotification(message, type)
    if Config.NotificationType == 'ox' then
        exports.ox_lib:notify({
            title = 'Banking',
            description = message,
            type = type or 'info',
            duration = 5000
        })
    elseif Config.NotificationType == 'esx' then
        Framework.ShowNotification(message)
    elseif Config.NotificationType == 'qb' then
        Framework.Functions.Notify(message, type or 'primary', 5000)
    end
end

local function ShowHelpNotification(message)
    if FrameworkName == 'esx' then
        Framework.ShowHelpNotification(message)
    elseif FrameworkName == 'qb' then
        -- Try QB Core's DrawText, fallback to native help text
        if exports['qb-core'] and exports['qb-core'].DrawText then
            exports['qb-core']:DrawText(message, 'left')
        else
            -- Fallback to native GTA help text
            BeginTextCommandDisplayHelp('STRING')
            AddTextComponentSubstringPlayerName(message)
            EndTextCommandDisplayHelp(0, false, true, -1)
        end
    end
    isShowingHelpText = true
end

local function HideHelpNotification()
    if isShowingHelpText then
        if FrameworkName == 'qb' then
            -- Hide QB Core's DrawText
            if exports['qb-core'] and exports['qb-core'].HideText then
                exports['qb-core']:HideText()
            end
        end
        isShowingHelpText = false
    end
end

local function TriggerServerCallback(name, callback, ...)
    if FrameworkName == 'esx' then
        Framework.TriggerServerCallback(name, callback, ...)
    elseif FrameworkName == 'qb' then
        Framework.Functions.TriggerCallback(name, callback, ...)
    end
end

local bankerPed = nil
local bankingOpen = false
local nearbyATMs = {}
local isUsingATM = false
local isShowingHelpText = false

-- Function to create banker peds at all bank locations
function CreateBankerPeds()
    if not Config.BankerPed.enabled then return end
    
    local pedModel = GetHashKey(Config.BankerPed.model)
    
    RequestModel(pedModel)
    while not HasModelLoaded(pedModel) do
        Wait(1)
    end
    
    for i, bank in pairs(Config.BankLocations) do
        local ped = CreatePed(4, pedModel, bank.coords.x, bank.coords.y, bank.coords.z - 1.0, bank.coords.w, false, true)
        
        SetEntityHeading(ped, bank.coords.w)
        
        if Config.BankerPed.freeze then
            FreezeEntityPosition(ped, true)
        end
        
        if Config.BankerPed.invincible then
            SetEntityInvincible(ped, true)
        end
        
        if Config.BankerPed.blockEvents then
            SetBlockingOfNonTemporaryEvents(ped, true)
        end
        
        -- Set ped as mission entity to prevent despawning
        SetEntityAsMissionEntity(ped, true, true)
        
        -- Add banking scenario
        if Config.BankerPed.scenario then
            TaskStartScenarioInPlace(ped, Config.BankerPed.scenario, 0, true)
        end
        
        -- Store ped reference (if you need to track multiple peds, use a table)
        if not bankerPeds then bankerPeds = {} end
        bankerPeds[i] = ped
    end
    
    SetModelAsNoLongerNeeded(pedModel)
end

-- Function to delete banker peds
function DeleteBankerPeds()
    if bankerPeds then
        for _, ped in pairs(bankerPeds) do
            if DoesEntityExist(ped) then
                DeleteEntity(ped)
            end
        end
        bankerPeds = {}
    end
    
    -- Legacy cleanup for old single ped variable
    if bankerPed and DoesEntityExist(bankerPed) then
        DeleteEntity(bankerPed)
        bankerPed = nil
    end
end



-- Function to open banking UI
function OpenBankingUI()
    if bankingOpen then return end
    
    bankingOpen = true
    SetNuiFocus(true, true)
    
    -- Get player data, transaction history, and balance history
    TriggerServerCallback('omes_banking:getPlayerData', function(playerData)
        TriggerServerCallback('omes_banking:getTransactionHistory', function(transactions)
            TriggerServerCallback('omes_banking:getBalanceHistory', function(balanceHistory)
        SendNUIMessage({
            type = 'openBank',
            playerData = playerData,
                    bankName = Config.BankName,
                    transactions = transactions,
                    balanceHistory = balanceHistory
        })
            end)
        end)
    end)
end

-- Function to close banking UI
function CloseBankingUI()
    if not bankingOpen then return end
    
    bankingOpen = false
    isUsingATM = false
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    
    SendNUIMessage({
        type = 'closeBank'
    })
end

-- Function to handle ATM access with PIN verification
function HandleATMAccess()
    isUsingATM = true
    
    -- First check if player has a PIN set up
    TriggerServerCallback('omes_banking:getPlayerData', function(playerData)
        if not playerData.hasPin then
            ShowNotification('You need to set up a PIN at a bank first', 'error')
            isUsingATM = false
            return
        end
        
        -- Show PIN entry modal
        SetNuiFocus(true, true)
        SendNUIMessage({
            type = 'showPinEntry',
            isATM = true
        })
    end)
end

-- Create bank blips
function CreateBankBlips()
    if not Config.Blips.enabled then return end
    
    for _, bank in pairs(Config.BankLocations) do
        local blip = AddBlipForCoord(bank.coords.x, bank.coords.y, bank.coords.z)
        SetBlipSprite(blip, Config.Blips.sprite)
        SetBlipDisplay(blip, Config.Blips.display)
        SetBlipScale(blip, Config.Blips.scale)
        SetBlipColour(blip, Config.Blips.color)
        SetBlipAsShortRange(blip, Config.Blips.shortRange)
        BeginTextCommandSetBlipName("STRING")
        AddTextComponentString(Config.BankName)
        EndTextCommandSetBlipName(blip)
    end
end



-- Function to scan for nearby ATMs
function ScanForNearbyATMs()
    if not Config.ATM.enabled then return end
    
    local playerCoords = GetEntityCoords(PlayerPedId())
    nearbyATMs = {}
    
    for _, model in pairs(Config.ATM.models) do
        local atmObject = GetClosestObjectOfType(playerCoords.x, playerCoords.y, playerCoords.z, 10.0, model, false, false, false)
        
        if atmObject ~= 0 then
            local atmCoords = GetEntityCoords(atmObject)
            local distance = #(playerCoords - atmCoords)
            
            if distance <= 10.0 then
                table.insert(nearbyATMs, {
                    object = atmObject,
                    coords = atmCoords,
                    distance = distance
                })
            end
        end
    end
end

-- NUI Callbacks
RegisterNUICallback('closeBank', function(data, cb)
    CloseBankingUI()
    cb('ok')
end)

RegisterNUICallback('transfer', function(data, cb)
    TriggerServerEvent('omes_banking:transfer', data.recipient, data.amount, data.description)
    
    -- Refresh player data, transaction history, and balance history after transfer
    Citizen.Wait(500) -- Small delay to ensure transaction is processed
    TriggerServerCallback('omes_banking:getPlayerData', function(playerData)
        TriggerServerCallback('omes_banking:getTransactionHistory', function(transactions)
            TriggerServerCallback('omes_banking:getBalanceHistory', function(balanceHistory)
                SendNUIMessage({
                    type = 'updateBankingData',
                    playerData = playerData,
                    transactions = transactions,
                    balanceHistory = balanceHistory
                })
            end)
        end)
    end)
    
    cb('ok')
end)

RegisterNUICallback('deposit', function(data, cb)
    TriggerServerEvent('omes_banking:deposit', data.amount)
    
    -- Refresh player data, transaction history, and balance history after deposit
    Citizen.Wait(500) -- Small delay to ensure transaction is processed
    TriggerServerCallback('omes_banking:getPlayerData', function(playerData)
        TriggerServerCallback('omes_banking:getTransactionHistory', function(transactions)
            TriggerServerCallback('omes_banking:getBalanceHistory', function(balanceHistory)
                SendNUIMessage({
                    type = 'updateBankingData',
                    playerData = playerData,
                    transactions = transactions,
                    balanceHistory = balanceHistory
                })
            end)
        end)
    end)
    
    cb('ok')
end)

RegisterNUICallback('withdraw', function(data, cb)
    TriggerServerEvent('omes_banking:withdraw', data.amount)
    
    -- Refresh player data, transaction history, and balance history after withdrawal
    Citizen.Wait(500) -- Small delay to ensure transaction is processed
    TriggerServerCallback('omes_banking:getPlayerData', function(playerData)
        TriggerServerCallback('omes_banking:getTransactionHistory', function(transactions)
            TriggerServerCallback('omes_banking:getBalanceHistory', function(balanceHistory)
                SendNUIMessage({
                    type = 'updateBankingData',
                    playerData = playerData,
                    transactions = transactions,
                    balanceHistory = balanceHistory
                })
            end)
        end)
    end)
    
    cb('ok')
end)

RegisterNUICallback('openSavingsAccount', function(data, cb)
    TriggerServerEvent('omes_banking:openSavingsAccount')
    
    -- Refresh player data after opening savings account
    Citizen.Wait(1000) -- Longer delay to ensure transaction is processed
    TriggerServerCallback('omes_banking:getPlayerData', function(playerData)
        TriggerServerCallback('omes_banking:getTransactionHistory', function(transactions)
            TriggerServerCallback('omes_banking:getBalanceHistory', function(balanceHistory)
                SendNUIMessage({
                    type = 'updateBankingData',
                    playerData = playerData,
                    transactions = transactions,
                    balanceHistory = balanceHistory
                })
            end)
        end)
    end)
    
    cb('ok')
end)

RegisterNUICallback('depositSavings', function(data, cb)
    TriggerServerEvent('omes_banking:depositSavings', data.amount)
    
    -- Refresh player data, transaction history, and balance history after savings deposit
    Citizen.Wait(500) -- Small delay to ensure transaction is processed
    TriggerServerCallback('omes_banking:getPlayerData', function(playerData)
        TriggerServerCallback('omes_banking:getTransactionHistory', function(transactions)
            TriggerServerCallback('omes_banking:getBalanceHistory', function(balanceHistory)
                SendNUIMessage({
                    type = 'updateBankingData',
                    playerData = playerData,
                    transactions = transactions,
                    balanceHistory = balanceHistory
                })
            end)
        end)
    end)
    
    cb('ok')
end)

RegisterNUICallback('withdrawSavings', function(data, cb)
    TriggerServerEvent('omes_banking:withdrawSavings', data.amount)
    
    -- Refresh player data, transaction history, and balance history after savings withdrawal
    Citizen.Wait(500) -- Small delay to ensure transaction is processed
    TriggerServerCallback('omes_banking:getPlayerData', function(playerData)
        TriggerServerCallback('omes_banking:getTransactionHistory', function(transactions)
            TriggerServerCallback('omes_banking:getBalanceHistory', function(balanceHistory)
                SendNUIMessage({
                    type = 'updateBankingData',
                    playerData = playerData,
                    transactions = transactions,
                    balanceHistory = balanceHistory
                })
            end)
        end)
    end)
    
    cb('ok')
end)

RegisterNUICallback('transferBetweenAccounts', function(data, cb)
    TriggerServerEvent('omes_banking:transferBetweenAccounts', data.fromAccount, data.toAccount, data.amount)
    
    -- Refresh player data, transaction history, and balance history after account transfer
    Citizen.Wait(500) -- Small delay to ensure transaction is processed
    TriggerServerCallback('omes_banking:getPlayerData', function(playerData)
        TriggerServerCallback('omes_banking:getTransactionHistory', function(transactions)
            TriggerServerCallback('omes_banking:getBalanceHistory', function(balanceHistory)
                SendNUIMessage({
                    type = 'updateBankingData',
                    playerData = playerData,
                    transactions = transactions,
                    balanceHistory = balanceHistory
                })
            end)
        end)
    end)
    
    cb('ok')
end)

RegisterNUICallback('setupPin', function(data, cb)
    TriggerServerEvent('omes_banking:setupPin', data.pin)
    cb('ok')
end)

RegisterNUICallback('clearAllTransactions', function(data, cb)
    TriggerServerEvent('omes_banking:clearAllTransactions')
    cb('ok')
end)

RegisterNUICallback('getPlayerData', function(data, cb)
    -- Get fresh player data from server
    TriggerServerCallback('omes_banking:getPlayerData', function(playerData)
        cb(playerData)
    end)
end)

RegisterNUICallback('closeSavingsAccount', function(data, cb)
    TriggerServerEvent('omes_banking:closeSavingsAccount')
    cb('ok')
end)

-- Function to open ATM UI (simplified banking interface)
function OpenATMUI()
    if bankingOpen then return end
    
    bankingOpen = true
    TriggerServerCallback('omes_banking:getPlayerData', function(playerData)
        TriggerServerCallback('omes_banking:getTransactionHistory', function(transactions)
            TriggerServerCallback('omes_banking:getBalanceHistory', function(balanceHistory)
                SetNuiFocus(true, true)
                SendNUIMessage({
                    type = 'openBank',
                    playerData = playerData,
                    bankName = Config.BankName,
                    transactions = transactions,
                    balanceHistory = balanceHistory,
                    isATM = true -- Flag to indicate ATM mode
                })
            end)
        end)
    end)
end

-- Register NUI Callbacks for PIN verification
RegisterNUICallback('verifyPin', function(data, cb)
    local wasUsingATM = isUsingATM
    
    TriggerServerCallback('omes_banking:verifyPin', function(isValid)
        if isValid then
            -- PIN is correct, allow ATM access
            SendNUIMessage({
                type = 'pinVerificationSuccess'
            })
            
            -- Reset ATM state first
            isUsingATM = false
            
            -- Open appropriate UI based on what we were using
            if wasUsingATM then
                OpenATMUI()
            else
                OpenBankingUI()
            end
        else
            -- PIN is incorrect
            SendNUIMessage({
                type = 'pinVerificationFailed'
            })
        end
    end, data.pin)
    
    cb('ok')
end)

-- Register NUI Callback for closing PIN entry
RegisterNUICallback('closePinEntry', function(data, cb)
    SetNuiFocus(false, false)
    isUsingATM = false
    cb('ok')
end)

-- Handle PIN setup success from server
RegisterNetEvent('omes_banking:pinSetupSuccess')
AddEventHandler('omes_banking:pinSetupSuccess', function(data)
    SendNUIMessage({
        type = 'pinSetupSuccess',
        pin = data.pin
    })
end)

-- Handle savings account closed from server
RegisterNetEvent('omes_banking:savingsAccountClosed')
AddEventHandler('omes_banking:savingsAccountClosed', function()
    SendNUIMessage({
        type = 'savingsAccountClosed'
    })
end)

-- Create peds and blips when resource starts
Citizen.CreateThread(function()
    if Config.Banking.enableBankerPed then
        CreateBankerPeds()
    end
    CreateBankBlips()
end)

-- Cleanup when resource stops
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        DeleteBankerPeds()
        if bankingOpen then
            CloseBankingUI()
        end
    end
end)

-- Close UI on ESC key
Citizen.CreateThread(function()
    while true do
        if bankingOpen then
            if IsControlJustReleased(0, 322) then -- ESC key
                CloseBankingUI()
            end
        end
        Wait(0)
    end
end)

-- Interaction with banker peds at bank locations and ATMs
Citizen.CreateThread(function()
    local lastATMScan = 0
    
    while true do
        local sleep = 1000
        local playerPed = PlayerPedId()
        local playerCoords = GetEntityCoords(playerPed)
        local canInteract = false
        
        -- Check interaction with bank locations
        if Config.Banking.enableBankerPed then
            for _, bank in pairs(Config.BankLocations) do
                local distance = #(playerCoords - vector3(bank.coords.x, bank.coords.y, bank.coords.z))
                
                if distance < Config.Interaction.distance then
                    sleep = 0
                    canInteract = true
                    ShowHelpNotification(Config.Interaction.helpText)
                    
                    if IsControlJustReleased(0, Config.Interaction.key) then
                        OpenBankingUI()
                        break
                    end
                end
            end
        end
        
        -- Check interaction with ATMs (scan less frequently to reduce CPU usage)
        if Config.ATM.enabled and not canInteract then
            local currentTime = GetGameTimer()
            if currentTime - lastATMScan > 500 then -- Only scan every 500ms instead of every frame
                ScanForNearbyATMs()
                lastATMScan = currentTime
            end
            
            for _, atm in pairs(nearbyATMs) do
                if atm.distance <= Config.ATM.interactionDistance then
                    sleep = 0
                    canInteract = true
                    ShowHelpNotification('Press [E] to use ATM')
                    
                    if IsControlJustReleased(0, Config.Interaction.key) then
                        HandleATMAccess()
                        break
                    end
                end
            end
        end
        
        -- Hide help text if not near any interaction point
        if not canInteract then
            HideHelpNotification()
        end
        
        Wait(sleep)
    end
end)


