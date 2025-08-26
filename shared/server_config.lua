if not IsDuplicityVersion() then return {} end

local ServerConfig = {}

ServerConfig.packageProps = {
    [`prop_drug_package_02`] = {
        weight = 15,
        rewards = {
            { item = 'brick_cocaine2', minAmount = 1, maxAmount = 2, chance = 5 },
            { item = 'meth', minAmount = 1, maxAmount = 1, chance = 5 },
            { item = 'panties', minAmount = 1, maxAmount = 5, chance = 30 },
            { item = 'circuit_board', minAmount = 1, maxAmount = 1, chance = 30 },
        }
    },
    [`prop_ld_case_01`] = {
        weight = 20,
        rewards = {
            { item = 'water', minAmount = 2, maxAmount = 6, chance = 35 },
            { item = 'baggy_cocaine', minAmount = 2, maxAmount = 3, chance = 35 },
            { item = 'money', minAmount = 10, maxAmount = 20, chance = 10 },
        }
    },
    [`m23_1_prop_m31_laptop_01a`] = {
        weight = 10,
        rewards = {
            { item = 'laptop4', minAmount = 1, maxAmount = 1, chance = 1 },
            { item = 'circuit_board', minAmount = 1, maxAmount = 1, chance = 30 },
        }
    },
    [`ch_prop_ch_bag_01a`] = {
        weight = 25,
        rewards = {
            { item = 'firstaid', minAmount = 1, maxAmount = 1, chance = 20 },
            { item = 'bandage', minAmount = 1, maxAmount = 2, chance = 35 },
            { item = 'money', minAmount = 10, maxAmount = 50, chance = 10 },
            { item = 'water', minAmount = 2, maxAmount = 3, chance = 35 }
        }
    },
    [`v_ret_ml_beerbar`] = {
        weight = 25,
        rewards = {
            { item = 'beer', minAmount = 1, maxAmount = 5, chance = 30 },
            { item = 'vodka', minAmount = 1, maxAmount = 5, chance = 30 },
            { item = 'whiskey', minAmount = 1, maxAmount = 5, chance = 30 },
            { item = 'meth', minAmount = 1, maxAmount = 1, chance = 10 }
        }
    },
    [`xm3_prop_xm3_backpack_01a`] = {
        weight = 12,
        rewards = {
            { item = 'water', minAmount = 1, maxAmount = 3, chance = 35 },
            { item = 'sprunk', minAmount = 1, maxAmount = 3, chance = 35 },
            { item = 'panties', minAmount = 1, maxAmount = 5, chance = 35 },
            { item = 'parachute', minAmount = 1, maxAmount = 1, chance = 10 }
        }
    }
}

ServerConfig.vendingRewards = {
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

ServerConfig.chopshopRewards = {
    [0] = {
        rewards = { aluminum = 70, steel = 100, glass = 60 },
        quantities = { aluminum = {min = 1, max = 3}, steel = {min = 2, max = 4}, glass = {min = 1, max = 2} }
    },
    [1] = {
        rewards = { aluminum = 70, steel = 100, glass = 60 },
        quantities = { aluminum = {min = 1, max = 3}, steel = {min = 2, max = 4}, glass = {min = 1, max = 2} }
    },
    [2] = {
        rewards = { aluminum = 65, steel = 90, glass = 60 },
        quantities = { aluminum = {min = 1, max = 2}, steel = {min = 1, max = 3}, glass = {min = 1, max = 2} }
    },
    [3] = {
        rewards = { aluminum = 65, steel = 90, glass = 60 },
        quantities = { aluminum = {min = 1, max = 2}, steel = {min = 1, max = 3}, glass = {min = 1, max = 2} }
    },
    [4] = {
        rewards = { aluminum = 85, steel = 100 },
        quantities = { aluminum = {min = 2, max = 5}, steel = {min = 2, max = 4} }
    },
    [5] = {
        rewards = { aluminum = 80, steel = 100 },
        quantities = { aluminum = {min = 2, max = 4}, steel = {min = 2, max = 4} }
    },
    [6] = {
        rewards = { rubber = 90, aluminum = 70, steel = 50 },
        quantities = { rubber = {min = 3, max = 6}, aluminum = {min = 1, max = 3}, steel = {min = 1, max = 2} }
    },
    [7] = {
        rewards = { rubber = 90, aluminum = 70, steel = 50 },
        quantities = { rubber = {min = 3, max = 6}, aluminum = {min = 1, max = 3}, steel = {min = 1, max = 2} }
    },
    [8] = {
        rewards = { rubber = 90, aluminum = 70, steel = 50 },
        quantities = { rubber = {min = 3, max = 6}, aluminum = {min = 1, max = 3}, steel = {min = 1, max = 2} }
    },
    [9] = {
        rewards = { rubber = 90, aluminum = 70, steel = 50 },
        quantities = { rubber = {min = 3, max = 6}, aluminum = {min = 1, max = 3}, steel = {min = 1, max = 2} }
    },
    [10] = {
        rewards = { aluminum = 80, plastic = 90, steel = 40 },
        quantities = { aluminum = {min = 2, max = 4}, plastic = {min = 3, max = 6}, steel = {min = 1, max = 2} }
    },
    [11] = {
        rewards = { aluminum = 80, plastic = 90, steel = 40 },
        quantities = { aluminum = {min = 2, max = 4}, plastic = {min = 3, max = 6}, steel = {min = 1, max = 2} }
    }
}

ServerConfig.chopshopCompletionBonus = {
    steel = 15,
    aluminum = 12,
    rubber = 10,
    glass = 8,
    plastic = 6,
    copper = 4
}

ServerConfig.porchPirateRewards = {
    { item = 'laptop4', minAmount = 1, maxAmount = 1, chance = 5 },
    { item = 'circuit_board', minAmount = 1, maxAmount = 3, chance = 60 },
    { item = 'water', minAmount = 2, maxAmount = 5, chance = 70 },
    { item = 'baggy_cocaine', minAmount = 1, maxAmount = 2, chance = 15 },
    { item = 'firstaid', minAmount = 1, maxAmount = 2, chance = 40 },
    { item = 'phone', minAmount = 1, maxAmount = 1, chance = 25 },
    { item = 'bandage', minAmount = 2, maxAmount = 6, chance = 50 }
}

ServerConfig.porchPirateLocations = {
    vec3(903.63, -615.71, 58.45),
    vec3(886.81, -608.24, 58.45),
    vec3(861.32, -582.59, 58.16),
    vec3(844.18, -563.18, 57.84)
}

ServerConfig.porchPirateProps = {
    'bzzz_prop_custom_box_1a', 'bzzz_prop_custom_box_1b', 'bzzz_prop_custom_box_1c',
    'bzzz_prop_custom_box_1d', 'bzzz_prop_custom_box_1e', 'bzzz_prop_custom_box_2a',
    'bzzz_prop_custom_box_2b', 'bzzz_prop_custom_box_2c', 'bzzz_prop_custom_box_2d',
    'bzzz_prop_custom_box_2e', 'bzzz_prop_custom_box_3a', 'bzzz_prop_custom_box_3b',
    'bzzz_prop_custom_box_3c', 'bzzz_prop_custom_box_3d', 'bzzz_prop_custom_box_3e'
}

return ServerConfig