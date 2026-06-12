HIRELING_SKILLS = {
	BANKER = {1, "banker"},
	COOKING = {2, "cooking"},
	STEWARD = {3, "steward"},
	TRADER = {4, "trader"},
}

HIRELING_SEX = {
	FEMALE = 0,
	MALE = 1,
}

HIRELING_OUTFIT_DEFAULT = {name = "Citizen", female = 136, male = 128}

HIRELING_OUTFITS = {
	BANKER = 1,
	COOKING = 2,
	STEWARD = 4,
	TRADER = 8,
	SERVANT = 16,
	HYDRA = 32,
	FERUMBRAS = 64,
	BONELORD = 128,
	DRAGON = 256,
}

HIRELING_OUTFITS_TABLE = {
	BANKER = {name = "Banker Dress", female = 1109, male = 1110},
	BONELORD = {name = "Bonelord Dress", female = 1123, male = 1124},
	COOKING = {name = "Cook Dress", female = 1113, male = 1114},
	DRAGON = {name = "Dragon Dress", female = 1125, male = 1126},
	FERUMBRAS = {name = "Ferumbras Dress", female = 1131, male = 1132},
	HYDRA = {name = "Hydra Dress", female = 1129, male = 1130},
	SERVANT = {name = "Servant Dress", female = 1117, male = 1118},
	STEWARD = {name = "Stewart Dress", female = 1115, male = 1116},
	TRADER = {name = "Trader Dress", female = 1111, male = 1112},
}

HIRELING_LAMP_ID = 29432
HIRELING_ATTRIBUTE = "HIRELING_ID"

HIRELING_FOODS_BOOST = {
	MAGIC = 35174,
	MELEE = 35175,
	SHIELDING = 35172,
	DISTANCE = 35173,
}

HIRELING_FOODS_IDS = {35176, 35177, 35178, 35179, 35180}

local HIRELINGS = {}
local PLAYER_HIRELINGS = {}
HIRELING_OUTFIT_CHANGING = {}

local function getHirelingKV(playerGuid)
	return kv.scoped("player"):scoped(tostring(playerGuid)):scoped("hireling")
end

local function getSkillFlag(skillName)
	local flags = {banker = 1, cooking = 2, steward = 4, trader = 8}
	return flags[skillName] or 0
end

local function hasSkillByKV(playerGuid, skillName)
	local store = getHirelingKV(playerGuid)
	local skills = store:get("skills") or 0
	local flag = getSkillFlag(skillName)
	if flag == 0 or skills <= 0 then return false end
	return bit.band(skills, flag) ~= 0
end

-- [[ HIRELING CLASS ]]

Hireling = {
	id = -1,
	player_id = -1,
	name = "hireling",
	active = 0,
	sex = 0,
	posx = 0,
	posy = 0,
	posz = 0,
	lookbody = 34,
	lookfeet = 116,
	lookhead = 97,
	looklegs = 3,
	looktype = 0,
	cid = -1,
}

function Hireling:new(o)
	o = o or {}
	setmetatable(o, self)
	self.__index = self
	return o
end

function Hireling:getOwnerId()
	return self.player_id
end

function Hireling:getId()
	return self.id
end

function Hireling:getName()
	return self.name
end

function Hireling:canTalkTo(player)
	if not player then return false end
	local tile = Tile(player:getPosition())
	if not tile then return false end
	local house = tile:getHouse()
	if not house then return false end
	local hirelingTile = Tile(self:getPosition())
	if not hirelingTile then return false end
	local hirelingHouse = hirelingTile:getHouse()
	if not hirelingHouse then return false end
	return house:getId() == hirelingHouse:getId()
end

function Hireling:getPosition()
	return Position(self.posx, self.posy, self.posz)
end

function Hireling:setPosition(pos)
	self.posx = pos.x
	self.posy = pos.y
	self.posz = pos.z
end

