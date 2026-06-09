-- Bounty Tasks subsystem
-- Handles: generation, kill tracking, claim, reroll, difficulty, talisman, preferred

if not TaskBoard then TaskBoard = {} end

-- ============================================================================
-- Bounty difficulty configs
-- ============================================================================

local BOUNTY_DIFFICULTY = {
    [0] = {name = "Beginner", minKills = 50, maxKills = 100, expMin = 30, expMax = 50, points = 3},
    [1] = {name = "Adept", minKills = 100, maxKills = 200, expMin = 70, expMax = 100, points = 7},
    [2] = {name = "Expert", minKills = 200, maxKills = 300, expMin = 150, expMax = 200, points = 16},
    [3] = {name = "Master", minKills = 300, maxKills = 600, expMin = 300, expMax = 400, points = 27},
}

local GRADE_NORMAL = 0
local GRADE_SILVER = 1
local GRADE_GOLD = 2

local STATE_NONE = 0
local STATE_SELECTION = 1
local STATE_ACTIVE = 2
local STATE_COMPLETED = 3

local MAX_REROLL_TOKENS = 10
local FREE_REROLL_COOLDOWN = 72000 -- seconds (20 hours)
local MAX_PREFERRED_SLOTS = 5
local SLOT_UNLOCK_COSTS = {0, 300, 600, 900, 1200}
local PREFERRED_CHANGE_COST = 10

-- ============================================================================
-- DB Load/Save
-- ============================================================================

function TaskBoard.loadBountyFromDB(playerGuid)
    local data = {
        state = STATE_NONE,
        difficulty = 0,
        bountyPoints = 0,
        rerollTokens = 0,
        freeRerollTimestamp = 0,
        activeTask = {},
        creatures = {},
        talisman = {
            {level = 0}, {level = 0}, {level = 0}, {level = 0}
        },
        preferred = {},
    }

    local resultId = db.storeQuery("SELECT * FROM `player_bounty_tasks` WHERE `player_id` = " .. playerGuid)
    if resultId == false then
        -- Ensure row exists
        db.query("INSERT INTO `player_bounty_tasks` (`player_id`) VALUES (" .. playerGuid .. ")")
        return data
    end

    data.state = result.getDataInt(resultId, "state")
    data.difficulty = result.getDataInt(resultId, "difficulty")
    data.bountyPoints = result.getDataInt(resultId, "bounty_points")
    data.rerollTokens = result.getDataInt(resultId, "reroll_tokens")
    data.freeRerollTimestamp = result.getDataLong(resultId, "free_reroll")

    data.activeTask = {
        raceId = result.getDataInt(resultId, "active_raceid"),
        currentKills = result.getDataInt(resultId, "active_kills"),
        requiredKills = result.getDataInt(resultId, "active_required_kills"),
        rewardExp = result.getDataInt(resultId, "active_reward_exp"),
        rewardBountyPoints = result.getDataInt(resultId, "active_reward_points"),
        grade = result.getDataInt(resultId, "active_task_grade"),
        taskIndex = 0,
    }

    data.talisman = {
        {level = result.getDataInt(resultId, "talisman_damage_level")},
        {level = result.getDataInt(resultId, "talisman_lifeleech_level")},
        {level = result.getDataInt(resultId, "talisman_loot_level")},
        {level = result.getDataInt(resultId, "talisman_bestiary_level")},
    }

    -- Load preferred lists (BLOB: 5 bytes per slot: U8 active + U16 preferred + U16 unwanted)
    local prefBlob = result.getDataString(resultId, "preferred_lists") or ""
    data.preferred = {}
    for i = 1, MAX_PREFERRED_SLOTS do
        local offset = (i - 1) * 5 + 1
        if offset + 4 <= #prefBlob then
            local active = string.byte(prefBlob, offset)
            local prefRaceId = string.byte(prefBlob, offset + 1) + string.byte(prefBlob, offset + 2) * 256
            local unwRaceId = string.byte(prefBlob, offset + 3) + string.byte(prefBlob, offset + 4) * 256
            data.preferred[i] = {
                active = active ~= 0,
                preferredRaceId = prefRaceId,
                unwantedRaceId = unwRaceId,
            }
        else
            data.preferred[i] = {active = false, preferredRaceId = 0, unwantedRaceId = 0}
        end
    end

    -- Load current creatures list (BLOB: 13 bytes per creature)
    local creaBlob = result.getDataString(resultId, "current_creatures_list") or ""
    data.creatures = {}
    for i = 1, 3 do
        local offset = (i - 1) * 13 + 1
        if offset + 12 <= #creaBlob then
            local raceId = string.byte(creaBlob, offset) + string.byte(creaBlob, offset + 1) * 256
            local reqKills = string.byte(creaBlob, offset + 2) + string.byte(creaBlob, offset + 3) * 256
            local rewardExp = string.byte(creaBlob, offset + 4) + string.byte(creaBlob, offset + 5) * 256 +
                string.byte(creaBlob, offset + 6) * 65536 + string.byte(creaBlob, offset + 7) * 16777216
            local rewardPts = string.byte(creaBlob, offset + 8)
            local curKills = string.byte(creaBlob, offset + 9) + string.byte(creaBlob, offset + 10) * 256
            local claimState = string.byte(creaBlob, offset + 11)
            local grade = string.byte(creaBlob, offset + 12)
            data.creatures[i] = {
                raceId = raceId,
                requiredKills = reqKills,
                rewardExp = rewardExp,
                rewardBountyPoints = rewardPts,
                currentKills = curKills,
                claimState = claimState,
                grade = grade,
                taskIndex = i - 1,
            }
        end
    end

    result.free(resultId)
    return data
