

local uevrUtils = require('libs/uevr_utils')
local input = require('libs/input')
local controllers = require('libs/controllers')
local plugin = require('libs/core/plugin')
local mounts = require('helpers/mounts')

local M = {}
local status = {}
local EMPTY_NAME = uevrUtils.fname_from_string("")
-- Abilities whose motion adjust steers the body mesh to a world target. While one is active (enabled = true),
-- the view carries the head-alignment offset instead of the mesh, so the capsule lands where the game intends,
-- but the view follows the animation's head sway. Matched by substring in order; the first match wins.
local meshOffsetOnCameraAbilities = {
	{ prefix = "ABL_ClimbLadder_MountTop", enabled = true }, -- required: otherwise the mount ends at floor height
	{ prefix = "ABL_ClimbLadder_", enabled = false }, -- rest of the ladder
	{ prefix = "ABL_Climb", enabled = false }, -- ledge climbs and mantles
	{ prefix = "ABL_JumpVault", enabled = false },
	{ prefix = "ABL_SwimClimbLedge", enabled = false },
	{ prefix = "ABL_OpenChest", enabled = false },
	{ prefix = "ABL_TeeterOnEdge", enabled = false },
}

-- Kept outside status: cleanup() clears status on every level change, and hook_ptr adds another callback on every call.
local cameraShakeHooksInstalled = false

local function disableCameraShakes(currentPawn)
	if status.cameraShakesDisabled then
		return
	end

	local playerCameraManager = uevrUtils.getValid(currentPawn, {"Controller", "PlayerCameraManager"})
	if playerCameraManager ~= nil then
		local cameraShakeModifier = uevrUtils.getValid(playerCameraManager, {"CachedCameraShakeMod"})
		if cameraShakeModifier ~= nil and cameraShakeModifier.DisableModifier ~= nil then
			cameraShakeModifier:DisableModifier(true)
		end
	end

	if playerCameraManager ~= nil and playerCameraManager.StopAllCameraShakes ~= nil then
		playerCameraManager:StopAllCameraShakes(true)
	end

	local gameEngine = uevrUtils.find_first_of("Class /Script/Engine.GameEngine")
	local gameSettings = uevrUtils.getValid(gameEngine, {"GameUserSettings"})
	if gameSettings ~= nil then
		if gameSettings.SetCameraShake ~= nil then
			gameSettings:SetCameraShake(0.0)
		end
		if gameSettings.SetCineCameraShake ~= nil then
			gameSettings:SetCineCameraShake(false)
		end
		if gameSettings.CameraSettings ~= nil then
			local cameraSettings = gameSettings.CameraSettings
			cameraSettings.CameraShake = 0.0
			cameraSettings.bCineCameraShake = false
			gameSettings.CameraSettings = cameraSettings
		end
	end

	--does this do anything?
	-- local tasks = uevrUtils.find_all_instances("Class /Script/AbleCore.AblCamShakeTask", true)
	-- if tasks ~= nil then
	-- 	for _, task in pairs(tasks) do
	-- 		if uevrUtils.getValid(task) ~= nil then
	-- 			task.Shake = nil
	-- 		end
	-- 	end
	-- end

	if not cameraShakeHooksInstalled then
		local function blockShake()
			return true
		end
		hook_function("Class /Script/Engine.PlayerCameraManager", "StartCameraShake", true, blockShake, nil, false)
		hook_function("Class /Script/Engine.PlayerCameraManager", "StartCameraShakeFromSource", true, blockShake, nil, false)
		hook_function("Class /Script/Engine.PlayerController", "ClientStartCameraShake", true, blockShake, nil, false)
		hook_function("Class /Script/Engine.PlayerController", "ClientStartCameraShakeFromSource", true, blockShake, nil, false)
		cameraShakeHooksInstalled = true
	end

	status.cameraShakesDisabled = true
end

local function isNativeSprintActive(currentPawn)
	-- Sprint state can carry over into a mount, where forcing body yaw from the HMD would feed back through the view.
	return mounts.isWalking() and (status.L3Pressed or (status.pawnHasSpeedModifier and currentPawn:IsUsingSpeedModifier()))
end

