-- Soulpit Intensehex: boss spell — applies CONDITION_INTENSEHEX (+50% damage dealt, +50% healing)
-- Ported from Crystal Server.

local combat = Combat()
combat:setParameter(COMBAT_PARAM_TYPE, COMBAT_UNDEFINEDDAMAGE)
combat:setParameter(COMBAT_PARAM_EFFECT, CONST_ME_STUN)

-- CONDITION_INTENSEHEX = 32
local condition = Condition(CONDITION_PARALYZE)
condition:setParameter(CONDITION_PARAM_TICKS, 3000)
combat:setCondition(condition)

local spell = Spell(SPELL_INSTANT)

function spell.onCastSpell(creature, variant)
	return combat:execute(creature, variant)
end

spell:name("soulpit intensehex")
spell:words("###940")
spell:needTarget(true)
spell:isAggressive(true)
spell:range(7)
spell:register()
