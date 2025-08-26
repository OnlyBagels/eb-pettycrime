lib.locale()

local Config = require'shared.config'
local Systems = require'shared.systems'
local ServerConfig = require'shared.server_config'

-- State tracking
local activePackages = {}
local packageCounter = 0
local playerCooldowns = {}
local locationCooldowns = {}

local function debugPrint(msg)
    if Config.debug then
        print("^2[PORCH-SERVER]^0 " .. tostring(msg))
    end
end

local function getLocationKey(coords)
    return string.format("%.1f_%.1f_%.1f", coords.x, coords.y, coords.z)
end

local function isLocationOnCooldown(coords)
    local key = getLocationKey(coords)
    local cooldownEnd = locationCooldowns[key]
    
    if cooldownEnd and os.time() < cooldownEnd then
        return true, cooldownEnd - os.time()
    end
    
    return false, 0
end

local function setLocationCooldown(coords)
    local key = getLocationKey(coords)
    locationCooldowns[key] = os.time() + (Config.porchPirate.locationCooldown * 60)
    debugPrint("Set cooldown for location: " .. key)
end

local function isPlayerOnCooldown(playerId)
    local cooldownEnd = playerCooldowns[playerId]
    if cooldownEnd and GetGameTimer() < cooldownEnd then
        return true, math.ceil((cooldownEnd - GetGameTimer()) / 1000)
    end
    return false, 0
end

local function setPlayerCooldown(playerId, seconds)
    playerCooldowns[playerId] = GetGameTimer() + (seconds * 1000)
end

local function getRandomReward()
    local rewards = ServerConfig.porchPirateRewards
    if not rewards or #rewards == 0 then
        debugPrint("No rewards configured")
        return 'money', 10
    end
    
    local totalWeight = 0
    for _, reward in ipairs(rewards) do
        totalWeight = totalWeight + reward.chance
    end
    
    local roll = math.random() * totalWeight
    local currentWeight = 0
    
    for _, reward in ipairs(rewards) do
        currentWeight = currentWeight + reward.chance
        if roll <= currentWeight then
            local amount = math.random(reward.minAmount, reward.maxAmount)
            return reward.item, amount
        end
    end
    
    -- Fallback
    local fallback = rewards[1]
    return fallback.item, math.random(fallback.minAmount, fallback.maxAmount)
end