-- Keep native Ambulatory locomotion, but use its strafe variants in first person.
local function neutralizeStrafeTurnAssist()
	if status.strafeTurnAssistNeutralized then
		return
	end
	local instances = uevrUtils.find_all_instances("Class /Script/Phoenix.RootMotionModifierProperties_TurnAssist", true)
	if instances == nil then
		return
	end
	for _, props in pairs(instances) do
		if uevrUtils.getValid(props) ~= nil then
			local name = props:get_full_name()
			if name ~= nil and string.find(name, "ABL_Strafe", 1, true) ~= nil then
				if props.RegularSpeedRotationInterpSpeed ~= nil then
					props.RegularSpeedRotationInterpSpeed = 0
				end
				if props.LowSpeedRotationInterpSpeed ~= nil then
					props.LowSpeedRotationInterpSpeed = 0
				end
				if props.SpringHalflife ~= nil then
					props.SpringHalflife = 0
				end
			end
		end
	end
	status.strafeTurnAssistNeutralized = true
end

-- ABL_DodgeRoll fires ToggleDodgeCamera; disable that camera style once.
local function neutralizeDodgeCamera()
	if status.dodgeCameraNeutralized then
		return
	end
	local tasks = uevrUtils.find_all_instances("Class /Script/AbleCore.AblBTCustomActionTask", true)
	if tasks == nil then
		return
	end
	local cleared = 0
	for _, task in pairs(tasks) do
		if uevrUtils.getValid(task) ~= nil and task.BTCustomAction ~= nil then
			local action = task.BTCustomAction
			local actionName = action.ActionName
			if actionName ~= nil and string.find(tostring(actionName), "ToggleDodgeCamera", 1, true) ~= nil then
				action.ActionName = uevrUtils.fname_from_string("None")
				cleared = cleared + 1
			end
		end
	end
	if cleared > 0 then
		status.dodgeCameraNeutralized = true
	end
end

local function configureShadowBlinkModifier()
	if status.shadowBlinkModifierConfigured then return end
	local props = uevrUtils.find_all_instances("Class /Script/Phoenix.RootMotionModifierProperties_DodgeRoll", true)
	if props == nil then return end
	for _, modifier in pairs(props) do
		if uevrUtils.getValid(modifier) ~= nil then
			local name = modifier:get_full_name()
			if name ~= nil and string.find(name, "ABL_ShadowBlink.Default__ABL_ShadowBlink_C", 1, true) ~= nil then
				modifier.bShadowBlinkWithTarget = true
				modifier.RotationInterpSpeed = 4
				status.shadowBlinkModifierConfigured = true
				return
			end
		end
	end
end

-- StrafeMove_Start normally blends the outgoing dodge's root motion into its
-- own start animation. After a dodge that outgoing motion takes a forward step
-- even when DesiredWorldDirection already points backward or sideways.
local function configureDodgeRecovery()
	if status.dodgeRecoveryConfigured then return end
	local task = uevrUtils.getValid(uevrUtils.find_required_object("AblPlayAnimationArchitectTask /Game/Pawn/Student/Abilities/Locomotion/ABL_StrafeMove_Start.Default__ABL_StrafeMove_Start_C.AblPlayAnimationArchitectTask_0"))
	if task == nil then return end
	plugin.setProperty(task, "m_RootMode.m_UseSourceRootMotion", 1) -- ERM_NoRootMotion
	status.dodgeRecoveryConfigured = true
end

