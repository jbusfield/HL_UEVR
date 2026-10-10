local uevrUtils = require("libs/uevr_utils")
local controllers = require("libs/controllers")
local pawnModule = require('libs/pawn')
local input = require('libs/input')
local remap = require('libs/remap')
local ik = require('libs/ik')

local M = {}

-- Also add grips to the hippogriff near players lap for steering

-- Controller pitch/roll mapped onto stick axes while flying the hippogriff.
local HIPPOGRIFF_AXIS_DEADZONE = 8
local HIPPOGRIFF_AXIS_FULL = 40
local HIPPOGRIFF_SETTLED_SAMPLE_INTERVAL = 0.05
local HIPPOGRIFF_SETTLED_VIEW_FRAMES = 4

M.EMountTypes = {
    Broom_Flying = 0,
    Broom_Ground = 1,
    Graphorn_Ground = 2,
    Hippogriff_Flying = 3,
    Hippogriff_Ground = 4,
    Niffler_Ground = 5,
    Avatar_Ground = 6,
    EMountTypes_MAX = 7,
	Cart_Rider = 8,
};
local status = {}

status.mountType = nil
status.isFlying = false
status.pitchZero = 20
status.rollZero = 0
status.autoflyEnabled = true
status.autoflyLocked = false
status.autoflyStickNeutral = true
status.autoflyLastForwardTap = nil

local AUTOFLY_STICK_THRESHOLD = 20000
local AUTOFLY_DOUBLE_TAP_WINDOW = 0.35
local BROOM_NEUTRAL_HIP_FLEX = 15
local BROOM_IDLE_SPEED_TOLERANCE = 0.05
local BROOM_NEUTRAL_REFERENCE_ROLL = 65
local BROOM_HIGH_SPEED_START_ROLL = 75
local BROOM_STICK_DEADZONE = 8000
local BROOM_MAX_LEAN_PITCH = 65
local BROOM_MAX_BANK_ROLL = 50
local BROOM_HIGH_SPEED_REFERENCE_ROLL = 90
local BROOM_FULL_RISE_BONE_DELTA = 17.1
local BROOM_FULL_DIVE_BONE_DELTA = 29.5
local BROOM_LEVEL_LIFT_TOLERANCE = 0.03
local BROOM_LEVEL_PITCH_TOLERANCE = 2
local broomHipsName = uevrUtils.fname_from_string("Hips")
local broomReferenceName = uevrUtils.fname_from_string("Reference")
local broomBoneName = uevrUtils.fname_from_string("Broom")
local hippogriffHeadName = uevrUtils.fname_from_string("Head")
status.broomStickY = 0
status.broomNeutralHipFlex = nil
status.broomNeutralTime = 0
status.followBroomRoll = false
status.broomMaxRisePitchOffset = 0
status.broomMaxDivePitchOffset = 0
status.broomRoot = nil
status.broomMesh = nil
status.broomAnim = nil
status.broomLevelRoll = BROOM_NEUTRAL_REFERENCE_ROLL
status.broomHighSpeedHeadOffset = 0
status.broomHighSpeedAlpha = 0
status.broomForwardX = 0
status.broomForwardY = 0
status.hippogriffRiderRoot = nil
status.hippogriffRiderMesh = nil
status.hippogriffViewX = nil
status.hippogriffViewZ = nil
status.hippogriffGroundX = nil
status.hippogriffGroundZ = nil
status.hippogriffAirX = nil
status.hippogriffAirZ = nil
status.hippogriffPhase = nil
status.hippogriffPhaseTime = 0
status.hippogriffRootX = 0
status.hippogriffRootZ = 0
status.hippogriffMeshX = 0
status.hippogriffMeshZ = 0
status.hippogriffTakeoffRequested = false
status.hippogriffWasFlying = nil
status.hippogriffLastPitch = 0
status.hippogriffBaseMeshX = nil
status.hippogriffBaseMeshY = nil
status.hippogriffBaseMeshZ = nil
status.hippogriffSampleTime = 0
status.hippogriffViewFrames = 0


