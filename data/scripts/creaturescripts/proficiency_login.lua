-- Proficiency: Register events on player login
local proficiencyLogin = CreatureEvent("ProficiencyLogin")

function proficiencyLogin.onLogin(player)
	if configManager.getBoolean(configKeys.WEAPON_PROFICIENCY_ENABLED) then
		player:registerEvent("ProficiencyKill")
	end
	return true
end

proficiencyLogin:register()
