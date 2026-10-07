local uevrUtils = require('libs/uevr_utils')
local plugin = require('libs/core/plugin')
local mounts = require('helpers/mounts')
local controllers = require('libs/controllers')
local ui = require('libs/ui')
local widgetModule = require('libs/widget')

local M = {}

local status = {}
local noneBone

local currentLogLevel = LogLevel.Error
function M.setLogLevel(val)
	currentLogLevel = val
end
function M.print(text, logLevel)
    if logLevel == nil then logLevel = LogLevel.Debug end
    if logLevel <= currentLogLevel then
        uevrUtils.print("[spell] " .. text, logLevel)
    end
end

local function getWand(pawn)
	if pawn ~= nil and UEVR_UObjectHook.exists(pawn) then
		local success, wand = pcall(function()
			return pawn:GetWand()
		end)
		return uevrUtils.getValid(wand)
	end
	return nil
end
function M.getWand(pawn)
	return getWand(pawn)
end

local function isInRoomOfRequirement()
	status.mapSubSystem = uevrUtils.getValid(status.mapSubSystem) or uevrUtils.find_first_of("Class /Script/Phoenix.MapSubSystem", false)
	return status.mapSubSystem ~= nil and status.mapSubSystem:IsSanctuary()
end

local function capturableCreatureInRange()
	status.capturableCreatureInRange = false
	status.creatureManager = uevrUtils.getValid(status.creatureManager) or uevrUtils.find_first_of("Class /Script/Phoenix.CreatureManager", false)
	if status.creatureManager == nil or uevrUtils.getValid(pawn) == nil then return false end
	local loc = pawn:K2_GetActorLocation()
	for _, creature in ipairs(uevrUtils.find_all_of("Class /Script/Phoenix.Creature_Character", false) or {}) do
		local def = status.creatureManager:BP_GetCreatureDefinitionForActor(creature)
		if def ~= nil and def:GetCanBeCaptured() then
			local c = creature:K2_GetActorLocation()
			local dx, dy, dz = c.X - loc.X, c.Y - loc.Y, c.Z - loc.Z
			local max = def:GetCapturingDistanceMax()
			if dx * dx + dy * dy + dz * dz <= max * max then
				status.capturableCreatureInRange = true
				return true
			end
		end
	end
	return false
end

-- When auto targeting is off, the sense is still needed for creature capture and RoR transformation targeting
local useContextAutoTargetSense = true -- false = old behavior: sense follows the config setting only
local useAutoTargeting = false
local function updateAutoTargetSense()
	if not useContextAutoTargetSense then return end
	local on = useAutoTargeting or isInRoomOfRequirement() or capturableCreatureInRange()
	-- keep reasserting off: the game re-enables the sense itself (e.g. on broom dismount)
	if on and status.autoTargetSenseOn then return end
	local pc = uevr.api:get_player_controller(0)
	if pc ~= nil and pc.ActivateAutoTargetSense ~= nil then
		pc:ActivateAutoTargetSense(on, true)
		status.autoTargetSenseOn = on
	end
end
setInterval(500, updateAutoTargetSense)

function M.activateAutoTargetSense(value)
	if not useContextAutoTargetSense then
		local pc = uevr.api:get_player_controller(0)
		if pc ~= nil and pc.ActivateAutoTargetSense ~= nil then
			pc:ActivateAutoTargetSense(value, true)
		end
		return
	end
	useAutoTargeting = value == true
	status.autoTargetSenseOn = nil
	updateAutoTargetSense()
end

function M.isWandDrawn(pawn)
	if status.mapSubSystem == nil then
		status.mapSubSystem = uevrUtils.find_first_of("Class /Script/Phoenix.MapSubSystem", false)
	end
	if status.mapSubSystem ~= nil and status.mapSubSystem:IsTutorial() then
		--print("IsTutorial", true)

		local anim = pawn.Mesh and pawn.Mesh:GetAnimInstance()
		if anim ~= nil then
			if anim.IsWandEquipped then return true end
			-- BlockedByWall(13) + stuck IsEquippingWand is not in-hand; only trust it during Stupefy tutorial.
			if anim.IsEquippingWand and anim.PartialBodyState == 13 then
				if status.tutorialSystem == nil then
					status.tutorialSystem = uevrUtils.find_first_of("Class /Script/Phoenix.TutorialSystem", false)
				end
				if status.tutorialSystem ~= nil and status.tutorialSystem:IsTutorialActive(uevrUtils.fname_from_string("Stupefy")) then return true end
			end
			local p = anim.PartialBodyState
			if p == 1 or p == 2 or p == 3 or p == 4 or p == 10 or p == 14 or p == 16 or p == 17 then
				return true
			end
		end
		local arm = pawn.GetRightArmState and pawn:GetRightArmState(1)
		if arm == 1 or arm == 3 or arm == 4 or arm == 5 or arm == 6 or arm == 14 or arm == 15 then
			return true
		end
		local abl = pawn.AblAbilityComponent
		if abl ~= nil then
			for _, channel in ipairs({"PartialBody", "FullBody", "RightArm"}) do
				local ability = abl:GetActiveAbility_New(uevrUtils.fname_from_string(channel))
				local name = ability and ability:get_full_name() or ""
				if string.find(name, "Wand", 1, true) and not string.find(name, "Unequip", 1, true) then
					return true
				end
			end
		end
		return false
	end

	-- Outside tutorial: HoldItem is the in-hand pose. Wand* abilities cover casts (arm leaves HoldItem).
	local anim = pawn.Mesh and pawn.Mesh:GetAnimInstance()
	if anim ~= nil and anim.IsWandEquipped then return true end
	local arm = pawn.GetRightArmState and pawn:GetRightArmState(1)
	if arm == 3 then return true end
	local abl = pawn.AblAbilityComponent
	if abl ~= nil then
		for _, channel in ipairs({"PartialBody", "FullBody", "RightArm"}) do
			local ability = abl:GetActiveAbility_New(uevrUtils.fname_from_string(channel))
			local name = ability and ability:get_full_name() or ""
			if string.find(name, "Wand", 1, true) and not string.find(name, "Unequip", 1, true) then
				return true
			end
		end
	end
	return false

end

----------------- Accio fix for flying pages ------------------
local function getPagePaper(page)
	local mesh = plugin.getProperty(page, "SK_Paper")
	if mesh == nil then mesh = plugin.getProperty(page, "Sphere") end
	if mesh == nil then mesh = plugin.getProperty(page, "BookRoot") end
	return mesh
end

