
/*******
-- YOU MUST RUN THIS IN ACORE_CHARACTERS DATABASE
-- characters.prestige_stats
********/

CREATE TABLE IF NOT EXISTS `prestige_stats` (
  `player_id` INT NOT NULL PRIMARY KEY,
  `prestige_level` INT DEFAULT 0,
  `draft_state` TINYINT DEFAULT 0,
  `successful_drafts` INT DEFAULT 0,
  `total_expected_drafts` INT DEFAULT 0,
  `rerolls` INT DEFAULT 0,
  `stored_class` TINYINT DEFAULT 0,
  `offered_spell_1` INT DEFAULT 0,
  `offered_spell_2` INT DEFAULT 0,
  `offered_spell_3` INT DEFAULT 0
);
-- characters.drafted_spells
CREATE TABLE IF NOT EXISTS `drafted_spells` (
  `player_guid` INT NOT NULL,
  `spell_id` INT NOT NULL,
  PRIMARY KEY (`player_guid`, `spell_id`)
);