function M.hideBodyMesh(currentPawn, visible)
	if uevrUtils.getValid(currentPawn.Mesh) ~= nil then
		local children = currentPawn.Mesh.AttachChildren
		if children ~= nil then
			for i, child in ipairs(children) do
				-- Parent Mesh is often hidden; attach-parent bounds then cull clothing when the camera is close.
				child.bUseAttachParentBound = false
				if child.BoundsScale ~= nil then child.BoundsScale = 16 end
				local childName = child:get_full_name()
				if string.find(childName, "Hair") then
					--child:SetVisibility(visible, false)
					child.bRenderInDepthPass = visible
					child:SetRenderInMainPass(visible)
					--child:SetRenderCustomDepth(visible)
				elseif string.find(childName, "Glasses") then
					--child:SetVisibility(visible, false)
					child.bRenderInDepthPass = visible
					child:SetRenderInMainPass(visible)
					--child:SetRenderCustomDepth(visible)
				elseif string.find(childName, "Hat") then
					--child:SetVisibility(visible, false)
					child.bRenderInDepthPass = visible
					child:SetRenderInMainPass(visible)
					--child:SetRenderCustomDepth(visible)
				elseif string.find(childName, "Mask") then
					--child:SetVisibility(visible, false)
					child.bRenderInDepthPass = visible
					child:SetRenderInMainPass(visible)
					--child:SetRenderCustomDepth(visible)
				elseif string.find(childName, "Arms") then
					child:SetVisibility(visible, false)
					--child:SetRenderInMainPass(visible)
					--child:SetRenderCustomDepth(visible)
				elseif string.find(childName, "Gloves") then
					child:SetVisibility(visible, false)
					--child:SetRenderInMainPass(visible)
					--child:SetRenderCustomDepth(visible)
				elseif string.find(childName, "Robe") or string.find(childName, "Upper") then
					-- the Deathly Hallows robe follows Mesh's master pose, so bone hiding must go on Mesh
					local target = (string.find(childName, "Upper") or string.find(childName, "DeathlyHallows", 1, true)) and currentPawn.Mesh or child
					if visible then
						target:UnHideBoneByName(uevrUtils.fname_from_string("LeftArm"), 0)
						target:UnHideBoneByName(uevrUtils.fname_from_string("RightArm"), 0)
					else
						target:HideBoneByName(uevrUtils.fname_from_string("LeftArm"), 0)
						target:HideBoneByName(uevrUtils.fname_from_string("RightArm"), 0)
					end
				end
							end
		end
	end
end

function M.hideViewableMesh(currentPawn, visible)
	if uevrUtils.getValid(currentPawn.Mesh) ~= nil then
		local children = currentPawn.Mesh.AttachChildren
		if children ~= nil then
			for i, child in ipairs(children) do
				-- Parent Mesh is often hidden; attach-parent bounds then cull clothing when the camera is close.
				child.bUseAttachParentBound = false
				if child.BoundsScale ~= nil then child.BoundsScale = 16 end
				local childName = child:get_full_name()
				if string.find(childName, "Hair") then

				elseif string.find(childName, "Glasses") then

				elseif string.find(childName, "Hat") then

				elseif string.find(childName, "Mask") then

				elseif string.find(childName, "Arms") then

				elseif string.find(childName, "Gloves") then

				else
					child:SetVisibility(visible, false)
				end
			end
		end
	end
end

local function clearAutoflyLock()
	status.autoflyLocked = false
	status.autoflyStickNeutral = true
	status.autoflyLastForwardTap = nil
end

function M.setAutofly(enabled)
	status.autoflyEnabled = enabled == true
	if not status.autoflyEnabled then
		clearAutoflyLock()
	end
end

function M.setBroomRollFollow(enabled)
	status.followBroomRoll = enabled == true
end

function M.setBroomMaxRisePitchOffset(value)
	status.broomMaxRisePitchOffset = math.max(-45, math.min(45, tonumber(value) or 0))
end

function M.setBroomMaxDivePitchOffset(value)
	status.broomMaxDivePitchOffset = math.max(-45, math.min(45, tonumber(value) or 0))
end

function M.setBroomHighSpeedHeadOffset(value)
	status.broomHighSpeedHeadOffset = math.max(-75, math.min(75, tonumber(value) or 0))
	if status.broomHighSpeedHeadOffset == 0 then
		status.broomHighSpeedAlpha = 0
	end
end

local function isHippogriffFlying()
	return status.isFlying and (status.mountType == M.EMountTypes.Hippogriff_Flying or status.mountType == M.EMountTypes.Hippogriff_Ground)
end

local function isHippogriff()
	return status.mountType == M.EMountTypes.Hippogriff_Flying or status.mountType == M.EMountTypes.Hippogriff_Ground
end

local function getAverageControllerAxes()
	local pitch = 0
	local roll = 0
	local left = controllers.getControllerRotation(Handed.Left)
	local right = controllers.getControllerRotation(Handed.Right)
	if left == nil or right == nil then return nil end
	if isHippogriff() or status.mountType == M.EMountTypes.Broom_Flying or status.mountType == M.EMountTypes.Graphorn_Ground then
		if status.isGripping ~= nil and status.isGripping[Handed.Left] then
			pitch = pitch + left.Pitch
			roll = roll + left.Roll
		end
		if status.isGripping ~= nil and status.isGripping[Handed.Right] then
			pitch = pitch + right.Pitch
			roll = roll + right.Roll
		end
	else
		pitch = pitch + (left.Pitch + right.Pitch) * 0.5
		roll = roll + (left.Roll + right.Roll) * 0.5
	end
	return pitch, roll
end

local function stickFromAxis(value)
	local absValue = math.abs(value)
	if absValue <= HIPPOGRIFF_AXIS_DEADZONE then return 0 end
	local normalized = math.min(1, (absValue - HIPPOGRIFF_AXIS_DEADZONE) / (HIPPOGRIFF_AXIS_FULL - HIPPOGRIFF_AXIS_DEADZONE))
	return math.floor((value < 0 and -1 or 1) * normalized * 32767)
