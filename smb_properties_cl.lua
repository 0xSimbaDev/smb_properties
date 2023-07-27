local QBCore = exports['qb-core']:GetCoreObject()
local isInsizeZone = false
local displayDistance = 1.0
local currentProperty = nil
local ClientDoorStates = {}

local function IsPlayerNearCoord(coord)
    local playerCoord = GetEntityCoords(PlayerPedId())
    local distance = #(playerCoord - vector3(coord.x, coord.y, coord.z))
    return distance <= displayDistance
end

local function SetDoorState(doorHash, state)
    local doorState = state and 4 or 0
    DoorSystemSetDoorState(doorHash, doorState)
end

local function loadAnimDict(dict)
	RequestAnimDict(dict)
	while not HasAnimDictLoaded(dict) do
		Wait(0)
	end
end

local function doorAnim()
	CreateThread(function()
		loadAnimDict("anim@heists@keycard@")
        TaskPlayAnim(PlayerPedId(), "anim@heists@keycard@", "exit", 8.0, 1.0, -1, 48, 0, 0, 0, 0)
        Wait(1000)
        ClearPedTasks(PlayerPedId())
    end)
end

local function FormatStashHeader(stashId)
    local stashNumber = stashId:match("stash_(%d+)$")
    if stashNumber then
        return "Stash " .. stashNumber
    else
        return "Unknown Stash"
    end
end

local function ToggleDoorState(door, unitId)
    QBCore.Functions.TriggerCallback('smb_properties:server:GetAccessData', function(hasAccess)
        if hasAccess then
            door.locked = not door.locked
            TriggerServerEvent('smb_properties:server:UpdateDoorState', propertyName, door.doorHash, door.locked)

            if door.locked then
                QBCore.Functions.Notify('Door locked!', 'success')
            else
                QBCore.Functions.Notify('Door unlocked!', 'success')
            end
        else
            QBCore.Functions.Notify('You don\'t have access to this door!', 'error')
        end
    end, currentProperty.name, unitId)
end

local function ShowStashMenu(stash, unitId)
    local elements = {
        {
            header = 'Unit Stash',
            icon = 'fas fa-box',
            isMenuHeader = true
        }
    }

    for _, stashId in ipairs(stash.ids) do
        table.insert(elements, {
            header = FormatStashHeader(stashId),
            txt = 'Access Stash',
            icon = 'fas fa-archive',
            params = {
                event = 'smb_properties:client:OpenStash',
                args = {
                    stashId = stashId
                }
            }
        })
    end

    exports['qb-menu']:openMenu(elements)
end

local function HandleAction(actionType, property, unitId)
    if actionType == "stash" then
        QBCore.Functions.Notify('Accessing property stash!', 'success')
    elseif actionType == "door" then
        QBCore.Functions.Notify('Using property door!', 'success')
    elseif actionType == "unit_stash" then
        local stash = property.units[unitId].stash
        ShowStashMenu(stash, unitId)
    elseif actionType == "unit_door" then
        local door = property.units[unitId].door
        doorAnim()
        ToggleDoorState(door, unitId)
    end
end

local function RegisterDoor(door)
    print("Registering door: " .. door.doorHash)
    AddDoorToSystem(door.doorHash, door.modelHash, door.coords.x, door.coords.y, door.coords.z, false, true, false)
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
                RegisterDoor(door)
            end
        elseif property.type == "motel" then
            for _, unit in pairs(property.units) do
                local door = unit.door
                RegisterDoor(unit.door)
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
                    if unit.stash and IsPlayerNearCoord(unit.stash.coords) then
                        exports['qb-core']:DrawText("Press [E] to open stash")
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

RegisterCommand('propertymenu', function()
    local elements = {
        {
            header = 'Property Management',
            icon = 'fas fa-home',
            isMenuHeader = true
        }
    }

    for k, property in pairs(Config.Properties) do
        table.insert(elements, {
            header = property.name,
            txt = 'Manage this property',
            icon = 'fas fa-building',
            params = {
                event = 'smb_properties:client:manageProperty',
                args = {
                    propertyName = k
                }
            }
        })
    end

    exports['qb-menu']:openMenu(elements)
end)

RegisterNetEvent('smb_properties:client:manageProperty', function(data)
    local propertyName = data.propertyName
    local property = Config.Properties[propertyName]
    local elements = {
        {
            header = 'Manage ' .. propertyName,
            icon = 'fas fa-tools',
            isMenuHeader = true
        }
    }

    for k, unit in pairs(property.units) do
        table.insert(elements, {
            header = 'Unit ' .. k,
            txt = 'Check Availability',
            icon = 'fas fa-door-open',
            params = {
                event = 'qb-menu:client:manageUnit',
                args = {
                    propertyName = propertyName,
                    unitNumber = k
                }
            }
        })
    end

    exports['qb-menu']:openMenu(elements)
end)

