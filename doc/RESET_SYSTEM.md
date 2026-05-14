# Reset System — TFS 1.8

## Visao Geral

O Reset System permite que jogadores reiniciem seu nivel (voltando a um nivel base configuravel) em troca de **bonus permanentes e cumulativos** de dano, defesa, experiencia, cura, HP, mana e velocidade de ataque. Cada reset aumenta progressivamente os requisitos de nivel e reduz o ganho de XP (via `stagesresets.xml`), tornando o progresso mais desafiador.

Os bonus de dano, defesa e cura sao aplicados **diretamente no C++** dentro de `combatChangeHealth()` — sem overhead por player, independente do numero de players online.

### Novidade: Spelltype (Formula por Spell)

Cada spell pode definir seu proprio bonus de dano de reset via `combat:setResetDamageMultiplier(valor)`. Quando definido (`>= 0`), substitui o bonus global do jogador para aquela spell. Isso permite balancear individualmente quais spells recebem o bonus de reset.

---

## Configuracao Rapida

### 1. Ativar/Desativar — `config.lua.dist`

```lua
resetssystem = false   -- true = ativa o sistema completo de resets
```

Quando `false`, todo o sistema fica inerte (zero custo de CPU).

### 2. Bonus por Vocacao — `data/scripts/resetsystem/configbonus.lua`

```lua
ResetBonusConfig = {
    resetLevel    = 10000,  -- nivel apos o reset
    maxResets     = 0,      -- 0 = ilimitado
    resetCooldown = 0,      -- segundos entre resets (0 = sem cooldown)

    damage = { enabled = true, [0] = { steps = {...}, default = 0.1 } },
    defense = { enabled = true, [0] = { steps = {...}, default = 0.1 } },
    experience = { enabled = true, [0] = { steps = {...}, default = 0.1 } },
    healing = { enabled = true, [0] = { steps = {...}, default = 0.05 } },
    attackSpeed = { enabled = true, [0] = { steps = {...}, default = 2 } },
    hp = { enabled = true, bonusMode = "percent", [0] = { ranges = {...} } },
    mana = { enabled = true, bonusMode = "percent", [0] = { ranges = {...} } },
    manaPotion = { enabled = true, [0] = { ranges = {...} } },
    manaSpell = { enabled = true, [0] = { ranges = {...} } },
}
```

`[0]` = VOCATION_ALL (fallback para todas as vocacoes). Adicione `[1]` a `[8]` para bonus especificos por vocacao.

### 3. Requisitos de Nivel — `data/scripts/resetsystem/tabelaresets.lua`

```lua
ResetLevelTable = {
    useFormula = true,
    formula = { baseLevel = 65000, levelPerReset = 5000 },
    -- ou use a tabela manual descomentando useFormula = false
}
```

### 4. XP por Faixa de Reset — `data/XML/stagesresets.xml`

```xml
<stagesresets>
    <stage minreset="0"   maxreset="0"   multiplier="1.0"  />
    <stage minreset="1"   maxreset="5"   multiplier="0.85" />
    <stage minreset="151" maxreset="0"   multiplier="0.10" />
</stagesresets>
```

---

## Comandos

| Comando | Descricao |
|---------|-----------|
| `!reset` | O jogador reseta a si mesmo |
| `/resetplayer <nome>` | GM reseta outro jogador |
| `!resetinfo` | Mostra todos os bonus atuais do jogador |

---

## API Lua — Player

### Contador de Resets

```lua
player:getResetCount() -> number
player:setResetCount(count)  -- nao reaplica bonus, chame applyBonuses() depois
player:addResetCount(amount)  -- default = 1
```

### Bonus Armazenados no Player (campos C++)

