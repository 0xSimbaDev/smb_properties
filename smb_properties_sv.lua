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
    local citizenID = QBCore.Functions.GetPlayer(src).PlayerData.citizenid
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
        ORDER BY transactionDate DESC 
        LIMIT 1
    ]]
    
    MySQL.Async.fetchScalar(query, { ['@tenantID'] = tenantID }, function(balance)
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
    local cashBalance = player.PlayerData.money["cash"]

    debugPrint("Processing rent for CitizenID: " .. citizenID)
    debugPrint("Current Bank Balance: " .. bankBalance)
    debugPrint("Current Cash Balance: " .. cashBalance)

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

                if cashBalance + bankBalance < rentAmount then
                    local dueAmount = rentAmount - cashBalance - bankBalance
                    GetLatestBalance(tenantID, function(latestBalance)
                        local balanceAfterTransaction = latestBalance + dueAmount  
                        
                        local ledgerQuery = "INSERT INTO smb_properties_ledger (tenantID, description, amount, balance, transactionType) VALUES (@tenantID, 'Monthly Rent', @dueAmount, @balanceAfterTransaction, 'Charge')"
                        MySQL.Async.execute(ledgerQuery, { ['@tenantID'] = tenantID, ['@dueAmount'] = dueAmount, ['@balanceAfterTransaction'] = balanceAfterTransaction })
                        
                        if balanceAfterTransaction >= 10000 then
                            local evictionQuery = "UPDATE smb_properties_tenants SET status = 'evicted' WHERE tenantID = @tenantID"
                            MySQL.Async.execute(evictionQuery, { ['@tenantID'] = tenantID })
                            debugPrint("TenantID: " .. tenantID .. " evicted due to high debt!")
                        end
                    end)
                else
                
                    local remainingBalance = cashBalance + bankBalance - rentAmount
                    debugPrint("Sufficient funds. New balance after rent deduction: " .. remainingBalance)

                    if remainingBalance > cashBalance then
                        player.Functions.RemoveMoney('cash', cashBalance)
                        player.Functions.RemoveMoney('bank', remainingBalance - cashBalance)
                    else
                        player.Functions.RemoveMoney('cash', rentAmount)
                    end

                    local ledgerQuery = "INSERT INTO smb_properties_ledger (tenantID, description, amount, balance, transactionType) VALUES (@tenantID, 'Rent Payment', @rentAmount, 0, 'Payment')"
                    MySQL.Async.execute(ledgerQuery, { ['@tenantID'] = tenantID, ['@rentAmount'] = -rentAmount })
                    debugPrint("Rent payment logged for TenantID: " .. tenantID)
                end
            end
        else
            debugPrint("No active tenants found for CitizenID: " .. citizenID)
        end
    end)
end

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(1800000) --  30 minutes

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

QBCore.Functions.CreateCallback('smb_properties:server:CheckStashAccess', function(source, cb, stashID)
    local src = source
    local citizenID = QBCore.Functions.GetPlayer(src).PlayerData.citizenid

    local query = [[
        SELECT 
            stash_id 
        FROM 
            smb_properties_tenants 
        WHERE 
            citizenID = @citizenID AND status = 'active'
    ]]
    
    MySQL.Async.fetchAll(query, {['@citizenID'] = citizenID}, function(result)
        if result and #result > 0 then
            for i=1, #result do
                if result[i].stash_id == stashID then
                    cb(true)
                    return
                end
            end
        end
        cb(false)
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
        end

        local cash = player.Functions.GetMoney("cash")
        local bank = player.Functions.GetMoney("bank")

        -- if bank >= amountPaid then
        --     player.Functions.RemoveMoney('bank', amountPaid)
            
            local ledgerQuery = [[
                INSERT INTO smb_properties_ledger (tenantID, description, amount, balance, transactionType) 
                VALUES (@tenantID, 'Payment', @amountPaid, @newBalance, 'Payment')
            ]]
            MySQL.Async.execute(ledgerQuery, { 
                ['@tenantID'] = tenantID, 
                ['@amountPaid'] = -amountPaid, 
                ['@newBalance'] = prevBalance - amountPaid 
            }, function()
                
                local updateTenantStatusQuery = [[
                    UPDATE smb_properties_tenants
                    SET status = 'completed'
                    WHERE tenantID = @tenantID
                ]]
                MySQL.Async.execute(updateTenantStatusQuery, { ['@tenantID'] = tenantID }, function()
                    cb(true, "Payment successful and tenancy marked as completed!")
                end)
            end)
        -- else
        --     cb(false, "Not enough money in the bank account!")
        --     return
        -- end
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
                        MySQL.Async.fetchAll("SELECT stash_id FROM smb_properties_tenants WHERE unitID = @unitID AND status = 'active'", {
                            ['@unitID'] = unitID
                        }, function(tenants)
                            local inUseStashes = {}
                            for _, tenant in ipairs(tenants) do
                                inUseStashes[tenant.stash_id] = true
                            end
                            
                            local stash_id
                            for _, stashId in ipairs(Config.Properties[propertyName].units[unitID].stash.ids) do
                                if not inUseStashes[stashId] then
                                    stash_id = stashId
                                    break
                                end
                            end
                            
                            if not stash_id then
                                cb(false, "Error assigning stash ID.")
                                return
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
                                ['@stash_id'] = stash_id
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