function Hireling:getOutfit()
	return {
		lookType = self.looktype,
		lookHead = self.lookhead,
		lookAddons = 0,
		lookMount = 0,
		lookLegs = self.looklegs,
		lookBody = self.lookbody,
		lookFeet = self.lookfeet,
	}
end

function Hireling:setOutfit(outfit)
	self.looktype = outfit.lookType
	self.lookhead = outfit.lookHead
	self.lookbody = outfit.lookBody
	self.looklegs = outfit.lookLegs
	self.lookfeet = outfit.lookFeet
end

function Hireling:getAvailableOutfits()
	local store = getHirelingKV(self:getOwnerId())
	local flags = store:get("outfits") or 0
	local sex = (self.sex == HIRELING_SEX.FEMALE) and "female" or "male"

	local outfits = {}
	table.insert(outfits, {name = HIRELING_OUTFIT_DEFAULT.name, lookType = HIRELING_OUTFIT_DEFAULT[sex]})

	if flags > 0 then
		for key, value in pairs(HIRELING_OUTFITS) do
			if bit.band(flags, value) ~= 0 then
				local tbl = HIRELING_OUTFITS_TABLE[key]
				if tbl then
					table.insert(outfits, {name = tbl.name, lookType = tbl[sex]})
				end
			end
		end
	end
	return outfits
end

function Hireling:hasOutfit(lookType)
	local outfits = self:getAvailableOutfits()
	for _, outfit in ipairs(outfits) do
		if outfit.lookType == lookType then
			return true
		end
	end
	return false
end

function Hireling:requestOutfitChange()
	local player = Player(self:getOwnerId())
	if not player then return end
	if not player:isUsingAstraClient() then return end
	HIRELING_OUTFIT_CHANGING[self:getOwnerId()] = self:getId()
	player:sendHirelingOutfitWindow(self)
end

function Hireling:changeOutfit(outfit)
	HIRELING_OUTFIT_CHANGING[self:getOwnerId()] = nil
	if not self:hasOutfit(outfit.lookType) then return end
	local npc = Npc(self.cid)
	if npc then
		local creature = Creature(npc)
		if creature then
			creature:setOutfit(outfit)
		end
	end
	self:setOutfit(outfit)
end

function Hireling:hasSkill(skillName)
	return hasSkillByKV(self:getOwnerId(), skillName)
end

function Hireling:setCreature(cid)
	self.cid = cid
end

function Hireling:save()
	local sql = "UPDATE `player_hirelings` SET"
	sql = sql .. " `name`=" .. db.escapeString(self.name)
	sql = sql .. ", `active`=" .. tostring(self.active)
	sql = sql .. ", `sex`=" .. tostring(self.sex)
	sql = sql .. ", `posx`=" .. tostring(self.posx)
	sql = sql .. ", `posy`=" .. tostring(self.posy)
	sql = sql .. ", `posz`=" .. tostring(self.posz)
	sql = sql .. ", `lookbody`=" .. tostring(self.lookbody)
	sql = sql .. ", `lookfeet`=" .. tostring(self.lookfeet)
	sql = sql .. ", `lookhead`=" .. tostring(self.lookhead)
	sql = sql .. ", `looklegs`=" .. tostring(self.looklegs)
	sql = sql .. ", `looktype`=" .. tostring(self.looktype)
	sql = sql .. " WHERE `id`=" .. tostring(self.id)
	db.query(sql)
end

function Hireling:spawn()
	self.active = 1
	local npc = Game.createNpc("Hireling", self:getPosition(), false, true, CONST_ME_TELEPORT)
	if not npc then return end
	npc:setName(self:getName())
	local creature = Creature(npc)
	if creature then
		creature:setOutfit(self:getOutfit())
	end
	npc:setSpeechBubble(SPEECHBUBBLE_NORMAL)
end

