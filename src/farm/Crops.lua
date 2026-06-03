local Crops = {}

Crops.SOIL_TILE = 228

Crops.defs = {
    potato = {
        id = "potato",
        seedItem = "potato",
        harvestItem = "potato",
        growSeconds = 30,
        stages = { 229, 230, 231 },
    },
    wheat = {
        id = "wheat",
        seedItem = "wheat_seed",
        harvestItem = "wheat",
        growSeconds = 24,
        stages = { 229, 230, 232 },
    },
    tomato = {
        id = "tomato",
        seedItem = "tomato_seed",
        harvestItem = "tomato",
        growSeconds = 28,
        stages = { 229, 230, 233 },
    },
}

Crops.seedToCrop = {
    potato = "potato",
    wheat_seed = "wheat",
    tomato_seed = "tomato",
}

return Crops
