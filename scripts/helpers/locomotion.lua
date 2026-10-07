

local uevrUtils = require('libs/uevr_utils')
local input = require('libs/input')
local controllers = require('libs/controllers')
local plugin = require('libs/core/plugin')
local mounts = require('helpers/mounts')

local M = {}
local status = {}

local function disableCameraShakes(currentPawn)
	local playerCameraManager = uevrUtils.getValid(currentPawn, {"Controller", "PlayerCameraManager"})
	if playerCameraManager ~= nil then
		local cameraShakeModifier = uevrUtils.getValid(playerCameraManager, {"CachedCameraShakeMod"})
		if cameraShakeModifier ~= nil and cameraShakeModifier.DisableModifier ~= nil then
			cameraShakeModifier:DisableModifier(true)
		end
	end

	if status.cameraShakesDisabled then
		return
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

	local function blockShake()
		return true
	end
	hook_function("Class /Script/Engine.PlayerCameraManager", "StartCameraShake", true, blockShake, nil, false)
	hook_function("Class /Script/Engine.PlayerCameraManager", "StartCameraShakeFromSource", true, blockShake, nil, false)
	hook_function("Class /Script/Engine.PlayerController", "ClientStartCameraShake", true, blockShake, nil, false)
	hook_function("Class /Script/Engine.PlayerController", "ClientStartCameraShakeFromSource", true, blockShake, nil, false)

	status.cameraShakesDisabled = true
end

local function isNativeSprintActive(currentPawn)
	return (status.L3Pressed and mounts.isWalking()) or (currentPawn.IsUsingSpeedModifier ~= nil and currentPawn:IsUsingSpeedModifier())
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
local function getActiveShadowBlink(currentPawn)
	local abl = uevrUtils.getValid(currentPawn, {"AblAbilityComponent"})
	if abl == nil or abl.GetActiveAbility_New == nil then return false end
	local ability = abl:GetActiveAbility_New(uevrUtils.fname_from_string(""))
	local name = ability and ability:get_full_name()
	return name ~= nil and string.find(name, "ABL_ShadowBlink", 1, true) ~= nil
end

local function getActiveDodgeRoll(currentPawn)
	local abl = uevrUtils.getValid(currentPawn, {"AblAbilityComponent"})
	if abl == nil or abl.GetActiveAbility_New == nil then return false end
	local ability = abl:GetActiveAbility_New(uevrUtils.fname_from_string(""))
	local name = ability and ability:get_full_name()
	return name ~= nil and string.find(name, "ABL_DodgeRoll", 1, true) ~= nil
end

local function configureAmbulatoryFP(currentPawn)
	if uevrUtils.getValid(currentPawn) == nil then
		return
	end

	neutralizeStrafeTurnAssist()
	neutralizeDodgeCamera()
	configureShadowBlinkModifier()
	configureDodgeRecovery()
	configureShadowBlinkRecovery()
	disableCameraShakes(currentPawn)

	if status.locomotionPawn ~= currentPawn then
		status.locomotionPawn = currentPawn
		status.strafeFacingTarget = nil
	end

	-- Sprint only runs forward, so face the body along the stick relative to the HMD to sprint sideways without turning the view.
	local sprintYaw = nil
	if isNativeSprintActive(currentPawn) then
		local x, y = status.moveStickLX or 0, status.moveStickLY or 0
		if y < 5000 then
			-- Past sideways the body would turn away from the view.
			if currentPawn:IsUsingSpeedModifier() then currentPawn:SprintStop() end
		else
			local hmdRot = controllers.getControllerRotation(2)
			if hmdRot ~= nil then
				sprintYaw = hmdRot.Yaw + math.deg(math.atan(x, y))
			end
		end
	end
	input.setForcedBodyYaw(sprintYaw)

	local faceTargetTracker = uevrUtils.getValid(currentPawn, {"FaceTargetTracker"})
	if getActiveDodgeRoll(currentPawn) or isNativeSprintActive(currentPawn) then
		-- DodgeRoll steers its root motion toward the best facing target each tick.
		if faceTargetTracker ~= nil and uevrUtils.getValid(status.strafeFacingTarget) ~= nil and faceTargetTracker.RemoveTargetByPtr ~= nil then
			faceTargetTracker:RemoveTargetByPtr(255, status.strafeFacingTarget)
		end
		status.strafeFacingTarget = nil
	elseif faceTargetTracker ~= nil and currentPawn.GetActorForwardVector ~= nil then
		if uevrUtils.getValid(status.strafeFacingTarget) == nil and faceTargetTracker.AddTarget_StaticWorldDirection ~= nil then
			status.strafeFacingTarget = faceTargetTracker:AddTarget_StaticWorldDirection(currentPawn:GetActorForwardVector(), 255)
			if uevrUtils.getValid(status.strafeFacingTarget) ~= nil and status.strafeFacingTarget.SetComputedPriority ~= nil then
				status.strafeFacingTarget:SetComputedPriority(-1000)
			end
		elseif uevrUtils.getValid(status.strafeFacingTarget) ~= nil and status.strafeFacingTarget.SetStaticWorldDirection ~= nil then
			status.strafeFacingTarget:SetStaticWorldDirection(currentPawn:GetActorForwardVector())
		end
	end

	if currentPawn.bUseTurnAssist ~= nil then
		currentPawn.bUseTurnAssist = false
	end
	if currentPawn.bOnlyLockOnMode ~= nil then
		currentPawn.bOnlyLockOnMode = false
	end

	if currentPawn.bUseDesiredFocusDirection ~= nil then
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


local function updateShadowBlinkDirection(currentPawn)
	if not getActiveShadowBlink(currentPawn) then
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


hook_function("Class /Script/Phoenix.Biped_Player", "SetDodgeDirection", true, nil,
	function(fn, currentPawn, locals, result)
		if currentPawn == nil then return end
		-- This runs before Shadow Blink replaces the preceding locomotion ability.
		local direction = getStickWorldDirection(currentPawn)
		if direction == nil then return end
		status.shadowBlinkDirection = direction
		setShadowBlinkDirection(currentPawn, direction)
end, false)

uevrUtils.registerOnPreInputGetStateCallback(function(retval, user_index, state)
    if user_index == 0 then
        status.moveStickLX = state.Gamepad.sThumbLX
        status.moveStickLY = state.Gamepad.sThumbLY
    end
	status.L3Pressed =  uevrUtils.isButtonPressed(state, XINPUT_GAMEPAD_LEFT_THUMB)
end)

uevr.sdk.callbacks.on_pre_engine_tick(function(engine, deltaTime)
    local pawn = uevrUtils.getValid(pawn)
    if pawn == nil then return end
    if pawn.MyPlayer ~= nil then return end --if riding the cart don't update the camera

    configureAmbulatoryFP(uevrUtils.getValid(pawn))
    if pawn ~= nil then
        updateShadowBlinkDirection(pawn)
    end
 end)

local function cleanup()
    status = {}
end

uevrUtils.registerLevelChangeCallback(function(level, levelName)
    cleanup()
    configureAmbulatoryFP(uevrUtils.getValid(pawn))
end)

 uevr.params.sdk.callbacks.on_script_reset(function()
	cleanup()
	configureAmbulatoryFP(uevrUtils.getValid(pawn))
end)

return M