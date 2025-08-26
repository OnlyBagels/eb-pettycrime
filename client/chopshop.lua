lib.locale()

local Config = require'shared.config'
local Systems = require'shared.systems'

local activeVehicles = {}
local isInChopZone = false
local lastChopshopTime = 0
local lastChopAttempt = 0
local CHOP_ACTION_COOLDOWN = 3000

local function AreAllPartsRemoved(partsRemoved)
    local totalParts = 0
    for _ in pairs(Config.chopshop.parts) do
        totalParts = totalParts + 1
    end
    
    local removedCount = 0
    for _, removed in pairs(partsRemoved) do
        if removed then removedCount = removedCount + 1 end
    end

    return removedCount >= totalParts
end

local function IsValidChopVehicle(vehicle)
    if not DoesEntityExist(vehicle) then return false end
    
    local vehicleClass = GetVehicleClass(vehicle)
    if vehicleClass == 18 or vehicleClass == 19 or vehicleClass == 15 or vehicleClass == 16 then
        return false
    end
    
    for i = -1, GetVehicleMaxNumberOfPassengers(vehicle) do
        if GetPedInVehicleSeat(vehicle, i) ~= 0 then
            return false
        end
    end
    
    if Config.chopshop.requireUnlocked and GetVehicleDoorLockStatus(vehicle) > 1 then
        return false
    end
    
    return true
end

local function RemoveVehiclePart(vehicle, partIndex)
    if partIndex <= 5 then
        SetVehicleDoorBroken(vehicle, partIndex, true)
    elseif partIndex >= 6 and partIndex <= 9 then
        BreakOffVehicleWheel(vehicle, partIndex - 6, true, true, true, false)
    elseif partIndex >= 10 then
        SetVehicleBodyHealth(vehicle, GetVehicleBodyHealth(vehicle) - 200)
        local dimensions = GetModelDimensions(GetEntityModel(vehicle))
        if partIndex == 10 then
            SetVehicleDamage(vehicle, 0.0, -2.5, 0.0, 200.0, 100.0, true)
        else
            SetVehicleDamage(vehicle, 0.0, dimensions.y - 0.5, 0.0, 200.0, 100.0, true)
        end
    end
    
    SetVehicleDirtLevel(vehicle, math.min(GetVehicleDirtLevel(vehicle) + 1.5, 15.0))
    
    if partIndex >= 10 then
        SetVehicleBodyHealth(vehicle, math.max(GetVehicleBodyHealth(vehicle) - 100, 100))
    end
end

