# KV (Key-Value) System

Sistema general-purpose de armazenamento chave-valor com persistência SQL, cache LRU em memória e suporte a escopos hierárquicos via notação de ponto.

## Por que KV em vez de Storage?

O sistema de storage tradicional do TFS (`player_storage`, `game_storage`, `account_storage`) armazena pares `(key INT, value BIGINT)` — apenas inteiros. O KV substitui isso com vantagens substanciais:

| | Storage (antigo) | KV (novo) |
|---|---|---|
| **Tipos** | Apenas inteiro (`BIGINT`) | bool, int, double, string, array, map |
| **Chaves** | `INT` numérico (ex: `30015`) | `VARCHAR(191)` nomeado (ex: `player.123.quests.annihilator.reward`) |
| **Legibilidade** | Números mágicos, exige constantes | Chaves descritivas e auto-documentadas |
| **Escopos** | Manual — chaves espalhadas | Hierárquico — `player.<guid>.quests.<name>.*` |
| **Cache** | Carregado no login, salvo no logout | LRU em memória com persistência sob demanda |
| **Performance** | Cada `setStorageValue` é imediato no map | Cache de 1M entradas, eviction automática |
| **Organização** | Uma tabela por domínio (player/game/account) | Tabela única, namespaces por prefixo |
| **Serialização** | Coluna `value BIGINT` | Blob binário TLV — suporta nested maps/arrays |

### Benefícios reais e concretos

**1. Fim dos números mágicos.** Com storage, cada dado novo exige uma constante numérica (ex: `30015`) que precisa ser documentada e mantida no `storages.lua`. Com KV, a chave é o próprio caminho: `player.123.quests.annihilator.reward` — legível por qualquer um, sem precisar consultar constantes.

```lua
-- Antes: precisa saber o que 30015 significa
player:getStorageValue(30015)

-- Depois: auto-documentado
player:questKV("annihilator"):get("reward")
```

**2. Dados complexos sem gambiarras.** Storage só aceita `BIGINT`. Para guardar string, timestamp ou múltiplos valores, era preciso codificar em inteiro ou usar múltiplas keys. KV aceita bool, string, double, arrays e maps diretamente:

```lua
-- Antes: uma key por dado, tudo inteiro, timestamp codificado
player:setStorageValue(50001, 1)                          -- completed?
player:setStorageValue(50002, os.time())                  -- completedAt
player:setStorageValue(50003, chosenRewardId)             -- escolha

-- Depois: um map com todos os dados da quest
local quest = player:questKV("annihilator")
quest:set("completed", true)
quest:set("completedAt", os.time())
quest:set("chosenReward", "magicSword")
quest:set("bossKills", 5)
quest:set("partyMembers", {"Player1", "Player2"})
```

**3. Escopos hierárquicos — organização natural.** Cada player tem seu próprio namespace isolado. Dados de quests ficam em `player.<guid>.quests.*`, configurações em `player.<guid>.settings.*`. Impossível haver colisão de chaves entre sistemas diferentes.

```
player.100.quests.annihilator.reward = true
player.100.quests.annihilator.completedAt = 1716230400
player.100.quests.demonOak.stage = 3
player.100.settings.chainSystem = true
player.100.settings.autoloot = false
```

**4. Inspeção e debug via Lua.** Com storage, inspecionar dados de um jogador exigia queries SQL manuais. Com KV, basta um script:

```lua
-- Listar todas as chaves de um jogador
local keys = player:kv():keys()
for _, key in ipairs(keys) do print(key) end

-- Ver uma quest específica
local quest = player:questKV("annihilator")
for _, key in ipairs(quest:keys()) do
    print(key, quest:get(key))
end
```

**5. Performance superior.** O cache LRU de 1 milhão de entradas mantém os dados quentes em memória. Diferente do storage que carrega TUDO no login, o KV carrega sob demanda e evicta automaticamente. Para dados acessados com frequência (ex: chain system, quests), não há query SQL — é tudo in-memory.

**6. Menos tabelas, menos complexidade.** O TFS tradicional tem 3 tabelas separadas (`player_storage`, `game_storage`, `account_storage`) + 3 sistemas de carga/save. KV é uma única tabela com um único sistema, organizado por prefixos:

```
player.<guid>.*       → dados de jogador
account.<id>.*        → dados de conta
game.*                → dados globais
events.*              → estado de eventos
```

