# KV (Key-Value) System

Sistema general-purpose de armazenamento chave-valor com persistência SQL, cache LRU em memória e suporte a escopos hierárquicos via notação de ponto.

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
Os valores são serializados em formato binário TLV (Type-Length-Value).

## Lua API

### Global `kv`

| Método | Descrição |
|--------|-----------|
| `kv.scoped(scope)` | Retorna um escopo scoped `KV` userdata |
| `kv.set(key, value)` | Atribui um valor (bool, number, string, table) |
| `kv.get(key[, forceLoad])` | Obtém um valor. `forceLoad=true` ignora cache |
| `kv.keys([prefix])` | Lista chaves no escopo atual |
| `kv.remove(key)` | Remove uma chave (soft-delete) |

**Tipos suportados em `kv.set`:** `boolean`, `number` (int ou double), `string`, `table` (array-like ou map-like).

### Metatable `KV` (userdata)

Retornado por `kv.scoped()` e `player:kv()`. Mesmos métodos: `scoped`, `set`, `get`, `keys`, `remove`.

### Player

```lua
player:kv()  -- Escopo automático: player.<guid>.*
```

#### Padrão de uso para quests

```lua
function Player:questKV(questName)
    return self:kv():scoped("quests"):scoped(questName)
end
```

### Exemplos

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

-- Player quest
local quest = player:kv():scoped("quests"):scoped("annihilator")
quest:set("completed", true)
quest:set("completedAt", os.time())

-- Listar chaves
local keys = kv.keys("events.")  -- prefixo opcional
for i, key in ipairs(keys) do
    print(key)
end

-- Remover
kv.remove("temporary")
```

## C++ API

### Include

```cpp
#include "kv/kv.hpp"
```

### Global access

```cpp
KVStore::getInstance()  // Singleton
```

### Interface (`KV`)

```cpp
class KV {
    virtual void set(const std::string &key, const ValueWrapper &value) = 0;
    virtual std::optional<ValueWrapper> get(const std::string &key, bool forceLoad = false) = 0;
    virtual std::shared_ptr<KV> scoped(const std::string &scope) = 0;
    virtual std::unordered_set<std::string> keys(const std::string &prefix = "") = 0;
    void remove(const std::string &key);
    virtual bool saveAll();
    virtual void flush();
};
```

### ValueWrapper

Wrapper type-erased com 6 tipos: `StringType`, `BooleanType`, `IntType` (int32), `DoubleType`, `ArrayType`, `MapType`.

```cpp
ValueWrapper val(42);                          // int
ValueWrapper val("hello");                     // string
ValueWrapper val(true);                        // bool
ValueWrapper val(3.14);                        // double
ValueWrapper val(ArrayType{1, 2, 3});          // array
ValueWrapper val(MapType{{"key", ...}});        // map

// Typed get
auto str = val.get<StringType>();
auto num = val.get<IntType>();
auto arr = val.get<ArrayType>();

// Variant access
const ValueVariant &var = val.getVariant();
std::visit([](const auto &v) { ... }, var);
```

### ScopedKV

Template `get<T>` para acesso tipado direto:

```cpp
auto scoped = KVStore::getInstance().scoped("events");
scoped->get<bool>("doubleExp");
scoped->get<int>("rate");
```

### Persistence

```cpp
KVStore::getInstance().load(key);       // Load from DB
KVStore::getInstance().save(key, val);  // Save to DB
KVStore::getInstance().saveAll();       // Save ALL cached (called during server save)
KVStore::getInstance().loadPrefix("player."); // Load keys matching prefix
```

### Exemplos C++

```cpp
// Set global
KVStore::getInstance().set("serverName", ValueWrapper("MyServer"));

// Get global
auto opt = KVStore::getInstance().get("serverName");
if (opt.has_value()) {
    std::string name = opt->get<StringType>();
}

// Player-scoped
auto playerKV = KVStore::getInstance().scoped("player")->scoped(std::to_string(player->getGUID()));
playerKV->set("quests.annihilator.completed", ValueWrapper(true));
```

## Arquitetura

```
KV (abstract interface)
 └── KVStore (LRU cache + virtual persistence hooks)
      ├── set/get/keys/remove (in-memory, thread-safe)
      ├── load/loadPrefix/save/saveAll (SQL)
      └── LRU eviction (MAX_SIZE = 1,000,000 entries)
           └── ScopedKV (prefix decorator, non-owning)
```

- **Cache LRU**: Até 1 milhão de entradas em memória. Excedido, a menos recentemente usada é evictada e persistida.
- **Thread-safe**: Todas operações usam `std::scoped_lock` no `mutex_`.
- **Serialização**: Formato binário TLV próprio (sem dependência de protobuf).
- **Save integrado**: `SaveManager::saveAll()` chama `KVStore::getInstance().saveAll()`.

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
| `data/migrations/41.lua` | Migration: cria tabela `kv_store` |
| `schema.sql` | Tabela `kv_store` |
