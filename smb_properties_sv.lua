local QBCore = exports['qb-core']:GetCoreObject()

local DoorStates = {}
local DEBUG_MODE = true  

local function debugPrint(message)
    if DEBUG_MODE then
        print("[DEBUG]: " .. message)
    end
end

local function InitializeDoorStates()
    for propertyName, property in pairs(Config.Properties) do
        if property.doors then
            for _, door in ipairs(property.doors) do
                DoorStates[door.doorHash] = door.locked or false
            end
        elseif property.type == "motel" then
            for _, unit in pairs(property.units) do
                local door = unit.door
                DoorStates[door.doorHash] = door.locked or false
            end
        end
    end
end

local function IsTenant(src, callback)
    local player = QBCore.Functions.GetPlayer(src)

    if not player then
        debugPrint("Player not found for src: " .. src)
        callback(false)
        return
    end

    local citizenID = player.PlayerData and player.PlayerData.citizenid

    if not citizenID then
        debugPrint("CitizenID not found for player src: " .. src)
        callback(false)
        return
    end

    local query = "SELECT * FROM smb_properties_tenants WHERE citizenID = @citizenID"
    
    MySQL.Async.fetchAll(query, { ['@citizenID'] = citizenID }, function(result)
        if result and #result > 0 then
            -- print("[DEBUG] Player with CitizenID: " .. citizenID .. " is a tenant.")
            callback(true)
        else
            -- print("[DEBUG] Player with CitizenID: " .. citizenID .. " is NOT a tenant.")
            callback(false)
        end
    end)
end

local function GetLatestBalance(tenantID, callback)
    local query = [[
        SELECT balance 
        FROM smb_properties_ledger 
        WHERE tenantID = @tenantID 
        AND transactionType = 'balance_update'
        ORDER BY transactionDate DESC 
        LIMIT 1
    ]]
    
    MySQL.Async.fetchScalar(query, { ['@tenantID'] = tenantID }, function(balance)

        print(balance)
        if balance then
            callback(tonumber(balance))
        else
            callback(0)
        end
    end)
end


