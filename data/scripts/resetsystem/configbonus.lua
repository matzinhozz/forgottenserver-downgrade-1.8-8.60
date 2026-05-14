local VOCATION_ALL = 0

ResetBonusConfig = {
	resetLevel    = 10000,
	maxResets     = 0,
	resetCooldown = 0,

	damage = {
		enabled = true,
		[VOCATION_ALL] = {
			steps = {
				{ reset = 1, bonus = 10.0 },
				{ reset = 2, bonus =  5.0 },
				{ reset = 3, bonus =  5.0 },
			},
			default = 0.1,
		},
	},

	defense = {
		enabled = true,
		[VOCATION_ALL] = {
			steps = {
				{ reset = 1, bonus =  5.0 },
				{ reset = 2, bonus =  5.0 },
				{ reset = 3, bonus =  2.5 },
				{ reset = 4, bonus =  2.5 },
				{ reset = 5, bonus =  2.5 },
			},
			default = 0.1,
		},
	},

	experience = {
		enabled = true,
		[VOCATION_ALL] = {
			steps = {
				{ reset = 1, bonus = 15.0 },
				{ reset = 2, bonus =  5.0 },
				{ reset = 3, bonus =  5.0 },
			},
			default = 0.1,
		},
	},

	healing = {
		enabled = true,
		[VOCATION_ALL] = {
			steps = {
				{ reset = 1, bonus =  5.0 },
				{ reset = 2, bonus =  5.0 },
				{ reset = 3, bonus =  2.5 },
			},
			default = 0.05,
		},
	},

	attackSpeed = {
		enabled = true,
		[VOCATION_ALL] = {
			steps = {
				{ reset = 1, bonus = 20 },
				{ reset = 2, bonus = 10 },
				{ reset = 3, bonus = 10 },
			},
			default = 2,
		},
	},

	hp = {
		enabled = true,
		bonusMode = "percent",
		[VOCATION_ALL] = {
			ranges = {
				{ minReset = 1, maxReset = 0, bonus = 10.0 },
			},
		},
	},

	mana = {
		enabled = true,
		bonusMode = "percent",
		[VOCATION_ALL] = {
			ranges = {
				{ minReset = 1, maxReset = 0, bonus = 10.0 },
			},
		},
	},

	manaPotion = {
		enabled = true,
		[VOCATION_ALL] = {
			ranges = {
				{ minReset = 1, maxReset = 0, bonus = 1.0 },
			},
		},
		[2] = { ranges = { { minReset = 1, maxReset = 0, bonus = 2.0 } } },
		[6] = { ranges = { { minReset = 1, maxReset = 0, bonus = 2.0 } } },
		[1] = { ranges = { { minReset = 1, maxReset = 0, bonus = 2.0 } } },
		[5] = { ranges = { { minReset = 1, maxReset = 0, bonus = 2.0 } } },
		[4] = { ranges = { { minReset = 1, maxReset = 0, bonus = 1.5 } } },
		[8] = { ranges = { { minReset = 1, maxReset = 0, bonus = 1.5 } } },
		[3] = { ranges = { { minReset = 1, maxReset = 0, bonus = 1.3 } } },
		[7] = { ranges = { { minReset = 1, maxReset = 0, bonus = 1.3 } } },
	},

	manaSpell = {
		enabled = true,
		[VOCATION_ALL] = {
			ranges = {
				{ minReset = 1, maxReset = 0, bonus = 0.5 },
			},
		},
		[1] = { ranges = { { minReset = 1, maxReset = 0, bonus = 3.0 } } },
		[5] = { ranges = { { minReset = 1, maxReset = 0, bonus = 3.0 } } },
		[2] = { ranges = { { minReset = 1, maxReset = 0, bonus = 3.0 } } },
		[6] = { ranges = { { minReset = 1, maxReset = 0, bonus = 3.0 } } },
		[3] = { ranges = { { minReset = 1, maxReset = 0, bonus = 1.5 } } },
		[7] = { ranges = { { minReset = 1, maxReset = 0, bonus = 1.5 } } },
		[4] = { ranges = { { minReset = 1, maxReset = 0, bonus = 0.0 } } },
		[8] = { ranges = { { minReset = 1, maxReset = 0, bonus = 0.0 } } },
	},
}