local function findNearbyAccioPage(pawn)
	local pawnLoc = pawn ~= nil and pawn.K2_GetActorLocation and pawn:K2_GetActorLocation()
	if pawnLoc == nil then return nil end
	local best, bestDist = nil, 1500 * 1500
	local function consider(list)
		if list == nil then return end
		for _, actor in pairs(list) do
			if actor ~= nil and UEVR_UObjectHook.exists(actor) then
				local mesh = getPagePaper(actor)
				local loc = mesh ~= nil and mesh.K2_GetComponentLocation and mesh:K2_GetComponentLocation()
				if loc ~= nil and pawnLoc ~= nil then
					local dx, dy, dz = loc.X - pawnLoc.X, loc.Y - pawnLoc.Y, loc.Z - pawnLoc.Z
					local d = dx * dx + dy * dy + dz * dz
					if d < bestDist then
						best, bestDist = actor, d
					end
				end
			end
		end
	end
	consider(uevrUtils.find_all_of("Class /Script/Phoenix.FlyingBook", false))
	consider(uevrUtils.find_all_of("Class /Script/Phoenix.FieldGuidePage", false))
	return best
end

-- Don't call AccioStart before the wand Accio fires: that hides the page.
-- Don't retarget GetTargetDestination: that made Accio miss again.
-- After Accio hits, detach the paper, walk it to the current wand, then collect.
local function pullAccioPage(pawn, page)
	local mesh = getPagePaper(page)
	if mesh == nil then return end
	local ticks = 0
	local collecting = false
	local function step()
		if page == nil or not UEVR_UObjectHook.exists(page) then return end
		if pawn == nil or not UEVR_UObjectHook.exists(pawn) then return end
		if mesh == nil or not UEVR_UObjectHook.exists(mesh) then return end
		if ticks == 0 then
			if mesh.DetachFromParent ~= nil then
				mesh:DetachFromParent(true, false)
			end
			plugin.setProperty(page, "bFollowSpline", false)
			plugin.setProperty(page, "bStartFlying", false)
			plugin.setProperty(page, "BookSpeed", 0)
			plugin.setProperty(page, "BookSpeedMod", 0)
			local abp = plugin.getProperty(page, "ABP")
			if abp ~= nil then
				plugin.executeFunction(abp, "AccioPull", true)
				plugin.setProperty(abp, "bAccio", true)
				plugin.setProperty(abp, "bPanic", false)
				plugin.setProperty(abp, "bFlap", false)
			end
		end
		local wandMesh = uevrUtils.getValid(getWand(pawn), {"Mesh"})
		local dest = wandMesh ~= nil and wandMesh:K2_GetComponentLocation() or pawn:K2_GetActorLocation()
		local loc = mesh:K2_GetComponentLocation()
		if dest == nil or loc == nil then return end
		ticks = ticks + 1
		local dx, dy, dz = dest.X - loc.X, dest.Y - loc.Y, dest.Z - loc.Z
		local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
		if dist < 80 and ticks > 20 then
			if not collecting then
				collecting = true
				if wandMesh ~= nil and mesh.K2_AttachToComponent ~= nil then
					mesh:K2_AttachToComponent(wandMesh, "", 2, 2, 0, false)
				end
				local abp = plugin.getProperty(page, "ABP")
				if abp ~= nil then plugin.setProperty(abp, "bCollect", true) end
				plugin.executeFunction(page, "OnSpellEffective", pawn)
				plugin.executeFunction(page, "InteractionInitiated")
				plugin.executeFunction(page, "DestroyActorTimer")
			end
			mesh:K2_SetWorldLocation(dest, false, reusable_hit_result, true)
			delay(20, step)
			return
		end
		local n = math.min(1, 54 / math.max(dist, 1))
		mesh:K2_SetWorldLocation(uevrUtils.vector(loc.X + dx * n, loc.Y + dy * n, loc.Z + dz * n), false, reusable_hit_result, true)
		delay(20, step)
	end
	delay(400, step)
end
---------------------- End accio page fix ------------------



-- Spell VO is posted via AvaAudio (VO_Spell / PostEventPlayerVoice), not by blanking AudioSwitchName.
-- Mute by suppressing those posts and briefly zeroing the voice bus around a muted cast.
local function shouldMuteSpellVoice()
	return status.muteSpellVoice == true or status.suppressSpellVoice == true
end

local function getGameSettings()
	if uevrUtils.getValid(status.gameSettings) == nil then
		local cdo = uevrUtils.find_required_object("PhoenixGameSettings /Script/Phoenix.Default__PhoenixGameSettings")
		if cdo ~= nil and cdo.GetPhoenixGameSettings ~= nil then
			status.gameSettings = cdo:GetPhoenixGameSettings()
		end
	end
	return status.gameSettings
end

-- Mutes only the player's own Wwise emitters so NPC dialogue keeps playing.
local function beginSpellVoiceSuppress(pawn, seconds)
	status.suppressSpellVoice = true
	status.spellVoiceSuppressId = (status.spellVoiceSuppressId or 0) + 1
	local id = status.spellVoiceSuppressId
	local comps = {}
	for _, comp in ipairs(uevrUtils.find_all_of("Class /Script/AkAudio.AkComponent", false) or {}) do
		if comp:GetOwner() == pawn then
			comp:SetOutputBusVolume(0)
			table.insert(comps, comp)
		end
	end
	delay(seconds or 2000, function()
		if status.spellVoiceSuppressId ~= id then return end
		status.suppressSpellVoice = false
		for _, comp in ipairs(comps) do
			if UEVR_UObjectHook.exists(comp) then comp:SetOutputBusVolume(1) end
		end
	end)
end

function M.setMuteSpellVoice(val)
	status.muteSpellVoice = val == true
end

-- return false skips the native call (UEVR hook_ptr)
hook_function("Class /Script/Phoenix.AvaAudioGameplayStatics", "PostEventPlayerVoice", true,
	function(fn, obj, locals, result)
		if shouldMuteSpellVoice() then return false end
	end,
	nil
)

hook_function("Class /Script/Phoenix.AvaAudioGameplayStatics", "PostDialogueEvent", true,
	function(fn, obj, locals, result)
		if not shouldMuteSpellVoice() or locals == nil then return end
		pcall(function()
			local name = locals.DialogueEventName
			if name ~= nil and string.find(tostring(name), "VO_Spell", 1, true) then return false end
			local ev = locals.DialogueEvent
			if ev ~= nil then
				local full = ev.get_full_name and ev:get_full_name()
				if full ~= nil and string.find(full, "VO_Spell", 1, true) then return false end
			end
		end)
	end,
	nil
)


local function isSpellAvailable(spellRecord)
	if spellRecord ~= nil then
		if status.spellManager == nil then
			status.spellManager = uevrUtils.find_required_object("SpellManagerBPInterface /Script/Phoenix.Default__SpellManagerBPInterface")
		end
		if status.spellManager ~= nil then
			return status.spellManager:IsUnlocked(spellRecord.LookupName)
		end
	end
	return false