local function CalculateAndChargeRent(src)
    local player = QBCore.Functions.GetPlayer(src)
    local citizenID = player.PlayerData.citizenid
    local bankBalance = player.PlayerData.money["bank"]
    -- local cashBalance = player.PlayerData.money["cash"]

    debugPrint("Processing rent for CitizenID: " .. citizenID)
    debugPrint("Current Bank Balance: " .. bankBalance)
    -- debugPrint("Current Cash Balance: " .. cashBalance)

    local query = [[
        SELECT 
            smb_properties_tenants.*, 
            smb_properties_units.*, 
            smb_properties.ownerCitizenID 
        FROM 
            smb_properties_tenants 
        INNER JOIN 
            smb_properties_units 
        ON 
            smb_properties_tenants.unitID = smb_properties_units.unitID 
        AND 
            smb_properties_tenants.propertyName = smb_properties_units.propertyName
        INNER JOIN 
            smb_properties 
        ON 
            smb_properties_tenants.propertyName = smb_properties.propertyName 
        WHERE 
            smb_properties_tenants.citizenID = @citizenID 
        AND 
            smb_properties_tenants.status = 'active'
    
    ]]

    MySQL.Async.fetchAll(query, { ['@citizenID'] = citizenID }, function(results)
        debugPrint("Raw SQL Results: " .. json.encode(results))
        if results and #results > 0 then
            debugPrint("Found " .. #results .. " active tenants for CitizenID: " .. citizenID)

            for _, result in ipairs(results) do  
                local rentAmount = result.rentCost 
                local tenantID = result.tenantID
            
                debugPrint("Processing TenantID: " .. tenantID .. " with Rent Amount: " .. rentAmount)
                GetLatestBalance(tenantID, function(balance)
                    
                    debugPrint("$" .. balance .. " balance for Citizen " .. citizenID)
                    
                    
                    if bankBalance < rentAmount then
                        debugPrint("$" .. bankBalance .. " Bank balance is not enough for rent. Lodging to balance account." )
                        -- TriggerClientEvent('QBCore:Notify', source, "Not enough money in the bank to pay $" .. rentAmount .. " rent!")
                        local latestBalance = balance + rentAmount  
                        local ledgerQuery = "INSERT INTO smb_properties_ledger (tenantID, description, amount, balance, transactionType) VALUES (@tenantID, 'Rent Payment', @rentAmount, @latestBalance, 'balance_update')"
                        MySQL.Async.execute(ledgerQuery, { ['@tenantID'] = tenantID, ['@rentAmount'] = rentAmount, ['@latestBalance'] = latestBalance })
                            
                        if latestBalance >= 10000 then
                        local evictionQuery = "UPDATE smb_properties_tenants SET status = 'evicted' WHERE tenantID = @tenantID"
                        MySQL.Async.execute(evictionQuery, { ['@tenantID'] = tenantID })
                            debugPrint("TenantID: " .. tenantID .. " evicted due to high debt!")
                        end
                    
                    else
                        -- TriggerClientEvent('QBCore:Notify', source, "$" .. rentAmount .. " rent paid", "success")
                        debugPrint("Sufficient funds, rent paid: $" .. rentAmount .. " Remaining $" .. balance .. " needs to be paid.")
                        player.Functions.RemoveMoney('bank', rentAmount)
                    
                        -- local ledgerQuery = "INSERT INTO smb_properties_ledger (tenantID, description, amount, balance, transactionType) VALUES (@tenantID, 'Rent Payment', @rentAmount, 0, 'auto_debit')"
                        -- MySQL.Async.execute(ledgerQuery, { ['@tenantID'] = tenantID, ['@rentAmount'] = -rentAmount })
                        debugPrint("Rent payment logged for TenantID: " .. tenantID)
                    end
                end)
            end
               
        else
            debugPrint("No active tenants found for CitizenID: " .. citizenID)
        end
    end)
end

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(1800000) --  30 minutes

        -- Citizen.Wait(60000)

        for _, src in ipairs(GetPlayers()) do
            IsTenant(tonumber(src), function(isPlayerTenant)
                if isPlayerTenant then
                    CalculateAndChargeRent(tonumber(src))
                end
            end)
        end
    end
end)

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        InitializeDoorStates()
    end
end)

RegisterServerEvent('smb_properties:server:UpdateDoorState')
AddEventHandler('smb_properties:server:UpdateDoorState', function(propertyName, doorHash, state)
    local src = source
    DoorStates[doorHash] = state
    TriggerClientEvent('smb_properties:client:SetDoorState', -1, propertyName, doorHash, state)
end)

AddEventHandler('playerConnecting', function(playerName, setKickReason, deferrals)
    local src = source
    TriggerClientEvent('smb_properties:client:InitializeDoorStates', src, DoorStates)
end)

RegisterServerEvent('smb_properties:server:VaultChange')
AddEventHandler('smb_properties:server:VaultChange', function(amount, action, tenantID, dm)

  
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    local setDM 

    if tonumber(amount) < 0 then 
        TriggerClientEvent('QBCore:Notify', source, "Amount cannot be negative!", "error")
        return
    end

    if action == "withdraw" and tonumber(dm) >= tonumber(amount) then
        setDMDB = dm - amount
    elseif action == "deposit" and Player.Functions.GetMoney('dirtymoney') >= tonumber(amount) then
        setDMDB = dm + amount
    else
        TriggerClientEvent('QBCore:Notify', source, "Not enough DM!", "error")
        return
    end   

    local query = "UPDATE `smb_properties_tenants` set dm = @dm WHERE tenantID=@tenantID"
    MySQL.Async.execute(query, { 
        ['@dm'] = setDMDB, 
        ['@tenantID'] = tenantID
    }, function(result)
        
        if result then
            
            if action == "withdraw" then
                Player.Functions.AddMoney("dirtymoney", amount, "smb-properties-vault-withdraw")
                TriggerClientEvent('QBCore:Notify', source, "Withdraw success!", "success")
            elseif action == "deposit" then
                Player.Functions.RemoveMoney("dirtymoney", amount, "smb-properties-vault-deposit")
                TriggerClientEvent('QBCore:Notify', source, "Deposit success!", "success")
            end  
            TriggerClientEvent('QBCore:Notify', source, "Vault updated!", "success")
        else
            TriggerClientEvent('QBCore:Notify', source, "Vault error!", "error")
        end
    end)
  

end)


