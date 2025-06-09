-- Framework Detection and Compatibility Layer
local Framework = nil
local FrameworkName = Config.Framework

if FrameworkName == 'esx' then
    Framework = exports['es_extended']:getSharedObject()
elseif FrameworkName == 'qb' then
    Framework = exports['qb-core']:GetCoreObject()
end

-- Framework compatibility functions
local function GetPlayer(source)
    if FrameworkName == 'esx' then
        return Framework.GetPlayerFromId(source)
    elseif FrameworkName == 'qb' then
        return Framework.Functions.GetPlayer(source)
    end
end

local function GetPlayerIdentifier(player)
    if FrameworkName == 'esx' then
        return player.identifier
    elseif FrameworkName == 'qb' then
        return player.PlayerData.citizenid
    end
end

local function GetPlayerName(player)
    if FrameworkName == 'esx' then
        return player.getName()
    elseif FrameworkName == 'qb' then
        return player.PlayerData.charinfo.firstname .. ' ' .. player.PlayerData.charinfo.lastname
    end
end

local function GetPlayerCash(player)
    if FrameworkName == 'esx' then
        return player.getMoney()
    elseif FrameworkName == 'qb' then
        return player.PlayerData.money.cash
    end
end

local function GetPlayerBank(player)
    if FrameworkName == 'esx' then
        return player.getAccount('bank').money
    elseif FrameworkName == 'qb' then
        return player.PlayerData.money.bank
    end
end

local function AddPlayerCash(player, amount)
    if FrameworkName == 'esx' then
        player.addMoney(amount)
    elseif FrameworkName == 'qb' then
        player.Functions.AddMoney('cash', amount)
    end
end

local function RemovePlayerCash(player, amount)
    if FrameworkName == 'esx' then
        player.removeMoney(amount)
    elseif FrameworkName == 'qb' then
        player.Functions.RemoveMoney('cash', amount)
    end
end

local function AddPlayerBank(player, amount)
    if FrameworkName == 'esx' then
        player.addAccountMoney('bank', amount)
    elseif FrameworkName == 'qb' then
        player.Functions.AddMoney('bank', amount)
    end
end

local function RemovePlayerBank(player, amount)
    if FrameworkName == 'esx' then
        player.removeAccountMoney('bank', amount)
    elseif FrameworkName == 'qb' then
        player.Functions.RemoveMoney('bank', amount)
    end
end

local function RegisterCallback(name, callback)
    if FrameworkName == 'esx' then
        Framework.RegisterServerCallback(name, callback)
    elseif FrameworkName == 'qb' then
        Framework.Functions.CreateCallback(name, callback)
    end
end

local function RegisterCommand(name, permission, callback, restricted, suggestion)
    if FrameworkName == 'esx' then
        Framework.RegisterCommand(name, permission, callback, restricted, suggestion)
    elseif FrameworkName == 'qb' then
        Framework.Commands.Add(name, suggestion.help, {}, restricted, callback, permission)
    end
end

local function FormatMoney(amount)
    if FrameworkName == 'esx' then
        return Framework.Math.GroupDigits(amount)
    elseif FrameworkName == 'qb' then
        -- QBCore doesn't have CommaValue in Shared, so we'll create our own formatting
        local formatted = tostring(amount)
        local k
        while true do
            formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
            if k == 0 then
                break
            end
        end
        return formatted
    end
end

-- Notification function
function SendNotification(source, message, type)
    type = type or 'info' -- Default type
    
    if Config.NotificationType == 'ox' then
        -- OX lib notification
        TriggerClientEvent('ox_lib:notify', source, {
            title = 'Banking',
            description = message,
            type = type,
            duration = 5000
        })
    elseif Config.NotificationType == 'esx' then
        -- ESX notification
        TriggerClientEvent('esx:showNotification', source, message)
    elseif Config.NotificationType == 'qb' then
        -- QB Core notification
        TriggerClientEvent('QBCore:Notify', source, message, type, 5000)
    end
end

-- Discord Webhook Logging Function
function SendDiscordLog(logType, title, description, fields, color)
    if not Config.DiscordLogging.enabled or not Config.DiscordLogging.webhook or Config.DiscordLogging.webhook == "" then
        return
    end
    
    -- Check if this log type is enabled
    if not Config.DiscordLogging.logEvents[logType] then
        return
    end
    
    local embed = {
        {
            ["title"] = title,
            ["description"] = description,
            ["type"] = "rich",
            ["color"] = color or Config.DiscordLogging.color.admin,
            ["fields"] = fields or {},
            ["footer"] = {
                ["text"] = "Banking System • " .. os.date("%Y-%m-%d %H:%M:%S"),
            },
            ["timestamp"] = os.date("!%Y-%m-%dT%H:%M:%SZ")
        }
    }
    
    local payload = {
        ["username"] = Config.DiscordLogging.botName,
        ["avatar_url"] = Config.DiscordLogging.botAvatar,
        ["embeds"] = embed
    }
    
    PerformHttpRequest(Config.DiscordLogging.webhook, function(err, text, headers) end, 'POST', json.encode(payload), {
        ['Content-Type'] = 'application/json'
    })
