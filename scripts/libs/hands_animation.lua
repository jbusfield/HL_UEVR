local uevrUtils = require("libs/uevr_utils")
local attachments = require("libs/attachments")
local animation = require("libs/animation")

local M = {}

local holdingAttachment = {}
local inputHandlerAnimID = {}
local activeComponents = {}
local autoHandleInput = true
local disableAnimations = false --used during hand configuration to prevent loaded animation from interfering
-- A/B flag: when a hand's pose changes (attachment gripped or released), stop that hand's in-flight blends.
-- Otherwise a blend started just before the change finishes over the new pose and leaves the previous pose.
local cancelLerpsOnPoseChange = true
-- Only this XInput user index drives the automatic input handler (default 0). Games that also poll an empty controller slot
-- would otherwise read each grip/trigger as pressed then released every frame, so its blend restarts every frame and the
-- fingers never move. Opt out with setInputUserIndex(nil) to read every index, or pass another index.
local inputUserIndex = 0
-- When a hand is re-posed open (montage end, attachment released, hands created), any grip/trigger/thumb still held is put
-- straight back in its pressed pose in the same frame, so the hand never shows open. Otherwise a held input stays open until
-- it is released and pressed again. Opt out with setRestoreHeldInputsOnOpenPose(false).
local restoreHeldInputsOnOpenPose = true


local currentLogLevel = LogLevel.Error
function M.setLogLevel(val)
	currentLogLevel = val
end
function M.print(text, logLevel)
	if logLevel == nil then logLevel = LogLevel.Debug end
	if logLevel <= currentLogLevel then
		uevrUtils.print("[hands_animation] " .. text, logLevel)
	end
end

local function getAnimIDSuffix(animID)
	local arr = uevrUtils.splitStr(animID, "_")
	return #arr > 0 and arr[#arr] or nil
end


------------------- Hand parameters -------------------
-- This module is the only reader of the hands parameters file (hands_parameters.json by default). hands.lua and ik.lua take its
-- profiles and animations from here, so hands and IK arms always use the same file and the same profile and animation.
-- Other modules get the file's grip animation list through two events and never require this module:
--   "on_hand_animation_ids_changed" (info)   sent when the list changes: the file is loaded, or another file or table is set.
--   "get_hand_animation_ids" (out)           fills out.ids, out.labels and out.animations with the current list, for a module
--                                            that starts after the list was sent. out is left unchanged when this module is
--                                            not loaded; its lists are empty when there is no parameters file.
-- info.ids and info.labels are paired lists sorted by label (only the configured grip animations, no Default or None entry).
-- info.animations is the file's "attachments" table ({id = {label = ...}}), the form attachments.setAnimationIDs takes.
-- All of them are copies.
-- The file is read once and kept until Reset Scripts (level changes keep it), so an edit made to the file outside the game
-- takes effect after Reset Scripts.
local parametersFileName = "hands_parameters"
local parameters = nil
local parametersLoadTried = false
local preferredProfileName = nil
local preferredAnimationName = nil

local function copyTable(source)
	local result = {}
	for key, value in pairs(source) do
		result[key] = type(value) == "table" and copyTable(value) or value
	end
	return result
end

local function getAnimationIDInfo(params)
	local info = {ids = {}, labels = {}, animations = {}}
	local list = params ~= nil and params["attachments"] or nil
	if type(list) ~= "table" then return info end
	local entries = {}
	for id, data in pairs(list) do
		local label = type(data) == "table" and data["label"] or nil
		table.insert(entries, {id = id, label = label ~= nil and tostring(label) or tostring(id)})
		info.animations[id] = type(data) == "table" and copyTable(data) or data
	end
	table.sort(entries, function(a, b)
		if a.label == b.label then return tostring(a.id) < tostring(b.id) end
		return a.label < b.label
	end)
	for i, entry in ipairs(entries) do
		info.ids[i] = entry.id
		info.labels[i] = entry.label
	end
	return info
end

local function sendAnimationIDs()
	uevrUtils.executeUEVRCallbacks("on_hand_animation_ids_changed", getAnimationIDInfo(parameters))