QBCore.Functions.CreateCallback('smb_properties:server:GetAccessData', function(source, cb, propertyName, unitID)
    local src = source
    local citizenID = QBCore.Functions.GetPlayer(src).PlayerData.citizenid


    local query = "SELECT ownerCitizenID FROM smb_properties WHERE propertyName = @propertyName"
    MySQL.Async.fetchAll(query, { ['@propertyName'] = propertyName }, function(results)
        if results[1] and results[1].ownerCitizenID == citizenID then
            cb(true)
            return
        end

        query = [[
            SELECT COUNT(*) as count 
            FROM smb_properties_tenants 
            WHERE unitID = @unitID AND propertyName = @propertyName AND citizenID = @citizenID AND status = 'active'
        ]]
        MySQL.Async.fetchAll(query, { 
            ['@unitID'] = unitID, 
            ['@propertyName'] = propertyName, 
            ['@citizenID'] = citizenID 
        }, function(tenants)
            if tenants[1] and tenants[1].count > 0 then
                cb(true)
            else
                cb(false)
            end
        end)
    end)
end)
 
QBCore.Functions.CreateCallback('smb_properties:server:IsTenantOfUnit', function(source, cb, propertyName, unitID)
    local citizenID = QBCore.Functions.GetPlayer(source).PlayerData.citizenid
    local query = "SELECT ownerCitizenID FROM smb_properties WHERE propertyName = @propertyName"

    MySQL.Async.fetchAll(query, { ['@propertyName'] = propertyName }, function(results)
        if results[1] and results[1].ownerCitizenID == citizenID then
            cb(results[1])
            return
        end

        local newquery = "SELECT * FROM smb_properties_tenants WHERE unitID = @unitID AND propertyName = @propertyName AND citizenID = @citizenID AND status = 'active'"

        MySQL.Async.fetchAll(newquery, { 
            ['@unitID'] = unitID, 
            ['@propertyName'] = propertyName, 
            ['@citizenID'] = citizenID 
        }, function(results)
            if results[1] then
                cb(results[1])
            end
        end)
    end)
end)

QBCore.Functions.CreateCallback('smb_properties:server:GetPlayerRole', function(source, cb, propertyName)
    local src = source
    local citizenID = QBCore.Functions.GetPlayer(src).PlayerData.citizenid

    local query = [[
        SELECT ownerCitizenID 
        FROM smb_properties 
        WHERE propertyName = @propertyName
    ]]
    
    MySQL.Async.fetchAll(query, { ['@propertyName'] = propertyName }, function(results)
        if results[1] and results[1].ownerCitizenID == citizenID then
            cb("owner")
        else
            query = [[
                SELECT COUNT(*) as count 
                FROM 
                    smb_properties_tenants 
                WHERE unitID IN (
                    SELECT unitID 
                    FROM smb_properties_units 
                    WHERE propertyName = @propertyName
                ) 
                AND citizenID = @citizenID
            ]]
            
            MySQL.Async.fetchAll(query, { ['@propertyName'] = propertyName, ['@citizenID'] = citizenID }, function(tenants)
                if tenants and #tenants > 0 and tenants[1].count > 0 then
                    cb("tenant")
                else
                    cb("none")
                end
            end)
        end
    end)
end)

