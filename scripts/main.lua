local uevrUtils = require('libs/uevr_utils')
local controllers = require('libs/controllers')
local configui = require("libs/configui")
local reticule = require("libs/reticule")
local hands = require('libs/hands')
local attachments = require('libs/attachments')
local accessories = require('libs/accessories')
local input = require('libs/input')
local pawnModule = require('libs/pawn')
local montage = require('libs/montage')
local interaction = require('libs/interaction')
local ui = require('libs/ui')
local remap = require('libs/remap')
local gestures = require('libs/gestures')
--local gunstock = require('libs/gunstock')
local scopes = require('libs/scope')
local ik = require('libs/ik')
local animation = require('libs/animation')
local collision = require('libs/collision')
local laser = require('libs/laser')
local particles = require('libs/particles')
local plugin = require('libs/core/plugin')
local widgetModule = require('libs/widget')
local gestureTrainer = require('libs/config/gesture_trainer')
local spells = require('helpers/spells')
local mouse = require('libs/mouse')
local mounts = require('helpers/mounts')
local interactions = require('helpers/interactions')
local locomotion = require('helpers/locomotion')

--local dev = require('libs/uevr_dev')
--dev.init()

local BROOM_ACCESSORY_KEY = "Broom"
local function getBroomAccessoryMesh(hand)
	if uevrUtils.isInCutscene() then return nil end
	local mountType = mounts.getMountType()
	if mountType ~= mounts.EMountTypes.Broom_Flying and mountType ~= mounts.EMountTypes.Broom_Ground then return nil end
	if hand ~= nil then
		local handsType = configui.getValue("hands_type") or 1
		if handsType == 1 and #hands.getHandComponentsForHand(hand) == 0 then return nil end
		if handsType == 2 and not ik.exists() then return nil end
	end
	local currentPawn = uevrUtils.getValid(pawn)
	local riderMesh = currentPawn and uevrUtils.getValid(currentPawn.Mesh)
	local parent = riderMesh and uevrUtils.getValid(riderMesh.AttachParent)
	if parent == nil or not string.find(parent:get_full_name(), "Broom", 1, true) then return nil end
	return parent
end


local function getBroomAccessoryWidgets()
	local widgets = accessories.getConfigWidgets(BROOM_ACCESSORY_KEY, "broom_", 300)
	for _, widget in ipairs(widgets) do
		if widget.id == "broom_accessory_item_socket_finder_instructions" then
			widget.label = "Mount a broom and press Refresh to list its sockets."
		end
	end
	return widgets
end

local HIPPOGRIFF_ACCESSORY_KEY = "Hippogriff"
local function getHippogriffAccessoryMesh(hand)
	if uevrUtils.isInCutscene() then return nil end
	local mountType = mounts.getMountType()
	if mountType ~= mounts.EMountTypes.Hippogriff_Flying and mountType ~= mounts.EMountTypes.Hippogriff_Ground then return nil end
	if hand ~= nil then
		local handsType = configui.getValue("hands_type") or 1
		if handsType == 1 and #hands.getHandComponentsForHand(hand) == 0 then return nil end
		if handsType == 2 and not ik.exists() then return nil end
	end
	return uevrUtils.getValid(pawn, {"Mesh"})
end

local function getHippogriffAccessoryWidgets()
	local widgets = accessories.getConfigWidgets(HIPPOGRIFF_ACCESSORY_KEY, "hippogriff_", 300)
	for _, widget in ipairs(widgets) do
		if widget.id == "hippogriff_accessory_item_socket_finder_instructions" then
			widget.label = "Mount a hippogriff and press Refresh to list its sockets."
		end
	end
	return widgets
end

local GRAPHORN_ACCESSORY_KEY = "Graphorn"
local function getGraphornAccessoryMesh(hand)
	if uevrUtils.isInCutscene() then return nil end
	local mountType = mounts.getMountType()
	if mountType ~= mounts.EMountTypes.Graphorn_Ground then return nil end
	if hand ~= nil then
		local handsType = configui.getValue("hands_type") or 1
		if handsType == 1 and #hands.getHandComponentsForHand(hand) == 0 then return nil end
		if handsType == 2 and not ik.exists() then return nil end
	end
	return uevrUtils.getValid(pawn, {"Mesh"})
end

local function getGraphornAccessoryWidgets()
	local widgets = accessories.getConfigWidgets(GRAPHORN_ACCESSORY_KEY, "graphorn_", 300)
	for _, widget in ipairs(widgets) do
		if widget.id == "graphorn_accessory_item_socket_finder_instructions" then
			widget.label = "Mount a graphorn and press Refresh to list its sockets."
		end
	end
	return widgets
end

accessories.setTargetProvider(function(hand)
	local broomMesh = getBroomAccessoryMesh(hand)
	if broomMesh ~= nil then return broomMesh, BROOM_ACCESSORY_KEY end
	local hippogriffMesh = getHippogriffAccessoryMesh(hand)
	if hippogriffMesh ~= nil then return hippogriffMesh, HIPPOGRIFF_ACCESSORY_KEY end
	local graphornMesh = getGraphornAccessoryMesh(hand)
	if graphornMesh ~= nil then return graphornMesh, GRAPHORN_ACCESSORY_KEY end
end)
accessories.setSocketProvider(BROOM_ACCESSORY_KEY, function(callback)
	local broomMesh = getBroomAccessoryMesh()
	if broomMesh ~= nil then
		uevrUtils.getSocketNames(broomMesh, callback)
	else
		callback(nil)
	end
end)
accessories.setSocketProvider(HIPPOGRIFF_ACCESSORY_KEY, function(callback)
	local hippogriffMesh = getHippogriffAccessoryMesh()
	if hippogriffMesh ~= nil then
		uevrUtils.getSocketNames(hippogriffMesh, callback)
	else
		callback(nil)
	end
end)
accessories.setSocketProvider(GRAPHORN_ACCESSORY_KEY, function(callback)
	local graphornMesh = getGraphornAccessoryMesh()
	if graphornMesh ~= nil then
		uevrUtils.getSocketNames(graphornMesh, callback)
	else
		callback(nil)
	end
end)

--uevrUtils.setLogLevel(LogLevel.Debug)
-- reticule.setLogLevel(LogLevel.Debug)
-- input.setLogLevel(LogLevel.Debug)
-- attachments.setLogLevel(LogLevel.Debug)
-- animation.setLogLevel(LogLevel.Debug)
-- ui.setLogLevel(LogLevel.Debug)
-- remap.setLogLevel(LogLevel.Debug)
-- hands.setLogLevel(LogLevel.Debug)
-- widgetModule.setLogLevel(LogLevel.Debug)
-- ik.setLogLevel(LogLevel.Debug)
--spells.setLogLevel(LogLevel.Debug)

--uevrUtils.setDeveloperMode(true)
--hands.enableConfigurationTool()
--uevrUtils.profiler:toggle(true)

gestureTrainer.init()
ui.init()
ui.setRequireWidgetVisibility(true)
montage.init()
interaction.init()
attachments.init()
attachments.setLaserColor("#00FF00FF")
reticule.init()
reticule.setHiddenWhenScopeActive(true)
pawnModule.init()
remap.init()
input.init()
gestures.init()
--gunstock.showConfiguration()
scopes.setDefaultPitchOffset(90.0)
ik.init()
collision.init()
particles.init()
hands.setAutoCreateHands(false)
ik.setAutoCreateArms(false)

uevrUtils.set_roomscale_active(true)

local isDeveloperMode = false
if uevrUtils.getDeveloperMode() ~= nil then
	isDeveloperMode = uevrUtils.getDeveloperMode() or false
end

