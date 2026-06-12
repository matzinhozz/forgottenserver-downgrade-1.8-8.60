local hirelingStartup = GlobalEvent("HirelingStartup")

function hirelingStartup.onStartup()
	HirelingsInit()
	return true
end

hirelingStartup:register()