QBCore.Functions.CreateCallback('smb_properties:server:CheckOwnership', function(source, cb, propertyName)
    local src = source
    local player = QBCore.Functions.GetPlayer(src)
    local citizenID = player.PlayerData.citizenid

    local query = [[
        SELECT 
            ownerCitizenID 
        FROM 
            smb_properties 
        WHERE 
            propertyName = @propertyName
    ]]

    MySQL.Async.fetchAll(query, { ['@propertyName'] = propertyName }, function(results)
        if results and #results > 0 and results[1].ownerCitizenID == citizenID then
            cb(true)
        else
            cb(false)
        end
    end)
end)

function dump(o)
    if type(o) == 'table' then
        local s = '{ '
        for k,v in pairs(o) do
            if type(k) ~= 'number' then k = '"'..k..'"' end
            s = s .. '['..k..'] = ' .. dump(v) .. ','
        end
        return s .. '} '
    else
        return tostring(o)
    end
end

QBCore.Functions.CreateCallback('smb_properties:server:CheckStashAccess', function(source, cb, property, unitID)
    local src = source
    local citizenID = QBCore.Functions.GetPlayer(src).PlayerData.citizenid
    local query = "SELECT stash_id FROM `smb_properties_tenants` WHERE citizenID = @citizenID AND `status` = 'active' AND propertyName = @propertyName AND unitID = @unitID"
   
    MySQL.Async.fetchAll(query, 
    {
    ['@citizenID'] = citizenID, 
    ['@propertyName'] = property,
    ['@unitID'] = unitID
    }, 
    function(result)
        -- print(dump(result[1].stash_id))
        if result then
            cb(result[1].stash_id)
        end
        cb(nil)
    end)
end)

QBCore.Functions.CreateCallback('smb_properties:server:AddTenant', function(source, cb, unitId, unitData, playerId)
    local player = QBCore.Functions.GetPlayer(tonumber(playerId))
    local citizenID = player.PlayerData.citizenid
    local citizenName = player.PlayerData.charinfo.firstname .. " " .. player.PlayerData.charinfo.lastname
    
    local query = "SELECT COUNT(*) as count FROM smb_properties_tenants WHERE unitID = @unitID"
    
    MySQL.Async.fetchAll(query, { ['@unitID'] = unitId }, function(tenants)
        if tenants[1] and tenants[1].count < 3 then
            if unitData and unitData.stash and unitData.stash.ids then
                local stash_id = unitData.stash.ids[tenants[1].count + 1]
                
                query = "INSERT INTO smb_properties_tenants (unitID, citizenID, citizenName, stash_id) VALUES (@unitID, @citizenID, @citizenName, @stash_id)"
                MySQL.Async.execute(query, {
                    ['@unitID'] = unitId,
                    ['@citizenID'] = citizenID,
                    ['@citizenName'] = citizenName,
                    ['@stash_id'] = stash_id
                }, function(inserted)
                    if inserted > 0 then
                        cb(true)
                    else
                        cb(false)
                    end
                end)
            else
                cb(false, "Invalid unit data provided.")
            end
        else
            cb(false, "This unit already has the maximum number of tenants.")
        end
    end)
end)

