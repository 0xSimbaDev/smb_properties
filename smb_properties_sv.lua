local QBCore = exports['qb-core']:GetCoreObject()

local DoorStates = {}

local InitializeDoorStates()
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

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        InitializeDoorStates()
    end
end)

RegisterServerEvent('smb_properties:server:UpdateDoorState')
AddEventHandler('smb_properties:server:UpdateDoorState', function(propertyName, doorHash, state)
    DoorStates[doorHash] = state
    TriggerClientEvent('smb_properties:client:SetDoorState', -1, propertyName, doorHash, state)
end)

AddEventHandler('playerConnecting', function(playerName, setKickReason, deferrals)
    local src = source
    TriggerClientEvent('smb_properties:client:InitializeDoorStates', src, DoorStates)
end)