end

local function addStick(current, delta)
	local combined = current + delta
	if combined > 32767 then return 32767 end
	if combined < -32767 then return -32767 end
	return combined
end

-- Sets the neutral controller pitch used for climb/dive.
-- Call with no args to capture the current hand pose as zero, or pass a pitch value.
function M.adjustPitchZero(pitch)
	if pitch == nil then
		pitch = select(1, getAverageControllerAxes())
		if pitch == nil then return end
	end
	status.pitchZero = pitch
end

-- Sets the neutral controller roll used for left/right.
-- Call with no args to capture the current hand pose as zero, or pass a roll value.
function M.adjustRollZero(roll)
	if roll == nil then
		roll = select(2, getAverageControllerAxes())
		if roll == nil then return end
	end
	status.rollZero = roll
end

function M.getIsFlying()
	return status.isFlying == true
end

function M.getMountType()
	return status.mountType
end

function M.isWalking()
	return status.mountType == M.EMountTypes.Avatar_Ground
end

function M.isOnBroom()
	return status.mountType == M.EMountTypes.Broom_Flying
end

function M.getMountPawn(pawn)
	local mountPawn = nil
	if uevrUtils.validate_object(pawn) ~= nil then
		mountPawn = pawn
		if status.mountType >= M.EMountTypes.Graphorn_Ground and status.mountType <= M.EMountTypes.Niffler_Ground and pawn.GetMountComponent ~= nil then
			local mountComponent = pawn:GetMountComponent()
			if mountComponent ~= nil then
				mountPawn = mountComponent.RiderCharacter
			end
		elseif status.mountType == M.EMountTypes.Cart_Rider then
			mountPawn = pawn.MyPlayer
		end
	end
	return mountPawn
end

function M.getMountInfo(pawn)
	local isFlying = false
	local mountType = M.EMountTypes.Avatar_Ground
	if uevrUtils.validate_object(pawn) ~= nil then
		if pawn.GetMountComponent ~= nil then
			local mountComponent = pawn:GetMountComponent()
			if mountComponent ~= nil and mountComponent.IsFlying ~= nil then
				mountType = mountComponent:GetMountHandler().CreatureMountType
				isFlying = mountComponent:IsFlying()
			end
		elseif pawn.MyPlayer ~= nil then
			-- riding a cart
			mountType = M.EMountTypes.Cart_Rider
			isFlying = false
		else
			status.flyingBroomClass = status.flyingBroomClass or uevrUtils.find_required_object("Class /Script/Phoenix.FlyingBroom")
			local parent = pawn:GetAttachParentActor()
			local onBroom = parent ~= nil --and parent:is_a(status.flyingBroomClass)
			if onBroom then
				mountType = M.EMountTypes.Broom_Flying
				isFlying = true
			end
			-- if status.mountZone == nil then
			-- 	status.mountZone = uevrUtils.find_default_instance("Class /Script/Phoenix.MountZoneVolumeBase")
			-- end
			-- if status.mountZone ~= nil then
			-- 	local out = {}
			-- 	status.mountZone:GetMountType(pawn, out)
			-- 	print("Mount type: ", out.result)
			-- 	mountType = out.result
			-- 	isFlying = mountType == 0
			-- end
			-- if pawn.GetIsOnAMountOrInTransition ~= nil and pawn:GetIsOnAMountOrInTransition() then
			-- 	isFlying = true
			-- 	mountType = 0 --broom
			-- end
		end
	end
	return mountType, isFlying
end

local function executeOnMountChangeCallback(...)
	return uevrUtils.executeUEVRCallbacks("on_mount_changed", table.unpack({...}))
end

local function executeOnFlyingChangedCallback(...)
	return uevrUtils.executeUEVRCallbacks("on_flying_changed", table.unpack({...}))
end

local g_walkingLocomotionMode = nil
function M.updateMountLocomotionMode(pawn, locomotionMode)
	local newLocomotionMode = nil
	local lastMountType = status.mountType
	local wasFlying = status.isFlying
	status.mountType, status.isFlying = M.getMountInfo(pawn)
	if wasFlying and not status.isFlying then
		clearAutoflyLock()
	end
	if lastMountType ~= status.mountType or wasFlying ~= status.isFlying then
		status.broomNeutralHipFlex = nil
		status.broomNeutralTime = 0
		status.broomRoot = nil
		status.broomMesh = nil
		status.broomAnim = nil
		status.broomLevelRoll = BROOM_NEUTRAL_REFERENCE_ROLL
		status.broomHighSpeedAlpha = 0
		if lastMountType ~= status.mountType then
			executeOnMountChangeCallback(status.mountType, status.isFlying)
		end
		if wasFlying ~= status.isFlying then
			executeOnFlyingChangedCallback(status.mountType, status.isFlying)
		end

		--animal mounts need to use locomotion mode 0
		if status.mountType >= M.EMountTypes.Graphorn_Ground and status.mountType <= M.EMountTypes.Niffler_Ground then
			g_walkingLocomotionMode = locomotionMode
			newLocomotionMode = 0
		end
		--after dismounting animal mounts, set locomotion mode back to what it was before mounting
		if status.mountType == M.EMountTypes.Avatar_Ground and g_walkingLocomotionMode ~= nil then
			newLocomotionMode = g_walkingLocomotionMode
			g_walkingLocomotionMode = nil
		end
	end
	return newLocomotionMode
