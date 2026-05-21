-- Server-only configuration.
-- MyAAC reads config.lua, so keep advanced Lua values and server-only toggles here.

-- Dual Wielding
-- NOTE: dualWieldingSpeedRate = 200 means dual-wielding attacks twice as fast
-- dualWieldingDamageRate = 60 means each hit deals 60% of normal damage
-- dualWieldingMode = "allweapons" allows any melee weapon to dual-wield
-- dualWieldingMode = "itemxml" requires <attribute key="dualwielding" value="true"/> on weapons
allowDualWielding = false
dualWieldingSpeedRate = 200
dualWieldingDamageRate = 60
dualWieldingMode = "allweapons"

-- Reset System
-- Enable or disable the full reset system.
resetssystem = true

-- Visual display customization
modifyDamageInK = false
modifyExpInK = false
defaultExpColor = "white"
defaultHealthDisplay = "real"

-- Loot Grouping
-- When enabled, loot from multiple kills of the same monster type within 500ms
-- is grouped into a single message: Loot of a (3x) rat: 5 gold coins, 2 cheese.
lootGroupingEnabled = true