RegisterNetEvent('qb-menu:client:manageUnit', function(data)
    local propertyName = data.propertyName
    local unitNumber = data.unitNumber
    local unit = Config.Properties[propertyName].units[unitNumber]

    local elements = {
        {
            header = 'Manage Unit ' .. unitNumber,
            icon = 'fas fa-user-circle',
            isMenuHeader = true
        },
        {
            header = 'Add Tenant',
            txt = 'Assign a new tenant',
            icon = 'fas fa-user-plus',
            params = {
                event = 'smb_properties:client:OpenTenantForm',
                args = {
                    unitData = unit,
                    unitNumber = unitNumber
                }
            }
        },
        {
            header = 'Evict Tenant',
            txt = 'Remove a tenant from this unit',
            icon = 'fas fa-user-minus',
            params = {
                event = 'smb_properties:client:EvictTenantOption',
                args = {
                    propertyName = propertyName,
                    unitNumber = unitNumber
                }
            }
        },
        {
            header = 'Show Tenant List',
            txt = 'Remove a tenant from this unit',
            icon = 'fas fa-list-ul',
            params = {
                event = 'smb_properties:client:ShowTenantList',
                args = {
                    propertyName = propertyName,
                    unitNumber = unitNumber
                }
            }
        }
    }

    exports['qb-menu']:openMenu(elements)
end)

RegisterNetEvent('smb_properties:client:OpenStash', function(stashData)
    if stashData.stashId ~= nil then
        QBCore.Functions.TriggerCallback('smb_properties:server:CheckStashAccess', function(hasAccess)
            if hasAccess then
                TriggerServerEvent("inventory:server:OpenInventory", "stash", stashData.stashId)
                TriggerServerEvent("InteractSound_SV:PlayOnSource", "StashOpen", 0.4)
                TriggerEvent("inventory:client:SetCurrentStash", stashData.stashId)
            else
                QBCore.Functions.Notify('You do not have access to this stash.', 'error')
            end
        end, stashData.stashId)
    else
        QBCore.Functions.Notify('You are not near a property or unit stash.', 'error')
    end
end)

RegisterNetEvent('smb_properties:client:OpenTenantForm')
AddEventHandler('smb_properties:client:OpenTenantForm', function(data)
    local unit = data.unitData
    local unitNumber = data.unitNumber

    local dialog = exports['qb-input']:ShowInput({
        header = "Add Tenant",
        submitText = "Add",
        inputs = {
            {
                text = "Citizen ID (#)",
                name = "citizenid",
                type = "number",
                isRequired = true,
            }
        },
    })

    if dialog then
        QBCore.Functions.TriggerCallback('smb_properties:server:AddTenant', function(success, msg)
            if success then
                QBCore.Functions.Notify("Tenant added successfully!", "success")
            else
                if msg then
                    QBCore.Functions.Notify(msg, "error")
                else
                    QBCore.Functions.Notify("Failed to add tenant!", "error")
                end
            end
        end, unitNumber, unit, dialog.citizenid, dialog.startDate, dialog.endDate)
    end
end)

RegisterNetEvent('smb_properties:client:EvictTenantOption', function(args)
    local propertyName = args.propertyName
    local unitNumber = args.unitNumber
    
    QBCore.Functions.TriggerCallback('smb_properties:server:GetTenants', function(tenants)
        if tenants and #tenants > 0 then
            local elements = {}
            for _, tenant in ipairs(tenants) do
                table.insert(elements, {
                    header = "Tenant: " .. tenant.citizenName,  
                    txt = 'Evict this tenant',
                    icon = 'fas fa-user-minus',
                    params = {
                        event = 'smb_properties:client:EvictTenant',
                        args = {
                            propertyName = propertyName,
                            unitNumber = unitNumber,
                            tenantID = tenant.tenantID
                        }
                    }
                })
            end
            
            exports['qb-menu']:openMenu(elements)
        else
            QBCore.Functions.Notify("No tenants found for this unit.", "error")
        end
    end, unitNumber)
end)

RegisterNetEvent('smb_properties:client:EvictTenant')
AddEventHandler('smb_properties:client:EvictTenant', function(args)
    local propertyName = args.propertyName
    local unitNumber = args.unitNumber
    local tenantID = args.tenantID

    QBCore.Functions.TriggerCallback('smb_properties:server:EvictTenant', function(success, msg)
        if success then
            QBCore.Functions.Notify("Tenant evicted successfully!", "success")
        else
            if msg then
                QBCore.Functions.Notify(msg, "error")
            else
                QBCore.Functions.Notify("Failed to evict tenant!", "error")
            end
        end
    end, propertyName, unitNumber, tenantID)
end)

RegisterNetEvent('smb_properties:client:ShowTenantList', function(data)
    local propertyName = data.propertyName
    local unitNumber = data.unitNumber

    QBCore.Functions.TriggerCallback('smb_properties:server:GetTenantsDetails', function(tenants)
        local tenantMenu = {
            {
                header = "Tenants in Unit " .. unitNumber,
                icon = 'fas fa-user-circle',
                isMenuHeader = true
            }
        }

        for _, tenant in ipairs(tenants) do
            table.insert(tenantMenu, {
                header = tenant.citizenName .. " | Tenant ID: " ..tenant.tenantID,
                txt = " Status: " .. tenant.status .. " | Total Due Amount: $" .. tenant.totalDue,
                icon = 'fas fa-user'
            })
        end

        exports['qb-menu']:openMenu(tenantMenu)
    end, unitNumber)
end)