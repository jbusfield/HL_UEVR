--[[
Developer configuration for libs/mechanisms. mechanisms.init loads it in developer mode only; the saved entries it edits are read
by libs/mechanisms in every mode.

    Disable Mechanisms: everything works as usual (prompts, reaching, hands put on their spots, letting go) but the game's
    button is never pressed, so the game doesn't act. It is saved with the panel.

    "In front of you" names a thing and the mechanism that handles it. Find With (saved with the panel) chooses how it is found:
    Game, the game adapter's answer (what the game offers now, else what the player is using, shown "in use"), or Pointing, with
    no game code (what the right controller points at, else the thing nearest that hand; kept while the menu is open, since the
    controller then points at the menu). With no game adapter, only Pointing. If no mechanism handles it, Add either makes a new mechanism for it or puts it under an existing one ("Handle it with"). If one does,
    Select It shows that mechanism and the thing's variation.

    Current Mechanism lists every mechanism. A mechanism made here has a Type (how it is worked, one of the library's;
    the line under it lists the game code that type still needs, or says Ready), only that type's own settings (each type
    supplies its settings UI: see Type settings), and a Variation dropdown: Default (its settings) and then each
    kind of thing it works. A variation uses the Default until Use Default Settings is unticked: the first time, it gets a copy of
    the Default's settings and hand spots to change; after that its own are kept, whether they are used or not. Variations are
    listed as they are seen (every half second, of the things loaded around the player); one not listed yet uses the Default.

    A mechanism made in code shows only its Engage With, its reach, its release and release time, and its hand spots.

    Engage With: Reach (reaching a hand spot starts it) or Grip (a grip pressed within reach of one starts it). Release's When I
    release grip is offered only with Grip. Engage With is not offered while Button is a grip (Left or Right Bumper), nor for a
    mechanism with a grip engagement of its own.

    Prompt Text: what the game's prompt says for it, for the Default or a variation of its own. Until it is edited it shows the
    game code's text for its Engage With (and follows it); once edited, the text is its own from then on, kept as typed (an empty
    one too). Not shown for a mechanism with no prompt.

    Hand spots are libs/accessories accessories under the selection's accessory key, edited with that library's editor. A hand
    reaches the mechanism at its nearest spot and is put on it, so something worked from several places has a spot at each.
]]

local uevrUtils = require("libs/uevr_utils")
local configui = require("libs/configui")
local accessories = require("libs/accessories")
local controllers = require("libs/controllers")

local M = {}

local configFileName = "dev/mechanisms_config_dev"
local configTabLabel = "Mechanisms Dev Config"
local widgetPrefix = "uevr_mechanism_"
local STATUS_INTERVAL = 500 -- ms between updates of the status lines and the search for new variations

local ACTION_LABELS = {"Tap the button once", "Hold the button"}
local RELEASE_LABELS = {"When game animation finishes", "After a set time", "When I pull my hand back", "When I release grip"}
-- Release without Engage With: Grip (When I release grip is only for Grip).
local REACH_RELEASE_LABELS = {RELEASE_LABELS[1], RELEASE_LABELS[2], RELEASE_LABELS[3]}
local ENGAGE_LABELS = {"Reach", "Grip"}
local SETTING_WIDGETS = {"action", "button", "contactDistance", "engageWith", "release", "releaseAfter", "promptText"}
local FIND_WITH_LABELS = {"Game", "Pointing"}
local FindWith = {Game = 1, Pointing = 2}
local POINT_DISTANCE = 1000 -- cm, how far the right controller points
local NEAR_HAND_RADIUS = 30 -- cm, pointing at nothing: how near the right hand a thing has to be

-- Each type's own settings UI, by type name (see Type settings, below).
local typeUIs = {}
local function getTypeGroupID(typeName)
	return widgetPrefix .. "type_" .. typeName .. "_group"
end

---@type any
local mechanismsModule = nil
---@type any
local paramManager = nil
local panelBuilt = false
local wiredKeys = {}
local status = {entryIDs = {}, handleWithIDs = {}, variationNames = {}, variation = {}, offered = nil, offeredMechanism = nil,
	offeredClass = nil, frontText = nil, handsText = nil, typeNames = {}, pointed = nil}

local currentLogLevel = LogLevel.Error
function M.setLogLevel(val)
	currentLogLevel = val
end
function M.print(text, logLevel)
	if logLevel == nil then logLevel = LogLevel.Debug end
	if logLevel <= currentLogLevel then
		uevrUtils.print("[mechanisms config] " .. text, logLevel)
	end
end

local helpText = "A mechanism is one way of working things, like Sliding Door. Its Default settings apply to every kind of thing it works. Each kind is listed under Variation as you come across it; untick Use Default Settings on one to give it settings and hand spots of its own. To handle something new, stand at it so its prompt shows: if it works like an existing mechanism, pick that under Handle it with and press Add; otherwise leave A new mechanism and press Add. Find With: Game shows what the game offers now, or what you are using (in use); Pointing shows what the right controller points at, or the nearest thing to that hand, and keeps it while this menu is open. Type says how the mechanism is worked (Button: reach a hand spot and a button is pressed); Engage With: Reach starts it as a hand reaches its spot, Grip only when a grip is pressed within Reach of it, and Release then says when the hands let go (When I release grip, offered with Grip: as the grip is let go of); the line under it says what game code that type still needs, or Ready. Ladder: Getting on is pressing a button to get on, as a Button does (untick Use Getting On Stage when walking up to a ladder puts you on it); Climbing is while you are on it: a grip on the rungs takes hold and pulling down climbs. With Snap Hands To Hand Spots, a hand that takes hold is put on its hand spot, moved to the rung it took, so place the spots on one rung. Grip Animation is the pose of a hand holding the rungs: Default uses the hand spot's own Grip Animation; any other choice replaces it."
local handSpotHelp = "Each hand spot is an accessory: add one per hand with Left Hand Always or Right Hand Always as the activation, pick a socket if the hand should move with a part of it, tick Test Left or Test Right to put the hand there, and tune its position. For something worked from more than one place, like both sides of a door, add a spot at each place: the hand uses the nearest one."

local function getMechanism(entryID)
	for _, mechanism in ipairs(mechanismsModule.getMechanisms()) do
		if mechanism:getEntryID() == entryID then return mechanism end
	end
	return nil
end

local function getActiveMechanism()
	local mechanism = getMechanism(paramManager:get({"_profileState", "currentEditingProfile"}))
	return mechanism or mechanismsModule.getMechanisms()[1]
