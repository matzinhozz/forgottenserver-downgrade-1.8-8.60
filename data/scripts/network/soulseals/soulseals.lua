-- Soulseals System
-- Handles: soulseal window (0xBA), fight action, mastered creatures, soulseal points

if not Soulseals then
    Soulseals = {}
end

Soulseals.cache = Soulseals.cache or {} -- [playerGuid] = { mastered = {raceId=true, ...} }

-- ============================================================================
-- DB
-- ============================================================================

function Soulseals.ensureTable()
    db.query([[
        CREATE TABLE IF NOT EXISTS `player_soulseals_mastered` (
            `player_id` INT NOT NULL,
            `raceid` INT UNSIGNED NOT NULL,
            PRIMARY KEY (`player_id`, `raceid`),
            CONSTRAINT `player_soulseals_mastered_fk` FOREIGN KEY (`player_id`) REFERENCES `players` (`id`) ON DELETE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
end
Soulseals.ensureTable()

function Soulseals.loadFromDB(playerGuid)
    local mastered = {}
    local resultId = db.storeQuery("SELECT `raceid` FROM `player_soulseals_mastered` WHERE `player_id` = " .. playerGuid)
    if resultId ~= false then
        repeat
            local raceId = result.getDataInt(resultId, "raceid")
            mastered[raceId] = true
        until not result.next(resultId)
        result.free(resultId)
    end
    return mastered
end

function Soulseals.addMastered(playerGuid, raceId)
    db.query("INSERT IGNORE INTO `player_soulseals_mastered` (`player_id`, `raceid`) VALUES (" ..
        playerGuid .. ", " .. raceId .. ")")
    if Soulseals.cache[playerGuid] then
        Soulseals.cache[playerGuid][raceId] = true
    end
end

function Soulseals.isMastered(playerGuid, raceId)
    local cache = Soulseals.cache[playerGuid]
    if not cache then return false end
    return cache[raceId] == true
end

-- ============================================================================
-- Soulseal Points (stored in weekly cache)
-- ============================================================================

function Soulseals.getPoints(player)
    local guid = player:getGuid()
    local weekly = TaskBoard.weeklyCache[guid]
    if weekly then
        return weekly.soulsealsPoints or 0
    end
    -- Fallback: load from DB
    local resultId = db.storeQuery("SELECT `soulseals_points` FROM `player_weekly_tasks` WHERE `player_id` = " .. guid)
    if resultId ~= false then
        local pts = result.getDataInt(resultId, "soulseals_points")
        result.free(resultId)
        return pts
    end
    return 0
end

function Soulseals.setPoints(player, amount)
    local guid = player:getGuid()
    local weekly = TaskBoard.weeklyCache[guid]
    if weekly then
        weekly.soulsealsPoints = amount
    end
    db.query("UPDATE `player_weekly_tasks` SET `soulseals_points` = " .. amount .. " WHERE `player_id` = " .. guid)
end

function Soulseals.addPoints(player, amount)
    Soulseals.setPoints(player, Soulseals.getPoints(player) + amount)
end

function Soulseals.removePoints(player, amount)
    local current = Soulseals.getPoints(player)
    if current < amount then
        return false
    end
    Soulseals.setPoints(player, current - amount)
    return true
end

-- ============================================================================
-- Send soulseal window (opcode 0xBA server→client)
-- ============================================================================

function Soulseals.sendWindow(player)
    if not configManager.getBoolean(configKeys.SOULSEALS_SYSTEM_ENABLED) then return end
    if not player:isUsingOtClient() then return end

    local guid = player:getGuid()
    local mastered = Soulseals.cache[guid] or {}

    -- Build list of mastered race IDs
    local raceIds = {}
    for raceId, _ in pairs(mastered) do
        table.insert(raceIds, raceId)
    end

    local out = NetworkMessage(player)
    out:addByte(0xBA)
    out:addU16(#raceIds)
    for _, raceId in ipairs(raceIds) do
        out:addU16(raceId)
    end
    out:sendToPlayer(player)

    -- Also send resource balance
    TaskBoard.sendResourceBalance(player, TaskBoard.RESOURCE_SOULSEAL_POINTS, Soulseals.getPoints(player))
end

-- ============================================================================
-- Soulseal fight action (opcode 0xBA client→server)
-- ============================================================================

local soulsealFightHandler = PacketHandler(0xBA)

function soulsealFightHandler.onReceive(player, msg)
    if not configManager.getBoolean(configKeys.SOULPIT_SYSTEM_ENABLED) then return end
    if not player:isUsingOtClient() then return end

    local raceId = msg:getU16()
    if raceId == 0 then return end

    Soulseals.performFight(player, raceId)
end

soulsealFightHandler:register()

function Soulseals.performFight(player, raceId)
    -- Check if player is near an obelisk
    local pos = player:getPosition()
    local nearObelisk = false

    for dx = -1, 1 do
        for dy = -1, 1 do
            local tile = Tile(pos.x + dx, pos.y + dy, pos.z)
            if tile then
                local items = tile:getItems()
                for _, item in ipairs(items) do
                    local itemId = item:getId()
                    if itemId == 47367 or itemId == 47379 then -- obelisk inactive/active
                        nearObelisk = true
                        break
                    end
                end
            end
            if nearObelisk then break end
        end
        if nearObelisk then break end
    end

    if not nearObelisk then
        player:sendTextMessage(MESSAGE_STATUS_SMALL, "You need to be near a soulpit obelisk.")
        return
    end

    -- Check if creature is mastered
    local guid = player:getGuid()
    if not Soulseals.isMastered(guid, raceId) then
        player:sendTextMessage(MESSAGE_STATUS_SMALL, "You haven't mastered this creature yet.")
        return
    end

    -- Get monster type by raceId
    local mType = MonsterType(raceId)
    if not mType then
        player:sendTextMessage(MESSAGE_STATUS_SMALL, "Invalid creature.")
        return
    end

    -- Calculate cost: (bestiaryStars + 1) * 10
    local stars = mType:bestiaryStars() or 0
    local cost = (stars + 1) * 10

    local currentPoints = Soulseals.getPoints(player)
    if currentPoints < cost then
        player:sendTextMessage(MESSAGE_STATUS_SMALL, string.format(
            "You need %d soulseal points (you have %d).", cost, currentPoints))
        return
    end

    -- Deduct points
    Soulseals.removePoints(player, cost)

    -- Spawn creature near the player
    local spawnPos = Position(pos.x + 1, pos.y, pos.z)
    local monster = Game.createMonster(mType:name(), spawnPos, false, true)
    if monster then
        player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format(
            "You spent %d soulseal points to fight %s!", cost, mType:name()))
    else
        player:sendTextMessage(MESSAGE_STATUS_SMALL, "Failed to spawn creature.")
        -- Refund
        Soulseals.addPoints(player, cost)
    end

    -- Update resource balance on client
    TaskBoard.sendResourceBalance(player, TaskBoard.RESOURCE_SOULSEAL_POINTS, Soulseals.getPoints(player))
end

-- ============================================================================
-- Login / Logout
-- ============================================================================

local soulsealLogin = CreatureEvent("SoulsealsLogin")

function soulsealLogin.onLogin(player)
    if not configManager.getBoolean(configKeys.SOULSEALS_SYSTEM_ENABLED) then
        return true
    end

    local guid = player:getGuid()
    Soulseals.cache[guid] = Soulseals.loadFromDB(guid)

    player:registerEvent("SoulsealsLogout")
    return true
end

soulsealLogin:register()

local soulsealLogout = CreatureEvent("SoulsealsLogout")

function soulsealLogout.onLogout(player)
    local guid = player:getGuid()
    Soulseals.cache[guid] = nil
    return true
end

soulsealLogout:register()

print("[Soulseals] Soulseals system loaded")
