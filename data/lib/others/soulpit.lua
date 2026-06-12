-- Soulpit System: Arena configuration, soul core fusion, monster variations.
-- Ported from Crystal Server. Uses native code — no JSON, no extended opcodes.

SoulPit = SoulPit or {}

-- ============================================
-- SOUL CORES CONFIGURATION
-- ============================================

SoulPit.SoulCoresConfiguration = {
	chanceToGetSameMonsterSoulCore = 15,   -- 15%
	chanceToDropSoulCore = 5,              -- 5%
	chanceToGetOminousSoulCore = 2,        -- 2%
	chanceToDropSoulPrism = 4,             -- 4%
	monsterVariationsSoulCore = {
		["Horse"] = "horse soul core (taupe)",
		["Brown Horse"] = "horse soul core (brown)",
		["Grey Horse"] = "horse soul core (gray)",
		["Nomad"] = "nomad soul core (basic)",
		["Nomad Blue"] = "nomad soul core (blue)",
		["Nomad Female"] = "nomad soul core (female)",
		["Purple Butterfly"] = "butterfly soul core (purple)",
		["Butterfly"] = "butterfly soul core (blue)",
		["Blue Butterfly"] = "butterfly soul core (blue)",
		["Red Butterfly"] = "butterfly soul core (red)",
	},
	monstersDifficulties = {
		["Harmless"] = 1,
		["Trivial"] = 2,
		["Easy"] = 3,
		["Medium"] = 4,
		["Hard"] = 5,
		["Challenge"] = 6,
	},
}

-- ============================================
-- WAVES CONFIGURATION
-- ============================================

SoulPit.waves = {
	[1] = { stacks = { [1] = 7 } },                      -- 7 regular monsters (stack 1)
	[2] = { stacks = { [1] = 4, [5] = 3 } },              -- 4 stack-1 + 3 stack-5
	[3] = { stacks = { [1] = 5, [15] = 2 } },             -- 5 stack-1 + 2 stack-15
	[4] = { stacks = { [1] = 3, [5] = 3, [40] = 1 } },   -- 3 stack-1 + 3 stack-5 + 1 boss
}

SoulPit.effects = {
	[1] = CONST_ME_TELEPORT,
	[5] = CONST_ME_TELEPORT, -- fallback if CONST_ME_ORANGETELEPORT not available
	[15] = CONST_ME_TELEPORT, -- fallback if CONST_ME_REDTELEPORT not available
	[40] = CONST_ME_TELEPORT, -- fallback if CONST_ME_PURPLETELEPORT not available
}

-- Boss ability pool (random each boss spawn)
SoulPit.possibleAbilities = {
	"overpowerSoulPit",
	"enrageSoulPit",
	"opressorSoulPit",
}

-- ============================================
-- BOSS ABILITIES
-- ============================================

SoulPit.bossAbilities = {
	-- Overpower: +50% crit chance, +25% crit damage
	overpowerSoulPit = function(monster)
		if not monster then return end
		local ok, err = pcall(function()
			monster:criticalChance(50)
			monster:criticalDamage(25)
		end)
		if not ok then
			print("[Soulpit] Warning: overpowerSoulPit failed: " .. tostring(err))
		end
	end,

	-- Enrage: damage reduction based on HP threshold (handled in creatureevent)
	enrageSoulPit = function(monster)
		if not monster then return end
		local ok, err = pcall(function()
			monster:registerEvent("SoulPitEnrage")
		end)
		if not ok then
			print("[Soulpit] Warning: enrageSoulPit failed: " .. tostring(err))
		end
	end,

	-- Opressor: adds boss spells (handled in fight script)
	opressorSoulPit = function(monster)
		if not monster then return end
		local ok, err = pcall(function()
			monster:addAttackSpell("soulpit opressor", 2000, 25)
			monster:addAttackSpell("soulpit powerless", 2000, 30)
			monster:addAttackSpell("soulpit intensehex", 2000, 15)
		end)
		if not ok then
			print("[Soulpit] Warning: opressorSoulPit failed: " .. tostring(err))
		end
	end,
}

-- ============================================
-- TIMING CONSTANTS
-- ============================================

SoulPit.timeToSpawnMonsters = 4000    -- 4 seconds effects before monsters appear
SoulPit.checkMonstersDelay = 4500     -- 4.5 seconds between stage checks
SoulPit.timeToKick = 600000           -- 10 minutes auto-kick
SoulPit.totalMonsters = 7

-- ============================================
-- ZONE CONFIGURATION
-- (ADJUST THESE TO YOUR MAP!)
-- ============================================

