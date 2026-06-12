local hirelingSave = GlobalEvent("HirelingSave")

function hirelingSave.onShutdown()
	print(">> Saving Hirelings")
	SaveHirelings()
	return true
end

hirelingSave:register()
