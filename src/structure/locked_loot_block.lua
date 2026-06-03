return {
    id = "locked_loot_block",
    width = 1,
    height = 1,
    background = {},
    foreground = {},
    -- reuse lock tile for now
    overlay = { { dx = 0, dy = 0, tileId = 227 } },
    colliders = { { dx = 0, dy = 0, mask = 15 } },
    interactors = { { dx = 0, dy = 0 } },
    on_interact = { "lock_puzzle:locked_loot" },
    interact_range = 2.5,
    frequency = 0.25,
    max_per_map = 35,
    min_distance = 0,
    player_buildable = false,
}