end

local function updateControllerPitchRoll(state)
	local pitch, roll = getAverageControllerAxes()
	if pitch == nil then return end

	-- hands pitch or right stick Y controls the hippogriff flight pitch
	local pitchStick = stickFromAxis(pitch - status.pitchZero)
	if pitchStick ~= 0 then
		state.Gamepad.sThumbRY = addStick(state.Gamepad.sThumbRY, pitchStick)
		-- dont let the pitch be too great or the rider clips through the hippogriff
		if isHippogriffFlying() then
			if state.Gamepad.sThumbRY > 25000 then state.Gamepad.sThumbRY = 25000 end
		end
	end

	-- hands roll or left stick X controls the hippogriff flight turn
	local rollStick = stickFromAxis(roll - status.rollZero)
	if rollStick ~= 0 then
		state.Gamepad.sThumbLX = addStick(state.Gamepad.sThumbLX, rollStick)
	end
end

uevrUtils.registerUEVRCallback("on_accessory_attach", function(handed, parentAttachment, socketName, attachType, loc, rot)
	if status.isGripping == nil then status.isGripping = {} end
	status.isGripping[handed] = true
end)

uevrUtils.registerUEVRCallback("on_accessory_detach", function(handed)
	if status.isGripping ~= nil then
		status.isGripping[handed] = nil
	end
end)


uevrUtils.registerPreEngineTickCallback(function()
	M.updateMountLocomotionMode(pawn, 0)
end)

uevrUtils.registerOnPreInputGetStateCallback(function(retval, user_index, state)
	if status.mountType == M.EMountTypes.Broom_Flying then
		status.broomStickY = state.Gamepad.sThumbLY
	end
	-- if riding a hippogriff on the ground, right stick forward will make it fly
	if status.mountType == M.EMountTypes.Hippogriff_Ground then
		if state.Gamepad.sThumbRY > 22000 then
			uevrUtils.pressButton(state, XINPUT_GAMEPAD_A)
		end
		if uevrUtils.isButtonPressed(state, XINPUT_GAMEPAD_A) then
			status.hippogriffTakeoffRequested = true
			M.hideViewableMesh(M.getMountPawn(pawn), false)
			delay(3000, function()
				M.hideViewableMesh(M.getMountPawn(pawn), true)
			end)
		end
	end

	--disable right stick turning while on hippogriff. Left stick controls turning
	if status.mountType == M.EMountTypes.Hippogriff_Ground or status.mountType == M.EMountTypes.Hippogriff_Flying or status.mountType == M.EMountTypes.Graphorn_Ground then
		state.Gamepad.sThumbRX = 0
	end

	if isHippogriff() or status.mountType == M.EMountTypes.Broom_Flying or status.mountType == M.EMountTypes.Graphorn_Ground then
		if status.autoflyEnabled then
			--double tap left stick forward or press L3 to toggle forward flight		
			if uevrUtils.isButtonPressed(state, XINPUT_GAMEPAD_LEFT_THUMB) then
				if isHippogriff()  or status.mountType == M.EMountTypes.Graphorn_Ground then
					status.autoflyLocked = not status.autoflyLocked
				else
					status.autoflyLocked = false
				end
				status.autoflyLastForwardTap = nil
			end

			local ly = state.Gamepad.sThumbLY
			local forward = ly > AUTOFLY_STICK_THRESHOLD
			local backward = ly < -AUTOFLY_STICK_THRESHOLD
			if status.autoflyStickNeutral then
				if forward then
					local now = os.clock()
					if status.autoflyLastForwardTap ~= nil and (now - status.autoflyLastForwardTap) <= AUTOFLY_DOUBLE_TAP_WINDOW then
						status.autoflyLocked = not status.autoflyLocked
						status.autoflyLastForwardTap = nil
					else
						status.autoflyLastForwardTap = now
					end
					status.autoflyStickNeutral = false
				elseif backward and status.autoflyLocked then
					clearAutoflyLock()
					status.autoflyStickNeutral = false
				end
			elseif not forward and not backward then
				status.autoflyStickNeutral = true
			end
			if status.autoflyLocked then
				state.Gamepad.sThumbLY = 32767
			end
		end

		updateControllerPitchRoll(state)
	end
end)

