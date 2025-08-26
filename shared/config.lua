local Config = {}

Config.debug = false
Config.notifications = false

Config.policeRequired = true
Config.policeJobType = 'leo'
Config.DynamicPolice = {
    enabled = true,
    scaling = {
        {5, 0},
        {10, 1},
        {15, 2},
        {math.huge, 4}
    }
}

Config.useDispatch = true
Config.dispatchResource = 'cd_dispatch'
Config.dispatchOnFail = true
Config.dispatchJobs = {'lspd', 'sasp', 'bcso', 'usms'}

Config.witnessSystem = {
    enabled = true,
    distance = 35.0,
    callChance = 25
}

Config.timeRestricted = {
    enabled = false,
    allowedStartTime = 21,
    allowedEndTime = 6
}

Config.lockpick = {
    required = true,
    item = 'lockpick',
    breakChance = 25,
    removeOnSuccess = false
}

Config.robberyTime = {
    carpackage = 30000,
    vending = 30000,
    chopshop = 30000,
    porchpirate = 30000,
}

Config.packageSettings = {
    spawnChance = 15,
    interactionDistance = 2.5
}

Config.blacklistedModels = {
    [`caddy`] = true,
    [`forklift`] = true,
    [`blazer`] = true,
    [`mlue`] = true,
    [`mlue2`] = true
}

Config.vending = {
    robbedCooldown = 60,
    progressBarDuration = 15000,
    objectLabel = 'break_into_vending',
    objectIcon = 'fas fa-sack-dollar',
    objects = {
        `prop_vend_soda_01`,
        `prop_vend_soda_02`,
        `sf_prop_sf_vend_drink_01a`,
        `ch_chint10_vending_smallroom_01`
    }
}

Config.newspaper = {
    label = 'break_into_newspaper',
    icon = 'fas fa-newspaper',
    objects = {
        `prop_news_disp_02a_s`, `prop_news_disp_02c`, `prop_news_disp_05a`,
        `prop_news_disp_02e`, `prop_news_disp_03c`, `prop_news_disp_06a`,
        `prop_news_disp_02a`, `prop_news_disp_02d`, `prop_news_disp_02b`,
        `prop_news_disp_01a`, `prop_news_disp_03a`
    },
    progressText = 'breaking_newspaper'
}

Config.parkingMeter = {
    label = 'break_into_parking_meter',
    icon = 'fas fa-coins',
    objects = {
        `prop_parknmeter_01`,
        `prop_parknmeter_02`
    },
    progressText = 'breaking_parking_meter'
}

Config.chopshop = {
    showBlip = false,
    vehicleDeleteDelay = 300000,
    cooldown = 15,
    dispatchChance = 25,
    requireUnlocked = true,
    zone = {
        center = vector3(-440.45, -1693.46, 19.23),
        radius = 50.0
    },
    chainsaw = {
        dict = 'anim@heists@fleeca_bank@drilling',
        clip = 'drill_straight_fail',
        prop = 'prop_tool_consaw',
        propBone = 28422,
        propPlacement = {
            x = 0.0, y = 0.0, z = 0.0,
            xRot = 0.0, yRot = 0.0, zRot = 90.0
        }
    },
    effects = {
        sparkEffect = {
            dict = 'scr_reconstructionaccident',
            name = 'scr_sparking_generator',
            scale = 0.5,
            duration = 1000
        },
        chainsawSound = {
            name = 'Drill_Pin_Break',
            set = 'DLC_HEIST_FLEECA_SOUNDSET',
            volume = 0.8,
            range = 20.0
        }
    },
    parts = {
        [0] = { label = "driver_front_door", bone = "door_dside_f" },
        [1] = { label = "passenger_front_door", bone = "door_pside_f" },
        [2] = { label = "driver_rear_door", bone = "door_dside_r" },
        [3] = { label = "passenger_rear_door", bone = "door_pside_r" },
        [4] = { label = "hood_bonnet", bone = "bonnet" },
        [5] = { label = "trunk_boot", bone = "boot" },
        [6] = { label = "left_front_wheel", bone = "wheel_lf" },
        [7] = { label = "right_front_wheel", bone = "wheel_rf" },
        [8] = { label = "left_rear_wheel", bone = "wheel_lr" },
        [9] = { label = "right_rear_wheel", bone = "wheel_rr" },
        [10] = { label = "front_bumper", bone = "bumper_f" },
        [11] = { label = "rear_bumper", bone = "bumper_r" }
    }
}

Config.porchPirate = {
   spawnChance = 15,
   spawnInterval = 900000,
   maxActivePackages = 8,
   packageLifetime =  1800000, 
   locationCooldown = 45
}

Config.NotifyTypes = {
    success = 'success',
    error = 'error',
    warning = 'warning',
    info = 'inform'
}

function Config.GetRequiredPolice()
    if not Config.DynamicPolice.enabled then
        return 1
    end
    
    local playerCount = GlobalState.PlayerCount or #GetPlayers()
    
    for _, threshold in ipairs(Config.DynamicPolice.scaling) do
        if playerCount <= threshold[1] then
            return threshold[2]
        end
    end
    
    return 1
end

function Config.IsWithinAllowedTime()
    if not Config.timeRestricted.enabled then return true end
    
    local currentHour = tonumber(os.date("%H"))
    local startTime = Config.timeRestricted.allowedStartTime
    local endTime = Config.timeRestricted.allowedEndTime
    
    if startTime > endTime then
        return currentHour >= startTime or currentHour < endTime
    else
        return currentHour >= startTime and currentHour < endTime
    end
end

return Config