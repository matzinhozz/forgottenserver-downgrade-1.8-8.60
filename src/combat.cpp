// Copyright 2023 The Forgotten Server Authors. All rights reserved.
// Use of this source code is governed by the GPL-2.0 License that can be found in the LICENSE file.

#include "otpch.h"

#include "combat.h"

#include "configmanager.h"
#include "events.h"
#include "game.h"
#include "instance_utils.h"
#include "luascript.h"
#include "matrixarea.h"
#include "monster.h"
#include "scriptmanager.h"
#include "scheduler.h"
#include "weapons.h"

extern Game g_game;

extern LuaEnvironment g_luaEnvironment;

std::vector<Tile*> getList(const MatrixArea& area, const Position& targetPos, const Direction dir)
{
	auto casterPos = getNextPosition(dir, targetPos);

	std::vector<Tile*> vec;

	auto& center = area.getCenter();

	Position tmpPos(targetPos.x - center.first, targetPos.y - center.second, targetPos.z);
	for (uint32_t row = 0; row < area.getRows(); ++row, ++tmpPos.y) {
		for (uint32_t col = 0; col < area.getCols(); ++col, ++tmpPos.x) {
			if (area(row, col)) {
				if (g_game.isSightClear(casterPos, tmpPos, true)) {
					Tile* tile = g_game.map.getTile(tmpPos);
					if (!tile) {
						auto newTile = std::make_unique<StaticTile>(tmpPos.x, tmpPos.y, tmpPos.z);
						tile = newTile.get();
						g_game.map.setTile(tmpPos, std::move(newTile));
					}
					vec.push_back(tile);
	}
}

namespace {

uint32_t g_cleaveDefaultPercent = 30;
uint32_t g_cleaveFistPercent = 20;
bool g_cleaveConfigLoaded = false;

void loadCleaveConfigFromLua()
{
	if (g_cleaveConfigLoaded) {
		return;
	}

	lua_State* L = g_luaEnvironment.getLuaState();
	if (!L) {
		g_cleaveConfigLoaded = true;
		return;
	}

	lua_getglobal(L, "CleaveSystem");
	if (lua_istable(L, -1)) {
		lua_getfield(L, -1, "defaultPercent");
		if (lua_isnumber(L, -1)) {
			g_cleaveDefaultPercent = static_cast<uint32_t>(lua_tonumber(L, -1));
		}
		lua_pop(L, 1);

		lua_getfield(L, -1, "fistPercent");
		if (lua_isnumber(L, -1)) {
			g_cleaveFistPercent = static_cast<uint32_t>(lua_tonumber(L, -1));
		}
		lua_pop(L, 1);
	}
	lua_pop(L, 1);

	g_cleaveConfigLoaded = true;
}

} // namespace

uint32_t Combat::getCleaveDefaultPercent()
{
	loadCleaveConfigFromLua();
	return g_cleaveDefaultPercent;
}

uint32_t Combat::getCleaveFistPercent()
{
	loadCleaveConfigFromLua();
	return g_cleaveFistPercent;
}

void Combat::doCombatCleave(Creature* caster, Creature* primaryTarget, const CombatDamage& originalDamage,
                            const CombatParams& params, uint32_t cleavePercent)
{
	if (cleavePercent == 0 || !caster) {
		return;
	}

	const Position& casterPos = caster->getPosition();

	SpectatorVec spectators;
	g_game.map.getSpectators(spectators, casterPos, false, false);

	for (const auto& spectator : spectators) {
		Creature* creature = spectator.get();
		if (!creature || creature == caster || creature == primaryTarget) {
			continue;
		}

		const Position& targetPos = creature->getPosition();
		if (targetPos.z != casterPos.z) {
			continue;
		}
		if (std::abs(targetPos.x - casterPos.x) > 1 || std::abs(targetPos.y - casterPos.y) > 1) {
			continue;
		}

		if (Combat::canDoCombat(caster, creature) != RETURNVALUE_NOERROR) {
			continue;
		}

		CombatDamage cleaveDamage;
		cleaveDamage.primary.type = originalDamage.primary.type;
		cleaveDamage.primary.value = (originalDamage.primary.value * static_cast<int32_t>(cleavePercent)) / 100;
		cleaveDamage.secondary.type = originalDamage.secondary.type;
		cleaveDamage.secondary.value = (originalDamage.secondary.value * static_cast<int32_t>(cleavePercent)) / 100;
		cleaveDamage.origin = originalDamage.origin;

		CombatParams cleaveParams;
		cleaveParams.impactEffect = params.impactEffect;
		cleaveParams.combatType = params.combatType;

		Combat::doTargetCombat(caster, creature, cleaveDamage, cleaveParams);
	}
}

//**********************************************************//

void ValueCallback::getMinMaxValues(Player* player, CombatDamage& damage) const
{
	// onGetPlayerMinMaxValues(...)
	if (!scriptInterface->reserveScriptEnv()) {
		LOG_ERROR("[Error - ValueCallback::getMinMaxValues] Call stack overflow");
		return;
	}

	ScriptEnvironment* env = scriptInterface->getScriptEnv();
	if (!env->setCallbackId(scriptId, scriptInterface)) {
		scriptInterface->resetScriptEnv();
		return;
	}

	lua_State* L = scriptInterface->getLuaState();

	scriptInterface->pushFunction(scriptId);

	Lua::pushUserdata<Player>(L, player);
	Lua::setMetatable(L, -1, "Player");

	int parameters = 1;
	switch (type) {
		case COMBAT_FORMULA_LEVELMAGIC: {
			// onGetPlayerMinMaxValues(player, level, maglevel)
			lua_pushinteger(L, player->getLevel());
			lua_pushinteger(L, player->getMagicLevel());
			parameters += 2;
			break;
		}

		case COMBAT_FORMULA_SKILL: {
			// onGetPlayerMinMaxValues(player, attackSkill, attackValue, attackFactor)
			Item* tool = player->getWeapon();
			const Weapon* weapon = g_weapons->getWeapon(tool);
			Item* item = nullptr;

			int32_t attackValue = 7;
			if (weapon) {
				attackValue = tool->getAttack();
				if (tool->getWeaponType() == WEAPON_AMMO) {
					item = player->getWeapon(true);
					if (item) {
						attackValue += item->getAttack();
					}
				}

				damage.secondary.type = weapon->getElementType();
				damage.secondary.value = weapon->getElementDamage(player, nullptr, tool);
			}

			lua_pushinteger(L, player->getWeaponSkill(item ? item : tool));
			lua_pushinteger(L, attackValue);
			lua_pushnumber(L, player->getAttackFactor());
			parameters += 3;
			break;
		}

		default: {
			LOG_ERROR("ValueCallback::getMinMaxValues - unknown callback type");
			scriptInterface->resetScriptEnv();
			return;
		}
	}

	int size0 = lua_gettop(L);
	if (lua_pcall(L, parameters, 2, 0) != 0) {
		LuaScriptInterface::reportError(nullptr, Lua::popString(L));
	} else {
		damage.primary.value = normal_random(static_cast<int32_t>(Lua::getNumber<double>(L, -2)),
		                                     static_cast<int32_t>(Lua::getNumber<double>(L, -1)));
		lua_pop(L, 2);
	}

	if ((lua_gettop(L) + parameters + 1) != size0) {
		LuaScriptInterface::reportError(nullptr, "Stack size changed!");
	}

	scriptInterface->resetScriptEnv();
}

//**********************************************************//

void TileCallback::onTileCombat(Creature* creature, Tile* tile) const
{
	// onTileCombat(creature, pos)
	if (!scriptInterface->reserveScriptEnv()) {
		LOG_ERROR("[Error - TileCallback::onTileCombat] Call stack overflow");
		return;
	}

	ScriptEnvironment* env = scriptInterface->getScriptEnv();
	if (!env->setCallbackId(scriptId, scriptInterface)) {
		scriptInterface->resetScriptEnv();
		return;
	}

	lua_State* L = scriptInterface->getLuaState();

	scriptInterface->pushFunction(scriptId);
	if (creature) {
		Lua::pushUserdata<Creature>(L, creature);
		Lua::setCreatureMetatable(L, -1, creature);
	} else {
		lua_pushnil(L);
	}
	Lua::pushPosition(L, tile->getPosition());

	scriptInterface->callFunction(2);
}

//**********************************************************//

void TargetCallback::onTargetCombat(Creature* creature, Creature* target) const
{
	// onTargetCombat(creature, target)
	if (!scriptInterface->reserveScriptEnv()) {
		LOG_ERROR("[Error - TargetCallback::onTargetCombat] Call stack overflow");
		return;
	}

	ScriptEnvironment* env = scriptInterface->getScriptEnv();
	if (!env->setCallbackId(scriptId, scriptInterface)) {
		scriptInterface->resetScriptEnv();
		return;
	}

	lua_State* L = scriptInterface->getLuaState();

	scriptInterface->pushFunction(scriptId);

	if (creature) {
		Lua::pushUserdata<Creature>(L, creature);
		Lua::setCreatureMetatable(L, -1, creature);
	} else {
		lua_pushnil(L);
	}

	if (target) {
		Lua::pushUserdata<Creature>(L, target);
		Lua::setCreatureMetatable(L, -1, target);
	} else {
		lua_pushnil(L);
	}

	int size0 = lua_gettop(L);

	if (lua_pcall(L, 2, 0 /*nReturnValues*/, 0) != 0) {
		LuaScriptInterface::reportError(nullptr, Lua::popString(L));
	}

	if ((lua_gettop(L) + 2 /*nParams*/ + 1) != size0) {
		LuaScriptInterface::reportError(nullptr, "Stack size changed!");
	}

	scriptInterface->resetScriptEnv();
}

const MatrixArea& AreaCombat::getArea(const Position& centerPos, const Position& targetPos) const
{
	int32_t dx = targetPos.getOffsetX(centerPos);
	int32_t dy = targetPos.getOffsetY(centerPos);

	Direction dir;
	if (dx < 0) {
		dir = DIRECTION_WEST;
	} else if (dx > 0) {
		dir = DIRECTION_EAST;
	} else if (dy < 0) {
		dir = DIRECTION_NORTH;
	} else {
		dir = DIRECTION_SOUTH;
	}

	if (hasExtArea) {
		if (dx < 0 && dy < 0) {
			dir = DIRECTION_NORTHWEST;
		} else if (dx > 0 && dy < 0) {
			dir = DIRECTION_NORTHEAST;
		} else if (dx < 0 && dy > 0) {
			dir = DIRECTION_SOUTHWEST;
		} else if (dx > 0 && dy > 0) {
			dir = DIRECTION_SOUTHEAST;
		}
	}

	if (dir >= areas.size()) {
		// this should not happen. it means we forgot to call setupArea.
		static MatrixArea empty;
		return empty;
	}
	return areas[dir];
}

void AreaCombat::setupArea(const std::vector<uint32_t>& vec, uint32_t rows)
{
	auto area = createArea(vec, rows);
	if (areas.size() == 0) {
		areas.resize(4);
	}

	areas[DIRECTION_EAST] = area.rotate90();
	areas[DIRECTION_SOUTH] = area.rotate180();
	areas[DIRECTION_WEST] = area.rotate270();
	areas[DIRECTION_NORTH] = std::move(area);
}

void AreaCombat::setupArea(int32_t length, int32_t spread)
{
	uint32_t rows = length;
	int32_t cols = 1;

	if (spread != 0) {
		cols = ((length - (length % spread)) / spread) * 2 + 1;
	}

	int32_t colSpread = cols;

	std::vector<uint32_t> vec;
	vec.reserve(rows * cols);
	for (uint32_t y = 1; y <= rows; ++y) {
		int32_t mincol = cols - colSpread + 1;
		int32_t maxcol = cols - (cols - colSpread);

		for (int32_t x = 1; x <= cols; ++x) {
			if (y == rows && x == ((cols - (cols % 2)) / 2) + 1) {
				vec.push_back(3);
			} else if (x >= mincol && x <= maxcol) {
				vec.push_back(1);
			} else {
				vec.push_back(0);
			}
		}

		if (spread > 0 && y % spread == 0) {
			--colSpread;
		}
	}

	setupArea(vec, rows);
}

void AreaCombat::setupArea(int32_t radius)
{
	int32_t area[13][13] = {{0, 0, 0, 0, 0, 0, 8, 0, 0, 0, 0, 0, 0}, {0, 0, 0, 0, 8, 8, 7, 8, 8, 0, 0, 0, 0},
	                        {0, 0, 0, 8, 7, 6, 6, 6, 7, 8, 0, 0, 0}, {0, 0, 8, 7, 6, 5, 5, 5, 6, 7, 8, 0, 0},
	                        {0, 8, 7, 6, 5, 4, 4, 4, 5, 6, 7, 8, 0}, {0, 8, 6, 5, 4, 3, 2, 3, 4, 5, 6, 8, 0},
	                        {8, 7, 6, 5, 4, 2, 1, 2, 4, 5, 6, 7, 8}, {0, 8, 6, 5, 4, 3, 2, 3, 4, 5, 6, 8, 0},
	                        {0, 8, 7, 6, 5, 4, 4, 4, 5, 6, 7, 8, 0}, {0, 0, 8, 7, 6, 5, 5, 5, 6, 7, 8, 0, 0},
	                        {0, 0, 0, 8, 7, 6, 6, 6, 7, 8, 0, 0, 0}, {0, 0, 0, 0, 8, 8, 7, 8, 8, 0, 0, 0, 0},
	                        {0, 0, 0, 0, 0, 0, 8, 0, 0, 0, 0, 0, 0}};

	std::vector<uint32_t> vec;
	vec.reserve(13 * 13);
	for (auto& row : area) {
		for (int cell : row) {
			if (cell == 1) {
				vec.push_back(3);
			} else if (cell > 0 && cell <= radius) {
				vec.push_back(1);
			} else {
				vec.push_back(0);
			}
		}
	}

	setupArea(vec, 13);
}

void AreaCombat::setupAreaRing(int32_t ring)
{
	int32_t area[13][13] = {{0, 0, 0, 0, 0, 7, 7, 7, 0, 0, 0, 0, 0}, {0, 0, 0, 0, 7, 6, 6, 6, 7, 0, 0, 0, 0},
	                        {0, 0, 0, 7, 6, 5, 5, 5, 6, 7, 0, 0, 0}, {0, 0, 7, 6, 5, 4, 4, 4, 5, 6, 7, 0, 0},
	                        {0, 7, 6, 5, 4, 3, 3, 3, 4, 5, 6, 7, 0}, {7, 6, 5, 4, 3, 2, 0, 2, 3, 4, 5, 6, 7},
	                        {7, 6, 5, 4, 3, 0, 1, 0, 3, 4, 5, 6, 7}, {7, 6, 5, 4, 3, 2, 0, 2, 3, 4, 5, 6, 7},
	                        {0, 7, 6, 5, 4, 3, 3, 3, 4, 5, 6, 7, 0}, {0, 0, 7, 6, 5, 4, 4, 4, 5, 6, 7, 0, 0},
	                        {0, 0, 0, 7, 6, 5, 5, 5, 6, 7, 0, 0, 0}, {0, 0, 0, 0, 7, 6, 6, 6, 7, 0, 0, 0, 0},
	                        {0, 0, 0, 0, 0, 7, 7, 7, 0, 0, 0, 0, 0}};

	std::vector<uint32_t> vec;
	vec.reserve(13 * 13);
	for (auto& row : area) {
		for (int cell : row) {
			if (cell == 1) {
				vec.push_back(3);
			} else if (cell > 0 && cell == ring) {
				vec.push_back(1);
			} else {
				vec.push_back(0);
			}
		}
	}

	setupArea(vec, 13);
}

void AreaCombat::setupExtArea(const std::vector<uint32_t>& vec, uint32_t rows)
{
	if (vec.empty()) {
		return;
	}

	hasExtArea = true;
	auto area = createArea(vec, rows);
	areas.resize(8);
	areas[DIRECTION_NORTHEAST] = area.mirror();
	areas[DIRECTION_SOUTHWEST] = area.flip();
	areas[DIRECTION_SOUTHEAST] = area.rotate180();
	areas[DIRECTION_NORTHWEST] = std::move(area);
}

//**********************************************************//
// Chain System
//**********************************************************//

ChainCallback::ChainCallback(uint8_t chainTargets, uint8_t chainDistance, bool backtracking)
    : m_chainDistance(chainDistance), m_chainTargets(chainTargets), m_backtracking(backtracking) {}

void ChainCallback::setFromLua(bool fromLua) { m_fromLua = fromLua; }

void ChainCallback::getChainValues(Creature* creature, uint8_t& maxTargets, uint8_t& chainDistance, bool& backtracking)
{
	if (m_fromLua) {
		onChainCombat(creature, maxTargets, chainDistance, backtracking);
		return;
	}

	if (m_chainTargets && m_chainDistance) {
		maxTargets = m_chainTargets;
		chainDistance = m_chainDistance;
		backtracking = m_backtracking;
	}
}

void ChainCallback::onChainCombat(Creature* creature, uint8_t& chainTargets, uint8_t& chainDistance, bool& backtracking) const
{
	if (!scriptInterface->reserveScriptEnv()) {
		LOG_ERROR("[ChainCallback::onChainCombat] Call stack overflow");
		return;
	}

	ScriptEnvironment* env = scriptInterface->getScriptEnv();
	if (!env->setCallbackId(scriptId, scriptInterface)) {
		scriptInterface->resetScriptEnv();
		return;
	}

	lua_State* L = scriptInterface->getLuaState();
	scriptInterface->pushFunction(scriptId);

	if (creature) {
		Lua::pushUserdata<Creature>(L, creature);
		Lua::setCreatureMetatable(L, -1, creature);
	} else {
		lua_pushnil(L);
	}

	int size0 = lua_gettop(L);
	if (lua_pcall(L, 1, 3, 0) != 0) {
		LuaScriptInterface::reportError(nullptr, Lua::popString(L));
	} else {
		chainTargets = std::max<uint8_t>(1, Lua::getNumber<uint8_t>(L, -3));
		chainDistance = std::max<uint8_t>(1, Lua::getNumber<uint8_t>(L, -2));
		backtracking = Lua::getBoolean(L, -1);
		lua_pop(L, 3);
	}

	if ((lua_gettop(L) + 1 + 1) != size0) {
		LuaScriptInterface::reportError(nullptr, "Stack size changed!");
	}

	scriptInterface->resetScriptEnv();
}

//**********************************************************//

bool ChainPickerCallback::onChainCombat(Creature* creature, Creature* target) const
{
	if (!scriptInterface->reserveScriptEnv()) {
		LOG_ERROR("[ChainPickerCallback::onChainCombat] Call stack overflow");
		return true;
	}

	ScriptEnvironment* env = scriptInterface->getScriptEnv();
	if (!env->setCallbackId(scriptId, scriptInterface)) {
		scriptInterface->resetScriptEnv();
		return true;
	}

	lua_State* L = scriptInterface->getLuaState();
	scriptInterface->pushFunction(scriptId);

	if (creature) {
		Lua::pushUserdata<Creature>(L, creature);
		Lua::setCreatureMetatable(L, -1, creature);
	} else {
		lua_pushnil(L);
	}

	if (target) {
		Lua::pushUserdata<Creature>(L, target);
		Lua::setCreatureMetatable(L, -1, target);
	} else {
		lua_pushnil(L);
	}

	int size0 = lua_gettop(L);
	bool result = true;

	if (lua_pcall(L, 2, 1, 0) != 0) {
		LuaScriptInterface::reportError(nullptr, Lua::popString(L));
	} else {
		result = Lua::getBoolean(L, -1);
		lua_pop(L, 1);
	}

	if ((lua_gettop(L) + 2 + 1) != size0) {
		LuaScriptInterface::reportError(nullptr, "Stack size changed!");
	}

	scriptInterface->resetScriptEnv();
	return result;
}

//**********************************************************//

void Combat::setChainCallback(uint8_t chainTargets, uint8_t chainDistance, bool backtracking)
{
	params.chainCallback = std::make_unique<ChainCallback>(chainTargets, chainDistance, backtracking);
}

void Combat::doChainEffect(const Position& origin, const Position& pos, uint8_t effect)
{
	if (effect == CONST_ME_NONE) {
		return;
	}

	g_game.addMagicEffect(origin, effect);
	g_game.addMagicEffect(pos, effect);
}

bool Combat::isValidChainTarget(Creature* caster, Creature* currentTarget, Creature* potentialTarget,
                                const CombatParams& params, bool /*aggressive*/)
{
	if (Combat::canDoCombat(caster, potentialTarget) != RETURNVALUE_NOERROR) {
		return false;
	}

	if (params.chainPickerCallback && !params.chainPickerCallback->onChainCombat(caster, potentialTarget)) {
		return false;
	}

	if (!g_game.isSightClear(currentTarget->getPosition(), potentialTarget->getPosition(), true)) {
		return false;
	}

	return true;
}

std::vector<std::pair<Position, std::vector<uint32_t>>> Combat::pickChainTargets(
    Creature* caster, const CombatParams& params, uint8_t chainDistance, uint8_t maxTargets,
    bool aggressive, bool backtracking, Creature* initialTarget)
{
	std::vector<std::pair<Position, std::vector<uint32_t>>> resultMap;
	std::vector<Creature*> targets;
	std::unordered_set<uint32_t> visited;

	if (initialTarget && initialTarget != caster) {
		targets.push_back(initialTarget);
		visited.insert(initialTarget->getID());
		resultMap.emplace_back(caster->getPosition(), std::vector<uint32_t>{initialTarget->getID()});
	} else {
		targets.push_back(caster);
		maxTargets++;
	}

	int backtrackingAttempts = 10;
	while (!targets.empty() && targets.size() < static_cast<size_t>(maxTargets) && backtrackingAttempts > 0) {
		Creature* currentTarget = targets.back();

		SpectatorVec spectators;
		g_game.map.getSpectators(spectators, currentTarget->getPosition(), false, false,
		                         chainDistance, chainDistance, chainDistance, chainDistance);

		double closestDist = std::numeric_limits<double>::max();
		Creature* closestSpectator = nullptr;

		for (const auto& spectator : spectators) {
			if (!spectator || visited.contains(spectator->getID())) {
				continue;
			}

			if (spectator->getNpc()) {
				visited.insert(spectator->getID());
				continue;
			}

			if (spectator.get() == caster) {
				visited.insert(spectator->getID());
				continue;
			}

			Tile* tile = spectator->getTile();
			if (tile && tile->hasFlag(TILESTATE_PROTECTIONZONE)) {
				visited.insert(spectator->getID());
				continue;
			}

			Player* casterPlayer = caster ? caster->getPlayer() : nullptr;
			Monster* casterMonster = caster ? caster->getMonster() : nullptr;
			Player* spectatorPlayer = spectator->getPlayer();
			bool spectatorSummon = spectator->isSummon();

			if (casterPlayer) {
				if (casterPlayer->hasSecureMode()) {
					if (spectatorPlayer) {
						visited.insert(spectator->getID());
						continue;
					}
					if (spectatorSummon && spectator->getMaster() && spectator->getMaster()->getPlayer()) {
						visited.insert(spectator->getID());
						continue;
					}
				}
			} else if (casterMonster) {
				if (spectatorSummon) {
					auto master = spectator->getMaster();
					if (!master || !master->getPlayer()) {
						visited.insert(spectator->getID());
						continue;
					}
				} else if (!spectatorPlayer) {
					visited.insert(spectator->getID());
					continue;
				}
			}

			if (!isValidChainTarget(caster, currentTarget, spectator.get(), params, aggressive)) {
				visited.insert(spectator->getID());
				continue;
			}

			double dist = currentTarget->getPosition().getDistanceX(spectator->getPosition()) +
			              currentTarget->getPosition().getDistanceY(spectator->getPosition());

			if (dist < closestDist) {
				closestDist = dist;
				closestSpectator = spectator.get();
			}
		}

		if (closestSpectator) {
			bool found = false;
			for (auto& [pos, vec] : resultMap) {
				if (pos == currentTarget->getPosition()) {
					vec.push_back(closestSpectator->getID());
					found = true;
					break;
				}
			}
			if (!found) {
				resultMap.emplace_back(currentTarget->getPosition(),
				                       std::vector<uint32_t>{closestSpectator->getID()});
			}

			targets.push_back(closestSpectator);
			visited.insert(closestSpectator->getID());
			continue;
		}

		if (backtracking) {
			targets.pop_back();
			backtrackingAttempts--;
			continue;
		}
		break;
	}

	return resultMap;
}

bool Combat::doCombatChain(Creature* caster, Creature* target, bool aggressive) const
{
	if (!params.chainCallback) {
		return false;
	}

	uint8_t maxTargets = 0;
	uint8_t chainDistance = 0;
	bool backtracking = false;
	params.chainCallback->getChainValues(caster, maxTargets, chainDistance, backtracking);

	auto targets = pickChainTargets(caster, params, chainDistance, maxTargets, aggressive, backtracking, target);
	if (targets.empty() || (targets.size() == 1 && targets.begin()->second.empty())) {
		return false;
	}

	auto self = shared_from_this();
	const uint8_t capturedChainEffect = params.chainEffect;
	int i = 0;
	for (const auto& [from, toVector] : targets) {
		auto delay = i * std::max<int32_t>(SCHEDULER_MINTICKS, ConfigManager::getInteger(ConfigManager::COMBAT_CHAIN_DELAY));
		++i;
		for (const auto& to : toVector) {
			g_scheduler.addEvent(delay, [self, casterId = caster ? caster->getID() : 0, to, from, capturedChainEffect]() {
				Creature* resolvedCaster = g_game.getCreatureByID(casterId);
				Creature* nextTarget = g_game.getCreatureByID(to);
				if (!nextTarget) {
					return;
				}
				Combat::doChainEffect(from, nextTarget->getPosition(), capturedChainEffect);
				if (resolvedCaster) {
					CombatDamage damage = self->getCombatDamage(resolvedCaster, nextTarget);
					bool canCombat = !self->params.aggressive ||
					                 (resolvedCaster != nextTarget &&
					                  Combat::canDoCombat(resolvedCaster, nextTarget) == RETURNVALUE_NOERROR);
					if (canCombat) {
						doTargetCombat(resolvedCaster, nextTarget, damage, self->params);
					}
				}
			});
		}
	}

	return true;
}

void Combat::setupChain(const Weapon* weapon)
{
	if (!weapon) {
		return;
	}

	WeaponType_t weaponType = weapon->weaponType;
	if (weaponType == WEAPON_NONE || weaponType == WEAPON_SHIELD) {
		return;
	}

	if (weapon->isChainDisabled()) {
		return;
	}

	params.combatType = weapon->params.combatType;
	if (weaponType != WEAPON_WAND) {
		params.blockedByArmor = true;
	}

	setChainCallback(static_cast<uint8_t>(ConfigManager::getInteger(ConfigManager::COMBAT_CHAIN_TARGETS)), 1, true);

	double formula = 1.0;
	uint16_t effect = CONST_ME_HITAREA;

	switch (weaponType) {
		case WEAPON_FIST:
			formula = ConfigManager::getFloat(ConfigManager::COMBAT_CHAIN_SKILL_FORMULA_FIST);
			effect = CONST_ME_HITAREA;
			break;
		case WEAPON_SWORD:
			formula = ConfigManager::getFloat(ConfigManager::COMBAT_CHAIN_SKILL_FORMULA_SWORD);
			effect = CONST_ME_SLASH;
			break;
		case WEAPON_CLUB:
			formula = ConfigManager::getFloat(ConfigManager::COMBAT_CHAIN_SKILL_FORMULA_CLUB);
			effect = CONST_ME_BLACK_BLOOD;
			break;
		case WEAPON_AXE:
			formula = ConfigManager::getFloat(ConfigManager::COMBAT_CHAIN_SKILL_FORMULA_AXE);
			effect = CONST_ME_HITAREA;
			break;
		case WEAPON_DISTANCE:
		case WEAPON_AMMO:
			formula = ConfigManager::getFloat(ConfigManager::COMBAT_CHAIN_SKILL_FORMULA_DISTANCE);
			effect = CONST_ME_HOLYDAMAGE;
			break;
		default:
			break;
	}

	double weaponSkillFormula = weapon->getChainSkillValue();
	double useFormula = weaponSkillFormula > 0 ? weaponSkillFormula : formula;
	setPlayerCombatValues(COMBAT_FORMULA_SKILL, 0, 0, useFormula, 0);
	params.impactEffect = effect;

	if (weaponType == WEAPON_WAND) {
		static const std::map<CombatType_t, std::pair<uint16_t, uint16_t>> elementEffects = {
		    {COMBAT_DEATHDAMAGE, {CONST_ME_MORTAREA, CONST_ME_BLACK_BLOOD}},
		    {COMBAT_ENERGYDAMAGE, {CONST_ME_ENERGYAREA, CONST_ME_ENERGYHIT}},
		    {COMBAT_FIREDAMAGE, {CONST_ME_FIREATTACK, CONST_ME_FIREATTACK}},
		    {COMBAT_ICEDAMAGE, {CONST_ME_ICEATTACK, CONST_ME_ICEATTACK}},
		    {COMBAT_EARTHDAMAGE, {CONST_ME_STONES, CONST_ME_POISONAREA}},
		};

		auto it = elementEffects.find(weapon->getElementType());
		if (it != elementEffects.end()) {
			setPlayerCombatValues(COMBAT_FORMULA_LEVELMAGIC, 0, 0,
			                      -ConfigManager::getFloat(ConfigManager::COMBAT_CHAIN_SKILL_FORMULA_WANDS_AND_RODS), 0);
			params.impactEffect = it->second.first;
			params.chainEffect = static_cast<uint8_t>(it->second.second);
		}
	}
}

//**********************************************************//

void MagicField::onStepInField(Creature* creature)
{
	const ItemType& it = items[getID()];
	if (it.conditionDamage) {
		auto conditionCopy = it.conditionDamage->clone();
		uint32_t ownerId = getOwner();
		if (ownerId) {
			bool harmfulField = true;

			if (g_game.getWorldType() == WORLD_TYPE_NO_PVP || getTile()->hasFlag(TILESTATE_NOPVPZONE)) {
				Creature* owner = g_game.getCreatureByID(ownerId);
				if (owner) {
					if (owner->getPlayer() || (owner->isSummon() && owner->getMaster()->getPlayer())) {
						harmfulField = false;
					}
				}
			}

			Player* targetPlayer = creature->getPlayer();
			if (targetPlayer) {
				auto attackerPlayer = g_game.getPlayerByID(ownerId);
				if (attackerPlayer) {
					if (Combat::isProtected(attackerPlayer.get(), targetPlayer)) {
						harmfulField = false;
					}
				}
			}

			if (!harmfulField || (OTSYS_TIME() - createTime <= 5000) || creature->hasBeenAttacked(ownerId)) {
				conditionCopy->setParam(CONDITION_PARAM_OWNER, ownerId);
			}
		}

		if (conditionCopy->getType() == CONDITION_AGONY) {
			creature->addCombatCondition(std::move(conditionCopy));
		} else {
			creature->addCondition(std::move(conditionCopy));
		}
	}
}