end

--spells like lumos will remain active unless cancelled
local function cancelContinuousActiveSpells(pawn)
	local wand = getWand(pawn)
	if wand ~= nil then
		local currentActiveSpell = wand:GetActiveSpellTool()
		if currentActiveSpell ~= nil then
			local spellName = currentActiveSpell:GetSpellToolRecord().LookupName:to_string()
			if spellName == "Spell_Lumos" or spellName == "Spell_Accio" or spellName == "Spell_Wingardium" then
				wand:CancelCurrentSpell()
			end
			if spellName == "Spell_Accio" then
				M.clearAccioFX()
			end
		end
	end
end

function M.cancelContinuousActiveSpells(pawn)
	cancelContinuousActiveSpells(pawn)
end

-- Accio channel FX can stick after the spell is no longer active (e.g. VFX_NS_Accio_ReelInBeam).
function M.clearAccioFX()
	for _, spell in pairs(uevrUtils.find_all_of("Class /Script/Phoenix.AccioSpellTool", false) or {}) do
		if spell ~= nil and UEVR_UObjectHook.exists(spell) then
			if spell.TriggerReleased ~= nil then spell:TriggerReleased(true, true) end
			if spell.StopActive ~= nil then spell:StopActive() end
		end
	end
	for _, pc in pairs(uevrUtils.find_all_of("Class /Script/Niagara.NiagaraComponent", false) or {}) do
		if pc ~= nil and UEVR_UObjectHook.exists(pc) then
			local asset = pc.GetAsset and pc:GetAsset()
			local name = asset and asset.get_full_name and asset:get_full_name() or ""
			if string.find(name, "/Accio/", 1, true) then
				pc.bIsActive = false
				pc.bRenderingEnabled = false
				plugin.executeFunction(pc, "Deactivate")
				plugin.executeFunction(pc, "SetRenderingEnabled", false)
				plugin.executeFunction(pc, "SetVisibility", false, true)
			end
		end
	end
end

local function castPewPew(pawn)
	local wand = getWand(pawn)
	if wand ~= nil then
		wand:CastPewPewSpell()
	end
end

function M.castPewPew(pawn)
	castPewPew(pawn)
end

-- old way using wandpos.dll
-- function M.updateWandAim(pawn)
--     local meshComponent = uevrUtils.getValid(getWand(pawn), {"Mesh"})
--     if meshComponent ~= nil then
--         local upVector = meshComponent:GetUpVector()
--         local location = meshComponent:K2_GetComponentLocation()
--         upVector = location + upVector * 5000
--         --print(string.format("%f %f %f", upVector.X, upVector.Y, upVector.Z))
--         uevr.api:dispatch_custom_event("WandLocation", string.format("%f %f %f", upVector.X, upVector.Y, upVector.Z))
--     end
-- end
function M.getWandAim(pawn)
    local meshComponent = uevrUtils.getValid(getWand(pawn), {"Mesh"})
    if meshComponent ~= nil then
        local upVector = meshComponent:GetUpVector()
        local location = meshComponent:K2_GetComponentLocation()
        upVector = location + upVector * 5000
        return upVector
    end
    return nil
end

-- CastSpellImmediate with wand aim + bTriggerCastAnim=false: fires without ABL_WandCast_* (FullBody stays idle).
local function getSpellHelper()
	if uevrUtils.getValid(status.spellHelper) == nil or status.spellHelper.CastSpellImmediate == nil then
		status.spellHelper = uevrUtils.find_first_of("Class /Script/Phoenix.SpellHelper", false)
	end
	return status.spellHelper
end

local function isChannelingSpellName(pawn,name)
	local isChanneling = name == "Spell_Lumos" or name == "Spell_Incendio" or name == "Spell_Reparo" or name == "Spell_Disillusionment" or name == "Spell_Wingardium" or name == "Spell_Conjuration" or name == "Spell_Transformation" or name == "Spell_Vanishment"
	if not pawn.bInCombatMode then
		-- When in combat mode accio works like a combat spell with no pawn stopping on cast
		isChanneling = isChanneling or name == "Spell_Accio"
	end
	return isChanneling
end

local function castSpellNoAnim(pawn, spellTool)
	if spellTool == nil or not UEVR_UObjectHook.exists(spellTool) then return false end
	local record = spellTool.GetSpellToolRecord and spellTool:GetSpellToolRecord()
	local lookup = record and record.LookupName and record.LookupName:to_string()

	-- if lookup == "Spell_Transformation" then
	-- 	M.activateAutoTargetSense(true)
	-- end
	-- CastSpellImmediate applies this via a SpellHelper-owned copy; the wand tool then cannot toggle it off.
	if lookup == "Spell_Disillusionment" then
		local osi = pawn ~= nil and pawn.GetObjectStateInfo and pawn:GetObjectStateInfo()
		if osi ~= nil and osi.IsDisillusioned and osi:IsDisillusioned() then
			if pawn.ForceEndDisillusionment ~= nil then
				pawn:ForceEndDisillusionment()
			end
			return true
		end
	end

	-- if lookup == "Spell_Accio" then
	-- 	local page = findNearbyAccioPage(pawn)
	-- 	if page ~= nil then
	-- 		pullAccioPage(pawn, page)
	-- 		return false
	-- 	end
	-- end

	if lookup ~= nil and isChannelingSpellName(pawn,lookup) then return false end
	local helper = getSpellHelper()
	local aim = M.getWandAim(pawn)
	if helper == nil or record == nil or aim == nil then return false end
	local source = spellTool.GetMuzzleLocation and spellTool:GetMuzzleLocation()
	if source == nil then
		local mesh = uevrUtils.getValid(getWand(pawn), {"Mesh"})
		if mesh ~= nil then source = mesh:K2_GetComponentLocation() end
	end
	if source == nil then return false end
	helper:CastSpellImmediate(nil, source, record, aim, pawn, false, 0, true, true, false, false, 0, false, 0, false, false, false, true, -1)
	return true
end

local function castCurrentFlickSpell(pawn)
	local wand = getWand(pawn)
	if wand ~= nil then
		if status.currentFlickSpell == nil then
			--print("Casting active spell\n")
			status.currentFlickSpell =  wand:GetActiveSpellTool()
		else
			--print("Casting flick spell\n")
			if status.currentFlickSpell ~= nil and UEVR_UObjectHook.exists(status.currentFlickSpell) then
				pcall(function() --GetSpellToolRecord can be nil even if the test for currentFlickSpell succeeds
					local spellToolRecord = status.currentFlickSpell:GetSpellToolRecord()
					if spellToolRecord ~= nil and isSpellAvailable(spellToolRecord) then
						wand:CancelCurrentSpell()
						local spellTool = wand:ActivateSpellTool(spellToolRecord, true)
						if spellTool == nil then spellTool = status.currentFlickSpell end
						if not castSpellNoAnim(pawn, spellTool) then
							wand:CastSpell(spellTool, true)
							--castChannelingSpellWhileMoving(pawn, spellTool, function() return wand:CastSpell(spellTool, true) end)
						end
					end
				end)
			else
				status.currentFlickSpell = nil
			end
		end
	end