QBCore.Functions.CreateCallback('smb_properties:server:EvictTenant', function(source, cb, propertyName, unitID, tenantID)
    local src = source
    local player = QBCore.Functions.GetPlayer(src)
    local ownerCitizenID = player.PlayerData.citizenid

    print("[DEBUG] Server Evicting Tenant with TenantID:", tenantID, "from Property:", propertyName, "Unit ID:", unitID)

    local ownerQuery = [[
        SELECT ownerCitizenID 
        FROM smb_properties 
        WHERE propertyName = @propertyName
    ]]
    
    MySQL.Async.fetchAll(ownerQuery, { ['@propertyName'] = propertyName }, function(results)
        if results and #results > 0 and results[1].ownerCitizenID == ownerCitizenID then
            print("[DEBUG] CitizenID:", ownerCitizenID, "is the owner. Proceeding with eviction.")
            
            local evictionQuery = [[
                UPDATE smb_properties_tenants 
                SET status = 'evicted' 
                WHERE unitID = @unitID AND tenantID = @tenantID AND status = 'active' AND propertyName = @propertyName
            ]]
            
            MySQL.Async.execute(evictionQuery, { 
                ['@unitID'] = unitID, 
                ['@tenantID'] = tenantID, 
                ['@propertyName'] = propertyName 
            }, function(affectedRows)
                if affectedRows > 0 then
                    print("[DEBUG] Tenant evicted successfully.")
                    cb(true, "Tenant evicted successfully.") 
                else
                    print("[DEBUG] Eviction query didn't affect any rows. Possibly tenant wasn't active or doesn't exist.")
                    cb(false, "Failed to evict the tenant. They might not be active or might not exist.") 
                end
            end)
        else
            print("[DEBUG] CitizenID:", ownerCitizenID, "is NOT the owner.")
            cb(false, "You are not the owner of this property.")
        end
    end)
end)


QBCore.Functions.CreateCallback('smb_properties:server:GetTenants', function(source, cb, unitID, propertyName)
    local query = [[
        SELECT * 
        FROM smb_properties_tenants
        WHERE unitID = @unitID AND propertyName = @propertyName AND status = 'active'
    ]]
    
    MySQL.Async.fetchAll(query, { 
        ['@unitID'] = unitID,
        ['@propertyName'] = propertyName 
    }, function(results)
        cb(results)
    end)
end)

QBCore.Functions.CreateCallback('smb_properties:server:GetTenantsDetails', function(source, cb, unitNumber, propertyName)
    local query = [[
        SELECT t.tenantID, t.unitID, t.citizenName, t.status, COALESCE(l.balance, 0) as totalDue
        FROM smb_properties_tenants AS t 
        LEFT JOIN (
            SELECT l1.tenantID, l1.balance
            FROM smb_properties_ledger l1
            JOIN (
                SELECT tenantID, MAX(transactionDate) as latestDate
                FROM smb_properties_ledger
                GROUP BY tenantID
            ) AS l2 ON l1.tenantID = l2.tenantID AND l1.transactionDate = l2.latestDate
        ) AS l ON t.tenantID = l.tenantID
        WHERE t.unitID = @unitID AND t.propertyName = @propertyName
    ]]

    MySQL.Async.fetchAll(query, { 
        ['@unitID'] = unitNumber,
        ['@propertyName'] = propertyName 
    }, function(tenants)
        if tenants and #tenants > 0 then
            cb(tenants)
        else
            print("No tenants found for the specified unit in the given property.")
        end
    end)
end)


QBCore.Functions.CreateCallback('smb_properties:server:GetRentedUnits', function(source, cb, propertyName)
    local src = source
    local citizenID = QBCore.Functions.GetPlayer(src).PlayerData.citizenid

    local query = [[
        SELECT t.tenantID, t.unitID, COALESCE(l.balance, 0) as totalAmountDue
        FROM smb_properties_tenants t
        JOIN smb_properties_units u ON t.unitID = u.unitID
        JOIN smb_properties p ON u.propertyName = p.propertyName
        LEFT JOIN (
            SELECT l1.tenantID, MAX(l1.transactionDate) as latestDate, l1.balance
            FROM smb_properties_ledger l1
            JOIN (
                SELECT tenantID, MAX(transactionDate) as maxDate
                FROM smb_properties_ledger
                GROUP BY tenantID
            ) AS l2 ON l1.tenantID = l2.tenantID AND l1.transactionDate = l2.maxDate
            GROUP BY l1.tenantID, l1.balance
        ) AS l ON t.tenantID = l.tenantID
        WHERE t.citizenID = ? AND p.propertyName = ? AND t.propertyName = ?
        GROUP BY t.tenantID, t.unitID, l.balance
    ]]

    MySQL.Async.fetchAll(query, { citizenID, propertyName, propertyName }, function(results)

        print(dump(results))
        if results and #results > 0 then
            cb(results)
        else
            cb(nil, "No rented units found for this player in the specified property.")
        end
    end)
end)

