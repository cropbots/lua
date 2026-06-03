local EntityFlags = require("src.EntityFlags")
local BehaviorTree = require("src.BehaviorTree")

return {
    id = "virat",
    kind = "enemy",
    targetMode = "player",
    targetRange = 0.35,
    sprite = "assets/objects/virat.png",
    hitbox = { x = -6.49, y = -4.24, w = 12.975, h = 8.475 },
    speed = 200,
    hp = 5,
    flags = EntityFlags.TARGET_PLAYER + EntityFlags.PATHFINDING,
    stats = { damage = 1 },
    behavior = BehaviorTree.selector({
        BehaviorTree.sequence({
            BehaviorTree.condition("target_in_range"),
            BehaviorTree.action("dash_at_target", {
                dash_cooldown = 1.5,
                dash_speed = 600,
                dash_duration = 0.2,
            }),
        }),
        BehaviorTree.action("watch", {
            seek_range = 280,
            flee_range = 48,
            seek_force = 90,
            flee_force = 220,
        }),
        BehaviorTree.sequence({
            BehaviorTree.condition("has_target"),
            BehaviorTree.not_condition("target_in_range"),
            BehaviorTree.action("seek"),
        }),
    }),
    drawParams = { destSize = { x = 12.975, y = 8.475 }, offset = { x = -6.49, y = -4.24 } },
}
