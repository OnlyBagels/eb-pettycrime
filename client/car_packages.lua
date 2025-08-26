lib.locale()

local Config = require'shared.config'
local Systems = require'shared.systems'

local objects = {}
local packageVehicles = {}
local trackedVehicles = {}
local actionCooldowns = { lastStealAttempt = 0, STEAL_COOLDOWN = 3000 }

local validSeats = { 'seat_pside_f', 'seat_dside_r', 'seat_pside_r' }
local seatMappings = {
    windows = { ['seat_pside_f'] = 1, ['seat_dside_r'] = 2, ['seat_pside_r'] = 3 },
    doors = { ['seat_pside_f'] = 1, ['seat_dside_r'] = 2, ['seat_pside_r'] = 3 },
    names = { ['seat_pside_f'] = locale('front_passenger'), ['seat_dside_r'] = locale('rear_driver'), ['seat_pside_r'] = locale('rear_passenger') }
}

local debugMarkers = {}

local function getSafeMapping(seatName, mappingType, fallback)
    return seatMappings[mappingType][seatName] or fallback
end

local function getValidSeats(entity)
    local validSeatList = {}
    
    for i = 1, #validSeats do
        local seatName = validSeats[i]
        local boneIndex = GetEntityBoneIndexByName(entity, seatName)
        
        if boneIndex and boneIndex ~= -1 and boneIndex ~= 0 then
            validSeatList[#validSeatList + 1] = { name = seatName, boneIndex = boneIndex }
        end
    end
    
    return validSeatList
end

local function isVehicleDoorOpen(vehicle, doorIndex)
    return GetVehicleDoorAngleRatio(vehicle, doorIndex) > 0.1
end

local function isValidPropModel(modelHash)
    if not modelHash then return false end
    
    if type(modelHash) == "string" then
        modelHash = GetHashKey(modelHash)
    end
    
    if IsModelValid(modelHash) and not IsModelAVehicle(modelHash) then
        return true
    end
    
    return false
end

local TargetManager = {
    createPackageTarget = function(vehicle, packageData)
        local targetId = 'package_vehicle_' .. vehicle
        local doorName = getSafeMapping(packageData.seatName, 'names', locale('front_passenger'))
        
        exports.ox_target:addLocalEntity(vehicle, {
            {
                name = targetId .. '_steal',
                icon = 'fas fa-hand-paper',
                label = locale('steal_package_from', doorName),
                distance = Config.packageSettings.interactionDistance,
                canInteract = function()
                    if not packageData.windowIndex or not packageData.doorIndex then return false end
                    
                    local windowBroken = not IsVehicleWindowIntact(vehicle, packageData.windowIndex)
                    local doorOpen = isVehicleDoorOpen(vehicle, packageData.doorIndex)
                    local canSteal = (GetGameTimer() - actionCooldowns.lastStealAttempt) >= actionCooldowns.STEAL_COOLDOWN
                    
                    return (windowBroken or doorOpen) and DoesEntityExist(packageData.packageEntity) and canSteal
                end,
                onSelect = function()
                    print("DEBUG: onSelect triggered for vehicle", vehicle)
                    
                    local currentTime = GetGameTimer()
                    if (currentTime - actionCooldowns.lastStealAttempt) < actionCooldowns.STEAL_COOLDOWN then
                        if Config.notifications then
                            lib.notify({ title = locale('too_fast'), type = 'error' })
                        end
                        return
                    end
                    
                    actionCooldowns.lastStealAttempt = currentTime
                    
                    if not DoesEntityExist(vehicle) or not Entity(vehicle).state.hasPackage then
                        if Config.notifications then
                            lib.notify({ title = locale('invalid_target'), type = 'error' })
                        end
                        return
                    end
                    
                    local playerCoords = GetEntityCoords(cache.ped)
                    local vehicleCoords = GetEntityCoords(vehicle)
                    if #(playerCoords - vehicleCoords) > Config.packageSettings.interactionDistance * 1.5 then
                        if Config.notifications then
                            lib.notify({ title = locale('too_far'), type = 'error' })
                        end
                        return
                    end
                    
                    local windowBroken = not IsVehicleWindowIntact(vehicle, packageData.windowIndex)
                    local doorOpen = isVehicleDoorOpen(vehicle, packageData.doorIndex)
                    
                    local progressConfig = {
                        label = doorOpen and locale('grabbing_package_door') or locale('reaching_through_window'),
                        duration = Config.robberyTime.carpackage,
                        canCancel = true,
                        position = 'bottom',
                        disable = { car = true, move = true, combat = true },
                        anim = { dict = 'mini@repair', clip = 'fixing_a_ped' }
                    }
                    
                    Systems.Witness.checkForWitnesses(playerCoords, 'package_theft')
                    
                    if lib.progressCircle(progressConfig) then
                        local success, message, item, amount = lib.callback.await(
                            'eb-pettycrime-package:server:StealPackage',
                            false,
                            NetworkGetNetworkIdFromEntity(vehicle)
                        )
                        
                        if success then
                            TargetManager.removePackageTarget(vehicle)
                            packageVehicles[vehicle] = nil
                            Systems.Dispatch.sendTheftDispatch(vehicleCoords, 'package_theft')
                            
                            if Config.notifications then
                                lib.notify({
                                    title = locale('package_stolen'),
                                    description = locale('package_stolen_desc', amount or 1, item or 'item'),
                                    type = 'success'
                                })
                            end
                        else
                            if Config.notifications then
                                lib.notify({
                                    title = locale('cannot_steal_package'),
                                    description = message or locale('unknown_error'),
                                    type = 'error',
                                    duration = 4000
                                })
                            end
                        end
                    end
                end
            }
        })
        
        return targetId
    end,
    
    removePackageTarget = function(vehicle)
        local targetId = 'package_vehicle_' .. vehicle
        exports.ox_target:removeLocalEntity(vehicle, targetId .. '_steal')
    end
}

local PackageManager = {
    cleanupPackage = function(vehicle, packageEntity)
        TargetManager.removePackageTarget(vehicle)
        
        if packageEntity and DoesEntityExist(packageEntity) then
            DeleteEntity(packageEntity)
            objects[packageEntity] = nil
        end
        
        if debugMarkers[vehicle] then
            debugMarkers[vehicle] = nil
        end
        
        packageVehicles[vehicle] = nil
        trackedVehicles[vehicle] = nil
    end,
    
    createPackage = function(vehicle, packageData)
        local modelHash = packageData.model
        
        if not isValidPropModel(modelHash) then
            print("ERROR: Invalid prop model hash:", modelHash, "- skipping package creation")
            return nil
        end
        
        if not lib.requestModel(modelHash, 5000) then
            print("ERROR: Failed to load model:", modelHash)
            return nil
        end
        
        local coords = GetEntityCoords(vehicle)
        local package = CreateObject(modelHash, coords.x, coords.y, coords.z - 5, false, true, false)
        SetModelAsNoLongerNeeded(modelHash)
        
        if not DoesEntityExist(package) then 
            print("ERROR: Failed to create package object")
            return nil 
        end
        
        SetDisableFragDamage(package, true)
        SetEntityCollision(package, false, false)
        SetEntityNoCollisionEntity(package, vehicle, false)
        
        AttachEntityToEntity(
            package, vehicle, packageData.boneID,
            packageData.offset and packageData.offset.x or 0.0,
            packageData.offset and packageData.offset.y or 0.0,
            packageData.offset and packageData.offset.z or 0.0,
            0.0, 0.0, packageData.rotation or 0.0,
            0.0, false, false, false, false, 2, true, false
        )
        
        objects[package] = true
        
        if Config.debug then
            print("DEBUG CLIENT: Package created on vehicle", vehicle, "with entity", package, "model:", modelHash)
            debugMarkers[vehicle] = {
                vehicle = vehicle,
                package = package,
                coords = coords
            }
        end
        
        return package
    end
}

AddStateBagChangeHandler('loadPackage', nil, function(bagName, key, value, reserved, replicated)
    if replicated then return end
    
    local vehicle = lib.waitFor(function()
        local e = GetEntityFromStateBagName(bagName)
        if e > 0 and DoesEntityExist(e) then return e end
    end, 'Failed to get vehicle from statebag', 5000)
    
    if not vehicle then return end
    
    if Config.debug then
        print("DEBUG CLIENT: StateBag loadPackage changed for vehicle", vehicle, "value:", value and "PACKAGE DATA" or "NIL")
    end
    
    if not value then
        if packageVehicles[vehicle] then
            PackageManager.cleanupPackage(vehicle, packageVehicles[vehicle].packageEntity)
        end
        return
    end
    
    if not value.model or not value.boneID or not value.seatName then return end
    
    trackedVehicles[vehicle] = true
    
    local package = PackageManager.createPackage(vehicle, value)
    if not package then return end
    
    local packageData = {
        packageEntity = package,
        seatName = value.seatName,
        windowIndex = getSafeMapping(value.seatName, 'windows', 1),
        doorIndex = getSafeMapping(value.seatName, 'doors', 1),
        doorName = getSafeMapping(value.seatName, 'names', locale('front_passenger'))
    }
    
    packageVehicles[vehicle] = packageData
    TargetManager.createPackageTarget(vehicle, packageData)
    
    CreateThread(function()
        local checkInterval = 1000
        local maxChecks = 300
        local checks = 0
        
        while DoesEntityExist(vehicle) and DoesEntityExist(package) and checks < maxChecks do
            local state = Entity(vehicle).state
            if not state.hasPackage then break end
            
            if not IsEntityAttachedToEntity(package, vehicle) then break end
            
            if checks > 60 then checkInterval = 5000 end
            
            Wait(checkInterval)
            checks = checks + 1
        end
        
        PackageManager.cleanupPackage(vehicle, package)
    end)
end)

AddStateBagChangeHandler('hasPackage', nil, function(bagName, key, value, reserved, replicated)
    if replicated or value then return end
    
    local vehicle = GetEntityFromStateBagName(bagName)
    if vehicle and vehicle > 0 and DoesEntityExist(vehicle) and packageVehicles[vehicle] then
        PackageManager.cleanupPackage(vehicle, packageVehicles[vehicle].packageEntity)
    end
end)

if Config.debug then
    CreateThread(function()
        while true do
            Wait(0)
            
            local playerCoords = GetEntityCoords(cache.ped)
            
            for vehicle, markerData in pairs(debugMarkers) do
                if DoesEntityExist(vehicle) and DoesEntityExist(markerData.package) then
                    local vehCoords = GetEntityCoords(vehicle)
                    local distance = #(playerCoords - vehCoords)
                    
                    if distance <= 100.0 then
                        DrawMarker(
                            1,
                            vehCoords.x, vehCoords.y, vehCoords.z + 2.0,
                            0.0, 0.0, 0.0,
                            0.0, 0.0, 0.0,
                            1.0, 1.0, 1.0,
                            255, 0, 0, 200,
                            false, true, 2,
                            false, false, false
                        )
                        
                        if distance <= 25.0 then
                            local onScreen, screenX, screenY = GetScreenCoordFromWorldCoord(vehCoords.x, vehCoords.y, vehCoords.z + 1.5)
                            if onScreen then
                                SetTextScale(0.35, 0.35)
                                SetTextFont(4)
                                SetTextColour(255, 255, 255, 255)
                                SetTextCentre(true)
                                SetTextOutline()
                                DisplayText(screenX, screenY, "PACKAGE HERE")
                            end
                        end
                    end
                else
                    debugMarkers[vehicle] = nil
                end
            end
        end
    end)
end

CreateThread(function()
    while true do
        Wait(5000)
        
        local toCleanup = {}
        for vehicle in pairs(trackedVehicles) do
            if not DoesEntityExist(vehicle) then
                toCleanup[#toCleanup + 1] = vehicle
            end
        end
        
        for i = 1, #toCleanup do
            local vehicle = toCleanup[i]
            if packageVehicles[vehicle] then
                PackageManager.cleanupPackage(vehicle, packageVehicles[vehicle].packageEntity)
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if cache.resource ~= resourceName then return end
    
    for object in pairs(objects) do
        if DoesEntityExist(object) then
            DeleteEntity(object)
        end
    end
    
    for vehicle in pairs(packageVehicles) do
        TargetManager.removePackageTarget(vehicle)
    end
    
    objects = {}
    packageVehicles = {}
    trackedVehicles = {}
    debugMarkers = {}
end)