-- v2.0.3
-- Basic cast no longer pauses character movement
-- Accio flying page problem fixed
-- The game's Levioso glyph drawing shape also works in addition to the quick version shown in the spell screen
-- Fixed Viaspecto missing glyph
local versionTxt = "v2.0.3"
local title = "Hogwarts Legacy First Person Mod " .. versionTxt
local configDefinition = {
	{
		panelLabel = "Hogwarts Legacy Config",
		saveFile = "hogwarts_legacy_config",
		layout = spliceableInlineArray
		{
			{ widgetType = "text", id = "title", label = title },
			{ widgetType = "indent", width = 20 }, { widgetType = "text", label = "General" }, { widgetType = "begin_rect", },
                {
                    widgetType = "combo",
                    id = "hands_type",
                    label = "Hands Type",
                    selections = {"Hands Only", "IK Arms"},
                    initialValue = 1,
					width = 150
                },
				{
					widgetType = "drag_float3",
					id = "custom_glove_wand_position_right",
					label = "Custom Glove Wand Position (Right)",
					speed = 0.1,
					range = {-50, 50},
					initialValue = {-1.131, -9.719, -0.594},
					isHidden = not isDeveloperMode,
				},
				{
					widgetType = "drag_float3",
					id = "custom_glove_wand_rotation_right",
					label = "Custom Glove Wand Rotation (Right)",
					speed = 0.5,
					range = {-180, 180},
					initialValue = {10.153, 90.0, -12.754},
					isHidden = not isDeveloperMode,
				},
				{
					widgetType = "drag_float3",
					id = "custom_glove_wand_position_left",
					label = "Custom Glove Item Position (Left)",
					speed = 0.1,
					range = {-50, 50},
					initialValue = {0, 0, 0},
					isHidden = not isDeveloperMode,
				},
				{
					widgetType = "drag_float3",
					id = "custom_glove_wand_rotation_left",
					label = "Custom Glove Item Rotation (Left)",
					speed = 0.5,
					range = {-180, 180},
					initialValue = {0, 0, 0},
					isHidden = not isDeveloperMode,
				},
				{
					widgetType = "checkbox",
					id = "use_auto_targeting",
					label = "Use Auto Targeting",
					initialValue = false
				},
				{
					widgetType = "checkbox",
					id = "use_volumetric_fog",
					label = "Use Volumetric Fog",
					initialValue = true
				},
				{
					widgetType = "checkbox",
					id = "use_controller_mouse",
					label = "Controller Based Mouse Movement in Menus",
					initialValue = true
				},

			{ widgetType = "end_rect", additionalSize = 12, rounding = 5 }, { widgetType = "unindent", width = 20 },
			{ widgetType = "new_line" },

			{ widgetType = "indent", width = 20 }, { widgetType = "text", label = "Control" }, { widgetType = "begin_rect", },
				{
					widgetType = "checkbox",
					id = "left_arm_block",
					label = "Left Arm Raise for Protego",
					initialValue = true,
				},
				{ widgetType = "indent", width = 20 },
					{
						widgetType = "text",
						id = "left_arm_block_info",
						wrapped = true,
						label = "Raise your left arm in front of your face with palm out for Protego",
					},
				{ widgetType = "unindent", width = 20 },
			{ widgetType = "end_rect", additionalSize = 12, rounding = 5 }, { widgetType = "unindent", width = 20 },
			{ widgetType = "new_line" },

			{ widgetType = "begin_group", id = "mount_dev_group", isHidden = not isDeveloperMode },
			{ widgetType = "indent", width = 20 }, { widgetType = "text", label = "Mounts" }, { widgetType = "begin_rect", },
				{
					widgetType = "checkbox",
					id = "use_mount_hand_controlled_movement",
					label = "Hand Controlled Movement",
					initialValue = true,
				},
				{ widgetType = "begin_group", id = "use_mount_hand_controlled_movement_group" },{ widgetType = "indent", width = 20 },
					{ widgetType = "text", wrapped = true, id = "mount_hand_controlled_movement_help", label = "Pitch your hands up and down to make the mount fly up and dive. Roll your hands left and right to make the mount turn left and right. " },
				{ widgetType = "unindent", width = 20 },{ widgetType = "end_group", },
				
				{ widgetType = "tree_node", id = "mount_broom_tree", initialOpen = true, label = "Broom" },
					{
						widgetType = "checkbox",
						id = "follow_broom_roll",
						label = "Follow Bank in High Speed Turns",
						initialValue = false,
					},
					{ widgetType = "text", wrapped = true, id = "broom_roll_help", label = "Pitch always follows the rider. Enable this to tilt with the rider in high speed turns." },
					{
						widgetType = "slider_float",
						id = "broom_max_rise_pitch_offset",
						label = "Pitch Offset at Max Rise (deg)",
						initialValue = 0,
						speed = 0.5,
						range = {-45, 45},
					},
					{
						widgetType = "slider_float",
						id = "broom_max_dive_pitch_offset",
						label = "Pitch Offset at Max Dive (deg)",
						initialValue = 0,
						speed = 0.5,
						range = {-45, 45},
					},
					{ widgetType = "text", wrapped = true, id = "broom_pitch_offset_help", label = "Offsets blend from zero when the broom is level to these values at full rise or dive." },
					{
						widgetType = "slider_float",
						id = "broom_high_speed_head_offset",
						label = "High Speed Head Forward/Back (cm)",
						initialValue = 0,
						speed = 1,
						range = {-75, 75},
					},
					{ widgetType = "text", wrapped = true, id = "broom_head_offset_help", label = "Negative moves your view toward the broom tail; positive moves it toward the front. Standstill and normal speed are unchanged." },
					{ widgetType = "text", wrapped = true, id = "broom_grip_help", label = "Add left and right accessories below. Choose hand proximity, grip, or grip toggle, then tune each hand position while mounted." },
					expandArray(getBroomAccessoryWidgets),
				{ widgetType = "tree_pop" },
             	{ widgetType = "tree_node", id = "mount_hippogriff_tree", initialOpen = true, label = "Hippogriff" },
					{
						widgetType = "checkbox",
						id = "use_hippogriff_hand_controlled_movement",
						label = "Hand Controlled Movement",
						initialValue = true,
					},
					{ widgetType = "begin_group", id = "use_hippogriff_hand_controlled_movement_group" },{ widgetType = "indent", width = 20 },
						{ widgetType = "text", wrapped = true, id = "hippogriff_hand_controlled_movement_help", label = "Pitch your hands up and down to make the hippogriff fly up and dive. Roll your hands left and right to make the hippogriff turn left and right. " },
						{
							widgetType = "slider_float",
							id = "hippogriff_pitch_offset",
							label = "Pitch Offset",
							initialValue = 0,
							speed = 1,
							range = {-45, 45},
						},
					{ widgetType = "unindent", width = 20 },{ widgetType = "end_group", },
					-- {
					-- 	widgetType = "checkbox",
					-- 	id = "use_hippogriff_autofly",
					-- 	label = "Autofly",
					-- 	initialValue = true,
					-- },
					-- { widgetType = "indent", width = 20 },
					-- 	{ widgetType = "text", wrapped = true, id = "hippogriff_autofly_help", label = "When enabled, double-tap the left stick forward while flying to lock forward flight. Double-tap forward again or push back to release. " },
					-- { widgetType = "unindent", width = 20 },
					{ widgetType = "text", wrapped = true, id = "hippogriff_grip_help", label = "Add left and right accessories below. Choose hand proximity, grip, or grip toggle, then tune each hand position while mounted." },
						expandArray(getHippogriffAccessoryWidgets),
				{ widgetType = "tree_pop" },

				{ widgetType = "tree_node", id = "mount_graphorn_tree", initialOpen = true, label = "Graphorn" },
					{
						widgetType = "checkbox",
						id = "use_graphorn_hand_controlled_movement",
						label = "Hand Controlled Movement",
						initialValue = true,
					},
					-- { widgetType = "begin_group", id = "use_hippogriff_hand_controlled_movement_group" },{ widgetType = "indent", width = 20 },
					-- 	{ widgetType = "text", wrapped = true, id = "hippogriff_hand_controlled_movement_help", label = "Pitch your hands up and down to make the hippogriff fly up and dive. Roll your hands left and right to make the hippogriff turn left and right. " },
					-- 	{
					-- 		widgetType = "slider_float",
					-- 		id = "hippogriff_pitch_offset",
					-- 		label = "Pitch Offset",
					-- 		initialValue = 0,
					-- 		speed = 1,
					-- 		range = {-45, 45},
					-- 	},
					-- { widgetType = "unindent", width = 20 },{ widgetType = "end_group", },
					-- {
					-- 	widgetType = "checkbox",
					-- 	id = "use_hippogriff_autofly",
					-- 	label = "Autofly",
					-- 	initialValue = true,
					-- },
					-- { widgetType = "indent", width = 20 },
					-- 	{ widgetType = "text", wrapped = true, id = "hippogriff_autofly_help", label = "When enabled, double-tap the left stick forward while flying to lock forward flight. Double-tap forward again or push back to release. " },
					-- { widgetType = "unindent", width = 20 },
					{ widgetType = "text", wrapped = true, id = "graphorn_grip_help", label = "Add left and right accessories below. Choose hand proximity, grip, or grip toggle, then tune each hand position while mounted." },
						expandArray(getGraphornAccessoryWidgets),
				{ widgetType = "tree_pop" },
			{ widgetType = "end_rect", additionalSize = 12, rounding = 5 }, { widgetType = "unindent", width = 20 },
			{ widgetType = "new_line" },
			{ widgetType = "end_group", },

			{ widgetType = "indent", width = 20 }, { widgetType = "text", label = "Spell Gesture Detection" }, { widgetType = "begin_rect", },
				{
					widgetType = "checkbox",
					id = "use_gesture_detection",
					label = "Enable",
					initialValue = true,
				},
				{ widgetType = "begin_group", id = "use_gesture_detection_group" },{ widgetType = "indent", width = 20 },
					{
						widgetType = "slider_float",
						id = "gesture_min_confidence",
						label = "Minimum Confidence",
						initialValue = .60,
						speed = 0.01,
						range = {0, 1},
					},
					{
						widgetType = "slider_float",
						id = "gesture_cast_delay",
						label = "Gesture Cast Delay (secs)",
						initialValue = .30,
						speed = 0.01,
						range = {0, 1},
					},
					{
						widgetType = "drag_float3",
						id = "hand_spell_icon_position",
						label = "Hand Spell Icon Position",
						speed = 0.1,
						range = {-50, 50},
						initialValue = {5, 0, 8},
						isHidden = not isDeveloperMode,
					},
					{
						widgetType = "drag_float3",
						id = "hand_spell_icon_rotation",
						label = "Hand Spell Icon Rotation",
						speed = 0.5,
						range = {-180, 180},
						initialValue = {0, 180, 0},
						isHidden = not isDeveloperMode,
					},
					{
						widgetType = "slider_float",
						id = "hand_spell_icon_exposure",
						label = "Hand Spell Icon Brightness",
						initialValue = -1.0,
						speed = 0.1,
						range = {-5, 5},
						isHidden = not isDeveloperMode,
					},
				{ widgetType = "unindent", width = 20 },{ widgetType = "end_group", },
			{ widgetType = "end_rect", additionalSize = 12, rounding = 5 }, { widgetType = "unindent", width = 20 },
			{ widgetType = "new_line" },

			{ widgetType = "indent", width = 20 }, { widgetType = "text", label = "Spell Voice Detection" }, { widgetType = "begin_rect", },
				{
					widgetType = "checkbox",
					id = "use_voice_detection",
					label = "Enable",
					initialValue = true,
				},
				{ widgetType = "begin_group", id = "use_voice_detection_group" },{ widgetType = "indent", width = 20 },
					{
						widgetType = "checkbox",
						id = "mute_spell_voice",
						label = "Mute Game Spell Voice",
						initialValue = false,
					},
					{
						widgetType = "slider_float",
						id = "voice_min_confidence",
						label = "Minimum Confidence",
						initialValue = .40,
						speed = 0.01,
						range = {0, 1},
					},
					{
						widgetType = "slider_float",
						id = "microphone_volume",
						label = "Mic. Input Volume",
						initialValue = 1.0,
						speed = 0.01,
						range = {0, 1},
					},
					{
						widgetType = "checkbox",
						id = "use_agc",
						label = "Use Automatic Gain Control (AGC)",
						initialValue = false,
					},
					{ widgetType = "begin_group", id = "agc_group" },{ widgetType = "indent", width = 40 },
						{
							widgetType = "slider_float",
							id = "agc_target",
							label = "Target",
							initialValue = 0.5,
							speed = 0.01,
							range = {0, 1},
						},
						{
							widgetType = "slider_float",
							id = "agc_max_gain",
							label = "Max Gain",
							initialValue = 8.0,
							speed = 0.1,
							range = {0, 16},
						},
					{ widgetType = "unindent", width = 40 },{ widgetType = "end_group", },
				{ widgetType = "unindent", width = 20 },{ widgetType = "end_group", },
			{ widgetType = "end_rect", additionalSize = 12, rounding = 5 }, { widgetType = "unindent", width = 20 },
			{ widgetType = "new_line" },

			{ widgetType = "indent", width = 20 }, { widgetType = "text", label = "UI" }, { widgetType = "begin_rect", },
				expandArray(ui.getConfigurationWidgets),
			{ widgetType = "end_rect", additionalSize = 12, rounding = 5 }, { widgetType = "unindent", width = 20 },
			{ widgetType = "new_line" },
			{ widgetType = "indent", width = 20 }, { widgetType = "text", label = "Input" }, { widgetType = "begin_rect", },
				expandArray(input.getConfigurationWidgets,{{id="uevr_input_config_pawnRotationMode", isHidden=true},}),
			{ widgetType = "end_rect", additionalSize = 12, rounding = 5 }, { widgetType = "unindent", width = 20 },
			{ widgetType = "new_line" },
			{ widgetType = "indent", width = 20 }, { widgetType = "text", label = "Reticule" }, { widgetType = "begin_rect", },
				expandArray(reticule.getConfigurationWidgets,{{id="uevr_reticule_update_distance", initialValue=200},}),
			{ widgetType = "end_rect", additionalSize = 12, rounding = 5 }, { widgetType = "unindent", width = 20 },
			{ widgetType = "new_line" },
		}
	}
}

