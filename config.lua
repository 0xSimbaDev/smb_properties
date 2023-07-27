Config = {}

Config.Properties = {
    ["pinkcage"] = {
        name = "pinkcage",
        type = "motel",
        coords = {x = -1919.7110595704, y = 3022.0185546875, z = 53.8},
        purchasePrice = 15000000,
        isPropertySold = true,
        units = {
            [1] = {
                coords = {x = 123.4, y = 567.8, z = 910.11},
                door = {
                    coords = vec3(306.848938, -213.674500, 54.371540), 
                    locked = true,
                    doorHash = `pinkcage_unit_1`,
                    modelHash = -1156992775,
                },
                stash = {
                    coords = vec3(307.02, -207.97, 54.22),
                    ids = {
                        'pinkcage_unit1_stash_1',
                        'pinkcage_unit1_stash_2',
                        'pinkcage_unit1_stash_3',
                    },
                },
            },
            [2] = {
                coords = {x = 123.4, y = 567.8, z = 910.11},
                door = {
                    coords = vec3(310.64, -203.79, 54.37), 
                    locked = true,
                    doorHash = `pinkcage_unit_2`,
                    modelHash = -1156992775,
                },
                stash = {
                    coords = vec3(310.69, -198.1, 54.76),
                    ids = {
                        'pinkcage_unit2_stash_1',
                        'pinkcage_unit2_stash_2',
                        'pinkcage_unit2_stash_3',
                    },
                },
            },    
        },
        polyZone = {
            vector2(358.58950805664, -198.37442016602),
            vector2(308.73391723632, -179.08024597168),
            vector2(293.75567626954, -224.45109558106),
            vector2(321.90798950196, -233.97221374512),
            vector2(320.65698242188, -236.88807678222),
            vector2(343.94140625, -245.03831481934),
            vector2(351.86981201172, -223.4574432373)
        },
    },
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
    -- ["del_perro"] = {
    --     type = "motel",
    --     coords = {x = -1919.7110595704, y = 3022.0185546875, z = 32.81031036377},
    --     units = {
    --         [1] = {
    --             coords = {x = 123.4, y = 567.8, z = 910.11},
    --             door = {
    --                 coords = {x = -1466.37, y = -648.15, z = 29.5}, 
    --                 locked = false,
    --                 doorHash = `unique_door_hash_5`,
    --                 modelHash = `model_hash_5`,
    --             },
    --             stash = {x = 123.4, y = 567.8, z = 910.11},
    --             isAvailableForRent = true,
    --             rentDetails = {
    --                 cost = 500, 
    --                 duration = "week"
    --             }
    --         },
    --     },
    --     polyZone = {
    --         vector2(-1457.9395751954, -626.24633789062),
    --         vector2(-1436.8034667968, -654.50561523438),
    --         vector2(-1474.377319336, -682.05212402344),
    --         vector2(-1486.4700927734, -690.05322265625),
    --         vector2(-1514.8278808594, -666.49285888672)
    --     },
    -- },

}
