function onUpdateDatabase()
	logger.info("Updating database to version 40 (Reset System: verify resets column)")

	local res = db.storeQuery(
		"SELECT COUNT(*) AS `cnt` FROM `information_schema`.`COLUMNS`"
		.. " WHERE `TABLE_SCHEMA` = DATABASE()"
		.. "   AND `TABLE_NAME`   = 'players'"
		.. "   AND `COLUMN_NAME`  = 'reset'"
	)
	local exists = false
	if res then
		exists = res:getNumber("cnt") > 0
		res:free()
	end

	if not exists then
		db.query("ALTER TABLE `players` ADD COLUMN `reset` int(10) UNSIGNED NOT NULL DEFAULT '0' AFTER `level`")
	end

	return true
end