-- Shadow Blink's end animation moves the pawn forward during recovery.
-- Keep the outgoing Blink motion, drop that animation's translation, and
-- shorten the blend back into walking so the resulting pause is less noticeable.
local function configureShadowBlinkRecovery()
	if status.shadowBlinkRecoveryConfigured then return end
	local task = uevrUtils.getValid(uevrUtils.find_required_object("AblPlayAnimationArchitectTask /Game/Pawn/Student/Abilities/Locomotion/ABL_ShadowBlink_End.Default__ABL_ShadowBlink_End_C.AblPlayAnimationArchitectTask_1"))
	local walkBranch = uevrUtils.getValid(uevrUtils.find_required_object("AblBranchTask /Game/Pawn/Student/Abilities/Locomotion/ABL_ShadowBlink_End.Default__ABL_ShadowBlink_End_C.AblBranchTask_1"))
	local sprintBranch = uevrUtils.getValid(uevrUtils.find_required_object("AblBranchTask /Game/Pawn/Student/Abilities/Locomotion/ABL_ShadowBlink_End.Default__ABL_ShadowBlink_End_C.AblBranchTask_2"))
	if task == nil or walkBranch == nil or sprintBranch == nil then return end
	plugin.setProperty(task, "m_RootMode.m_UseDestRootMotion", 1) -- ERM_NoRootMotion
	plugin.setProperty(walkBranch, "m_TransitionBlend.BlendTime", 0.1)
	plugin.setProperty(sprintBranch, "m_TransitionBlend.BlendTime", 0.1)
	status.shadowBlinkRecoveryConfigured = true
end

-- Shadow Blink uses SetDodgeDirection, which copies pawn forward into the anim
-- instance. With bShadowBlinkWithTarget enabled, its root motion reads that
-- direction. Replace the forward vector with the movement stick direction.
local function getActiveAbilityName(currentPawn)
	local abl = uevrUtils.getValid(currentPawn, {"AblAbilityComponent"})
	if abl == nil or abl.GetActiveAbility_New == nil then return nil end
	local ability = abl:GetActiveAbility_New(EMPTY_NAME)
	return ability and ability:get_full_name()
end

local function isAbilityActive(abilityName, ablName)
	return abilityName ~= nil and string.find(abilityName, ablName, 1, true) ~= nil
end

local function isMeshOffsetOnCamera(abilityName)
	if abilityName == nil then return false end
	for _, entry in ipairs(meshOffsetOnCameraAbilities) do
		if string.find(abilityName, entry.prefix, 1, true) ~= nil then return entry.enabled end
	end
	return false
end

-- Full name of the pawn's active ability, read by this module's pre-engine tick.
-- That tick is registered when this module loads, so later pre-engine tick callbacks see this frame's value.
function M.getActiveAbilityName()
	return status.activeAbilityName
end