-- The rider mesh is attached to the broom rather than the character capsule.
-- World-space sockets preserve the broom's pitch and bank when we tilt the capsule.
local function readBroomPose(mesh)
	local hipTransform = mesh:GetSocketTransform(broomHipsName, 0) -- RTS_World
	local referenceTransform = mesh:GetSocketTransform(broomReferenceName, 0)
	if hipTransform == nil or referenceTransform == nil then return nil end
	local hipQuat = hipTransform.Rotation
	local referenceQuat = referenceTransform.Rotation
	if hipQuat == nil or referenceQuat == nil then return nil end
	local reference = uevrUtils.rotatorFromQuat(referenceQuat.X, referenceQuat.Y, referenceQuat.Z, referenceQuat.W)
	if reference == nil then return nil end

	-- Hips' local X rotation is forward flexion, independent of broom banking.
	local relativeW = referenceQuat.W * hipQuat.W + referenceQuat.X * hipQuat.X
		+ referenceQuat.Y * hipQuat.Y + referenceQuat.Z * hipQuat.Z
	local relativeX = referenceQuat.W * hipQuat.X - referenceQuat.X * hipQuat.W
		- referenceQuat.Y * hipQuat.Z + referenceQuat.Z * hipQuat.Y
	local hipFlex = math.deg(-2 * math.atan(relativeX, relativeW))
	return reference, hipFlex
end

local function updateBroomNeutralHipFlex(reference, hipFlex, delta)
	---@diagnostic disable-next-line: undefined-field
	local broomAnim = uevrUtils.getValid(status.broomAnim)
	if broomAnim == nil then return end

	local broomSpeed = broomAnim.Speed or nil
	local normalStraight = type(broomSpeed) == "number" and broomSpeed < BROOM_IDLE_SPEED_TOLERANCE
		and math.abs(uevrUtils.clampAngle180(reference.Roll - BROOM_NEUTRAL_REFERENCE_ROLL)) < 5
		and math.abs(reference.Pitch) < 5
	if normalStraight and math.abs(status.broomStickY) < BROOM_STICK_DEADZONE then
		status.broomNeutralTime = status.broomNeutralTime + (delta or 0)
		if status.broomNeutralTime > 0.5 then
			local neutral = status.broomNeutralHipFlex or BROOM_NEUTRAL_HIP_FLEX
			local alpha = math.min(1, (delta or 0) * 2)
			status.broomNeutralHipFlex = neutral + uevrUtils.clampAngle180(hipFlex - neutral) * alpha
		end
	else
		status.broomNeutralTime = 0
	end
end

local function updateBroomHeadOffset(referenceRoll, broomRoot)
	if status.broomHighSpeedHeadOffset == 0 then return end
	local highSpeedRoll = uevrUtils.clampAngle180(referenceRoll - BROOM_HIGH_SPEED_START_ROLL)
	if highSpeedRoll <= 0 then return end

	if broomRoot.GetForwardVector == nil then return end
	local forward = broomRoot:GetForwardVector()
	if forward == nil then return end
	status.broomForwardX = forward.X
	status.broomForwardY = forward.Y
	status.broomHighSpeedAlpha = math.min(1, highSpeedRoll / (BROOM_HIGH_SPEED_REFERENCE_ROLL - BROOM_HIGH_SPEED_START_ROLL))
end

-- Learn the level-flight bone angle from the bone itself. Anim Speed reaches 1
-- in normal flight as well as high-speed flight, so it cannot set this baseline.
local function readBroomBonePitch(broomRoot)
	if broomRoot == nil then return nil end
	if status.broomRoot ~= broomRoot then
		status.broomRoot = broomRoot
		status.broomMesh = nil
		status.broomAnim = nil
		status.broomLevelRoll = BROOM_NEUTRAL_REFERENCE_ROLL
	end
	local broomMesh = uevrUtils.validate_object(status.broomMesh)
	if broomMesh == nil then
		local broomActor = broomRoot.GetOwner ~= nil and uevrUtils.validate_object(broomRoot:GetOwner()) or nil
		broomMesh = broomActor ~= nil and uevrUtils.validate_object(broomActor.SkeletalMesh) or nil
		status.broomMesh = broomMesh
		status.broomAnim = nil
	end
	if broomMesh == nil or broomMesh.GetSocketRotation == nil then return nil end

	local broomAnim = uevrUtils.validate_object(status.broomAnim)
	if broomAnim == nil then
		broomAnim = uevrUtils.validate_object(broomMesh.AnimScriptInstance)
		status.broomAnim = broomAnim
	end
	if broomAnim == nil then return nil end
	local lift = broomAnim.Lift
	if type(lift) ~= "number" then return nil end

	local rotation = broomMesh:GetSocketRotation(broomBoneName)
	if rotation == nil then return nil end
	local parentRotation = uevrUtils.getComponentRotation(broomRoot)
	if parentRotation ~= nil
		and math.abs(lift) < BROOM_LEVEL_LIFT_TOLERANCE
		and math.abs(parentRotation.Pitch) < BROOM_LEVEL_PITCH_TOLERANCE then
		status.broomLevelRoll = math.max(BROOM_NEUTRAL_REFERENCE_ROLL,
			math.min(BROOM_HIGH_SPEED_REFERENCE_ROLL, rotation.Roll))
	end
	return uevrUtils.clampAngle180(status.broomLevelRoll - rotation.Roll)
end

