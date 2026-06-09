-- Task Board Kill Tracking
-- CreatureEvent that fires on monster death to update bounty/weekly tasks

if not TaskBoard then TaskBoard = {} end

local taskBoardKill = CreatureEvent("TaskBoardKill")

function taskBoardKill.onDeath(creature, corpse, killer, mostDamageKiller, lastHitUnjustified, mostDamageUnjustified)
    if not configManager.getBoolean(configKeys.TASK_HUNTING_SYSTEM_ENABLED) then
        return true
    end

    -- Ignore summons
    if creature and creature:getMaster() then
        return true
    end

    -- Get raceId from creature
    local monsterType = creature:getType()
    if not monsterType then return true end
    local raceId = monsterType:getRaceId()
    if raceId == 0 then return true end

    -- Collect all players who should get kill credit
    local players = {}
    if killer and killer:isPlayer() then
        local guid = killer:getGuid()
        players[guid] = killer
    end
    if mostDamageKiller and mostDamageKiller:isPlayer() then
        local guid = mostDamageKiller:getGuid()
        if not players[guid] then
            players[guid] = mostDamageKiller
        end
    end

    for _, player in pairs(players) do
        -- Update bounty tasks
        TaskBoard.onBountyKill(player, raceId)
        -- Update weekly tasks
        TaskBoard.onWeeklyKill(player, raceId)
    end

    return true
end

taskBoardKill:register()

-- Register event on all monsters
local taskBoardSpawn = MonsterEvent("TaskBoardSpawn")

function taskBoardSpawn.onSpawn(monster)
    monster:registerEvent("TaskBoardKill")
    return true
end

taskBoardSpawn:register()

print("[TaskBoard] Kill tracking registered")
