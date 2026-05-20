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
| **God commands** | Sem inspeção nativa | `kv.get()` / `kv.keys()` direto via script |

**Exemplo da diferença:**

```lua
-- Storage (antigo): número mágico, só inteiro
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