end

function M.castCurrentFlickSpell(pawn)
	if status.muteSpellVoice then
		beginSpellVoiceSuppress(pawn, 2000)
	end
	if status.currentFlickSpellName ~= nil then
		M.castSpell(pawn, status.currentFlickSpellName)
	else
		castCurrentFlickSpell(pawn)
	end
end

local function castAlohomora(pawn)
	status.isAlohomoraCasting = true
end

local function castPetrificus(pawn)
	status.isPetrificusCasting = true
end

local function castViaspecto(pawn)
	status.isViaspectoCasting = true
end

local function castTormentum(pawn)
	status.isTormentumCasting = true
end

local function castOppugno(pawn)
	status.isOppugnoCasting = true
end

local function castUpBroom(pawn)
	if status.phoenixBlueprintLibrary == nil then
		status.phoenixBlueprintLibrary = uevrUtils.find_default_instance("Class /Script/Phoenix.UIBlueprintFunctionLibrary")
	end
	if status.phoenixBlueprintLibrary ~= nil and status.phoenixBlueprintLibrary:CanUseBroom(true) then
		if status.gadgetWheelWidget == nil then
			status.gadgetWheelWidget = uevrUtils.find_default_instance("WidgetBlueprintGeneratedClass /Game/UI/GadgetWheel/UI_BP_GadgetWheel.UI_BP_GadgetWheel_C")
		end
		if status.gadgetWheelWidget ~= nil then
			local found = {}
			local itemName = {}
			local holder = uevrUtils.fname_from_string("ActiveBroom")
			status.gadgetWheelWidget:FindSlottedBroomMountItem(holder, found, itemName)
			if found.result then
				pawn:LoadInventoryItemByName(itemName.result, holder)
				pawn:UseInventoryItemByName(itemName.result, holder)
			end
		end
	end
end

local function castUpGraphorn(pawn)
	if status.phoenixBlueprintLibrary == nil then
		status.phoenixBlueprintLibrary = uevrUtils.find_default_instance("Class /Script/Phoenix.UIBlueprintFunctionLibrary")
	end
	if status.phoenixBlueprintLibrary ~= nil and status.phoenixBlueprintLibrary:CanUseGraphorn() then
		local graphorn = uevrUtils.fname_from_string("GraphornMount")
		local holder = uevrUtils.fname_from_string("ActorBackpack")
		pawn:LoadInventoryItemByName(graphorn, holder)
		pawn:UseInventoryItemByName(graphorn, holder)
	end
end

local function castUpHippogriff(pawn)
	if status.phoenixBlueprintLibrary == nil then
		status.phoenixBlueprintLibrary = uevrUtils.find_default_instance("Class /Script/Phoenix.UIBlueprintFunctionLibrary")
	end
	if status.phoenixBlueprintLibrary ~= nil and status.phoenixBlueprintLibrary:CanUseHippogriff() then
		if status.gadgetWheelWidget == nil then
			status.gadgetWheelWidget = uevrUtils.find_default_instance("WidgetBlueprintGeneratedClass /Game/UI/GadgetWheel/UI_BP_GadgetWheel.UI_BP_GadgetWheel_C")
		end
		if status.gadgetWheelWidget ~= nil then
			local found = {}
			local itemName = {}
			local holder = uevrUtils.fname_from_string("ActiveFlyingMount")
			status.gadgetWheelWidget:FindSlottedBroomMountItem(holder, found, itemName)
			if found.result then
				pawn:LoadInventoryItemByName(itemName.result, holder)
				pawn:UseInventoryItemByName(itemName.result, holder)
			end
		end
	end
end

--tool records that report IsLoaded() == false until their tool class is loaded
local creatureToolClasses = {
	CreatureFeedToolRecord = "BlueprintGeneratedClass /Game/Gameplay/ToolSet/Items/InventoryItems/CreatureFeed/BP_FeedTool_CreatureFeed.BP_FeedTool_CreatureFeed_C",
	CreaturePettingBrushToolRecord = "BlueprintGeneratedClass /Game/Gameplay/Nurturing/Creatures/Blueprints/Petting/BP_CreaturePettingTool.BP_CreaturePettingTool_C",
	CaptureDeviceToolRecord = "BlueprintGeneratedClass /Game/Gameplay/Nurturing/Creatures/Blueprints/CreatureCapture/CaptureDevice/BP_Capture_Device_New.BP_Capture_Device_New_C",
}

local function endCurrentTool(tool)
	if tool == status.currentTool then
		tool:EndItemUsage()
		status.currentTool, status.feedCan = nil, nil
	end
end

-- Read once on activation; reading GraphornFeedCan off the tool every frame throws once the game has destroyed the can
function M.getCreatureFeedCan()
	return uevrUtils.getValid(status.feedCan)
end

local function castCreatureSpell(pawn, toolName)
	local inventoryToolSet = pawn.InventoryToolSetComponent
	if inventoryToolSet == nil then
		M.print("Inventory Toolset component not available")
		return
	end
	inventoryToolSet:ClearActiveTool()
	for _, toolRecord in pairs(inventoryToolSet:GetToolRecords() or {}) do
		if toolRecord.LookupName:to_string() == toolName then
			if not toolRecord:IsLoaded() then
				local fullName = toolRecord:get_full_name()
				for recordClass, toolClass in pairs(creatureToolClasses) do
					if string.find(fullName, recordClass, 1, true) then
						uevrUtils.getLoadedAsset(toolClass)
						break
					end
				end
			end
			if not inventoryToolSet:IsToolUsageAllowed(toolRecord) then
				M.print("Tool not unlocked")
				return
			end
			inventoryToolSet:AsyncLoadToolByName(toolRecord.LookupName)
			local tool = inventoryToolSet:ActivateTool(toolRecord)
			if tool == nil then
				M.print("Could not activate tool")
				return
			end
			tool:BeginItemUsage()
			status.currentTool, status.feedCan = tool, tool.GraphornFeedCan
			M.print("Tool activated: " .. tool:get_full_name())
			-- fallback: feed/pet may never start an interaction (no creature in range), so OnInteractionEnded never fires
			if tool.OnInteractionEnded ~= nil then
				delay(math.max(tool.MaxUsageTime, 3) * 1000, function() endCurrentTool(tool) end)
			end
			return
		end
	end
	M.print("Tool not found")
