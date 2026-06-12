function onUpdateDatabase()
	logMigration("[Hireling System] Creating player_hirelings table")

	db.query([[
		CREATE TABLE IF NOT EXISTS `player_hirelings` (
			`id` INT NOT NULL AUTO_INCREMENT,
			`player_id` INT NOT NULL,
			`name` VARCHAR(255) NOT NULL DEFAULT '',
			`active` TINYINT UNSIGNED NOT NULL DEFAULT '0',
			`sex` TINYINT UNSIGNED NOT NULL DEFAULT '0',
			`posx` INT NOT NULL DEFAULT '0',
			`posy` INT NOT NULL DEFAULT '0',
			`posz` INT NOT NULL DEFAULT '0',
			`lookbody` INT NOT NULL DEFAULT '0',
			`lookfeet` INT NOT NULL DEFAULT '0',
			`lookhead` INT NOT NULL DEFAULT '0',
			`looklegs` INT NOT NULL DEFAULT '0',
			`looktype` INT NOT NULL DEFAULT '136',
			PRIMARY KEY (`id`),
			KEY `player_id` (`player_id`),
			CONSTRAINT `player_hirelings_ibfk_1` FOREIGN KEY (`player_id`) REFERENCES `players` (`id`) ON DELETE CASCADE
		) ENGINE=InnoDB DEFAULT CHARACTER SET=utf8;
	]])

	return true
end
