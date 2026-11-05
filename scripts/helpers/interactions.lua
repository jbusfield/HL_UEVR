local uevrUtils = require('libs/uevr_utils')
local plugin = require('libs/core/plugin')
local controllers = require('libs/controllers')
local configui = require('libs/configui')
local grabbable = require('libs/grabbable')
local prompts = require('libs/prompts')
local GRIP_PRIORITY = require('helpers/grip_priority')
local gestures = require('libs/gestures')
local accessories = require('libs/accessories')

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

------------------- Physical item grab -------------------
-- Hogwarts Legacy settings for libs/grabbable: a grip on a loot bag or inventory item (e.g. a wolf pelt) flies it into that hand; the
-- right hand only grabs while it has nothing else (the wand drawn, a mount's accessory). Releasing at that hand's ear collects it with
-- the game's X, releasing elsewhere throws or drops it. A left grip on any other interaction prompt holds X. main.lua's grip update
-- callback attaches the left hand's copy (getHeldItemMesh); libs/grabbable attaches the right hand's.
-- Loot bags by class name; anything derived from Phoenix.InventoryObject is grabbable too. Breakables such as moonstones are neither.
local GRAB_CLASSES = {BP_LootDrop_Container_C = true}
local GRAB_SCAN_INTERVAL = 250 -- ms between prompt icon checks (and palm pointing scans)
local PROMPT_GRIP_KEY = "InputAction_AM_ItemMenu" -- Item Menu action, LB on a gamepad
local PROMPT_INTERACT_KEY = "InputAction_AM_Interact" -- the prompt's own key (X on a gamepad)

-- Dev and A/B flags:
-- GRAB_TOGGLE_GRIP: the grip toggles (press to grab, the item stays after release, press again to collect at the ear or drop),
--   for adjusting attachment transforms hands-free. No throwing in this mode.
-- GRAB_PROMPT_ICON: the game's interaction prompt shows the left grip's button (LB) instead of X.
-- GRAB_REQUIRE_POINTING: items are chosen by pointing the left palm at them instead of by the interaction prompt.
local GRAB_TOGGLE_GRIP = false
local GRAB_PROMPT_ICON = true
local GRAB_REQUIRE_POINTING = false
--Use real physics for dropped or thrown items
grabbable.useRealPhysics(true)

local inventoryObjectClass, callOutClass, stencilManager, targetEffect = nil, nil, nil, nil
local itemGrab = nil -- created below; canClaim asks it whether the other hand is holding an item

local function isGrabbable(actor)
	inventoryObjectClass = inventoryObjectClass or uevrUtils.get_class("Class /Script/Phoenix.InventoryObject")
	return GRAB_CLASSES[actor:get_class():get_fname():to_string()] == true or (inventoryObjectClass ~= nil and actor:is_a(inventoryObjectClass))
end

-- What the game's interaction prompt (callout) is on. The right hand only grabs: a prompt on anything else is left to the left grip.
local function getInteractTarget(state, hand)
	local target = uevrUtils.getValid(pawn, {"Controller", "CurrentInteractTarget"})
	if hand == Handed.Right and target ~= nil and not isGrabbable(target) then return nil end
	return target
end

-- The LB+RB Ancient Magic chord (a hand doesn't claim while the other grip is down), a mount's accessory the hand holds or would grip,
-- and the left mouth grip gesture take precedence over grabbing and interacting. An open palette wheel and the left ear grip (menu) take
-- precedence through their own grip claims; a drawn wand keeps the right hand busy (libs/grabbable).
local function canClaim(state, hand)
	if configui.getValue("left_handed_mode") then return false end
	-- The other grip holding an item is a hold, not half of the chord (e.g. a hand-to-hand handoff).
	local otherHand = hand == Handed.Left and Handed.Right or Handed.Left
	if uevrUtils.isButtonPressed(state, otherHand == Handed.Right and XINPUT_GAMEPAD_RIGHT_SHOULDER or XINPUT_GAMEPAD_LEFT_SHOULDER)
		and not (itemGrab ~= nil and itemGrab:isHolding(otherHand)) then return false end
	if accessories.isGripHandEngaged(hand) then return false end
	if hand ~= Handed.Left then return true end
	local gripMouth = gestures.getHeadGestures(state, Handed.Left, true)
	return not gripMouth
end

-- Same stencil effect the game uses for its white target outline on shootable objects (palm pointing only).
local function setHighlight(actor, on)
	stencilManager = stencilManager or uevrUtils.find_default_instance("Class /Script/StencilManager.StencilManager")
	if stencilManager == nil then return end
	targetEffect = targetEffect or uevrUtils.fname_from_string("Target")
	stencilManager:SetStencilEffect(actor, targetEffect, on)
end

itemGrab = grabbable.new({
	names = {[Handed.Left] = "item_grab", [Handed.Right] = "item_grab_right"},
	claimPriority = GRIP_PRIORITY.ITEM_GRAB,
	heldPriority = GRIP_PRIORITY.ITEM_HELD,
	hands = {Handed.Left, Handed.Right},
	isGrabbable = isGrabbable,
	canClaim = canClaim,
	getInteractTarget = getInteractTarget,
	interactButton = XINPUT_GAMEPAD_X,
	-- The hidden item sits at the hand, so the game's X targets it.
	isCollectGesture = function(state, hand)
		local _, _, _, gripEar = gestures.getHeadGestures(state, hand, true)
		return gripEar
	end,
	collectButton = XINPUT_GAMEPAD_X,
	-- Drawing the wand into the right hand drops what it holds; an open palette only makes a left-hand item wait.
	dropWhenHandTaken = {[Handed.Right] = true},
	toggleGrip = GRAB_TOGGLE_GRIP,
	-- Full 0.4 s flight from 1 m or more; a grab right next to the hand (e.g. a catch) is almost immediate.
	flightDistance = 100,
	dropRescaleTime = 0.5,
	-- Barely rescales right after release, most of it near the end of the drop.
	dropRescaleEase = 3,
	-- Keeps its release size this long first, so a toss to the other hand doesn't visibly rescale.
	dropRescaleDelay = .4,
	pointing = {
		enabled = GRAB_REQUIRE_POINTING,
		highlight = setHighlight,
		scanInterval = GRAB_SCAN_INTERVAL,
		-- The overlap scan only runs while the game reports an interactable nearby; its interaction range and the grab range feel the same.
		shouldScan = function()
			local controller = uevrUtils.getValid(pawn, {"Controller"})
			return controller ~= nil and controller.bNearInteractable == true and not configui.getValue("left_handed_mode")
		end,
	},
})

-- The prompt is the target's CallOutComponent widget (UI_BP_InteractBlip_C), whose ButtonCallout shows the button. The game creates and
-- reuses these widgets and sets the Interact key whenever one is shown; libs/prompts checks it every interval, switches it to the grip's
-- key, and puts the game's key back when the swap stops applying, the feature is turned off, or on level change and script reset.
-- FString values read from Lua can carry a hidden trailing null character (as spells.lua handles for spell names), so strip it before comparing.
local promptIcon = prompts.new({
	interval = GRAB_SCAN_INTERVAL,
	getPrompts = function()
		local target = getInteractTarget()
		if target == nil then return nil end
		callOutClass = callOutClass or uevrUtils.get_class("Class /Script/Phoenix.CallOutComponent")
		local widget = callOutClass ~= nil and uevrUtils.getValid(target:GetComponentByClass(callOutClass), {"Widget"}) or nil
		local button = uevrUtils.getValid(widget, {"ButtonCallout"})
		return button ~= nil and {button} or nil
	end,
	get = function(button)
		local key = button.LocalizationKey
		return type(key) == "string" and (key:gsub("%z", "")) or nil
	end,
	set = function(button, key)
		button:SetTextKey(key)
	end,
	getReplacement = function(button, original)
		if original == PROMPT_INTERACT_KEY and not configui.getValue("left_handed_mode") then return PROMPT_GRIP_KEY end
		return nil
	end,
})

function M.setItemGrabEnabled(value)
	local enabled = value == true
	itemGrab:setEnabled(enabled)
	promptIcon:setEnabled(enabled and GRAB_PROMPT_ICON)
end

-- The copy of the item's mesh in hand, attached (hidden during the flight) from the start of a grab, for main.lua's grip update
-- callback (left hand).
function M.getHeldItemMesh(hand)
	return itemGrab:getHeldMesh(hand)
end

-- True while an item is in hand, and for the rest of a grip press that grabbed, collected or dropped one,
-- so main.lua's grip head gestures stand aside (an ear release collect must not go on to open the menu).
function M.isHoldingItem(hand)
	return itemGrab:isHolding(hand)
end
------------------- End physical item grab -------------------

uevr.params.sdk.callbacks.on_script_reset(function()
	reset()
end)

uevrUtils.registerLevelChangeCallback(function()
	reset()
end)

return M