end

hook_function("Class /Script/Phoenix.CreatureInteractionTool", "OnInteractionEnded", true, nil,
	function(fn, obj, locals, result) endCurrentTool(obj) end
)
-- ECaptureState: 4 Succeeded, 6 Cancelled, 7 Interrupted, 8 Failing
hook_function("Class /Script/Phoenix.CaptureDeviceItemTool", "OnCaptureStateChanged", true, nil,
	function(fn, obj, locals, result)
		local s = locals.NewState
		if s == 4 or s == 6 or s == 7 or s == 8 then endCurrentTool(obj) end
	end
)

--ITEM_CaptureDevice - Sanctuaria, S (replace transformation with something else)
--ITEM_CreatureFeed - Nutritio, U left to right
--Item_CreaturePettingBrush - Placato, sideways figure 8
local function castSpellByName(pawn, spellName, muteVoice)
	local wand = getWand(pawn)
	if spellName ~= nil and spellName ~= "" and wand ~= nil then

		local mute = muteVoice
		if mute == nil then mute = status.muteSpellVoice end
		mute = mute == true

		--special case handlers that the game doesnt handle on its own
		if spellName == "Spell_Petrificus" or spellName == "Spell_Sanctuarium" or spellName == "Spell_Nutritio" or spellName == "Spell_Placato" then
			status.currentFlickSpellName = spellName
		end
		if spellName == "Spell_Alohomora" then
			if mute then 
				beginSpellVoiceSuppress(pawn, 2000)
			end
			castAlohomora(pawn)
			return
		elseif spellName == "Spell_Petrificus" then
			castPetrificus(pawn)
			return
		elseif spellName == "Spell_Viaspecto" then
			castViaspecto(pawn)
			return
		elseif spellName == "Spell_Tormentum" then
			castTormentum(pawn)
			return
		elseif spellName == "Spell_Oppugno" then
			castOppugno(pawn)
			return
		elseif spellName == "Spell_UpBroom" then
			castUpBroom(pawn)
			return
		elseif spellName == "Spell_UpGraphorn" then
			castUpGraphorn(pawn)
			return
		elseif spellName == "Spell_UpHippogriff" then
			castUpHippogriff(pawn)
			return
		elseif spellName == "Spell_Sanctuarium" then
			castCreatureSpell(pawn, "ITEM_CaptureDevice")
			return
		elseif spellName == "Spell_Nutritio" then
			castCreatureSpell(pawn, "ITEM_CreatureFeed")
			return
		elseif spellName == "Spell_Placato" then
			castCreatureSpell(pawn, "Item_CreaturePettingBrush")
			return
		end

		M.print("Casting spell by name " .. spellName)
		if string.sub(spellName, 1, 6) == "Spell_" then -- this is a spell call
			if spellName == "Spell_PewPew" then
				castPewPew(pawn)
				local currentActiveSpell = wand:GetActiveSpellTool()
				status.currentFlickSpell = currentActiveSpell
				status.currentFlickSpellName = nil
			else
				local toolsetComponent = wand.ToolSetComponent
				if toolsetComponent ~= nil and toolsetComponent.GetToolRecords ~= nil then
					local toolRecords = toolsetComponent:GetToolRecords()
					for index, spellToolRecord in pairs(toolRecords) do
						local lookupName = spellToolRecord.LookupName:to_string()
						if lookupName == spellName then
							M.print("Found spell tool record for " .. lookupName .. " ")
							local isUnlocked = isSpellAvailable(spellToolRecord) --spellManager:IsUnlocked(spellToolRecord.LookupName)
							M.print(lookupName .. " is unlocked: " .. (isUnlocked and "true" or "false"))
							if isUnlocked then
								if mute then
									beginSpellVoiceSuppress(pawn, 2000)
								end
								if lookupName == "Spell_Conjuration" or lookupName == "Spell_Transformation" or lookupName == "Spell_Vanishment" then
									M.slotEditSpell(string.sub(lookupName, 7))
								end
								wand:CancelCurrentSpell()
								local spellTool = wand:ActivateSpellTool(spellToolRecord, true)
								if spellTool ~= nil then
									if not castSpellNoAnim(pawn, spellTool) then
										wand:CastActiveSpell()
										--castChannelingSpellWhileMoving(pawn, spellTool, function() return wand:CastActiveSpell() end)
									end
									--print("Casting spell complete","\n")
									status.currentFlickSpell = spellTool
									status.currentFlickSpellName = nil
								end
								break
							end
						end
					end
				else
					M.print("Spell Toolset component not available")
				end
			end
		else -- this is a use item call
			--castCreatureSpell(pawn, spellName)

            -- local inventoryToolSet = pawn.InventoryToolSetComponent
            -- if inventoryToolSet ~= nil then
            --     inventoryToolSet:ClearActiveTool()
            --     local toolRecords = inventoryToolSet:GetToolRecords()
            --     if toolRecords ~= nil then
            --         local found = false
            --         local toolName = spellName
            --         for index, toolRecord in pairs(toolRecords) do
            --             local lookupName = toolRecord.LookupName:to_string()
            --             if lookupName == toolName then
            --                 M.print("Found tool lookup name for " .. toolRecord:get_full_name() .. "\tisLoaded: " .. (toolRecord:IsLoaded() and "true" or "false"))
            --                 --toolRecord:IsLoaded() is false when tool wont activate. How to load tool record? AsyncLoadToolByName doesnt seem to work
            --                 if toolRecord:IsLoaded() == false then
            --                     local name = ""
            --                     if string.find(toolRecord:get_full_name(), "CreatureFeedToolRecord") then
            --                         name = "BlueprintGeneratedClass /Game/Gameplay/ToolSet/Items/InventoryItems/CreatureFeed/BP_FeedTool_CreatureFeed.BP_FeedTool_CreatureFeed_C"
            --                     elseif string.find(toolRecord:get_full_name(), "CreaturePettingBrushToolRecord") then
            --                         name = "BlueprintGeneratedClass /Game/Gameplay/Nurturing/Creatures/Blueprints/Petting/BP_CreaturePettingTool.BP_CreaturePettingTool_C"
            --                     elseif string.find(toolRecord:get_full_name(), "CaptureDeviceToolRecord") then
            --                         name = "BlueprintGeneratedClass /Game/Gameplay/Nurturing/Creatures/Blueprints/CreatureCapture/CaptureDevice/BP_Capture_Device_New.BP_Capture_Device_New_C"
            --                     elseif string.find(toolRecord:get_full_name(), "HippogriffMountToolRecord") then
            --                         --This code works but lib:CanUseHippogriff() returns true even when youre too low a level so for now going
            --                         --to stick with if default way to summon is used one then can use gestures after
            --                         -- local lib = uevrUtils.find_first_instance("Class /Script/Phoenix.UIBlueprintFunctionLibrary", true)
            --                         -- if lib ~= nil and lib:CanUseHippogriff() then
            --                             -- name = "BlueprintGeneratedClass /Game/Gameplay/Nurturing/Creatures/Blueprints/Mounts/BP_HippogriffMountTool.BP_HippogriffMountTool_C"
            --                         -- else
            --                             -- uevrUtils.print("Can't use Hippogriff yet")
            --                         -- end

            --                         --this will also mount the hippo without needing the code above but also doesnt check for too low level
            --                         --local tool = uevrUtils.getLoadedAsset("BlueprintGeneratedClass /Game/Gameplay/Nurturing/Creatures/Blueprints/Mounts/BP_HippogriffMountTool.BP_HippogriffMountTool_C")
            --                         --tool:SpawnAndMountCreature(true, false)
            --                     end

            --                     if name ~= "" then
            --                         local tool = uevrUtils.getLoadedAsset(name)
            --                     end
            --                 end
            --                 found = true
            --                 local isUnlocked = inventoryToolSet:IsToolUsageAllowed(toolRecord)
            --                 if isUnlocked then
            --                     -- local currentTool = inventoryToolSet:ClearActiveTool() -- inventoryToolSet:GetActiveTool()
            --                     -- if currentTool ~= nil then
            --                         -- print("Current active tool is",currentTool:get_full_name(),"\n")
            --                         -- currentTool:EndItemUsage()
            --                         -- currentTool:UnequipTool()                                    
            --                     -- end
            --                     inventoryToolSet:AsyncLoadToolByName(toolRecord.LookupName)
            --                     local tool =  inventoryToolSet:ActivateTool(toolRecord)
            --                     if tool ~= nil then
            --                         tool:BeginItemUsage()
            --                         status.currentTool = tool
            --                         M.print("Tool activated: " .. tool:get_full_name())
            --                         delay(3000, function()
            --                             status.currentTool:EndItemUsage()
            --                             --pawn:RevertSpeedMode()
            --                             --pawn:SetSpeedMode()
            --                             M.print("Tool usage ended: " .. status.currentTool:get_full_name())
            --                             status.currentTool = nil
            --                         end)
            --                     else
            --                         --inventoryToolSet:AsyncLoadToolByName(toolRecord.LookupName)
            --                         --toolRecord:LoadComplete(toolRecord)
            --                         --toolRecord:LoadComplete()
            --                         M.print("Could not activate tool")
            --                     end
            --                 else
            --                     M.print("Tool not unlocked")
            --                 end
            --                 break
            --             end
            --         end
            --         if not found then
            --             M.print("Tool not found")
            --         end
            --     else
            --         M.print("Inventory Toolset toolrecords not available")
            --     end
            -- else
            --     M.print("Inventory Toolset component not available")
            -- end
		end
	end
