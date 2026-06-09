-- Task Board System (Bounty / Weekly / Shop / Soulseals)
-- Opcode 0x5F (client->server), 0x53 (server->client), 0xEE (resource balance)

if not TaskBoard then
    TaskBoard = {}
end

TaskBoard.RESOURCE_TASK_HUNTING = 0x32
TaskBoard.RESOURCE_BOUNTY_POINTS = 0x5E
TaskBoard.RESOURCE_SOULSEAL_POINTS = 0x60

TaskBoard.OPCODE_TASK_BOARD = 0x53
TaskBoard.OPCODE_RESOURCE_BALANCE = 0xEE

TaskBoard.bountyCache = TaskBoard.bountyCache or {}
TaskBoard.weeklyCache = TaskBoard.weeklyCache or {}

-- ============================================================================
-- Send helpers
-- ============================================================================

function TaskBoard.sendResourceBalance(player, resourceType, value)
    local out = NetworkMessage(player)
    out:addByte(TaskBoard.OPCODE_RESOURCE_BALANCE)
    out:addByte(resourceType)
    out:addU64(value)
    out:sendToPlayer(player)
end

function TaskBoard.sendAllResourceBalances(player)
    local guid = player:getGuid()
    local bounty = TaskBoard.bountyCache[guid]
    local weekly = TaskBoard.weeklyCache[guid]
    local bountyPoints = bounty and bounty.bountyPoints or 0
    local htp = TaskBoard.getHuntingTaskPoints(player)
    local soulseals = weekly and weekly.soulsealsPoints or 0
    TaskBoard.sendResourceBalance(player, TaskBoard.RESOURCE_TASK_HUNTING, htp)
    TaskBoard.sendResourceBalance(player, TaskBoard.RESOURCE_BOUNTY_POINTS, bountyPoints)
    TaskBoard.sendResourceBalance(player, TaskBoard.RESOURCE_SOULSEAL_POINTS, soulseals)
end

function TaskBoard.getHuntingTaskPoints(player)
    local resultId = db.storeQuery("SELECT `points` FROM `player_hunting_task_points` WHERE `player_id` = " .. player:getGuid())
    if resultId ~= false then
        local pts = result.getDataLong(resultId, "points")
        result.free(resultId)
        return pts
    end
    return 0
end

function TaskBoard.setHuntingTaskPoints(player, points)
    db.query("INSERT INTO `player_hunting_task_points` (`player_id`, `points`) VALUES (" ..
        player:getGuid() .. ", " .. points .. ") ON DUPLICATE KEY UPDATE `points` = " .. points)
end

function TaskBoard.addHuntingTaskPoints(player, amount)
    local current = TaskBoard.getHuntingTaskPoints(player)
    TaskBoard.setHuntingTaskPoints(player, current + amount)
end

-- ============================================================================
-- Send bounty task data (opcode 0x53 subtype 0)
-- ============================================================================

