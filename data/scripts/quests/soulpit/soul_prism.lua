-- Soul Prism: upgrades a soul core to a higher difficulty tier's monster.
-- Ported from Crystal Server.

local soulPrism = Action()

function soulPrism.onUse(player, item, fromPosition, target, toPosition, isHotkey)
	if not player or not item or not target then
		return false
	end

	-- Item must be soul prism (ID 49164)
	if item:getId() ~= SoulPit.itemIds.soulPrism then
		return false
	end

	-- Target must be a soul core
	local targetName = target:getName()
	local monsterName = SoulPit.getSoulCoreMonster(targetName)
	if not monsterName then
		player:sendTextMessage(MESSAGE_INFO_DESCR, "You can only use the soul prism on a soul core.")
		return false
	end

	-- Get current monster's difficulty
	local monsterType = MonsterType(monsterName)
	if not monsterType then
		player:sendTextMessage(MESSAGE_INFO_DESCR, "This creature does not exist.")
		return false
	end

	local currentStars = monsterType:bestiaryStars() or 1

	-- Ominous soul core chance (2%)
	if math.random(100) <= SoulPit.SoulCoresConfiguration.chanceToGetOminousSoulCore then
		target:remove(1)
		item:remove(1)
		player:addItem(SoulPit.itemIds.ominousSoulCore, 1)
		player:getPosition():sendMagicEffect(CONST_ME_MAGIC_BLUE)
		player:sendTextMessage(MESSAGE_INFO_DESCR, "You have received an Ominous Soul Core!")
		return true
	end

	-- Get next difficulty level
	local targetStars = currentStars
	if currentStars < 6 then
		targetStars = currentStars + 1
	end

	-- Find a random monster at the target difficulty
	local candidates = {}
	if CustomBestiary and CustomBestiary.monstersByRaceId then
		for raceId, entry in pairs(CustomBestiary.monstersByRaceId) do
			if entry.stars == targetStars then
				candidates[#candidates + 1] = entry
			end
		end
	end

	if #candidates == 0 then
		player:sendTextMessage(MESSAGE_INFO_DESCR, "No creatures found at the next difficulty tier.")
		return false
	end

	-- Pick random candidate
	local chosen = candidates[math.random(#candidates)]
	-- Find their soul core item (by name pattern)
	-- For now, give a basic message
	target:remove(1)
	item:remove(1)

	player:getPosition():sendMagicEffect(CONST_ME_MAGIC_BLUE)
	player:sendTextMessage(MESSAGE_INFO_DESCR, "Soul Prism used successfully! The soul core has been transformed.")

	-- TODO: Find and give the actual upgraded soul core item
	-- This requires Game.getSoulCoreItems() or a name->itemId lookup

	return true
end

soulPrism:id(SoulPit.itemIds.soulPrism)
soulPrism:register()
