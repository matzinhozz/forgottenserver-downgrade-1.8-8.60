-- Soulpit Arena System
-- Simplified version for TFS 1.8 (no Encounter/Lever/Zone classes)
-- Handles: entrance, fight, waves, boss, exit, soul core items

if not Soulpit then
    Soulpit = {}
end

-- ============================================================================
-- Configuration (customize positions for your map)
-- ============================================================================

Soulpit.config = {
    requiredLevel = 8,
    timeToKick = 10 * 60 * 1000, -- 10 minutes

    -- Obelisk item IDs
    obeliskActive = 47379,
    obeliskInactive = 47367,

    -- Positions (customize for your map)
    obeliskPosition = Position(32375, 31157, 8),
    bossPosition = Position(32376, 31144, 8),
    exitPosition = Position(32373, 31158, 8),

    -- Player lever positions (up to 5 players)
    playerPositions = {
        Position(32375, 31158, 8),
        Position(32375, 31159, 8),
        Position(32375, 31160, 8),
        Position(32375, 31161, 8),
        Position(32375, 31162, 8),
    },

    -- Teleport destinations (one per player)
    teleportPositions = {
        Position(32373, 31151, 8),
        Position(32374, 31151, 8),
        Position(32375, 31151, 8),
        Position(32376, 31151, 8),
        Position(32377, 31151, 8),
    },

    -- Arena bounds (for random spawn positions)
    arenaMin = Position(32362, 31132, 8),
    arenaMax = Position(32390, 31153, 8),

    -- Wave configuration: [wave] = { [stack] = count }
    waves = {
        [1] = {[1] = 7},
        [2] = {[1] = 4, [5] = 3},
        [3] = {[1] = 5, [15] = 2},
        [4] = {[1] = 3, [5] = 3, [40] = 1},
    },

    -- Visual effects per stack
    effects = {
        [1] = CONST_ME_TELEPORT,
        [5] = CONST_ME_ORANGETELEPORT,
        [15] = CONST_ME_REDTELEPORT,
        [40] = CONST_ME_PURPLETELEPORT,
    },

    -- Boss abilities (simplified)
    bossAbilities = {
        "overpower",   -- high crit
        "enrage",      -- damage reduction
        "opressor",    -- debuffs
    },
}

-- ============================================================================
-- Active encounters (in-memory)
-- ============================================================================

Soulpit.activeEncounters = Soulpit.activeEncounters or {} -- [playerGuid] = {monsterName, wave, monsters, kickEvent, ...}

-- ============================================================================
-- Helper: get random position in arena
-- ============================================================================

function Soulpit.getRandomArenaPosition()
    local x = math.random(Soulpit.config.arenaMin.x, Soulpit.config.arenaMax.x)
    local y = math.random(Soulpit.config.arenaMin.y, Soulpit.config.arenaMax.y)
    local z = Soulpit.config.arenaMin.z
    return Position(x, y, z)
end

-- ============================================================================
-- Helper: get monster name from soul core item name
-- ============================================================================

function Soulpit.getMonsterNameFromSoulCore(itemName)
    -- "demon soul core" -> "demon"
    -- "horse soul core (taupe)" -> special handling
    local baseName = itemName:match("^(.-) soul core")
    if not baseName then return nil end

    -- Check variations
    local variations = {
        ["horse soul core (taupe)"] = "Horse",
        ["horse soul core (brown)"] = "Brown Horse",
        ["horse soul core (gray)"] = "Grey Horse",
        ["nomad soul core (basic)"] = "Nomad",
        ["nomad soul core (blue)"] = "Nomad Blue",
        ["nomad soul core (female)"] = "Nomad Female",
        ["butterfly soul core (purple)"] = "Purple Butterfly",
        ["butterfly soul core (blue)"] = "Butterfly",
        ["butterfly soul core (red)"] = "Red Butterfly",
    }

    return variations[itemName:lower()] or baseName
end

-- ============================================================================
-- Start encounter
-- ============================================================================

function Soulpit.startEncounter(player, soulCoreItemName)
    local guid = player:getGuid()

    -- Check if already in encounter
    if Soulpit.activeEncounters[guid] then
        player:sendTextMessage(MESSAGE_STATUS_SMALL, "You are already in a soulpit encounter.")
        return false
    end

    local monsterName = Soulpit.getMonsterNameFromSoulCore(soulCoreItemName)
    if not monsterName then
        player:sendTextMessage(MESSAGE_STATUS_SMALL, "Invalid soul core.")
        return false
    end

    -- Verify monster exists
    local mType = MonsterType(monsterName)
    if not mType then
        player:sendTextMessage(MESSAGE_STATUS_SMALL, "Creature not found: " .. monsterName)
        return false
    end

    -- Find player position in lever list
    local playerPos = player:getPosition()
    local leverIndex = nil
    for i, pos in ipairs(Soulpit.config.playerPositions) do
        if pos.x == playerPos.x and pos.y == playerPos.y and pos.z == playerPos.z then
            leverIndex = i
            break
        end
    end

    if not leverIndex then
        player:sendTextMessage(MESSAGE_STATUS_SMALL, "You must be standing on a lever position.")
        return false
    end

    -- Check level
    if player:getLevel() < Soulpit.config.requiredLevel then
        player:sendTextMessage(MESSAGE_STATUS_SMALL, string.format(
            "You need level %d to enter the soulpit.", Soulpit.config.requiredLevel))
        return false
    end

    -- Create encounter data
    local encounter = {
        monsterName = monsterName,
        wave = 0,
        monsters = {},
        kickEvent = nil,
        players = {player},
        startTime = os.time(),
    }

    Soulpit.activeEncounters[guid] = encounter

    -- Teleport player to arena
    local teleportPos = Soulpit.config.teleportPositions[leverIndex] or Soulpit.config.teleportPositions[1]
    player:teleportTo(teleportPos)
    player:getPosition():sendMagicEffect(CONST_ME_TELEPORT)

    -- Transform obelisk
    Soulpit.config.obeliskPosition:transformItem(Soulpit.config.obeliskInactive, Soulpit.config.obeliskActive)

    -- Set kick timer
    encounter.kickEvent = addEvent(function()
        Soulpit.kickPlayer(guid)
    end, Soulpit.config.timeToKick)

    -- Start first wave
    Soulpit.nextWave(guid)

    player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format(
        "Soulpit started! Defeat the %s soul!", monsterName))
    return true