-- Soulpit zone area: { fromPos = {x, y, z}, toPos = {x, y, z} }
SoulPit.zoneArea = {
	fromPos = Position(32362, 31132, 8),
	toPos = Position(32390, 31153, 8),
}

-- Obelisk position (inactive)
SoulPit.obeliskPos = Position(32375, 31157, 8)
SoulPit.obeliskInactiveId = 47367
SoulPit.obeliskActiveId = 47379

-- Entrance/exit positions
SoulPit.entrancePos = {
	{ fromPos = Position(32350, 31030, 3), toPos = Position(32374, 31171, 8) },
	{ fromPos = Position(32349, 31030, 3), toPos = Position(32374, 31171, 8) },
}

SoulPit.exitPos = Position(32374, 31173, 8)
SoulPit.exitDestination = Position(32349, 31032, 3)

-- Player spawn positions inside arena
SoulPit.playerPositions = {
	Position(32375, 31158, 8),
	Position(32375, 31159, 8),
	Position(32375, 31160, 8),
	Position(32375, 31161, 8),
	Position(32375, 31162, 8),
}

-- Player exit destination inside
SoulPit.playerExitDestination = Position(32373, 31151, 8)

-- ============================================
-- ITEM IDs
-- ============================================

SoulPit.itemIds = {
	ominousSoulCore = 49163,
	soulPrism = 49164,
	exaltedCore = 37110,
	largeObeliskInactive = 47367,
	largeObeliskActive = 47379,
}

-- ============================================
-- FUNCTIONS
-- ============================================

-- Get the base monster name from a soul core item name
function SoulPit.getSoulCoreMonster(name)
	return name and name:match("^(.-) soul core") or nil
end

-- Get variation mapping from monster type name to soul core variant name
function SoulPit.getMonsterVariationNameBySoulCore(searchName)
	local variations = SoulPit.SoulCoresConfiguration.monsterVariationsSoulCore
	return variations[searchName]
end

-- Get difficulty name by stars count
function SoulPit.getDifficultyByStars(stars)
	local diffs = SoulPit.SoulCoresConfiguration.monstersDifficulties
	for name, count in pairs(diffs) do
		if count == stars then
			return name
		end
	end
	return "Unknown"
end

-- Get all soul core items from the game
function SoulPit.getSoulCoreItems()
	if Game and Game.getSoulCoreItems then
		return Game.getSoulCoreItems()
	end
	-- Fallback: manually list known soul cores
	return {}
end

-- Get soul core item for a monster (by name or raceId)
function SoulPit.getSoulCoreForMonster(monsterIdentifier)
	-- This would need to search through loaded items for the matching soul core
	-- The Crystal Server uses C++ Game.getSoulCoreItems() for this
	-- For the port, we store soul core item ID lookups in the soulpit_fight script
	return false
end

-- Fuse two soul cores of the same type into a random new one
function SoulPit.onFuseSoulCores(player, item, target)
	if not player or not item or not target then
		return false
	end

	-- Must be same item ID
	if item:getId() ~= target:getId() then
		return false
	end

	-- Source must have stack count <= 1
	if item:getCount() > 1 then
		return false
	end

	-- Both items must be soul cores
	local itemName = item:getName()
	local targetName = target:getName()
	local sourceMonster = SoulPit.getSoulCoreMonster(itemName)
	local targetMonster = SoulPit.getSoulCoreMonster(targetName)

	if not sourceMonster or not targetMonster then
		return false
	end

	-- Consume both items
	item:remove(1)
	target:remove(1)

	-- Get all possible soul cores and pick a random one
	local soulCores = SoulPit.getSoulCoreItems()
	if #soulCores == 0 then
		-- Fallback: give a random core from known list
		player:sendTextMessage(MESSAGE_INFO_DESCR, "Soul core fusion is not yet available.")
		return false
	end

	local randomCore = soulCores[math.random(#soulCores)]
	local coreItemId = randomCore:getId()
	local coreName = randomCore:getName()

	-- Give the fused core
	player:addItem(coreItemId, 1)

	-- Visual feedback
	Position(player:getPosition()):sendMagicEffect(CONST_ME_MAGIC_BLUE)
	player:sendTextMessage(MESSAGE_INFO_DESCR, "You have received a " .. coreName .. ".")

	return true
end

-- ============================================
-- DEBUG / LOGGING
-- ============================================

function SoulPit.log(message)
	if logger and logger.info then
		logger.info("[Soulpit] " .. tostring(message))
	else
		print("[Soulpit] " .. tostring(message))
	end
end

return SoulPit