function Hireling:returnToLamp(player_id)
	local player = Player(player_id)
	if not player then return end

	if self:getOwnerId() ~= player_id then
		player:getPosition():sendMagicEffect(CONST_ME_POFF)
		player:sendTextMessage(MESSAGE_INFO_DESCR, "You are not the master of this hireling.")
		return
	end

	local lampType = ItemType(HIRELING_LAMP_ID)
	if player:getFreeCapacity() < lampType:getWeight(1) then
		player:getPosition():sendMagicEffect(CONST_ME_POFF)
		player:sendTextMessage(MESSAGE_INFO_DESCR, "You do not have enough capacity.")
		return
	end

	local inbox = player:getStoreInbox()
	if not inbox then
		player:getPosition():sendMagicEffect(CONST_ME_POFF)
		player:sendTextMessage(MESSAGE_INFO_DESCR, "You don't have enough room in your inbox.")
		return
	end

	local creature = Creature(self.cid)
	if creature then
		creature:getPosition():sendMagicEffect(CONST_ME_PURPLESMOKE)
		creature:remove()
	end

	local lamp = inbox:addItem(HIRELING_LAMP_ID, 1, INDEX_WHEREEVER, FLAG_NOLIMIT)
	if lamp then
		lamp:setAttribute(ITEM_ATTRIBUTE_DESCRIPTION,
			"This mysterious lamp summons your very own personal hireling.\n" ..
			"This item cannot be traded.\n" ..
			"This magic lamp is the home of " .. self:getName() .. ".")
		lamp:setAttribute(ITEM_ATTRIBUTE_ACTIONID, self:getId())
	end

	self.active = 0
	self.cid = -1
	self:setPosition({x = 0, y = 0, z = 0})
end

-- [[ GLOBAL FUNCTIONS ]]

function SaveHirelings()
	for _, hireling in ipairs(HIRELINGS) do
		hireling:save()
	end
end

function getHirelingById(id)
	for _, hireling in ipairs(HIRELINGS) do
		if hireling:getId() == id then
			return hireling
		end
	end
	return nil
end

function getHirelingByPosition(position)
	for _, hireling in ipairs(HIRELINGS) do
		if hireling.posx == position.x and hireling.posy == position.y and hireling.posz == position.z then
			return hireling
		end
	end
	return nil
end

local function checkHouseAccess(hireling)
	if hireling.active == 0 then return false end
	local pos = hireling:getPosition()
	local tile = Tile(pos)
	if not tile then return false end
	local house = tile:getHouse()
	if not house then return false end

	if house:getOwnerGuid() == hireling:getOwnerId() then return true end

	local player = Game.getOfflinePlayer(hireling:getOwnerId())
	if not player then return false end

	print(">> Returning Hireling:" .. hireling:getName() .. " to owner Inbox")
	local inbox = player:getStoreInbox()
	if inbox then
		local lamp = inbox:addItem(HIRELING_LAMP_ID, 1, INDEX_WHEREEVER, FLAG_NOLIMIT)
		if lamp then
			lamp:setAttribute(ITEM_ATTRIBUTE_DESCRIPTION,
				"This mysterious lamp summons your very own personal hireling.\n" ..
				"This item cannot be traded.\n" ..
				"This magic lamp is the home of " .. hireling:getName() .. ".")
			lamp:setAttribute(ITEM_ATTRIBUTE_ACTIONID, hireling:getId())
		end
	end
	player:save()
	hireling.active = 0
	hireling.cid = -1
	hireling:setPosition({x = 0, y = 0, z = 0})
	return false
end

