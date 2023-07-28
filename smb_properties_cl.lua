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
    elseif actionType == "unit_clothing" then
        TriggerEvent('smb_properties:client:ChangeOutfit')
    elseif actionType == "unit_management" then
        TriggerEvent('smb_properties:client:ManageProperty')
    end
end

local function RegisterDoor(door)
    print("Registering door: " .. door.doorHash)
    AddDoorToSystem(door.doorHash, door.modelHash, door.coords.x, door.coords.y, door.coords.z, false, false, false)
end

CreateThread(function()
    for propertyName, property in pairs(Config.Properties) do

        if property.polyZone then
            local zone = PolyZone:Create(property.polyZone.points, {
                name = propertyName,
                debugPoly = true,
                minZ = property.polyZone.minZ,
                maxZ = property.polyZone.maxZ
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

            if not isNearSomething and currentProperty.management and IsPlayerNearCoord(currentProperty.management.coords) then
                exports['qb-core']:DrawText("Press [E] to manage property")
                actionType = "unit_management"
                isNearSomething = true
            end

            if not isNearSomething and (currentProperty.type == "mansion" or currentProperty.type == "motel") then
                for id, unit in pairs(currentProperty.units or {}) do
                    if unit.stash and IsPlayerNearCoord(unit.stash.coords) then
                        exports['qb-core']:DrawText("Press [E] to open stash")
                        actionType = "unit_stash"
                        unitId = id
                        isNearSomething = true
                        break
                    elseif unit.clothinCoords and IsPlayerNearCoord(unit.clothinCoords) then
                        exports['qb-core']:DrawText("Press [E] to open clothing")
                        actionType = "unit_clothing"
                        unitId = id
                        isNearSomething = true
                        break
                    elseif unit.door and IsPlayerNearCoord(unit.door.coords) then
                        exports['qb-core']:DrawText("Unit " .. id .. " | Press [E] to unlock door")
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

RegisterNetEvent('smb_properties:client:ManageProperty')
AddEventHandler('smb_properties:client:ManageProperty', function()
    local propertyName = currentProperty.name

    local elements = {
        {
            header = 'Property Management',
            icon = 'fas fa-home',
            isMenuHeader = true
        }
    }

    QBCore.Functions.TriggerCallback('smb_properties:server:GetPlayerRole', function(role)

        if role == "owner" then
            table.insert(elements, {
                header = propertyName,
                txt = 'Manage this property as owner',
                icon = 'fas fa-building',
                params = {
                    event = 'smb_properties:client:OwnerManagement',
                    args = {
                        propertyName = propertyName
                    }
                }
            })
        elseif role == "tenant" then
            table.insert(elements, {
                header = propertyName,
                txt = 'Manage this property as tenant',
                icon = 'fas fa-building',
                params = {
                    event = 'smb_properties:client:TenantManagement',
                    args = {
                        propertyName = propertyName
                    }
                }
            })
        else
            table.insert(elements, {
                header = "You are not a tenant in this property.",
                txt = "You do not have access to manage this property as a tenant.",
                icon = 'fas fa-user-slash'
            })
        end

        table.insert(elements, {
            header = 'View Available Units',
            txt = 'View the available units in this property',
            icon = 'fas fa-home',
            params = {
                event = 'smb_properties:client:ViewAvailableUnits',
                args = {
                    propertyName = propertyName
                }
            }
        })

        exports['qb-menu']:openMenu(elements)
    end, propertyName)
end)

RegisterNetEvent('smb_properties:client:TenantManagement')
AddEventHandler('smb_properties:client:TenantManagement', function(data)
    local propertyName = data.propertyName

    local elements = {
        {
            header = 'Property Management',
            icon = 'fas fa-home',
            isMenuHeader = true
        },
        {
            header = 'My Rented Units',
            txt = 'View units you are renting',
            icon = 'fas fa-list-ul',
            params = {
                event = 'smb_properties:client:ShowRentedUnits',
                args = {
                    propertyName = propertyName
                }
            }
        },
    }

    exports['qb-menu']:openMenu(elements)
end)

RegisterNetEvent('smb_properties:client:OwnerManagement')
AddEventHandler('smb_properties:client:OwnerManagement', function(data)

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
                event = 'smb_properties:client:ManageUnit',
                args = {
                    propertyName = propertyName,
                    unitNumber = k
                }
            }
        })
    end

    exports['qb-menu']:openMenu(elements)
end)

RegisterNetEvent('smb_properties:client:ViewAvailableUnits')
AddEventHandler('smb_properties:client:ViewAvailableUnits', function(data)
    local propertyName = data.propertyName

    QBCore.Functions.TriggerCallback('smb_properties:server:GetAvailableUnits', function(units)
        local elements = {
            {
                header = 'Available Units',
                icon = 'fas fa-home',
                isMenuHeader = true
            }
        }

        if units and #units > 0 then
            for _, unit in ipairs(units) do

                local tenantCount = unit.tenantCount or 0
                local availableSlots = 3 - tenantCount
                local tenantStatus = tenantCount == 3 and "Fully Occupied" or "Vacant | Avaible Slots: " .. availableSlots
                local rentCost = unit.rentCost

                table.insert(elements, {
                    header = "Unit " .. unit.unitID  .. " | Rent Cost: $" .. rentCost,
                    txt = "Status: " .. tenantStatus .. " | Tenants: " .. tenantCount,
                    icon = 'fas fa-building',
                    params = {
                        event = 'smb_properties:client:RentUnit',
                        args = {
                            unitID = unit.unitID,
                            propertyName = propertyName,
                            rentCost = rentCost,
                        }
                    }
                })
            end
        else
            table.insert(elements, {
                header = "No available units in this property.",
                txt = "All units are occupied by tenants.",
                icon = 'fas fa-user-slash'
            })
        end

        exports['qb-menu']:openMenu(elements)
    end, propertyName)
end)

