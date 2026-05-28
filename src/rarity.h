#ifndef FS_RARITY_H
#define FS_RARITY_H

#include <array>
#include <string_view>

#include "enums.h"

namespace Rarity {

inline constexpr std::string_view TIER = "rarity.tier";

inline constexpr std::string_view STAT_ON_ATTACK_FIRE = "onAttackFireStrike";
inline constexpr std::string_view STAT_ON_ATTACK_ICE = "onAttackIceStrike";
inline constexpr std::string_view STAT_ON_ATTACK_TERRA = "onAttackTerraStrike";
inline constexpr std::string_view STAT_ON_ATTACK_DEATH = "onAttackDeathStrike";
inline constexpr std::string_view STAT_ON_ATTACK_ENERGY = "onAttackEnergyStrike";
inline constexpr std::string_view STAT_ON_ATTACK_DIVINE = "onAttackDivineMissile";

inline constexpr std::string_view STAT_ON_HIT_FIRE = "onHitFireStrike";
inline constexpr std::string_view STAT_ON_HIT_ICE = "onHitIceStrike";
inline constexpr std::string_view STAT_ON_HIT_TERRA = "onHitTerraStrike";
inline constexpr std::string_view STAT_ON_HIT_DEATH = "onHitDeathStrike";
inline constexpr std::string_view STAT_ON_HIT_ENERGY = "onHitEnergyStrike";
inline constexpr std::string_view STAT_ON_HIT_DIVINE = "onHitDivineMissile";

inline constexpr std::string_view STAT_DOUBLE_DAMAGE = "doubleDamage";
inline constexpr std::string_view STAT_PHYSICAL_DAMAGE = "physicalDamage";
inline constexpr std::string_view STAT_ENERGY_DAMAGE = "energyDamage";
inline constexpr std::string_view STAT_EARTH_DAMAGE = "earthDamage";
inline constexpr std::string_view STAT_FIRE_DAMAGE = "fireDamage";
inline constexpr std::string_view STAT_ICE_DAMAGE = "iceDamage";
inline constexpr std::string_view STAT_HOLY_DAMAGE = "holyDamage";
inline constexpr std::string_view STAT_DEATH_DAMAGE = "deathDamage";
inline constexpr std::string_view STAT_ELEMENTAL_DAMAGE = "elementalDamage";

inline constexpr std::string_view STAT_ON_KILL_EXPLOSION = "onKillExplosion";
inline constexpr std::string_view STAT_ON_KILL_REGEN_HP = "onKillRegenHp";
inline constexpr std::string_view STAT_ON_KILL_REGEN_MP = "onKillRegenMp";
inline constexpr std::string_view STAT_ON_KILL_BUFF_DAMAGE = "onKillBuffDamage";
inline constexpr std::string_view STAT_ON_KILL_BUFF_MAXHP = "onKillBuffMaxHp";
inline constexpr std::string_view STAT_ON_KILL_BUFF_MAXMP = "onKillBuffMaxMp";

inline constexpr std::string_view STAT_SPELL_SCALE_LEVEL = "spellScaleLevel";
inline constexpr std::string_view STAT_SPELL_SCALE_MAGIC = "spellScaleMagic";
inline constexpr std::string_view STAT_SPELL_SCALE_DIVISOR = "spellScaleDivisor";
inline constexpr std::string_view STAT_SPELL_DMG_MIN_SUFFIX = "DmgMin";
inline constexpr std::string_view STAT_SPELL_DMG_MAX_SUFFIX = "DmgMax";
inline constexpr std::string_view STAT_ON_KILL_BUFF_DURATION = "onKillBuffDuration";
inline constexpr std::string_view STAT_ON_KILL_BUFF_CRIT_CHANCE = "onKillBuffCritChance";
inline constexpr std::string_view STAT_ON_KILL_BUFF_CRIT_AMOUNT = "onKillBuffCritAmount";
inline constexpr std::string_view STAT_ON_KILL_BUFF_MAXHP_PCT = "onKillBuffMaxHpPercent";
inline constexpr std::string_view STAT_ON_KILL_BUFF_MAXMP_PCT = "onKillBuffMaxMpPercent";

inline constexpr std::array<slots_t, 5> ATTACK_SLOTS = {
	CONST_SLOT_LEFT, CONST_SLOT_RIGHT, CONST_SLOT_NECKLACE, CONST_SLOT_HEAD, CONST_SLOT_RING
};

} // namespace Rarity

#endif