local function spawnPackageAtLocation(location)
    if not location then return end
    
    packageCounter = packageCounter + 1
    local packageId = 'package_' .. packageCounter
    
    local props = ServerConfig.porchPirateProps
    local modelName = props[math.random(#props)]
    
    activePackages[packageId] = {
        id = packageId,
        location = location,
        model = modelName,
        spawnTime = os.time(),
        stolen = false
    }
    
    debugPrint("Spawning package: " .. packageId .. " at " .. tostring(location))
    
    
    TriggerClientEvent('eb-pettycrime-porch:client:SpawnPackage', -1, packageId, location, modelName)
    
    
    SetTimeout(Config.porchPirate.packageLifetime, function()
        if activePackages[packageId] and not activePackages[packageId].stolen then
            debugPrint("Package expired: " .. packageId)
            removePackage(packageId)
        end
    end)
    
    return packageId
end

function removePackage(packageId)
    if not activePackages[packageId] then return end
    
    debugPrint("Removing package: " .. packageId)
    
    TriggerClientEvent('eb-pettycrime-porch:client:RemovePackage', -1, packageId)
    activePackages[packageId] = nil
end


CreateThread(function()
    Wait(5000) 
    
    while true do
        Wait(Config.porchPirate.spawnInterval)
        
        local activeCount = 0
        for _ in pairs(activePackages) do
            activeCount = activeCount + 1
        end
        
        if activeCount >= Config.porchPirate.maxActivePackages then
            debugPrint("Max packages reached: " .. activeCount)
            goto continue
        end
        
        
        if Config.timeRestricted.enabled and not Systems.Time.isAllowedTime() then
            debugPrint("Outside allowed time")
            goto continue
        end
        
        
        if Config.policeRequired then
            local hasEnoughPolice = Systems.Police.checkRequirement()
            if not hasEnoughPolice then
                debugPrint("Not enough police online")
                goto continue
            end
        end
        
        
        for _, location in ipairs(ServerConfig.porchPirateLocations) do
            if math.random(1, 100) <= Config.porchPirate.spawnChance then
                
                local hasNearby = false
                for _, packageData in pairs(activePackages) do
                    if #(location - packageData.location) < 5.0 then
                        hasNearby = true
                        break
                    end
                end
                
                if not hasNearby then
                    debugPrint("Spawning at location: " .. tostring(location))
                    spawnPackageAtLocation(location)
                    break 
                end
            end
        end
        
        ::continue::
    end
end)


lib.callback.register('eb-pettycrime-porch:server:StealPackage', function(source, packageId, coords)
    debugPrint("=== CALLBACK START ===")
    debugPrint("Source: " .. tostring(source))
    debugPrint("PackageID: " .. tostring(packageId))
    debugPrint("Coords: " .. tostring(coords))
    
    if not source or source <= 0 then
        debugPrint("ERROR: Invalid source")
        return false, "Invalid source"
    end
    
    local onCooldown, timeLeft = isPlayerOnCooldown(source)
    if onCooldown then
        debugPrint("Player on cooldown: " .. timeLeft .. "s")
        return false, locale('please_wait_seconds', timeLeft)
    end
    
    if not activePackages[packageId] then
        debugPrint("Package not found: " .. packageId)
        return false, locale('package_no_longer_available')
    end
    
    local packageData = activePackages[packageId]
    
    if packageData.stolen then
        debugPrint("Package already stolen: " .. packageId)
        return false, locale('package_no_longer_available')
    end
    
    if not Systems.Security.validatePlayerPosition(source, packageData.location, 4.0) then
        debugPrint("Player too far from package")
        return false, locale('too_far_from_package')
    end
    
    local locationOnCooldown, cooldownTime = isLocationOnCooldown(packageData.location)
    if locationOnCooldown then
        debugPrint("Location on cooldown: " .. cooldownTime .. "s")
        return false, locale('location_recently_robbed', math.ceil(cooldownTime / 60))
    end
    
    if Config.policeRequired then
        local hasEnoughPolice, requiredPolice, onlinePolice = Systems.Police.checkRequirement()
        if not hasEnoughPolice then
            debugPrint("Not enough police: " .. onlinePolice .. "/" .. requiredPolice)
            return false, locale('need_police_online', requiredPolice, onlinePolice)
        end
    end
    
    local item, amount = getRandomReward()
    
    if not exports.ox_inventory:CanCarryItem(source, item, amount) then
        debugPrint("Player inventory full")
        return false, locale('inventory_full')
    end
    
    local success = exports.ox_inventory:AddItem(source, item, amount)
    if not success then
        debugPrint("Failed to add item to inventory")
        return false, locale('failed_add_inventory')
    end
    
    setPlayerCooldown(source, 3)
    setLocationCooldown(packageData.location)
    
    packageData.stolen = true
    removePackage(packageId)
    
    debugPrint("Package stolen successfully by player " .. source .. ": " .. amount .. "x " .. item)
    
    return true, locale('package_stolen'), item, amount
end)

CreateThread(function()
    while true do
        Wait(300000) 
        
        local currentTime = os.time()
        local currentGameTime = GetGameTimer()
        

        local toRemove = {}
        for packageId, packageData in pairs(activePackages) do
            if (currentTime - packageData.spawnTime) > 1800 then 
                toRemove[#toRemove + 1] = packageId
            end
        end
        
        for i = 1, #toRemove do
            debugPrint("Cleanup removing expired package: " .. toRemove[i])
            removePackage(toRemove[i])
        end
        
        for playerId, cooldownEnd in pairs(playerCooldowns) do
            if currentGameTime >= cooldownEnd then
                playerCooldowns[playerId] = nil
            end
        end
        
        for locationKey, cooldownEnd in pairs(locationCooldowns) do
            if currentTime >= cooldownEnd then
                locationCooldowns[locationKey] = nil
            end
        end
        
        debugPrint("Cleanup completed")
    end
end)

AddEventHandler('playerDropped', function()
    local source = source
    playerCooldowns[source] = nil
    debugPrint("Cleaned up cooldowns for disconnected player: " .. source)
end)

AddEventHandler('onResourceStop', function(resourceName)
    if cache.resource ~= resourceName then return end
    
    debugPrint("Resource stopping - cleaning up packages")
    
    for packageId in pairs(activePackages) do
        TriggerClientEvent('eb-pettycrime-porch:client:RemovePackage', -1, packageId)
    end
    
    activePackages = {}
    playerCooldowns = {}
    locationCooldowns = {}
    packageCounter = 0
end)