RegisterNetEvent('smb_properties:client:ManageUnit', function(data)
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
            header = 'Tenant List',
            txt = 'View list of tenants',
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

RegisterNetEvent('smb_properties:client:ManageTenantUnit')
AddEventHandler('smb_properties:client:ManageTenantUnit', function(unit)
    local unit = unit.unit
    local manageUnitMenu = {
        {
            header = "Manage Unit " .. unit.unitID,
            icon = 'fas fa-building',
            isMenuHeader = true
        },
        {
            header = "Pay Amount Due",
            txt = "Pay your outstanding amount.",
            icon = 'fas fa-money-bill-wave',
            params = {
                event = 'smb_properties:client:PayAmountDue',
                args = {
                    tenantID = unit.tenantID
                }
            }
        },
        {
            header = "Terminate Lease",
            txt = "Stop renting this unit.",
            icon = 'fas fa-sign-out-alt',
            params = {
                event = 'smb_properties:client:TerminateLease',
                args = {
                    tenantID = unit.tenantID
                }
            }
        }
    }

    exports['qb-menu']:openMenu(manageUnitMenu)
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

RegisterNetEvent('smb_properties:client:ShowRentedUnits')
AddEventHandler('smb_properties:client:ShowRentedUnits', function(data)
    local propertyName = data.propertyName

    QBCore.Functions.TriggerCallback('smb_properties:server:GetRentedUnits', function(units, error)
        if not units then
            print(error or "Unknown error occurred!")
            return
        end
        
        local rentedUnitsMenu = {
            {
                header = "Units I'm Renting",
                icon = 'fas fa-home',
                isMenuHeader = true
            }
        }
    
        for _, unit in ipairs(units) do
            table.insert(rentedUnitsMenu, {
                header = "Unit ID: " .. unit.unitID .. " | Tenant ID: " .. unit.tenantID .. " | Total Amount Due: " .. unit.totalAmountDue,
                txt = "Click to manage this unit.",
                icon = 'fas fa-building',
                params = {
                    event = 'smb_properties:client:ManageTenantUnit',
                    args = {
                        unit = unit
                    }
                }
            })
        end
    
        exports['qb-menu']:openMenu(rentedUnitsMenu)
    end, propertyName)
end)

RegisterNetEvent('smb_properties:client:PayAmountDue')
AddEventHandler('smb_properties:client:PayAmountDue', function(unit)
    local tenantID = unit.tenantID  

    QBCore.Functions.TriggerCallback('smb_properties:server:FetchAmountDue', function(amountDue)
        if amountDue and amountDue > 0 then
            local dialog = exports['qb-input']:ShowInput({
                header = "Amount Due",
                submitText = "Pay",
                inputs = {
                    {
                        text = "You have an outstanding amount of $" .. amountDue .. ". Enter amount to pay:",
                        name = "payAmount",
                        type = "number",
                        isRequired = true,
                        default = amountDue 
                    }
                },
            })

            if dialog ~= nil and dialog.payAmount ~= nil then
                local amountToPay = tonumber(dialog.payAmount)
                if amountToPay and amountToPay > 0 and amountToPay <= amountDue then
                    QBCore.Functions.TriggerCallback('smb_properties:server:PayAmountDue', function(success, msg) 
                        if success then
                            QBCore.Functions.Notify('You have paid the amount of $' .. amountToPay, 'success')
                        else
                            QBCore.Functions.Notify(msg, 'error')
                        end
                    end, tenantID, amountToPay)
                else
                    QBCore.Functions.Notify('Invalid amount entered.', 'error')
                end
            else
                QBCore.Functions.Notify('Payment cancelled.', 'error')
            end
        else
            QBCore.Functions.Notify('You have no outstanding amount to pay.', 'info')
        end
    end, tenantID)
end)

RegisterNetEvent('smb_properties:client:ChangeOutfit', function()
    TriggerServerEvent("InteractSound_SV:PlayOnSource", "Clothes1", 0.4)
    TriggerEvent('qb-clothing:client:openOutfitMenu')
end)

RegisterNetEvent('smb_properties:client:RentUnit')
AddEventHandler('smb_properties:client:RentUnit', function(data)
    local unitID = data.unitID
    local propertyName = data.propertyName
    local rentCost = data.rentCost

    QBCore.Functions.TriggerCallback('smb_properties:server:RentUnit', function(success, message)
        if success then
            QBCore.Functions.Notify("Successfully rented the unit! Monthly rent: $" .. rentCost, "success")
        else
            QBCore.Functions.Notify(message, "error")
        end
    end, unitID, propertyName)
end)
