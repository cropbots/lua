return {
    id = "tree_plains",
    width = 2,
    height = 3,
    background = {},
    foreground = {
        { dx = 0, dy = 2, tileId = 191 },
        { dx = 1, dy = 2, tileId = 192 },
    },
    overlay = {
        { dx = 0, dy = 0, tileId = 157 },
        { dx = 1, dy = 0, tileId = 158 },
        { dx = 0, dy = 1, tileId = 174 },
        { dx = 1, dy = 1, tileId = 175 },
    },
    colliders = {
        { dx = 0, dy = 2, mask = 2 },
        { dx = 1, dy = 2, mask = 1 },
    },
    interactors = {
        { dx = 0, dy = 2, mask = 15 },
        { dx = 1, dy = 2, mask = 15 },
    },
    on_interact = { "chop:tree" },
    interact_range = 2.2,
    frequency = 0.025,
    max_per_map = 800,
    min_distance = 40,
    player_buildable = false,
    build_cog_cost = 0,
    build_materials = {},
}