end

-- The parameters file's name, without .json.
function M.getParametersFileName()
	return parametersFileName
end

-- Uses another parameters file (name without .json) for hands and IK arms. The file is read now and the grip animation list is
-- sent. The current file's name reads it now if it hasn't been read yet, and does nothing if it has.
function M.setParametersFileName(fileName)
	if fileName == nil or fileName == "" then return end
	if fileName ~= parametersFileName then
		parametersFileName = fileName
		parameters = nil
		parametersLoadTried = false
	end
	M.getParameters()
end

-- The parameters: the file's, read once, or the table given to setParameters. nil when the file is missing (it is not read again).
function M.getParameters()
	if parameters == nil and not parametersLoadTried then
		parametersLoadTried = true
		parameters = json.load_file(parametersFileName .. ".json")
		if parameters == nil then
			M.print("No hands parameters file " .. parametersFileName .. ".json", LogLevel.Info)
		else
			M.print("Loaded hands parameters from " .. parametersFileName .. ".json", LogLevel.Info)
			sendAnimationIDs()
		end
	end
	return parameters
end

-- Whether params is the table getParameters returns now (without reading the file).
function M.isCurrentParameters(params)
	return params ~= nil and params == parameters
end

-- Parameters given as a table (the hands config tool's, or a table passed to hands.createFromConfig). They are used in place of
-- the file's until another file is set, and the grip animation list is sent again. Call it again after changing the table's
-- "attachments" so the list is sent again.
function M.setParameters(params)
	if type(params) ~= "table" then return end
	parameters = params
	parametersLoadTried = true
	sendAnimationIDs()
end

-- A parameters file read once without keeping it, or the kept parameters when fileName is the current file. nil when missing.
function M.loadParametersFile(fileName)
	if fileName == nil or fileName == parametersFileName then return M.getParameters() end
	return json.load_file(fileName .. ".json")
end

-- Chooses which profile and animation of the parameters hands and IK arms use. A name that is nil or not in the parameters
-- falls back to the first one found.
function M.setActiveProfile(profileName, animationName)
	preferredProfileName = profileName
	preferredAnimationName = animationName
end

local function getActiveName(list, preferred)
	if type(list) ~= "table" then return nil end
	if preferred ~= nil and list[preferred] ~= nil then return preferred end
	for key, _ in pairs(list) do
		return key
	end
	return nil
end

-- The profile and animation names chosen in params (default: the current parameters), or nil when it has none.
function M.getActiveProfileName(params)
	if params == nil then params = M.getParameters() end
	if params == nil then return nil end
	return getActiveName(params["profiles"], preferredProfileName)
end

function M.getActiveAnimationName(params)
	if params == nil then params = M.getParameters() end
	if params == nil then return nil end
	return getActiveName(params["animations"], preferredAnimationName)
end

uevrUtils.registerUEVRCallback("get_hand_animation_ids", function(out)
	if type(out) ~= "table" then return end
	local info = getAnimationIDInfo(M.getParameters())
	out.ids, out.labels, out.animations = info.ids, info.labels, info.animations
end)

-- This needs to be called externally
function M.createAnimationHandler(animID, component, handAnimations)
    if component == nil then
        M.print("No component provided for animation handler creation for animID: " .. tostring(animID), LogLevel.Error)
        return
    end
    local suffix = getAnimIDSuffix(animID)
    if suffix ~= nil then inputHandlerAnimID[animID] = suffix end
    activeComponents[component] = animID
    animation.add(animID, component, handAnimations)
	animation.initialize(animID, component)
end

function M.destroyAnimationHandler(component)
    local animID = activeComponents[component]
    if animID ~= nil then
        inputHandlerAnimID[animID] = nil
    end
end

function M.reset()
	autoHandleInput = true
    disableAnimations = false
	inputHandlerAnimID = {}
    holdingAttachment = {}
    activeComponents = {}
end

function M.exists()
    return next(inputHandlerAnimID) ~= nil
end

local function forEachUniqueTarget(callback)
	local handledTargets = {}
	for _, target in pairs(inputHandlerAnimID) do
		if target ~= nil and not handledTargets[target] then
			handledTargets[target] = true
			callback(target)
		end
	end
end

local createInputHandler = doOnce(function()
	attachments.registerOnGripAnimationCallback(function(gripAnimation, gripHand)
		M.print("Grip animation changed to " .. (gripAnimation and tostring(gripAnimation) or "None") .. " for " .. (gripHand == Handed.Left and "Left" or "Right") .. " hand", LogLevel.Debug)
		--print("Grip animation changed to ", gripAnimation, gripHand)
		M.updateAnimationState(gripHand)
	end)

	uevrUtils.registerOnPreInputGetStateCallback(function(retval, user_index, state)
		if inputUserIndex ~= nil and user_index ~= inputUserIndex then return end
		if autoHandleInput and M.exists() then
			local rightAttachment = holdingAttachment[Handed.Right] or attachments.getCurrentGripAnimation(Handed.Right)
			local leftAttachment = holdingAttachment[Handed.Left] or attachments.getCurrentGripAnimation(Handed.Left)
			--M.handleInput(state, attachment, Handed.Right, nil, true)
			M.handleInputForHands(state, rightAttachment, leftAttachment, nil, true)
		end
	end, 10) --high priority to intercept messages before possible remapper
end, Once.EVER)
createInputHandler()

local function getAttachmentStateAndExtension(attachment)
	local isHoldingAttachment = false
	local attachmentExtension = ""
	if type(attachment) == "boolean" then
		isHoldingAttachment = attachment
	elseif type(attachment) == "string" and attachment ~= "attachment_none" then
		isHoldingAttachment = true
		if attachment ~= "" then
			attachmentExtension = "_" .. attachment
		end
	end
	return isHoldingAttachment, attachmentExtension
end

function M.setAutoHandleInput(val)
	autoHandleInput = val
end

function M.setInputUserIndex(val)
	inputUserIndex = val
end

function M.disableAnimations(value)
	disableAnimations = value
end

function M.setCancelLerpsOnPoseChange(value)
	cancelLerpsOnPoseChange = value
end

function M.setRestoreHeldInputsOnOpenPose(value)
	restoreHeldInputsOnOpenPose = value
end

function M.setHoldingAttachment(hand, val)
	holdingAttachment[hand] = val
	M.updateAnimationState(hand)
end

function M.updateAnimationState(hand)
	if M.exists() then
		local attachment = holdingAttachment[hand]
		if attachment == nil then
			attachment = attachments.getCurrentGripAnimation(hand)
		end
		M.print("Updating animation state for " .. (hand == Handed.Left and "Left" or "Right") .. " hand with attachment: " .. (type(attachment) == "string" and attachment or tostring(attachment)), LogLevel.Debug)
		local isHoldingAttachment, attachmentExtension = getAttachmentStateAndExtension(attachment)
		M.print("Is holding attachment: " .. tostring(isHoldingAttachment), LogLevel.Debug)

		if isHoldingAttachment then
			forEachUniqueTarget(function(target)
				local handStr = hand == Handed.Left and "left" or "right"
				if cancelLerpsOnPoseChange then animation.cancelLerps(handStr .. "_" .. target) end
				animation.resetAnimation(handStr.."_"..target, handStr.."_grip_weapon" .. attachmentExtension, true) --forces an update regardless of current state
				animation.resetAnimation(handStr.."_"..target, handStr.."_trigger_weapon" .. attachmentExtension, true) --forces an update regardless of current state
				animation.pose(handStr .. "_" .. target, "grip_" .. handStr .. "_weapon" .. attachmentExtension)
			end)
		else
			forEachUniqueTarget(function(target)
				local handStr = hand == Handed.Left and "left" or "right"
				if cancelLerpsOnPoseChange then animation.cancelLerps(handStr .. "_" .. target) end
				animation.pose(handStr .. "_" .. target, "open_" .. handStr)
				if restoreHeldInputsOnOpenPose then
					local animID = handStr .. "_" .. target
					for _, input in ipairs({"_grip", "_trigger", "_thumb"}) do
						if animation.isAnimationOn(animID, handStr .. input) then
							animation.animate(animID, handStr .. input, "on")
						end
					end
				end
			end)
		end
	end
end
M.updateAnimationState = uevrUtils.profiler:wrap("Hand Animations: updateAnimationState", M.updateAnimationState)

function M.handleInputForHands(state, rightAttachment, leftAttachment, overrideTrigger, allowAutoHandle)
	if allowAutoHandle ~= true then
		autoHandleInput = false --if something else is calling this then dont auto handle input
	end
	if disableAnimations then
		--print("Animations are disabled, skipping handleInputForHands")
		return true
	end

	if overrideTrigger == nil then overrideTrigger = false end
	local animDuration = 0.1
	forEachUniqueTarget(function(target)
		for hand = Handed.Left, Handed.Right do
			local handStr = hand == Handed.Right and "right" or "left"
			--do not use ternary operators like this. If right attachment is nil then it will always pick leftAttachment for Handed.Right == true
			--local attachment = hand == Handed.Right and rightAttachment or leftAttachment
			local attachment = nil
			if hand == Handed.Right then attachment = rightAttachment else attachment = leftAttachment end
			local isHoldingAttachment, attachmentExtension = getAttachmentStateAndExtension(attachment)
			--print("Handling input for " .. handStr .. " hand, attachment: " .. (type(attachment) == "string" and attachment or tostring(attachment)) .. ", isHoldingAttachment: " .. tostring(isHoldingAttachment) .. ", attachmentExtension: " .. attachmentExtension)

			if not isHoldingAttachment then
				local weaponHandTriggerValue = (hand == Handed.Right or overrideTrigger) and state.Gamepad.bRightTrigger or state.Gamepad.bLeftTrigger
				animation.updateAnimation(handStr.."_"..target, handStr.."_trigger", weaponHandTriggerValue > 100, {duration=animDuration})
				animation.updateAnimation(handStr.."_"..target, handStr.."_grip", uevrUtils.isButtonPressed(state, hand == Handed.Right and XINPUT_GAMEPAD_RIGHT_SHOULDER or XINPUT_GAMEPAD_LEFT_SHOULDER), {duration=animDuration})

				local weaponhandController = uevr.params.vr.get_right_joystick_source()
				if not (hand == Handed.Right) then weaponhandController = uevr.params.vr.get_left_joystick_source() end
				local weaponhandRest = uevr.params.vr.get_action_handle(hand == Handed.Right and "/actions/default/in/ThumbrestTouchRight" or "/actions/default/in/ThumbrestTouchLeft")
				animation.updateAnimation(handStr.."_"..target, handStr.."_thumb", uevr.params.vr.is_action_active(weaponhandRest, weaponhandController), {duration=animDuration})
			else
				local weaponHandTriggerValue = (hand == Handed.Right or overrideTrigger) and state.Gamepad.bRightTrigger or state.Gamepad.bLeftTrigger
				animation.updateAnimation(handStr.."_"..target, handStr.."_trigger_weapon" .. attachmentExtension, weaponHandTriggerValue > 100, {duration=animDuration})
				local isButtonPressed = uevrUtils.isButtonPressed(state, hand == Handed.Right and XINPUT_GAMEPAD_RIGHT_SHOULDER or XINPUT_GAMEPAD_LEFT_SHOULDER)
				animation.updateAnimation(handStr.."_"..target, handStr.."_grip_weapon" .. attachmentExtension, isButtonPressed, {duration=animDuration})
			end
		end
	end)
end

--deprecated
function M.handleInput(state, attachment, hand, overrideTrigger, allowAutoHandle)
	if allowAutoHandle ~= true then
		autoHandleInput = false --if something else is calling this then dont auto handle input
	end
	if disableAnimations then
		--print("Animations are disabled, skipping handleInput")
		return true
	end

	local isHoldingAttachment, attachmentExtension = getAttachmentStateAndExtension(attachment)

	if hand == nil then hand = Handed.Right end
	if overrideTrigger == nil then overrideTrigger = false end
	local isRightHanded = hand == Handed.Right
	local weaponHandStr = isRightHanded and "right" or "left"
	local offHandStr = isRightHanded and "left" or "right"
	local animDuration = 0.1
	forEachUniqueTarget(function(target)
		local offhandTriggerValue = (isRightHanded or overrideTrigger) and state.Gamepad.bLeftTrigger or state.Gamepad.bRightTrigger
		animation.updateAnimation(offHandStr.."_"..target, offHandStr.."_trigger", offhandTriggerValue > 100, {duration=animDuration})

		animation.updateAnimation(offHandStr.."_"..target, offHandStr.."_grip", uevrUtils.isButtonPressed(state, isRightHanded and XINPUT_GAMEPAD_LEFT_SHOULDER or XINPUT_GAMEPAD_RIGHT_SHOULDER), {duration=animDuration})

		local offhandController = uevr.params.vr.get_left_joystick_source()
		if not isRightHanded then offhandController = uevr.params.vr.get_right_joystick_source() end
		local offhandRest = uevr.params.vr.get_action_handle(isRightHanded and "/actions/default/in/ThumbrestTouchLeft" or "/actions/default/in/ThumbrestTouchRight")
		animation.updateAnimation(offHandStr.."_"..target, offHandStr.."_thumb", uevr.params.vr.is_action_active(offhandRest, offhandController), {duration=animDuration})

		if not isHoldingAttachment then
			local weaponHandTriggerValue = (isRightHanded or overrideTrigger) and state.Gamepad.bRightTrigger or state.Gamepad.bLeftTrigger
			animation.updateAnimation(weaponHandStr.."_"..target, weaponHandStr.."_trigger", weaponHandTriggerValue > 100, {duration=animDuration})

			animation.updateAnimation(weaponHandStr.."_"..target, weaponHandStr.."_grip", uevrUtils.isButtonPressed(state, isRightHanded and XINPUT_GAMEPAD_RIGHT_SHOULDER or XINPUT_GAMEPAD_LEFT_SHOULDER), {duration=animDuration})

			local weaponhandController = uevr.params.vr.get_right_joystick_source()
			if not isRightHanded then weaponhandController = uevr.params.vr.get_left_joystick_source() end
			local weaponhandRest = uevr.params.vr.get_action_handle(isRightHanded and "/actions/default/in/ThumbrestTouchRight" or "/actions/default/in/ThumbrestTouchLeft")
			animation.updateAnimation(weaponHandStr.."_"..target, weaponHandStr.."_thumb", uevr.params.vr.is_action_active(weaponhandRest, weaponhandController), {duration=animDuration})
		else
			local weaponHandTriggerValue = (isRightHanded or overrideTrigger) and state.Gamepad.bRightTrigger or state.Gamepad.bLeftTrigger
			animation.updateAnimation(weaponHandStr.."_"..target, weaponHandStr.."_trigger_weapon" .. attachmentExtension, weaponHandTriggerValue > 100, {duration=animDuration})
			if uevrUtils.isButtonPressed(state, isRightHanded and XINPUT_GAMEPAD_RIGHT_SHOULDER or XINPUT_GAMEPAD_LEFT_SHOULDER) then
				animation.resetAnimation(weaponHandStr.."_"..target, weaponHandStr.."_grip_weapon" .. attachmentExtension, false) --forces an update regardless of current state
--print("Here",weaponHandStr.."_"..target,weaponHandStr.."_grip_weapon" .. attachmentExtension)
				animation.updateAnimation(weaponHandStr.."_"..target, weaponHandStr.."_grip_weapon" .. attachmentExtension, true, {duration=animDuration})
			end
		end
	end)
end

uevrUtils.registerUEVRCallback("on_module_montage_change", function(montageObject, montageName, label, animInstance)
	if montageName == nil or montageName == "" then
		M.updateAnimationState(Handed.Left)
		M.updateAnimationState(Handed.Right)
	end
end)

uevr.params.sdk.callbacks.on_script_reset(function()
	M.reset()
end)

uevrUtils.registerPreLevelChangeCallback(function(level)
	M.reset()
end)

return M