QBCore.Functions.CreateCallback('smb_properties:server:PayAmountDue', function(source, cb, tenantID, amountPaid)
    local src = source
    local player = QBCore.Functions.GetPlayer(src)

    GetLatestBalance(tenantID, function(prevBalance)
        
        if not prevBalance then
            prevBalance = 0
        end

        if prevBalance < amountPaid then
            cb(false, "Amount paid exceeds balance due!")
            return

        elseif amountPaid < 0 then
            cb(false, "Amount cannot be negative!")
            return
        end

        local cash = player.Functions.GetMoney("cash")
        -- local bank = player.Functions.GetMoney("bank")

        if cash >= amountPaid then
            player.Functions.RemoveMoney('cash', amountPaid)
            
            local ledgerQuery = [[
                INSERT INTO smb_properties_ledger (tenantID, description, amount, balance, transactionType) 
                VALUES (@tenantID, 'Payment', @amountPaid, @newBalance, 'balance_update')
            ]]
            MySQL.Async.execute(ledgerQuery, { 
                ['@tenantID'] = tenantID, 
                ['@amountPaid'] = -amountPaid, 
                ['@newBalance'] = prevBalance - amountPaid 
            }, function()
                
                -- local updateTenantStatusQuery = [[
                --     UPDATE smb_properties_tenants
                --     SET status = 'completed'
                --     WHERE tenantID = @tenantID
                -- ]]
                -- MySQL.Async.execute(updateTenantStatusQuery, { ['@tenantID'] = tenantID }, function()
                    cb(true, "Payment successful and tenancy marked as completed!")
                -- end)
            end)
        else
            cb(false, "You do not have enough cash!")
            return
        end
    end)
end)

QBCore.Functions.CreateCallback('smb_properties:server:FetchAmountDue', function(source, cb, tenantID)
    local query = [[
        SELECT COALESCE(l.balance, 0) as totalDue
        FROM smb_properties_ledger l
        WHERE l.transactionDate = (
            SELECT MAX(transactionDate)
            FROM smb_properties_ledger
            WHERE tenantID = @tenantID
        ) AND l.tenantID = @tenantID
    ]]

    MySQL.Async.fetchScalar(query, { ['@tenantID'] = tenantID }, function(totalDue)
        if totalDue then
            cb(tonumber(totalDue))
        else
            cb(0)
        end
    end)
end)

QBCore.Functions.CreateCallback('smb_properties:server:GetAvailableUnits', function(source, cb, propertyName)
    local query = [[
        SELECT 
            u.unitID, u.propertyName, u.rentCost, IFNULL(t.tenantCount, 0) as tenantCount, u.isAvailable
        FROM 
            smb_properties_units u
        LEFT JOIN (
            SELECT unitID, propertyName, COUNT(*) as tenantCount
            FROM smb_properties_tenants
            WHERE status = 'active'
            GROUP BY unitID, propertyName
        ) t ON u.unitID = t.unitID AND u.propertyName = t.propertyName
        WHERE 
            u.propertyName = @propertyName AND u.isAvailable = 1
    ]]

    MySQL.Async.fetchAll(query, { ['@propertyName'] = propertyName }, function(units, err)
        if err then
            debugPrint("Callback: Error executing SQL query:", err)
            cb(nil)
            return
        end

        debugPrint("Callback: Units retrieved from the database.")
        debugPrint("Callback: Property Name: " .. propertyName)

        if units then
            local availableUnits = {}
            for _, unit in ipairs(units) do
                local unitID = unit.unitID
                local tenantCount = unit.tenantCount or 0
                local availableSlots = 3 - tenantCount
                local tenantStatus = tenantCount == 3 and "Fully Occupied" or "Vacant (" .. availableSlots .. " slots available)"
                local rentCost = unit.rentCost

                debugPrint("Unit ID: " .. unitID)
                debugPrint("Tenant Count: " .. tenantCount)
                debugPrint("Available Slots: " .. availableSlots)

                table.insert(availableUnits, {
                    unitID = unitID,
                    tenantCount = tenantCount,
                    availableSlots = availableSlots,
                    tenantStatus = tenantStatus,
                    rentCost = rentCost
                })
            end

            if #availableUnits > 0 then
                debugPrint("Callback: Units found.")
                cb(availableUnits)
            else
                debugPrint("Callback: No units found for the specified property.")
                cb(nil)
            end
        else
            debugPrint("Callback: No units found for the specified property.")
            cb(nil)
        end
    end)
end)

