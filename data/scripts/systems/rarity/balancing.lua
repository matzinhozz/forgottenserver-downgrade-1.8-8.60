-- Rarity System Balancing
-- All numeric values read by C++ at runtime. Written into items during rollRarity().

rarityBalancing = {
	spellScale = { level = 2, magic = 3, divisor = 5 },

	spells = {
		onAttackFireStrike    = { dmgMin = 20, dmgMax = 45 },
		onAttackIceStrike     = { dmgMin = 15, dmgMax = 35 },
		onAttackTerraStrike   = { dmgMin = 15, dmgMax = 35 },
		onAttackDeathStrike   = { dmgMin = 15, dmgMax = 40 },
		onAttackEnergyStrike  = { dmgMin = 20, dmgMax = 50 },
		onAttackDivineMissile = { dmgMin = 20, dmgMax = 40 },
		onHitFireStrike       = { dmgMin = 20, dmgMax = 45 },
		onHitIceStrike        = { dmgMin = 15, dmgMax = 35 },
		onHitTerraStrike      = { dmgMin = 15, dmgMax = 35 },
		onHitDeathStrike      = { dmgMin = 15, dmgMax = 40 },
		onHitEnergyStrike     = { dmgMin = 20, dmgMax = 50 },
		onHitDivineMissile    = { dmgMin = 20, dmgMax = 40 },
	},

	onKill = {
		buffDuration   = 30000,
		critChance     = 1000,
		critAmount     = 5000,
		maxHpPercent   = 5,
		maxMpPercent   = 5,
	},
}