end

function M.castSpell(pawn, spellName, muteVoice)
	castSpellByName(pawn, spellName, muteVoice)
end

uevrUtils.registerOnPreInputGetStateCallback(function(retval, user_index, state)
	if status.isAlohomoraCasting or status.isPetrificusCasting then
		uevrUtils.pressButton(state, XINPUT_GAMEPAD_X)
		status.isAlohomoraCasting = false
		status.isPetrificusCasting = false
	end
	if status.isViaspectoCasting then
		uevrUtils.pressButton(state, XINPUT_GAMEPAD_DPAD_UP)
		status.isViaspectoCasting = false
	end
	if status.isTormentumCasting then
		uevrUtils.pressButton(state, XINPUT_GAMEPAD_LEFT_SHOULDER)
		uevrUtils.pressButton(state, XINPUT_GAMEPAD_RIGHT_SHOULDER)
		delay(200, function()
			status.isTormentumCasting = false
		end)
	end
	if status.isOppugnoCasting then
		uevrUtils.pressButton(state, XINPUT_GAMEPAD_RIGHT_SHOULDER)
		delay(200, function()
			status.isOppugnoCasting = false
		end)
	end
end)

-- While Wingardium is holding, pin the target to the wand ray.
local function updateWingardiumWandHoldFullControl()
	local wand = getWand(pawn)
	local tool = wand and wand:GetActiveSpellTool()
	if tool == nil or tool.AdjustWingardiumHeight == nil or not tool:IsChanneling() then
		status.wingardiumHoldDist = nil
		return
	end
	local target = tool:GetActiveTarget()
	local mesh = uevrUtils.getValid(wand, {"Mesh"})
	local prim = target and target.RootComponent
	if prim == nil or mesh == nil then
		status.wingardiumHoldDist = nil
		return
	end
	local origin = mesh:K2_GetComponentLocation()
	local dir = mesh:GetUpVector()
	if status.wingardiumHoldDist == nil then
		local loc = prim:K2_GetComponentLocation()
		local dx, dy, dz = loc.X - origin.X, loc.Y - origin.Y, loc.Z - origin.Z
		status.wingardiumHoldDist = math.sqrt(dx * dx + dy * dy + dz * dz)
	end
	local d = status.wingardiumHoldDist
	prim:K2_SetWorldLocation(uevrUtils.vector(origin.X + dir.X * d, origin.Y + dir.Y * d, origin.Z + dir.Z * d), false, reusable_hit_result, true)
	if noneBone == nil then noneBone = uevrUtils.fname_from_string("None") end
	prim:SetPhysicsLinearVelocity(uevrUtils.vector(0, 0, 0), false, noneBone)
end

-- While Wingardium is holding, pin XY to the wand; leave Z to native stick height.
local function updateWingardiumWandHold()
	status.isWingardiumHolding = false
	local wand = getWand(pawn)
	local tool = wand and wand:GetActiveSpellTool()
	if tool == nil or tool.AdjustWingardiumHeight == nil or not tool:IsChanneling() then
		status.wingardiumHoldDist = nil
		return
	end
	local target = tool:GetActiveTarget()
	local mesh = uevrUtils.getValid(wand, {"Mesh"})
	local prim = target and target.RootComponent
	if prim == nil or mesh == nil then
		status.wingardiumHoldDist = nil
		return
	end
	local origin = mesh:K2_GetComponentLocation()
	local dir = mesh:GetUpVector()
	local loc = prim:K2_GetComponentLocation()
	local fx, fy = dir.X, dir.Y
	local flen2 = fx * fx + fy * fy
	if flen2 < 0.0001 then return end
	if status.wingardiumHoldDist == nil then
		local dx, dy = loc.X - origin.X, loc.Y - origin.Y
		status.wingardiumHoldDist = math.sqrt(dx * dx + dy * dy)
	end
	local scale = status.wingardiumHoldDist / math.sqrt(flen2)
	prim:K2_SetWorldLocation(uevrUtils.vector(origin.X + fx * scale, origin.Y + fy * scale, loc.Z), false, reusable_hit_result, true)
	status.isWingardiumHolding = true
	-- if noneBone == nil then noneBone = uevrUtils.fname_from_string("None") end
	-- local vel = prim:GetPhysicsLinearVelocity(noneBone)
	-- prim:SetPhysicsLinearVelocity(uevrUtils.vector(0, 0, vel and vel.Z or 0), false, noneBone)
