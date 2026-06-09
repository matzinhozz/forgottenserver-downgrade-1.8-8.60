-- Weekly Tasks subsystem
-- Handles: generation, kill tracking, delivery, reset, rewards

if not TaskBoard then TaskBoard = {} end

-- ============================================================================
-- Weekly configs
-- ============================================================================

local WEEKLY_KILL_TASKS_BASE = 5
local WEEKLY_KILL_TASKS_EXPANDED = 8
local WEEKLY_DELIVERY_TASKS_BASE = 6
local WEEKLY_DELIVERY_TASKS_EXPANDED = 9

local WEEKLY_ANY_CREATURE_KILLS = {
    [0] = 1000, -- Beginner
    [1] = 2000, -- Adept
    [2] = 3000, -- Expert
    [3] = 4000, -- Master
}

-- ============================================================================
-- DB Load/Save
-- ============================================================================

function TaskBoard.loadWeeklyFromDB(playerGuid)
    local data = {
        hasExpansion = false,
        difficultyMultiplier = 0,
        anyCreatureTotalKills = 0,
        anyCreatureCurrentKills = 0,
        completedKillTasks = 0,
        completedDeliveryTasks = 0,
        killTaskRewardExp = 0,
        deliveryTaskRewardExp = 0,
        rewardHuntingTasksPoints = 0,
        rewardSoulseals = 0,
        soulsealsPoints = 0,
        needsReward = 0,
        weeklyProgressFinished = 0,
        killTasks = {},
        deliveryTasks = {},
    }

    local resultId = db.storeQuery("SELECT * FROM `player_weekly_tasks` WHERE `player_id` = " .. playerGuid)
    if resultId == false then
        db.query("INSERT INTO `player_weekly_tasks` (`player_id`) VALUES (" .. playerGuid .. ")")
        return data
    end

    data.hasExpansion = result.getDataInt(resultId, "has_expansion") ~= 0
    data.difficultyMultiplier = result.getDataInt(resultId, "difficulty")
    data.anyCreatureTotalKills = result.getDataInt(resultId, "any_creature_total_kills")
    data.anyCreatureCurrentKills = result.getDataInt(resultId, "any_creature_current_kills")
    data.completedKillTasks = result.getDataInt(resultId, "completed_kill_tasks")
    data.completedDeliveryTasks = result.getDataInt(resultId, "completed_delivery_tasks")
    data.killTaskRewardExp = result.getDataInt(resultId, "kill_task_reward_exp")
    data.deliveryTaskRewardExp = result.getDataInt(resultId, "delivery_task_reward_exp")
    data.rewardHuntingTasksPoints = result.getDataInt(resultId, "reward_hunting_points")
    data.rewardSoulseals = result.getDataInt(resultId, "reward_soulseals")
    data.soulsealsPoints = result.getDataInt(resultId, "soulseals_points")
    data.needsReward = result.getDataInt(resultId, "needs_reward")
    data.weeklyProgressFinished = result.getDataInt(resultId, "weekly_progress_finished")

    -- Load kill tasks (BLOB: 6 bytes per task: U16 raceId + U16 totalKills + U16 currentKills)
    local killBlob = result.getDataString(resultId, "kill_tasks") or ""
    data.killTasks = {}
    for i = 1, math.floor(#killBlob / 6) do
        local offset = (i - 1) * 6 + 1
        local raceId = string.byte(killBlob, offset) + string.byte(killBlob, offset + 1) * 256
        local totalKills = string.byte(killBlob, offset + 2) + string.byte(killBlob, offset + 3) * 256
        local currentKills = string.byte(killBlob, offset + 4) + string.byte(killBlob, offset + 5) * 256
        table.insert(data.killTasks, {
            raceId = raceId,
            totalKills = totalKills,
            currentKills = currentKills,
        })
    end

    -- Load delivery tasks (BLOB: 10 bytes per task)
    local delBlob = result.getDataString(resultId, "delivery_tasks") or ""
    data.deliveryTasks = {}
    for i = 1, math.floor(#delBlob / 10) do
        local offset = (i - 1) * 10 + 1
        local index = string.byte(delBlob, offset)
        local itemId = string.byte(delBlob, offset + 1) + string.byte(delBlob, offset + 2) * 256
        local totalItems = string.byte(delBlob, offset + 5) + string.byte(delBlob, offset + 6) * 256 * 256 +
            string.byte(delBlob, offset + 7) * 65536
        local delivered = string.byte(delBlob, offset + 9)
        table.insert(data.deliveryTasks, {
            index = index,
            itemId = itemId,
            totalItems = totalItems,
            delivered = delivered,
        })
    end

    result.free(resultId)
    return data
end

function TaskBoard.saveWeeklyToDB(playerGuid, data)
    if not data then return end

    local killBlob = ""
    for _, task in ipairs(data.killTasks or {}) do
        local r = task.raceId or 0
        local t = task.totalKills or 0
        local c = task.currentKills or 0
        killBlob = killBlob .. string.char(r % 256, math.floor(r / 256), t % 256, math.floor(t / 256), c % 256, math.floor(c / 256))
    end

    local delBlob = ""
    for _, task in ipairs(data.deliveryTasks or {}) do
        local idx = task.index or 0
        local itemId = task.itemId or 0
        local total = task.totalItems or 0
        delBlob = delBlob .. string.char(
            idx, itemId % 256, math.floor(itemId / 256),
            0, 0, -- unknown1, unknown2
            total % 256, math.floor(total / 256) % 256, math.floor(total / 65536) % 256, 0,
            task.delivered or 0
        )
    end

    db.query(string.format(
        "UPDATE `player_weekly_tasks` SET `has_expansion` = %s, `difficulty` = %d, " ..
        "`any_creature_total_kills` = %d, `any_creature_current_kills` = %d, " ..
        "`completed_kill_tasks` = %d, `completed_delivery_tasks` = %d, " ..
        "`kill_task_reward_exp` = %d, `delivery_task_reward_exp` = %d, " ..
        "`reward_hunting_points` = %d, `reward_soulseals` = %d, `soulseals_points` = %d, " ..
        "`needs_reward` = %d, `weekly_progress_finished` = %d, " ..
        "`kill_tasks` = %s, `delivery_tasks` = %s " ..
        "WHERE `player_id` = %d",
        data.hasExpansion and "TRUE" or "FALSE",
        data.difficultyMultiplier or 0,
        data.anyCreatureTotalKills or 0, data.anyCreatureCurrentKills or 0,
        data.completedKillTasks or 0, data.completedDeliveryTasks or 0,
        data.killTaskRewardExp or 0, data.deliveryTaskRewardExp or 0,
        data.rewardHuntingTasksPoints or 0, data.rewardSoulseals or 0, data.soulsealsPoints or 0,
        data.needsReward or 0, data.weeklyProgressFinished or 0,
        db.escapeString(killBlob), db.escapeString(delBlob),
        playerGuid
    ))
end

-- ============================================================================
-- Task generation
-- ============================================================================

function TaskBoard.generateWeeklyTasks(player, difficulty)
    local guid = player:getGuid()
    local weekly = TaskBoard.weeklyCache[guid]
    if not weekly then return end

    local level = player:getLevel()
    local maxKillTasks = weekly.hasExpansion and WEEKLY_KILL_TASKS_EXPANDED or WEEKLY_KILL_TASKS_BASE
    local maxDeliveryTasks = weekly.hasExpansion and WEEKLY_DELIVERY_TASKS_EXPANDED or WEEKLY_DELIVERY_TASKS_BASE

    weekly.difficultyMultiplier = difficulty
    weekly.anyCreatureTotalKills = WEEKLY_ANY_CREATURE_KILLS[difficulty] or 1000
    weekly.anyCreatureCurrentKills = 0
    weekly.completedKillTasks = 0
    weekly.completedDeliveryTasks = 0
    weekly.killTaskRewardExp = TaskBoard.getWeeklyKillExp(level, difficulty)
    weekly.deliveryTaskRewardExp = TaskBoard.getWeeklyDeliveryExp(level, difficulty)
    weekly.weeklyProgressFinished = 0
    weekly.needsReward = 0

    -- Generate kill tasks
    weekly.killTasks = {}
    local usedRaceIds = {}
    local allMonsters = {}
    local resultId = db.storeQuery("SELECT DISTINCT `raceid` FROM `player_bestiary_kills` WHERE `raceid` > 0")
    if resultId ~= false then
        repeat
            table.insert(allMonsters, result.getDataInt(resultId, "raceid"))
        until not result.next(resultId)
        result.free(resultId)
    end

    -- Shuffle
    for i = #allMonsters, 2, -1 do
        local j = math.random(i)
        allMonsters[i], allMonsters[j] = allMonsters[j], allMonsters[i]
    end

    local killMultiplier = ({1, 2, 3, 5})[difficulty + 1] or 1
    for i = 1, math.min(maxKillTasks, #allMonsters) do
        local raceId = allMonsters[i]
        local baseKills = math.random(200, 500) * killMultiplier
        table.insert(weekly.killTasks, {
            raceId = raceId,
            totalKills = baseKills,
            currentKills = 0,
        })
        usedRaceIds[raceId] = true
    end

    -- Generate delivery tasks
    weekly.deliveryTasks = {}
    local deliveryItems = WEEKLY_DELIVERY_ITEMS or {}
    for i = 1, math.min(maxDeliveryTasks, #deliveryItems) do
        local item = deliveryItems[i]
        table.insert(weekly.deliveryTasks, {
            index = i - 1,
            itemId = item.itemId,
            totalItems = math.random(item.minAmount or 1, item.maxAmount or 5),
            delivered = 0,
        })
    end

    -- Recalculate rewards
    TaskBoard.recalculateWeeklyRewards(player)

    TaskBoard.sendWeeklyTaskData(player)
    TaskBoard.saveWeeklyToDB(guid, weekly)
end

-- ============================================================================
-- Open weekly (option 1)
-- ============================================================================

function TaskBoard.openWeekly(player)
    local guid = player:getGuid()
    local weekly = TaskBoard.weeklyCache[guid]
    if not weekly then return end

    -- If no tasks and not finished, show difficulty selection
    if #weekly.killTasks == 0 and weekly.weeklyProgressFinished == 0 then
        weekly.weeklyProgressFinished = 1
    end

    TaskBoard.sendWeeklyTaskData(player)
end

-- ============================================================================
-- Select difficulty (option 9)
-- ============================================================================

function TaskBoard.selectWeeklyDifficulty(player, difficulty)
    if difficulty < 0 or difficulty > 3 then return end
    local guid = player:getGuid()
    local weekly = TaskBoard.weeklyCache[guid]
    if not weekly then return end

    local unlocked = TaskBoard.getUnlockedDifficulty(player:getLevel())
    if difficulty > unlocked then
        player:sendTextMessage(MESSAGE_STATUS_SMALL, "Your level is not high enough for this difficulty.")
        TaskBoard.sendWeeklyTaskData(player)
        return
    end

    TaskBoard.generateWeeklyTasks(player, difficulty)
end

-- ============================================================================
-- Kill tracking
-- ============================================================================

function TaskBoard.onWeeklyKill(player, raceId)
    if not configManager.getBoolean(configKeys.WEEKLY_TASKS_ENABLED) then return end

    local guid = player:getGuid()
    local weekly = TaskBoard.weeklyCache[guid]
    if not weekly or weekly.weeklyProgressFinished ~= 0 then return end
    if #weekly.killTasks == 0 then return end

    local updated = false

    -- Update "any creature" counter
    if weekly.anyCreatureCurrentKills < weekly.anyCreatureTotalKills then
        weekly.anyCreatureCurrentKills = weekly.anyCreatureCurrentKills + 1
        updated = true

        if weekly.anyCreatureCurrentKills >= weekly.anyCreatureTotalKills then
            weekly.completedKillTasks = weekly.completedKillTasks + 1
            if weekly.killTaskRewardExp > 0 then
                player:addExperience(weekly.killTaskRewardExp, false)
            end
            player:sendTextMessage(MESSAGE_STATUS, "You have completed the weekly 'any creature' kill task!")
            TaskBoard.recalculateWeeklyRewards(player)
        end
    end

    -- Update specific creature tasks
    for _, task in ipairs(weekly.killTasks) do
        if task.raceId == raceId and task.currentKills < task.totalKills then
            task.currentKills = task.currentKills + 1
            updated = true
            if task.currentKills >= task.totalKills then
                weekly.completedKillTasks = weekly.completedKillTasks + 1
                if weekly.killTaskRewardExp > 0 then
                    player:addExperience(weekly.killTaskRewardExp, false)
                end
                player:sendTextMessage(MESSAGE_STATUS, "You have completed a weekly kill task!")
                TaskBoard.recalculateWeeklyRewards(player)
            end
            break
        end
    end

    if updated then
        TaskBoard.sendWeeklyTaskData(player)
        TaskBoard.saveWeeklyToDB(guid, weekly)
    end
end

-- ============================================================================
-- Delivery (option 8)
-- ============================================================================

function TaskBoard.deliverWeeklyTask(player, taskIndex)
    local guid = player:getGuid()
    local weekly = TaskBoard.weeklyCache[guid]
    if not weekly or weekly.weeklyProgressFinished ~= 0 then return end

    local task = weekly.deliveryTasks[taskIndex + 1]
    if not task or task.delivered ~= 0 then return end

    local available = player:getItemCount(task.itemId) or 0
    if available < task.totalItems then
        player:sendTextMessage(MESSAGE_STATUS_SMALL, "You don't have enough items to deliver.")
        TaskBoard.sendWeeklyTaskData(player)
        return
    end

    -- Remove items
    if not player:removeItem(task.itemId, task.totalItems) then
        player:sendTextMessage(MESSAGE_STATUS_SMALL, "Failed to remove items.")
        TaskBoard.sendWeeklyTaskData(player)
        return
    end

    task.delivered = 1
    weekly.completedDeliveryTasks = weekly.completedDeliveryTasks + 1

    if weekly.deliveryTaskRewardExp > 0 then
        player:addExperience(weekly.deliveryTaskRewardExp, false)
    end

    player:sendTextMessage(MESSAGE_STATUS, "Weekly delivery task completed!")
    TaskBoard.recalculateWeeklyRewards(player)

    TaskBoard.sendWeeklyTaskData(player)
    TaskBoard.saveWeeklyToDB(guid, weekly)
end

-- ============================================================================
-- Reward calculation
-- ============================================================================

function TaskBoard.recalculateWeeklyRewards(player)
    local guid = player:getGuid()
    local weekly = TaskBoard.weeklyCache[guid]
    if not weekly then return end

    local totalCompleted = weekly.completedKillTasks + weekly.completedDeliveryTasks
    local htpPerKill = TaskBoard.getHTPPerKillTask(weekly.difficultyMultiplier)
    local baseHTP = weekly.completedKillTasks * htpPerKill + weekly.completedDeliveryTasks * 75
    local multiplier = TaskBoard.getHTPMultiplier(totalCompleted)
    weekly.rewardHuntingTasksPoints = baseHTP * multiplier
    weekly.rewardSoulseals = totalCompleted
end

-- ============================================================================
-- Weekly rewards distribution (on reset or login with needsReward)
-- ============================================================================

function TaskBoard.distributeWeeklyRewards(player)
    local guid = player:getGuid()
    local weekly = TaskBoard.weeklyCache[guid]
    if not weekly then return end

    local totalCompleted = weekly.completedKillTasks + weekly.completedDeliveryTasks
    if totalCompleted == 0 then
        -- Just reset
        weekly.needsReward = 0
        weekly.weeklyProgressFinished = 1
        TaskBoard.sendWeeklyTaskData(player)
        TaskBoard.saveWeeklyToDB(guid, weekly)
        return
    end

    -- Grant HTP
    local htp = weekly.rewardHuntingTasksPoints or 0
    if htp > 0 then
        TaskBoard.addHuntingTaskPoints(player, htp)
    end

    -- Grant soulseals
    local soulseals = weekly.rewardSoulseals or 0
    if soulseals > 0 then
        weekly.soulsealsPoints = (weekly.soulsealsPoints or 0) + soulseals
    end

    player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format(
        "[Weekly Tasks] Week ended! You completed %d tasks.\n  Hunting Task Points: +%d\n  Soulseals: +%d",
        totalCompleted, htp, soulseals))

    -- Reset weekly data
    weekly.needsReward = 0
    weekly.weeklyProgressFinished = 1
    weekly.killTasks = {}
    weekly.deliveryTasks = {}
    weekly.anyCreatureTotalKills = 0
    weekly.anyCreatureCurrentKills = 0
    weekly.completedKillTasks = 0
    weekly.completedDeliveryTasks = 0
    weekly.rewardHuntingTasksPoints = 0
    weekly.rewardSoulseals = 0

    TaskBoard.sendWeeklyTaskData(player)
    TaskBoard.sendAllResourceBalances(player)
    TaskBoard.saveWeeklyToDB(guid, weekly)
end
