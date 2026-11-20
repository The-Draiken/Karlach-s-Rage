local MOD_PREFIX = "[KarlachsRage]"
local KARLACH = "S_Player_Karlach_2c76687d-93a2-477b-8b18-8a14b549304c"

local FORCE_STATUS = "KAR_RAGE_STAGE_Force"
local END_RAGE_SPELL = "Shout_EndRage"

-- If Karlach has this, DO NOT auto-end rage on Fireball_KAR, and DO NOT item-destroy elsewhere
local INFERNAL_FURY_STATUS = "ORI_KARLACH_INFERNAL_FURY"

-- Your custom fireball spell (must be usable while raging if you want to cast it during Rage)
local FIREBALL_SPELL = "Projectile_Fireball_KAR"

local state = {
  forceActive = false,
}

local function log(msg)
  Ext.Utils.Print(string.format("%s %s", MOD_PREFIX, msg))
end

local function hasStatus(char, status)
  local ok, v = pcall(function()
    return Osi.HasActiveStatus(char, status)
  end)
  return ok and v == 1
end

local function hasForce()
  return hasStatus(KARLACH, FORCE_STATUS)
end

local function hasInfernalFury()
  return hasStatus(KARLACH, INFERNAL_FURY_STATUS)
end

local function addSpell()
  -- Be tolerant of signature differences across SE builds
  if Osi.AddSpell then
    pcall(Osi.AddSpell, KARLACH, FIREBALL_SPELL, 0, 0)
    pcall(Osi.AddSpell, KARLACH, FIREBALL_SPELL, 1, 0)
    pcall(Osi.AddSpell, KARLACH, FIREBALL_SPELL, 0)
    pcall(Osi.AddSpell, KARLACH, FIREBALL_SPELL)
  elseif Osi.CharacterAddSpell then
    pcall(Osi.CharacterAddSpell, KARLACH, FIREBALL_SPELL)
  end
end

local function removeSpell()
  if Osi.RemoveSpell then
    pcall(Osi.RemoveSpell, KARLACH, FIREBALL_SPELL)
  elseif Osi.CharacterRemoveSpell then
    pcall(Osi.CharacterRemoveSpell, KARLACH, FIREBALL_SPELL)
  end
end

local function clearAll()
  state.forceActive = false
  removeSpell()
  log("Cleared Fireball spell")
end

local function tryForceEndRage()
  -- Casting EndRage is the cleanest way because your existing EndRage cleanup logic triggers.
  local ok = false

  if Osi.UseSpell then
    ok = pcall(Osi.UseSpell, KARLACH, END_RAGE_SPELL, KARLACH)
  end
  if (not ok) and Osi.CharacterUseSpell then
    ok = pcall(Osi.CharacterUseSpell, KARLACH, END_RAGE_SPELL, KARLACH)
  end
  if (not ok) and Osi.CastSpell then
    ok = pcall(Osi.CastSpell, KARLACH, END_RAGE_SPELL, KARLACH)
  end
  if (not ok) and Osi.CharacterCastSpell then
    ok = pcall(Osi.CharacterCastSpell, KARLACH, END_RAGE_SPELL, KARLACH)
  end

  if not ok then
    log("WARN: Could not auto-cast Shout_EndRage (no supported Osiris function succeeded).")
  end
end

-- When FORCE starts, grant the spell immediately.
Ext.Osiris.RegisterListener("StatusApplied", 4, "after", function(target, status, _, _)
  if target ~= KARLACH then return end
  if status ~= FORCE_STATUS then return end

  state.forceActive = true
  log("FORCE applied -> granting Fireball_KAR")
  addSpell()
end)

-- When FORCE ends (or rage cleanup removes it), remove the spell.
Ext.Osiris.RegisterListener("StatusRemoved", 4, "after", function(target, status, _, _)
  if target ~= KARLACH then return end
  if status ~= FORCE_STATUS then return end

  log("FORCE removed -> clearing Fireball_KAR")
  clearAll()
end)

-- When Karlach uses End Rage, clear the spell (and stop any tracking).
Ext.Osiris.RegisterListener("UsingSpellOnTarget", 6, "after", function(caster, target, spell, _, _, _)
  if caster ~= KARLACH then return end
  if spell ~= END_RAGE_SPELL then return end

  log("End rage -> clearing Fireball_KAR")
  clearAll()
end)

-- If Karlach casts Fireball_KAR, immediately end Rage so all your statuses/passives are removed.
-- BUT: if she has ORI_KARLACH_INFERNAL_FURY, do NOT end rage.
Ext.Osiris.RegisterListener("UsingSpell", 5, "after", function(caster, spell, spellType, _, _)
  if caster ~= KARLACH then return end
  if spell ~= FIREBALL_SPELL then return end

  -- Optional: require FORCE to be active; remove this guard if you want ANY cast to end rage.
  if not state.forceActive then return end
  if not hasForce() then return end

  if hasInfernalFury() then
    log("Infernal Fury active -> Fireball_KAR will NOT end rage")
    return
  end

  log("Projectile_Fireball_KAR used -> forcing End Rage")

  -- Small delay avoids edge cases where ending rage might interfere with the projectile spawning.
  Ext.Timer.WaitFor(1, tryForceEndRage)
end)