QBCore.Functions.CreateCallback('smb_properties:server:GetTenantData', function(source, cb, propertyName)
    local query = [[
        SELECT 
            u.unitID, u.propertyName, u.rentCost, IFNULL(t.tenantCount, 0) as tenantCount, u.isAvailable
        FROM 
            smb_properties_units u
        LEFT JOIN (
            SELECT unitID, propertyName, COUNT(*) as tenantCount
            FROM smb_properties_tenants
            WHERE status = 'active'
            GROUP BY unitID, propertyName
        ) t ON u.unitID = t.unitID AND u.propertyName = t.propertyName
        WHERE 
            u.propertyName = @propertyName AND u.isAvailable = 1
    ]]

    MySQL.Async.fetchAll(query, { ['@propertyName'] = propertyName }, function(units, err)
        if err then
            debugPrint("Callback: Error executing SQL query:", err)
            cb(nil)
            return
        end

        debugPrint("Callback: Units retrieved from the database.")
        debugPrint("Callback: Property Name: " .. propertyName)

        if units then
            local availableUnits = {}
            for _, unit in ipairs(units) do
                local unitID = unit.unitID
                local tenantCount = unit.tenantCount or 0
                local availableSlots = 3 - tenantCount
                local tenantStatus = tenantCount == 3 and "Fully Occupied" or "Vacant (" .. availableSlots .. " slots available)"
                local rentCost = unit.rentCost

                debugPrint("Unit ID: " .. unitID)
                debugPrint("Tenant Count: " .. tenantCount)
                debugPrint("Available Slots: " .. availableSlots)

                table.insert(availableUnits, {
                    unitID = unitID,
                    tenantCount = tenantCount,
                    availableSlots = availableSlots,
                    tenantStatus = tenantStatus,
                    rentCost = rentCost
                })
            end

            if #availableUnits > 0 then
                debugPrint("Callback: Units found.")
                cb(availableUnits)
            else
                debugPrint("Callback: No units found for the specified property.")
                cb(nil)
            end
        else
            debugPrint("Callback: No units found for the specified property.")
            cb(nil)
        end
    end)
end)

function generateStashid(propertyName, unitid)
    local stashid = {}
    for i = 1,3,1 do
        stashid[i] = propertyName .. '_unit_' .. unitid .. '_stash_' ..  i
    end
    return stashid
end

