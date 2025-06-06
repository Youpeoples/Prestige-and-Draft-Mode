
-- YOU MUST RUN THIS IN ACORE_CHARACTERS DATABASE
-- characters.prestige_stats
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




--- NPC CHROMIE RUN THIS IN ACORE_WORLD (claims entryid 2069426)
DELETE FROM `creature_template` WHERE (`entry` = 2069426);
INSERT INTO `creature_template` (`entry`, `difficulty_entry_1`, `difficulty_entry_2`, `difficulty_entry_3`, `KillCredit1`, `KillCredit2`, `name`, `subname`, `IconName`, `gossip_menu_id`, `minlevel`, `maxlevel`, `exp`, `faction`, `npcflag`, `speed_walk`, `speed_run`, `speed_swim`, `speed_flight`, `detection_range`, `scale`, `rank`, `dmgschool`, `DamageModifier`, `BaseAttackTime`, `RangeAttackTime`, `BaseVariance`, `RangeVariance`, `unit_class`, `unit_flags`, `unit_flags2`, `dynamicflags`, `family`, `trainer_type`, `trainer_spell`, `trainer_class`, `trainer_race`, `type`, `type_flags`, `lootid`, `pickpocketloot`, `skinloot`, `PetSpellDataId`, `VehicleId`, `mingold`, `maxgold`, `AIName`, `MovementType`, `HoverHeight`, `HealthModifier`, `ManaModifier`, `ArmorModifier`, `ExperienceModifier`, `RacialLeader`, `movementId`, `RegenHealth`, `mechanic_immune_mask`, `spell_school_immune_mask`, `flags_extra`, `ScriptName`, `VerifiedBuild`) VALUES
(2069426, 0, 0, 0, 0, 0, 'Chromie', 'Prestige Ambassador', '', 0, 1, 1, 0, 35, 1, 1, 1.14286, 1, 1, 1, 1, 2, 0, 1, 0, 0, 0, 0, 0, 258, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, '', 0, 1, 1, 1, 1, 1, 0, 0, 1, 0, 0, 2, '', 0);
DELETE FROM `creature_template_model` WHERE (`CreatureID` = 2069426) AND (`Idx` IN (0));
INSERT INTO `creature_template_model` (`CreatureID`, `Idx`, `CreatureDisplayID`, `DisplayScale`, `Probability`, `VerifiedBuild`) VALUES
(2069426, 0, 24877, 1, 1, 0);
UPDATE `creature_template` SET `unit_class` = 8 WHERE (`entry` = 2069426);