function ResetBonusConfig.getTotalBonus(bonusType, resetCount, vocationId)
	if resetCount <= 0 then
		return 0
	end

	local config = ResetBonusConfig[bonusType]
	if not config then
		return 0
	end

	if config.enabled == false then
		return 0
	end

	local vocConfig = config[vocationId] or config[0]
	if not vocConfig then
		return 0
	end

	local total = 0
	local lastStep = (vocConfig.steps and #vocConfig.steps > 0) and vocConfig.steps[#vocConfig.steps].reset or 0

	for i = 1, resetCount do
		local found = false
		if vocConfig.steps then
			for _, step in ipairs(vocConfig.steps) do
				if step.reset == i then
					total = total + (step.bonus or 0)
					found = true
					break
				end
			end
		end
		if not found then
			if vocConfig.ranges then
				for _, range in ipairs(vocConfig.ranges) do
					if i >= range.minReset and (range.maxReset == 0 or i <= range.maxReset) then
						total = total + (range.bonus or 0)
						found = true
						break
					end
				end
			end
			if not found then
				total = total + (vocConfig.default or 0)
			end
		end
	end

	return total
end

function ResetBonusConfig.applyBonuses(player)
	local resets = player:getResetCount()
	local vocId = player:getVocationId()

	local spd = 0
	if ResetBonusConfig.attackSpeed.enabled ~= false then
		spd = ResetBonusConfig.getTotalBonus("attackSpeed", resets, vocId)
	end
	player:setResetAttackSpeedBonus(math.floor(spd))

	local dmg = 0
	if ResetBonusConfig.damage.enabled ~= false then
		dmg = ResetBonusConfig.getTotalBonus("damage", resets, vocId)
	end
	player:setResetDamageBonus(dmg)

	local def = 0
	if ResetBonusConfig.defense.enabled ~= false then
		def = ResetBonusConfig.getTotalBonus("defense", resets, vocId)
	end
	player:setResetDefenseBonus(def)

	local heal = 0
	if ResetBonusConfig.healing.enabled ~= false then
		heal = ResetBonusConfig.getTotalBonus("healing", resets, vocId)
	end
	player:setResetHealingBonus(heal)

	local hpConfig = ResetBonusConfig.hp
	if hpConfig and hpConfig.enabled ~= false then
		local hpTotal = ResetBonusConfig.getTotalBonus("hp", resets, vocId)
		if hpTotal > 0 then
			if hpConfig.bonusMode == "flat" then
				player:setResetHpBonus(math.floor(hpTotal))
			else
				player:setResetHpBonus(0)
				local baseHp = player:getMaxHealth()
				player:setResetHpBonus(math.floor(baseHp * hpTotal / 100))
			end
		else
			player:setResetHpBonus(0)
		end
	else
		player:setResetHpBonus(0)
	end

	local manaConfig = ResetBonusConfig.mana
	if manaConfig and manaConfig.enabled ~= false then
		local manaTotal = ResetBonusConfig.getTotalBonus("mana", resets, vocId)
		if manaTotal > 0 then
			if manaConfig.bonusMode == "flat" then
				player:setResetManaBonus(math.floor(manaTotal))
			else
				player:setResetManaBonus(0)
				local baseMana = player:getMaxMana()
				player:setResetManaBonus(math.floor(baseMana * manaTotal / 100))
			end
		else
			player:setResetManaBonus(0)
		end
	else
		player:setResetManaBonus(0)
	end

	local mpConfig = ResetBonusConfig.manaPotion
	if mpConfig and mpConfig.enabled ~= false then
		local mpBonus = ResetBonusConfig.getTotalBonus("manaPotion", resets, vocId)
		player:setResetManaPotionBonus(mpBonus)
	else
		player:setResetManaPotionBonus(0)
	end

	local msConfig = ResetBonusConfig.manaSpell
	if msConfig and msConfig.enabled ~= false then
		local msBonus = ResetBonusConfig.getTotalBonus("manaSpell", resets, vocId)
		player:setResetManaSpellBonus(msBonus)
	else
		player:setResetManaSpellBonus(0)
	end
end
