local QBCore = exports['qb-core']:GetCoreObject()

RegisterServerEvent('smb_properties:server:UpdateDoorState')
AddEventHandler('smb_properties:server:UpdateDoorState', function(propertyName, doorHash, state)
    local src = source
    TriggerClientEvent('smb_properties:client:SetDoorState', -1, propertyName, doorHash, state)
end)