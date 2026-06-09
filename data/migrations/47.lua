function onUpdateDatabase()
	logMigration("Updating database to version 47 (Bounty Tasks, Weekly Tasks, Soulseals)")

	local queries = {
		[[
			CREATE TABLE IF NOT EXISTS `player_bounty_tasks` (
				`player_id` INT NOT NULL,
				`state` TINYINT NOT NULL DEFAULT 0,
				`difficulty` TINYINT NOT NULL DEFAULT 0,
				`bounty_points` INT NOT NULL DEFAULT 0,
				`reroll_tokens` TINYINT NOT NULL DEFAULT 0,
				`free_reroll` BIGINT NOT NULL DEFAULT 0,
				`active_raceid` INT NOT NULL DEFAULT 0,
				`active_kills` INT NOT NULL DEFAULT 0,
				`active_required_kills` INT NOT NULL DEFAULT 0,
				`active_reward_exp` INT NOT NULL DEFAULT 0,
				`active_reward_points` TINYINT NOT NULL DEFAULT 0,
				`active_task_grade` TINYINT NOT NULL DEFAULT 0,
				`active_task_difficulty` TINYINT NOT NULL DEFAULT 0,
				`talisman_damage_level` TINYINT NOT NULL DEFAULT 0,
				`talisman_lifeleech_level` TINYINT NOT NULL DEFAULT 0,
				`talisman_loot_level` TINYINT NOT NULL DEFAULT 0,
				`talisman_bestiary_level` TINYINT NOT NULL DEFAULT 0,
				`preferred_lists` BLOB NULL,
				`current_creatures_list` BLOB NULL,
				PRIMARY KEY (`player_id`),
				CONSTRAINT `player_bounty_tasks_fk` FOREIGN KEY (`player_id`) REFERENCES `players` (`id`) ON DELETE CASCADE
			) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
		]],
		[[
			CREATE TABLE IF NOT EXISTS `player_weekly_tasks` (
				`player_id` INT NOT NULL,
				`has_expansion` BOOLEAN NOT NULL DEFAULT FALSE,
				`difficulty` TINYINT NOT NULL DEFAULT 0,
				`any_creature_total_kills` INT NOT NULL DEFAULT 0,
				`any_creature_current_kills` INT NOT NULL DEFAULT 0,
				`completed_kill_tasks` TINYINT NOT NULL DEFAULT 0,
				`completed_delivery_tasks` TINYINT NOT NULL DEFAULT 0,
				`kill_task_reward_exp` INT NOT NULL DEFAULT 0,
				`delivery_task_reward_exp` INT NOT NULL DEFAULT 0,
				`reward_hunting_points` INT NOT NULL DEFAULT 0,
				`reward_soulseals` INT NOT NULL DEFAULT 0,
				`soulseals_points` INT NOT NULL DEFAULT 0,
				`needs_reward` TINYINT NOT NULL DEFAULT 0,
				`weekly_progress_finished` TINYINT NOT NULL DEFAULT 0,
				`kill_tasks` BLOB NULL,
				`delivery_tasks` BLOB NULL,
				PRIMARY KEY (`player_id`),
				CONSTRAINT `player_weekly_tasks_fk` FOREIGN KEY (`player_id`) REFERENCES `players` (`id`) ON DELETE CASCADE
			) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
		]],
	}

	for _, query in ipairs(queries) do
		if not db.query(query) then
			return false
		end
	end
	return true
end