local function StartChoppingPart(vehicle, partIndex, partLabel)
    if (GetGameTimer() - lastChopAttempt) < CHOP_ACTION_COOLDOWN then
        lib.notify({
            title = locale('chopshop_title'),
            description = locale('too_fast'),
            type = 'error'
        })
        return
    end
    
    if not DoesEntityExist(vehicle) then
        lib.notify({
            title = locale('chopshop_title'),
            description = locale('vehicle_no_exists'),
            type = 'error'
        })
        return
    end
    
    if not isInChopZone then
        lib.notify({
            title = locale('chopshop_title'),
            description = locale('must_be_in_chopshop'),
            type = 'error'
        })
        return
    end
    
    local playerCoords = GetEntityCoords(cache.ped)
    local vehicleCoords = GetEntityCoords(vehicle)
    if #(playerCoords - vehicleCoords) > 10.0 then
        lib.notify({
            title = locale('chopshop_title'),
            description = locale('too_far_from_vehicle'),
            type = 'error'
        })
        return
    end
    
    local currentTime = GetGameTimer()
    local cooldownTime = Config.chopshop.cooldown * 60 * 1000
    
    if currentTime - lastChopshopTime < cooldownTime and lastChopshopTime > 0 then
        return
    end
    
    local vehicleStateBag = Entity(vehicle).state
    if not activeVehicles[vehicle] or (vehicleStateBag.partsRemoved and vehicleStateBag.partsRemoved[partIndex]) then
        lib.notify({
            title = locale('chopshop_title'),
            description = locale('part_already_removed'),
            type = 'error'
        })
        return
    end
    
    lastChopAttempt = GetGameTimer()
    
    if not activeVehicles[vehicle].dispatchSent then
        if math.random(1, 100) <= Config.chopshop.dispatchChance then
            Systems.Dispatch.sendTheftDispatch(vehicleCoords, 'chopshop')
        end
        activeVehicles[vehicle].dispatchSent = true
    end
    
    local animDict = Config.chopshop.chainsaw.dict
    local animName = Config.chopshop.chainsaw.clip
    local propName = Config.chopshop.chainsaw.prop
    
    lib.requestAnimDict(animDict)
    local propHash = GetHashKey(propName)
    lib.requestModel(propHash)
    
    if Config.chopshop.effects?.sparkEffect then
        lib.requestNamedPtfxAsset(Config.chopshop.effects.sparkEffect.dict)
    end
    
    local playerPed = cache.ped
    
    local soundId = nil
    if Config.chopshop.effects?.chainsawSound then
        soundId = GetSoundId()
        PlaySoundFromEntity(
            soundId,
            Config.chopshop.effects.chainsawSound.name,
            playerPed,
            Config.chopshop.effects.chainsawSound.set,
            false,
            0
        )
    end
    
    Systems.Witness.checkForWitnesses(playerCoords, 'chopshop')
    
    local success = lib.progressCircle({
        duration = Config.robberyTime.chopshop,
        position = 'bottom',
        label = locale('dismantling_part', partLabel),
        canCancel = true,
        disable = { car = true, move = false, combat = true },
        anim = { dict = animDict, clip = animName, flag = 1 },
        prop = {
            model = propHash,
            bone = Config.chopshop.chainsaw.propBone,
            pos = {
                x = Config.chopshop.chainsaw.propPlacement.x,
                y = Config.chopshop.chainsaw.propPlacement.y,
                z = Config.chopshop.chainsaw.propPlacement.z
            },
            rot = {
                x = Config.chopshop.chainsaw.propPlacement.xRot,
                y = Config.chopshop.chainsaw.propPlacement.yRot,
                z = Config.chopshop.chainsaw.propPlacement.zRot
            }
        }
    })
    
    if soundId then
        StopSound(soundId)
        ReleaseSoundId(soundId)
    end
    
    StopAnimTask(playerPed, animDict, animName, 1.0)
    
    if success then
        if not DoesEntityExist(vehicle) then
            lib.notify({
                title = locale('chopshop_title'),
                description = locale('vehicle_disappeared'),
                type = 'error'
            })
            return
        end
        
        RemoveVehiclePart(vehicle, partIndex)
        
        activeVehicles[vehicle].partsRemoved[partIndex] = true
        
        local currentParts = vehicleStateBag.partsRemoved or {}
        currentParts[partIndex] = true
        vehicleStateBag:set('partsRemoved', currentParts, true)
        
        UpdateVehicleTargetZones(vehicle)
        
        local vehicleModel = GetEntityModel(vehicle)
        TriggerServerEvent('pc:action:1', partIndex, vehicleModel)
        
        if AreAllPartsRemoved(activeVehicles[vehicle].partsRemoved) then
            lastChopshopTime = GetGameTimer()
            
            lib.notify({
                title = locale('chopshop_title'),
                description = locale('vehicle_dismantled'),
                type = 'success'
            })
            
            RemoveVehicleTargetZones(vehicle)
            vehicleStateBag:set('fullyStripped', true, true)
            
            SetTimeout(Config.chopshop.vehicleDeleteDelay, function()
                if DoesEntityExist(vehicle) then
                    if not IsPedAPlayer(GetPedInVehicleSeat(vehicle, -1)) then
                        DeleteEntity(vehicle)
                    end
                end
                activeVehicles[vehicle] = nil
            end)
        end
    else
        lib.notify({
            title = locale('chopshop_title'),
            description = locale('dismantling_cancelled'),
            type = 'error'
        })
    end
end

function AddVehicleTargetZones(vehicle)
    if not DoesEntityExist(vehicle) then return end
    
    local vehicleData = activeVehicles[vehicle]
    if not vehicleData or vehicleData.targetZonesAdded then return end
    
    local options = {}
    
    for partIndex, partConfig in pairs(Config.chopshop.parts) do
        local vehicleStateBag = Entity(vehicle).state
        local partsRemovedLocal = vehicleData.partsRemoved[partIndex]
        local partsRemovedState = vehicleStateBag.partsRemoved and vehicleStateBag.partsRemoved[partIndex]
        
        if not partsRemovedLocal and not partsRemovedState then
            local boneIndex = GetEntityBoneIndexByName(vehicle, partConfig.bone)
            if boneIndex ~= -1 then
                table.insert(options, {
                    name = 'chop_part_' .. partIndex,
                    icon = 'fas fa-cut',
                    label = locale('dismantle_part', locale(partConfig.label)),
                    bones = {partConfig.bone},
                    distance = 2.5,
                    onSelect = function()
                        StartChoppingPart(vehicle, partIndex, locale(partConfig.label))
                    end,
                    canInteract = function()
                        local playerCoords = GetEntityCoords(cache.ped)
                        local vehCoords = GetEntityCoords(vehicle)
                        local distance = #(playerCoords - vehCoords)
                        
                        return isInChopZone and
                               distance <= 10.0 and
                               DoesEntityExist(vehicle) and
                               not (vehicleData.partsRemoved[partIndex] or 
                                   (Entity(vehicle).state.partsRemoved and Entity(vehicle).state.partsRemoved[partIndex])) and
                               (GetGameTimer() - lastChopshopTime >= (Config.chopshop.cooldown * 60 * 1000) or lastChopshopTime == 0)
                    end
                })
            end
        end
    end
    
    if #options > 0 then
        exports.ox_target:addLocalEntity(vehicle, options)
        vehicleData.targetZonesAdded = true
    end