QBCore.Functions.CreateCallback('smb_properties:server:RentUnit', function(source, cb, unitID, propertyName)
    local player = QBCore.Functions.GetPlayer(source)
    local citizenID = player.PlayerData.citizenid

    local evictionQuery = [[
        SELECT 
            *
        FROM 
            smb_properties_tenants
        WHERE 
            citizenID = @citizenID AND propertyName = @propertyName AND status = 'evicted'
    ]]

    MySQL.Async.fetchAll(evictionQuery, {
        ['@citizenID'] = citizenID,
        ['@propertyName'] = propertyName
    }, function(evictedTenant)
        if #evictedTenant > 0 then
            cb(false, "You have been evicted from this property and cannot rent a unit here.")
            return
        end

        local query = [[
            SELECT 
                *
            FROM 
                smb_properties_tenants
            WHERE 
                unitID = @unitID AND citizenID = @citizenID AND propertyName = @propertyName
        ]]

        MySQL.Async.fetchAll(query, {
            ['@unitID'] = unitID,
            ['@citizenID'] = citizenID,
            ['@propertyName'] = propertyName
        }, function(existingTenant, err)
            if err then
                debugPrint("RentUnit: Error executing SQL query:", err)
                cb(false, "An error occurred while processing your request.")
                return
            end
            -- print("Existing Tenant Data:", json.encode(existingTenant))
            local isActiveRentalExists = false

            for _, tenant in ipairs(existingTenant) do
                if tenant.status == "active" then
                    isActiveRentalExists = true
                    break
                end
            end
            
            if isActiveRentalExists then
                cb(false, "You are currently renting this unit.")
                return
            end

            local query2 = [[
                SELECT tenantCount, rentCost
                FROM smb_properties_units
                LEFT JOIN (
                    SELECT unitID, propertyName, COUNT(*) as tenantCount
                    FROM smb_properties_tenants
                    WHERE status = 'active'
                    GROUP BY unitID, propertyName
                ) t ON smb_properties_units.unitID = t.unitID AND smb_properties_units.propertyName = t.propertyName
                WHERE smb_properties_units.unitID = @unitID AND smb_properties_units.propertyName = @propertyName
            ]]

            MySQL.Async.fetchAll(query2, {
                ['@unitID'] = unitID,
                ['@propertyName'] = propertyName
            }, function(unitInfo, err2)
                if err2 then
                    debugPrint("RentUnit: Error executing SQL query:", err2)
                    cb(false, "An error occurred while processing your request.")
                    return
                end

                if unitInfo and #unitInfo > 0 then
                    local tenantCount = unitInfo[1].tenantCount or 0
                    local rentCost = unitInfo[1].rentCost
                    local availableSlots = 3 - tenantCount

                    if player.PlayerData.money.cash >= rentCost then
                        player.Functions.RemoveMoney('cash', rentCost, "rented-property")
                    elseif player.PlayerData.money.bank >= rentCost then
                        player.Functions.RemoveMoney('bank', rentCost, "rented-property")
                    else
                        cb(false, "You do not have enough funds to rent this unit. Needed: $" .. rentCost)
                        return
                    end

                    if availableSlots > 0 then
                        MySQL.Async.fetchAll("SELECT stash_id FROM `smb_properties_tenants` WHERE unitID = @unitID AND status = 'active'", {
                            ['@unitID'] = unitID
                        }, function(tenants)
                            local inUseStashes = {}
                            for _, tenant in ipairs(tenants) do
                                inUseStashes[tenant.stash_id] = true
                            end
                            
                            local stash_id
                            for _, stashId in ipairs(generateStashid(propertyName, unitID)) do
                                if not inUseStashes[stashId] then
                                    stash_id = stashId
                                    break
                                end
                            end

    
                            local insertQuery = [[
                                INSERT INTO 
                                    smb_properties_tenants (unitID, propertyName, citizenID, status, citizenName, stash_id)
                                VALUES 
                                    (@unitID, @propertyName, @citizenID, @status, @citizenName, @stash_id)
                            ]]
                        
                            MySQL.Async.execute(insertQuery, {
                                ['@unitID'] = unitID,
                                ['@propertyName'] = propertyName,
                                ['@citizenID'] = citizenID,
                                ['@status'] = 'active',
                                ['@citizenName'] = player.PlayerData.charinfo.firstname .. ' ' .. player.PlayerData.charinfo.lastname,
                                ['@stash_id'] = stash_id,
                            }, function(rowsInserted, err3)
                                if err3 then
                                    debugPrint("RentUnit: Error executing SQL query:", err3)
                                    cb(false, "An error occurred while processing your request.")
                                    return
                                end

                                cb(true, "Unit rented successfully! Monthly rent: $" .. rentCost)
                            end)
                        end)
                    else
                        cb(false, "This unit is fully occupied.")
                    end
                else
                    cb(false, "Invalid unit ID or property name.")
                end
            end)
        end)
    end)
end)