end
function M.isWingardiumHolding()
	return status.isWingardiumHolding == true
end

uevrUtils.registerPostEngineTickCallback(updateWingardiumWandHold)

------------------- Room of Requirement spell slotting -------------------
-- Room of Requirement only highlights/targets for Conjuration/Transformation/Vanishment when it is on the active spell page.
-- This is needed so Alterations in Room of Requirement allow the item highlights to be controlled by the wand
-- We could also run this outside of the Room of requirement but then pawn motion would
-- always be "follows wand direction"
local function setTargetingCameraRotation(pawn)
	--print(status.capturableCreatureInRange)
	if isInRoomOfRequirement() or (status.capturableCreatureInRange and mounts.isWalking()) then
		local mesh = uevrUtils.getValid(M.getWand(pawn), {"Mesh"})
		if mesh ~= nil and pawn.SetPhoenixCameraRotation ~= nil and M.isWandDrawn(pawn) then
			pawn:SetPhoenixCameraRotation(kismet_math_library:Conv_VectorToRotator(mesh:GetUpVector()))
		end
	end
end
function M.setTargetingCameraRotation(pawn)
	setTargetingCameraRotation(pawn)
end

function M.slotEditSpell(spellID)
	if not isInRoomOfRequirement() then return end
	status.quickActions = uevrUtils.getValid(status.quickActions) or uevrUtils.find_first_of("Class /Script/Phoenix.QuickActionManager", false)
	local qa = status.quickActions
	if qa == nil then return end
	local group = qa:GetActiveGroupIndex()
	local out = {}
	qa:GetItemName(group, 0, 0, out)
	local current = out.result and out.result:to_string() or ""
	if current == spellID then return end
	if status.editSlotRestore == nil then
		status.editSlotRestore = { group = group, item = current == "None" and "" or current }
	end
	qa:SlotSpellFromCode(spellID, 0, group)
end
-- Put back whatever slotEditSpell replaced once no Conjuration/Transformation/Vanishment tool is active.
setInterval(1000, function()
	local saved = status.editSlotRestore
	if saved == nil then return end
	status.transfigurationClass = status.transfigurationClass or uevrUtils.find_required_object("Class /Script/Phoenix.TransfigurationSpellToolBase")
	local wand = getWand(pawn)
	local tool = wand and wand:GetActiveSpellTool()
	if tool ~= nil and tool:is_a(status.transfigurationClass) then return end
	local qa = uevrUtils.getValid(status.quickActions)
	if qa == nil then return end
	qa:SlotSpellFromCode(saved.item, 0, saved.group)
	local out = {}
	qa:GetItemName(saved.group, 0, 0, out)
	local current = out.result and out.result:to_string() or ""
	if current == (saved.item == "" and "None" or saved.item) then status.editSlotRestore = nil end
end)
------------------- End room of requirement spell slotting -------------------


------------------- Feed Pellet animations -------------------
-- Feed pellets are animated toward the hidden body mesh hands. Fly them from the feed can (left controller)
-- to the right controller in an arc, then release them to the creature from the right controller.
local PELLET_FLIGHT_TIME = 0.5 -- seconds, roughly the game's can-to-hand phase
local PELLET_CAN_OFFSET = 20 -- cm along the left controller's up axis
local PELLET_ARC_HEIGHT = 20 -- cm

-- Moves the pellet actor so the pellets' average location lands on the given world position
local function placePellets(obj, x, y, z)
	local avg, loc = obj.FeedFloatingComponent:GetAveragePelletLocation(), obj:K2_GetActorLocation()
	obj:K2_SetActorLocation(uevrUtils.vector(x + loc.X - avg.X, y + loc.Y - avg.Y, z + loc.Z - avg.Z), false, reusable_hit_result, true)
end

local function updatePelletFlight(deltaTime)
	local flight = status.pelletFlight
	if flight == nil then return end
	local obj = uevrUtils.getValid(flight.actor)
	local can = controllers.getControllerLocation(Handed.Left)
	local up = controllers.getControllerUpVector(Handed.Left)
	local hand = controllers.getControllerLocation(Handed.Right)
	if obj == nil or obj.FeedFloatingComponent == nil or can == nil or up == nil or hand == nil then
		status.pelletFlight = nil
		return
	end
	flight.elapsed = flight.elapsed + deltaTime
	local t = math.min(flight.elapsed / PELLET_FLIGHT_TIME, 1)
	local sx, sy, sz = can.X + up.X * PELLET_CAN_OFFSET, can.Y + up.Y * PELLET_CAN_OFFSET, can.Z + up.Z * PELLET_CAN_OFFSET
	placePellets(obj, sx + (hand.X - sx) * t, sy + (hand.Y - sy) * t, sz + (hand.Z - sz) * t + math.sin(math.pi * t) * PELLET_ARC_HEIGHT)
end

hook_function("Class /Script/Phoenix.CreatureFeed", "InitializeRelease", true, nil, function(fn, obj, locals, result)
	status.pelletFlight = { actor = obj, elapsed = 0 }
	updatePelletFlight(0)
end)

hook_function("Class /Script/Phoenix.CreatureFeed", "FloatToCreature", true,
	function(fn, obj, locals, result)
		status.pelletFlight = nil
		local hand = controllers.getControllerLocation(Handed.Right)
		if hand ~= nil and obj.FeedFloatingComponent ~= nil then placePellets(obj, hand.X, hand.Y, hand.Z) end
	end,
	nil
)
------------------- End Feed Pellet animations -------------------

-- fixes wand aim to use where the wand points
-- Keep the native call so Blueprint callers consume EX_EndFunctionParms before we override its result.
hook_function( "Class /Script/Phoenix.Biped_Character", "GetTargetDestination", true, -- native often needed so `result` is the real out buffer
  nil,
  function(fn, obj, locals, result)
	if obj == pawn then
		local aim = M.getWandAim(pawn)
		if aim then
			plugin.writeHookResult(fn, result, aim)
		end
	end
  end
)