local status = {}
local HandsType = {
	Forearms = 1,
	IKArms = 2,
}


gestureTrainer.registerGetMeshCallback(function()
	return spells.getWandTrailMesh(), "MuzzleSocket"
end)


-- register_key_bind("F1", function()
-- end)

-- Hogwarts Legacy keeps live auto-exposure on its RenderSettingsSingleton
local function getEV100()
	-- Other worlds (e.g. /Temp SplineWorld) have their own singleton that never measures exposure
	if uevrUtils.getValid(status.renderSettings) == nil or not status.renderSettings.LastFrameExposure.Filtered.bValid then
		status.renderSettings = nil
		for _, renderSettings in ipairs(uevrUtils.find_all_instances("Class /Script/RenderSettings.RenderSettingsSingleton", false) or {}) do
			if renderSettings.LastFrameExposure.Filtered.bValid then
				status.renderSettings = renderSettings
				break
			end
		end
	end
	return status.renderSettings ~= nil and status.renderSettings.LastFrameExposure.Filtered.AutoExposureEV100 or nil
end

setInterval(1000, function()
	widgetModule.setWidgetComponentExposure(status.handSpellComponent, getEV100(), configui.getValue("hand_spell_icon_exposure"))
end)

local function updateHandSpellIconTransform()
	local pos = configui.getValue("hand_spell_icon_position")
	local rot = configui.getValue("hand_spell_icon_rotation")
	if uevrUtils.getValid(status.handSpellComponent) == nil or pos == nil or rot == nil then return end
	status.handSpellComponent:K2_SetRelativeLocation(uevrUtils.vector(pos.X, pos.Y, pos.Z), false, reusable_hit_result, false)
	status.handSpellComponent:K2_SetRelativeRotation(uevrUtils.rotator(rot.X, rot.Y, rot.Z), false, reusable_hit_result, false)
end

