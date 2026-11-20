-- Karlach Rage stage chain (TB = true turns, RT = real seconds)
-- V32+ SE note: Osi.ApplyStatus duration is always seconds even in TB, and
-- CharacterApplyStatus is unreliable/absent.  We apply stages with -1 (infinite)
-- duration in TB mode and drive chaining via manual turn counting on Karlach's
-- TurnStarted events.  The force-destroy loop also uses manual turn counting.

local MOD_PREFIX = "[KarlachsRage]"
local KARLACH = "S_Player_Karlach_2c76687d-93a2-477b-8b18-8a14b549304c"

-- If Karlach has this, she should NOT undergo item destruction, and Fireball should NOT end rage.
local INFERNAL_FURY_STATUS = "ORI_KARLACH_INFERNAL_FURY"

local STAGE = {
  FIRE    = "KAR_RAGE_STAGE_FIRE",
  BLUNT   = "KAR_RAGE_STAGE_BLUNT",
  SLASH   = "KAR_RAGE_STAGE_SLASH",
  PIERCE  = "KAR_RAGE_STAGE_PIERCE",
  THUNDER = "KAR_RAGE_STAGE_THUNDER",
  FORCE   = "KAR_RAGE_STAGE_Force",
}

-- Internal helper status to pulse "destroy all equipped items" every 2 turns while FORCE is active (TB only)
local FORCE_LOOP = "KAR_RAGE_FORCE_DESTROY_LOOP"

-- Extra effects requested
local BURNING_AURA = "LOW_HOH_BOAR_BURNING_AURA"
-- Area aura: applies BURNING to everyone within 2m of Karlach (not herself). Defined in Status_BOOST.txt
local FIRE_AURA = "KAR_RAGE_FIRE_AURA"
local DOWNED_STATUS = "DOWNED"

local NEXT_STAGE = {
  [STAGE.FIRE]    = STAGE.BLUNT,
  [STAGE.BLUNT]   = STAGE.SLASH,
  [STAGE.SLASH]   = STAGE.PIERCE,
  [STAGE.PIERCE]  = STAGE.THUNDER,
  [STAGE.THUNDER] = STAGE.FORCE,
}

-- Desired TB durations in TURNS
local TB_TURNS = {
  [STAGE.FIRE]    = 2,
  [STAGE.BLUNT]   = 2,
  [STAGE.SLASH]   = 2,
  [STAGE.PIERCE]  = 3,
  [STAGE.THUNDER] = 3,  -- thunder lasts 3 turns then transitions to FORCE
  [STAGE.FORCE]   = -1, -- persists until EndRage
}

-- Desired RT durations in SECONDS
local RT_SECONDS = {
  [STAGE.FIRE]    = 12.0,
  [STAGE.BLUNT]   = 12.0,
  [STAGE.SLASH]   = 12.0,
  [STAGE.PIERCE]  = 18.0,
  [STAGE.THUNDER] = 18.0, -- thunder lasts 18s then transitions to FORCE
  [STAGE.FORCE]   = -1.0,
}

local State = {
  raging = false,
  currentStage = nil,
  tb = false,
  thunderProc = false, -- 1 random item destruction + aura (once per rage)
  forceProc = false,   -- destroy ALL equipped items (once per rage)
  forceLoopActive = false, -- keep destroying items every 2 turns while FORCE is active
  forceRTScheduled = false,
  pauseReasons = {
    downed = false,
    forceTB = false,
  },
  deadStopped = false,
  -- Manual turn tracking (V32+): instead of relying on the engine's turn-duration
  -- (which now counts in real seconds), we count Karlach's own TurnStarted events.
  tbTurnsRemaining = 0,
  forceLoopTurns = 0,
}

local ApplyStage


-- Combat/TB detection (vanilla combat turns)
local ActiveCombatCount = 0

local function IsInForceTB()
  local ok, res = pcall(Osi.IsInForceTurnBasedMode, KARLACH)
  if ok and res ~= nil then return res == 1 end
  return false
end

local function IsInCombatNow()
  local ok, res = pcall(Osi.IsInCombat, KARLACH)
  return ok and res == 1
end

local function IsDeadNow()
  local ok, res = pcall(Osi.IsDead, KARLACH)
  return ok and res == 1
end

local function IsPaused()
  return State.pauseReasons.downed or State.pauseReasons.forceTB