**7. Tipagem forte no C++.** Com `ValueWrapper` e `std::variant`, o compilador garante type safety. Sem casts manuais de `int64_t` para `bool` ou `string`. O `ScopedKV::get<T>()` retorna o tipo correto ou default:

```cpp
// C++ com storage: frágil, sem tipo
auto val = getStorageValue(40001);
if (val.has_value() && val.value() == 1) { ... }  // 1 = true? quem sabe?

// C++ com KV: tipado, claro
auto settings = KVStore::getInstance().scoped("player")->scoped(fmt::format("{}", getGUID()))->scoped("settings");
auto enabled = settings->get<bool>("chainSystem");  // compilador garante bool
```

**8. Thread-safe garantido.** `KVStore` usa `std::scoped_lock` em todas as operações do cache. Operações de DB são feitas fora do lock, evitando deadlock com o `databaseLock` do MySQL. O storage tradicional não tem proteção de concorrência padronizada.

**9. Migração progressiva.** Não é necessário migrar tudo de uma vez. KV e storage coexistem. Basta substituir um sistema por vez (ex: chain system, depois quests, depois VIP, etc). As tabelas antigas continuam funcionando normalmente.

**10. Menos código boilerplate.** Cada storage key exigia: constante no `storages.lua`, `setStorageValue`/`getStorageValue` no script, e se usado em C++, declaração no `player.h` + carga no `iologindata`. Com KV: só usar.

```lua
-- Antes: 4 lugares para manter
-- 1. storages.lua:    annihilatorReward = 30015
-- 2. quest script:     getStorageValue(PlayerStorageKeys.annihilatorReward)
-- 3. C++ (se usado):   static constexpr uint32_t STORAGE = 30015;
-- 4. iologindata.cpp:   SELECT value FROM player_storage WHERE player_id = ? AND key = ?

-- Depois: 1 lugar, auto-contido
quest:set("reward", true)
```

**Exemplo da diferença em cenário real:**

```lua
-- Storage (antigo): números mágicos, sem contexto
player:setStorageValue(30015, 1)

-- KV (novo): chave descritiva, booleano nativo
player:questKV("annihilator"):set("reward", true)
```

---

## Lua API

### Global `kv`

| Método | Descrição |
|--------|-----------|
| `kv.scoped(scope)` | Retorna um `KV` userdata com escopo |
| `kv.set(key, value)` | Atribui um valor (bool, number, string, table) |
| `kv.get(key[, forceLoad])` | Obtém um valor. `forceLoad=true` ignora cache |
| `kv.keys([prefix])` | Lista chaves no escopo atual |
| `kv.remove(key)` | Remove uma chave (soft-delete) |

**Tipos suportados em `kv.set`:** `boolean`, `number` (int ou double), `string`, `table` (array-like `{1,2,3}` ou map-like `{k=v}`).

### Metatable `KV` (userdata)

Retornado por `kv.scoped()` e `player:kv()`. Mesmos métodos: `scoped`, `set`, `get`, `keys`, `remove`.

### Player

```lua
player:kv()                           -- player.<guid>.*
player:questKV("demonOak")            -- player.<guid>.quests.demonOak.*
```

`Player:questKV(name)` é um helper definido em `data/lib/core/player.lua`:

```lua
function Player.questKV(self, questName)
    return self:kv():scoped("quests"):scoped(questName)
end
```

### Criando uma Quest com KV

Antes (storage):
```lua
-- data/scripts/actions/quests/anihiChest.lua
if player:getStorageValue(PlayerStorageKeys.annihilatorReward) == 1 then
    player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "It is empty.")
    return true
end
-- ... entregar recompensa ...
player:setStorageValue(PlayerStorageKeys.annihilatorReward, 1)
```

Depois (KV):
```lua
-- data/scripts/actions/quests/anihiChest.lua
local quest = player:questKV("annihilator")

if quest:get("reward") then
    player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "It is empty.")
    return true
end
-- ... entregar recompensa ...
quest:set("reward", true)
quest:set("completedAt", os.time())
```

**Padrão completo de quest:**

```lua
local quest = player:questKV("demonOak")

-- Verificar progresso
local stage = quest:get("stage") or 0

-- Salvar estado
quest:set("stage", stage + 1)
quest:set("startedAt", os.time())

-- Múltiplos dados
quest:set("choices", {axe = true, sword = false})

-- Verificar completude
if quest:get("completed") then
    player:sendTextMessage(MESSAGE_INFO_DESCR, "You already completed this quest.")
    return true
end

-- Marcar como completo com timestamp
quest:set("completed", true)
quest:set("completedAt", os.time())

-- Contador de repetições
local kills = quest:get("demonKills") or 0
quest:set("demonKills", kills + 1)
```

