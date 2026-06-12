-- Creature Events for Task Board: onKill, onLogin, onLogout hooks.

-- Guard: only register if Task Hunting system is enabled
if not configManager or not configManager.getBoolean or not configManager.getBoolean(configKeys.TASK_HUNTING_SYSTEM_ENABLED) then
	return
end

local bountyEnabled = configManager.getBoolean(configKeys.BOUNTY_TASKS_ENABLED)
local weeklyEnabled = configManager.getBoolean(configKeys.WEEKLY_TASKS_ENABLED)
local soulsealsEnabled = configManager.getBoolean(configKeys.SOULSEALS_SYSTEM_ENABLED)

-- Use globals set by init.lua (single module instance, protocol already wired).
-- Do NOT reload modules via dofile — that creates a second copy with nil protocol
-- and a separate cache, causing nil crashes and stale progress in UI.
local function getBountyModule()
	return _TASK_BOARD_BOUNTY_MODULE
end

local function getWeeklyModule()
	return _TASK_BOARD_WEEKLY_MODULE
end

local function getResourceBalance()
	return TaskBoardResourceBalance
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
	local playerGuid = player:getGuid()

	-- Sync C++ fields from Lua DB caches (C++ fields default to 0 on login)
	-- Bounty points: load from player_bounty_tasks DB
	if bountyEnabled then
		local bounty = getBountyModule()
		if bounty then
			-- Force-load the Lua cache, which reads bounty_points from DB
			local ok, bountyData = pcall(function()
				-- Access internal loadBountyData via a helper
				local data = bounty.loadBountyData and bounty.loadBountyData(playerGuid)
				return data
			end)
			if ok and bountyData then
				player:setBountyPoints(bountyData.bountyPoints or 0)
			end
		end
	end

	-- Soulseals: load from player_weekly_tasks DB
	if weeklyEnabled then
		local weekly = getWeeklyModule()
		if weekly then
			weekly.checkRewardsOnLogin(player)
			local ok, weeklyData = pcall(function()
				local data = weekly.loadWeeklyData and weekly.loadWeeklyData(playerGuid)
				return data
			end)
			if ok and weeklyData then
				player:setSoulsealsPoints(weeklyData.soulsealsPoints or 0)
				if weeklyData.hasExpansion then
					player:setWeeklyExpansion(true)
				end
			end
		end
	end

	-- Task hunting points: load from player_hunting_task_points table
	local resultId = db.storeQuery("SELECT `points` FROM `player_hunting_task_points` WHERE `player_id` = " .. playerGuid)
	if resultId ~= false then
		player:setTaskHuntingPoints(result.getDataLong(resultId, "points") or 0)
		result.free(resultId)
	end

	-- Send resource balances (use GUID to re-acquire player after delay)
	local rb = getResourceBalance()
	if rb then
		addEvent(function()
			local p = Player(playerGuid)
			if p then
				rb.sendAll(p)
			end
		end, 1000) -- delay 1s for client to be ready
	end

	return true
end

taskBoardLogin:type("login")
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

taskBoardLogout:type("logout")
taskBoardLogout:register()