end

-- The selected variation of a mechanism (its class name), or nil for its Default.
local function getActiveVariation(mechanism)
	if mechanism == nil or not mechanism:isDataDefined() then return nil end
	local className = status.variation[mechanism:getEntryID()]
	if className == nil then return nil end
	for _, name in ipairs(mechanism:getVariations()) do
		if name == className then return className end
	end
	status.variation[mechanism:getEntryID()] = nil
	return nil
end

local function addAll(target, list)
	for _, widget in ipairs(list or {}) do target[#target + 1] = widget end
end

-- Every accessory key in use, in mechanism order.
local function getAccessoryKeys()
	local keys, seen = {}, {}
	for _, mechanism in ipairs(mechanismsModule.getMechanisms()) do
		for _, key in ipairs(mechanism:getAccessoryKeys()) do
			if not seen[key] then
				seen[key] = true
				keys[#keys + 1] = key
			end
		end
	end
	return keys
end

-- Every Ladder's side accessory key (its Climbing's side hand spots), in mechanism order.
local function getSideAccessoryKeys()
	local keys, seen = {}, {}
	for _, mechanism in ipairs(mechanismsModule.getMechanisms()) do
		for _, key in ipairs(mechanism:getSideAccessoryKeys()) do
			if not seen[key] then
				seen[key] = true
				keys[#keys + 1] = key
			end
		end
	end
	return keys
end

local function getSpotsGroupID(key)
	return mechanismsModule.getAccessoryWidgetPrefix(key) .. "group"
end

-- The accessory editor for a key, in a group shown only while it is the selection's. label: its tree's (default "Hand Locations").
local function getSpotWidgets(key, label)
	local prefix = mechanismsModule.getAccessoryWidgetPrefix(key)
	local widgets = {{widgetType = "begin_group", id = getSpotsGroupID(key), isHidden = true}}
	for _, widget in ipairs(accessories.getConfigWidgets(key, prefix, 300) or {}) do
		widgets[#widgets + 1] = widget
		if widget.id == prefix .. "accessory_tree" then
			widget.label = label or "Hand Locations"
			widgets[#widgets + 1] = {widgetType = "checkbox", id = prefix .. "show_debug_location", label = "Show Debug Location", initialValue = false}
		end
	end
	widgets[#widgets + 1] = {widgetType = "end_group"}
	return widgets
end

local function getLayout()
	local layout = {}
	addAll(layout, {
		{widgetType = "checkbox", id = widgetPrefix .. "paused", label = "Disable Mechanisms", initialValue = false},
		{widgetType = "new_line"},
		{widgetType = "combo", id = widgetPrefix .. "find_with", label = "Find With", selections = FIND_WITH_LABELS, initialValue = 1, width = 200},
		{widgetType = "text", id = widgetPrefix .. "in_front", wrapped = true, label = "In front of you: nothing the game offers"},
		{widgetType = "begin_group", id = widgetPrefix .. "add_group", isHidden = true},
			{widgetType = "combo", id = widgetPrefix .. "handle_with", label = "Handle it with", selections = {"A new mechanism"}, initialValue = 1, width = 200},
			--{widgetType = "same_line"},
			{ widgetType = "indent", width = 185},
				{widgetType = "button", id = widgetPrefix .. "add_here", label = "Add"},
			{widgetType = "unindent", width = 185},
		{widgetType = "end_group"},
		{widgetType = "begin_group", id = widgetPrefix .. "select_group", isHidden = true},
			{ widgetType = "indent", width = 185},
				{widgetType = "button", id = widgetPrefix .. "select_here", label = "Select It"},
			{widgetType = "unindent", width = 185},
		{widgetType = "end_group"},
		--{widgetType = "new_line"},
	})
	-- Current Mechanism and Rename (libs/core/params' profile widgets).
	addAll(layout, paramManager.getProfilePreConfigurationWidgets(widgetPrefix, "Mechanism"))
	addAll(layout, {
		{widgetType = "begin_group", id = widgetPrefix .. "profile_group", isHidden = false}, {widgetType = "indent", width = 10}, {widgetType = "text", label = "Mechanism Configuration"}, {widgetType = "begin_rect"},
		--{widgetType = "text", id = widgetPrefix .. "applies_to", wrapped = true, label = ""},
		{widgetType = "begin_group", id = widgetPrefix .. "type_group", isHidden = false},
			{widgetType = "combo", id = widgetPrefix .. "type", label = "Type", selections = {"Button"}, initialValue = 1},
			{widgetType = "text", id = widgetPrefix .. "type_status", wrapped = true, label = ""},
		{widgetType = "end_group"},
		{widgetType = "begin_group", id = widgetPrefix .. "variation_group", isHidden = false},
			{widgetType = "combo", id = widgetPrefix .. "variation", label = "Variation", selections = {"Default"}, initialValue = 1},
			{widgetType = "begin_group", id = widgetPrefix .. "use_default_group", isHidden = true}, {widgetType = "indent", width = 20},
				{widgetType = "checkbox", id = widgetPrefix .. "use_default", label = "Use Default Settings", initialValue = true},
			{widgetType = "unindent", width = 20}, {widgetType = "end_group"},
		{widgetType = "end_group"},
		{widgetType = "begin_group", id = widgetPrefix .. "config_group", isHidden = false}, {widgetType = "indent", width = 20},
	})
	-- Each type's own settings, in a group shown only while the selection is of that type.
	for _, info in ipairs(mechanismsModule.getTypes()) do
		local typeUI = typeUIs[info.name]
		if typeUI ~= nil then
			layout[#layout + 1] = {widgetType = "begin_group", id = getTypeGroupID(info.name), isHidden = true}
			addAll(layout, typeUI.getWidgets())
			layout[#layout + 1] = {widgetType = "end_group"}
		end
	end
	addAll(layout, {
			{ widgetType = "new_line"},
			{widgetType = "text", id = widgetPrefix .. "hands_status", wrapped = true, label = ""},
			--{widgetType = "text", id = widgetPrefix .. "spots_note", wrapped = true, label = ""},
		{widgetType = "unindent", width = 20}, {widgetType = "end_group"},
		{widgetType = "indent", width = 20},
	})
	for _, key in ipairs(getAccessoryKeys()) do addAll(layout, getSpotWidgets(key)) end
	addAll(layout, {
		{ widgetType = "unindent", width = 20},
		{ widgetType = "indent", width = 145},
			{widgetType = "button", id = widgetPrefix .. "remove_variation", label = "Delete Variation"},
		{widgetType = "unindent", width = 145},
		{widgetType = "end_rect", additionalSize = 12, rounding = 5}, {widgetType = "unindent", width = 10}, {widgetType = "end_group"},
		{widgetType = "new_line"},
		{ widgetType = "indent", width = 140},
			{widgetType = "button", id = widgetPrefix .. "delete_entry", label = "Delete Mechanism"},
		{widgetType = "unindent", width = 140},
		{widgetType = "new_line"},
		{widgetType = "tree_node", id = widgetPrefix .. "help_tree", initialOpen = true, label = "Help"},
			{widgetType = "text", id = widgetPrefix .. "help", label = helpText, wrapped = true},
			{widgetType = "text", id = widgetPrefix .. "help_spots", label = handSpotHelp, wrapped = true},
		{widgetType = "tree_pop"},
	})
	return layout
end

-- The mechanism to show a key's sockets and test its spots on: the current one if it uses the key, else the first that does.
local function getMechanismForKey(key)
	local active = getActiveMechanism()
	local list = mechanismsModule.getMechanisms()
	if active ~= nil then table.insert(list, 1, active) end
	for _, mechanism in ipairs(list) do
		for _, used in ipairs(mechanism:getAccessoryKeys()) do
			if used == key then return mechanism end
		end
		for _, used in ipairs(mechanism:getSideAccessoryKeys()) do
			if used == key then return mechanism end
		end
	end
	return nil
end

-- Accessory editor callbacks and socket lists, once per accessory key.
local function wireAccessoryKeys()
	local keys = getAccessoryKeys()
	for _, key in ipairs(getSideAccessoryKeys()) do keys[#keys + 1] = key end
	for _, key in ipairs(keys) do
		if not wiredKeys[key] then
			wiredKeys[key] = true
			local prefix = mechanismsModule.getAccessoryWidgetPrefix(key)
			accessories.createConfigCallbacks(key, prefix)
			accessories.setSocketProvider(key, function(callback)
				local mechanism = getMechanismForKey(key)
				local component = mechanism ~= nil and mechanism:getAccessoryComponent(mechanism:getActor() or mechanism:findNearest()) or nil
				if component ~= nil then uevrUtils.getSocketNames(component, callback) else callback(nil) end
			end)
			-- A Test box left ticked in an earlier session would keep that hand on the mechanism.
			configui.setValue(prefix .. "accessory_item_test_left_hand", false, true)
			configui.setValue(prefix .. "accessory_item_test_right_hand", false, true)
		end
	end
end

-- The mechanism list, the selection's values, and its hand spots shown (the others hidden).
local function refreshUI()
	local active = getActiveMechanism()
	local ids, labels, current = {}, {}, 1
	local handleIDs, handleLabels = {false}, {"A new mechanism"}
	for i, mechanism in ipairs(mechanismsModule.getMechanisms()) do
		ids[i] = mechanism:getEntryID()
		labels[i] = mechanism:getLabel()
		if mechanism == active then current = i end
		if mechanism:isDataDefined() then
			handleIDs[#handleIDs + 1] = mechanism:getEntryID()
			handleLabels[#handleLabels + 1] = mechanism:getLabel()
		end
	end
	status.entryIDs, status.handleWithIDs = ids, handleIDs
	configui.setSelections(widgetPrefix .. "active_profile", labels)
	configui.setValue(widgetPrefix .. "active_profile", current, true)
	configui.setSelections(widgetPrefix .. "handle_with", handleLabels)
	if (configui.getValue(widgetPrefix .. "handle_with") or 1) > #handleLabels then configui.setValue(widgetPrefix .. "handle_with", 1, true) end

	configui.setHidden(widgetPrefix .. "profile_group", active == nil)
	status.shownSpotKey = nil
	status.shownSideSpotKey = nil
	if active == nil then
		for _, key in ipairs(getAccessoryKeys()) do configui.setHidden(getSpotsGroupID(key), true) end
		return
	end

	local isData = active:isDataDefined()
	local variation = getActiveVariation(active)
	local usesDefault = variation ~= nil and active:usesDefault(variation)

	-- The Variation dropdown: Default, then each variation (one with settings of its own says so).
	local names, variationLabels, currentVariation = {false}, {"Default"}, 1
	if isData then
		for _, className in ipairs(active:getVariations()) do
			names[#names + 1] = className
			variationLabels[#variationLabels + 1] = (mechanismsModule.getShortClassName(className) or className) .. (active:usesDefault(className) and "" or " (own settings)")
			if className == variation then currentVariation = #names end
		end
	end
	status.variationNames = names
	configui.setHidden(widgetPrefix .. "variation_group", not isData)
	configui.setSelections(widgetPrefix .. "variation", variationLabels)
	configui.setValue(widgetPrefix .. "variation", currentVariation, true)
	configui.setHidden(widgetPrefix .. "use_default_group", variation == nil)
	configui.setHidden(widgetPrefix .. "remove_variation", variation == nil)
	configui.setValue(widgetPrefix .. "use_default", usesDefault, true)

	-- The type, and what game code it still needs (a mechanism made in code has neither).
	local typeName = active:getType() or mechanismsModule.DEFAULT_TYPE
	local typeNames, typeLabels, currentType, typeLabel = {}, {}, 1, typeName
	for i, info in ipairs(mechanismsModule.getTypes()) do
		typeNames[i], typeLabels[i] = info.name, info.label
		if info.name == typeName then currentType, typeLabel = i, info.label end
	end
	status.typeNames = typeNames
	configui.setHidden(widgetPrefix .. "type_group", not isData)
	configui.setSelections(widgetPrefix .. "type", typeLabels)
	configui.setValue(widgetPrefix .. "type", currentType, true)
	local missing = mechanismsModule.getMissingAdapterFunctions(active)
	configui.setLabel(widgetPrefix .. "type_status", #missing == 0 and "Ready" or (typeLabel .. " needs game code: " .. table.concat(missing, ", ")))

	-- The settings shown: the selection's type's own, and no other type's.
	for name, _ in pairs(typeUIs) do configui.setHidden(getTypeGroupID(name), name ~= typeName) end
	local typeUI = typeUIs[typeName]
	if typeUI ~= nil then
		typeUI.refresh({mechanism = active, variation = variation, usesDefault = usesDefault, isData = isData, settings = active:getSettings(variation)})
	end

	-- local appliesTo
	-- if isData then
	-- 	local class = mechanismsModule.getShortClassName(paramManager:get({active:getEntryID(), "class"})) or "?"
	-- 	if variation == nil then
	-- 		appliesTo = "Default settings: used by every variation below that uses the Default, and by everything derived from " .. class .. " not listed yet."
	-- 	elseif usesDefault then
	-- 		appliesTo = "This variation uses the Default settings. Untick Use Default Settings to give it its own."
	-- 	else
	-- 		appliesTo = "This variation's own settings. Tick Use Default Settings to use the Default again; these are kept."
	-- 	end
	-- else
	-- 	appliesTo = "This mechanism is made in the game's code. Its reach, its release time (0 = off) and its hand spots can be changed here."
	-- end
	-- configui.setLabel(widgetPrefix .. "applies_to", appliesTo)

	-- Hand spots: the selection's editor, or (a variation using the Default) none.
	local activeKey = not usesDefault and active:getAccessoryKey(variation) or nil
	status.shownSpotKey = activeKey
	for _, key in ipairs(getAccessoryKeys()) do configui.setHidden(getSpotsGroupID(key), key ~= activeKey) end
	-- local note = ""
	-- if usesDefault then
	-- 	note = "Hand spots: the Default's."
	-- elseif activeKey == nil then
	-- 	note = "This mechanism has no hand spots."
	-- end
	--configui.setLabel(widgetPrefix .. "spots_note", note)
	configui.setLabel(widgetPrefix .. "delete_entry", isData and "Delete Mechanism" or "Reset Settings")
end

local function buildPanel()
	-- The layout starts with its status lines and groups as new.
	status.frontText, status.handsText = nil, nil
	configui.update({{panelLabel = configTabLabel, saveFile = configFileName, layout = getLayout()}})
	panelBuilt = true
	mechanismsModule.setPaused(configui.getValue(widgetPrefix .. "paused") == true)
	-- With no game adapter, things are found by pointing only.
	configui.setHidden(widgetPrefix .. "find_with", not mechanismsModule.hasGameAdapter())
	wireAccessoryKeys()
	refreshUI()
end

local function setActive(entryID, className)
	paramManager:set({"_profileState", "currentEditingProfile"}, entryID, true)
	status.variation[entryID] = className
	refreshUI()
end

local function formatHand(mechanism, hand, name)
	local distance, label = mechanism:getHandSpotDistance(hand)
	if distance == nil then return name .. " hand: no spot here" end
	if type(label) ~= "string" or label == "" then label = "its nearest spot" end
	return string.format("%s hand: %.0f cm from %s", name, distance, label)
end

------------------- Show Debug Location -------------------
-- A sphere where the accessory selected in the shown Hand Locations editor puts a hand, while that editor's Show Debug Location
-- box is ticked.
local DEBUG_SPHERE_MESH = "StaticMesh /Engine/BasicShapes/Sphere.Sphere"
local DEBUG_SPHERE_SCALE = 0.05 -- the engine sphere is 100 cm across
local debugSphere = {component = nil, key = nil, target = nil, shown = false}

local function setDebugSphereShown(shown)
	local component = uevrUtils.getValid(debugSphere.component)
	if component == nil or debugSphere.shown == shown then return end
	component:SetVisibility(shown, false)
	debugSphere.shown = shown
end

local function forgetDebugSphere()
	debugSphere.component, debugSphere.target, debugSphere.shown = nil, nil, false
end

local function destroyDebugSphere()
	local component = uevrUtils.getValid(debugSphere.component)
	if component ~= nil then uevrUtils.destroyComponent(component, true) end
	forgetDebugSphere()
end

-- With the status lines (every STATUS_INTERVAL): whether the shown editor's box is ticked and what its accessory is on (the
-- mechanism's actor or the nearest one), and the sphere made when first needed.
local function updateDebugSphereTarget()
	-- The side hand spots' editor (a Ladder's) first, when its box is ticked.
	local key = status.shownSideSpotKey
	local ticked = key ~= nil and configui.getValue(mechanismsModule.getAccessoryWidgetPrefix(key) .. "show_debug_location") == true
	if not ticked then
		key = status.shownSpotKey
		ticked = key ~= nil and configui.getValue(mechanismsModule.getAccessoryWidgetPrefix(key) .. "show_debug_location") == true
	end
	local target = nil
	if ticked then
		local mechanism = getMechanismForKey(key)
		target = mechanism ~= nil and mechanism:getAccessoryComponent(mechanism:getActor() or mechanism:findNearest()) or nil
	end
	debugSphere.key = ticked and key or nil
	debugSphere.target = target
	if target ~= nil and uevrUtils.getValid(debugSphere.component) == nil then
		forgetDebugSphere()
		local component = uevrUtils.createStaticMeshComponent(DEBUG_SPHERE_MESH, {visible = false, collisionEnabled = false})
		if component ~= nil then
			component:SetWorldScale3D(uevrUtils.vector(DEBUG_SPHERE_SCALE, DEBUG_SPHERE_SCALE, DEBUG_SPHERE_SCALE))
			debugSphere.component = component
		end
	end
end

-- Every frame: the sphere on the selected accessory's location (so it follows a location being dragged), or hidden.
local function updateDebugSphere()
	-- Nothing to do with no sphere, or with no box ticked and the sphere already hidden.
	if debugSphere.component == nil or (debugSphere.key == nil and not debugSphere.shown) then return end
	local key, target = debugSphere.key, uevrUtils.getValid(debugSphere.target)
	local location = nil
	if key ~= nil and target ~= nil then
		local id = configui.getValue(mechanismsModule.getAccessoryWidgetPrefix(key) .. "accessory_item_id")
		if type(id) == "string" and id ~= "" then location = accessories.getTargetAccessoryLocation(key, id, target) end
	end
	local component = location ~= nil and uevrUtils.getValid(debugSphere.component) or nil
	if component ~= nil then component:K2_SetWorldLocation(uevrUtils.vector(location), false, reusable_hit_result, false) end
	setDebugSphereShown(component ~= nil)
end

------------------- Find With -------------------
-- Game: what the game offers now, or else what the player is using (the game adapter). Pointing (no game code): what the right
-- controller points at, or with nothing there the thing nearest the right hand. With no game adapter, only Pointing.
local function getFindWith()
	if not mechanismsModule.hasGameAdapter() then return FindWith.Pointing end
	return tonumber(configui.getValue(widgetPrefix .. "find_with")) or FindWith.Game
end

-- The actor of the thing nearest a location, within NEAR_HAND_RADIUS (a short sphere sweep there).
local function getActorNear(location)
	local world = uevrUtils.get_world()
	if world == nil then return nil end
	local finish = uevrUtils.vector(location.X, location.Y, location.Z + 1)
	local hit = kismet_system_library:SphereTraceSingle(world, location, finish, NEAR_HAND_RADIUS, 0, false, {uevrUtils.getValid(pawn)}, 0,
		reusable_hit_result, true, zero_color, zero_color, 1.0)
	if not hit then return nil end
	local details = uevrUtils.getCleanHitResult(reusable_hit_result)
	return details ~= nil and uevrUtils.getValid(details.Actor) or nil
end

local function tracePointedActor()
	local origin = controllers.getControllerLocation(Handed.Right)
	local direction = controllers.getControllerDirection(Handed.Right)
	if origin == nil or direction == nil then return nil end
	local hit = uevrUtils.getLineTraceHitResult(origin, direction, 0, false, {uevrUtils.getValid(pawn)}, nil, POINT_DISTANCE, true)
	local actor = hit ~= nil and uevrUtils.getValid(hit.Actor) or nil
	if actor == nil then actor = getActorNear(origin) end
	return actor
end

-- While this menu is open the controller points at it, so what was pointed at before is kept.
local function getPointedActor()
	local drawingUI = uevr.params.functions.is_drawing_ui ~= nil and uevr.params.functions.is_drawing_ui()
	if not drawingUI then
		local ok, actor = pcall(tracePointedActor)
		status.pointed = ok and actor or nil
	end
	return uevrUtils.getValid(status.pointed)
end

-- "In front of you", how far each hand is from the current mechanism's spots, and new variations.
local function updateStatus()
	if not panelBuilt then return end
	updateDebugSphereTarget()
	if mechanismsModule.discoverVariations() then refreshUI() end

	local pointing = getFindWith() == FindWith.Pointing
	local offered, inUse = nil, false
	if pointing then
		offered = getPointedActor()
	else
		local state = nil
		offered, state = mechanismsModule.getCurrentActor()
		inUse = offered ~= nil and state ~= mechanismsModule.State.Offered
	end
	local mechanism, className = nil, nil
	if offered ~= nil then mechanism, className = mechanismsModule.getMechanismForActor(offered) end
	local text = pointing and "In front of you: nothing pointed at" or "In front of you: nothing the game offers"
	if offered ~= nil then
		local name = (mechanismsModule.getShortClassName(className) or "?") .. (inUse and " (in use)" or "")
		if mechanism ~= nil then
			local own = mechanism:isDataDefined() and not mechanism:usesDefault(className) and ", own settings" or ""
			text = "In front of you: " .. name .. ", handled by " .. mechanism:getLabel() .. own .. (mechanism:isEngaged() and " (hands on it)" or "")
		else
			text = "In front of you: " .. name .. ", not handled yet"
		end
	end
	status.offered, status.offeredMechanism, status.offeredClass = offered, mechanism, className
	if text ~= status.frontText then
		status.frontText = text
		configui.setLabel(widgetPrefix .. "in_front", text)
		configui.setHidden(widgetPrefix .. "add_group", offered == nil or mechanism ~= nil)
		configui.setHidden(widgetPrefix .. "select_group", mechanism == nil)
	end

	local active = getActiveMechanism()
	local hands = ""
	if active ~= nil and #active:getAccessoryKeys() > 0 then
		local reach = tonumber(active:getSettings(getActiveVariation(active)).contactDistance) or 0
		hands = formatHand(active, Handed.Left, "Left") .. ". " .. formatHand(active, Handed.Right, "Right") .. string.format(". Reach is %.0f cm.", reach)
	end
	if hands ~= status.handsText then
		status.handsText = hands
		configui.setLabel(widgetPrefix .. "hands_status", hands)
	end
end

-- Saves a setting of the selection (a variation with settings of its own, else the Default).
local function saveSetting(key, value)
	local active = getActiveMechanism()
	if active == nil then return end
	local variation = getActiveVariation(active)
	if variation ~= nil and active:usesDefault(variation) then return end
	mechanismsModule.setSetting(active, variation, key, value)
end

------------------- Type settings -------------------
-- Each type supplies its own settings UI: getWidgets() -> widgets, refresh(ctx) shows the selection's values, and
-- registerHandlers(helpers) saves changes. Types don't share UI. The panel shows only the selection's type's.
--   ctx: {mechanism, variation (nil: the Default), usesDefault, isData, settings (the selection's, as they apply)}
--   helpers: {saveSetting(key, value) (to the selected variation, or the Default), refresh()}

-- Button's six settings (Button, Activation, Engage With, Reach, Release, Let go after), under a widget ID prefix: the widgets of each type
-- that has them are its own (Button's, and Ladder's Getting on), but they edit the same saved settings.
local function getButtonSettingWidgets(prefix)
	return {
		{widgetType = "begin_group", id = prefix .. "data_group", isHidden = false},
			{widgetType = "combo", id = prefix .. "button", label = "Button", selections = mechanismsModule.BUTTONS, initialValue = 1},
			{widgetType = "combo", id = prefix .. "action", label = "Activation", selections = ACTION_LABELS, initialValue = 1, },
		{widgetType = "end_group"},
		{widgetType = "begin_group", id = prefix .. "engage_group", isHidden = false},
			{widgetType = "combo", id = prefix .. "engageWith", label = "Engage With", selections = ENGAGE_LABELS, initialValue = 1},
		{widgetType = "end_group"},
		{widgetType = "drag_float", id = prefix .. "contactDistance", label = "Reach (cm)", speed = 0.5, range = {1, 1000}, initialValue = 20},
		{widgetType = "begin_group", id = prefix .. "release_group", isHidden = false},
			{widgetType = "combo", id = prefix .. "release", label = "Release", selections = RELEASE_LABELS, initialValue = 1},
		{widgetType = "end_group"},
		{widgetType = "begin_group", id = prefix .. "release_after_group", isHidden = false}, {widgetType = "indent", width = 20},
			{widgetType = "drag_float", id = prefix .. "releaseAfter", label = "Time (secs)", speed = 0.05, range = {0, 30}, initialValue = 0},
		{widgetType = "unindent", width = 20}, {widgetType = "end_group"},
		{widgetType = "begin_group", id = prefix .. "prompt_group", isHidden = false},
			{widgetType = "input_text", id = prefix .. "promptText", label = "Prompt Text", initialValue = ""},
		{widgetType = "end_group"},
	}
end

-- hidden: none shown (a variation using the Default). A mechanism made in code shows all but Button and Activation. Engage With
-- is shown only where it applies (not while Button is a grip), and When I release grip only with Grip.
local function refreshButtonSettings(prefix, ctx, hidden)
	local isData, settings = ctx.isData, ctx.settings
	configui.setHidden(prefix .. "data_group", not isData or hidden)
	configui.setHidden(prefix .. "contactDistance", hidden)
	local canGrip = ctx.mechanism ~= nil and ctx.mechanism:canEngageWithGrip()
		and not (isData and mechanismsModule.isGripButton(settings.button))
	configui.setHidden(prefix .. "engage_group", hidden or not canGrip)
	local engageGrip = canGrip and tonumber(settings.engageWith) == mechanismsModule.EngageWith.Grip
	configui.setHidden(prefix .. "release_group", hidden)
	configui.setSelections(prefix .. "release", engageGrip and RELEASE_LABELS or REACH_RELEASE_LABELS)
	-- Kept as saved: without Grip, When I release grip works as when the game finishes, and is shown so.
	local release = tonumber(settings.release) or 1
	if release == mechanismsModule.Release.GripReleased and not engageGrip then release = mechanismsModule.Release.GameFinishes end
	configui.setHidden(prefix .. "release_after_group", hidden or release ~= mechanismsModule.Release.AfterTime)
	-- Prompt Text: its own text once edited, else the prompt's own for its Engage With. None without a prompt.
	local text, gripText = nil, nil
	if ctx.mechanism ~= nil then text, gripText = ctx.mechanism:getPromptTexts() end
	configui.setHidden(prefix .. "prompt_group", hidden or text == nil)
	local custom = settings.promptTextCustom == true
	for _, key in ipairs(SETTING_WIDGETS) do
		local value = settings[key]
		if key == "promptText" then
			if custom then value = type(value) == "string" and value or "" else value = (engageGrip and gripText) or text or "" end
		elseif key == "contactDistance" or key == "releaseAfter" then
			value = tonumber(value) or 0
		else
			value = tonumber(value) or 1
		end
		if key == "release" then value = release end
		configui.setValue(prefix .. key, value, true)
	end
end

local function registerButtonSettingHandlers(prefix, helpers)
	configui.onUpdate(prefix .. "action", function(value) helpers.saveSetting("action", tonumber(value) or 1) end)
	configui.onUpdate(prefix .. "button", function(value)
		helpers.saveSetting("button", tonumber(value) or 1)
		-- Engage With isn't offered while Button is a grip.
		helpers.refresh()
	end)
	configui.onUpdate(prefix .. "engageWith", function(value)
		helpers.saveSetting("engageWith", tonumber(value) or 1)
		-- When I release grip is offered only with Grip, and a Prompt Text not edited follows Engage With.
		helpers.refresh()
	end)
	-- An edit makes the text its own from then on, kept as typed.
	configui.onUpdate(prefix .. "promptText", function(value)
		helpers.saveSetting("promptText", type(value) == "string" and value or "")
		local active = getActiveMechanism()
		if active ~= nil and active:getSettings(getActiveVariation(active)).promptTextCustom ~= true then
			helpers.saveSetting("promptTextCustom", true)
		end
	end)
	configui.onUpdate(prefix .. "contactDistance", function(value) helpers.saveSetting("contactDistance", tonumber(value)) end)
	configui.onUpdate(prefix .. "releaseAfter", function(value) helpers.saveSetting("releaseAfter", tonumber(value)) end)
	configui.onUpdate(prefix .. "release", function(value)
		helpers.saveSetting("release", tonumber(value) or 1)
		helpers.refresh()
	end)
end

-- Button. A mechanism made in code shows it too, in part.
typeUIs.button = {
	getWidgets = function() return getButtonSettingWidgets(widgetPrefix) end,
	refresh = function(ctx) refreshButtonSettings(widgetPrefix, ctx, ctx.usesDefault) end,
	registerHandlers = function(helpers) registerButtonSettingHandlers(widgetPrefix, helpers) end,
}

-- Ladder: Getting on (Use Getting On Stage and, while it is ticked, Button's settings) and Climbing (Snap Hands To Hand Spots).
local LADDER_PREFIX = widgetPrefix .. "ladder_"
-- Climbing's Grip Animation: Default (the hand spot's), then the hands parameters file's grip animations. The ids pair with the
-- entries after Default.
local ladderGripAnimationIDs, ladderGripAnimationLabels = {}, {"Default"}
local function setLadderGripAnimations(ids, labels)
	ladderGripAnimationIDs, ladderGripAnimationLabels = {}, {"Default"}
	for i, id in ipairs(ids or {}) do
		ladderGripAnimationIDs[i] = id
		ladderGripAnimationLabels[i + 1] = labels ~= nil and labels[i] ~= nil and tostring(labels[i]) or tostring(id)
	end
	if panelBuilt then
		configui.setSelections(LADDER_PREFIX .. "climbGripAnimation", ladderGripAnimationLabels)
		refreshUI()
	end
end
typeUIs.ladder = {
	getWidgets = function()
		local widgets = {
			{widgetType = "begin_group", id = LADDER_PREFIX .. "settings_group", isHidden = false},
				{widgetType = "text", id = LADDER_PREFIX .. "geton_label", label = "Getting on"},
				{widgetType = "indent", width = 20},
				{widgetType = "checkbox", id = LADDER_PREFIX .. "useGetOn", label = "Use Getting On Stage", initialValue = true},
		}
		addAll(widgets, getButtonSettingWidgets(LADDER_PREFIX))
		addAll(widgets, {
				{widgetType = "unindent", width = 20},
				{widgetType = "text", id = LADDER_PREFIX .. "climb_label", label = "Climbing"},
				{widgetType = "indent", width = 20},
				{widgetType = "checkbox", id = LADDER_PREFIX .. "rungGrip", label = "Hold Rungs", initialValue = true},
				{widgetType = "begin_group", id = LADDER_PREFIX .. "rung_group", isHidden = false}, {widgetType = "indent", width = 20},
					{widgetType = "checkbox", id = LADDER_PREFIX .. "snapHands", label = "Snap Hands To Hand Spots", initialValue = true},
					{widgetType = "begin_group", id = LADDER_PREFIX .. "snap_near_group", isHidden = false}, {widgetType = "indent", width = 20},
						{widgetType = "checkbox", id = LADDER_PREFIX .. "rungKeepAlong", label = "Keep Position Along Rung", initialValue = false},
						{widgetType = "checkbox", id = LADDER_PREFIX .. "snapNear", label = "Only Snap Near A Rung", initialValue = false},
						{widgetType = "begin_group", id = LADDER_PREFIX .. "snap_distance_group", isHidden = true}, {widgetType = "indent", width = 20},
							{widgetType = "drag_float", id = LADDER_PREFIX .. "snapDistance", label = "Snap Distance (cm)", speed = 0.25, range = {1, 30}, initialValue = 5},
						{widgetType = "unindent", width = 20}, {widgetType = "end_group"},
					{widgetType = "unindent", width = 20}, {widgetType = "end_group"},
					{widgetType = "combo", id = LADDER_PREFIX .. "climbGripAnimation", label = "Rung Grip Animation", selections = ladderGripAnimationLabels, initialValue = 1},
				{widgetType = "unindent", width = 20}, {widgetType = "end_group"},
				{widgetType = "checkbox", id = LADDER_PREFIX .. "sideGrip", label = "Hold Sides", initialValue = false},
				{widgetType = "begin_group", id = LADDER_PREFIX .. "side_group", isHidden = true}, {widgetType = "indent", width = 20},
					{widgetType = "drag_float", id = LADDER_PREFIX .. "sideStart", label = "Sides Start At (cm from centre)", speed = 0.25, range = {0, 60}, initialValue = 16},
					{widgetType = "checkbox", id = LADDER_PREFIX .. "sideSnap", label = "Snap To Side (Keeps Height)", initialValue = false},
					{widgetType = "text", id = LADDER_PREFIX .. "side_spots_note", wrapped = true, label = "A hand with no side hand location uses its hand location below."},
		})
		-- The side hand spots' editor of every Ladder key, each shown only while it is the selection's.
		for _, key in ipairs(getSideAccessoryKeys()) do addAll(widgets, getSpotWidgets(key, "Side Hand Locations")) end
		addAll(widgets, {
				{widgetType = "unindent", width = 20}, {widgetType = "end_group"},
				{widgetType = "checkbox", id = LADDER_PREFIX .. "animateSteps", label = "Animate Steps With Hands", initialValue = false},
				{widgetType = "unindent", width = 20},
			{widgetType = "end_group"},
		})
		return widgets
	end,
	-- A variation using the Default shows none.
	refresh = function(ctx)
		local useGetOn = ctx.settings.useGetOn ~= false
		configui.setHidden(LADDER_PREFIX .. "settings_group", ctx.usesDefault)
		configui.setValue(LADDER_PREFIX .. "useGetOn", useGetOn, true)
		refreshButtonSettings(LADDER_PREFIX, ctx, ctx.usesDefault or not useGetOn)
		local snapHands, snapNear = ctx.settings.snapHands ~= false, ctx.settings.snapNear == true
		configui.setValue(LADDER_PREFIX .. "snapHands", snapHands, true)
		-- Only Snap Near A Rung only while snapping; its distance only while it is ticked.
		configui.setHidden(LADDER_PREFIX .. "snap_near_group", not snapHands)
		configui.setValue(LADDER_PREFIX .. "snapNear", snapNear, true)
		configui.setHidden(LADDER_PREFIX .. "snap_distance_group", not snapNear)
		configui.setValue(LADDER_PREFIX .. "snapDistance", tonumber(ctx.settings.snapDistance) or 5, true)
		-- A part's settings only while it is held.
		local rungGrip, sideGrip = ctx.settings.rungGrip ~= false, ctx.settings.sideGrip == true
		configui.setValue(LADDER_PREFIX .. "rungGrip", rungGrip, true)
		configui.setHidden(LADDER_PREFIX .. "rung_group", not rungGrip)
		configui.setValue(LADDER_PREFIX .. "sideGrip", sideGrip, true)
		configui.setHidden(LADDER_PREFIX .. "side_group", not sideGrip)
		configui.setValue(LADDER_PREFIX .. "sideStart", tonumber(ctx.settings.sideStart) or 16, true)
		configui.setValue(LADDER_PREFIX .. "sideSnap", ctx.settings.sideSnap == true, true)
		-- Side hand spots: the selection's editor, or (a variation using the Default) none.
		local sideKey = not ctx.usesDefault and ctx.mechanism:getSideAccessoryKey(ctx.variation) or nil
		status.shownSideSpotKey = sideKey
		for _, key in ipairs(getSideAccessoryKeys()) do configui.setHidden(getSpotsGroupID(key), key ~= sideKey) end
		configui.setValue(LADDER_PREFIX .. "rungKeepAlong", ctx.settings.rungKeepAlong == true, true)
		-- Grip Animations: the saved id's entry, else (none saved, or one no longer in the list) Default.
		local function getGripIndex(saved)
			local index = 1
			for i, id in ipairs(ladderGripAnimationIDs) do
				if id == saved then index = i + 1 end
			end
			return index
		end
		configui.setValue(LADDER_PREFIX .. "climbGripAnimation", getGripIndex(ctx.settings.climbGripAnimation), true)
		configui.setValue(LADDER_PREFIX .. "animateSteps", ctx.settings.animateSteps == true, true)
	end,
	registerHandlers = function(helpers)
		registerButtonSettingHandlers(LADDER_PREFIX, helpers)
		configui.onUpdate(LADDER_PREFIX .. "useGetOn", function(value)
			helpers.saveSetting("useGetOn", value == true)
			helpers.refresh()
		end)
		configui.onUpdate(LADDER_PREFIX .. "snapHands", function(value)
			helpers.saveSetting("snapHands", value == true)
			helpers.refresh()
		end)
		configui.onUpdate(LADDER_PREFIX .. "snapNear", function(value)
			helpers.saveSetting("snapNear", value == true)
			helpers.refresh()
		end)
		configui.onUpdate(LADDER_PREFIX .. "snapDistance", function(value) helpers.saveSetting("snapDistance", tonumber(value)) end)
		-- The id is saved, not the list position (the list follows the hands parameters file). Default saves "".
		configui.onUpdate(LADDER_PREFIX .. "climbGripAnimation", function(value)
			local index = tonumber(value) or 1
			helpers.saveSetting("climbGripAnimation", index > 1 and ladderGripAnimationIDs[index - 1] or "")
		end)
		configui.onUpdate(LADDER_PREFIX .. "rungGrip", function(value)
			helpers.saveSetting("rungGrip", value == true)
			helpers.refresh()
		end)
		configui.onUpdate(LADDER_PREFIX .. "sideGrip", function(value)
			helpers.saveSetting("sideGrip", value == true)
			helpers.refresh()
		end)
		configui.onUpdate(LADDER_PREFIX .. "sideStart", function(value) helpers.saveSetting("sideStart", tonumber(value)) end)
		configui.onUpdate(LADDER_PREFIX .. "sideSnap", function(value) helpers.saveSetting("sideSnap", value == true) end)
		configui.onUpdate(LADDER_PREFIX .. "rungKeepAlong", function(value) helpers.saveSetting("rungKeepAlong", value == true) end)
		-- Applies from the next time the player gets on a ladder.
		configui.onUpdate(LADDER_PREFIX .. "animateSteps", function(value) helpers.saveSetting("animateSteps", value == true) end)
	end,
}

local function registerHandlers()
	configui.onUpdate(widgetPrefix .. "add_here", function()
		local offered = uevrUtils.getValid(status.offered)
		if offered == nil or status.offeredMechanism ~= nil then return end
		local handleWithID = status.handleWithIDs[configui.getValue(widgetPrefix .. "handle_with") or 1]
		local target = handleWithID and getMechanism(handleWithID) or nil
		if target ~= nil then
			local className = mechanismsModule.addVariation(target, offered)
			if className == nil then return end
			paramManager:set({"_profileState", "currentEditingProfile"}, target:getEntryID(), true)
			status.variation[target:getEntryID()] = className
		else
			local id = mechanismsModule.addEntry(offered)
			if id == nil then return end
			paramManager:set({"_profileState", "currentEditingProfile"}, id, true)
		end
		buildPanel()
	end)

	configui.onUpdate(widgetPrefix .. "select_here", function()
		local mechanism = status.offeredMechanism
		if mechanism == nil then return end
		setActive(mechanism:getEntryID(), mechanism:isDataDefined() and status.offeredClass or nil)
	end)

	configui.onUpdate(widgetPrefix .. "active_profile", function(value)
		local id = status.entryIDs[value]
		if id ~= nil then setActive(id, status.variation[id]) end
	end)

	configui.onUpdate(widgetPrefix .. "variation", function(value)
		local active = getActiveMechanism()
		if active == nil then return end
		status.variation[active:getEntryID()] = status.variationNames[value] or nil
		refreshUI()
	end)

	configui.onUpdate(widgetPrefix .. "use_default", function(value)
		local active = getActiveMechanism()
		local variation = getActiveVariation(active)
		if variation == nil then return end
		-- The first time a variation stops using the Default it gets new hand spots: the panel is built again for their editor.
		local keysBefore = #getAccessoryKeys()
		mechanismsModule.setVariationUseDefault(active, variation, value == true)
		if #getAccessoryKeys() ~= keysBefore then buildPanel() else refreshUI() end
	end)

	configui.onUpdate(widgetPrefix .. "remove_variation", function()
		local active = getActiveMechanism()
		local variation = getActiveVariation(active)
		if variation == nil then return end
		mechanismsModule.removeVariation(active, variation)
		status.variation[active:getEntryID()] = nil
		status.frontText = nil
		buildPanel()
	end)

	configui.onUpdate(widgetPrefix .. "rename_profile", function()
		local active = getActiveMechanism()
		if active == nil then return end
		configui.setHidden(widgetPrefix .. "rename_profile_group", false)
		configui.setValue(widgetPrefix .. "rename_profile_input", active:getLabel(), true)
	end)

	configui.onUpdate(widgetPrefix .. "rename_profile_update", function()
		local label = configui.getValue(widgetPrefix .. "rename_profile_input")
		local active = getActiveMechanism()
		if active ~= nil and type(label) == "string" and label ~= "" then paramManager:set({"_profileLabels", active:getEntryID()}, label, true) end
		configui.setHidden(widgetPrefix .. "rename_profile_group", true)
		status.frontText = nil
		refreshUI()
	end)

	configui.onUpdate(widgetPrefix .. "paused", function(value) mechanismsModule.setPaused(value == true) end)

	configui.onUpdate(widgetPrefix .. "find_with", function()
		status.pointed, status.frontText = nil, nil
	end)

	-- Changing the type makes the entry's mechanisms again; the selection stays on the entry.
	configui.onUpdate(widgetPrefix .. "type", function(value)
		local active = getActiveMechanism()
		local name = status.typeNames[value]
		if active == nil or name == nil or name == active:getType() then return end
		mechanismsModule.setType(active, name)
		status.frontText = nil
		refreshUI()
	end)

	-- Each type's own settings.
	local helpers = {saveSetting = saveSetting, refresh = function() refreshUI() end}
	for _, typeUI in pairs(typeUIs) do typeUI.registerHandlers(helpers) end

	-- Delete Mechanism removes one made here. One made in code can't be removed: its settings go back to the code's values.
	configui.onUpdate(widgetPrefix .. "delete_entry", function()
		local active = getActiveMechanism()
		if active == nil then return end
		if active:isDataDefined() then
			mechanismsModule.removeEntry(active:getEntryID())
			local first = mechanismsModule.getMechanisms()[1]
			paramManager:set({"_profileState", "currentEditingProfile"}, first ~= nil and first:getEntryID() or nil, true)
			buildPanel()
			return
		end
		paramManager:set({active:getEntryID(), "contactDistance"}, nil, true)
		paramManager:set({active:getEntryID(), "releaseAfter"}, nil, true)
		mechanismsModule.notifyEntriesChanged()
		refreshUI()
	end)
end

-- Builds the panel again, for mechanisms made after init.
function M.refresh()
	if mechanismsModule ~= nil then buildPanel() end
end

function M.init(m_mechanisms)
	if mechanismsModule ~= nil then return end
	mechanismsModule = m_mechanisms
	paramManager = m_mechanisms.getParamManager()
	paramManager.widgetPrefix = widgetPrefix
	registerHandlers()
	-- Climbing's grip animations: those sent before this was loaded, then each change.
	setLadderGripAnimations(m_mechanisms.getHandAnimations())
	uevrUtils.registerUEVRCallback("on_hand_animation_ids_changed", function(info)
		if type(info) == "table" then setLadderGripAnimations(info.ids, info.labels) end
	end)
	buildPanel()
	uevrUtils.setInterval(STATUS_INTERVAL, updateStatus)
	uevrUtils.registerPostEngineTickCallback(updateDebugSphere)
	-- The sphere's actor goes with the level; on Reset Scripts it is destroyed here.
	uevrUtils.registerPreLevelChangeCallback(forgetDebugSphere)
	uevr.params.sdk.callbacks.on_script_reset(destroyDebugSphere)
end

return M
