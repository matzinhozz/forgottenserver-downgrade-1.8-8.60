-- Soulpit Creature Event: Boss enrage (damage reduction by HP threshold)
-- Ported from Crystal Server.

local enrage = CreatureEvent("SoulPitEnrage")

function enrage.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType)
	if not creature or not creature:isMonster() then
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end

	-- Only applies to soulpit bosses in the arena
	if not SoulPit or not SoulPit.encounter then
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end

	local healthPercent = creature:getHealth() / math.max(1, creature:getMaxHealth())
	local reductionMultiplier = 1.0

	-- Damage reduction by HP threshold
	if healthPercent >= 0.6 and healthPercent < 0.8 then
		reductionMultiplier = 0.9   -- 10% reduction at 60-80% HP
	elseif healthPercent >= 0.4 and healthPercent < 0.6 then
		reductionMultiplier = 0.75  -- 25% reduction at 40-60% HP
	elseif healthPercent >= 0.2 and healthPercent < 0.4 then
		reductionMultiplier = 0.6   -- 40% reduction at 20-40% HP
	elseif healthPercent < 0.2 then
		reductionMultiplier = 0.4   -- 60% reduction below 20% HP
	end

	if reductionMultiplier < 1.0 then
		primaryDamage = math.floor(primaryDamage * reductionMultiplier)
		if secondaryDamage then
			secondaryDamage = math.floor(secondaryDamage * reductionMultiplier)
		end
	end

	return primaryDamage, primaryType, secondaryDamage, secondaryType
end

enrage:register()
