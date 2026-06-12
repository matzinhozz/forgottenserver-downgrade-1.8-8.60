function onHirelingOutfitChange(playerId, outfit)
	local player = Player(playerId)
	if not player then return end

	local hireling = player:getHirelingChangingOutfit()
	if not hireling then
		player:sendCancelMessage(RETURNVALUE_NOTPOSSIBLE)
		return
	end

	hireling:changeOutfit(outfit)
end
