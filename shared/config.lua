local Config = {}

-- Core Settings
Config.debug = false
Config.notifications = true

-- Police System
Config.policeRequired = true
Config.policeJobType = 'leo'
Config.DynamicPolice = {
    enabled = true,
    scaling = {
        {5, 1},
        {10, 2},
        {math.huge, 3}
    }
}
Config.minPolice = 1

-- Dispatch Integration
Config.useDispatch = true
Config.dispatchResource = 'cd_dispatch'
Config.dispatchOnFail = true
Config.dispatchJobs = {'lspd', 'sasp', 'bcso', 'usms'}

-- Global Requirements
Config.RequiredItem = 'lockpick'

-- Package System
Config.packageSettings = {
    percent = 5,
    stealTime = 7500,
    interactionDistance = 2.5,
    timeRestricted = true,
    allowedStartTime = 21,
    allowedEndTime = 5,
    witnessSystem = true,
    witnessDistance = 35.0,
    witnessCallChance = 4
}

Config.blacklistedModels = {
    [`caddy`] = true,
    [`forklift`] = true,
    [`blazer`] = true,
    [`mlue`] = true,
    [`mlue2`] = true
}

Config.packageProps = {
    [`prop_drug_package_02`] = {
        weight = 15,
        rewards = {
            { item = 'water', minAmount = 2, maxAmount = 6, chance = 35 }
        }
    },
    [`h4_prop_h4_cash_bag_01a`] = {
        weight = 20,
        rewards = {
            { item = 'water', minAmount = 2, maxAmount = 6, chance = 35 }
        }
    },
    [`sf_prop_sf_laptop_01a`] = {
        weight = 10,
        rewards = {
            { item = 'water', minAmount = 2, maxAmount = 6, chance = 35 }
        }
    },
    [`ch_prop_ch_bag_01a`] = {
        weight = 25,
        rewards = {
            { item = 'lockpick', minAmount = 1, maxAmount = 3, chance = 20 },
            { item = 'money', minAmount = 50, maxAmount = 120, chance = 10 },
            { item = 'water', minAmount = 2, maxAmount = 6, chance = 35 }
        }
    },
    [`xm3_prop_xm3_backpack_01a`] = {
        weight = 12,
        rewards = {
            { item = 'water', minAmount = 2, maxAmount = 6, chance = 35 }
        }
    }
}

-- Vending System
Config.vending = {
    robbedCooldown = 60,
    lockpickBreakChance = 75,
    progressBarDuration = 20000,
    objectLabel = 'Break into vending machine',
    objectIcon = 'fas fa-sack-dollar',
    objects = {
        `prop_vend_soda_01`,
        `prop_vend_soda_02`,
        `sf_prop_sf_vend_drink_01a`,
        `ch_chint10_vending_smallroom_01`
    },
    rewards = {
        vending = {
            { item = 'money', min = 5, max = 50, chance = 100, label = 'Cash' },
            { item = 'orange_tang', min = 1, max = 1, chance = 75, label = 'Orange Tang' }
        },
        parking_meter = {
            { item = 'money', min = 8, max = 35, chance = 95, label = 'Coins' }
        },
        newspaper = {
            { item = 'money', min = 2, max = 15, chance = 100, label = 'Change' }
        }
    }
}

Config.newspaper = {
    label = 'Break into newspaper dispenser',
    icon = 'fas fa-newspaper',
    objects = {
        `prop_news_disp_02a_s`, `prop_news_disp_02c`, `prop_news_disp_05a`,
        `prop_news_disp_02e`, `prop_news_disp_03c`, `prop_news_disp_06a`,
        `prop_news_disp_02a`, `prop_news_disp_02d`, `prop_news_disp_02b`,
        `prop_news_disp_01a`, `prop_news_disp_03a`
    },
    progressText = 'Robbing newspaper dispenser...'
}

Config.parkingMeter = {
    label = 'Break into parking meter',
    icon = 'fas fa-coins',
    objects = {
        `prop_parknmeter_01`,
        `prop_parknmeter_02`
    },
    progressText = 'Breaking into parking meter...'
}

