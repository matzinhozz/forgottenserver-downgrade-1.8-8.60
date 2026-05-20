function onUpdateDatabase()
	logMigration("Updating database to version 41 (kv_store table)")
	db.query([[
		CREATE TABLE IF NOT EXISTS `kv_store` (
			`key_name` varchar(191) NOT NULL,
			`timestamp` bigint NOT NULL,
			`value` longblob NOT NULL,
			PRIMARY KEY (`key_name`)
		) ENGINE=InnoDB DEFAULT CHARACTER SET=utf8;
	]])
	return true
end
