local QBCore = exports['qb-core']:GetCoreObject()
local isInsizeZone = false
local displayDistance = 2.0
local currentProperty = nil

local function IsPlayerNearCoord(coord)
    local playerCoord = GetEntityCoords(PlayerPedId())
    local distance = #(playerCoord - vector3(coord.x, coord.y, coord.z))
    return distance <= displayDistance
end

CreateThread(function()
    for propertyName, property in pairs(Config.Properties) do
        -- local polyzoneCoords

        -- if property.type == "house" or property.type == "mansion" then
        --     polyzoneCoords = property.polyzone
        -- end

        -- elseif property.type == "hotel" then
        --     for roomId, room in pairs(property.rooms) do
        --         polyzoneCoords = {room.coords}
        --     end
        -- end

        if property.polyZone then
            local zone = PolyZone:Create(property.polyZone, {
                name = propertyName,
                debugPoly = true,
                minZ = property.coords.z - 10.0, 
                maxZ = property.coords.z + 7.0
            })

            zone:onPlayerInOut(function(isPointInside)
                if isPointInside then
                    insideZone = true
                    currentProperty = property
                else
                    insideZone = false
                    currentProperty = nil
                end
            end)
        end
    end
end)

CreateThread(function()
    local waitTime = 500
    local actionType = nil
    local actionPropertyId = nil
    local actionUnitId = nil

    while true do
        if insideZone and currentProperty then
            local isNearSomething = false
            local property = currentProperty
            local propertyType = property.type

            if property.stash and IsPlayerNearCoord(property.stash) then
                exports['qb-core']:DrawText("Press [E] to access property stash")
                actionType = "stash"
                actionPropertyId = currentProperty
                isNearSomething = true
            end
            
            for _, door in ipairs(property.doors or {}) do
                if IsPlayerNearCoord(door.coords) then
                    exports['qb-core']:DrawText("Press [E] to use property door")
                    actionType = "door"
                    actionPropertyId = currentProperty
                    isNearSomething = true
                    break
                end
            end

            if propertyType == "house" then
            elseif propertyType == "mansion" then
                for unitId, unit in pairs(property.units or {}) do
                    if unit.stash and IsPlayerNearCoord(unit.stash) then
                        exports['qb-core']:DrawText("Press [E] to access unit stash")
                        actionType = "unit_stash"
                        actionPropertyId = currentProperty
                        actionUnitId = unitId
                        isNearSomething = true
                        break
                    elseif unit.door and IsPlayerNearCoord(unit.door.coords) then
                        exports['qb-core']:DrawText("Press [E] to use unit door")
                        actionType = "unit_door"
                        actionPropertyId = currentProperty
                        actionUnitId = unitId
                        isNearSomething = true
                        break
                    end
                end
            elseif propertyType == "motel" then
                for unitId, unit in ipairs(property.units or {}) do
                    if unit.stash and IsPlayerNearCoord(unit.stash) then
                        exports['qb-core']:DrawText("Press [E] to unlock door")
                        actionType = "unit_stash"
                        actionPropertyId = currentProperty
                        actionUnitId = unitId
                        isNearSomething = true
                        break
                    elseif unit.door and IsPlayerNearCoord(unit.door.coords) then
                        exports['qb-core']:DrawText("Press [E] to unlock door")
                        actionType = "unit_door"
                        actionPropertyId = currentProperty
                        actionUnitId = unitId
                        isNearSomething = true
                        break
                    end
                end
            end

            if IsControlJustPressed(0, 38) and actionType and actionPropertyId then
                if actionType == "stash" then
                    QBCore.Functions.Notify('Accessing property stash!', 'success')
                elseif actionType == "door" then
                    QBCore.Functions.Notify('Using property door!', 'success')
                elseif actionType == "unit_stash" then
                    QBCore.Functions.Notify('Accessing unit stash!', 'success')
                elseif actionType == "unit_door" then
                    QBCore.Functions.Notify('Using unit door!', 'success')
                end
            end

            if not isNearSomething then
                actionType = nil
                actionPropertyId = nil
                actionUnitId = nil
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






-- CreateThread(function()
--     local waitTime = 500

--     while true do
--         print("This loop is running")
--         if insideZone and currentProperty then
--             local isNearSomething = false

--             for roomId, room in pairs(currentProperty.rooms) do
--                 if IsPlayerNearCoord(room.stash) then
--                     exports['qb-core']:DrawText("Press [E] to access stash")
--                     isNearSomething = true
--                     waitTime = 5
--                     break 
--                 elseif IsPlayerNearCoord(room.door.coords) then
--                     exports['qb-core']:DrawText("Press [E] to use door")
--                     isNearSomething = true
--                     waitTime = 5
--                     break
--                 else
--                     waitTime = 500 
--                 end
--             end

--             if not isNearSomething then
--                 waitTime = 500
--             end
--         else
--             waitTime = 1000
--         end

--         Wait(waitTime)
--     end
-- end)