```lua
player:getResetDamageBonus()          -- % de dano extra (PvE)
player:setResetDamageBonus(pct)

player:getResetDefenseBonus()         -- % de reducao de dano (PvE, cap 90%)
player:setResetDefenseBonus(pct)

player:getResetHealingBonus()         -- % de amplificacao de cura (HP + mana)
player:setResetHealingBonus(pct)

player:getResetAttackSpeedBonus()     -- ms subtraidos do intervalo de ataque
player:setResetAttackSpeedBonus(ms)

player:getResetHpBonus()              -- HP flat adicionado ao getMaxHealth()
player:setResetHpBonus(flat)

player:getResetManaBonus()            -- Mana flat adicionado ao getMaxMana()
player:setResetManaBonus(flat)

player:getResetManaPotionBonus()      -- % bonus de mana de potions/itens (sem caster)
player:setResetManaPotionBonus(pct)

player:getResetManaSpellBonus()       -- % bonus de mana de spells (com caster)
player:setResetManaSpellBonus(pct)
```

### Funcoes de Configuracao

```lua
ResetBonusConfig.getTotalBonus(bonusType, resetCount, vocationId) -> float
ResetBonusConfig.applyBonuses(player)  -- empurra todos os bonus para o C++
ResetStages.getMultiplier(resetCount)  -- multiplicador XP por faixa de resets
```

---

## API Lua — Spelltype (Formula por Spell)

```lua
-- Define formula especifica de bonus de dano de reset para esta spell
spell:resetDamageFormula("resets * 1.5 + level * 0.02")

-- No onCastSpell, avalie a formula e aplique ao combat:
local combat = Combat()
-- ... config ...
if spell:resetDamageFormula() ~= "" then
    -- Avalie a formula (exemplo: bonus = resets * 1.5)
    local bonus = player:getResetCount() * 1.5
    combat:setResetDamageMultiplier(bonus)  -- substitui o bonus global
end
combat:execute(player, variant)
```

Quando `setResetDamageMultiplier(valor)` e chamado com `valor >= 0`, o **bonus global de dano do jogador e ignorado** e o valor fornecido e usado diretamente como percentual de bonus para aquela spell.

### Exemplo completo de spell com spelltype

```lua
local combat = Combat()
combat:setParameter(COMBAT_PARAM_TYPE, COMBAT_PHYSICALDAMAGE)
combat:setParameter(COMBAT_PARAM_EFFECT, CONST_ME_HITAREA)
combat:setFormula(COMBAT_FORMULA_LEVELMAGIC, -1.0, -100, -1.0, -200)

local spell = Spell("instant")
spell:name("Exori Vis Custom")
spell:words("exori vis")
spell:group("attack")
spell:level(100)
spell:mana(150)
spell:resetDamageFormula("resets * 1.5")  -- formula customizada

function spell.onCastSpell(creature, variant)
    local player = creature:getPlayer()
    if not player then return false end

    -- Avalia a formula (resets * 1.5 = bonus %)
    if spell:resetDamageFormula() == "resets * 1.5" then
        local bonus = player:getResetCount() * 1.5
        combat:setResetDamageMultiplier(bonus)
    end

    return combat:execute(creature, variant)
end
spell:register()
```

---

## API Lua — MoveEvent (equip de itens)

```lua
local weapon = MoveEvent()
weapon:type("equip")
weapon:resets(10)  -- exige 10 resets para equipar

function weapon.onEquip(player, item, slot) return true end
weapon:register()
```

---

## items.xml — Atributo `reqresets`

```xml
<item id="12345" name="Sword of Resets">
    <attribute key="attack"     value="80" />
    <attribute key="weapontype" value="sword" />
    <attribute key="level"      value="8000" />
    <attribute key="reqresets"  value="10" />
</item>
```

---

## AID Range — Portas e Pisos de Reset (AID 150001–150999)

