-- Soulpit Enrage Boss Ability
-- Reduces damage taken based on HP percentage

local soulpitEnrage = CreatureEvent("SoulpitEnrage")

function soulpitEnrage.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
    if not creature or not creature:isMonster() then
        return primaryDamage, primaryType, secondaryDamage, secondaryType
    end

    local healthPercent = creature:getHealth() / creature:getMaxHealth()

    -- Damage reduction based on HP thresholds
    local multiplier = 1.0
    if healthPercent <= 0.2 then
        multiplier = 0.4 -- 60% reduction
    elseif healthPercent <= 0.4 then
        multiplier = 0.6 -- 40% reduction
    elseif healthPercent <= 0.6 then
        multiplier = 0.75 -- 25% reduction
    elseif healthPercent <= 0.8 then
        multiplier = 0.9 -- 10% reduction
    end

    primaryDamage = math.floor(primaryDamage * multiplier)
    secondaryDamage = math.floor(secondaryDamage * multiplier)

    return primaryDamage, primaryType, secondaryDamage, secondaryType
end

soulpitEnrage:register()