local function getBroomPitchOffset(bonePitch)
	if bonePitch == nil then return 0 end
	if bonePitch > 0 then
		return status.broomMaxRisePitchOffset * math.min(1, bonePitch / BROOM_FULL_RISE_BONE_DELTA)
	elseif bonePitch < 0 then
		return status.broomMaxDivePitchOffset * math.min(1, -bonePitch / BROOM_FULL_DIVE_BONE_DELTA)
	end
	return 0
end

local function applyBroomRootRotation(root, reference, hipFlex, bonePitch)
	local neutral = status.broomNeutralHipFlex or BROOM_NEUTRAL_HIP_FLEX
	local pitch = -uevrUtils.clampAngle180(reference.Roll - BROOM_NEUTRAL_REFERENCE_ROLL)
		- uevrUtils.clampAngle180(hipFlex - neutral) + getBroomPitchOffset(bonePitch)
	pitch = math.max(-BROOM_MAX_LEAN_PITCH, math.min(BROOM_MAX_LEAN_PITCH, pitch))
	local roll = status.followBroomRoll and math.max(-BROOM_MAX_BANK_ROLL, math.min(BROOM_MAX_BANK_ROLL, reference.Pitch)) or 0
	local rotation = uevrUtils.getComponentRotation(root)
	if rotation ~= nil and (math.abs(uevrUtils.clampAngle180(rotation.Pitch - pitch)) > 0.1 or math.abs(uevrUtils.clampAngle180(rotation.Roll - roll)) > 0.1) then
		root:K2_SetWorldRotation(uevrUtils.rotator(pitch, rotation.Yaw, roll), false, reusable_hit_result, false)
	end
end

local function updateBroomPose(delta)
	status.broomHighSpeedAlpha = 0
	if status.mountType ~= M.EMountTypes.Broom_Flying or not status.isFlying then return end
	local currentPawn = uevrUtils.validate_object(pawn)
	if currentPawn == nil then return end
	local mesh = uevrUtils.validate_object(currentPawn.Mesh)
	local root = uevrUtils.validate_object(currentPawn.RootComponent)
	if mesh == nil or root == nil or mesh.GetSocketTransform == nil or root.K2_SetWorldRotation == nil then return end

	local reference, hipFlex = readBroomPose(mesh)
	if reference == nil then return end
	local hasPitchOffset = status.broomMaxRisePitchOffset ~= 0 or status.broomMaxDivePitchOffset ~= 0
	local broomRoot = nil
	if hasPitchOffset or status.broomHighSpeedHeadOffset ~= 0 then
		broomRoot = uevrUtils.validate_object(root.AttachParent)
	end
	local bonePitch = hasPitchOffset and readBroomBonePitch(broomRoot) or nil
	updateBroomNeutralHipFlex(reference, hipFlex, delta)
	applyBroomRootRotation(root, reference, hipFlex, bonePitch)
	updateBroomHeadOffset(reference.Roll, broomRoot or root)
end

-- Keep the mounted rider in the game's pose while shifting the capsule during
-- takeoff. On landing, move only the rider mesh so the view stays clear of the
-- hippogriff's neck. The view itself remains owned by the input profile.
local function hippogriffLocalXZ(root, x, y, z)
	local origin = uevrUtils.getComponentLocation(root)
	local forward = root:GetForwardVector()
	local up = root:GetUpVector()
	if origin == nil or forward == nil or up == nil then return nil end
	local dx, dy, dz = x - origin.X, y - origin.Y, z - origin.Z
	return dx * forward.X + dy * forward.Y + dz * forward.Z,
		dx * up.X + dy * up.Y + dz * up.Z
end

local function applyHippogriffRiderOffsets(rootX, rootZ, meshX, meshZ)
	local root, mesh = status.hippogriffRiderRoot, status.hippogriffRiderMesh
	if root == nil or mesh == nil then return end
	uevrUtils.setComponentRelativeLocation(root, rootX, nil, rootZ)
	if status.hippogriffBaseMeshX ~= nil then
		uevrUtils.setComponentRelativeLocation(mesh,
			status.hippogriffBaseMeshX - rootX + meshX,
			status.hippogriffBaseMeshY,
			status.hippogriffBaseMeshZ - rootZ + meshZ)
	end
	status.hippogriffRootX, status.hippogriffRootZ = rootX, rootZ
	status.hippogriffMeshX, status.hippogriffMeshZ = meshX, meshZ
end

local function clearHippogriffRiderAlignment()
	if status.hippogriffRootX ~= 0 or status.hippogriffRootZ ~= 0
		or status.hippogriffMeshX ~= 0 or status.hippogriffMeshZ ~= 0 then
		if uevrUtils.validate_object(status.hippogriffRiderRoot) ~= nil
			and uevrUtils.validate_object(status.hippogriffRiderMesh) ~= nil then
			applyHippogriffRiderOffsets(0, 0, 0, 0)
		end
	end
	status.hippogriffRiderRoot, status.hippogriffRiderMesh = nil, nil
	status.hippogriffRootX, status.hippogriffRootZ = 0, 0
	status.hippogriffMeshX, status.hippogriffMeshZ = 0, 0
	status.hippogriffViewX, status.hippogriffViewZ = nil, nil
	status.hippogriffGroundX, status.hippogriffGroundZ = nil, nil
	status.hippogriffAirX, status.hippogriffAirZ = nil, nil
	status.hippogriffPhase, status.hippogriffPhaseTime = nil, 0
	status.hippogriffTakeoffRequested, status.hippogriffWasFlying = false, nil
	status.hippogriffLastPitch = 0
	status.hippogriffBaseMeshX, status.hippogriffBaseMeshY, status.hippogriffBaseMeshZ = nil, nil, nil
	status.hippogriffSampleTime, status.hippogriffViewFrames = 0, 0
