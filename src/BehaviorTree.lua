--- BehaviorTree module
--- Provides behavior tree evaluation and node constructor helpers for the entity system.
--- Node types: selector, sequence, condition, not_condition, action

local BehaviorTree = {}

--- Evaluate a behavior tree node against an entity instance and context.
--- @param node table BehaviorNode table with a `type` field
--- @param instance table EntityInstance with a `stats` StatBlock
--- @param ctx table Context table; `ctx.selectedActions` is a list that action nodes append to
--- @return string "success" or "failure"
function BehaviorTree.evaluateTree(node, instance, ctx)
    local ok, result = pcall(function()
        return BehaviorTree._eval(node, instance, ctx)
    end)
    if not ok then
        if print then
            print("[BehaviorTree] error evaluating node: " .. tostring(result))
        end
        return "failure"
    end
    return result
end

--- Internal recursive evaluator (not wrapped in pcall — caller handles errors).
--- @param node table
--- @param instance table
--- @param ctx table
--- @return string "success" or "failure"
function BehaviorTree._eval(node, instance, ctx)
    local t = node.type

    if t == "selector" then
        -- Try children in order; return "success" on the first success.
        for _, child in ipairs(node.children) do
            local r = BehaviorTree._eval(child, instance, ctx)
            if r == "success" then
                return "success"
            end
        end
        return "failure"

    elseif t == "sequence" then
        -- Run all children; fail on the first failure.
        for _, child in ipairs(node.children) do
            local r = BehaviorTree._eval(child, instance, ctx)
            if r == "failure" then
                return "failure"
            end
        end
        return "success"

    elseif t == "condition" then
        -- Check instance.stats:get(name, 0) > (value or 0)
        local statVal = instance.stats:get(node.name, 0)
        local threshold = node.value or 0
        if statVal > threshold then
            return "success"
        else
            return "failure"
        end

    elseif t == "not_condition" then
        -- Inverse of condition.
        local statVal = instance.stats:get(node.name, 0)
        local threshold = node.value or 0
        if statVal > threshold then
            return "failure"
        else
            return "success"
        end

    elseif t == "action" then
        if ctx and ctx.selectedActions then
            ctx.selectedActions[#ctx.selectedActions + 1] = {
                name = node.name,
                params = node.params or {},
            }
        end
        return "success"

    else
        -- Unknown node type — treat as failure.
        if print then
            print("[BehaviorTree] unknown node type: " .. tostring(t))
        end
        return "failure"
    end
end

--- Create a selector node that tries children in order, returning success on the first success.
--- @param children table Array of BehaviorNode tables
--- @return table BehaviorNode
function BehaviorTree.selector(children)
    return { type = "selector", children = children }
end

--- Create a sequence node that runs all children, failing on the first failure.
--- @param children table Array of BehaviorNode tables
--- @return table BehaviorNode
function BehaviorTree.sequence(children)
    return { type = "sequence", children = children }
end

--- Create a condition node that checks instance.stats:get(name, 0) > (value or 0).
--- @param name string Stat name to check
--- @param value number|nil Threshold value (defaults to 0)
--- @return table BehaviorNode
function BehaviorTree.condition(name, value)
    return { type = "condition", name = name, value = value }
end

--- Create a not_condition node — the inverse of a condition check.
--- @param name string Stat name to check
--- @param value number|nil Threshold value (defaults to 0)
--- @return table BehaviorNode
function BehaviorTree.not_condition(name, value)
    return { type = "not_condition", name = name, value = value }
end

--- Create an action node that pushes `name` to ctx.selectedActions when evaluated.
--- @param name string Action name
--- @param params table|nil Optional parameters table (defaults to {})
--- @return table BehaviorNode
function BehaviorTree.action(name, params)
    return { type = "action", name = name, params = params or {} }
end

return BehaviorTree
