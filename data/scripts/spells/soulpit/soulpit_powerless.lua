-- Soulpit Powerless: boss spell — applies CONDITION_POWERLESS
-- Ported from Crystal Server.

local combat = Combat()
combat:setParameter(COMBAT_PARAM_TYPE, COMBAT_UNDEFINEDDAMAGE)
combat:setParameter(COMBAT_PARAM_EFFECT, CONST_ME_EXPLOSIONHIT)

-- CONDITION_POWERLESS = 36
local condition = Condition(CONDITION_PARALYZE)
condition:setParameter(CONDITION_PARAM_TICKS, 3000)
combat:setCondition(condition)

local spell = Spell(SPELL_INSTANT)

function spell.onCastSpell(creature, variant)
	return combat:execute(creature, variant)
end

spell:name("soulpit powerless")
spell:words("###939")
spell:needTarget(true)
spell:isAggressive(true)
spell:range(7)
spell:register()