end

-- ============================================================================
-- Next wave
-- ============================================================================

function Soulpit.nextWave(guid)
    local encounter = Soulpit.activeEncounters[guid]
    if not encounter then return end

    encounter.wave = encounter.wave + 1
    local waveConfig = Soulpit.config.waves[encounter.wave]

    if not waveConfig then
        -- All waves complete - victory!
        Soulpit.victory(guid)
        return
    end

    -- Spawn monsters for this wave
    for stack, count in pairs(waveConfig) do
        for i = 1, count do
            local spawnPos
            if stack == 40 then
                spawnPos = Soulpit.config.bossPosition
            else
                spawnPos = Soulpit.getRandomArenaPosition()
            end

            -- Visual effect before spawn
            local effect = Soulpit.config.effects[stack]
            if effect then
                spawnPos:sendMagicEffect(effect)
            end

            -- Spawn monster
            local monster = Game.createMonster(encounter.monsterName, spawnPos, false, true)
            if monster then
                -- Mark as soulpit monster
                monster:setForgeStack(stack)
                if stack == 40 then
                    -- Boss: apply random ability
                    local ability = Soulpit.config.bossAbilities[math.random(#Soulpit.config.bossAbilities)]
                    Soulpit.applyBossAbility(monster, ability)
                end
                table.insert(encounter.monsters, monster:getId())
            end
        end
    end

    -- Start checking for wave completion
    addEvent(function()
        Soulpit.checkWaveComplete(guid)
    end, 4500) -- check every 4.5 seconds
end

-- ============================================================================
-- Check wave complete
-- ============================================================================

function Soulpit.checkWaveComplete(guid)
    local encounter = Soulpit.activeEncounters[guid]
    if not encounter then return end

    -- Check if all monsters from current wave are dead
    local allDead = true
    for _, monsterId in ipairs(encounter.monsters) do
        local monster = Creature(monsterId)
        if monster and monster:getHealth() > 0 then
            allDead = false
            break
        end
    end

    if allDead then
        encounter.monsters = {}
        Soulpit.nextWave(guid)
    else
        -- Check again later
        addEvent(function()
            Soulpit.checkWaveComplete(guid)
        end, 4500)
    end
end

-- ============================================================================
-- Boss abilities
-- ============================================================================

function Soulpit.applyBossAbility(monster, ability)
    if ability == "overpower" then
        -- High critical chance (simplified - just make it stronger)
        -- In TFS 1.8 we can't easily set crit stats, so we just mark it
        monster:setMaxHealth(monster:getMaxHealth() * 2)
        monster:setHealth(monster:getMaxHealth())
    elseif ability == "enrage" then
        -- Register enrage event for damage reduction
        monster:registerEvent("SoulpitEnrage")
    elseif ability == "opressor" then
        -- Register opressor event for debuffs
        monster:registerEvent("SoulpitOpressor")
    end
end

-- ============================================================================
-- Victory
-- ============================================================================

function Soulpit.victory(guid)
    local encounter = Soulpit.activeEncounters[guid]
    if not encounter then return end

    -- Grant animus mastery to all players in encounter
    for _, p in ipairs(encounter.players) do
        if p and p:isPlayer() then
            Soulseals.addMastered(p:getGuid(), 0) -- 0 = generic mastered flag
            p:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format(
                "You have defeated the %s soul and mastered it!", encounter.monsterName))
        end
    end

    -- Cleanup
    Soulpit.cleanupEncounter(guid)
end

-- ============================================================================
-- Kick / Cleanup
-- ============================================================================

function Soulpit.kickPlayer(guid)
    local encounter = Soulpit.activeEncounters[guid]
    if not encounter then return end

    for _, p in ipairs(encounter.players) do
        if p and p:isPlayer() then
            p:teleportTo(Soulpit.config.exitPosition)
            p:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
            p:sendTextMessage(MESSAGE_EVENT_ADVANCE, "Soulpit time expired!")
        end
    end

    Soulpit.cleanupEncounter(guid)
end

function Soulpit.cleanupEncounter(guid)
    local encounter = Soulpit.activeEncounters[guid]
    if not encounter then return end

    -- Stop kick event
    if encounter.kickEvent then
        stopEvent(encounter.kickEvent)
    end

    -- Remove monsters
    for _, monsterId in ipairs(encounter.monsters or {}) do
        local monster = Creature(monsterId)
        if monster then
            monster:remove()
        end
    end

    -- Transform obelisk back
    Soulpit.config.obeliskPosition:transformItem(Soulpit.config.obeliskActive, Soulpit.config.obeliskInactive)

    Soulpit.activeEncounters[guid] = nil
end

-- ============================================================================
-- Exit action
-- ============================================================================

function Soulpit.exitPlayer(player)
    local guid = player:getGuid()
    if Soulpit.activeEncounters[guid] then
        Soulpit.cleanupEncounter(guid)
    end
    player:teleportTo(Soulpit.config.exitPosition)
    player:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
end

print("[Soulpit] Soulpit arena system loaded")
