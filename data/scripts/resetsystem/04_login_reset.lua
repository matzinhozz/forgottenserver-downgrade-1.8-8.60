local resetOnLogin = CreatureEvent("ResetSystemOnLogin")

function resetOnLogin.onLogin(player)
	ResetBonusConfig.applyBonuses(player)
	return true
end

resetOnLogin:register()