end

function RemoveVehicleTargetZones(vehicle)
    if DoesEntityExist(vehicle) then
        exports.ox_target:removeLocalEntity(vehicle)
    end
end

function UpdateVehicleTargetZones(vehicle)
    if not activeVehicles[vehicle] then return end
    
    RemoveVehicleTargetZones(vehicle)
    activeVehicles[vehicle].targetZonesAdded = false
    AddVehicleTargetZones(vehicle)
end

CreateThread(function()
    while true do
        Wait(1000)
        local playerCoords = GetEntityCoords(cache.ped)
        local dist = #(playerCoords - Config.chopshop.zone.center)
        
        isInChopZone = dist <= Config.chopshop.zone.radius
    end
end)

CreateThread(function()
    local sleep = 2000
    while true do
        Wait(sleep)
        
        if not isInChopZone then
            sleep = 2000
            goto continue
        end
        
        local playerPed = cache.ped
        local playerCoords = GetEntityCoords(playerPed)
        local vehicle = GetClosestVehicle(playerCoords.x, playerCoords.y, playerCoords.z, 10.0, 0, 70)
        
        if not vehicle or vehicle == 0 then
            sleep = 1000
            goto continue
        end
        
        if not IsValidChopVehicle(vehicle) then
            sleep = 1000
            goto continue
        end
        
        if not activeVehicles[vehicle] then
            activeVehicles[vehicle] = {
                entity = vehicle,
                partsRemoved = {},
                timeAdded = GetGameTimer(),
                targetZonesAdded = false,
                dispatchSent = false
            }
            
            local vehicleStateBag = Entity(vehicle).state
            vehicleStateBag:set('partsRemoved', {}, true)
            vehicleStateBag:set('chopshopVehicle', true, true)
            
            AddVehicleTargetZones(vehicle)
        end
        
        sleep = 1000
        ::continue::
    end
end)

CreateThread(function()
    while true do
        Wait(60000)
        
        local currentTime = GetGameTimer()
        for vehicle, data in pairs(activeVehicles) do
            if not DoesEntityExist(vehicle) or (currentTime - data.timeAdded) > 600000 then
                RemoveVehicleTargetZones(vehicle)
                
                if DoesEntityExist(vehicle) then
                    local vehicleStateBag = Entity(vehicle).state
                    vehicleStateBag:set('chopshopVehicle', nil, true)
                    vehicleStateBag:set('partsRemoved', nil, true)
                    vehicleStateBag:set('fullyStripped', nil, true)
                end
                
                activeVehicles[vehicle] = nil
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        for vehicle in pairs(activeVehicles) do
            RemoveVehicleTargetZones(vehicle)
            
            if DoesEntityExist(vehicle) then
                local vehicleStateBag = Entity(vehicle).state
                vehicleStateBag:set('chopshopVehicle', nil, true)
                vehicleStateBag:set('partsRemoved', nil, true)
                vehicleStateBag:set('fullyStripped', nil, true)
            end
        end
        activeVehicles = {}
    end
end)

if Config.chopshop.showBlip then
    CreateThread(function()
        local blip = AddBlipForCoord(
            Config.chopshop.zone.center.x,
            Config.chopshop.zone.center.y,
            Config.chopshop.zone.center.z
        )
        SetBlipSprite(blip, 380)
        SetBlipScale(blip, 0.8)
        SetBlipColour(blip, 1)
        SetBlipAsShortRange(blip, true)
        BeginTextCommandSetBlipName("STRING")
        AddTextComponentString(locale('chopshop_blip_name'))
        EndTextCommandSetBlipName(blip)
    end)
end

RegisterNetEvent('chopshop:notify')
AddEventHandler('chopshop:notify', function(data)
    lib.notify(data)
end)

AddStateBagChangeHandler('partsRemoved', nil, function(bagName, key, value, reserved, replicated)
    if replicated then return end
    
    local entityId = GetEntityFromStateBagName(bagName)
    if not entityId or entityId == 0 then return end
    
    local vehicle = entityId
    if not DoesEntityExist(vehicle) then return end
    
    if activeVehicles[vehicle] then
        activeVehicles[vehicle].partsRemoved = value or {}
        
        if activeVehicles[vehicle].targetZonesAdded then
            UpdateVehicleTargetZones(vehicle)
        end
    end
end)

AddStateBagChangeHandler('fullyStripped', nil, function(bagName, key, value, reserved, replicated)
    if not value or replicated then return end
    
    local entityId = GetEntityFromStateBagName(bagName)
    if not entityId or entityId == 0 then return end
    
    local vehicle = entityId
    if not DoesEntityExist(vehicle) then return end
    
    if activeVehicles[vehicle] then
        RemoveVehicleTargetZones(vehicle)
        activeVehicles[vehicle] = nil
    end
end)