### KV Global — Dados compartilhados entre sistemas

O KV global (`kv` sem player) é ideal para estado do servidor, eventos, e dependências entre quests. Diferente do storage de player que isola dados por personagem, o KV global é acessível por qualquer script.

**Exemplo: Demon Oak requer Annihilator concluída**

Este é um caso clássico de quest com pré-requisito. O jogador precisa ter completado a Annihilator antes de poder fazer a Demon Oak. Usando KV, a verificação é trivial:

```lua
-- No script da Demon Oak (checagem de acesso)
local function canEnterDemonOak(player)
    -- Verifica se o player completou a Annihilator
    local anni = player:questKV("annihilator")
    if not anni:get("reward") then
        player:sendTextMessage(MESSAGE_INFO_DESCR, 
            "You must complete the Annihilator quest first.")
        return false
    end
    
    -- Verifica se já completou a Demon Oak
    local demonOak = player:questKV("demonOak")
    if demonOak:get("completed") then
        player:sendTextMessage(MESSAGE_INFO_DESCR, 
            "You have already completed the Demon Oak quest.")
        return false
    end
    
    return true
end
```

**Exemplo: estado global de evento entre múltiplos scripts**

```lua
-- Script A: seta o evento
local rs = kv.scoped("events"):scoped("rattlesnake")
rs:set("active", true)
rs:set("startedBy", player:getName())
rs:set("startedAt", os.time())
rs:set("participants", {})

-- Script B (outro arquivo): verifica se evento está ativo
local rs = kv.scoped("events"):scoped("rattlesnake")
if rs:get("active") then
    local participants = rs:get("participants") or {}
    table.insert(participants, player:getName())
    rs:set("participants", participants)
end

-- Script C (outro arquivo): finaliza o evento
local rs = kv.scoped("events"):scoped("rattlesnake")
rs:set("active", false)
rs:set("endedAt", os.time())
rs:set("winner", player:getName())

-- God command: inspecionar estado do evento
local rs = kv.scoped("events"):scoped("rattlesnake")
for _, k in ipairs(rs:keys()) do
    player:sendTextMessage(MESSAGE_INFO_DESCR, k .. " = " .. PrettyString(rs:get(k)))
end
```

**Tabela de escopos recomendados:**

| Escopo | Uso |
|--------|-----|
| `player.<guid>.quests.<name>.*` | Dados de quest por jogador |
| `player.<guid>.settings.*` | Configurações do jogador (chain, autoloot...) |
| `player.<guid>.cooldowns.*` | Cooldowns e exhausts personalizados |
| `account.<id>.*` | Dados compartilhados entre personagens da conta |
| `events.<name>.*` | Estado de eventos globais |
| `game.*` | Configurações e estado global do servidor |
| `raids.*` | Estado e histórico de raids |

### Exemplos Gerais

```lua
-- Global
kv.set("motd", "Welcome!")
local motd = kv.get("motd")

-- Number
kv.set("maxPlayers", 100)
local max = kv.get("maxPlayers")

-- Boolean
kv.set("maintenance", true)

-- Table (array)
kv.set("topPlayers", {"Player1", "Player2", "Player3"})

-- Table (map)
kv.set("config", {rate = 2.5, enabled = true, name = "MyServer"})

-- Scoped
local events = kv.scoped("events")
events:set("doubleExp", true)
if events:get("doubleExp") then
    -- ...
end

-- Listar chaves de um escopo
local keys = events:keys()
for i, key in ipairs(keys) do
    print(key)  -- "doubleExp", ...
end

-- Remover
kv.remove("temporary")
```

---

## C++ API

### Visão Geral da Arquitetura

```
KV (abstract interface)
 └── KVStore (LRU cache + SQL persistence)
      ├── set/get/keys/remove — in-memory, thread-safe via std::mutex
      ├── load/loadPrefix/save/saveAll — MySQL via Database singleton
      ├── LRU eviction — MAX_SIZE = 1.000.000 entries
      └── ScopedKV — prefix decorator, non-owning, add dots to keys
```