function TaskBoard.sendBountyTaskData(player)
    if not configManager.getBoolean(configKeys.BOUNTY_TASKS_ENABLED) then return end

    local guid = player:getGuid()
    local bounty = TaskBoard.bountyCache[guid]
    if not bounty then return end

    TaskBoard.sendAllResourceBalances(player)

    local out = NetworkMessage(player)
    out:addByte(TaskBoard.OPCODE_TASK_BOARD)
    out:addByte(0x00) -- subtype BOUNTY

    if bounty.state == 2 then
        -- ACTIVE: single creature
        local t = bounty.activeTask
        out:addByte(1)
        out:addByte(t.taskIndex or 0)
        out:addU16(t.raceId or 0)
        out:addU16(t.requiredKills or 0)
        out:addU32(t.rewardExp or 0)
        out:addByte(t.rewardBountyPoints or 0)
        out:addU16(t.currentKills or 0)
        out:addByte(1) -- claimState: active (no click)
        out:addByte(t.grade or 0)
    elseif bounty.state == 3 then
        -- COMPLETED: single creature with claim button
        local t = bounty.activeTask
        out:addByte(1)
        out:addByte(t.taskIndex or 0)
        out:addU16(t.raceId or 0)
        out:addU16(t.requiredKills or 0)
        out:addU32(t.rewardExp or 0)
        out:addByte(t.rewardBountyPoints or 0)
        out:addU16(t.currentKills or 0)
        out:addByte(2) -- claimState: claimable
        out:addByte(t.grade or 0)
    elseif bounty.state == 1 and bounty.creatures and #bounty.creatures > 0 then
        -- SELECTION: 3 creatures to choose
        out:addByte(#bounty.creatures)
        for i, c in ipairs(bounty.creatures) do
            out:addByte(i - 1)
            out:addU16(c.raceId or 0)
            out:addU16(c.requiredKills or 0)
            out:addU32(c.rewardExp or 0)
            out:addByte(c.rewardBountyPoints or 0)
            out:addU16(c.currentKills or 0)
            out:addByte(0) -- claimState: select
            out:addByte(c.grade or 0)
        end
    else
        -- NONE: empty
        out:addByte(0)
    end

    -- Trailer
    out:addByte(bounty.rerollTokens or 0)
    local rerollMode = 1 -- timer running
    if (bounty.rerollTokens or 0) >= 10 then
        rerollMode = 2 -- limit reached
    elseif (bounty.freeRerollTimestamp or 0) <= os.time() then
        rerollMode = 0 -- daily claimable
    end
    out:addByte(rerollMode)
    out:addByte(bounty.difficulty or 0)

    -- 4 talisman paths
    local talisman = bounty.talisman or {}
    for i = 1, 4 do
        local t = talisman[i] or {level = 0}
        out:addByte(t.level or 0)
        out:addByte(0) -- multiplier2
        local canUpgrade = (t.level or 0) < 166 and 1 or 0
        if i == 4 then canUpgrade = (t.level or 0) < 180 and 1 or 0 end
        out:addByte(canUpgrade)
        local cost = 5 + (t.level or 0) * 12
        out:addU16(canUpgrade > 0 and cost or 0)
    end

    -- Preferred slots
    local preferred = bounty.preferred or {}
    out:addByte(#preferred)
    for _, slot in ipairs(preferred) do
        out:addByte(slot.active and 1 or 0)
        out:addU16(slot.preferredRaceId or 0)
        out:addU16(slot.unwantedRaceId or 0)
    end

    out:sendToPlayer(player)
end

-- ============================================================================
-- Send weekly task data (opcode 0x53 subtype 1)
-- ============================================================================

function TaskBoard.sendWeeklyTaskData(player)
    if not configManager.getBoolean(configKeys.WEEKLY_TASKS_ENABLED) then return end

    local guid = player:getGuid()
    local weekly = TaskBoard.weeklyCache[guid]
    if not weekly then return end

    local out = NetworkMessage(player)
    out:addByte(TaskBoard.OPCODE_TASK_BOARD)
    out:addByte(0x01) -- subtype WEEKLY

    out:addU16(weekly.anyCreatureTotalKills or 0)
    out:addU16(weekly.anyCreatureCurrentKills or 0)

    -- Kill tasks
    local killTasks = weekly.killTasks or {}
    out:addByte(#killTasks)
    for _, task in ipairs(killTasks) do
        out:addU16(task.raceId or 0)
        out:addU16(task.totalKills or 0)
        out:addU16(task.currentKills or 0)
    end

    -- Delivery tasks
    local deliveryTasks = weekly.deliveryTasks or {}
    out:addByte(#deliveryTasks)
    for _, task in ipairs(deliveryTasks) do
        out:addByte(task.index or 0)
        out:addU16(task.itemId or 0)
        out:addByte(0) -- unknown1
        out:addByte(0) -- unknown2
        out:addU32(task.totalItems or 0)
        if task.delivered and task.delivered ~= 0 then
            out:addU32(task.totalItems or 0)
        else
            local available = player:getItemCount(task.itemId or 0) or 0
            out:addU32(available)
        end
        out:addByte(task.delivered or 0)
    end

    local level = player:getLevel()
    local diffMult = weekly.difficultyMultiplier or 0
    local killExp = TaskBoard.getWeeklyKillExp(level, diffMult)
    local deliveryExp = TaskBoard.getWeeklyDeliveryExp(level, diffMult)

    out:addByte(diffMult)
    out:addU32(killExp)
    out:addU32(deliveryExp)
    out:addByte(weekly.completedKillTasks or 0)
    out:addByte(weekly.completedDeliveryTasks or 0)
    out:addByte(weekly.weeklyProgressFinished or 0)
    out:addByte(TaskBoard.getUnlockedDifficulty(level))
    out:addU32(TaskBoard.getWeeklyResetTimestamp())
    out:addByte(weekly.hasExpansion and 1 or 0)
    out:addU32(weekly.rewardHuntingTasksPoints or 0)
    out:addU32(weekly.rewardSoulseals or 0)

    out:sendToPlayer(player)
end

-- ============================================================================
-- Send shop data (opcode 0x53 subtype 2)
-- ============================================================================

function TaskBoard.sendShopData(player)
    if not configManager.getBoolean(configKeys.BOUNTY_TASKS_ENABLED) then return end

    TaskBoard.sendResourceBalance(player, TaskBoard.RESOURCE_TASK_HUNTING, TaskBoard.getHuntingTaskPoints(player))

    local offers = TaskBoard.getShopOffers()
    local out = NetworkMessage(player)
    out:addByte(TaskBoard.OPCODE_TASK_BOARD)
    out:addByte(0x02) -- subtype HUNT_SHOP

    out:addByte(#offers)
    for _, offer in ipairs(offers) do
        if offer.offerType == 4 then
            -- BONUS_PROMOTION
            out:addByte(4)
            out:addU16(offer.purchased or 0)
            out:addU32(offer.nextCost or 0)
            out:addByte(offer.status or 0)
        else
            local clientType = offer.offerType
            if clientType == 5 then clientType = 0 end -- WEEKLY_EXPANSION -> ITEM
            out:addByte(clientType)
            out:addString(offer.name or "")
            out:addString(offer.description or "")
            out:addU32(offer.looktypeOrItemId or 0)
            if offer.offerType == 2 then -- OUTFIT
                out:addByte(offer.addon or 0)
            end
            if offer.offerType == 3 then -- ITEM_DOUBLE
                out:addU32(offer.itemId2 or 0)
            end
            out:addU32(offer.price or 0)
            out:addByte(offer.status or 0)
        end
    end

    out:sendToPlayer(player)
end

-- ============================================================================
-- Weekly helper functions
-- ============================================================================

function TaskBoard.getWeeklyKillExp(level, difficulty)
    local base
    if level <= 82 then
        base = 25 * level * level - 75 * level + 100
    elseif level <= 999 then
        base = math.floor(1994.008 * level + 0.5)
    else
        base = 2 * level * level - 6 * level + 8
    end
    local cap = ({200000, 800000, 3000000, 999999999})[difficulty + 1] or 200000
    return math.min(base, cap)
end

function TaskBoard.getWeeklyDeliveryExp(level, difficulty)
    return TaskBoard.getWeeklyKillExp(level, difficulty)
end

function TaskBoard.getUnlockedDifficulty(level)
    if level >= 500 then return 3 end
    if level >= 300 then return 2 end
    if level >= 150 then return 1 end
    return 0
end

function TaskBoard.getWeeklyResetTimestamp()
    -- Next Monday 10:00 CET (UTC+1)
    local now = os.time()
    local dayOfWeek = tonumber(os.date("%w", now)) -- 0=Sunday
    local daysUntilMonday = (8 - dayOfWeek) % 7
    if daysUntilMonday == 0 then daysUntilMonday = 7 end
    local nextMonday = now + daysUntilMonday * 86400
    local resetTime = os.time({
        year = os.date("%Y", nextMonday),
        month = os.date("%m", nextMonday),
        day = os.date("%d", nextMonday),
        hour = 10, min = 0, sec = 0
    })
    -- Adjust for CET (UTC+1)
    return resetTime - 3600
end

function TaskBoard.getHTPMultiplier(completedTasks)
    if completedTasks >= 17 then return 8 end
    if completedTasks >= 13 then return 5 end
    if completedTasks >= 9 then return 3 end
    if completedTasks >= 5 then return 2 end
    return 1
end

function TaskBoard.getHTPPerKillTask(difficulty)
    return ({25, 50, 100, 110})[difficulty + 1] or 25
end

-- ============================================================================
-- Shop offers (loaded from Lua config)
-- ============================================================================

function TaskBoard.getShopOffers()
    return HUNT_TASK_SHOP_OFFERS or {}
end

-- ============================================================================
-- 0x5F Action dispatch
-- ============================================================================

local actionHandler = PacketHandler(0x5F)

function actionHandler.onReceive(player, msg)
    if not configManager.getBoolean(configKeys.TASK_HUNTING_SYSTEM_ENABLED) then return end
    if not player:isUsingOtClient() then return end

    local option = msg:getByte()
    local guid = player:getGuid()

    if option == 0 then
        -- Open Bounty
        if configManager.getBoolean(configKeys.BOUNTY_TASKS_ENABLED) then
            TaskBoard.openBounty(player)
        end
    elseif option == 1 then
        -- Open Weekly
        if configManager.getBoolean(configKeys.WEEKLY_TASKS_ENABLED) then
            TaskBoard.openWeekly(player)
        end
    elseif option == 2 then
        -- Change Difficulty
        local difficulty = msg:getByte()
        if configManager.getBoolean(configKeys.BOUNTY_TASKS_ENABLED) then
            TaskBoard.changeBountyDifficulty(player, difficulty)
        end
    elseif option == 3 then
        -- Reroll Tasks
        if configManager.getBoolean(configKeys.BOUNTY_TASKS_ENABLED) then
            TaskBoard.rerollBounty(player)
        end
    elseif option == 4 then
        -- Claim Daily Reroll
        if configManager.getBoolean(configKeys.BOUNTY_TASKS_ENABLED) then
            TaskBoard.claimDailyReroll(player)
        end
    elseif option == 5 then
        -- Select Task
        local taskIndex = msg:getByte()
        if configManager.getBoolean(configKeys.BOUNTY_TASKS_ENABLED) then
            TaskBoard.selectBountyTask(player, taskIndex)
        end
    elseif option == 6 then
        -- Claim Reward
        if configManager.getBoolean(configKeys.BOUNTY_TASKS_ENABLED) then
            TaskBoard.claimBountyReward(player)
        end
    elseif option == 7 then
        -- Talisman Upgrade
        local pathIndex = msg:getByte()
        if configManager.getBoolean(configKeys.BOUNTY_TASKS_ENABLED) then
            TaskBoard.upgradeTalisman(player, pathIndex)
        end
    elseif option == 8 then
        -- Weekly Deliver
        local taskIndex = msg:getByte()
        if configManager.getBoolean(configKeys.WEEKLY_TASKS_ENABLED) then
            TaskBoard.deliverWeeklyTask(player, taskIndex)
        end
    elseif option == 9 then
        -- Weekly Select Difficulty
        local difficulty = msg:getByte()
        if configManager.getBoolean(configKeys.WEEKLY_TASKS_ENABLED) then
            TaskBoard.selectWeeklyDifficulty(player, difficulty)
        end
    elseif option == 10 then
        -- Open Hunt Shop
        if configManager.getBoolean(configKeys.BOUNTY_TASKS_ENABLED) then
            TaskBoard.sendShopData(player)
        end
    elseif option == 11 then
        -- Buy Shop Offer
        local offerIndex = msg:getByte()
        if configManager.getBoolean(configKeys.BOUNTY_TASKS_ENABLED) then
            TaskBoard.buyShopOffer(player, offerIndex)
        end
    elseif option == 12 then
        -- Unlock Preferred Slot
        local slot = msg:getU16()
        if configManager.getBoolean(configKeys.BOUNTY_TASKS_ENABLED) then
            TaskBoard.unlockPreferredSlot(player, slot)
        end
    elseif option == 13 then
        -- Clear Preferred
        local slot = msg:getU16()
        if configManager.getBoolean(configKeys.BOUNTY_TASKS_ENABLED) then
            TaskBoard.clearPreferred(player, slot)
        end
    elseif option == 14 then
        -- Clear Unwanted
        local slot = msg:getU16()
        if configManager.getBoolean(configKeys.BOUNTY_TASKS_ENABLED) then
            TaskBoard.clearUnwanted(player, slot)
        end
    elseif option == 15 then
        -- Assign Preferred
        local slot = msg:getU16()
        local raceId = msg:getU16()
        if configManager.getBoolean(configKeys.BOUNTY_TASKS_ENABLED) then
            TaskBoard.assignPreferred(player, slot, raceId)
        end
    elseif option == 16 then
        -- Assign Unwanted
        local slot = msg:getU16()
        local raceId = msg:getU16()
        if configManager.getBoolean(configKeys.BOUNTY_TASKS_ENABLED) then
            TaskBoard.assignUnwanted(player, slot, raceId)
        end
    end
end

actionHandler:register()

-- ============================================================================
-- Login / Logout
-- ============================================================================

local loginEvent = CreatureEvent("TaskBoardLogin")

function loginEvent.onLogin(player)
    if not configManager.getBoolean(configKeys.TASK_HUNTING_SYSTEM_ENABLED) then
        return true
    end

    if not player:isUsingOtClient() then
        return true
    end

    local guid = player:getGuid()

    -- Load bounty data
    TaskBoard.bountyCache[guid] = TaskBoard.loadBountyFromDB(guid)

    -- Load weekly data
    TaskBoard.weeklyCache[guid] = TaskBoard.loadWeeklyFromDB(guid)

    -- Check weekly rewards
    local weekly = TaskBoard.weeklyCache[guid]
    if weekly and weekly.needsReward == 1 then
        TaskBoard.distributeWeeklyRewards(player)
    end

    -- Send data
    TaskBoard.sendAllResourceBalances(player)
    if configManager.getBoolean(configKeys.BOUNTY_TASKS_ENABLED) then
        TaskBoard.sendBountyTaskData(player)
    end
    if configManager.getBoolean(configKeys.WEEKLY_TASKS_ENABLED) then
        TaskBoard.sendWeeklyTaskData(player)
    end

    player:registerEvent("TaskBoardLogout")
    return true
end

loginEvent:register()

local logoutEvent = CreatureEvent("TaskBoardLogout")

function logoutEvent.onLogout(player)
    if not configManager.getBoolean(configKeys.TASK_HUNTING_SYSTEM_ENABLED) then
        return true
    end

    local guid = player:getGuid()

    if TaskBoard.bountyCache[guid] then
        TaskBoard.saveBountyToDB(guid, TaskBoard.bountyCache[guid])
        TaskBoard.bountyCache[guid] = nil
    end

    if TaskBoard.weeklyCache[guid] then
        TaskBoard.saveWeeklyToDB(guid, TaskBoard.weeklyCache[guid])
        TaskBoard.weeklyCache[guid] = nil
    end

    return true
end

logoutEvent:register()

-- ============================================================================
-- Server save periodic save
-- ============================================================================

local serverSaveEvent = GlobalEvent("TaskBoardServerSave")

function serverSaveEvent.onShutdown()
    if not configManager.getBoolean(configKeys.TASK_HUNTING_SYSTEM_ENABLED) then
        return true
    end
    -- Save all cached data
    for guid, data in pairs(TaskBoard.bountyCache) do
        TaskBoard.saveBountyToDB(guid, data)
    end
    for guid, data in pairs(TaskBoard.weeklyCache) do
        TaskBoard.saveWeeklyToDB(guid, data)
    end
    return true
end

serverSaveEvent:register()

print("[TaskBoard] Task Board system loaded")