end

local function RefreshTBState(reason)
  local was = State.tb
  -- Treat vanilla combat as TB for status application. Force TB also counts.
  State.tb = IsInForceTB() or (ActiveCombatCount > 0) or IsInCombatNow()
  if was ~= State.tb then
    Ext.Utils.Print(string.format("%s TB_STATE: %s -> %s (%s) ActiveCombatCount=%d",
      MOD_PREFIX, tostring(was), tostring(State.tb), tostring(reason), ActiveCombatCount))
    if State.raging and State.currentStage and not IsPaused() and not State.deadStopped then
      ApplyStage(State.currentStage)
    end
  end
end

local EQUIP_SLOTS = {
  "Helmet","Amulet","Breast","Cloak","Belt","Gloves","Leggings","Boots",
  "Ring","Ring2",
  "Weapon","Shield",
  "Melee Main Weapon","Melee Offhand Weapon",
  "Ranged Main Weapon","Ranged Offhand Weapon",
  "CampClothing","CampShoes","Underwear",
  "Instrument","Torch","Arrow",
}

local function HasActive(charGuid, status)
  local ok, has = pcall(function() return Osi.HasActiveStatus(charGuid, status) end)
  return ok and has ~= 0
end

local function HasStatus(status)
  return HasActive(KARLACH, status)
end

-- Osiris may hand us "Name_UUID" or the bare UUID depending on SE version; match on the UUID.
local KARLACH_UUID = string.sub(KARLACH, -36)
local function IsKarlach(guid)
  return type(guid) == "string" and string.sub(guid, -36) == KARLACH_UUID
end

local function HasInfernalFury()
  return HasActive(KARLACH, INFERNAL_FURY_STATUS)
end

local function IsItemImmuneToDestruction(itemGuid)
  if not itemGuid or itemGuid == "" then return false end
  if KarlachsRageConfig and KarlachsRageConfig.IsItemImmune then
    local ok, immune = pcall(KarlachsRageConfig.IsItemImmune, itemGuid)
    return ok and immune == true
  end
  return false
end

local function CollectEquippedItems(charGuid)
  local items, seen = {}, {}
  for _, slot in ipairs(EQUIP_SLOTS) do
    local item = ""
    pcall(function() item = Osi.GetEquippedItem(charGuid, slot) end)
    if item and item ~= "" and not seen[item] and not IsItemImmuneToDestruction(item) then
      seen[item] = true
      table.insert(items, item)
    end
  end
  return items
end

local function DestroyItem(charGuid, item)
  if not item or item == "" then return end
  if IsItemImmuneToDestruction(item) then
    Ext.Utils.Print(string.format("%s Item immunity active -> skipped destruction for %s", MOD_PREFIX, tostring(item)))
    return
  end
  pcall(function() Osi.Unequip(charGuid, item) end)
  pcall(function() Osi.RequestDelete(item) end)
end