Defina o **ActionID** no mapa (Remere's RME) como `150000 + resets_exigidos`:

| AID no mapa | Exige |
|-------------|-------|
| 150001 | 1 reset |
| 150010 | 10 resets |
| 150100 | 100 resets |

- Portas: o script `reset_door.lua` gerencia abertura/fechamento automaticamente
- Pisos/Tiles: o script `reset_tile.lua` bloqueia jogadores sem resets suficientes
- Portas fecham automaticamente via `closing_door.lua`

---

## Como os Bonus sao Aplicados — C++ (`game.cpp`)

Os bonus de dano, defesa, cura e mana **nao usam eventos Lua por jogador**. Sao aplicados diretamente nas funcoes de combate do engine:

```text
combatChangeHealth()
├── HEALING branch
│   ├── applyResetSystemBonuses()   ← HEALING BONUS (targetPlayer->resetHealingBonus)
│   └── target->gainHealth()
└── DAMAGE branch
    ├── applyResetSystemBonuses()   ← DAMAGE BONUS  (attackerPlayer->resetDamageBonus)
    │                                  DEFENSE BONUS (targetPlayer->resetDefenseBonus)
    └── damage.primary.value = abs(...)

combatChangeMana()
└── MANA RESTORATION branch (manaChange > 0)
    ├── resetManaSpellBonus  (se ha caster: spells)
    └── resetManaPotionBonus (se nao ha caster: potions/itens)
```

| Bonus | Condicao | Restricao |
|-------|----------|-----------|
| Damage | `attackerPlayer` && `!targetPlayer` | PvE apenas |
| Defense | `!attackerPlayer` && `targetPlayer` | PvE apenas, cap 90% |
| Healing (HP + Mana) | `targetPlayer` | PvP incluso |

---

## Eventos e Callbacks Automaticos

### Login — `ResetSystemOnLogin`

```lua
-- data/scripts/resetsystem/04_login_reset.lua
local resetOnLogin = CreatureEvent("ResetSystemOnLogin")
function resetOnLogin.onLogin(player)
    ResetBonusConfig.applyBonuses(player)
    return true
end
resetOnLogin:register()
```

### onGainExperience — bonus de XP + stagesresets

Integrado em `data/events/scripts/player.lua`:

```lua
if ResetBonusConfig then
    local resetXpBonus = ResetBonusConfig.getTotalBonus("experience", ...)
    finalExp = finalExp * (1 + resetXpBonus / 100)
end
if ResetStages then
    finalExp = finalExp * ResetStages.getMultiplier(self:getResetCount())
end
```

---

## Estrutura de Bonus — `steps` vs `ranges`

### Sintaxe `steps` (bonus por reset individual)

```lua
damage = {
    enabled = true,
    [0] = {
        steps = {
            { reset = 1, bonus = 10.0 },  -- 1o reset: +10%
            { reset = 2, bonus =  5.0 },  -- 2o reset: +5% (total 15%)
            { reset = 3, bonus =  5.0 },  -- 3o reset: +5% (total 20%)
        },
        default = 0.1,  -- 4o+ em diante: +0.1% por reset
    },
}
```

### Sintaxe `ranges` (bonus por faixa de resets)

```lua
damage = {
    enabled = true,
    [0] = {
        ranges = {
            { minReset =   1, maxReset =   5, bonus = 10.0 },
            { minReset =   6, maxReset =  20, bonus =  5.0 },
            { minReset =  21, maxReset = 100, bonus =  1.0 },
            { minReset = 101, maxReset =   0, bonus =  0.1 },  -- 0 = sem limite
        },
    },
}
```

`maxReset = 0` na range = sem limite superior. `steps` tem prioridade sobre `ranges`.

---

## IDs de Vocacao

| ID | Vocacao |
|----|---------|
| 0 | VOCATION_ALL (fallback) |
| 1 | Sorcerer |
| 2 | Druid |
| 3 | Paladin |
| 4 | Knight |
| 5 | Master Sorcerer |
| 6 | Elder Druid |
| 7 | Royal Paladin |
| 8 | Elite Knight |

---

## Arquitetura — Arquivos Modificados

### C++ (Engine)

| Arquivo | Descricao |
|---------|-----------|
| `src/player.h` | Campos: `reset`, `resetAttackSpeedBonus`, `resetDamageBonus`, `resetDefenseBonus`, `resetHealingBonus`, `resetHpBonus`, `resetManaBonus`, `resetManaPotionBonus`, `resetManaSpellBonus` (todos float/int32) + getters/setters + `getDisplayName()` |
| `src/player.cpp` | `getMaxHealth()` + round(resetHpBonus), `getMaxMana()` + round(resetManaBonus), `getAttackSpeed()` - resetAttackSpeedBonus, `getDescription()` mostra resets |
| `src/game.h` | Declaracao de `applyResetSystemBonuses()` |
| `src/game.cpp` | `applyResetSystemBonuses()` (HP em combatChangeHealth + mana em combatChangeMana). Suporte a spelltype via `damage.spellResetMultiplier` |
| `src/luaplayer.cpp` | 18 metodos Lua: get/set para todos os campos de reset |
| `src/luamoveevent.cpp` | `moveevent:resets(N)` |
| `src/luaspells.cpp` | `spell:resetDamageFormula(str)` |
| `src/spells.h` | Campo `resetDamageFormula` no Spell |
| `src/enums.h` | `spellResetMultiplier` no CombatDamage, `COMBAT_PARAM_RESET_DAMAGE_MULTIPLIER` |
| `src/combat.h` | `resetDamageMultiplier` no CombatParams, getter/setter no Combat |
| `src/combat.cpp` | Passa multiplier para damage antes de combatChangeHealth |
| `src/luacombat.cpp` | `combat:setResetDamageMultiplier(value)` |
| `src/movement.h/.cpp` | `reqResets` no MoveEvent, check em `EquipItem()` |
| `src/configmanager.h/.cpp` | `resetssystem` toggle (boolean RESET_SYSTEM_ENABLED) |
| `src/const.h` | `WIELDINFO_RESETS = 1 << 4` |
| `src/protocolgame.cpp` | `getDisplayName()` no sendCreatureSay e AddCreature |
| `src/items.h` | `minReqReset` no ItemType |
| `src/items.cpp` | Parse de `reqresets` no items.xml, WIELDINFO_RESETS |
| `src/iologindata.cpp` | Carrega/Salva `reset` do DB (removeu duplicata) |
| `src/luascript.cpp` | Registra enums `WIELDINFO_RESETS` e `COMBAT_PARAM_RESET_DAMAGE_MULTIPLIER` |

### Lua (Scripts)

| Arquivo | Descricao |
|---------|-----------|
| `data/scripts/resetsystem/tabelaresets.lua` | Requisitos de nivel VIP/Free |
| `data/scripts/resetsystem/configbonus.lua` | Configuracao de bonus + `getTotalBonus()` + `applyBonuses()` |
| `data/scripts/resetsystem/stagesresets.lua` | Parser do XML + `getMultiplier()` |
| `data/scripts/resetsystem/01_reset_core.lua` | `doPlayerReset()` — logica central |
| `data/scripts/resetsystem/02_talkaction_reset.lua` | Talkactions `!reset` + `/resetplayer` |
| `data/scripts/resetsystem/03_talkaction_resetinfo.lua` | Talkaction `!resetinfo` |
| `data/scripts/resetsystem/04_login_reset.lua` | CreatureEvent `ResetSystemOnLogin` |
| `data/XML/stagesresets.xml` | Multiplicadores de XP por faixa de resets |
| `data/events/scripts/player.lua` | `onGainExperience` com bonus XP + stagesresets |
| `data/scripts/actions/doors/reset_door.lua` | Action AID 150001–150999 para portas |
| `data/scripts/movements/reset_tile.lua` | MoveEvent AID 150001–150999 para pisos |
| `data/scripts/movements/closing_door.lua` | Adaptado para portas de reset no step-in |
| `data/migrations/40.lua` | Migracao DB (verifica/garante coluna `reset`) |
| `config.lua.dist` | Toggle `resetssystem = false` |

### Banco de Dados

```sql
`reset` int(11) NOT NULL DEFAULT 0
```

Coluna ja existente no `schema.sql` desde a implementacao anterior do sistema de reset.