end

local function updateHippogriffRiderAlignment(delta)
	if status.hippogriffPhase == nil and not status.hippogriffTakeoffRequested
		and status.hippogriffWasFlying == status.isFlying then
		status.hippogriffSampleTime = status.hippogriffSampleTime + (delta or (1 / 90))
		if status.hippogriffSampleTime < HIPPOGRIFF_SETTLED_SAMPLE_INTERVAL then return end
	end
	status.hippogriffSampleTime = 0
	local root = uevrUtils.validate_object(status.hippogriffRiderRoot)
	local mesh = uevrUtils.validate_object(status.hippogriffRiderMesh)
	if root == nil or mesh == nil then
		local rider = uevrUtils.validate_object(M.getMountPawn(pawn))
		if rider ~= nil and rider ~= pawn then
			root = uevrUtils.validate_object(rider.RootComponent)
			mesh = uevrUtils.validate_object(rider.Mesh)
		end
	end
	if root == nil or mesh == nil then
		clearHippogriffRiderAlignment()
		return
	end
	status.hippogriffRiderRoot, status.hippogriffRiderMesh = root, mesh
	if status.hippogriffBaseMeshZ == nil then status.hippogriffBaseMeshZ = mesh.RelativeLocation.Z end
	if status.hippogriffViewX == nil then return end
	local head = mesh:GetSocketLocation(hippogriffHeadName)
	local rotation = uevrUtils.getComponentRotation(root)
	if head == nil or rotation == nil then return end
	local headX, headZ = hippogriffLocalXZ(root, head.X, head.Y, head.Z)
	if headX == nil then return end
	-- Remove our previous mesh shift before comparing this pose with a settled pose.
	local poseX = headX - status.hippogriffViewX + status.hippogriffRootX - status.hippogriffMeshX
	local poseZ = headZ - status.hippogriffViewZ + status.hippogriffRootZ - status.hippogriffMeshZ
	local flying = status.isFlying
	local pitch = math.abs(rotation.Pitch)
	if status.hippogriffWasFlying == true and not flying then
		status.hippogriffPhase = status.hippogriffAirX ~= nil and "landing" or nil
	elseif not flying and status.hippogriffPhase == nil and status.hippogriffGroundX ~= nil
		and (status.hippogriffTakeoffRequested or (status.hippogriffLastPitch < 15 and pitch > 20)) then
		status.hippogriffPhase = "takeoff"
		status.hippogriffPhaseTime = 0
	end
	status.hippogriffWasFlying = flying
	status.hippogriffLastPitch = pitch
	status.hippogriffTakeoffRequested = false

	local rootX, rootZ, meshX, meshZ = 0, 0, 0, 0
	if status.hippogriffPhase == "takeoff" then
		if flying then status.hippogriffPhaseTime = status.hippogriffPhaseTime + (delta or 0) end
		local fade = math.max(0, math.min(1, 1.6 - status.hippogriffPhaseTime))
		rootX = math.max(-40, math.min(0, poseX - status.hippogriffGroundX)) * fade
		rootZ = math.max(0, math.min(40, poseZ - status.hippogriffGroundZ)) * fade
		if flying and fade == 0 then status.hippogriffPhase = nil end
	elseif status.hippogriffPhase == "landing" then
		local fade = math.max(0, math.min(1, (pitch - 10) / 20))
		meshX = math.max(-35, math.min(0, status.hippogriffAirX - poseX)) * fade
		meshZ = math.max(0, math.min(35, status.hippogriffAirZ - poseZ)) * fade
		if fade == 0 then status.hippogriffPhase = nil end
	end
	if status.hippogriffPhase == nil then
		if flying then
			status.hippogriffAirX, status.hippogriffAirZ = poseX, poseZ
		elseif pitch < 15 then
			status.hippogriffGroundX, status.hippogriffGroundZ = poseX, poseZ
		end
	end
	if rootX ~= status.hippogriffRootX or rootZ ~= status.hippogriffRootZ
		or meshX ~= status.hippogriffMeshX or meshZ ~= status.hippogriffMeshZ then
		applyHippogriffRiderOffsets(rootX, rootZ, meshX, meshZ)
	end
end