-- Hands only: gloves without SKT_Reference (e.g. BasicGlove01) resolve WandSocket with different axes. The wand
-- attaches to a proxy at the socket whose offset comes from the custom_glove_wand_* sliders.
local wandSocketProxies = {}
local function updateWandSocketProxyTransform(hand)
	local suffix = hand == Handed.Left and "left" or "right"
	local pos = configui.getValue("custom_glove_wand_position_" .. suffix)
	local rot = configui.getValue("custom_glove_wand_rotation_" .. suffix)
	if uevrUtils.getValid(wandSocketProxies[hand]) == nil or pos == nil or rot == nil then return end
	wandSocketProxies[hand]:K2_SetRelativeLocation(uevrUtils.vector(pos.X, pos.Y, pos.Z), false, reusable_hit_result, false)
	wandSocketProxies[hand]:K2_SetRelativeRotation(uevrUtils.rotator(rot.X, rot.Y, rot.Z), false, reusable_hit_result, false)
end

local function getWandAttachTarget(handComponent, socketName, hand)
	if handComponent == nil or handComponent.GetBoneIndex == nil or handComponent:GetBoneIndex(uevrUtils.fname_from_string("SKT_Reference")) ~= -1 then return handComponent, socketName end
	if uevrUtils.getValid(wandSocketProxies[hand]) == nil then
		wandSocketProxies[hand] = uevrUtils.create_component_of_class("Class /Script/Engine.SceneComponent")
	end
	if wandSocketProxies[hand].AttachParent ~= handComponent then
		wandSocketProxies[hand]:K2_AttachToComponent(handComponent, uevrUtils.fname_from_string(socketName or ""), 0, 0, 0, false)
		updateWandSocketProxyTransform(hand)
	end
	return wandSocketProxies[hand], ""
end

local getHandComponents
local function attachHandSpellIcon(rightHandComponent)
	rightHandComponent = rightHandComponent or getHandComponents()
	if uevrUtils.getValid(status.handSpellComponent) == nil or rightHandComponent == nil then return end
	local target, socket = getWandAttachTarget(rightHandComponent, rightHandComponent == status["ikMeshComponent"] and status["ikWandSocket"] or "WandSocket", Handed.Right)
	status.handSpellComponent:K2_AttachTo(target, uevrUtils.fname_from_string(socket), 0, false)
	-- Hiding the old hands propagates to children, so the icon can arrive on the new hands still hidden
	status.handSpellComponent:SetVisibility(true)
	updateHandSpellIconTransform()
end

local spellNameRemap = {}
spellNameRemap["BasicShot"] = "Spell_PewPew"
spellNameRemap["Alteration"] = "Spell_Transformation"
spellNameRemap["Bombarda"] = "Spell_Expulso"
spellNameRemap["BeastTool_Food"] = "ITEM_CreatureFeed"
spellNameRemap["BeastTool_Brush"] = "Item_CreaturePettingBrush"
spellNameRemap["BeastTool_Bag"] = "ITEM_CaptureDevice"
spellNameRemap["LeviosoAlt"] = "Spell_Levioso"

local function onSpellRecognize(pawn, spellName, muteVoice)
	if spellName == nil then return end
	if uevrUtils.isInCutscene() then return end

	if uevrUtils.getValid(status.handSpellComponent) == nil and getHandComponents() ~= nil then
		local transform = uevrUtils.get_transform(nil, nil, {X=0.08, Y=0.08, Z=0.08})
		status.handSpellComponent, status.handSpellIcon = widgetModule.createImageComponent(40, { relativeTransform = transform, twoSided = true, drawSize = uevrUtils.vector2D(120, 120) })
		if status.handSpellComponent ~= nil then
			attachHandSpellIcon()
			widgetModule.applyWidgetComponentExposureFix(status.handSpellComponent, getEV100(), configui.getValue("hand_spell_icon_exposure"))
		end
	end
	if status.handSpellIcon ~= nil then
		status.handSpellIcon:setTexture(spellName .. ".png")
	end

	if spellNameRemap[spellName] ~= nil then
		spellName = spellNameRemap[spellName]
	else
		spellName = "Spell_" .. spellName
	end
	spells.castSpell(pawn, spellName, muteVoice)

end

uevr.sdk.callbacks.on_lua_event(function(eventName, eventData)
    if eventName == "GestureRecognize" then
        print("GestureRecognize ", eventName, tostring(eventData))
		local data = json.load_string(eventData)
		if data ~= nil and data.confidence ~= nil then
			if data.confidence >= configui.getValue("gesture_min_confidence") then
				local spellName = data.spell --spellMap[data.spell]
				delay(configui.getValue("gesture_cast_delay") * 1000, function()
					onSpellRecognize(pawn, spellName)
				end)
			end
		end
    end
	if eventName == "VoiceRecognize" then
		print("VoiceRecognize ", eventName, tostring(eventData))
		local data = json.load_string(eventData)
		if data ~= nil then
			local spellName = data.word
			onSpellRecognize(pawn, spellName, true)
		end
    end
	if eventName == "VoiceRecognizePeak" then
		print("VoiceRecognizePeak ", eventName, tostring(eventData))
	end
end)

gestures.registerFlickCallback(function(strength, hand)
	--debounce so the spell goes to the intended wand location instead of where the wand is when the gesture is released
	-- the camera snap on cutscene exit reads as a flick
	if uevrUtils.isInCutscene() or os.clock() - (status.cutsceneEndTime or 0) < 0.5 then return end
	delay(200, function()
		spells.castCurrentFlickSpell(pawn)
	end)
end, uevrUtils.getHandedness() == Handed.Right, uevrUtils.getHandedness() == Handed.Left) -- rightHand, leftHand

gestures.registerFlickUpCallback(function(strength, hand)
	if uevrUtils.isInCutscene() then return end
	spells.cancelContinuousActiveSpells(pawn)
end, uevrUtils.getHandedness() == Handed.Right, uevrUtils.getHandedness() == Handed.Left)


local function regenerateHands(value)
	accessories.attachHandToTargetAccessory(Handed.Right, nil)
	accessories.attachHandToTargetAccessory(Handed.Left, nil)
	--detach attachments first so they dont get "lost" when hands are destroyed
	attachments.detachGripAttachments(Handed.Right)
	attachments.detachGripAttachments(Handed.Left)
	if uevrUtils.getValid(status.handSpellComponent) ~= nil then
		status.handSpellComponent:K2_DetachFromComponent(0, 0, 0, false)
	end
	-- The grip update must not reuse a mesh from the rig being destroyed.
	status["ikMeshComponent"] = nil

    hands.setAutoCreateHands(value == HandsType.Forearms)
    ik.setAutoCreateArms(value == HandsType.IKArms)

    hands.destroyHands()
    ik.destroyAll()

	if value == HandsType.Forearms then
		hands.regenerateHands()
	else
		--ik.regenerateArms()
	end
end

local function updateReticule()
	if uevrUtils.isInCutscene() or status.wandAttached ~= true then
		reticule.setHidden(true)
	else
		reticule.setHidden(false)
	end
end

local function getWeaponMesh()
	local wand = spells.getWand(pawn)
	if wand == nil or not spells.isWandDrawn(pawn) then
		return nil
	end
	wand:ActivateFx()
	return wand.Mesh
end

function getHandComponents()
    local rightHandComponent = nil
   	local leftHandComponent = nil
	local handsType = configui.getValue("hands_type")
    if handsType == HandsType.None then
        rightHandComponent = controllers.getController(Handed.Right)
        leftHandComponent = controllers.getController(Handed.Left)
    elseif handsType == HandsType.Forearms then
        rightHandComponent = hands.getHandComponent(Handed.Right)
        leftHandComponent = hands.getHandComponent(Handed.Left)
    elseif handsType == HandsType.IKArms then
		local ikMesh = status["ikMeshComponent"]
		if ik.exists() and uevrUtils.getValid(ikMesh) ~= nil then
			rightHandComponent = ikMesh
			leftHandComponent = ikMesh
		end
    end

    return rightHandComponent, leftHandComponent
end

