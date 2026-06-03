local EntityFlags = require("src.EntityFlags")
local BehaviorTree = require("src.BehaviorTree")

return {
    id = "cropbot",
    kind = "friend",
    sprite = "assets/items/gear.png",
    hitbox = { x = -8, y = -8, w = 16, h = 16 },
    speed = 130,
    hp = 12,
    flags = EntityFlags.PATHFINDING + EntityFlags.NO_ENTITY_COLLISION,
    stats = { damage = 0 },
    behavior = BehaviorTree.action("cropbot_farm"),
    drawParams = { destSize = { x = 16, y = 16 }, offset = { x = -8, y = -8 } },
}
