-- Soulpit Obelisk Action
-- Use a soul core item on the inactive obelisk to start the encounter

if not Soulpit then Soulpit = {} end

local soulpitObelisk = Action()

function soulpitObelisk.onUse(player, item, fromPosition, target, toPosition, isHotkey)
    if not configManager.getBoolean(configKeys.SOULPIT_SYSTEM_ENABLED) then
        return false
    end

    if not target then return false end

    local targetId = target:getId()

    -- Check if target is the active obelisk (someone already fighting)
    if targetId == Soulpit.config.obeliskActive then
        player:sendTextMessage(MESSAGE_STATUS_SMALL, "Someone is already fighting in the soulpit!")
        return false
    end

    -- Check if target is the inactive obelisk
    if targetId ~= Soulpit.config.obeliskInactive then
        return false
    end

    -- Get monster name from soul core item
    local itemName = item:getName()
    local monsterName = Soulpit.getMonsterNameFromSoulCore(itemName)
    if not monsterName then
        player:sendTextMessage(MESSAGE_STATUS_SMALL, "This is not a valid soul core.")
        return false
    end

    -- Check if player is on a lever position
    local playerPos = player:getPosition()
    local onLever = false
    for _, pos in ipairs(Soulpit.config.playerPositions) do
        if pos.x == playerPos.x and pos.y == playerPos.y and pos.z == playerPos.z then
            onLever = true
            break
        end
    end

    if not onLever then
        player:sendTextMessage(MESSAGE_STATUS_SMALL, "You must be standing on a lever position to use the obelisk.")
        return false
    end

    -- Consume the soul core
    item:remove(1)

    -- Start encounter
    Soulpit.startEncounter(player, itemName)
    return true
end

-- Register for all soul core items (items with "soul core" in the name)
-- You need to add specific item IDs here for your server's soul core items
-- Example: soulpitObelisk:id(49163) -- ominous soul core
-- For now, register for the specific obelisk items as targets
soulpitObelisk:allowFarUse(true)
soulpitObelisk:register()
