local QBCore = exports['qb-core']:GetCoreObject()
local isInsizeZone = false
local displayDistance = 2.0
local currentProperty = nil
local ClientDoorStates = {}

local function IsPlayerNearCoord(coord)
    local playerCoord = GetEntityCoords(PlayerPedId())
    local distance = #(playerCoord - vector3(coord.x, coord.y, coord.z))
    return distance <= displayDistance
end

local function ToggleDoorState(door)
    door.locked = not door.locked
    TriggerServerEvent('smb_properties:server:UpdateDoorState', currentPropertyName, door.doorHash, door.locked)

    if door.locked then
        QBCore.Functions.Notify('Door locked!', 'success')
    else
        QBCore.Functions.Notify('Door unlocked!', 'success')
    end
end

local function SetDoorState(doorHash, state)
    local doorState = state and 4 or 0
    DoorSystemSetDoorState(doorHash, doorState)
end

local function HandleAction(actionType, property, unitId)
    if actionType == "stash" then
        QBCore.Functions.Notify('Accessing property stash!', 'success')
    elseif actionType == "door" then
        QBCore.Functions.Notify('Using property door!', 'success')
    elseif actionType == "unit_stash" then
        QBCore.Functions.Notify('Accessing unit stash!', 'success')
    elseif actionType == "unit_door" then
        local door = property.units[unitId].door
        ToggleDoorState(door)
    end
end

CreateThread(function()
    for propertyName, property in pairs(Config.Properties) do

        if property.polyZone then
            local zone = PolyZone:Create(property.polyZone, {
                name = propertyName,
                debugPoly = false,
                minZ = property.coords.z - 10.0,
                maxZ = property.coords.z + 7.0
            })

            zone:onPlayerInOut(function(isPointInside)
                if isPointInside then
                    isInsizeZone = true
                    currentProperty = property
                else
                    isInsizeZone = false
                    currentProperty = nil
                end
            end)
        end

        if property.doors then
            for _, door in ipairs(property.doors) do
                print("Registering door: " .. door.doorHash)
                AddDoorToSystem(door.doorHash, door.modelHash, door.coords.x, door.coords.y, door.coords.z, false, true, false)
            end
        elseif property.type == "motel" then
            for _, unit in pairs(property.units) do
                local door = unit.door
                print("Registering motel door: " .. door.doorHash)
                AddDoorToSystem(door.doorHash, door.modelHash, door.coords.x, door.coords.y, door.coords.z, false, true, false)
            end
        end
    end
end)

CreateThread(function()
    local waitTime = 500
    local actionType, unitId

    while true do
        if isInsizeZone and currentProperty then
            local isNearSomething = false

            if currentProperty.stash and IsPlayerNearCoord(currentProperty.stash) then
                exports['qb-core']:DrawText("Press [E] to access property stash")
                actionType = "stash"
                isNearSomething = true
            end

            for _, door in ipairs(currentProperty.doors or {}) do
                if IsPlayerNearCoord(door.coords) then
                    exports['qb-core']:DrawText("Press [E] to use property door")
                    actionType = "door"
                    isNearSomething = true
                    break
                end
            end

            if currentProperty.type == "mansion" or currentProperty.type == "motel" then
                for id, unit in pairs(currentProperty.units or {}) do
                    if unit.stash and IsPlayerNearCoord(unit.stash) then
                        exports['qb-core']:DrawText("Press [E] to unlock door")
                        actionType = "unit_stash"
                        unitId = id
                        isNearSomething = true
                        break
                    elseif unit.door and IsPlayerNearCoord(unit.door.coords) then
                        exports['qb-core']:DrawText("Press [E] to unlock door")
                        actionType = "unit_door"
                        unitId = id
                        isNearSomething = true
                        break
                    end
                end
            end

            if IsControlJustPressed(0, 38) and actionType then
                HandleAction(actionType, currentProperty, unitId)
            end

            if not isNearSomething then
                actionType, unitId = nil, nil
                exports['qb-core']:HideText()
                waitTime = 500
            else
                waitTime = 10
            end
        else
            waitTime = 1000
        end

        Wait(waitTime)
    end
end)

RegisterNetEvent('smb_properties:client:InitializeDoorStates')
AddEventHandler('smb_properties:client:InitializeDoorStates', function(serverDoorStates)
    ClientDoorStates = serverDoorStates
    for doorHash, state in pairs(ClientDoorStates) do
        SetDoorState(doorHash, state)
    end
end)

RegisterNetEvent('smb_properties:client:SetDoorState')
AddEventHandler('smb_properties:client:SetDoorState', function(name, doorHash, state)
    ClientDoorStates[doorHash] = state
    SetDoorState(doorHash, state)
end)