local robeMeshSettings = {
    ["sk_hum_m_robe_sturobe02_master_clothjoint"] = {forearmTwistPitch=0},
    ["SK_HUM_M_Robe_StuRobe01_Master_ClothJoint"] = {forearmTwistPitch=0.33},
    ["SK_hum_f_robe_sturobe01_master_clothjoint"] = {forearmTwistPitch=0.33},
}
ik.registerOnMeshCreatedCallback(function(meshComponentList, ikInstance)
    -- Basically excludes robes from being a wand parent
    local wandMesh = nil
    for i, meshComponent in ipairs(meshComponentList or {}) do
        --print("MeshComponent:", meshComponent:GetSocketBoneName(uevrUtils.fname_from_string("WandSocket")))
        local socketName = meshComponent:GetSocketBoneName(uevrUtils.fname_from_string("WandSocket"))
        -- Some gloves (e.g. BasicGlove01) define WandSocket but lack its SKT_RightHand bone, so it resolves to the mesh origin
        if socketName ~= nil and socketName:to_string() ~= "None" and meshComponent:GetBoneIndex(socketName) ~= -1 then
            wandMesh = meshComponent
            status["ikWandSocket"] = "WandSocket"
            break

        end
    end
    -- WandSocket sits on SKT_RightHand with no offset, so the bone on another rig mesh (robe) is equivalent
    if wandMesh == nil then
        for i, meshComponent in ipairs(meshComponentList or {}) do
            if meshComponent:GetBoneIndex(uevrUtils.fname_from_string("SKT_RightHand")) ~= -1 then
                wandMesh = meshComponent
                status["ikWandSocket"] = "SKT_RightHand"
                break
            end
        end
    end

    if wandMesh ~= nil then status["ikMeshComponent"] = wandMesh end

	for i, meshComponent in ipairs(meshComponentList or {}) do
        --Some robes requires setting the forearm twist pitch so that the hands dont clip the robe as easily
        if meshComponent.SkeletalMesh ~= nil then
            print("Created rig mesh", uevrUtils.getShortName(meshComponent.SkeletalMesh), robeMeshSettings[uevrUtils.getShortName(meshComponent.SkeletalMesh)])
            local meshSettings = robeMeshSettings[uevrUtils.getShortName(meshComponent.SkeletalMesh)]
            if meshSettings ~= nil then
                ikInstance:setTwistBonePitch("LeftForeArmTwist1", meshSettings.forearmTwistPitch or 0)
                ikInstance:setTwistBonePitch("RightForeArmTwist1", meshSettings.forearmTwistPitch or 0)
            end
        end
    end
    -- ik.exists() is still false while this callback runs, so getHandComponents() can't see the new mesh yet
    attachHandSpellIcon(status["ikMeshComponent"])
end)

hands.onCreatedCallback(function() attachHandSpellIcon() end)

local defaultAttachOptions = {
	detachFromOriginOnGrip = false,
	maintainWorldPositionOnDetachFromOrigin = true,
	detachFromParentOnRelease = true,
	maintainWorldPositionOnDetachFromParent = true,
	reattachToOriginOnRelease = true,
	restoreTransformToOriginOnReattach = true,
	useZeroTransformOnReattach = false,
	allowChildVisibilityHandling = false,
	allowChildHiddenInGameHandling = false,
	allowRenderInMainPassHandling = false,
	useCurrentAttachedSocketName = false,
	--allowMobiltyChange = true,
}
attachments.registerOnGripUpdateCallback(function()
	local can = spells.getCreatureFeedCan()
	--print("can", can, can and can:get_full_name())

    local weaponMesh = getWeaponMesh()
	local rightHandComponent, leftHandComponent = getHandComponents()
	--print("grip anim", attachments.getCurrentGripAnimation(Handed.Right), "ik copy", uevrUtils.executeUEVRCallbacksWithPriorityBooleanResult("is_hands_animating_from_mesh", Handed.Right))
    if configui.getValue("left_handed_mode") then
		local leftTarget, leftSocket = getWandAttachTarget(leftHandComponent, nil, Handed.Left)
        return nil,nil,nil,leftTarget and weaponMesh, leftTarget, leftSocket  --, controllers.getController(Handed.Left)
    else
 		local weaponAttachSocket = rightHandComponent ~= nil and rightHandComponent == status["ikMeshComponent"] and status["ikWandSocket"] or "WandSocket" --uevrUtils.getValid(pawn,{"Equipment","WeaponAttachSocket"}) or "WeaponPoint"
		local rightTarget
		rightTarget, weaponAttachSocket = getWandAttachTarget(rightHandComponent, weaponAttachSocket, Handed.Right)
        local leftTarget, leftHandAttachSocket = getWandAttachTarget(leftHandComponent, "SKT_LeftHand", Handed.Left)
		--print(rightHandComponent, weaponMesh, weaponAttachSocket)
        return rightTarget and weaponMesh, rightTarget, weaponAttachSocket, leftTarget and can, leftTarget, leftHandAttachSocket, defaultAttachOptions --, controllers.getController(Handed.Right)
    end

end)


attachments.registerAttachmentChangeCallback(function(id, gripHand, attachment)
	if gripHand == Handed.Right then
		status.wandAttached = attachment ~= nil and id == "BP_WandTool_C_Mesh"
		if attachment == nil then
			spells.destroyWandTrail()
			return
		end
		attachment:SetVisibility(true, true)
		local mesh = attachment
		-- MuzzleSocket is on SK_Wand; grip attachment is often the StaticMesh "Mesh"
		if attachment.DoesSocketExist == nil or not attachment:DoesSocketExist(uevrUtils.fname_from_string("MuzzleSocket")) then
			for _, child in ipairs(attachment.AttachChildren or {}) do
				if child ~= nil and string.find(child:get_full_name(), "SK_Wand", 1, true) then
					mesh = child
					break
				end
			end
		end
		spells.setWandTrailMesh(mesh)
	end
end)

uevrUtils.registerOnPreInputGetStateCallback(function(retval, user_index, state)

	if configui.getValue("left_arm_block") and status.isBlocking then
		uevrUtils.pressButton(state, XINPUT_GAMEPAD_Y)
	end

	local gripMouthLeft, gripEyesLeft, gripHeadLeft, gripEarLeft, triggerMouthLeft, triggerEyesLeft, triggerHeadLeft, triggerEarLeft = gestures.getHeadGestures(state, Handed.Left, true)
	local gripMouthRight, gripEyesRight, gripHeadRight, gripEarRight, triggerMouthRight, triggerEyesRight, triggerHeadRight, triggerEarRight = gestures.getHeadGestures(state, Handed.Right, false)
	if gripEarLeft then uevrUtils.pressButton(state, XINPUT_GAMEPAD_START) end
	if gripEarRight then regenerateHands(configui.getValue("hands_type")) end
	if gripMouthLeft then uevrUtils.pressButton(state, XINPUT_GAMEPAD_DPAD_DOWN) end

end)

local function isWearingRobeAndGloves()
	local character = mounts.getMountType() ~= nil and mounts.getMountPawn(pawn) or pawn
	local mesh = uevrUtils.getValid(character, {"Mesh"})
	local wearingRobe = uevrUtils.getChildComponent(mesh, "Robe") ~= nil
	local wearingGloves = uevrUtils.getChildComponent(mesh, "Gloves") ~= nil
	--print("wearingRobe", wearingRobe, "wearingGloves", wearingGloves)
	return wearingRobe, wearingGloves
end