1. **KVStore** é um singleton (`getInstance()`). Todas operações passam por ele.
2. Cada chave é uma string com notação de ponto: `player.123.quests.annihilator.completed`.
3. **ScopedKV** é um wrapper que automaticamente prefixa chaves:
   - `kv.scoped("player").scoped("123")` → toda key ganha prefixo `player.123.`
   - Internamente: `scoped->set("quests.annihilator.completed", true)` → key real `player.123.quests.annihilator.completed`
4. Cache LRU: até 1M entradas em `std::unordered_map` + `std::list` para ordenação.
5. Ao exceder o limite, a entrada menos recentemente usada é evictada e persistida no banco.
6. Thread-safe: `std::scoped_lock` em todas as operações do cache. Operações de DB são feitas fora do lock (evita deadlock com o `databaseLock`).

### Acesso Global

```cpp
#include "kv/kv.hpp"

KVStore::getInstance()  // Singleton — sempre disponível após boot
```

### ValueWrapper

Wrapper type-erased com 6 tipos via `std::variant`:

| Tipo C++ | Tipo KV | Exemplo |
|----------|---------|---------|
| `StringType` (`std::string`) | string | `ValueWrapper("hello")` |
| `BooleanType` (`bool`) | bool | `ValueWrapper(true)` |
| `IntType` (`int32_t`) | int | `ValueWrapper(42)` |
| `DoubleType` (`double`) | double | `ValueWrapper(3.14)` |
| `ArrayType` (`std::vector<ValueWrapper>`) | array | `ValueWrapper(ArrayType{1, 2, 3})` |
| `MapType` (`std::unordered_map<string, shared_ptr<ValueWrapper>>`) | map | `ValueWrapper(MapType{{"k", v}})` |

```cpp
// Construção implícita
ValueWrapper val(42);        // int
ValueWrapper val("hello");   // string
ValueWrapper val(true);      // bool
ValueWrapper val(3.14);      // double

// Typed get
auto str = val.get<StringType>();
auto num = val.get<IntType>();
auto arr = val.get<ArrayType>();

// Variant
const ValueVariant &var = val.getVariant();
std::visit([](const auto &v) { /* ... */ }, var);

// Number genérico
double d = val.getNumber();  // funciona com IntType e DoubleType
```

### ScopedKV — Template get tipado

```cpp
auto scoped = KVStore::getInstance().scoped("events");
auto enabled = scoped->get<bool>("doubleExp");    // retorna false se ausente
auto rate    = scoped->get<int>("rate");          // retorna 0 se ausente
```

### Exemplos Práticos em C++

**Dado global de servidor:**
```cpp
// Set
KVStore::getInstance().set("welcomeMessage", ValueWrapper("Bem-vindo ao servidor!"));

// Get
auto msg = KVStore::getInstance().get("welcomeMessage");
if (msg.has_value()) {
    std::string text = msg->get<StringType>();
}
```

**Dado scoped de player (ex: chain system):**
```cpp
// Em player.cpp
bool Player::checkChainSystem() const {
    if (!ConfigManager::getBoolean(ConfigManager::CHAIN_SYSTEM_ENABLED)) {
        return false;
    }

    // Acessa player.<guid>.settings.chainSystem
    auto playerKV = KVStore::getInstance()
        .scoped("player")->scoped(fmt::format("{}", getGUID()));
    auto settings = playerKV->scoped("settings");
    auto value = settings->get("chainSystem");

    return value.has_value() && value->get<BooleanType>();
}
```

**Leitura de array:**
```cpp
auto opt = KVStore::getInstance().get("bannedIPs");
if (opt.has_value()) {
    auto arr = opt->get<ArrayType>();
    for (const auto &ip : arr) {
        std::string ipStr = ip.get<StringType>();
    }
}
```

**Leitura de map:**
```cpp
auto opt = KVStore::getInstance().get("serverRates");
if (opt.has_value()) {
    auto map = opt->get<MapType>();
    for (const auto &[key, val] : map) {
        double rate = val->get<DoubleType>();
    }
}
```

**Persistência manual:**
```cpp
KVStore::getInstance().save(key, value);    // Salva uma chave
KVStore::getInstance().saveAll();           // Salva TODAS (chamado pelo SaveManager)
KVStore::getInstance().load(key);           // Carrega do banco (ignora cache)
KVStore::getInstance().loadPrefix("player."); // Lista chaves por prefixo
```

### Integração no Save

O `SaveManager::saveAll()` (em `src/save_manager.cpp`) chama automaticamente:

```cpp
if (!KVStore::getInstance().saveAll()) {
    LOG_ERROR("[SaveManager] Failed to save KV store.");
}
```

