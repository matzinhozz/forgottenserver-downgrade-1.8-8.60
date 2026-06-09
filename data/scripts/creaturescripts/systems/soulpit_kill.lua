-- Soulpit Kill Tracking
-- When a soulpit boss (stack 40) is killed, grant animus mastery

local soulpitKill = CreatureEvent("SoulpitKill")

function soulpitKill.onDeath(creature, corpse, killer, mostDamageKiller, lastHitUnjustified, mostDamageUnjustified)
    if not configManager.getBoolean(configKeys.SOULPIT_SYSTEM_ENABLED) then
        return true
    end

    -- Check if this was a soulpit boss
    local stack = creature:getForgeStack()
    if stack ~= 40 then
        return true
    end

    -- Grant mastery to all players who damaged the boss
    local players = {}
    if killer and killer:isPlayer() then
        players[killer:getGuid()] = killer
    end
    if mostDamageKiller and mostDamageKiller:isPlayer() then
        players[mostDamageKiller:getGuid()] = mostDamageKiller
    end

    local monsterName = creature:getName():lower()

    for guid, player in pairs(players) do
        -- Add to mastered creatures
        local raceId = creature:getType():getRaceId()
        Soulseals.addMastered(guid, raceId)

        player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format(
            "You have mastered the soul of %s!", creature:getName()))
    end

    return true
end

soulpitKill:register()
