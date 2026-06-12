-- Creature Events for Task Board: onKill, onLogin, onLogout hooks.

-- Guard: only register if Task Hunting system is enabled
if not configManager.getBoolean(configKeys.TASK_HUNTING_SYSTEM_ENABLED) then
	return
end

local bountyEnabled = configManager.getBoolean(configKeys.BOUNTY_TASKS_ENABLED)
local weeklyEnabled = configManager.getBoolean(configKeys.WEEKLY_TASKS_ENABLED)
local soulsealsEnabled = configManager.getBoolean(configKeys.SOULSEALS_SYSTEM_ENABLED)

local bountyModule = nil
local weeklyModule = nil
local resourceBalance = nil

-- These are set after the modules load
local function getBountyModule()
	if not bountyModule then
		local ok, mod = pcall(function() return require("data/scripts/network/task_board/bounty_tasks") end)
		if ok then bountyModule = mod end
	end
	return bountyModule
end

local function getWeeklyModule()
	if not weeklyModule then
		local ok, mod = pcall(function() return require("data/scripts/network/task_board/weekly_tasks") end)
		if ok then weeklyModule = mod end
	end
	return weeklyModule
end

local function getResourceBalance()
	if not resourceBalance then
		local ok, mod = pcall(function() return require("data/scripts/network/task_board/resource_balance") end)
		if ok then resourceBalance = mod end
	end
	return resourceBalance
end

-- ============================================
-- ON KILL
-- ============================================

local taskBoardKill = CreatureEvent("TaskBoardKill")

function taskBoardKill.onKill(player, target, lastHit)
	if not player or not target then
		return true
	end

	-- Get monster race ID from target
	local monster = Monster(target)
	if not monster then
		return true
	end

	local monsterType = monster:getType()
	if not monsterType then
		return true
	end

	local raceId = monsterType:raceId()

	-- Bounty task kill tracking
	if bountyEnabled then
		local bounty = getBountyModule()
		if bounty then
			bounty.onKill(player, raceId)
		end
	end

	-- Weekly task kill tracking
	if weeklyEnabled then
		local weekly = getWeeklyModule()
		if weekly then
			weekly.onKill(player, raceId)
		end
	end

	return true
end

taskBoardKill:type("kill")
taskBoardKill:register()

-- ============================================
-- ON LOGIN
-- ============================================

local taskBoardLogin = CreatureEvent("TaskBoardLogin")

function taskBoardLogin.onLogin(player)
	-- Check weekly rewards
	if weeklyEnabled then
		local weekly = getWeeklyModule()
		if weekly then
			weekly.checkRewardsOnLogin(player)
		end
	end

	-- Send resource balances
	local rb = getResourceBalance()
	if rb then
		addEvent(function()
			if player then
				rb.sendAll(player)
			end
		end, 1000) -- delay 1s for client to be ready
	end

	return true
end

taskBoardLogin:register()

-- ============================================
-- ON LOGOUT
-- ============================================

local taskBoardLogout = CreatureEvent("TaskBoardLogout")

function taskBoardLogout.onLogout(player)
	if bountyEnabled then
		local bounty = getBountyModule()
		if bounty and bounty.saveOnLogout then
			bounty.saveOnLogout(player)
		end
	end

	if weeklyEnabled then
		local weekly = getWeeklyModule()
		if weekly and weekly.saveOnLogout then
			weekly.saveOnLogout(player)
		end
	end

	return true
end

taskBoardLogout:register()
