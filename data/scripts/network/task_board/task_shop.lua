-- Task Shop subsystem
-- Handles: shop offers, purchase

if not TaskBoard then TaskBoard = {} end

-- ============================================================================
-- Buy offer (option 11)
-- ============================================================================

function TaskBoard.buyShopOffer(player, offerIndex)
    local offers = TaskBoard.getShopOffers()
    local offer = offers[offerIndex + 1]
    if not offer then
        player:sendTextMessage(MESSAGE_STATUS_SMALL, "Invalid offer.")
        TaskBoard.sendShopData(player)
        return
    end

    local htp = TaskBoard.getHuntingTaskPoints(player)
    if htp < (offer.price or 0) then
        player:sendTextMessage(MESSAGE_STATUS_SMALL, "You don't have enough Hunting Task Points.")
        TaskBoard.sendShopData(player)
        return
    end

    -- Deduct points
    TaskBoard.setHuntingTaskPoints(player, htp - (offer.price or 0))

    -- Deliver reward based on type
    local success = false
    if offer.offerType == 0 then
        -- ITEM
        local item = Game.createItem(offer.itemId or 0, 1)
        if item then
            local inbox = player:getSlotItem(CONST_SLOT_STORE_INBOX)
            if inbox and inbox:addItemEx(item) ~= RETURNVALUE_NOERROR then
                player:getInbox():addItem(item, INDEX_WHEREEVER, FLAG_NOLIMIT)
            end
            success = true
        end
    elseif offer.offerType == 1 then
        -- MOUNT
        if offer.mountId then
            player:addMount(offer.mountId)
            success = true
        end
    elseif offer.offerType == 2 then
        -- OUTFIT
        if offer.lookType then
            player:addOutfit(offer.lookType)
            success = true
        end
    elseif offer.offerType == 3 then
        -- ITEM_DOUBLE
        local item1 = Game.createItem(offer.itemId or 0, 1)
        local item2 = Game.createItem(offer.itemId2 or 0, 1)
        if item1 then
            local inbox = player:getSlotItem(CONST_SLOT_STORE_INBOX)
            if inbox and inbox:addItemEx(item1) ~= RETURNVALUE_NOERROR then
                player:getInbox():addItem(item1, INDEX_WHEREEVER, FLAG_NOLIMIT)
            end
        end
        if item2 then
            local inbox = player:getSlotItem(CONST_SLOT_STORE_INBOX)
            if inbox and inbox:addItemEx(item2) ~= RETURNVALUE_NOERROR then
                player:getInbox():addItem(item2, INDEX_WHEREEVER, FLAG_NOLIMIT)
            end
        end
        success = true
    elseif offer.offerType == 5 then
        -- WEEKLY_EXPANSION
        local guid = player:getGuid()
        local weekly = TaskBoard.weeklyCache[guid]
        if weekly and not weekly.hasExpansion then
            weekly.hasExpansion = true
            TaskBoard.saveWeeklyToDB(guid, weekly)
            success = true
        else
            player:sendTextMessage(MESSAGE_STATUS_SMALL, "You already have the weekly expansion.")
        end
    end

    if success then
        player:sendTextMessage(MESSAGE_STATUS, "Purchase successful!")
    end

    TaskBoard.sendShopData(player)
    TaskBoard.sendAllResourceBalances(player)
end
