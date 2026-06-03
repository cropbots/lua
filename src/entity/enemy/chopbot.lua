local EntityFlags = require("src.EntityFlags")
local BehaviorTree = require("src.BehaviorTree")

return {
    id = "chopbot",
    kind = "friend",
    targetMode = "nearest_enemy",
    seekRange = 320,
    targetRange = 0.25,
    sprite = "assets/objects/chopbot.png",
    hitbox = { x = -5.58, y = -5, w = 11.16, h = 10 },
    speed = 300,
    hp = 5,
    flags = EntityFlags.PATHFINDING + EntityFlags.NO_ENTITY_COLLISION,
    stats = { damage = 1 },
    behavior = BehaviorTree.selector({
        BehaviorTree.sequence({
            BehaviorTree.condition("target_in_range"),
            BehaviorTree.action("curve_dash_at_target", {
                dash_cooldown = 1.0,
                arc_strength = 0.1,
                dash_speed = 300,
                dash_duration = 0.4,
            }),
        }),
        BehaviorTree.sequence({
            BehaviorTree.not_condition("has_target"),
            BehaviorTree.condition("player_in_range"),
            BehaviorTree.action("wander", { speed = 50 }),
        }),
        BehaviorTree.sequence({
            BehaviorTree.not_condition("has_target"),
            BehaviorTree.not_condition("player_in_range"),
            BehaviorTree.action("seek_player", { speed = 50 }),
        }),
        BehaviorTree.sequence({
            BehaviorTree.condition("has_target"),
            BehaviorTree.not_condition("target_in_range"),
            BehaviorTree.action("seek"),
        }),
        BehaviorTree.action("watch", {
            seek_range = 320,
            flee_range = 10,
            seek_force = 140,
            flee_force = 50,
        }),
    }),
    drawParams = { destSize = { x = 11.16, y = 10 }, offset = { x = -5.58, y = -5 } },
}