local function configureAmbulatoryFP(currentPawn, abilityName)
	if uevrUtils.getValid(currentPawn) == nil then
		return
	end

	neutralizeStrafeTurnAssist()
	--neutralizeDodgeCamera()
	configureShadowBlinkModifier()
	configureDodgeRecovery()
	configureShadowBlinkRecovery()
	disableCameraShakes(currentPawn)

	if status.locomotionPawn ~= currentPawn then
		status.locomotionPawn = currentPawn
		status.strafeFacingTarget = nil
		-- Each member check is a native reflection lookup; the pawn's class is fixed, so check them once.
		status.pawnHasSpeedModifier = currentPawn.IsUsingSpeedModifier ~= nil
		status.pawnHasForwardVector = currentPawn.GetActorForwardVector ~= nil
		status.pawnHasTurnAssist = currentPawn.bUseTurnAssist ~= nil
		status.pawnHasLockOnMode = currentPawn.bOnlyLockOnMode ~= nil
		status.pawnHasFocusDirection = currentPawn.bUseDesiredFocusDirection ~= nil
	end

	-- Ladder abilities set the pawn's yaw, including the 180-degree turn when mounting from the top.
	-- Let the game own body yaw on the ladder; input mirrors those turns into the view.
	local onLadder = isAbilityActive(abilityName, "ABL_ClimbLadder_")
	input.setBodyYawWritesSuppressed(onLadder)

	-- The head-under-HMD mesh offset would displace the capsule from motion-adjust targets (beside the ladder
	-- at floor height after MountTop). Only look the ability up in the table when it changes.
	if status.meshOffsetAbilityName ~= abilityName or status.meshOffsetOnCamera == nil then
		status.meshOffsetAbilityName = abilityName
		local meshOffsetOnCamera = isMeshOffsetOnCamera(abilityName)
		if status.meshOffsetOnCamera ~= meshOffsetOnCamera then
			input.setMeshOffsetAppliedToCamera(meshOffsetOnCamera)
			status.meshOffsetOnCamera = meshOffsetOnCamera
		end
	end

	-- Sprint only runs forward, so face the body along the stick relative to the HMD to sprint sideways without turning the view.
	local sprintYaw = nil
	local sprinting = not onLadder and isNativeSprintActive(currentPawn)
	if sprinting then
		local x, y = status.moveStickLX or 0, status.moveStickLY or 0
		if y < 5000 then
			-- Past sideways the body would turn away from the view.
			if currentPawn.IsUsingSpeedModifier ~= nil and currentPawn:IsUsingSpeedModifier() then currentPawn:SprintStop() end
		else
			local hmdRot = controllers.getControllerRotation(2)
			if hmdRot ~= nil then
				sprintYaw = hmdRot.Yaw + math.deg(math.atan(x, y))
			end
		end
	end
	input.setForcedBodyYaw(sprintYaw)

	local faceTargetTracker = uevrUtils.getValid(currentPawn, {"FaceTargetTracker"})
	local facingTarget = uevrUtils.getValid(status.strafeFacingTarget)
	if sprinting or isAbilityActive(abilityName, "ABL_DodgeRoll") then
		-- DodgeRoll steers its root motion toward the best facing target each tick.
		if faceTargetTracker ~= nil and facingTarget ~= nil and faceTargetTracker.RemoveTargetByPtr ~= nil then
			faceTargetTracker:RemoveTargetByPtr(255, facingTarget)
		end
		status.strafeFacingTarget = nil
	elseif faceTargetTracker ~= nil and status.pawnHasForwardVector then
		if facingTarget == nil and faceTargetTracker.AddTarget_StaticWorldDirection ~= nil then
			status.strafeFacingTarget = faceTargetTracker:AddTarget_StaticWorldDirection(currentPawn:GetActorForwardVector(), 255)
			if uevrUtils.getValid(status.strafeFacingTarget) ~= nil then
				if status.strafeFacingTarget.SetComputedPriority ~= nil then
					status.strafeFacingTarget:SetComputedPriority(-1000)
				end
				status.strafeFacingTargetSettable = status.strafeFacingTarget.SetStaticWorldDirection ~= nil
			end
		elseif facingTarget ~= nil and status.strafeFacingTargetSettable then
			facingTarget:SetStaticWorldDirection(currentPawn:GetActorForwardVector())
		end
	end

	if status.pawnHasTurnAssist then
		currentPawn.bUseTurnAssist = false
	end
	if status.pawnHasLockOnMode then
		currentPawn.bOnlyLockOnMode = false
	end

	if status.pawnHasFocusDirection then
		currentPawn.bUseDesiredFocusDirection = true
	end

	-- local anim = uevrUtils.getValid(currentPawn, {"Mesh", "AnimScriptInstance"})
	-- if anim ~= nil and currentPawn.SetMobilityModeState ~= nil then
	-- 	local mode = anim.MobilityModeState
	-- 	if mode == 1 then
	-- 		currentPawn:SetMobilityModeState(3) -- FreeRoam -> Strafe
	-- 	elseif mode == 2 then
	-- 		currentPawn:SetMobilityModeState(4) -- FreeRoamCombat -> StrafeCombat
	-- 	end
	-- end
end

local function getStickWorldDirection(currentPawn)
	local x = (status.moveStickLX or 0) / 32767
	local y = (status.moveStickLY or 0) / 32767
	if x * x + y * y < 0.0625 then return nil end
	local forward = currentPawn:GetActorForwardVector()
	local right = currentPawn:GetActorRightVector()
	if forward == nil or right == nil then return nil end
	local dx = forward.X * y + right.X * x
	local dy = forward.Y * y + right.Y * x
	local length = math.sqrt(dx * dx + dy * dy)
	if length < 0.001 then return nil end
	return uevrUtils.vector(dx / length, dy / length, 0)
end

local function setShadowBlinkDirection(currentPawn, direction)
	local anim = uevrUtils.getValid(currentPawn, {"Mesh", "AnimScriptInstance"})
	if anim == nil then return end
	anim.DesiredWorldDirection = direction
	anim.LastDesiredWorldDirection = direction
end


