local uevrUtils = require('libs/uevr_utils')
local plugin = require('libs/core/plugin')
local controllers = require('libs/controllers')

local M = {}

local status = {}

local reset = function()
    uevrUtils.setIsInCutsceneOverride(nil)
	status = {}
end
-- World props (food, drinks, etc.) play an interaction ability without a cinematic; GetAbilityClass is called once when it starts.
-- Treat it as a cutscene while the ability plays so it's watched from the third-person camera instead of happening inside the head.
-- Ability m_Length is unreliable (often inf), so poll the ability channels only while the interaction runs; active abilities are the class default objects.
-- Abilities listed here (by the name printed on interaction) stay in first person instead, with the spawned prop (e.g. cake slice) moved to the real mouth.
-- Each value is the mouth offset (cm, relative to HMD facing) correcting for the animated head bone not matching the real eye position and the prop's pivot,
-- plus an optional rotation offset (degrees) applied in the prop's local frame.
local firstPersonInteractions = {
	ABL_EatFoodLarge_C = {forward = 4, right = 10, up = -8},
	ABL_DrinkBeer_C = {forward = 8, right = 15, up = -15, pitch = 30, yaw = 0, roll = 0},
}

-- The animation brings the prop to the animated head; keep its offset from the head but apply it to the HMD, rotated by the HMD/body yaw difference.
-- The prop is spawned elsewhere and later attached to a hand socket on the body mesh (cake: SKT_LeftHand), so look for it among the mesh's children.
-- The unmodified position is rebuilt each frame from the attach socket and original relative offset, since moving the actor changes its relative location.
local function updateProp()
	local mesh = uevrUtils.getValid(pawn, {"Mesh"})
	local hmd, hmdRot = controllers.getControllerLocation(2), controllers.getControllerRotation(2)
	if mesh == nil or hmd == nil or hmdRot == nil then return end
	local prop = uevrUtils.getValid(status.prop)
	if prop == nil then
		for i = 0, mesh:GetNumChildrenComponents() - 1 do
			local child = mesh:GetChildComponent(i)
			local owner = child and child:GetOwner()
			if owner ~= nil and owner:is_a(status.propClass) then
				local rel, relRot = child.RelativeLocation, child.RelativeRotation
				prop, status.prop, status.propSocket, status.propOffset = owner, owner, child.AttachSocketName, uevrUtils.vector(rel.X, rel.Y, rel.Z)
				status.propRotation = uevrUtils.rotator(relRot.Pitch, relRot.Yaw, relRot.Roll)
				break
			end
		end
		if prop == nil then return end
	end
	local socket = mesh:GetSocketTransform(status.propSocket, 0)
	local loc = kismet_math_library:TransformLocation(socket, status.propOffset)
	local head = mesh:GetSocketLocation(uevrUtils.fname_from_string("head"))
	local yaw = math.rad(hmdRot.Yaw - pawn:K2_GetActorRotation().Yaw)
	local hmdYaw = math.rad(hmdRot.Yaw)
	local mouthOffset = status.mouthOffset
	local x, y = loc.X - head.X, loc.Y - head.Y
	x, y = x * math.cos(yaw) - y * math.sin(yaw) + mouthOffset.forward * math.cos(hmdYaw) - mouthOffset.right * math.sin(hmdYaw), x * math.sin(yaw) + y * math.cos(yaw) + mouthOffset.forward * math.sin(hmdYaw) + mouthOffset.right * math.cos(hmdYaw)
	local rot = kismet_math_library:ComposeRotators(uevrUtils.rotator(mouthOffset.pitch or 0, mouthOffset.yaw or 0, mouthOffset.roll or 0), kismet_math_library:TransformRotation(socket, status.propRotation))
	prop:K2_SetActorLocationAndRotation(uevrUtils.vector(hmd.X + x, hmd.Y + y, hmd.Z + loc.Z - head.Z + mouthOffset.up), rot, false, {}, true)
end

hook_function("Class /Script/Phoenix.SimpleInteractObject", "GetAbilityClass", true, nil, function(fn, obj, locals, result)
	local ability = obj.AbilityClass
	local abilityName = ability and ability:get_fname():to_string() or "nil"
	uevrUtils.print("Interaction " .. abilityName .. " " .. obj:get_class():get_fname():to_string())
	if ability == nil or not string.find(ability:get_full_name(), "/Interactions/", 1, true) then return end
	local abilityAddress = ability:get_class_default_object():get_address()
	local firstPerson = firstPersonInteractions[abilityName]
	status.prop, status.propClass, status.mouthOffset = nil, obj.AbilitySpawnActorClass, firstPerson
	if not firstPerson then
		uevrUtils.setIsInCutsceneOverride(true)
	elseif status.propClass ~= nil then
		uevrUtils.registerPostEngineTickCallback(updateProp)
	end
	-- Some abilities (e.g. ABL_EatCandy_C) can stay active forever waiting on an anim notify that never fires. A running ability always has active tasks
	-- (at least its animation), so also treat it as ended once its instance has had no active tasks for about a second. The ability itself is left alone
	-- since cancelling a genuinely running interaction locks the player in place.
	local idlePolls = 0
	local function waitForEnd()
		local component = uevrUtils.getValid(pawn, {"AblAbilityComponent"})
		for _, channel in ipairs(component and plugin.getProperty(component, "AblUberAbility.SortedAbilityChannels") or {}) do
			local instance = channel.ActiveAbilityInstance
			if instance ~= nil and instance.m_Ability ~= nil and instance.m_Ability:get_address() == abilityAddress then
				local tasks = #(plugin.getProperty(instance, "m_ActiveSyncTasks") or {}) + #(plugin.getProperty(instance, "m_ActiveAsyncTasks") or {})
				idlePolls = tasks > 0 and 0 or idlePolls + 1
				if idlePolls < 4 then delay(250, waitForEnd) return end
				break
			end
		end
		if firstPerson then
			uevrUtils.unregisterUEVRCallback("postEngineTick", updateProp)
			status.prop = nil
		else
			uevrUtils.setIsInCutsceneOverride(uevrUtils.getValid(pawn) ~= nil and pawn.InCinematic or nil)
		end
	end
	delay(500, waitForEnd)
end)

uevr.params.sdk.callbacks.on_script_reset(function()
	reset()
end)

uevrUtils.registerLevelChangeCallback(function()
	reset()
end)

return M