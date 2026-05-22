-- Imbuement Shrine Action (Protocol 15.11 style)
-- Shrine can be used directly (opens window, item selected inside the window)
-- or target an item from backpack (legacy/backward compatible)

local action = Action()

function action.onUse(player, item, fromPosition, target, toPosition, isHotkey)
	if not configManager.getBoolean(configKeys.IMBUEMENT_SYSTEM_ENABLED) then
		player:sendCancelMessage("Imbuement system is disabled.")
		return true
	end

	if configManager.getBoolean(configKeys.PROFICIENCY_IMBUEMENT_1511) then
		-- 15.11 style: open window without item, player selects inside the window
		player:openImbuementWindow()
	else
		-- Legacy: require item from backpack
		local selectedItem = nil
		if target and target:isItem() then
			if target:getTopParent() ~= player then
				player:sendTextMessage(MESSAGE_STATUS_SMALL, "Use an item from your backpack on the imbuing shrine.")
				return true
			end
			local ok, slots = pcall(function() return target:getImbuementSlots() end)
			if not ok or not slots or slots == 0 then
				player:sendTextMessage(MESSAGE_STATUS_SMALL, "Use an item with imbuement slots from your backpack on the imbuing shrine.")
				return true
			end
			selectedItem = target
		end

		if not selectedItem then
			-- Auto-find first imbuable item in backpack
			local backpack = player:getSlotItem(CONST_SLOT_BACKPACK)
			local container = backpack and backpack:getContainer()
			if container then
				local function findItem(cont)
					for _, it in ipairs(cont:getItems()) do
						local ok, slots = pcall(function() return it:getImbuementSlots() end)
						if ok and slots and slots > 0 then
							return it
						end
						local childCont = it:getContainer()
						if childCont then
							local found = findItem(childCont)
							if found then return found end
						end
					end
					return nil
				end
				selectedItem = findItem(container)
			end
		end

		if not selectedItem then
			player:sendTextMessage(MESSAGE_STATUS_SMALL, "Use an item with imbuement slots from your backpack on the imbuing shrine.")
			return true
		end

		ImbuingWindow.openItem(player, selectedItem)
	end
	return true
end

action:id(25060, 25061)
action:register()