hook_function("Class /Script/Phoenix.Biped_Player", "GetAutoTargetFocusDirection", true,
  nil,
  function(fn, obj, locals, result)
	--print("GetAutoTargetFocusDirection")
    local mesh = uevrUtils.getValid(getWand(pawn), {"Mesh"})
    if mesh ~= nil then
      plugin.writeHookResult(fn, result, mesh:GetUpVector())
    end
  end
)

------------------------ Spell Screen Hover Handlers ------------------------
local spellNameIcons = {}
spellNameIcons["Expulso"] = "Bombarda"
spellNameIcons["CreatureFeed"] = "Nutritio"
spellNameIcons["CreaturePettingBrush"] = "Placato"
spellNameIcons["CaptureDevice"] = "Sanctuarium"
spellNameIcons["AncientMagic"] = "Tormentum"

local spellNameExpressions = {}
spellNameExpressions["Conjuration"] = "Fabricaste"
spellNameExpressions["Transformation"] = "Mutatio"
spellNameExpressions["Vanishment"] = "Evanesco"
spellNameExpressions["CreatureFeed"] = "Nutritio"
spellNameExpressions["CreaturePettingBrush"] = "Placato"
spellNameExpressions["CaptureDevice"] = "Sanctuarium"
spellNameExpressions["TransformationOverland"] = "Transformus"
spellNameExpressions["Disillusionment"] = "Obscura"
spellNameExpressions["Petrificus"] = "Petrificus Totalis"
spellNameExpressions["AncientMagic"] = "Tormentum"
spellNameExpressions["BasicCast"] = ""
spellNameExpressions["Stupefy"] = ""
spellNameExpressions["Protego"] = ""

--Riddikulus

local function onSpellHover(spell)
	if status.currentSpellIcon == nil then return end
	if spell == nil or spell == "" then return end
	-- get rid of the GD hidden null character in the spell name
	spell = tostring(spell):gsub("%z", "")
	spell = spellNameIcons[spell] or spell
	if spell ~= "" and spell ~= status.hoveredSpellName then
		uevrUtils.print("onSpellHover " .. spell)
		status.hoveredSpellName = spell
		status.currentSpellIcon:setTexture(spell .. ".png")
		if status.currentSpellText ~= nil then
			status.currentSpellText:setText(spellNameExpressions[spell] or spell)
		end
	end
end

local function onSpellUnhover(spell)
	if status.currentSpellIcon == nil then return end
	if spell ~= nil and spell ~= "" then
		spell = tostring(spell):gsub("%z", "")
		if spell ~= "" and spell ~= status.hoveredSpellName then return end
	end
	status.hoveredSpellName = nil
	if status.currentSpellIcon.image ~= nil then
		status.currentSpellIcon.image:SetVisibility(1) -- Collapsed
		if status.currentSpellText ~= nil then
			status.currentSpellText:setText("")
		end

	end
end

-- CurrentHighlightedItem lags until help popup and often stays set after leave.
-- Essentials: HoveredItem + IsItemHovering. Grid spells: ItemScrollBox ButtonHovered.
-- Essential ItemId is not the spell name (Stupefy is "StupefySpecial_Send"); the widget's object name is.
local function syncEssentialHoverFromSelection()
	if status.currentSpellIcon == nil or status.actionSelectionWidget == nil then return end
	local sel = status.actionSelectionWidget
	local name = nil
	for _, screen in ipairs({ sel.ActionSelection_MKB, sel.ActionSelection_Controller }) do
		-- if screen ~= nil and screen.isItemHovering and screen.HoveredItem ~= nil then
        --     local id = screen.HoveredItem.ItemId
        --     if id ~= nil and id ~= "" then
        --         name = id
        --         break
        --     end
		-- FName casing of this property varies between game sessions
		if screen ~= nil and (screen.isItemHovering or screen.IsItemHovering) and screen.HoveredItem ~= nil then
			name = screen.HoveredItem:get_fname():to_string()
			break
		end
	end
	if name ~= nil then
		name = tostring(name):gsub("%z", "")
		status.hoverFromEssential = true
		if name ~= "" and name ~= status.hoveredSpellName then
			onSpellHover(name)
		end
	elseif status.hoverFromEssential then
		status.hoverFromEssential = false
		onSpellUnhover()
	end
end

------------------------ End Spell Screen Hover Handlers --------------------


local function hookLevelFunctions()
	hook_function(
		"WidgetBlueprintGeneratedClass /Game/UI/Common/UI_BP_ItemScrollBox.UI_BP_ItemScrollBox_C", "ButtonHovered", false, nil,
		function(fn, obj, locals, result)
			local button = locals and locals.Button
			status.hoverFromEssential = false
			onSpellHover(button and button.IconName)
		end, false)

	hook_function(
		"WidgetBlueprintGeneratedClass /Game/UI/Common/UI_BP_ItemScrollBox.UI_BP_ItemScrollBox_C", "ButtonUnhovered", false, nil,
		function(fn, obj, locals, result)
			local button = locals and locals.Button
			onSpellUnhover(button and button.IconName)
		end, false)
end

ui.registerWidgetChangeCallback("UI_BP_ActionSelection_PC_C", function(active, widget)
	if active then
		status.actionSelectionWidget = widget
		status.currentSpellIcon = widgetModule.Image.new(300)
		status.currentSpellIcon:addToWidget(widget, { align = widgetModule.Image.ALIGN.BOTTOM_RIGHT, offset = uevrUtils.vector2D(-170, -100)})
		status.currentSpellText = widgetModule.Text.new("")
		status.currentSpellText:addToWidget(widget, { align = widgetModule.Text.ALIGN.BOTTOM_RIGHT, alignment = uevrUtils.vector2D(0.5, 0), offset = uevrUtils.vector2D(-320, -115)})
		status.currentSpellText:setColor("#F9C046FF")
		status.currentSpellText:setFontSize(20)
		status.currentSpellText:setFont(nil, "Regular")
		status.hoveredSpellName = nil
		status.hoverFromEssential = false
	elseif status.currentSpellIcon ~= nil then
		status.currentSpellIcon:remove()
		status.currentSpellIcon = nil
		status.currentSpellText:remove()
		status.currentSpellText = nil
		status.actionSelectionWidget = nil
		status.hoveredSpellName = nil
		status.hoverFromEssential = false
	end
end)


uevr.sdk.callbacks.on_pre_engine_tick(function(engine, deltaTime)
	updatePelletFlight(deltaTime)
	syncEssentialHoverFromSelection()
end)

M.reset = function()
	status = {}
end
uevr.params.sdk.callbacks.on_script_reset(function()
	M.reset()
end)
uevrUtils.registerLevelChangeCallback(function(level)
	M.reset()
	hookLevelFunctions()
end, 1)

return M