end

function TaskBoard.saveBountyToDB(playerGuid, data)
    if not data then return end

    local prefBlob = ""
    for i = 1, MAX_PREFERRED_SLOTS do
        local slot = data.preferred[i] or {active = false, preferredRaceId = 0, unwantedRaceId = 0}
        local active = slot.active and 1 or 0
        local prefId = slot.preferredRaceId or 0
        local unwId = slot.unwantedRaceId or 0
        prefBlob = prefBlob .. string.char(active, prefId % 256, math.floor(prefId / 256),
            unwId % 256, math.floor(unwId / 256))
    end

    local creaBlob = ""
    for i = 1, 3 do
        local c = data.creatures[i]
        if c then
            local re = c.rewardExp or 0
            creaBlob = creaBlob .. string.char(
                (c.raceId or 0) % 256, math.floor((c.raceId or 0) / 256),
                (c.requiredKills or 0) % 256, math.floor((c.requiredKills or 0) / 256),
                re % 256, math.floor(re / 256) % 256, math.floor(re / 65536) % 256, math.floor(re / 16777216) % 256,
                c.rewardBountyPoints or 0,
                (c.currentKills or 0) % 256, math.floor((c.currentKills or 0) / 256),
                c.claimState or 0,
                c.grade or 0
            )
        else
            creaBlob = creaBlob .. string.char(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        end
    end

    local t = data.activeTask or {}
    db.query(string.format(
        "UPDATE `player_bounty_tasks` SET `state` = %d, `difficulty` = %d, `bounty_points` = %d, " ..
        "`reroll_tokens` = %d, `free_reroll` = %d, " ..
        "`active_raceid` = %d, `active_kills` = %d, `active_required_kills` = %d, " ..
        "`active_reward_exp` = %d, `active_reward_points` = %d, `active_task_grade` = %d, " ..
        "`active_task_difficulty` = %d, " ..
        "`talisman_damage_level` = %d, `talisman_lifeleech_level` = %d, " ..
        "`talisman_loot_level` = %d, `talisman_bestiary_level` = %d, " ..
        "`preferred_lists` = %s, `current_creatures_list` = %s " ..
        "WHERE `player_id` = %d",
        data.state or 0, data.difficulty or 0, data.bountyPoints or 0,
        data.rerollTokens or 0, data.freeRerollTimestamp or 0,
        t.raceId or 0, t.currentKills or 0, t.requiredKills or 0,
        t.rewardExp or 0, t.rewardBountyPoints or 0, t.grade or 0,
        data.difficulty or 0,
        (data.talisman[1] or {}).level or 0, (data.talisman[2] or {}).level or 0,
        (data.talisman[3] or {}).level or 0, (data.talisman[4] or {}).level or 0,
        db.escapeString(prefBlob), db.escapeString(creaBlob),
        playerGuid
    ))
end

-- ============================================================================
-- Task generation
-- ============================================================================

function TaskBoard.getRandomCreatures(count, difficulty, excludeRaceIds)
    local creatures = {}
    local usedRaceIds = {}
    for _, id in ipairs(excludeRaceIds or {}) do
        usedRaceIds[id] = true
    end

    -- Get all valid bestiary monsters
    local allMonsters = {}
    local resultId = db.storeQuery("SELECT DISTINCT `raceid` FROM `player_bestiary_kills` WHERE `raceid` > 0")
    if resultId ~= false then
        repeat
            local raceId = result.getDataInt(resultId, "raceid")
            if not usedRaceIds[raceId] then
                table.insert(allMonsters, raceId)
            end
        until not result.next(resultId)
        result.free(resultId)
    end

    if #allMonsters == 0 then
        return creatures
    end

    -- Shuffle and pick
    for i = #allMonsters, 2, -1 do
        local j = math.random(i)
        allMonsters[i], allMonsters[j] = allMonsters[j], allMonsters[i]
    end

    local diffConfig = BOUNTY_DIFFICULTY[difficulty] or BOUNTY_DIFFICULTY[0]
    for i = 1, math.min(count, #allMonsters) do
        local raceId = allMonsters[i]
        local reqKills = math.random(diffConfig.minKills, diffConfig.maxKills)
        local grade = GRADE_NORMAL
        local roll = math.random(100)
        if roll <= 5 then
            grade = GRADE_GOLD
        elseif roll <= 20 then
            grade = GRADE_SILVER
        end

        -- Get creature exp from bestiary data
        local creatureExp = 1000 -- fallback
        local mResult = db.storeQuery("SELECT `kills` FROM `player_bestiary_kills` WHERE `raceid` = " .. raceId)
        if mResult ~= false then
            result.free(mResult)
        end

        local baseExp = creatureExp * math.random(diffConfig.expMin, diffConfig.expMax)
        if grade == GRADE_SILVER then baseExp = baseExp * 2
        elseif grade == GRADE_GOLD then baseExp = baseExp * 4 end

        table.insert(creatures, {
            raceId = raceId,
            requiredKills = reqKills,
            rewardExp = baseExp,
            rewardBountyPoints = diffConfig.points,
            currentKills = 0,
            claimState = 0,
            grade = grade,
            taskIndex = i - 1,
        })
    end

    return creatures
end

-- ============================================================================
-- Open bounty (option 0)
-- ============================================================================

function TaskBoard.openBounty(player)
    local guid = player:getGuid()
    local bounty = TaskBoard.bountyCache[guid]
    if not bounty then return end

    -- If state is NONE, generate new selection
    if bounty.state == STATE_NONE then
        bounty.creatures = TaskBoard.getRandomCreatures(3, bounty.difficulty)
        bounty.state = STATE_SELECTION
    end

    TaskBoard.sendBountyTaskData(player)
end

-- ============================================================================
-- Select task (option 5)
-- ============================================================================

function TaskBoard.selectBountyTask(player, taskIndex)
    local guid = player:getGuid()
    local bounty = TaskBoard.bountyCache[guid]
    if not bounty or bounty.state ~= STATE_SELECTION then return end

    local creature = bounty.creatures[taskIndex + 1]
    if not creature then return end

    bounty.activeTask = {
        raceId = creature.raceId,
        requiredKills = creature.requiredKills,
        currentKills = 0,
        rewardExp = creature.rewardExp,
        rewardBountyPoints = creature.rewardBountyPoints,
        grade = creature.grade,
        taskIndex = taskIndex,
    }
    bounty.state = STATE_ACTIVE
    bounty.creatures = {}

    TaskBoard.sendBountyTaskData(player)
end

-- ============================================================================
-- Kill tracking
-- ============================================================================

function TaskBoard.onBountyKill(player, raceId)
    if not configManager.getBoolean(configKeys.BOUNTY_TASKS_ENABLED) then return end

    local guid = player:getGuid()
    local bounty = TaskBoard.bountyCache[guid]
    if not bounty or bounty.state ~= STATE_ACTIVE then return end
    if bounty.activeTask.raceId ~= raceId then return end

    bounty.activeTask.currentKills = bounty.activeTask.currentKills + 1

    if bounty.activeTask.currentKills >= bounty.activeTask.requiredKills then
        bounty.state = STATE_COMPLETED
        player:sendTextMessage(MESSAGE_STATUS, "You have completed your bounty task! Claim your reward.")
    end

    TaskBoard.sendBountyTaskData(player)
    TaskBoard.saveBountyToDB(guid, bounty)
end

-- ============================================================================
-- Claim reward (option 6)
-- ============================================================================

function TaskBoard.claimBountyReward(player)
    local guid = player:getGuid()
    local bounty = TaskBoard.bountyCache[guid]
    if not bounty or bounty.state ~= STATE_COMPLETED then return end

    local t = bounty.activeTask

    -- Grant exp
    if t.rewardExp and t.rewardExp > 0 then
        player:addExperience(t.rewardExp, false)
    end

    -- Grant bounty points
    bounty.bountyPoints = bounty.bountyPoints + (t.rewardBountyPoints or 0)

    -- Grant reroll token
    bounty.rerollTokens = math.min(bounty.rerollTokens + 1, MAX_REROLL_TOKENS)

    -- Reset to NONE and generate new selection
    bounty.state = STATE_NONE
    bounty.activeTask = {}
    bounty.creatures = TaskBoard.getRandomCreatures(3, bounty.difficulty)

    if #bounty.creatures > 0 then
        bounty.state = STATE_SELECTION
    end

    TaskBoard.sendBountyTaskData(player)
    TaskBoard.saveBountyToDB(guid, bounty)
end

-- ============================================================================
-- Reroll (option 3)
-- ============================================================================

function TaskBoard.rerollBounty(player)
    local guid = player:getGuid()
    local bounty = TaskBoard.bountyCache[guid]
    if not bounty then return end

    if bounty.rerollTokens <= 0 then
        player:sendTextMessage(MESSAGE_STATUS_SMALL, "You don't have any reroll tokens.")
        TaskBoard.sendBountyTaskData(player)
        return
    end

    bounty.rerollTokens = bounty.rerollTokens - 1
    bounty.creatures = TaskBoard.getRandomCreatures(3, bounty.difficulty)
    bounty.state = #bounty.creatures > 0 and STATE_SELECTION or STATE_NONE

    TaskBoard.sendBountyTaskData(player)
    TaskBoard.saveBountyToDB(guid, bounty)
end

-- ============================================================================
-- Claim daily reroll (option 4)
-- ============================================================================

function TaskBoard.claimDailyReroll(player)
    local guid = player:getGuid()
    local bounty = TaskBoard.bountyCache[guid]
    if not bounty then return end

    if bounty.freeRerollTimestamp > os.time() then
        player:sendTextMessage(MESSAGE_STATUS_SMALL, "Daily reroll is not ready yet.")
        TaskBoard.sendBountyTaskData(player)
        return
    end

    if bounty.rerollTokens >= MAX_REROLL_TOKENS then
        player:sendTextMessage(MESSAGE_STATUS_SMALL, "You already have maximum reroll tokens.")
        TaskBoard.sendBountyTaskData(player)
        return
    end

    bounty.rerollTokens = bounty.rerollTokens + 1
    bounty.freeRerollTimestamp = os.time() + FREE_REROLL_COOLDOWN

    TaskBoard.sendBountyTaskData(player)
    TaskBoard.saveBountyToDB(guid, bounty)
end

-- ============================================================================
-- Change difficulty (option 2)
-- ============================================================================

function TaskBoard.changeBountyDifficulty(player, difficulty)
    local guid = player:getGuid()
    local bounty = TaskBoard.bountyCache[guid]
    if not bounty then return end

    if difficulty < 0 or difficulty > 3 then return end
    if bounty.state == STATE_ACTIVE then
        player:sendTextMessage(MESSAGE_STATUS_SMALL, "You can't change difficulty while a task is active.")
        TaskBoard.sendBountyTaskData(player)
        return
    end

    bounty.difficulty = difficulty
    TaskBoard.sendBountyTaskData(player)
    TaskBoard.saveBountyToDB(guid, bounty)
end

-- ============================================================================
-- Talisman upgrade (option 7)
-- ============================================================================

function TaskBoard.upgradeTalisman(player, pathIndex)
    local guid = player:getGuid()
    local bounty = TaskBoard.bountyCache[guid]
    if not bounty then return end

    if pathIndex < 0 or pathIndex > 3 then return end

    local talisman = bounty.talisman[pathIndex + 1]
    if not talisman then return end

    local maxLevel = pathIndex == 3 and 180 or 166
    if talisman.level >= maxLevel then
        player:sendTextMessage(MESSAGE_STATUS_SMALL, "This talisman is already at maximum level.")
        TaskBoard.sendBountyTaskData(player)
        return
    end

    local cost = 5 + talisman.level * 12
    if bounty.bountyPoints < cost then
        player:sendTextMessage(MESSAGE_STATUS_SMALL, "You don't have enough bounty points.")
        TaskBoard.sendBountyTaskData(player)
        return
    end

    bounty.bountyPoints = bounty.bountyPoints - cost
    talisman.level = talisman.level + 1

    TaskBoard.sendBountyTaskData(player)
    TaskBoard.saveBountyToDB(guid, bounty)
end

-- ============================================================================
-- Preferred / Unwanted lists
-- ============================================================================

function TaskBoard.unlockPreferredSlot(player, slot)
    local guid = player:getGuid()
    local bounty = TaskBoard.bountyCache[guid]
    if not bounty then return end

    if slot < 1 or slot > MAX_PREFERRED_SLOTS then return end

    local slotData = bounty.preferred[slot]
    if slotData and slotData.active then
        player:sendTextMessage(MESSAGE_STATUS_SMALL, "This slot is already unlocked.")
        TaskBoard.sendBountyTaskData(player)
        return
    end

    local cost = SLOT_UNLOCK_COSTS[slot] or 0
    if bounty.bountyPoints < cost then
        player:sendTextMessage(MESSAGE_STATUS_SMALL, "You don't have enough bounty points.")
        TaskBoard.sendBountyTaskData(player)
        return
    end

    bounty.bountyPoints = bounty.bountyPoints - cost
    bounty.preferred[slot] = {active = true, preferredRaceId = 0, unwantedRaceId = 0}

    TaskBoard.sendBountyTaskData(player)
    TaskBoard.saveBountyToDB(guid, bounty)
end

function TaskBoard.clearPreferred(player, slot)
    local guid = player:getGuid()
    local bounty = TaskBoard.bountyCache[guid]
    if not bounty then return end

    local slotData = bounty.preferred[slot]
    if not slotData or not slotData.active then return end

    if bounty.bountyPoints < PREFERRED_CHANGE_COST then
        player:sendTextMessage(MESSAGE_STATUS_SMALL, "You don't have enough bounty points.")
        TaskBoard.sendBountyTaskData(player)
        return
    end

    bounty.bountyPoints = bounty.bountyPoints - PREFERRED_CHANGE_COST
    slotData.preferredRaceId = 0

    TaskBoard.sendBountyTaskData(player)
    TaskBoard.saveBountyToDB(guid, bounty)
end

function TaskBoard.clearUnwanted(player, slot)
    local guid = player:getGuid()
    local bounty = TaskBoard.bountyCache[guid]
    if not bounty then return end

    local slotData = bounty.preferred[slot]
    if not slotData or not slotData.active then return end

    if bounty.bountyPoints < PREFERRED_CHANGE_COST then
        player:sendTextMessage(MESSAGE_STATUS_SMALL, "You don't have enough bounty points.")
        TaskBoard.sendBountyTaskData(player)
        return
    end

    bounty.bountyPoints = bounty.bountyPoints - PREFERRED_CHANGE_COST
    slotData.unwantedRaceId = 0

    TaskBoard.sendBountyTaskData(player)
    TaskBoard.saveBountyToDB(guid, bounty)
end

function TaskBoard.assignPreferred(player, slot, raceId)
    local guid = player:getGuid()
    local bounty = TaskBoard.bountyCache[guid]
    if not bounty then return end

    local slotData = bounty.preferred[slot]
    if not slotData or not slotData.active then return end

    if bounty.bountyPoints < PREFERRED_CHANGE_COST then
        player:sendTextMessage(MESSAGE_STATUS_SMALL, "You don't have enough bounty points.")
        TaskBoard.sendBountyTaskData(player)
        return
    end

    bounty.bountyPoints = bounty.bountyPoints - PREFERRED_CHANGE_COST
    slotData.preferredRaceId = raceId

    TaskBoard.sendBountyTaskData(player)
    TaskBoard.saveBountyToDB(guid, bounty)
end

function TaskBoard.assignUnwanted(player, slot, raceId)
    local guid = player:getGuid()
    local bounty = TaskBoard.bountyCache[guid]
    if not bounty then return end

    local slotData = bounty.preferred[slot]
    if not slotData or not slotData.active then return end

    if bounty.bountyPoints < PREFERRED_CHANGE_COST then
        player:sendTextMessage(MESSAGE_STATUS_SMALL, "You don't have enough bounty points.")
        TaskBoard.sendBountyTaskData(player)
        return
    end

    bounty.bountyPoints = bounty.bountyPoints - PREFERRED_CHANGE_COST
    slotData.unwantedRaceId = raceId

    TaskBoard.sendBountyTaskData(player)
    TaskBoard.saveBountyToDB(guid, bounty)
end