-- Chopshop System
Config.chopshop = {
    showBlip = true,
    chopTime = 12000,
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
        [0] = { label = "Driver Front Door", bone = "door_dside_f",
                rewards = { aluminum = 70, steel = 100, glass = 60 },
                quantities = { aluminum = {min = 1, max = 3}, steel = {min = 2, max = 4}, glass = {min = 1, max = 2} }},
        [1] = { label = "Passenger Front Door", bone = "door_pside_f",
                rewards = { aluminum = 70, steel = 100, glass = 60 },
                quantities = { aluminum = {min = 1, max = 3}, steel = {min = 2, max = 4}, glass = {min = 1, max = 2} }},
        [2] = { label = "Driver Rear Door", bone = "door_dside_r",
                rewards = { aluminum = 65, steel = 90, glass = 60 },
                quantities = { aluminum = {min = 1, max = 2}, steel = {min = 1, max = 3}, glass = {min = 1, max = 2} }},
        [3] = { label = "Passenger Rear Door", bone = "door_pside_r",
                rewards = { aluminum = 65, steel = 90, glass = 60 },
                quantities = { aluminum = {min = 1, max = 2}, steel = {min = 1, max = 3}, glass = {min = 1, max = 2} }},
        [4] = { label = "Hood/Bonnet", bone = "bonnet",
                rewards = { aluminum = 85, steel = 100 },
                quantities = { aluminum = {min = 2, max = 5}, steel = {min = 2, max = 4} }},
        [5] = { label = "Trunk/Boot", bone = "boot",
                rewards = { aluminum = 80, steel = 100 },
                quantities = { aluminum = {min = 2, max = 4}, steel = {min = 2, max = 4} }},
        [6] = { label = "Left Front Wheel", bone = "wheel_lf",
                rewards = { rubber = 90, aluminum = 70, steel = 50 },
                quantities = { rubber = {min = 3, max = 6}, aluminum = {min = 1, max = 3}, steel = {min = 1, max = 2} }},
        [7] = { label = "Right Front Wheel", bone = "wheel_rf",
                rewards = { rubber = 90, aluminum = 70, steel = 50 },
                quantities = { rubber = {min = 3, max = 6}, aluminum = {min = 1, max = 3}, steel = {min = 1, max = 2} }},
        [8] = { label = "Left Rear Wheel", bone = "wheel_lr",
                rewards = { rubber = 90, aluminum = 70, steel = 50 },
                quantities = { rubber = {min = 3, max = 6}, aluminum = {min = 1, max = 3}, steel = {min = 1, max = 2} }},
        [9] = { label = "Right Rear Wheel", bone = "wheel_rr",
                rewards = { rubber = 90, aluminum = 70, steel = 50 },
                quantities = { rubber = {min = 3, max = 6}, aluminum = {min = 1, max = 3}, steel = {min = 1, max = 2} }},
        [10] = { label = "Front Bumper", bone = "bumper_f",
                 rewards = { aluminum = 80, plastic = 90, steel = 40 },
                 quantities = { aluminum = {min = 2, max = 4}, plastic = {min = 3, max = 6}, steel = {min = 1, max = 2} }},
        [11] = { label = "Rear Bumper", bone = "bumper_r",
                 rewards = { aluminum = 80, plastic = 90, steel = 40 },
                 quantities = { aluminum = {min = 2, max = 4}, plastic = {min = 3, max = 6}, steel = {min = 1, max = 2} }}
    },
    completionBonus = {
        steel = 15,
        aluminum = 12,
        rubber = 10,
        glass = 8,
        plastic = 6,
        copper = 4
    }
}

-- Text Configuration
Config.text = {
    attemptRobbery = 'Trying the lock...',
    robberySuccess = 'You managed to break in!',
    robberyFail = 'You bent the lockpick',
    progressBarText = 'Robbing vending machine...',
    notEnoughCops = 'Not enough police online!'
}

-- Notification Types
Config.NotifyTypes = {
    success = 'success',
    error = 'error',
    warning = 'warning',
    info = 'inform'
}

-- Dynamic police requirement function
function Config.GetRequiredPolice()
    if not Config.DynamicPolice.enabled then
        return Config.minPolice
    end
    
    local playerCount = GlobalState.PlayerCount or #GetPlayers()
    
    for _, threshold in ipairs(Config.DynamicPolice.scaling) do
        if playerCount <= threshold[1] then
            return threshold[2]
        end
    end
    
    return Config.minPolice
end

return Config