function getCustomIKComponent(rigID)
	local upperMeshName = isWearingRobeAndGloves() and "Robe" or "Upper"
	if mounts.getMountType() == mounts.EMountTypes.Avatar_Ground or mounts.getMountType() == mounts.EMountTypes.Broom_Ground or mounts.getMountType() == mounts.EMountTypes.Broom_Flying then
		if status.isDisguised then
			return {{descriptor = "Pawn.Mesh", animation = "Gloves", optional = true}}
		else
			return {{descriptor = "Pawn.Mesh(".. upperMeshName ..")"}, {descriptor = "Pawn.Mesh(Gloves)", animation = "Gloves", optional = true}, {descriptor = "Pawn.Mesh(Arms)", animation = "Arms", optional = true}}
		end
	elseif mounts.getMountType() == mounts.EMountTypes.Cart_Rider then
		return {{descriptor = "Pawn.MyPlayer.Mesh(".. upperMeshName ..")"}, {descriptor = "Pawn.MyPlayer.Mesh(Gloves)", animation = "Gloves", optional = true}, {descriptor = "Pawn.MyPlayer.Mesh(Arms)", animation = "Arms", optional = true}}
	elseif mounts.getMountType() ~= nil then
		return {{descriptor = "Pawn.MountComponent.RiderCharacter.Mesh(".. upperMeshName ..")"}, {descriptor = "Pawn.MountComponent.RiderCharacter.Mesh(Gloves)", animation = "Gloves", optional = true}, {descriptor = "Pawn.MountComponent.RiderCharacter.Mesh(Arms)", animation = "Arms", optional = true}}
	end
end

function getCustomHandComponent(key)
	--print("getCustomHandComponent", key)
	if status.isDisguised then
		hands.setOffset({X=0, Y=0, Z=0, Pitch=0, Yaw=180, Roll=0})
		if key == "Gloves" then
			return uevrUtils.getValid(pawn,{"Mesh"})
		end
	else
		local wearingRobe, wearingGloves = isWearingRobeAndGloves()
		if key == "Arms" and not wearingRobe then
			return nil
		end
		if key == "Gloves" and not wearingGloves and not wearingRobe then
			if mounts.getMountType() == mounts.EMountTypes.Avatar_Ground or mounts.getMountType() == mounts.EMountTypes.Broom_Ground or mounts.getMountType() == mounts.EMountTypes.Broom_Flying  then
				return uevrUtils.getObjectFromDescriptor("Pawn.Mesh(Arms)", false)
			elseif mounts.getMountType() ~= nil then
				return uevrUtils.getObjectFromDescriptor("Pawn.MountComponent.RiderCharacter.Mesh(Arms)", false)
			end
		end
		hands.setOffset(nil)
		if mounts.getMountType() == mounts.EMountTypes.Avatar_Ground or mounts.getMountType() == mounts.EMountTypes.Broom_Ground or mounts.getMountType() == mounts.EMountTypes.Broom_Flying  then
			return uevrUtils.getObjectFromDescriptor("Pawn.Mesh(".. key ..")", false)
		elseif mounts.getMountType() ~= nil then
			return uevrUtils.getObjectFromDescriptor("Pawn.MountComponent.RiderCharacter.Mesh(".. key ..")", false)
		end
	end
end

ik.registerOnDestroyCallback(function(ikInstance)
	for _, mesh in pairs(ikInstance.meshList or {}) do
		if mesh == status["ikMeshComponent"] then
			status["ikMeshComponent"] = nil
			break
		end
	end
	--detach attachments first so they dont get "lost" when hands are destroyed
	attachments.detachGripAttachments(Handed.Right)
	attachments.detachGripAttachments(Handed.Left)
end)

hands.registerOnDestroyCallback(function()
	--detach attachments first so they dont get "lost" when hands are destroyed
	attachments.detachGripAttachments(Handed.Right)
	attachments.detachGripAttachments(Handed.Left)
end)

local function checkIsDisguised()
	local isDisguised = uevrUtils.getShortName(uevrUtils.getValid(pawn,{"Mesh","SkeletalMesh"})) == "SK_Professor_PhineasBlack_Master"
	if isDisguised ~= status.isDisguised then
		regenerateHands(configui.getValue("hands_type") or 1)
		status.isDisguised = isDisguised
	end
end

local function updatePlayerVisibility()
    local isInCutscene = uevrUtils.isInCutscene()
    local visible = isInCutscene
	checkIsDisguised()

	local mountType = mounts.getMountType()
	if status.isDisguised then
		pawnModule.hideBodyMesh(false)
		--pawnModule.hideArmsBones(not isInCutscene)
		if visible then
			pawn.Mesh:UnHideBoneByName(uevrUtils.fname_from_string("LeftArm"), 0)
			pawn.Mesh:UnHideBoneByName(uevrUtils.fname_from_string("RightArm"), 0)
		else
			pawn.Mesh:HideBoneByName(uevrUtils.fname_from_string("LeftArm"), 0)
			pawn.Mesh:HideBoneByName(uevrUtils.fname_from_string("RightArm"), 0)
		end

		return
	elseif mountType == mounts.EMountTypes.Avatar_Ground or mounts.getMountType() == mounts.EMountTypes.Broom_Ground or mounts.getMountType() == mounts.EMountTypes.Broom_Flying  then
		pawnModule.hideBodyMesh(not visible)
		mounts.hideBodyMesh(pawn, visible)
	elseif mountType == mounts.EMountTypes.Hippogriff_Ground or mountType == mounts.EMountTypes.Graphorn_Ground then
		local mountPawn = mounts.getMountPawn(pawn)
		if mountPawn ~= nil then
			mountPawn.Mesh.bRenderInDepthPass = visible
			mountPawn.Mesh:SetRenderInMainPass(visible)
			mounts.hideBodyMesh(mountPawn, visible)
		end
		if uevrUtils.getValid(pawn) ~= nil and pawn.Mesh ~= nil then
			pawn.Mesh:call("SetRenderInMainPass", true)
		end
	elseif mountType ~= nil then
		if uevrUtils.getValid(pawn) ~= nil and pawn.Mesh ~= nil then
			--pawn.Mesh:call("SetRenderInMainPass", true)
			pawn.Mesh.bRenderInDepthPass = true
			pawn.Mesh:SetRenderInMainPass(true)
		end

	end

	--while looking at the map the pawn is a MapPawn
	if pawn.Mesh ~= nil then
		--pawn.Mesh:SetHiddenInGame(isInCutscene == false and (mountType == mounts.EMountTypes.Avatar_Ground or mountType == mounts.EMountTypes.Broom_Ground or mountType == mounts.EMountTypes.Broom_Flying), false)
		--pawn.Mesh:SetCastHiddenShadow(true)
		local render = not (visible == false and (mountType == mounts.EMountTypes.Avatar_Ground or mountType == mounts.EMountTypes.Broom_Ground or mountType == mounts.EMountTypes.Broom_Flying))
		pawn.Mesh.bRenderInDepthPass = render
		pawn.Mesh:SetRenderInMainPass(render)
		--pawn.Mesh:SetRenderCustomDepth(render)
	end
end
setInterval(200, function()
    updatePlayerVisibility()
	updateReticule()
end)

uevrUtils.registerUEVRCallback("on_mount_changed", function(mountType, isFlying)
	regenerateHands(configui.getValue("hands_type") or 1)
end)

hook_function("Class /Script/Phoenix.UIManager", "OnFadeInBegin", true, nil,
	function(fn, obj, locals, result)
		--print("UIManager:OnFadeInBegin\n")
		if ui.isFadeCameraEnabled() then return end
		uevrUtils.fadeCamera(0.001, true, false, true, false, 1)
		end
, true)

hook_function("Class /Script/Phoenix.UIManager", "OnFadeInComplete", true, nil,
	function(fn, obj, locals, result)
		--print("UIManager:OnFadeInEnd\n")
		if ui.isFadeCameraEnabled() then return end
		uevrUtils.fadeCamera(.6, false, false, true, false, 0)
		end
, true)

hook_function("Class /Script/Phoenix.UIManager", "OnFadeOutBegin", true, nil,
	function(fn, obj, locals, result)
		--print("UIManager:OnFadeOutBegin\n")
		if ui.isFadeCameraEnabled() then return end
		uevrUtils.fadeCamera(0.001, true, false, false, false, 1)
		end
, true)

hook_function("Class /Script/Phoenix.UIManager", "OnFadeOutComplete", true, nil,
	function(fn, obj, locals, result)
		--print("UIManager:OnFadeOutEnd\n")
		if ui.isFadeCameraEnabled() then return end
		uevrUtils.fadeCamera(.6, false, false, false, false, 0)
	end
, true)

