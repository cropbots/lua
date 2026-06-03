local EntityFlags = require("src.EntityFlags")
local BehaviorTree = require("src.BehaviorTree")

return {
    id = "virabird",
    kind = "enemy",
    targetMode = "player",
    targetRange = 0.35,
    sprite = "assets/objects/virabird.png",
    hitbox = { x = -6.33, y = -4.58, w = 12.65, h = 9.15 },
    speed = 200,
    hp = 2,
    flags = EntityFlags.TARGET_PLAYER + EntityFlags.NO_MAP_COLLISION,
    stats = { damage = 0 },
    behavior = BehaviorTree.selector({
        BehaviorTree.sequence({
            BehaviorTree.condition("has_target"),
            BehaviorTree.action("seek_player", { speed = 120 }),
        }),
        BehaviorTree.action("wander", { speed = 40 }),
    }),
    drawParams = { destSize = { x = 12.65, y = 9.15 }, offset = { x = -6.33, y = -4.58 } },
}
