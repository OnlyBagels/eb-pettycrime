local Config = require'shared.config'

local policeCount = 0
local playerCount = 0

local function UpdatePlayerCount()
    playerCount = #GetPlayers()
    GlobalState.PlayerCount = playerCount
    
    if Config.debug then
        local requiredPolice = Config.GetRequiredPolice()
        lib.print.debug(('Player Count: %d | Required Police: %d'):format(playerCount, requiredPolice))
    end
end

local function GetOnlinePoliceCount()
    if not Config.policeRequired then
        return Config.GetRequiredPolice()
    end
    
    local count = 0
    local players = GetPlayers()
    
    for i = 1, #players do
        local playerId = tonumber(players[i])
        if playerId then
            local Player = exports.qbx_core:GetPlayer(playerId)
            if Player?.PlayerData?.job?.type == Config.policeJobType then
                count = count + 1
            end
        end
    end
    
    policeCount = count
    return count
end

local function CheckPoliceRequirement()
    local requiredPolice = Config.GetRequiredPolice()
    local onlinePolice = GetOnlinePoliceCount()
    
    if Config.debug then
        lib.print.debug(('Police Check - Players: %d | Required: %d | Online: %d'):format(
            playerCount, requiredPolice, onlinePolice))
    end
    
    return onlinePolice >= requiredPolice, requiredPolice, onlinePolice
end

exports('GetOnlinePoliceCount', GetOnlinePoliceCount)
exports('CheckPoliceRequirement', CheckPoliceRequirement)

AddEventHandler('playerJoining', UpdatePlayerCount)

AddEventHandler('playerDropped', function()
    Wait(1000)
    UpdatePlayerCount()
end)

CreateThread(function()
    Wait(1000)
    UpdatePlayerCount()
    
    while true do
        Wait(60000)
        UpdatePlayerCount()
        GetOnlinePoliceCount()
    end
end)