local function hideLetterbox()
	local widget = uevrUtils.find_first_of("Class /Script/CameraStack.CameraAspectRatioWidget", false)
	if widget == nil then return end
	widget:SetVisibility(1)
	widget.RenderOpacity = 0
end

uevrUtils.registerCutsceneChangeCallback(function(isInCutscene)
    updatePlayerVisibility()

    if isInCutscene then
		hideLetterbox()
    else
		status.cutsceneEndTime = os.clock()
    end
end, 5)

-- Native Mode needs to update body yaw on only one eye,
-- while AFW Mode needs to update body yaw on both eyes.
local function setInputBodyYawMode()
	if uevrUtils.getUEVRParam_int("VR_RenderingMethod") == 0 then
		input.setOptimizeBodyYawCalculations(true)
	else
		input.setOptimizeBodyYawCalculations(false)
	end
end
-- Native Mode needs to use TimeSlice 0 to fix flickering
-- AFW doesnt have the flickering issue so use the more performant Timeslice 1
local function fixFlicker()
	if uevrUtils.getUEVRParam_int("VR_RenderingMethod") == 0 and uevrUtils.getUEVRParam_bool("VR_NativeStereoFix") then
		uevrUtils.set_cvar_int("r.SkyLight.RealTimeReflectionCapture.TimeSlice", 0)
	else
		uevrUtils.set_cvar_int("r.SkyLight.RealTimeReflectionCapture.TimeSlice", 1)
	end
end
--when the UEVR overlay closes, update the body yaw mode and flicker fixer in case UEVR rendering mode changed
uevrUtils.registerUEVRUIChangeCallback(function(isOpen)
    if isOpen == false then
		setInputBodyYawMode()
		fixFlicker()
	end
end)

local function solveAstronomyMinigame()
	pawn:CHEAT_SolveMinigame()
end

local function hookLevelFunctions()
	--move the attack indicator in front of and further away from the hmd
	hook_function("BlueprintGeneratedClass /Game/Pawn/Player/BP_AttackIndicatorVFX.BP_AttackIndicatorVFX_C", "ReceiveIndicatorStart", false, nil,
		function(fn, obj, locals, result)
				--print("ReceiveIndicatorStart bp\n")
				local components = obj.RootComponent.AttachParent.AttachChildren
				local niagaraClass = uevrUtils.get_class("Class /Script/Niagara.NiagaraComponent")
				for i, component in ipairs(components) do
					if component:is_a(niagaraClass) then
						--print("Got the niagara component")
						--component:DetachFromParent(true,false)
						local location = component:K2_GetComponentLocation()
						local hmdDirection = controllers.getControllerDirection(2)
						location = location + (hmdDirection * 300)
						component:K2_SetWorldLocation(location, false, reusable_hit_result, false)
					end
				end
		end
	, true)

	hook_function("BlueprintGeneratedClass /Game/Pawn/Shared/StateTree/BTT_Biped_PuzzleMiniGame.BTT_Biped_PuzzleMiniGame_C", "ReceiveExecute", true,
		function(fn, obj, locals, result)
			print("Alohomora:ReceiveExecute")
			status.isInAlohomora = true
			mounts.hideViewableMesh(pawn, false)
		end
	, nil, true)

	hook_function("BlueprintGeneratedClass /Game/Pawn/Shared/StateTree/BTT_Biped_PuzzleMiniGame.BTT_Biped_PuzzleMiniGame_C", "ExitTask", false, nil,
		function(fn, obj, locals, result)
			print("Alohomora:ExitTask")
			status.isInAlohomora = false
			delay(2000, function()
				mounts.hideViewableMesh(pawn, true)
			end)
		end
	, true)

	hook_function("WidgetBlueprintGeneratedClass /Game/UI/Actor/UI_BP_Astronomy_minigame.UI_BP_Astronomy_minigame_C", "ConstellationImageLoaded", true, nil,
	function(fn, obj, locals, result)
		print("Astronomy MiniGame ConstellationImageLoaded\n")

		--auto solve game unless we can find a solution for UEVR FOV locking
		obj:Solved()
		delay(3000, function()
			solveAstronomyMinigame()
		end)
	end
, true)

end

local function cleanup()
	if status.transformationTargetInitialized then
		local controller = uevrUtils.getValid(uevr.api:get_player_controller(0))
		if controller ~= nil and controller.SetAutoTargetAlwaysTargetActor ~= nil then
			controller:SetAutoTargetAlwaysTargetActor(nil)
		end
	end
    status = {}
	uevrUtils.setIsInCutsceneOverride(nil)
end

on_level_change = function(level, levelName)
	--print("on_level_change ", level, levelName)
    cleanup()
    regenerateHands(configui.getValue("hands_type") or 1)
	hookLevelFunctions()
	spells.activateAutoTargetSense(configui.getValue("use_auto_targeting"))
	setInputBodyYawMode()
	fixFlicker()

	uevr.api:dispatch_custom_event(configui.getValue("use_gesture_detection") and "GestureStart" or "GestureStop", "")
	uevr.api:dispatch_custom_event(configui.getValue("use_voice_detection") and "VoiceStart" or "VoiceStop", "")
end

ui.registerWidgetChangeCallback("UI_BP_GadgetWheel_C", function(active, widget)
	--status.gadgetWheel = active and widget or nil
	input.setStickTurnDisabled(active, "gadgetWheel")
end)

ui.registerWidgetChangeCallback("UI_BP_FieldGuide_C", function(active, widget)
	regenerateHands(configui.getValue("hands_type") or 1)
end)

ui.registerWidgetChangeCallback("UI_BP_Tutorial_NonModal_C", function(active, widget)
	print("UI_BP_Tutorial_NonModal_C: ", active, widget and widget.TutorialName:to_string())
	ui.setCustomState("handsEnabled", (active and widget.TutorialName:to_string() == "Stupefy") or nil, 1)
	--input.setRotationModeRotationDisabled(active)
	--input.setBodyYawWritesSuppressed(active)
	--mounts.hideViewableMesh(pawn, not active)
end)

configui.onUpdate("hands_type", function(value)
    regenerateHands(value)
end)

configui.onUpdate("custom_glove_wand_position_right", function(value) updateWandSocketProxyTransform(Handed.Right) end)
configui.onUpdate("custom_glove_wand_rotation_right", function(value) updateWandSocketProxyTransform(Handed.Right) end)
configui.onUpdate("custom_glove_wand_position_left", function(value) updateWandSocketProxyTransform(Handed.Left) end)
configui.onUpdate("custom_glove_wand_rotation_left", function(value) updateWandSocketProxyTransform(Handed.Left) end)

configui.onUpdate("hand_spell_icon_position", function(value)
	updateHandSpellIconTransform()
end)

configui.onUpdate("hand_spell_icon_rotation", function(value)
	updateHandSpellIconTransform()
end)

configui.onUpdate("mute_spell_voice", function(value)
	spells.setMuteSpellVoice(value)
end)

local function dispatchVoiceSettings()
	local params = {
		use_agc = configui.getValue("use_agc"),
		agc_target = configui.getValue("agc_target"),
		agc_max_gain = configui.getValue("agc_max_gain"),
		microphone_volume = configui.getValue("microphone_volume"),
		min_confidence = configui.getValue("voice_min_confidence"),
		override_voices = {
			Descendo = { override = "Diffindo", confidence = 0.15 },
			Confringo = { override = "Diffindo", confidence = 0.18 },
			Lumos = {
				{ override = "Levioso", confidence = 0.3 },
				{ override = "Expelliarmus", confidence = 0.3 }
			},
			Glacius = { override = "Crucio", confidence = 0.1 },
		},
		defer_voices = {
			Accio = {
				defer_for = "AvadaKedavra",
				confidence = 0.55,
				min_self = 0.15,
				min_other = 0.09
			}
		},
		commit_margin = 0.25,
		silence_voices = { "Lumos", "Depulso" },
		show_debug = false
	}
	uevr.api:dispatch_custom_event("VoiceSettings", json.dump_string(params))
end