function HirelingsInit()
	print(">> Loading Hirelings")
	local resultId = db.storeQuery("SELECT * FROM `player_hirelings`")
	if not resultId then return end

	repeat
		local player_id = result.getNumber(resultId, "player_id")
		if not PLAYER_HIRELINGS[player_id] then
			PLAYER_HIRELINGS[player_id] = {}
		end

		local hireling = Hireling:new()
		hireling.id = result.getNumber(resultId, "id")
		hireling.player_id = player_id
		hireling.name = result.getString(resultId, "name")
		hireling.active = result.getNumber(resultId, "active")
		hireling.sex = result.getNumber(resultId, "sex")
		hireling.posx = result.getNumber(resultId, "posx")
		hireling.posy = result.getNumber(resultId, "posy")
		hireling.posz = result.getNumber(resultId, "posz")
		hireling.lookbody = result.getNumber(resultId, "lookbody")
		hireling.lookfeet = result.getNumber(resultId, "lookfeet")
		hireling.lookhead = result.getNumber(resultId, "lookhead")
		hireling.looklegs = result.getNumber(resultId, "looklegs")
		hireling.looktype = result.getNumber(resultId, "looktype")

		table.insert(PLAYER_HIRELINGS[player_id], hireling)
		table.insert(HIRELINGS, hireling)
	until not result.next(resultId)
	result.free(resultId)

	print(">> Spawning Hirelings")
	for _, hireling in ipairs(HIRELINGS) do
		if checkHouseAccess(hireling) then
			hireling:spawn()
		end
	end
end

function PersistHireling(hireling)
	db.query(string.format(
		"INSERT INTO `player_hirelings` (`player_id`,`name`,`active`,`sex`,`posx`,`posy`,`posz`,`lookbody`,`lookfeet`,`lookhead`,`looklegs`,`looktype`) VALUES (%d, %s, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d)",
		hireling.player_id, db.escapeString(hireling.name), hireling.active, hireling.sex,
		hireling.posx, hireling.posy, hireling.posz,
		hireling.lookbody, hireling.lookfeet, hireling.lookhead, hireling.looklegs, hireling.looktype
	))

	local resultId = db.storeQuery(string.format(
		"SELECT `id` FROM `player_hirelings` WHERE `player_id`=%d ORDER BY `id` DESC LIMIT 1",
		hireling.player_id
	))
	if resultId then
		hireling.id = result.getNumber(resultId, "id")
		result.free(resultId)
		return true
	end
	return false
end

-- [[ PLAYER EXTENSIONS ]]

function Player:getHirelings()
	return PLAYER_HIRELINGS[self:getGuid()] or {}
end

function Player:getHirelingsCount()
	return #self:getHirelings()
end

function Player:hasHirelings()
	local hirelings = PLAYER_HIRELINGS[self:getGuid()]
	return hirelings and #hirelings > 0 or false
end

function Player:addNewHireling(name, sex)
	local hireling = Hireling:new()
	hireling.name = name
	hireling.player_id = self:getGuid()
	if sex == HIRELING_SEX.FEMALE then
		hireling.looktype = 136
		hireling.sex = HIRELING_SEX.FEMALE
	else
		hireling.looktype = 128
		hireling.sex = HIRELING_SEX.MALE
	end

	local lampType = ItemType(HIRELING_LAMP_ID)
	if self:getFreeCapacity() < lampType:getWeight(1) then
		self:getPosition():sendMagicEffect(CONST_ME_POFF)
		self:sendTextMessage(MESSAGE_INFO_DESCR, "You do not have enough capacity.")
		return false
	end

	local inbox = self:getStoreInbox()
	if not inbox then
		self:getPosition():sendMagicEffect(CONST_ME_POFF)
		self:sendTextMessage(MESSAGE_INFO_DESCR, "You don't have enough room in your inbox.")
		return false
	end

	local saved = PersistHireling(hireling)
	if not saved then
		print("Error saving Hireling:" .. name .. " - player:" .. self:getName())
		return false
	end

	if not PLAYER_HIRELINGS[self:getGuid()] then
		PLAYER_HIRELINGS[self:getGuid()] = {}
	end
	table.insert(PLAYER_HIRELINGS[self:getGuid()], hireling)
	table.insert(HIRELINGS, hireling)

	local lamp = inbox:addItem(HIRELING_LAMP_ID, 1, INDEX_WHEREEVER, FLAG_NOLIMIT)
	if lamp then
		lamp:setAttribute(ITEM_ATTRIBUTE_DESCRIPTION,
			"This mysterious lamp summons your very own personal hireling.\n" ..
			"This item cannot be traded.\n" ..
			"This magic lamp is the home of " .. hireling:getName() .. ".")
		lamp:setAttribute(ITEM_ATTRIBUTE_ACTIONID, hireling:getId())
	end
	hireling.active = 0
	return hireling
