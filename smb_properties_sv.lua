local QBCore = exports['qb-core']:GetCoreObject()

local DoorStates = {}

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

local function GetTotalDueAmount(tenantID, callback)
    local query = "SELECT SUM(amountDue) as totalDue FROM smb_properties_payments WHERE tenantID = @tenantID"
    MySQL.Async.fetchAll(query, { ['@tenantID'] = tenantID }, function(results)
        if results and #results > 0 and results[1].totalDue then
            callback(tonumber(results[1].totalDue))
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

    -- print("[DEBUG] CitizenID:", citizenID, "Bank Balance:", bankBalance, "Cash Balance:", cashBalance) 

    local query = "SELECT smb_properties_tenants.*, smb_properties_units.*, smb_properties.ownerCitizenID FROM smb_properties_tenants INNER JOIN smb_properties_units ON smb_properties_tenants.unitID = smb_properties_units.unitID INNER JOIN smb_properties ON smb_properties_units.propertyName = smb_properties.propertyName WHERE smb_properties_tenants.citizenID = @citizenID AND smb_properties_tenants.status = 'active'"

    MySQL.Async.fetchAll(query, { ['@citizenID'] = citizenID }, function(results)
        if results and #results > 0 then
            for _, result in ipairs(results) do  
                local rentAmount = result.rentCost 
                local tenantID = result.tenantID
                local propertyOwner = result.ownerCitizenID

                -- print("[DEBUG] Rent Amount:", rentAmount, "TenantID:", tenantID, "Property Owner:", propertyOwner)

                local dueAmount = rentAmount - cashBalance - bankBalance

                -- print("[DEBUG] Calculated Due Amount:", dueAmount)

                if dueAmount > 0 then
                    GetTotalDueAmount(result.tenantID, function(totalDue)
                        -- print("[DEBUG] Total Due Amount:", totalDue)

                        local paymentQuery = "INSERT INTO smb_properties_payments (tenantID, amountDue) VALUES (@tenantID, @dueAmount)"
                        MySQL.Async.execute(paymentQuery, { ['@tenantID'] = result.tenantID, ['@dueAmount'] = dueAmount })

                        if totalDue + dueAmount >= 10000 then
                            local evictionQuery = "UPDATE smb_properties_tenants SET status = 'evicted' WHERE tenantID = @tenantID"
                            MySQL.Async.execute(evictionQuery, { ['@tenantID'] = result.tenantID })
                        end
                    end)
                else
                    local remainingBalance = cashBalance + bankBalance - rentAmount
                    -- print("[DEBUG] Remaining Balance after rent deduction:", remainingBalance) 
                    if remainingBalance > cashBalance then
                        player.Functions.RemoveMoney('cash', cashBalance)
                        player.Functions.RemoveMoney('bank', remainingBalance - cashBalance)
                    else
                        player.Functions.RemoveMoney('cash', rentAmount)
                    end
                end
            end
        end
    end)
end

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(10000) 

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

-- QBCore.Functions.CreateCallback('smb_properties:server:GetPropertyData', function(source, cb, propertyName, unitID)

--     if not propertyName or not unitID then
--         print("[Error] smb_properties:server:GetPropertyData - Invalid inputs")
--         cb(nil)
--         return
--     end

--     local query = "SELECT * FROM smb_properties WHERE propertyName = @propertyName AND unitID = @unitID"
--     MySQL.Async.fetchAll(query, {
--         ['@propertyName'] = propertyName,
--         ['@unitID'] = unitID
--     }, function(result)
--         if result and result[1] then
--             cb(result[1])
--         else
--             print("[Warning] smb_properties:server:GetPropertyData - No result found for propertyName:", propertyName, "and unitID:", unitID)
--             cb(nil)
--         end
--     end)
-- end)

QBCore.Functions.CreateCallback('smb_properties:server:GetAccessData', function(source, cb, propertyName, unitID)
    local src = source
    local citizenID = QBCore.Functions.GetPlayer(src).PlayerData.citizenid

    local query = "SELECT ownerCitizenID FROM smb_properties WHERE propertyName = @propertyName"
    MySQL.Async.fetchAll(query, { ['@propertyName'] = propertyName }, function(results)
        if results[1] and results[1].ownerCitizenID == citizenID then
            cb(true)
            return
        end

        query = "SELECT COUNT(*) as count FROM smb_properties_tenants WHERE unitID = @unitID AND citizenID = @citizenID AND status = 'active'"
        MySQL.Async.fetchAll(query, { ['@unitID'] = unitID, ['@citizenID'] = citizenID }, function(tenants)
            if tenants[1] and tenants[1].count > 0 then
                cb(true)
            else
                cb(false)
            end
        end)
    end)
end)


QBCore.Functions.CreateCallback('smb_properties:server:CheckStashAccess', function(source, cb, stashID)
    local src = source
    local citizenID = QBCore.Functions.GetPlayer(src).PlayerData.citizenid

    local query = [[
        SELECT stash_id 
        FROM smb_properties_tenants 
        WHERE citizenID = @citizenID AND status = 'active'
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
                WHERE unitID = @unitID AND tenantID = @tenantID AND status = 'active'
            ]]
            
            MySQL.Async.execute(evictionQuery, { ['@unitID'] = unitID, ['@tenantID'] = tenantID }, function(affectedRows)
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

QBCore.Functions.CreateCallback('smb_properties:server:GetTenants', function(source, cb, unitID)
    local query = [[
        SELECT * 
        FROM smb_properties_tenants
        WHERE unitID = @unitID
    ]]
    
    MySQL.Async.fetchAll(query, { ['@unitID'] = unitID }, function(results)
        cb(results)
    end)
end)

QBCore.Functions.CreateCallback('smb_properties:server:GetTenantsDetails', function(source, cb, unitNumber)
    local query = [[
        SELECT t.tenantID, t.unitID, t.citizenName, t.status, 
               SUM(p.amountDue) as totalDue
        FROM smb_properties_tenants AS t 
        JOIN smb_properties_payments AS p ON t.tenantID = p.tenantID 
        WHERE t.unitID = @unitID
        GROUP BY t.tenantID, t.unitID, t.citizenName, t.status
    ]]

    MySQL.Async.fetchAll(query, { ['@unitID'] = unitNumber }, function(tenants)
        if tenants and #tenants > 0 then
            cb(tenants)
        else
            print("No tenants found for the specified unit.")
        end
    end)
end)












-- QBCore.Functions.CreateCallback('smb_properties:server:GetPropertyData', function(source, cb, propertyName)
--     local query = "SELECT * FROM smb_properties WHERE propertyName = @propertyName"
--     MySQL.Async.fetchAll(query, {
--         ['@propertyName'] = propertyName
--     }, function(result)
--         if result and result[1] then
--             cb(result[1])
--         else
--             cb(nil)
--         end
--     end)
-- end)

-- QBCore.Functions.CreateCallback('smb_properties:server:GetUnitsByProperty', function(source, cb, propertyName)
--     local query = "SELECT * FROM smb_properties_units WHERE propertyName = @propertyName"
--     MySQL.Async.fetchAll(query, {
--         ['@propertyName'] = propertyName
--     }, function(units)
--         if units then
--             cb(units)
--         else
--             cb(nil)
--         end
--     end)
-- end)

-- QBCore.Functions.CreateCallback('smb_properties:server:GetTenantsByUnit', function(source, cb, unitID)
--     local query = "SELECT * FROM smb_properties_tenants WHERE unitID = @unitID"
--     MySQL.Async.fetchAll(query, {
--         ['@unitID'] = unitID
--     }, function(tenants)
--         if tenants then
--             cb(tenants)
--         else
--             cb(nil)
--         end
--     end)
-- end)

