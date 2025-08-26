lib.locale()

local Config = require'shared.config'
local Systems = require'shared.systems'

-- State tracking
local spawnedPackages = {}
local packageObjects = {}
local lastStealAttempt = 0

local function debugPrint(msg)
    if Config.debug then
        print("^3[PORCH-CLIENT]^0 " .. tostring(msg))
    end
end

local function createPackageObject(packageId, coords, modelName)
    debugPrint("Creating package: " .. packageId .. " at " .. tostring(coords))
    
    local modelHash = GetHashKey(modelName)
    if not lib.requestModel(modelHash, 10000) then
        debugPrint("Failed to load model: " .. modelName)
        return nil
    end
    
    local obj = CreateObject(modelHash, coords.x, coords.y, coords.z, false, true, false)
    SetModelAsNoLongerNeeded(modelHash)
    
    if not DoesEntityExist(obj) then
        debugPrint("Failed to create object")
        return nil
    end
    
    SetDisableFragDamage(obj, true)
    SetEntityCollision(obj, true, true)
    FreezeEntityPosition(obj, true)
    PlaceObjectOnGroundProperly(obj)
    
    packageObjects[obj] = packageId
    spawnedPackages[packageId] = {
        entity = obj,
        coords = coords,
        model = modelName
    }
    
    debugPrint("Package created successfully: entity " .. obj)
    return obj
end

local function addPackageTarget(entity, packageId)
    debugPrint("Adding target for package: " .. packageId .. " entity: " .. entity)
    
    exports.ox_target:addLocalEntity(entity, {
        {
            name = 'steal_package_' .. packageId,
            icon = 'fas fa-box-open',
            label = locale('steal_porch_package'),
            distance = 2.5,
            canInteract = function()
                local now = GetGameTimer()
                local canSteal = (now - lastStealAttempt) > 2000
                debugPrint("Can interact: " .. tostring(canSteal) .. " (cooldown: " .. (now - lastStealAttempt) .. ")")
                return canSteal
            end,
            onSelect = function()
                debugPrint("Target selected for package: " .. packageId)
                stealPackage(packageId)
            end
        }
    })
    
    debugPrint("Target added successfully")
end

local function removePackageTarget(entity, packageId)
    debugPrint("Removing target for package: " .. packageId)
    if DoesEntityExist(entity) then
        exports.ox_target:removeLocalEntity(entity, 'steal_package_' .. packageId)
    end
end

local function removePackageObject(packageId)
    debugPrint("Removing package: " .. packageId)
    
    local packageData = spawnedPackages[packageId]
    if not packageData then
        debugPrint("Package data not found: " .. packageId)
        return
    end
    
    local entity = packageData.entity
    
    removePackageTarget(entity, packageId)
    
    if DoesEntityExist(entity) then
        DeleteEntity(entity)
        packageObjects[entity] = nil
    end
    
    spawnedPackages[packageId] = nil
    debugPrint("Package removed: " .. packageId)
end

function stealPackage(packageId)
    debugPrint("Attempting to steal package: " .. packageId)
    
    local now = GetGameTimer()
    if (now - lastStealAttempt) < 2000 then
        lib.notify({
            title = locale('too_fast'),
            type = 'error'
        })
        return
    end
    
    lastStealAttempt = now
    
    local packageData = spawnedPackages[packageId]
    if not packageData then
        lib.notify({
            title = locale('package_gone'),
            type = 'error'
        })
        return
    end
    
    local entity = packageData.entity
    if not DoesEntityExist(entity) then
        lib.notify({
            title = locale('invalid_target'),
            type = 'error'
        })
        return
    end
    
    local playerCoords = GetEntityCoords(cache.ped)
    local packageCoords = GetEntityCoords(entity)
    local distance = #(playerCoords - packageCoords)
    
    if distance > 3.0 then
        lib.notify({
            title = locale('too_far_from_package'),
            type = 'error'
        })
        return
    end
    
    
    debugPrint("Starting steal animation")
    
    local success = lib.progressCircle({
        duration = Config.robberyTime.porchpirate,
        label = locale('stealing_porch_package'),
        position = 'bottom',
        canCancel = true,
        disable = {
            car = true,
            move = true,
            combat = true
        },
        anim = {
            dict = 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@',
            clip = 'machinic_loop_mechandplayer'
        }
    })
    
    if not success then
        debugPrint("Steal cancelled")
        return
    end
    
    debugPrint("Calling server callback")
    
    local result, message, item, amount = lib.callback.await(
        'eb-pettycrime-porch:server:StealPackage',
        false,
        packageId,
        packageCoords
    )
    
    debugPrint("Server result: " .. tostring(result) .. " " .. tostring(message))
    
    if result then
        if Config.notifications then
            lib.notify({
                title = locale('package_stolen'),
                description = locale('package_stolen_desc', amount or 1, item or 'item'),
                type = 'success'
            })
        end
        
        Systems.Dispatch.sendTheftDispatch(packageCoords, 'package_theft')
        
        removePackageObject(packageId)
    else
        if Config.notifications then
            lib.notify({
                title = locale('cannot_steal_package'),
                description = message or locale('unknown_error'),
                type = 'error'
            })
        end
    end
end

RegisterNetEvent('eb-pettycrime-porch:client:SpawnPackage', function(packageId, coords, modelName)
    debugPrint("Received spawn event: " .. packageId .. " at " .. tostring(coords))
    
    if spawnedPackages[packageId] then
        debugPrint("Package already exists: " .. packageId)
        return
    end
    
    local entity = createPackageObject(packageId, coords, modelName)
    if entity then
        SetTimeout(200, function()
            if DoesEntityExist(entity) then
                addPackageTarget(entity, packageId)
            end
        end)
    end
end)

RegisterNetEvent('eb-pettycrime-porch:client:RemovePackage', function(packageId)
    debugPrint("Received remove event: " .. packageId)
    removePackageObject(packageId)
end)

CreateThread(function()
    while true do
        Wait(60000) 
        
        local toRemove = {}
        for packageId, data in pairs(spawnedPackages) do
            if not DoesEntityExist(data.entity) then
                toRemove[#toRemove + 1] = packageId
            end
        end
        
        for i = 1, #toRemove do
            debugPrint("Cleanup removing: " .. toRemove[i])
            spawnedPackages[toRemove[i]] = nil
        end
    end
end)


-- Resource stop cleanup
AddEventHandler('onResourceStop', function(resourceName)
    if cache.resource ~= resourceName then return end
    
    -- Remove all targets and objects
    for entity, packageId in pairs(packageObjects) do
        if DoesEntityExist(entity) then
            removePackageTarget(entity, packageId)
            DeleteEntity(entity)
        end
    end
    
    packageObjects = {}
    spawnedPackages = {}
end)