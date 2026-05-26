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

-- Chain System
-- Chain system allows attacks to bounce from target to nearby targets
toggleChainSystem = true
-- Delay in milliseconds between each chain hop
combatChainDelay = 50
-- Maximum number of chain targets for weapon chain
combatChainTargets = 5
-- Weapon chain damage formulas (multiplier based on weapon skill)
combatChainSkillFormulaAxe = 0.9
combatChainSkillFormulaClub = 0.7
combatChainSkillFormulaSword = 1.1
combatChainSkillFormulaFist = 1.0
combatChainSkillFormulaDistance = 0.9
combatChainSkillFormulaWandsAndRods = 1.0

-- Cleave System
cleavesystem = true

-- Visual display customization
modifyDamageInK = false
modifyExpInK = false
defaultExpColor = "white"
defaultHealthDisplay = "real"

-- Raid spawn file generation
-- When a raid in data/raids/raids.xml has spawnFile="file.xml", successful
-- singlespawn/areaspawn monsters are exported to data/raids/file.xml.
-- spawntime value written to each generated <monster> node, in seconds.
-- Monsters created within this radius on the same floor are grouped into the same spawn block using x/y offsets.
-- Direction values: 0 = north, 1 = east, 2 = south, 3 = west.
raidSpawnFileEnabled = true
raidSpawnFileDirectory = "data/raids"
raidSpawnFileSpawntime = 60
raidSpawnFileRadius = 1
raidSpawnFileDirection = 2
