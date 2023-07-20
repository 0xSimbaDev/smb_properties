Config = {}

Config.Properties = {
    -- ["property_1"] = {
    --     type = "house",
    --     coords = {x = 123.4, y = 567.8, z = 910.11},
    --     doors = {
    --         {
    --             coords = {x = 123.4, y = 567.8, z = 910.11}, 
    --             locked = false,
    --             doorHash = "unique_door_hash_1",
    --             modelHash = "model_hash_1",
    --         },
    --         {
    --             coords = {x = 200.1, y = 200.2, z = 200.3}, 
    --             locked = true,
    --             doorHash = "unique_door_hash_2", 
    --             modelHash = "model_hash_2",
    --         },
    --     },
    --     zone = vector3(123.4, 567.8, 910.11), 
    --     stash = {x = 123.4, y = 567.8, z = 910.11}
    -- },
    -- ["mansion_1"] = {
    --     type = "mansion",
    --     coords = {x = 123.4, y = 567.8, z = 910.11},
    --     doors = {
    --         {
    --             coords = {x = 300.1, y = 300.2, z = 300.3}, 
    --             locked = true,
    --             doorHash = "unique_door_hash_3", 
    --             modelHash = "model_hash_3",
    --         },
    --         {
    --             coords = {x = 400.1, y = 400.2, z = 400.3}, 
    --             locked = false,
    --             doorHash = "unique_door_hash_4", 
    --             modelHash = "model_hash_4",
    --         },
    --     },
    --     rooms = {
    --         ["living_room"] = {
    --             coords = {x = 320.1, y = 320.2, z = 320.3},
    --             stash = {x = 320.4, y = 320.5, z = 320.6},
    --         },
    --         ["bedroom_1"] = {
    --             coords = {x = 420.1, y = 420.2, z = 420.3},
    --             stash = {x = 420.4, y = 420.5, z = 420.6},
    --         },
    --     },
    --     zone = vector3(123.4, 567.8, 910.11),
    -- },
    ["del_perro"] = {
        type = "motel",
        coords = {x = -1919.7110595704, y = 3022.0185546875, z = 32.81031036377},
        units = {
            [1] = {
                coords = {x = 123.4, y = 567.8, z = 910.11},
                door = {
                    coords = {x = -1466.37, y = -648.15, z = 29.5}, 
                    locked = false,
                    doorHash = "unique_door_hash_5",
                    modelHash = "model_hash_5",
                },
                stash = {x = 123.4, y = 567.8, z = 910.11},
                isAvailableForRent = true,
                rentDetails = {
                    cost = 500, 
                    duration = "week"
                }
            },
        },
        polyZone = {
            vector2(-1457.9395751954, -626.24633789062),
            vector2(-1436.8034667968, -654.50561523438),
            vector2(-1474.377319336, -682.05212402344),
            vector2(-1486.4700927734, -690.05322265625),
            vector2(-1514.8278808594, -666.49285888672)
        },
    },
}