configui.onCreateOrUpdate("use_voice_detection", function(value)
	--TODO if value is false then send VoiceStop but if true should check that we're in
	--a place where spells can be cast
	uevr.api:dispatch_custom_event(value and "VoiceStart" or "VoiceStop", "")
	configui.setHidden("use_voice_detection_group", not value)

	dispatchVoiceSettings()
end)

configui.onCreateOrUpdate("use_gesture_detection", function(value)
	uevr.api:dispatch_custom_event(value and "GestureStart" or "GestureStop", "")
	configui.setHidden("use_gesture_detection_group", not value)
end)

configui.onCreateOrUpdate("use_mount_hand_controlled_movement", function(value)
	configui.setHidden("use_mount_hand_controlled_movement_group", not value)
end)

configui.onCreateOrUpdate("follow_broom_roll", function(value)
	mounts.setBroomRollFollow(value)
end)

configui.onCreateOrUpdate("broom_max_rise_pitch_offset", function(value)
	mounts.setBroomMaxRisePitchOffset(value)
end)

configui.onCreateOrUpdate("broom_max_dive_pitch_offset", function(value)
	mounts.setBroomMaxDivePitchOffset(value)
end)

configui.onCreateOrUpdate("broom_high_speed_head_offset", function(value)
	mounts.setBroomHighSpeedHeadOffset(value)
end)

configui.onCreateOrUpdate("use_hippogriff_autofly", function(value)
	mounts.setAutofly(value)
end)

configui.onUpdate("use_agc", function(value)
	dispatchVoiceSettings()
	configui.setHidden("agc_group", not value)
end)

configui.onCreate("use_agc", function(value)
	configui.setHidden("agc_group", not value)
end)

configui.onUpdate("agc_target", function(value)
	dispatchVoiceSettings()
end)

configui.onUpdate("agc_max_gain", function(value)
	dispatchVoiceSettings()
end)

configui.onUpdate("microphone_volume", function(value)
	dispatchVoiceSettings()
end)

configui.onUpdate("voice_min_confidence", function(value)
	dispatchVoiceSettings()
end)

configui.onCreateOrUpdate("use_auto_targeting", function(value)
	spells.activateAutoTargetSense(value)
end)

configui.onCreateOrUpdate("use_controller_mouse", function(value)
	mouse.setOverrideEnable(value)
end)

configui.onCreateOrUpdate("left_arm_block", function(value)
	configui.setHidden("left_arm_block_info", value ~= true)
	gestures.autoDetectGesture(gestures.Gesture.BLOCK, value == true, Handed.Left)
	if value ~= true then
		status.isBlocking = false
	end
end)

gestures.registerBlockCallback(function(active, hand)
	status.isBlocking = active
end, false, true)

local function updateVolumetricFog()
    uevrUtils.set_cvar_int("r.VolumetricFog", configui.getValue("use_volumetric_fog") and 1 or 0)
end
configui.onCreateOrUpdate("use_volumetric_fog", function(value)
    updateVolumetricFog()
end)

accessories.createConfigCallbacks(BROOM_ACCESSORY_KEY, "broom_")
accessories.createConfigCallbacks(HIPPOGRIFF_ACCESSORY_KEY, "hippogriff_")
accessories.createConfigCallbacks(GRAPHORN_ACCESSORY_KEY, "graphorn_")
configui.create(configDefinition)
spells.setMuteSpellVoice(configui.getValue("mute_spell_voice"))


-- In third person, this is the camera that orbits around the pawn. Instead of fighting it we use it directly because changing
-- the camera arm rotation changes the pawn.Controller rotation. We also force the pitch to be 0 to keep the camera level.
-- Judder cause: ABL_Strafe* RootMotionModifierProperties_TurnAssist (FacingTarget_OR_DesiredDirection) rotates the pawn;
-- ForceSetArmRotation then copies that yaw into the camera and fights VR. bUseTurnAssist=false does not stop this path.
-- AnimMechanicType TurnStart/StrafeStart gating failed (stayed Idle(1) through Start/Loop). Two layers:
-- 1) Skip orbit sync while FullBody ability is *_Move_Start (brief Start window).
-- 2) Zero TurnAssist rotation speeds on ABL_Strafe* CDOs so Loop/Stop don't keep fighting orbit sync.
local function updateOrbitCamera(currentPawn, yawDelta, immediate)
	local abl = uevrUtils.getValid(currentPawn, {"AblAbilityComponent"})
	if abl ~= nil and abl.GetActiveAbility_New ~= nil then
		local ability = abl:GetActiveAbility_New(uevrUtils.fname_from_string(""))
		if ability ~= nil then
			local name = ability:get_full_name()
			if name ~= nil and string.find(name, "Move_Start", 1, true) ~= nil then
				return
			end
		end
	end

    local cameraStackActor = uevrUtils.getValid(currentPawn, {"Controller", "PlayerCameraManager", "ViewTarget", "Target"})
    if cameraStackActor ~= nil and cameraStackActor.GetArmRotation ~= nil and cameraStackActor.ForceSetArmRotation ~= nil then
        local armRotation = cameraStackActor:GetArmRotation()
        if armRotation ~= nil then
            armRotation.Pitch = 0.0
            armRotation.Roll = 0.0
            armRotation.Yaw = currentPawn:K2_GetActorRotation().Yaw
            cameraStackActor:ForceSetArmRotation(armRotation, immediate or true)
        end
    end
end

uevr.sdk.callbacks.on_pre_engine_tick(function(engine, deltaTime)
   	local pawn = uevrUtils.getValid(pawn)
	if pawn ~= nil and pawn.MyPlayer ~= nil then return end --if riding the cart don't update the camera
    if pawn ~= nil then
		-- Custom cutscene detection logic specific to Hogwarts Legacy
		local biped = pawn.InCinematic ~= nil and pawn or (pawn.MountComponent and pawn.MountComponent.RiderCharacter)
		local inCinematic = biped and biped.InCinematic
		inCinematic = inCinematic or nil -- use nil instead of false
		if inCinematic ~= status.isInCinematic then
			status.isInCinematic = inCinematic
			uevrUtils.setIsInCutsceneOverride(inCinematic)
		end

		if not inCinematic or configui.getValue("uevr_ui_reduceMotionSickness") then
			updateOrbitCamera(pawn)
		end

		--needs to be here maybe so its after orbit camera update?
		spells.setTargetingCameraRotation(pawn)
    end
end)

local function checkDisillusioned()
	local p = uevrUtils.getValid(pawn)
	local osi = p and p.GetObjectStateInfo and p:GetObjectStateInfo()
	if osi == nil then return end
	local isDisillusioned = osi:IsDisillusioned()
	if status.isDisillusioned ~= isDisillusioned then
		status.isDisillusioned = isDisillusioned
		status.waitDisillusionHands = true
	end
	if not status.waitDisillusionHands then return end
	if status.skinFxClass == nil then
		status.skinFxClass = uevrUtils.find_required_object("Class /Script/SkinFX.SkinFXComponent")
		status.disillusionFxClass = uevrUtils.find_required_object("BlueprintGeneratedClass /Game/VFX/SkinFX/BP_SkinFX_Disillusionment.BP_SkinFX_Disillusionment_C")
	end
	---@diagnostic disable-next-line: need-check-nil
	local skinFx = p:GetComponentByClass(status.skinFxClass)
	if (skinFx ~= nil and skinFx:SkinFXIsRunning(status.disillusionFxClass)) == isDisillusioned then
		status.waitDisillusionHands = nil
		regenerateHands(configui.getValue("hands_type") or 1)
	end
end

uevrUtils.registerPostEngineTickCallback(function(engine, deltaTime)
	checkDisillusioned()
end)

uevr.params.sdk.callbacks.on_script_reset(function()
	-- level change unloads the actor itself; only a script reload orphans it
	if uevrUtils.getValid(status.handSpellComponent) ~= nil then
		uevrUtils.destroy_actor(status.handSpellComponent:get_outer())
	end
	cleanup()
end)

-- local isPaused = false
-- register_key_bind("F2", function()
-- 	isPaused = not isPaused
-- 	uevrUtils.pauseGame(isPaused)
-- end)



