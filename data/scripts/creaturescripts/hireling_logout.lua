local hirelingLogout = CreatureEvent("HirelingLogout")

function hirelingLogout.onLogout(player)
	return true
end

hirelingLogout:register()