uevrUtils.registerUEVRCallback("on_input_mesh_relative_position_change", function(x, y)
	local mesh = status.hippogriffRiderMesh
	if mesh == nil or not isHippogriff() then return end
	status.hippogriffBaseMeshX, status.hippogriffBaseMeshY = x, y
	if status.hippogriffRootX ~= 0 or status.hippogriffRootZ ~= 0
		or status.hippogriffMeshX ~= 0 or status.hippogriffMeshZ ~= 0 then
		uevrUtils.setComponentRelativeLocation(mesh,
			x - status.hippogriffRootX + status.hippogriffMeshX, y,
			status.hippogriffBaseMeshZ - status.hippogriffRootZ + status.hippogriffMeshZ)
	end
end)

uevr.sdk.callbacks.on_post_engine_tick(function(engine, delta)
	updateBroomPose(delta)
	if isHippogriff() then updateHippogriffRiderAlignment(delta) end
end)

-- The input module sets the VR view position in this same callback phase.
-- This callback is registered afterward, so add the broom-only adjustment
-- to its result without moving the pawn, broom, or rider mesh.
local function applyBroomHeadOffset(position)
	local offset = status.broomHighSpeedHeadOffset * status.broomHighSpeedAlpha
	if offset == 0 or position == nil then return end
	position.x = position.x + status.broomForwardX * offset
	position.y = position.y + status.broomForwardY * offset
end

uevr.params.sdk.callbacks.on_early_calculate_stereo_view_offset(function(device, view_index, world_to_meters, position, rotation, is_double)
	applyBroomHeadOffset(position)
	if view_index == 1 and isHippogriff() and status.hippogriffRiderRoot ~= nil then
		if status.hippogriffPhase == nil then
			status.hippogriffViewFrames = status.hippogriffViewFrames + 1
			if status.hippogriffViewFrames < HIPPOGRIFF_SETTLED_VIEW_FRAMES then return end
			status.hippogriffViewFrames = 0
		end
		status.hippogriffViewX, status.hippogriffViewZ = hippogriffLocalXZ(
			status.hippogriffRiderRoot, position.x, position.y, position.z)
	end
end)

local function handleMountChange(mountType, isFlying)
	clearHippogriffRiderAlignment()
	--print("mountType", mountType)
	if mountType == M.EMountTypes.Avatar_Ground then
		pawnModule.setCurrentProfileByLabel("Default")
		input.setCurrentProfileByLabel("Default")
		remap.setCurrentProfileByLabel("Default")
		ik.setCurrentProfileByLabel("Default")
		input.setStickTurnDisabled(false, "mount")
		pawnModule.reset()
	elseif mountType == M.EMountTypes.Hippogriff_Ground then
		pawnModule.setCurrentProfileByLabel("MountPawn")
		input.setCurrentProfileByLabel(isFlying and "HippogriffAir" or "HippogriffGround")
		remap.setCurrentProfileByLabel("MountPawn")
		ik.setCurrentProfileByLabel("MountPawn")
		input.setStickTurnDisabled(true, "mount")
		pawnModule.reset()
	elseif mountType == M.EMountTypes.Broom_Ground or mountType == M.EMountTypes.Broom_Flying then
		pawnModule.setCurrentProfileByLabel("Default")
		input.setCurrentProfileByLabel("Broom")
		remap.setCurrentProfileByLabel("MountPawn")
		ik.setCurrentProfileByLabel("Broom")
		input.setStickTurnDisabled(true, "mount")
		pawnModule.reset()
	elseif mountType == M.EMountTypes.Graphorn_Ground then
		pawnModule.setCurrentProfileByLabel("MountPawn")
		input.setCurrentProfileByLabel("Graphorn")
		remap.setCurrentProfileByLabel("MountPawn")
		ik.setCurrentProfileByLabel("MountPawn")
		input.setStickTurnDisabled(true, "mount")
		pawnModule.reset()
	elseif mountType == M.EMountTypes.Cart_Rider then
		pawnModule.setCurrentProfileByLabel("CartRider")
		input.setCurrentProfileByLabel("CartRider")
		remap.setCurrentProfileByLabel("MountPawn")
		ik.setCurrentProfileByLabel("MountPawn")
		input.setStickTurnDisabled(true, "mount")
		pawnModule.reset()
	elseif mountType ~= nil then
		pawnModule.setCurrentProfileByLabel("MountPawn")
		input.setCurrentProfileByLabel("MountPawn")
		remap.setCurrentProfileByLabel("MountPawn")
		ik.setCurrentProfileByLabel("MountPawn")
		input.setStickTurnDisabled(true, "mount")
		pawnModule.reset()
	end
end

local function handleFlyingChange(mountType, isFlying)
	if isHippogriff() then
		input.setCurrentProfileByLabel(isFlying and "HippogriffAir" or "HippogriffGround")
	end
end

uevrUtils.registerLevelChangeCallback(function()
	handleMountChange(M.getMountType(), M.getIsFlying())
end)
uevrUtils.registerUEVRCallback("on_mount_changed", function(mountType, isFlying)
	handleMountChange(mountType, isFlying)
end)
uevrUtils.registerUEVRCallback("on_flying_changed", function(mountType, isFlying)
	handleFlyingChange(mountType, isFlying)
end)


return M