Isso persiste todas as entradas cacheadas em uma transação batch no banco.

---

## Database

Tabela `kv_store`:

```sql
CREATE TABLE IF NOT EXISTS `kv_store` (
  `key_name`   varchar(191) NOT NULL,
  `timestamp`  bigint NOT NULL,
  `value`      longblob NOT NULL,
  PRIMARY KEY (`key_name`)
) ENGINE=InnoDB DEFAULT CHARACTER SET=utf8;
```

As chaves usam notação de ponto para hierarquia: `player.123.quests.demonOak.completed`.  
Os valores são serializados em formato binário TLV (Type-Length-Value) — 6 tipos suportados com nesting arbitrário.

### Formato TLV

| Tipo | Tag | Payload |
|------|-----|---------|
| Null | `0x00` | — |
| Bool | `0x01` | 1 byte (0/1) |
| Int | `0x02` | 4 bytes LE |
| Double | `0x03` | 8 bytes LE |
| String | `0x04` | 4 bytes LE (len) + UTF-8 |
| Array | `0x05` | 4 bytes LE (count) + items... |
| Map | `0x06` | 4 bytes LE (count) + [4 bytes LE keyLen + key + value]... |

Sem dependência de protobuf. Serialização/deserialização em `value_wrapper.cpp`.

---

## Migrando de Storage para KV

### Passo a passo

1. **Identifique** a storage key usada (ex: `PlayerStorageKeys.annihilatorReward = 30015`).

2. **Escolha** o escopo KV adequado:
   - Dado de player → `player:kv()` ou `player:questKV("name")`
   - Dado global do servidor → `kv` (global)
   - Dado de account → `kv.scoped("account").scoped(id)`

3. **Substitua** `getStorageValue` → `kv:get()` e `setStorageValue` → `kv:set()`.

4. **Remova** a constante do `PlayerStorageKeys`/`GlobalStorageKeys` se não for mais referenciada.

5. Se houver código C++ lendo o storage, converta para `KVStore::getInstance()`.

### Exemplo real: Chain System

**Antes** (`chain_system.lua`):
```lua
local chainStorage = 40001
player:setStorageValue(chainStorage, 1)
local state = player:getStorageValue(chainStorage)
```

**Depois**:
```lua
local settings = player:kv():scoped("settings")
settings:set("chainSystem", true)
local enabled = settings:get("chainSystem")
```

**Antes** (`player.cpp`):
```cpp
static constexpr uint32_t CHAIN_SYSTEM_STORAGE = 40001;
auto value = getStorageValue(CHAIN_SYSTEM_STORAGE);
return value.has_value() && value.value() == 1;
```

**Depois**:
```cpp
auto playerKV = KVStore::getInstance().scoped("player")->scoped(fmt::format("{}", getGUID()));
auto settings = playerKV->scoped("settings");
auto chainValue = settings->get("chainSystem");
return chainValue.has_value() && chainValue->get<BooleanType>();
```

### Exemplo real: Annihilator Quest

**Antes** (`anihiChest.lua`):
```lua
if player:getStorageValue(PlayerStorageKeys.annihilatorReward) == 1 then
    player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "It is empty.")
    return true
end
-- ...
player:setStorageValue(PlayerStorageKeys.annihilatorReward, 1)
```

**Depois**:
```lua
local quest = player:questKV("annihilator")
if quest:get("reward") then
    player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "It is empty.")
    return true
end
-- ...
quest:set("reward", true)
quest:set("completedAt", os.time())
```

---

## Arquivos

| Arquivo | Descrição |
|---------|-----------|
| `src/kv/kv.hpp` | Interface `KV`, `KVStore`, `ScopedKV` |
| `src/kv/kv.cpp` | Implementação completa (cache + SQL) |
| `src/kv/value_wrapper.hpp` | `ValueWrapper` type-erased (6 tipos) |
| `src/kv/value_wrapper.cpp` | Serialização TLV binária |
| `src/database.h/.cpp` | `DBInsert::upsert()` adicionado |
| `src/luascript.cpp` | Bindings Lua (`kv` table, `KV` metatable) |
| `src/luaplayer.cpp` | `player:kv()` |
| `src/save_manager.cpp` | KV save no server save |
| `data/lib/core/player.lua` | Helper `Player:questKV(name)` |
| `data/migrations/41.lua` | Migration: cria tabela `kv_store` |
| `schema.sql` | Tabela `kv_store` |