local function DestroyRandomEquippedItem(charGuid)
  -- NEW: Skip all destruction if Infernal Fury is active
  if HasInfernalFury() then
    Ext.Utils.Print(MOD_PREFIX .. " Infernal Fury active -> skipping random equipped item destruction")
    return
  end

  local items = CollectEquippedItems(charGuid)
  if #items == 0 then
    Ext.Utils.Print(MOD_PREFIX .. " Thunder proc: no destroyable equipped items found")
    return
  end
  local idx = Ext.Utils.Random(1, #items)
  local item = items[idx]
  DestroyItem(charGuid, item)
  Ext.Utils.Print(string.format("%s Thunder proc: destroyed equipped item %s", MOD_PREFIX, tostring(item)))
end

local function DestroyAllEquippedItems(charGuid)
  -- NEW: Skip all destruction if Infernal Fury is active
  if HasInfernalFury() then
    Ext.Utils.Print(MOD_PREFIX .. " Infernal Fury active -> skipping ALL equipped item destruction")
    return
  end

  local items = CollectEquippedItems(charGuid)
  if #items == 0 then
    Ext.Utils.Print(MOD_PREFIX .. " Force proc: no destroyable equipped items found")
    return
  end
  for _, item in ipairs(items) do
    DestroyItem(charGuid, item)
  end
  Ext.Utils.Print(string.format("%s Force proc: destroyed %d equipped items", MOD_PREFIX, #items))
end

local function IsRageShout(spell)
  return type(spell) == "string" and spell:find("^Shout_Rage") ~= nil
end

local function IsEndRage(spell)
  return spell == "Shout_EndRage"
end

local function RemoveAllStages()
  for _, s in pairs(STAGE) do
    pcall(function() Osi.RemoveStatus(KARLACH, s) end)
  end
end

local function RemoveBurningAura()
  pcall(function() Osi.RemoveStatus(KARLACH, BURNING_AURA) end)
  pcall(function() Osi.RemoveStatus(KARLACH, FIRE_AURA) end)
end

local function RemoveForceLoop()
  pcall(function() Osi.RemoveStatus(KARLACH, FORCE_LOOP) end)
end

local function ClearActiveProgressionEffects()
  RemoveAllStages()
  RemoveBurningAura()
  RemoveForceLoop()
end

local function PauseRageProgression(reasonKey, reasonLabel)
  if not State.raging or State.deadStopped or not State.currentStage then return end
  if State.pauseReasons[reasonKey] then return end
  local wasPaused = IsPaused()
  State.pauseReasons[reasonKey] = true
  State.forceRTScheduled = false
  if not wasPaused then
    ClearActiveProgressionEffects()
    Ext.Utils.Print(string.format("%s Rage progression paused at stage %s (%s)", MOD_PREFIX, tostring(State.currentStage), tostring(reasonLabel)))
  else
    Ext.Utils.Print(string.format("%s Added pause reason %s at stage %s", MOD_PREFIX, tostring(reasonLabel), tostring(State.currentStage)))
  end
end

local function ResumeRageProgression(reasonKey, reasonLabel)
  if not State.raging or State.deadStopped or not State.currentStage then return end
  if not State.pauseReasons[reasonKey] then return end
  State.pauseReasons[reasonKey] = false
  if IsPaused() then
    Ext.Utils.Print(string.format("%s Cleared pause reason %s but progression is still paused", MOD_PREFIX, tostring(reasonLabel)))
    return
  end
  if HasStatus(DOWNED_STATUS) or IsDeadNow() then return end
  RefreshTBState("Resume:" .. tostring(reasonLabel))
  ApplyStage(State.currentStage)
  Ext.Utils.Print(string.format("%s Rage progression resumed at stage %s (%s)", MOD_PREFIX, tostring(State.currentStage), tostring(reasonLabel)))
end

local function StopRageBecauseDeath()
  local hadActiveRage = State.raging or IsPaused() or State.currentStage ~= nil
  State.raging = false
  State.currentStage = nil
  State.thunderProc = false
  State.forceProc = false
  State.forceLoopActive = false
  State.forceRTScheduled = false
  State.pauseReasons.downed = false
  State.pauseReasons.forceTB = false
  State.deadStopped = true
  State.tbTurnsRemaining = 0
  State.forceLoopTurns = 0
  ClearActiveProgressionEffects()
  if hadActiveRage then
    Ext.Utils.Print(MOD_PREFIX .. " Death detected -> stopped rage progression for this rage")
  end
end

local function ApplyStatus_TB(status, turns)
  -- V32+ SE: CharacterApplyStatus is unreliable/absent.
  -- Apply with a large fixed duration and handle turns manually via TurnStarted.
  pcall(function() Osi.ApplyStatus(KARLACH, status, -1.0, 1) end)
end

local function VerifyStatusApplied(status)
  -- Immediate HasActiveStatus can be false-negative right after ApplyStatus/CharacterApplyStatus.
  -- So we re-check 2ms later before logging an error.
  local ok, has = pcall(function() return Osi.HasActiveStatus(KARLACH, status) end)
  if not ok or has ~= 0 then
    return
  end

  Ext.Timer.WaitFor(2, function()
    local ok2, has2 = pcall(function() return Osi.HasActiveStatus(KARLACH, status) end)
    if ok2 and has2 == 0 then
      Ext.Utils.Print(string.format("%s ERROR: status not applied: %s", MOD_PREFIX, tostring(status)))
    end
  end)
end

local function ScheduleForceRTPulse()
  if State.forceRTScheduled then return end
  State.forceRTScheduled = true
  Ext.Timer.WaitFor(12000, function()
    State.forceRTScheduled = false
    if not (State.raging and State.forceLoopActive) then return end
    if IsPaused() or State.deadStopped then return end
    if State.tb then return end -- do not pulse by seconds in TB
    if not HasStatus(STAGE.FORCE) then return end
    DestroyAllEquippedItems(KARLACH)
    ScheduleForceRTPulse()
  end)
end

local function EnsureForceLoopRunning()
  if not (State.raging and State.forceLoopActive) then return end
  if IsPaused() or State.deadStopped then return end
  if State.tb then
    -- TB: drive pulses by a manual turn counter (2 Karlach turns)
    if State.forceLoopTurns <= 0 then
      State.forceLoopTurns = 2
      Ext.Utils.Print(string.format("%s FORCE loop TB: turn counter set to 2", MOD_PREFIX))
    end
  else
    ScheduleForceRTPulse()
  end
end

ApplyStage = function(stage)
  if IsPaused() or State.deadStopped then return end
  -- Exclusivity: only one stage at a time
  RemoveAllStages()

  if State.tb then
    local turns = TB_TURNS[stage] or -1
    ApplyStatus_TB(stage, turns)
    State.tbTurnsRemaining = turns  -- manual turn tracking
    VerifyStatusApplied(stage)
    Ext.Utils.Print(string.format("%s APPLY_STAGE_TB: %s turns=%s tbTurnsRemaining=%s", MOD_PREFIX, tostring(stage), tostring(turns), tostring(State.tbTurnsRemaining)))
  else
    State.tbTurnsRemaining = 0
    local seconds = RT_SECONDS[stage] or -1.0
    pcall(function() Osi.ApplyStatus(KARLACH, stage, seconds, 1) end)
    VerifyStatusApplied(stage)
    Ext.Utils.Print(string.format("%s APPLY_STAGE_RT: %s seconds=%s", MOD_PREFIX, tostring(stage), tostring(seconds)))
  end

  VerifyStatusApplied(stage)
  State.currentStage = stage

  -- Thunder side-effects: when we FIRST reach thunder in a rage chain
  if stage == STAGE.THUNDER and State.raging then
    if not State.thunderProc then
      State.thunderProc = true
      DestroyRandomEquippedItem(KARLACH)
    end
  end

  -- Auras start at THUNDER and persist through FORCE. Re-applied on FORCE too, so they
  -- come back after a pause (downed / forced turn-based) that stripped them.
  if (stage == STAGE.THUNDER or stage == STAGE.FORCE) and State.raging then
    pcall(function() Osi.ApplyStatus(KARLACH, BURNING_AURA, -1.0, 1) end)
    pcall(function() Osi.ApplyStatus(KARLACH, FIRE_AURA, -1.0, 1) end)
    Ext.Utils.Print(string.format("%s Applied auras: %s + %s", MOD_PREFIX, BURNING_AURA, FIRE_AURA))
  end

  -- Force side-effects: when we FIRST reach force in a rage chain
  if stage == STAGE.FORCE and State.raging and not State.forceProc then
    State.forceProc = true
    DestroyAllEquippedItems(KARLACH)

    -- After reaching FORCE, keep deleting anything the player equips again
    State.forceLoopActive = true
    EnsureForceLoopRunning()
  end

  -- If FORCE is active (and we re-applied current stage due to TB/RT toggle), make sure the loop keeps running
  if stage == STAGE.FORCE and State.raging and State.forceLoopActive then
    EnsureForceLoopRunning()
  end
end

local function StartRage(spell)
  State.raging = true
  RefreshTBState("RageStart")
  State.thunderProc = false
  State.forceProc = false
  State.forceLoopActive = false
  State.forceRTScheduled = false
  State.pauseReasons.downed = false
  State.pauseReasons.forceTB = IsInForceTB()
  State.deadStopped = false
  State.tbTurnsRemaining = 0
  State.forceLoopTurns = 0
  -- Safety: aura should not leak between rages
  RemoveBurningAura()
  RemoveForceLoop()
  State.currentStage = STAGE.FIRE
  if IsPaused() then
    Ext.Utils.Print(MOD_PREFIX .. " Rage started while paused; deferring stage application")
  else
    ApplyStage(STAGE.FIRE)
  end
end

local function EndRage()
  State.raging = false
  State.currentStage = nil
  State.forceLoopActive = false
  State.forceRTScheduled = false
  State.pauseReasons.downed = false
  State.pauseReasons.forceTB = false
  State.deadStopped = false
  State.tbTurnsRemaining = 0
  State.forceLoopTurns = 0
  RemoveAllStages()
  RemoveBurningAura()
  RemoveForceLoop()
  Ext.Utils.Print(MOD_PREFIX .. " End rage -> removed all stage statuses + aura")
end

local function OnStageRemoved(status)
  if not State.raging or IsPaused() or State.deadStopped then return end
  local nextStage = NEXT_STAGE[status]
  if not nextStage then return end
  -- Turn-based chaining is driven directly by the TurnStarted counter.
  -- Here we only handle a stage that genuinely ran out in real time; removals caused by
  -- our own re-apply / stage swap must NOT advance the chain (that skipped stages).
  if State.tb then return end
  Ext.Timer.WaitFor(1, function()
    if not State.raging or IsPaused() or State.deadStopped or State.tb then return end
    if State.currentStage ~= status then return end
    if HasStatus(status) then return end
    ApplyStage(nextStage)
  end)
end

-- Rage/End Rage
Ext.Osiris.RegisterListener("UsingSpellOnTarget", 6, "after", function(caster, target, spell)
  if not IsKarlach(caster) then return end
  if IsRageShout(spell) then
    Ext.Utils.Print(string.format("%s Rage shout detected: %s", MOD_PREFIX, tostring(spell)))
    StartRage(spell)
  elseif IsEndRage(spell) then
    Ext.Utils.Print(string.format("%s End rage detected: %s", MOD_PREFIX, tostring(spell)))
    EndRage()
  end
end)

Ext.Osiris.RegisterListener("StatusApplied", 4, "after", function(object, status)
  if not IsKarlach(object) then return end
  if status ~= DOWNED_STATUS then return end
  PauseRageProgression("downed", "DOWNED applied")
end)

Ext.Osiris.RegisterListener("StatusApplied", 3, "after", function(object, status)
  if not IsKarlach(object) then return end
  if status ~= DOWNED_STATUS then return end
  PauseRageProgression("downed", "DOWNED applied")
end)

-- Stage chaining
Ext.Osiris.RegisterListener("StatusRemoved", 4, "after", function(object, status)
  if not IsKarlach(object) then return end

  if status == DOWNED_STATUS then
    if IsDeadNow() then
      StopRageBecauseDeath()
    else
      ResumeRageProgression("downed", "DOWNED removed")
    end
    return
  end

  -- FORCE loop pulse (legacy RT mode only): in V32+ TB mode this is driven by TurnStarted.
  if status == FORCE_LOOP then
    if State.raging and not IsPaused() and not State.deadStopped and State.forceLoopActive and HasStatus(STAGE.FORCE) then
      DestroyAllEquippedItems(KARLACH)
      Ext.Utils.Print(MOD_PREFIX .. " FORCE loop pulse (legacy) -> destroyed all equipped items")
    end
    return
  end

  if NEXT_STAGE[status] == nil then return end
  Ext.Utils.Print(string.format("%s StatusRemoved: %s", MOD_PREFIX, tostring(status)))
  OnStageRemoved(status)
end)

Ext.Osiris.RegisterListener("StatusRemoved", 3, "after", function(object, status)
  if not IsKarlach(object) then return end
  if status == DOWNED_STATUS then
    if IsDeadNow() then
      StopRageBecauseDeath()
    else
      ResumeRageProgression("downed", "DOWNED removed")
    end
    return
  end
  if NEXT_STAGE[status] == nil then return end
  Ext.Utils.Print(string.format("%s StatusRemoved: %s", MOD_PREFIX, tostring(status)))
  OnStageRemoved(status)
end)

Ext.Osiris.RegisterListener("Died", 1, "after", function(character)
  if not IsKarlach(character) then return end
  StopRageBecauseDeath()
end)

-- Turn-based mode enter/exit (non-combat specific)
Ext.Osiris.RegisterListener("EnteredForceTurnBased", 1, "after", function(object)
  if not IsKarlach(object) then return end
  PauseRageProgression("forceTB", "EnteredForceTurnBased")
  if not State.tb then
    State.tb = true
  RefreshTBState("EnteredForceTurnBased")
    Ext.Utils.Print(MOD_PREFIX .. " EnteredForceTurnBased -> TB on")
    if State.raging and State.currentStage and not IsPaused() and not State.deadStopped then
      local cur = State.currentStage
      ApplyStage(cur)
    end
  end
end)

Ext.Osiris.RegisterListener("LeftForceTurnBased", 1, "after", function(object)
  if not IsKarlach(object) then return end
  if State.tb then
    State.tb = false
  RefreshTBState("LeftForceTurnBased")
    Ext.Utils.Print(MOD_PREFIX .. " LeftForceTurnBased -> TB off")
  end
  ResumeRageProgression("forceTB", "LeftForceTurnBased")
end)



-- Vanilla combat events (do not rely on dead entity combat membership)
Ext.Osiris.RegisterListener("CombatStarted", 1, "after", function(combatGuid)
  ActiveCombatCount = ActiveCombatCount + 1
  Ext.Utils.Print(string.format("%s CombatStarted: %s ActiveCombatCount=%d", MOD_PREFIX, tostring(combatGuid), ActiveCombatCount))
  RefreshTBState("CombatStarted")
end)

Ext.Osiris.RegisterListener("CombatEnded", 1, "after", function(combatGuid)
  ActiveCombatCount = math.max(0, ActiveCombatCount - 1)
  Ext.Utils.Print(string.format("%s CombatEnded: %s ActiveCombatCount=%d", MOD_PREFIX, tostring(combatGuid), ActiveCombatCount))
  RefreshTBState("CombatEnded")
end)

-- Track turns manually for stage chaining and force loop (V32+ compatibility)
Ext.Osiris.RegisterListener("TurnStarted", 1, "after", function(character)
  if not IsKarlach(character) then return end

  -- V32+ safety: if Karlach received a turn, we are in turn-based mode.
  -- Force TB detection here in case CombatStarted event signature changed.
  if not State.tb and not IsPaused() and not State.deadStopped then
    local was = State.tb
    State.tb = true
    if State.raging and State.currentStage then
      ApplyStage(State.currentStage)
      Ext.Utils.Print(string.format("%s TB forced true via TurnStarted (V32+ compat)", MOD_PREFIX))
    end
  end

  RefreshTBState("TurnStarted(Karlach)")

  if not State.raging or IsPaused() or State.deadStopped or not State.tb then return end
  if not State.currentStage then return end

  -- Decrement stage turn counter (skip -1 = infinite stages like FORCE)
  if State.tbTurnsRemaining > 0 then
    State.tbTurnsRemaining = State.tbTurnsRemaining - 1
    Ext.Utils.Print(string.format("%s TB turn decrement: stage=%s remaining=%d", MOD_PREFIX, tostring(State.currentStage), State.tbTurnsRemaining))
    if State.tbTurnsRemaining == 0 then
      local nextStage = NEXT_STAGE[State.currentStage]
      if nextStage then
        ApplyStage(nextStage)
      end
    end
  end

  -- Force loop: every 2 Karlach turns, destroy all equipped items
  if State.forceLoopActive and State.currentStage == STAGE.FORCE then
    State.forceLoopTurns = State.forceLoopTurns - 1
    if State.forceLoopTurns <= 0 then
      State.forceLoopTurns = 2
      DestroyAllEquippedItems(KARLACH)
      Ext.Utils.Print(MOD_PREFIX .. " FORCE loop pulse (TB turn) -> destroyed all equipped items")
    end
  end
end)

-- Save/load recovery: detect any existing stage on Karlach and resume tracking
local function RecoverRageState()
  local foundStage = nil
  for _, sid in pairs(STAGE) do
    if HasStatus(sid) then
      foundStage = sid
      break
    end
  end
  if not foundStage then return end

  State.raging = true
  State.currentStage = foundStage
  State.thunderProc = HasStatus(INFERNAL_FURY_STATUS) or false
  State.forceProc = false
  State.forceLoopActive = false
  State.forceRTScheduled = false
  State.pauseReasons.downed = HasStatus(DOWNED_STATUS)
  State.pauseReasons.forceTB = IsInForceTB()
  State.deadStopped = IsDeadNow()
  State.tb = IsInForceTB() or (ActiveCombatCount > 0) or IsInCombatNow()

  if State.tb then
    if foundStage == STAGE.FORCE then
      State.tbTurnsRemaining = -1
      State.forceProc = true
      State.forceLoopActive = true
      State.forceLoopTurns = 1
    else
      -- Assume 1 turn remaining so the stage progresses on next Karlach turn
      State.tbTurnsRemaining = 1
    end
  end

  if HasStatus(BURNING_AURA) and not State.thunderProc then
    State.thunderProc = true
  end

  Ext.Utils.Print(string.format("%s Save/load recovery: detected stage=%s tb=%s", MOD_PREFIX, tostring(foundStage), tostring(State.tb)))
end

-- At script-load time Osiris is not queryable yet, so this call only helps after a Lua reset.
RecoverRageState()
-- Real save/load recovery: run once the level is live.
Ext.Osiris.RegisterListener("LevelGameplayStarted", 2, "after", function()
  if not State.raging then
    RecoverRageState()
  end
end)

-- ============================================================================
-- Natural rage end detection
-- Previously the chain only stopped on Shout_EndRage, so when the game's own Rage
-- status ran out (combat ending, duration, being knocked out) the stages kept
-- going and kept burning her gear. We now watch Karlach's vanilla rage statuses
-- and end the progression once none of them are left on her.
-- ============================================================================
local ActiveRageStatuses = {}

local function IsVanillaRageStatus(status)
  if type(status) ~= "string" or status == "" then return false end
  if status:find("^KAR_") then return false end -- our own stage/aura statuses
  if status:find("^RAGE") then return true end
  local ok, found = pcall(function()
    local stat = Ext.Stats.Get(status)
    if not stat or not stat.StatusGroups then return false end
    for _, group in pairs(stat.StatusGroups) do
      if group == "SG_Rage" then return true end
    end
    return false
  end)
  return ok and found == true
end

local function AnyStageActive()
  for _, sid in pairs(STAGE) do
    if HasStatus(sid) then return true end
  end
  return false
end

local function EndRageAndCleanup(reason)
  Ext.Utils.Print(string.format("%s Ending rage progression (%s)", MOD_PREFIX, tostring(reason)))
  EndRage()
end

Ext.Osiris.RegisterListener("StatusApplied", 4, "after", function(object, status)
  if not IsKarlach(object) then return end
  if IsVanillaRageStatus(status) then
    ActiveRageStatuses[status] = true
  end
end)

Ext.Osiris.RegisterListener("StatusRemoved", 4, "after", function(object, status)
  if not IsKarlach(object) then return end
  if not IsVanillaRageStatus(status) then return end
  -- Short delay so a rage status that is just being refreshed/re-applied is not mistaken for rage ending.
  Ext.Timer.WaitFor(300, function()
    if HasStatus(status) then return end
    ActiveRageStatuses[status] = nil
    for other in pairs(ActiveRageStatuses) do
      if HasStatus(other) then return end
      ActiveRageStatuses[other] = nil
    end
    if State.raging or AnyStageActive() then
      EndRageAndCleanup("vanilla rage status " .. tostring(status) .. " ended")
    end
  end)
end)

-- ============================================================================
-- MCM debug: "End Karlach's Rage" button (client sends request; only allowed out of combat)
-- ============================================================================
local DEBUG_END_REQ = ModuleUUID .. "_Debug_EndRage"
local DEBUG_END_RES = ModuleUUID .. "_Debug_EndRage_Result"

local function ReplyToUser(user, message)
  pcall(function() Ext.ServerNet.PostMessageToUser(user, DEBUG_END_RES, message) end)
end

Ext.RegisterNetListener(DEBUG_END_REQ, function(_, _, user)
  if IsInCombatNow() then
    Ext.Utils.Print(MOD_PREFIX .. " Debug End Rage refused: Karlach is in combat")
    ReplyToUser(user, "Refused: Karlach is in combat. This button only works outside combat.")
    return
  end

  local hadProgression = State.raging or AnyStageActive()

  -- End the vanilla rage too, so it cannot keep driving anything.
  for rageStatus in pairs(ActiveRageStatuses) do
    pcall(function() Osi.RemoveStatus(KARLACH, rageStatus) end)
    ActiveRageStatuses[rageStatus] = nil
  end

  EndRageAndCleanup("MCM debug button")

  if hadProgression then
    ReplyToUser(user, "Karlach's rage and its progression have been ended.")
  else
    ReplyToUser(user, "No rage progression was active. Cleaned up any leftover statuses anyway.")
  end
end)

Ext.Utils.Print(MOD_PREFIX .. " Karlach_Rage_StatusChain_v12.lua LOADED (server)")
