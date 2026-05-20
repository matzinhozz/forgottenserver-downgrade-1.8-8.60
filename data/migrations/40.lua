function onUpdateDatabase()
	logMigration("Updating database to version 40 (Reset System: verify resets column)")

	local res = db.storeQuery(
		"SELECT COUNT(*) AS `cnt` FROM `information_schema`.`COLUMNS`"
		.. " WHERE `TABLE_SCHEMA` = DATABASE()"
		.. "   AND `TABLE_NAME`   = 'players'"
		.. "   AND `COLUMN_NAME`  = 'reset'"
	)
	local exists = false
	if res then
		exists = result.getNumber(res, "cnt") > 0
		result.free(res)
	end

	if not exists then
		local success = db.query("ALTER TABLE `players` ADD COLUMN `reset` int(10) UNSIGNED NOT NULL DEFAULT '0' AFTER `level`")
		if not success then
			logMigration("Failed to add `reset` column to `players` table")
			return false
		end
	end

	return true
end