end

-- Get player data callback
RegisterCallback('omes_banking:getPlayerData', function(source, cb)
    local xPlayer = GetPlayer(source)
    if not xPlayer then return cb(nil) end
    
    local identifier = GetPlayerIdentifier(xPlayer)
    
    -- Get savings account data
    MySQL.Async.fetchScalar('SELECT balance FROM banking_savings WHERE identifier = @identifier AND status = "active"', {
        ['@identifier'] = identifier
    }, function(savingsBalance)
        -- Check if savings account exists
        MySQL.Async.fetchScalar('SELECT status FROM banking_savings WHERE identifier = @identifier', {
            ['@identifier'] = identifier
        }, function(savingsStatus)
            -- Get PIN data
            MySQL.Async.fetchScalar('SELECT pin FROM banking_pins WHERE identifier = @identifier', {
                ['@identifier'] = identifier
            }, function(pin)
                local playerData = {
                    name = GetPlayerName(xPlayer),
                    balance = GetPlayerBank(xPlayer),
                    accountNumber = '****-****-' .. string.sub(identifier, -4),
                    savingsBalance = savingsBalance or 0,
                    savingsAccountNumber = '****-****-' .. string.sub(identifier, -4):reverse(),
                    hasSavingsAccount = savingsStatus == 'active',
                    hasPin = pin ~= nil,
                    pin = pin
                }
                
                cb(playerData)
            end)
        end)
    end)
end)

-- Get transaction history callback
RegisterCallback('omes_banking:getTransactionHistory', function(source, cb)
    local xPlayer = GetPlayer(source)
    if not xPlayer then return cb({}) end
    
    local identifier = GetPlayerIdentifier(xPlayer)
    
    MySQL.Async.fetchAll('SELECT * FROM banking_transactions WHERE identifier = @identifier ORDER BY date DESC LIMIT @limit', {
        ['@identifier'] = identifier,
        ['@limit'] = Config.Banking.maxHistoryEntries or 50
    }, function(result)
        local transactions = {}
        for i = 1, #result do
            local transaction = result[i]
            table.insert(transactions, {
                id = transaction.id,
                type = transaction.type,
                description = transaction.description,
                amount = transaction.amount,
                date = transaction.date
            })
        end
        cb(transactions)
    end)
end)

