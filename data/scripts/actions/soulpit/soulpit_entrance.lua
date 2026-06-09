-- Soulpit Entrance Action
-- Teleports players to the soulpit lobby area

local entrancePositions = {
    Position(32350, 31030, 3),
    Position(32349, 31030, 3),
}

local entranceDestination = Position(32374, 31171, 8)

local soulpitEntrance = MoveEvent()

function soulpitEntrance.onStepIn(creature, item, position, fromPosition)
    if not configManager.getBoolean(configKeys.SOULPIT_SYSTEM_ENABLED) then
        return true
    end

    local player = creature:getPlayer()
    if not player then
        return true
    end

    player:teleportTo(entranceDestination)
    player:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
    return true
end

for _, pos in ipairs(entrancePositions) do
    soulpitEntrance:position(pos)
end
soulpitEntrance:register()

-- Soulpit Exit Action
local exitPosition = Position(32374, 31173, 8)
local exitDestination = Position(32349, 31032, 3)

local soulpitExit = MoveEvent()

function soulpitExit.onStepIn(creature, item, position, fromPosition)
    if not configManager.getBoolean(configKeys.SOULPIT_SYSTEM_ENABLED) then
        return true
    end

    local player = creature:getPlayer()
    if not player then
        return true
    end

    Soulpit.exitPlayer(player)
    return true
end

soulpitExit:position(exitPosition)
soulpitExit:register()
