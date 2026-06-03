return {
    id = "lock_block_v",
    width = 1,
    height = 2,
    background = {},
    foreground = {},
    overlay = {
        { dx = 0, dy = 0, tileId = 227 },
        { dx = 0, dy = 1, tileId = 227 },
    },
    colliders = {
        { dx = 0, dy = 0, mask = 15 },
        { dx = 0, dy = 1, mask = 15 },
    },
    interactors = {
        { dx = 0, dy = 0, mask = 15 },
        { dx = 0, dy = 1, mask = 15 },
    },
    on_interact = { "lock_puzzle:basic_lock" },
    interact_range = 2.5,
    frequency = 0,
    max_per_map = 0,
    min_distance = 0,
    player_buildable = false,
}