end

function Player:isChangingHirelingOutfit()
	local id = HIRELING_OUTFIT_CHANGING[self:getGuid()]
	return id and id > 0 or false
end

function Player:getHirelingChangingOutfit()
	local id = HIRELING_OUTFIT_CHANGING[self:getGuid()]
	if not id then return nil end
	return getHirelingById(id)
end

function Player:findHirelingLamp(hirelingId)
	local inbox = self:getStoreInbox()
	if not inbox then return nil end
	local items = inbox:getItems()
	for _, item in ipairs(items) do
		if item:getId() == HIRELING_LAMP_ID and item:getAttribute(ITEM_ATTRIBUTE_ACTIONID) == hirelingId then
			return item
		end
	end
	return nil
end

function Player:hasHirelingSkill(skillName)
	return hasSkillByKV(self:getGuid(), skillName)
end

function Player:enableHirelingSkill(skillName)
	local store = getHirelingKV(self:getGuid())
	local skills = store:get("skills") or 0
	local flag = getSkillFlag(skillName)
	skills = bit.bor(skills, flag)
	store:set("skills", skills)
end

function Player:hasHirelingOutfit(outfitKey)
	local store = getHirelingKV(self:getGuid())
	local outfits = store:get("outfits") or 0
	local flag = HIRELING_OUTFITS[outfitKey]
	if not flag or outfits <= 0 then return false end
	return bit.band(outfits, flag) ~= 0
end

function Player:enableHirelingOutfit(outfitKey)
	local store = getHirelingKV(self:getGuid())
	local outfits = store:get("outfits") or 0
	local flag = HIRELING_OUTFITS[outfitKey]
	if not flag then return end
	outfits = bit.bor(outfits, flag)
	store:set("outfits", outfits)
end

local function addOutfit(msg, outfit)
	msg:addU16(outfit.lookType)
	msg:addByte(outfit.lookHead)
	msg:addByte(outfit.lookBody)
	msg:addByte(outfit.lookLegs)
	msg:addByte(outfit.lookFeet)
	msg:addByte(outfit.lookAddons)
	msg:addU16(outfit.lookMount)
end

function Player:sendHirelingOutfitWindow(hireling)
	local msg = NetworkMessage()
	msg:addByte(0xC8)
	addOutfit(msg, hireling:getOutfit())

	local availableOutfits = hireling:getAvailableOutfits()
	msg:addU16(#availableOutfits)

	for _, outfit in ipairs(availableOutfits) do
		msg:addU16(outfit.lookType)
		msg:addString(outfit.name)
		msg:addByte(0x00)
	end

	msg:addU16(0x00)
	msg:addByte(0x00)
	msg:addByte(0x00)
	msg:sendToPlayer(self)
end

function Player:sendHirelingSelectionModal(title, message, callback, data)
	local hirelings = self:getHirelings()
	local modal = ModalWindow {
		title = title,
		message = message,
	}
	local hireling
	for i = 1, #hirelings do
		hireling = hirelings[i]
		local choice = modal:addChoice(string.format("#%d - %s", i, hireling:getName()))
		choice.hireling = hireling
	end

	local playerId = self:getId()
	local internalConfirm = function(button, choice)
		local hrlng = choice and choice.hireling or nil
		callback(playerId, data, hrlng)
	end
	local internalCancel = function(btn, choice)
		callback(playerId, data, nil)
	end

	modal:addButton("Select", internalConfirm)
	modal:setDefaultEnterButton("Select")
	modal:addButton("Cancel", internalCancel)
	modal:setDefaultEscapeButton("Cancel")
	modal:sendToPlayer(self)
end