-- Get balance history for chart
RegisterCallback('omes_banking:getBalanceHistory', function(source, cb)
    local xPlayer = GetPlayer(source)
    if not xPlayer then return cb({}) end
    
    local identifier = GetPlayerIdentifier(xPlayer)
    
    -- Get transactions from the last 7 days, ordered by date ASC for calculation
    MySQL.Async.fetchAll('SELECT * FROM banking_transactions WHERE identifier = @identifier AND date >= DATE_SUB(NOW(), INTERVAL 7 DAY) ORDER BY date ASC', {
        ['@identifier'] = identifier
    }, function(result)
        local balanceHistory = {}
        local currentBalance = GetPlayerBank(xPlayer)
        
        -- Generate the last 7 days (including today)
        local days = {}
        for i = 6, 0, -1 do
            local date = os.date('%Y-%m-%d', os.time() - (i * 24 * 60 * 60))
            table.insert(days, date)
        end
        
        -- If no transactions in last 7 days, return current balance for all days
        if #result == 0 then
            for _, date in ipairs(days) do
                table.insert(balanceHistory, {
                    date = date,
                    balance = currentBalance
                })
            end
            return cb(balanceHistory)
        end
        
        -- Calculate balance at each transaction point (working backwards from current balance)
        local tempBalance = currentBalance
        
        -- First, calculate what the balance was at the start by reversing all transactions
        for i = #result, 1, -1 do
            local transaction = result[i]
            if transaction.type == 'deposit' or transaction.type == 'transfer_in' then
                tempBalance = tempBalance - transaction.amount
            elseif transaction.type == 'withdrawal' or transaction.type == 'transfer_out' or transaction.type == 'fee' then
                tempBalance = tempBalance + transaction.amount
            end
        end
        
        local startBalance = tempBalance
        
        -- Build transaction map by date
        local transactionsByDate = {}
        local runningBalance = startBalance
        
        for i = 1, #result do
            local transaction = result[i]
            local transactionDate = string.sub(transaction.date, 1, 10) -- Get just the date part
            
            -- Apply the transaction to running balance
            if transaction.type == 'deposit' or transaction.type == 'transfer_in' then
                runningBalance = runningBalance + transaction.amount
            elseif transaction.type == 'withdrawal' or transaction.type == 'transfer_out' or transaction.type == 'fee' then
                runningBalance = runningBalance - transaction.amount
            end
            
            -- Store the end-of-day balance for this date
            transactionsByDate[transactionDate] = runningBalance
        end
        
        -- Build the final 7-day history, filling in missing days
        local lastKnownBalance = startBalance
        for _, date in ipairs(days) do
            if transactionsByDate[date] then
                lastKnownBalance = transactionsByDate[date]
            end
            
            table.insert(balanceHistory, {
                date = date,
                balance = lastKnownBalance
            })
        end
        
        -- Ensure today shows current balance
        balanceHistory[#balanceHistory].balance = currentBalance
        
        cb(balanceHistory)
    end)
end)

-- Deposit money
RegisterServerEvent('omes_banking:deposit')
AddEventHandler('omes_banking:deposit', function(amount)
    local source = source
    local xPlayer = GetPlayer(source)
    
    if not xPlayer then return end
    
    amount = tonumber(amount)
    if not amount or amount <= 0 then
        SendNotification(source, 'Invalid amount', 'error')
        return
    end
    
    if amount > Config.Banking.maxTransferAmount then
        SendNotification(source, 'Amount exceeds maximum limit', 'error')
        return
    end
    
    local cashMoney = GetPlayerCash(xPlayer)
    if cashMoney < amount then
        SendNotification(source, 'Insufficient cash', 'error')
        return
    end
    
    RemovePlayerCash(xPlayer, amount)
    AddPlayerBank(xPlayer, amount)
    
    SendNotification(source, 'Deposited $' .. FormatMoney(amount), 'success')
    
    -- Log transaction
    LogTransaction(GetPlayerIdentifier(xPlayer), 'deposit', amount, 'Cash deposit')
    
    -- Discord logging
    SendDiscordLog('deposits', '💰 Cash Deposit', 
        'A player has made a cash deposit to their bank account.',
        {
            {
                ["name"] = "Player",
                ["value"] = GetPlayerName(xPlayer) .. ' (' .. source .. ')',
                ["inline"] = true
            },
            {
                ["name"] = "Amount",
                ["value"] = '$' .. FormatMoney(amount),
                ["inline"] = true
            },
            {
                ["name"] = "New Balance",
                ["value"] = '$' .. FormatMoney(GetPlayerBank(xPlayer)),
                ["inline"] = true
            }
        },
        Config.DiscordLogging.color.deposit
    )
end)

-- Withdraw money
RegisterServerEvent('omes_banking:withdraw')
AddEventHandler('omes_banking:withdraw', function(amount)
    local source = source
    local xPlayer = GetPlayer(source)
    
    if not xPlayer then return end
    
    amount = tonumber(amount)
    if not amount or amount <= 0 then
        SendNotification(source, 'Invalid amount', 'error')
        return
    end
    
    if amount > Config.Banking.maxTransferAmount then
        SendNotification(source, 'Amount exceeds maximum limit', 'error')
        return
    end
    
    local bankMoney = GetPlayerBank(xPlayer)
    if bankMoney < amount then
        SendNotification(source, 'Insufficient funds', 'error')
        return
    end
    
    RemovePlayerBank(xPlayer, amount)
    AddPlayerCash(xPlayer, amount)
    
    SendNotification(source, 'Withdrew $' .. FormatMoney(amount), 'success')
    
    -- Log transaction
    LogTransaction(GetPlayerIdentifier(xPlayer), 'withdrawal', amount, 'Cash withdrawal')
    
    -- Discord logging
    SendDiscordLog('withdrawals', '💸 Cash Withdrawal', 
        'A player has withdrawn cash from their bank account.',
        {
            {
                ["name"] = "Player",
                ["value"] = GetPlayerName(xPlayer) .. ' (' .. source .. ')',
                ["inline"] = true
            },
            {
                ["name"] = "Amount",
                ["value"] = '$' .. FormatMoney(amount),
                ["inline"] = true
            },
            {
                ["name"] = "Remaining Balance",
                ["value"] = '$' .. FormatMoney(GetPlayerBank(xPlayer)),
                ["inline"] = true
            }
        },
        Config.DiscordLogging.color.withdrawal
    )
end)

-- Transfer money
RegisterServerEvent('omes_banking:transfer')
AddEventHandler('omes_banking:transfer', function(targetId, amount, description)
    local source = source
    local xPlayer = GetPlayer(source)
    local xTarget = GetPlayer(targetId)
    
    if not xPlayer then return end
    
    amount = tonumber(amount)
    if not amount or amount <= 0 then
        SendNotification(source, 'Invalid amount', 'error')
        return
    end
    
    if amount < Config.Banking.minTransferAmount then
        SendNotification(source, 'Amount below minimum limit', 'error')
        return
    end
    
    if amount > Config.Banking.maxTransferAmount then
        SendNotification(source, 'Amount exceeds maximum limit', 'error')
        return
    end
    
    if not xTarget then
        SendNotification(source, 'Player not found', 'error')
        return
    end
    
    if source == targetId then
        SendNotification(source, 'Cannot transfer to yourself', 'error')
        return
    end
    
    local bankMoney = GetPlayerBank(xPlayer)
    local transferFee = math.floor(amount * (Config.Banking.transferFee / 100))
    local totalAmount = amount + transferFee
    
    if bankMoney < totalAmount then
        SendNotification(source, 'Insufficient funds (including fee)', 'error')
        return
    end
    
    -- Process transfer
    RemovePlayerBank(xPlayer, totalAmount)
    AddPlayerBank(xTarget, amount)
    
    -- Notifications
    local senderMsg = 'Transferred $' .. FormatMoney(amount) .. ' to ' .. GetPlayerName(xTarget)
    if transferFee > 0 then
        senderMsg = senderMsg .. ' (Fee: $' .. FormatMoney(transferFee) .. ')'
    end
    
    SendNotification(source, senderMsg, 'success')
    SendNotification(targetId, 'Received $' .. FormatMoney(amount) .. ' from ' .. GetPlayerName(xPlayer), 'success')
    
    -- Log transactions
    LogTransaction(GetPlayerIdentifier(xPlayer), 'transfer_out', amount, 'Transfer to ' .. GetPlayerName(xTarget) .. ': ' .. (description or 'No description'))
    LogTransaction(GetPlayerIdentifier(xTarget), 'transfer_in', amount, 'Transfer from ' .. GetPlayerName(xPlayer) .. ': ' .. (description or 'No description'))
    
    -- Discord logging
    SendDiscordLog('transfers', '💳 Bank Transfer', 
        'A player has transferred money to another player.',
        {
            {
                ["name"] = "From",
                ["value"] = GetPlayerName(xPlayer) .. ' (' .. source .. ')',
                ["inline"] = true
            },
            {
                ["name"] = "To",
                ["value"] = GetPlayerName(xTarget) .. ' (' .. targetId .. ')',
                ["inline"] = true
            },
            {
                ["name"] = "Amount",
                ["value"] = '$' .. FormatMoney(amount),
                ["inline"] = true
            },
            {
                ["name"] = "Transfer Fee",
                ["value"] = '$' .. FormatMoney(transferFee),
                ["inline"] = true
            },
            {
                ["name"] = "Description",
                ["value"] = description or 'No description provided',
                ["inline"] = false
            },
            {
                ["name"] = "Sender's New Balance",
                ["value"] = '$' .. FormatMoney(GetPlayerBank(xPlayer)),
                ["inline"] = true
            },
            {
                ["name"] = "Recipient's New Balance",
                ["value"] = '$' .. FormatMoney(GetPlayerBank(xTarget)),
                ["inline"] = true
            }
        },
        Config.DiscordLogging.color.transfer
    )
    
    if transferFee > 0 then
        LogTransaction(GetPlayerIdentifier(xPlayer), 'fee', transferFee, 'Transfer fee')
    end
end)

-- Function to log transactions (you can expand this to save to database)
function LogTransaction(identifier, type, amount, description)
    if not Config.Banking.enableTransactionHistory then return end
    
    -- Save to database
    MySQL.Async.execute('INSERT INTO banking_transactions (identifier, type, amount, description, date) VALUES (@identifier, @type, @amount, @description, NOW())', {
        ['@identifier'] = identifier,
        ['@type'] = type,
        ['@amount'] = amount,
        ['@description'] = description
    }, function(rowsChanged)
        if rowsChanged > 0 then
            print(string.format('[BANKING] Transaction logged: %s - %s: $%s - %s', identifier, type, amount, description))
        end
    end)
end

-- Command to open banking (for testing or admin use)
if FrameworkName == 'esx' then
    RegisterCommand('bank', 'user', function(xPlayer, args, showError)
        TriggerClientEvent('omes_banking:openUI', xPlayer.source)
    end, false, {help = 'Open banking interface'})
elseif FrameworkName == 'qb' then
    Framework.Commands.Add('bank', 'Open banking interface', {}, false, function(source, args)
        TriggerClientEvent('omes_banking:openUI', source)
    end, 'user')
end

-- Open savings account
RegisterServerEvent('omes_banking:openSavingsAccount')
AddEventHandler('omes_banking:openSavingsAccount', function()
    local source = source
    local xPlayer = GetPlayer(source)
    
    if not xPlayer then return end
    
    local identifier = GetPlayerIdentifier(xPlayer)
    
    -- Check if player already has a savings account
    MySQL.Async.fetchScalar('SELECT status FROM banking_savings WHERE identifier = @identifier', {
        ['@identifier'] = identifier
    }, function(status)
        if status == 'active' then
            SendNotification(source, 'You already have an active savings account', 'error')
            return
        end
        
        if status == 'inactive' then
            -- Reactivate existing account
            MySQL.Async.execute('UPDATE banking_savings SET status = "active" WHERE identifier = @identifier', {
                ['@identifier'] = identifier
            }, function(rowsChanged)
                if rowsChanged > 0 then
                    SendNotification(source, 'Savings account reactivated successfully!', 'success')
                    LogTransaction(identifier, 'savings_opened', 0, 'Savings account reactivated')
                    
                    -- Discord logging
                    SendDiscordLog('accountOperations', '🏦 Savings Account Reactivated', 
                        'A player has reactivated their savings account.',
                        {
                            {
                                ["name"] = "Player",
                                ["value"] = GetPlayerName(xPlayer) .. ' (' .. source .. ')',
                                ["inline"] = true
                            },
                            {
                                ["name"] = "Action",
                                ["value"] = "Account Reactivated",
                                ["inline"] = true
                            }
                        },
                        Config.DiscordLogging.color.savings
                    )
                end
            end)
        else
            -- Create new savings account
            MySQL.Async.execute('INSERT INTO banking_savings (identifier, balance, status) VALUES (@identifier, 0, "active")', {
                ['@identifier'] = identifier
            }, function(rowsChanged)
                if rowsChanged > 0 then
                    SendNotification(source, 'Savings account opened successfully!', 'success')
                    LogTransaction(identifier, 'savings_opened', 0, 'New savings account opened')
                    
                    -- Discord logging
                    SendDiscordLog('accountOperations', '🏦 New Savings Account Opened', 
                        'A player has opened a new savings account.',
                        {
                            {
                                ["name"] = "Player",
                                ["value"] = GetPlayerName(xPlayer) .. ' (' .. source .. ')',
                                ["inline"] = true
                            },
                            {
                                ["name"] = "Action",
                                ["value"] = "New Account Created",
                                ["inline"] = true
                            }
                        },
                        Config.DiscordLogging.color.savings
                    )
                end
            end)
        end
    end)
end)

-- Deposit to savings account
RegisterServerEvent('omes_banking:depositSavings')
AddEventHandler('omes_banking:depositSavings', function(amount)
    local source = source
    local xPlayer = GetPlayer(source)
    
    if not xPlayer then return end
    
    local identifier = GetPlayerIdentifier(xPlayer)
    
    amount = tonumber(amount)
    if not amount or amount <= 0 then
        SendNotification(source, 'Invalid amount', 'error')
        return
    end
    
    if amount > Config.Banking.maxTransferAmount then
        SendNotification(source, 'Amount exceeds maximum limit', 'error')
        return
    end
    
    -- Check if savings account exists and is active
    MySQL.Async.fetchScalar('SELECT status FROM banking_savings WHERE identifier = @identifier', {
        ['@identifier'] = identifier
    }, function(status)
        if status ~= 'active' then
            SendNotification(source, 'You need to open a savings account first', 'error')
            return
        end
        
        local bankMoney = GetPlayerBank(xPlayer)
        if bankMoney < amount then
            SendNotification(source, 'Insufficient funds in checking account', 'error')
            return
        end
        
        -- Transfer from checking to savings
        RemovePlayerBank(xPlayer, amount)
        
        MySQL.Async.execute('UPDATE banking_savings SET balance = balance + @amount WHERE identifier = @identifier', {
            ['@identifier'] = identifier,
            ['@amount'] = amount
        }, function(rowsChanged)
            if rowsChanged > 0 then
                SendNotification(source, 'Deposited $' .. FormatMoney(amount) .. ' to savings account', 'success')
                LogTransaction(identifier, 'savings_deposit', amount, 'Deposit to savings account')
            end
        end)
    end)
end)

-- Withdraw from savings account
RegisterServerEvent('omes_banking:withdrawSavings')
AddEventHandler('omes_banking:withdrawSavings', function(amount)
    local source = source
    local xPlayer = GetPlayer(source)
    
    if not xPlayer then return end
    
    local identifier = GetPlayerIdentifier(xPlayer)
    
    amount = tonumber(amount)
    if not amount or amount <= 0 then
        SendNotification(source, 'Invalid amount', 'error')
        return
    end
    
    if amount > Config.Banking.maxTransferAmount then
        SendNotification(source, 'Amount exceeds maximum limit', 'error')
        return
    end
    
    -- Check savings balance
    MySQL.Async.fetchScalar('SELECT balance FROM banking_savings WHERE identifier = @identifier AND status = "active"', {
        ['@identifier'] = identifier
    }, function(savingsBalance)
        if not savingsBalance then
            SendNotification(source, 'You need to open a savings account first', 'error')
            return
        end
        
        if savingsBalance < amount then
            SendNotification(source, 'Insufficient funds in savings account', 'error')
            return
        end
        
        -- Transfer from savings to checking
        MySQL.Async.execute('UPDATE banking_savings SET balance = balance - @amount WHERE identifier = @identifier', {
            ['@identifier'] = identifier,
            ['@amount'] = amount
        }, function(rowsChanged)
            if rowsChanged > 0 then
                AddPlayerBank(xPlayer, amount)
                SendNotification(source, 'Transferred $' .. FormatMoney(amount) .. ' from savings to checking account', 'success')
                LogTransaction(identifier, 'savings_withdrawal', amount, 'Withdrawal from savings account')
            end
        end)
    end)
end)

-- Transfer between accounts (checking <-> savings)
RegisterServerEvent('omes_banking:transferBetweenAccounts')
AddEventHandler('omes_banking:transferBetweenAccounts', function(fromAccount, toAccount, amount)
    local source = source
    local xPlayer = GetPlayer(source)
    
    if not xPlayer then return end
    
    local identifier = GetPlayerIdentifier(xPlayer)
    
    amount = tonumber(amount)
    if not amount or amount <= 0 then
        SendNotification(source, 'Invalid amount', 'error')
        return
    end
    
    if amount > Config.Banking.maxTransferAmount then
        SendNotification(source, 'Amount exceeds maximum limit', 'error')
        return
    end
    
    if fromAccount == toAccount then
        SendNotification(source, 'Cannot transfer to the same account', 'error')
        return
    end
    
    -- Get current balances
    local checkingBalance = GetPlayerBank(xPlayer)
    
    MySQL.Async.fetchScalar('SELECT balance FROM banking_savings WHERE identifier = @identifier AND status = "active"', {
        ['@identifier'] = identifier
    }, function(savingsBalance)
        if not savingsBalance then
            SendNotification(source, 'You need to open a savings account first', 'error')
            return
        end
        
        if fromAccount == 'checking' then
            if checkingBalance < amount then
                SendNotification(source, 'Insufficient funds in checking account', 'error')
                return
            end
            
            -- Transfer from checking to savings
            RemovePlayerBank(xPlayer, amount)
            MySQL.Async.execute('UPDATE banking_savings SET balance = balance + @amount WHERE identifier = @identifier', {
                ['@identifier'] = identifier,
                ['@amount'] = amount
            }, function(rowsChanged)
                if rowsChanged > 0 then
                    SendNotification(source, 'Transferred $' .. FormatMoney(amount) .. ' from checking to savings', 'success')
                    LogTransaction(identifier, 'account_transfer', amount, 'Transfer from checking to savings')
                    
                    -- Discord logging
                    SendDiscordLog('savingsOperations', '💰 Account Transfer', 
                        'A player has transferred money from checking to savings.',
                        {
                            {
                                ["name"] = "Player",
                                ["value"] = GetPlayerName(xPlayer) .. ' (' .. source .. ')',
                                ["inline"] = true
                            },
                            {
                                ["name"] = "Transfer Direction",
                                ["value"] = "Checking → Savings",
                                ["inline"] = true
                            },
                            {
                                ["name"] = "Amount",
                                ["value"] = '$' .. FormatMoney(amount),
                                ["inline"] = true
                            },
                            {
                                ["name"] = "New Checking Balance",
                                ["value"] = '$' .. FormatMoney(GetPlayerBank(xPlayer)),
                                ["inline"] = true
                            }
                        },
                        Config.DiscordLogging.color.savings
                    )
                end
            end)
            
        elseif fromAccount == 'savings' then
            if savingsBalance < amount then
                SendNotification(source, 'Insufficient funds in savings account', 'error')
                return
            end
            
            -- Transfer from savings to checking
            MySQL.Async.execute('UPDATE banking_savings SET balance = balance - @amount WHERE identifier = @identifier', {
                ['@identifier'] = identifier,
                ['@amount'] = amount
            }, function(rowsChanged)
                if rowsChanged > 0 then
                    AddPlayerBank(xPlayer, amount)
                    SendNotification(source, 'Transferred $' .. FormatMoney(amount) .. ' from savings to checking', 'success')
                    LogTransaction(identifier, 'account_transfer', amount, 'Transfer from savings to checking')
                    
                    -- Discord logging
                    SendDiscordLog('savingsOperations', '💰 Account Transfer', 
                        'A player has transferred money from savings to checking.',
                        {
                            {
                                ["name"] = "Player",
                                ["value"] = GetPlayerName(xPlayer) .. ' (' .. source .. ')',
                                ["inline"] = true
                            },
                            {
                                ["name"] = "Transfer Direction",
                                ["value"] = "Savings → Checking",
                                ["inline"] = true
                            },
                            {
                                ["name"] = "Amount",
                                ["value"] = '$' .. FormatMoney(amount),
                                ["inline"] = true
                            },
                            {
                                ["name"] = "New Checking Balance",
                                ["value"] = '$' .. FormatMoney(GetPlayerBank(xPlayer)),
                                ["inline"] = true
                            }
                        },
                        Config.DiscordLogging.color.savings
                    )
                end
            end)
        end
    end)
end)

-- Close savings account
RegisterServerEvent('omes_banking:closeSavingsAccount')
AddEventHandler('omes_banking:closeSavingsAccount', function()
    local source = source
    local xPlayer = GetPlayer(source)
    
    if not xPlayer then return end
    
    local identifier = GetPlayerIdentifier(xPlayer)
    
    print(string.format('[BANKING] Player %s (%s) attempting to close savings account', GetPlayerName(xPlayer), identifier))
    
    -- Get current savings balance and status
    MySQL.Async.fetchAll('SELECT balance, status FROM banking_savings WHERE identifier = @identifier', {
        ['@identifier'] = identifier
    }, function(result)
        if not result or #result == 0 then
            print(string.format('[BANKING] No savings account found for %s', identifier))
            SendNotification(source, 'You do not have a savings account', 'error')
            return
        end
        
        local accountData = result[1]
        local savingsBalance = accountData.balance or 0
        local currentStatus = accountData.status
        
        print(string.format('[BANKING] Found savings account for %s - Balance: %s, Status: %s', identifier, savingsBalance, currentStatus))
        
        if currentStatus ~= 'active' then
            SendNotification(source, 'Your savings account is already inactive', 'error')
            return
        end
        
        -- Transfer all savings money to checking account
        if savingsBalance > 0 then
            AddPlayerBank(xPlayer, savingsBalance)
            LogTransaction(identifier, 'account_transfer', savingsBalance, 'Savings account closure - transferred to checking')
            print(string.format('[BANKING] Transferred %s from savings to checking for %s', savingsBalance, identifier))
        end
        
        -- Close the savings account by setting status to inactive and balance to 0
        MySQL.Async.execute('UPDATE banking_savings SET status = @status, balance = @balance WHERE identifier = @identifier', {
            ['@identifier'] = identifier,
            ['@status'] = 'inactive',
            ['@balance'] = 0
        }, function(rowsChanged)
            print(string.format('[BANKING] Database update result for %s: %s rows changed', identifier, rowsChanged))
            
            if rowsChanged > 0 then
                local message = 'Savings account closed successfully'
                if savingsBalance > 0 then
                    message = message .. '. $' .. FormatMoney(savingsBalance) .. ' transferred to checking account'
                end
                SendNotification(source, message, 'success')
                LogTransaction(identifier, 'savings_closed', 0, 'Savings account closed')
                
                -- Discord logging
                SendDiscordLog('accountOperations', '🏦 Savings Account Closed', 
                    'A player has closed their savings account.',
                    {
                        {
                            ["name"] = "Player",
                            ["value"] = GetPlayerName(xPlayer) .. ' (' .. source .. ')',
                            ["inline"] = true
                        },
                        {
                            ["name"] = "Transferred Amount",
                            ["value"] = savingsBalance > 0 and ('$' .. FormatMoney(savingsBalance)) or 'No funds to transfer',
                            ["inline"] = true
                        },
                        {
                            ["name"] = "New Checking Balance",
                            ["value"] = '$' .. FormatMoney(GetPlayerBank(xPlayer)),
                            ["inline"] = true
                        }
                    },
                    Config.DiscordLogging.color.admin
                )
                
                -- Refresh player data on client side
                TriggerClientEvent('omes_banking:savingsAccountClosed', source)
                
                print(string.format('[BANKING] Successfully closed savings account for %s', identifier))
            else
                print(string.format('[BANKING] Failed to update database for %s', identifier))
                SendNotification(source, 'Failed to close savings account. Please try again.', 'error')
            end
        end)
    end)
end)

-- Client event to open UI
RegisterServerEvent('omes_banking:openUI')
AddEventHandler('omes_banking:openUI', function()
    local source = source
    TriggerClientEvent('omes_banking:openUI', source)
end)

-- Setup PIN
RegisterServerEvent('omes_banking:setupPin')
AddEventHandler('omes_banking:setupPin', function(pin)
    local source = source
    local xPlayer = GetPlayer(source)
    
    if not xPlayer then return end
    
    local identifier = GetPlayerIdentifier(xPlayer)
    
    if not pin or string.len(pin) ~= 4 or not tonumber(pin) then
        SendNotification(source, 'Invalid PIN format', 'error')
        return
    end
    
    -- Check if PIN already exists
    MySQL.Async.fetchScalar('SELECT pin FROM banking_pins WHERE identifier = @identifier', {
        ['@identifier'] = identifier
    }, function(existingPin)
        if existingPin then
            -- Update existing PIN
            MySQL.Async.execute('UPDATE banking_pins SET pin = @pin WHERE identifier = @identifier', {
                ['@identifier'] = identifier,
                ['@pin'] = pin
            }, function(rowsChanged)
                if rowsChanged > 0 then
                    SendNotification(source, 'PIN updated successfully', 'success')
                    -- Send success response to NUI
                    TriggerClientEvent('omes_banking:pinSetupSuccess', source, { pin = pin })
                    
                    -- Discord logging
                    SendDiscordLog('pinOperations', '🔐 PIN Updated', 
                        'A player has updated their banking PIN.',
                        {
                            {
                                ["name"] = "Player",
                                ["value"] = GetPlayerName(xPlayer) .. ' (' .. source .. ')',
                                ["inline"] = true
                            },
                            {
                                ["name"] = "Action",
                                ["value"] = "PIN Updated",
                                ["inline"] = true
                            }
                        },
                        Config.DiscordLogging.color.admin
                    )
                end
            end)
        else
            -- Create new PIN
            MySQL.Async.execute('INSERT INTO banking_pins (identifier, pin) VALUES (@identifier, @pin)', {
                ['@identifier'] = identifier,
                ['@pin'] = pin
            }, function(rowsChanged)
                if rowsChanged > 0 then
                    SendNotification(source, 'PIN set up successfully', 'success')
                    -- Send success response to NUI
                    TriggerClientEvent('omes_banking:pinSetupSuccess', source, { pin = pin })
                    
                    -- Discord logging
                    SendDiscordLog('pinOperations', '🔐 PIN Created', 
                        'A player has created a new banking PIN.',
                        {
                            {
                                ["name"] = "Player",
                                ["value"] = GetPlayerName(xPlayer) .. ' (' .. source .. ')',
                                ["inline"] = true
                            },
                            {
                                ["name"] = "Action",
                                ["value"] = "PIN Created",
                                ["inline"] = true
                            }
                        },
                        Config.DiscordLogging.color.admin
                    )
                end
            end)
        end
    end)
end)

-- Verify PIN for ATM access
RegisterCallback('omes_banking:verifyPin', function(source, cb, enteredPin)
    local xPlayer = GetPlayer(source)
    if not xPlayer then return cb(false) end
    
    local identifier = GetPlayerIdentifier(xPlayer)
    
    MySQL.Async.fetchScalar('SELECT pin FROM banking_pins WHERE identifier = @identifier', {
        ['@identifier'] = identifier
    }, function(storedPin)
        if storedPin and storedPin == enteredPin then
            cb(true)
        else
            cb(false)
        end
    end)
end)

-- Clear all transactions
RegisterServerEvent('omes_banking:clearAllTransactions')
AddEventHandler('omes_banking:clearAllTransactions', function()
    local source = source
    local xPlayer = GetPlayer(source)
    
    if not xPlayer then return end
    
    local identifier = GetPlayerIdentifier(xPlayer)
    
    MySQL.Async.execute('DELETE FROM banking_transactions WHERE identifier = @identifier', {
        ['@identifier'] = identifier
    }, function(rowsChanged)
        if rowsChanged > 0 then
            SendNotification(source, 'All transaction history cleared (' .. rowsChanged .. ' transactions deleted)', 'success')
            
            -- Discord logging
            SendDiscordLog('historyClearing', '🗑️ Transaction History Cleared', 
                'A player has cleared their entire transaction history.',
                {
                    {
                        ["name"] = "Player",
                        ["value"] = GetPlayerName(xPlayer) .. ' (' .. source .. ')',
                        ["inline"] = true
                    },
                    {
                        ["name"] = "Transactions Deleted",
                        ["value"] = tostring(rowsChanged),
                        ["inline"] = true
                    }
                },
                Config.DiscordLogging.color.admin
            )
        else
            SendNotification(source, 'No transaction history to clear', 'info')
        end
    end)
end)