local function updateShadowBlinkDirection(currentPawn, abilityName)
	if not isAbilityActive(abilityName, "ABL_ShadowBlink") then
		status.shadowBlinkDirection = nil
		return
	end
	if status.shadowBlinkDirection == nil then
		status.shadowBlinkDirection = getStickWorldDirection(currentPawn)
	end
	if status.shadowBlinkDirection ~= nil then
		setShadowBlinkDirection(currentPawn, status.shadowBlinkDirection)
	end
end


local function onSetDodgeDirection(fn, currentPawn, locals, result)
	if currentPawn == nil then return end
	-- This runs before Shadow Blink replaces the preceding locomotion ability.
	local direction = getStickWorldDirection(currentPawn)
	if direction == nil then return end
	status.shadowBlinkDirection = direction
	setShadowBlinkDirection(currentPawn, direction)
end

hook_function("Class /Script/Phoenix.Biped_Player", "SetDodgeDirection", true, nil, function(fn, currentPawn, locals, result)
	onSetDodgeDirection(fn, currentPawn, locals, result)
end, false)

uevrUtils.registerOnPreInputGetStateCallback(function(retval, user_index, state)
    if user_index == 0 then
        status.moveStickLX = state.Gamepad.sThumbLX
        status.moveStickLY = state.Gamepad.sThumbLY
    end
	status.L3Pressed =  uevrUtils.isButtonPressed(state, XINPUT_GAMEPAD_LEFT_THUMB)
end)

uevr.sdk.callbacks.on_pre_engine_tick(function(engine, deltaTime)
    status.activeAbilityName = nil
    local pawn = uevrUtils.getValid(pawn)
    if pawn == nil then return end
    if mounts.isRidingCart() then return end --if riding the cart don't update the camera

    local abilityName = getActiveAbilityName(pawn)
    status.activeAbilityName = abilityName
    configureAmbulatoryFP(pawn, abilityName)
    updateShadowBlinkDirection(pawn, abilityName)
 end)

 setInterval(1000, function()
    --configureAmbulatoryFP(uevrUtils.getValid(pawn))
 end)

local function cleanup()
    status = {}
end

uevrUtils.registerLevelChangeCallback(function(level, levelName)
    cleanup()
    configureAmbulatoryFP(uevrUtils.getValid(pawn), getActiveAbilityName(pawn))
end)

 uevr.params.sdk.callbacks.on_script_reset(function()
	cleanup()
	configureAmbulatoryFP(uevrUtils.getValid(pawn), getActiveAbilityName(pawn))
end)

-- Nested timings are inclusive. Toggle and report with uevrUtils.profiler.
disableCameraShakes = uevrUtils.profiler:wrap("Locomotion: disable camera shakes", disableCameraShakes)
isNativeSprintActive = uevrUtils.profiler:wrap("Locomotion: sprint active", isNativeSprintActive)
neutralizeStrafeTurnAssist = uevrUtils.profiler:wrap("Locomotion: neutralize strafe turn", neutralizeStrafeTurnAssist)
neutralizeDodgeCamera = uevrUtils.profiler:wrap("Locomotion: neutralize dodge camera", neutralizeDodgeCamera)
configureShadowBlinkModifier = uevrUtils.profiler:wrap("Locomotion: configure shadow blink", configureShadowBlinkModifier)
configureDodgeRecovery = uevrUtils.profiler:wrap("Locomotion: configure dodge recovery", configureDodgeRecovery)
configureShadowBlinkRecovery = uevrUtils.profiler:wrap("Locomotion: configure blink recovery", configureShadowBlinkRecovery)
getActiveAbilityName = uevrUtils.profiler:wrap("Locomotion: active ability", getActiveAbilityName)
configureAmbulatoryFP = uevrUtils.profiler:wrap("Locomotion: configure movement", configureAmbulatoryFP)
getStickWorldDirection = uevrUtils.profiler:wrap("Locomotion: stick direction", getStickWorldDirection)
setShadowBlinkDirection = uevrUtils.profiler:wrap("Locomotion: set blink direction", setShadowBlinkDirection)
updateShadowBlinkDirection = uevrUtils.profiler:wrap("Locomotion: update blink direction", updateShadowBlinkDirection)
onSetDodgeDirection = uevrUtils.profiler:wrap("Locomotion: set dodge direction", onSetDodgeDirection)

return M