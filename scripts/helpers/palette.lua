--StaticMesh /Game/Environment/Hogsmeade/BLDG_Zonkos/meshes/SM_HM_Zonkos_Mystery_Can_Lid.SM_HM_Zonkos_Mystery_Can_Lid
--StaticMesh /Game/Environment/Overland_Common/Objects/ManMade/Static_Meshes/SM_OV_Trunk_Lg_Steamer.SM_OV_Trunk_Lg_Steamer
--StaticMesh /Game/Environment/Castle_Dungeon/meshes/Props/Containers/SM_C_Dun_Container_Med_A.SM_C_Dun_Container_Med_A
--StaticMesh /Game/Environment/BanditCamps/CampB/meshes/Tents/Components/SM_CampB_TentB_Roof_LOD.SM_CampB_TentB_Roof_LOD

--NiagaraSystem /Game/VFX/Niagara/Interactables/VFX_NS_Whizzbee_Levitate.VFX_NS_Whizzbee_Levitate
-- first half of effect has nice warping
--NiagaraSystem /Game/VFX/Mechanics/Swimming/Splashes/VFX_NS_Dive_Splash_Enter.VFX_NS_Dive_Splash_Enter
-- swirling glowy
--NiagaraSystem /Game/VFX/Particles/Magic/States/VFX_NS_Stunned_State.VFX_NS_Stunned_State
--NiagaraSystem /Game/VFX/Particles/Magic/CuresedState/VFX_NS_Cursed_Pro.VFX_NS_Cursed_Pro
--NiagaraSystem /Game/VFX/Niagara/AncientMagic/Pickup/VFX_NS_TMB_Plasma.VFX_NS_TMB_Plasma
--NiagaraSystem /Game/VFX/UI/Mission_EntryPoint_Beacon/VFX_NS_MissionEntryPoint_Location.VFX_NS_MissionEntryPoint_Location

local uevrUtils = require("libs/uevr_utils")
local controllers = require("libs/controllers")
local particles = require("libs/particles")
local attachments = require("libs/attachments")
local mathLib = require("libs/core/math_lib")
local ui = require("libs/ui")
local widget = require("libs/widget")
local widgetComponent = require("libs/widgetcomponent")
local gestures = require("libs/gestures")
local accessories = require("libs/accessories")
local spells = require("helpers/spells")
local audio = require("helpers/audio")

local M = {}
local loadAsset = uevrUtils.profiler:wrap("Palette: load asset", uevrUtils.getLoadedAsset)

-- Attachment adjustment mode: true holds the copy until a second left grip;
-- false requires holding grip. Retained for manual attachment tuning.
local TOGGLE_GRIP_FOR_ADJUSTMENTS = false
-- World-space centimetres. Keep the current per-item scale/pivot tuning.
local RADIUS = 18
local FORWARD_OFFSET = 10.16 -- Four inches away from the viewer, sampled at spawn.
local SELECT_DISTANCE = 8 -- Controller centre to model centre, in centimetres.
-- Item-count text position relative to each model, in centimetres.
-- Edit these, then Reset Scripts and reopen the wheel.
local COUNT_OFFSET_RIGHT = 2.7 -- Positive moves right; negative moves left.
local COUNT_OFFSET_DOWN = 6 -- Positive moves down; negative moves up.
local COUNT_OFFSET_TOWARD_VIEWER = 3.5 -- cm: 0 = model plane; positive = toward you; negative = behind.
local COUNT_DRAW_SIZE, COUNT_SCALE, COUNT_FONT_SIZE = 768, 0.08, 17
local COUNT_COLOR = "#00FF00FF"
local COUNT_FONT = "Font /Game/UI/Fonts/UI_FNT_Body.UI_FNT_Body"
local COUNT_BACKGROUND = "Texture2D /Game/UI/Icons/MenuAssets/UI_T_AmountFrame.UI_T_AmountFrame"
local COUNT_BACKGROUND_SIZE = 40 -- Widget pixels; follows the text plane's scale and depth.
local COUNT_REFRESH_SECONDS = 0.5
-- The stock wheel's no-mount icon, shown over an unlocked mount the game cannot summon right
-- now (e.g. while swimming). Drawn on the count text plane, centred on the model.
local NO_MOUNT_ICON = "Texture2D /Game/UI/Icons/HUD/UI_T_NoMountIcon.UI_T_NoMountIcon"
local NO_MOUNT_ICON_SIZE = 50 -- Widget pixels; COUNT_SCALE centimetres per pixel.
-- Each mount's iconOffset (in diamondItems) moves its icon from the model's slot centre, in
-- centimetres: right positive moves right, down positive moves down.
local WHEEL_SLOTS = {"ItemTop", "ItemTR", "ItemRight", "ItemBR", "ItemBottom", "ItemBL", "ItemLeft", "ItemTL"}
-- A double tap of the left trigger opens the diamond of the stock wheel's four standalone
-- items instead of the ring. A single tap acts once this many seconds pass without a second
-- tap; 0 makes single taps act immediately and disables the diamond.
local DOUBLE_TAP_WINDOW = 0.3
local DIAMOND_RADIUS = 18 -- Centimetres from the diamond's centre to each model.
-- Feather wind is a world-space material offset; these parameters are scaled with the model.
local WIND_PARAMETERS = {"Movement Amount", "Wind Texture Scale"}
-- Seconds after a left grip in which a right grip still counts as LB+RB (Ancient Magic).
-- That chord goes to the game instead of creating a held copy. Closed wheel only.
local CHORD_WINDOW = 0.2
-- Using a held copy (gesture mode). A potion is used when the hand reaches the mouth
-- zone from libs/gestures. A plant is used when the grip is released within
-- THROW_RELEASE_WINDOW seconds of a thrust (the gestures punch detector).
local THROW_RELEASE_WINDOW = 0.5
-- The shared punch detector only advances while polled, so a new plant copy would inherit
-- the previous hold's cooldown and hand position. Polling it with this huge delta (seconds)
-- finishes either and records the current hand position without reporting a thrust.
local PUNCH_PRIME_DELTA = 1000000
-- A drunk potion stays in the hand until the game's gulp plays, then disappears. The drink
-- animation's DrinkPotion event is about 0.4 s in; raise this if the bottle leaves too early.
local DRINK_GULP_SECONDS = 1.0
local DRINK_SHRINK_SECONDS = 0.2 -- After the gulp, the held potion shrinks away over this time.
-- The game's drink animation raises its own potion tool bottle. Keep that tool hidden for
-- this many seconds after a drink; it is spawned asynchronously and may re-show on equip.
local DRINK_TOOL_HIDE_SECONDS = 3
-- The game's use call reports success even when it refuses a drink (e.g. Wiggenweld at full
-- health), so a drink is confirmed by the item's count dropping. From the gulp onwards the count
-- is checked every DRINK_CHECK_INTERVAL seconds; no drop by DRINK_CONFIRM_SECONDS means refused.
local DRINK_CHECK_INTERVAL = 0.25
local DRINK_CONFIRM_SECONDS = 3
-- Seconds after a Wiggenweld drink starts before another can be drunk, so a fresh bottle
-- cannot stack a second heal while the first is still filling the health bar.
local WIGGENWELD_COOLDOWN = 3
local EFFECT = "NiagaraSystem /Game/VFX/UI/Mission_EntryPoint_Beacon/VFX_NS_MissionEntryPoint_Location.VFX_NS_MissionEntryPoint_Location"
local EFFECT2 = "NiagaraSystem /Game/VFX/Particles/Magic/Accio/VFX_NS_AccioTarget.VFX_NS_AccioTarget" --"NiagaraSystem /Game/VFX/Niagara/MechanicsFX/Transfiguration/VFX_NS_Swirl_Expand_Flat.VFX_NS_Swirl_Expand_Flat" --"NiagaraSystem /Game/VFX/Particles/Magic/CuresedState/VFX_NS_Cursed_Pro.VFX_NS_Cursed_Pro"
local APPARITION_EFFECT = "NiagaraSystem /Game/VFX/Particles/Magic/Apparition/VFX_NS_Apparate_Universal_Master_Lg_In_V1.VFX_NS_Apparate_Universal_Master_Lg_In_V1"
local APPEAR_DELAY, APPEAR_SECONDS, APPEAR_MIN_SCALE = 0.18, 0.5, 0.02
local APPARITION_SCALE, APPARITION_SECONDS = 0.25, 4.0
-- Hand-tuned liquid colors, in linear RGB (not 0-255 or sRGB/hex).
-- Edit color = {red, green, blue}, then Reset Scripts and reopen the wheel.
-- brightness controls emissive amount for the four colored liquids.
-- Invisibility keeps its preferred default liquid material.
local POTION_COLORS = {
	Edurus       = {color = {0.7, 0.74, 0.8},    brightness = 5},
	Maxima       = {color = {0.8, 0.02, 0.035},  brightness = 5},
	Focus        = {color = {0.025, 0.2, 0.95},  brightness = 5},
	Thunderbrew  = {color = {0.42, 0.025, 0.85}, brightness = 5},
}
local LIQUID_MATERIAL = "MaterialInstanceConstant /Game/VFX/MasterMaterials/Base_Mat/MaterialInstance/VFX_MM_LiquidBottle_P3D_Adv_maxima.VFX_MM_LiquidBottle_P3D_Adv_maxima"
-- Keep the particle shader's surface cutoff outside our static liquid meshes.
-- The inherited Slosh Height (8.5) clipped them away; this preserves the approved shader.
local STATIC_LIQUID_SLOSH_HEIGHT = -1000000
local POTIONS = "/Game/VFX/Meshes/Potions/"
local PLANTS = "/Game/RiggedObjects/Characters/Creatures/Plants/"
-- recipeLock/pickupLock are the stock wheel's ItemRecipeLocks/ItemPickupLocks entries.
local items = {
	{name = "Edurus", id = "Edurus", mesh = POTIONS .. "SM_Edurus_Bottle", liquid = POTIONS .. "SM_Edurus_Liquid",
		scale = 0.4865238424326192, pivot = {X = 0, Y = 0, Z = -4.5625},
		recipeLock = "Potion_Edurus", pickupLock = "SancWheel_Edurus"},
	{name = "Maxima", id = "Maxima", mesh = POTIONS .. "SM_Maxima_Bottle", liquid = POTIONS .. "SM_Maxima_Liquid",
		scale = 0.5057471264367817, pivot = {X = 0, Y = 0, Z = -6.1875},
		recipeLock = "Potion_Maxima", pickupLock = "SancWheel_Maxima"},
	{name = "Focus", id = "AMFillPotion", mesh = POTIONS .. "SM_Focus_Bottle", liquid = POTIONS .. "SM_Focus_Liquid",
		scale = 0.4228228228228228, pivot = {X = 0, Y = 0, Z = -6.9921875},
		recipeLock = "Potion_AMFillPotion", pickupLock = "SancWheel_AMFillPotion"},
	{name = "Thunderbrew", id = "AutoDamagePotion", mesh = POTIONS .. "SM_Thunderbrew_Bottle", liquid = POTIONS .. "SM_Thunderbrew_Liquid",
		scale = 0.5053840631730079, pivot = {X = 0, Y = 0, Z = -5.0703125},
		recipeLock = "Potion_AutoDamagePotion", pickupLock = "SancWheel_AutoDamagePotion"},
	{name = "Invisibility", id = "InvisibilityPotion", mesh = POTIONS .. "SM_Invisibility_Bottle", liquid = POTIONS .. "SM_Invisibility_Liquid",
		scale = 0.4326982175783651, pivot = {X = 0, Y = 0, Z = -7.2265625},
		recipeLock = "Potion_InvisibilityPotion", pickupLock = "SancWheel_InvisibilityPotion"},
	{name = "Mandrake", id = "Mandrake_Byproduct", mesh = PLANTS .. "Mandrake/SK_MandrakePlant", skeletal = true,
		scale = 0.23605304974941938, pivot = {X = 1.0625, Y = -3.0625, Z = 3.3046875},
		recipeLock = "Plant_Mandrake", pickupLock = "SancWheel_Mandrake_Byproduct"},
	{name = "Chomping Cabbage", id = "ChompingCabbage_Byproduct", mesh = PLANTS .. "ChompingCabbage/SK_ChompingCabbage_LOD0", skeletal = true,
		scale = 0.235, pivot = {X = 1.3125, Y = -0.53125, Z = 16.4375},
		recipeLock = "Plant_ChompingCabbage", pickupLock = "SancWheel_ChompingCabbage_Byproduct"},
	{name = "Venomous Tentacula", id = "VenomousTentacula_Byproduct", mesh = "/Game/Gameplay/Nurturing/Herbology/Herbs/Meshes/SM_VenomousTentacula_Stage4",
		scale = 0.04170616113744076, pivot = {X = 6.21875, Y = 14.28125, Z = 126.5234375},
		recipeLock = "Plant_VenomousTentacula", pickupLock = "SancWheel_VenomousTentacula_Byproduct"},
}
-- Locked gadgets show the goblin chest lock in place of their model. The pivot is the
-- mesh's bounds centre; scale matches the bottles' height. LOCK_YAW (radians) turns
-- the lock about its centre if its face points away from the viewer.
local LOCK_MESH = "/Game/RiggedObjects/Props/Furniture/SM_Goblin_Chest_Lock"
local LOCK_SCALE = 0.32
local LOCK_PIVOT = {X = 0.035, Y = 0.366, Z = -4.59}
local LOCK_YAW = 0
-- The stock wheel's standalone controls: top, right, bottom, left. Mounts are summoned when
-- gripped; Felix Felicis is held and drunk like the other potions and is used by inventory
-- name, since it is not a quick-wheel item. The broom and flying mount show the Nightdancer
-- and Hippogriff models whichever is slotted. Scales/pivots/yaws are user-approved.
local MOUNTS = "/Game/RiggedObjects/Characters/Creatures/"
local diamondItems = {
	{name = "Broom", mesh = "/Game/RiggedObjects/Props/FlyingBroom/NightDancerBroom/SK_NightDancerBroom", skeletal = true,
		scale = 0.083, pivot = {X = -0.15625, Y = -21.4375, Z = 5.296875}, yaw = math.pi / 2,
		animation = "AnimSequence /Game/Animation/Props/Broom/Broom_Hover_Idle_anm.Broom_Hover_Idle_anm",
		-- Cloth simulates at full size whatever the model's scale; pin the ropes to the mesh.
		pinCloth = true,
		-- Without the avatar state CanUseBroom reports progression; with it, whether it works here.
		summon = "castUpBroom", unlocked = function(library) return library:CanUseBroom(false) end,
		usableNow = function(library) return library:CanUseBroom(true) end,
		iconOffset = {right = 0, down = 0}},
	{name = "Hippogriff", mesh = MOUNTS .. "Hippogriff/SK_Hippogriff", skeletal = true,
		scale = 0.043588665601614396, pivot = {X = 1.25, Y = -31.40625, Z = 129.03125}, yaw = math.pi / 2,
		animation = "AnimSequence /Game/Animation/Creatures/Horses/Hippogriff/HIPP_BM_Standing_anm.HIPP_BM_Standing_anm",
		windSlots = {4, 5, 6}, -- Body, wing and tail feather materials.
		summon = "castUpHippogriff", unlocked = function(library) return library:CanUseHippogriff() end,
		iconOffset = {right = -2, down = 0}},
	{name = "Felix Felicis", id = "FelixFelicis", direct = true,
		mesh = POTIONS .. "SM_Felix_Felicis_Bottle", liquid = POTIONS .. "SM_Felix_Felicis_Liquid",
		scale = 0.3902793122573489, pivot = {X = 0, Y = 0, Z = -8.578125},
		recipeLock = "Potion_FelixFelicis", pickupLock = "SancWheel_FelixFelicis"},
	{name = "Graphorn", mesh = MOUNTS .. "Graphorn/SK_Graphorn", skeletal = true,
		scale = 0.027434450239337004, pivot = {X = 0, Y = -133.5, Z = 173.40625}, yaw = math.pi * 3 / 2,
		animation = "AnimSequence /Game/Animation/Creatures/Graphorn/GRAP_BM_Standing_anm.GRAP_BM_Standing_anm",
		summon = "castUpGraphorn", unlocked = function(library) return library:CanUseGraphorn() end,
		iconOffset = {right = 5, down = 0}},
}
local function makeLockItems(list)
	local locks = {}
	for index, item in ipairs(list) do
		locks[index] = {name = item.name .. " lock", mesh = LOCK_MESH, skeletal = true,
			scale = LOCK_SCALE, pivot = LOCK_PIVOT, yaw = LOCK_YAW}
	end
	return locks
end
-- Wiggenweld sits in the ring's centre. It is not a stock-wheel item: selecting it sets the
-- game's selection to None (its HUD then shows an empty icon), and while None is selected a
-- left grip copies Wiggenweld. Like the game's own potion tool it uses the health bottle with
-- the animated Niagara liquid; having no liquid mesh, it is marked as a potion explicitly.
local wiggenweld = {name = "Wiggenweld", id = "WoundCleaning", direct = true, potion = true, clearsSelection = true,
	mesh = POTIONS .. "SM_Health_Bottle", cooldown = WIGGENWELD_COOLDOWN,
	liquidEffect = "NiagaraSystem /Game/VFX/Niagara/Potions/VFX_NS_LiquidBottle_Health.VFX_NS_LiquidBottle_Health",
	scale = 0.4467005133628845, pivot = {X = 0, Y = 0, Z = -7.6328125}}
local ringItems = {}
for index, item in ipairs(items) do ringItems[index] = item end
ringItems[#ringItems + 1] = wiggenweld
-- ringCount items go round the ring; any after them sit at its centre.
local layouts = {
	ring = {items = ringItems, locks = makeLockItems(ringItems), radius = RADIUS, ringCount = #items},
	diamond = {items = diamondItems, locks = makeLockItems(diamondItems), radius = DIAMOND_RADIUS, ringCount = #diamondItems},
}

-- Held potions are drunk at the mouth; anything else (plants) is thrown.
local function isPotion(item)
	return item.liquid ~= nil or item.potion == true
end

local actors = {}
local centers = {}
local lockedSlots = {}
local layout = nil -- The open display's entry in layouts.
local parentActor, parentRoot, effect, effect2 = nil, nil, nil, nil
local followActor, followRoot, followHmd = nil, nil, nil
local apparitionRoot, apparition, transition = nil, nil, nil
local apparitionElapsed, closing = 0, false
local displayPawn = nil
local initialized = false
local enabled = false
local gestureBased = false
---@type any, any, any
local activeActor, activeMesh, activePawn = nil, nil, nil
-- The gadget the held copy represents, seconds since its last thrust (nil if none),
-- and whether a drink is already queued for it.
local activeItem, thrustAge, useQueued = nil, nil, false
-- Seconds left to keep the game's drink tool hidden, and the tool hidden last.
local drinkToolTime, hiddenDrinkTool = nil, nil
-- The drink being confirmed: held actor, item, count before drinking, seconds since, next check.
local drinkCheck = nil
-- After a refused drink the held potion must leave the mouth zone before it can be tried again.
local awaitMouthExit = false
-- os.clock() time until which each item id with a cooldown cannot be drunk again.
local cooldownUntil = {}
local attachMesh = nil
---@type any
local selectionService = nil
local accessPawn, gadgetAvailable = nil, false
local availabilityResult = {}
local countDisplay = nil
local cachedCounts = nil
local countElapsed, countReadFailed = 0, false
local triggerWasPressed = true -- Require a release after reset, for either input.
local tapTime = nil -- When an unclassified trigger tap began (os.clock), until single/double is known.
local gripWasPressed = {[0] = true, [1] = true}
local consumeGrip = {[0] = false, [1] = false}
local leftChord, leftPressTime = false, nil -- Current left grip belongs to an LB+RB chord.
local leftAccessory = false -- Current left grip belongs to an accessory (e.g. a broom handle).
local pending = {}
local grips = {
	{hand = Handed.Left, button = XINPUT_GAMEPAD_LEFT_SHOULDER},
	{hand = Handed.Right, button = XINPUT_GAMEPAD_RIGHT_SHOULDER},
}

local function destroyActors(list)
	for _, actor in ipairs(list) do
		if uevrUtils.getValid(actor) ~= nil then
			actor:K2_DestroyActor()
		end
	end
end

local function destroyCounts(display)
	if display == nil then return end
	for _, text in ipairs(display.texts) do text:remove() end
	for _, image in ipairs(display.images) do image:remove() end
	for _, icon in ipairs(display.icons or {}) do icon:remove() end
	if display.component ~= nil then display.component:destroy() end
	if uevrUtils.getValid(display.owner) ~= nil and display.owner.K2_DestroyActor ~= nil then display.owner:K2_DestroyActor() end
end

local function parkCounts(display)
	if display == nil then return end
	local owner = uevrUtils.getValid(display.owner)
	local component = display.component and uevrUtils.getValid(display.component:getComponent())
	if owner ~= nil and component ~= nil and uevrUtils.getValid(owner.RootComponent) ~= nil then
		display.component:setVisibility(false)
		display.component:attachTo(owner.RootComponent)
		if component.AttachParent == owner.RootComponent then
			destroyCounts(cachedCounts)
			cachedCounts = display
			return
		end
	end
	destroyCounts(display)
end

local function destroyDisplay(list, parent, particle, particle2, follower, flourish, counts)
	destroyCounts(counts)
	destroyActors(list)
	if particle ~= nil then particle:destroy() end
	if particle2 ~= nil then particle2:destroy() end
	if flourish ~= nil then flourish:destroy() end
	if uevrUtils.getValid(parent) ~= nil then parent:K2_DestroyActor() end
	if uevrUtils.getValid(follower) ~= nil then follower:K2_DestroyActor() end
end

function M.getActor()
	return uevrUtils.getValid(parentActor)
end

function M.clearActiveMesh()
	local actor, mesh = activeActor, activeMesh
	activeActor, activeMesh, activePawn = nil, nil, nil
	activeItem, thrustAge, useQueued = nil, nil, false
	drinkCheck, awaitMouthExit = nil, false
	if actor == nil and mesh == nil then return end
	-- Only detach our own attachment; a feed can or wand may occupy the same hand.
	if mesh ~= nil then
		local current = attachments.getCurrentGrippedAttachmentData(Handed.Left)
		if current ~= nil and current.attachment == mesh then attachments.detachGripAttachments(Handed.Left) end
	end
	if uevrUtils.getValid(actor) ~= nil then actor:K2_DestroyActor() end
end

-- The game may reuse its potion tool, so show it again when the palette stops drinking:
-- stock-wheel drinks must keep their bottle.
local function restoreDrinkTool()
	drinkToolTime = nil
	local tool = uevrUtils.getValid(hiddenDrinkTool)
	hiddenDrinkTool = nil
	if tool ~= nil then tool:SetActorHiddenInGame(false) end
end

function M.setGestureBased(on)
	gestureBased = on == true
	if not gestureBased then
		M.clearActiveMesh()
		restoreDrinkTool()
	end
end

function M.setAttachMeshFunction(fn)
	attachMesh = type(fn) == "function" and uevrUtils.profiler:wrap("Palette: attach held item", fn) or nil
end

function M.close(keepCounts)
	if keepCounts == true then
		parkCounts(countDisplay)
		countDisplay = nil
	else
		destroyCounts(cachedCounts)
		cachedCounts = nil
	end
	destroyDisplay(actors, parentActor, effect, effect2, followActor, apparition, countDisplay)
	countDisplay = nil
	countElapsed, countReadFailed = 0, false
	actors = {}
	centers = {}
	lockedSlots = {}
	layout = nil
	parentActor, parentRoot, effect, effect2 = nil, nil, nil, nil
	followActor, followRoot, followHmd = nil, nil, nil
	apparitionRoot, apparition, transition = nil, nil, nil
	apparitionElapsed, closing = 0, false
	displayPawn = nil
end

function M.reset()
	selectionService = nil
	accessPawn, gadgetAvailable = nil, false
	pending = {}
	triggerWasPressed = true
	tapTime = nil
	gripWasPressed = {[0] = true, [1] = true}
	consumeGrip = {[0] = false, [1] = false}
	leftChord, leftPressTime = false, nil
	leftAccessory = false
	M.clearActiveMesh()
	restoreDrinkTool()
	M.close()
end

function M.setEnabled(on)
	on = on == true
	if enabled == on then return end
	enabled = on
	if enabled then
		triggerWasPressed = true
	else
		M.reset()
	end
end

local function getSelectionService()
	local service = uevrUtils.getValid(selectionService)
	if service ~= nil and service.ActorOwner == pawn then return service end
	selectionService = nil
	-- Read the pawn's own node instances. A cached class lookup goes stale when loading
	-- another character reloads the Blueprint class, hiding the service until a reset.
	local component = uevrUtils.getValid(pawn.BehaviorComp_Primary)
	if component == nil then return nil end
	for _, candidate in ipairs(component.NodeInstances or {}) do
		if uevrUtils.getValid(candidate) ~= nil and candidate:get_class():get_fname():to_string() == "BTS_Biped_TopLevel_C" then
			selectionService = candidate
			return candidate
		end
	end
end

local function hasGadgetAccess()
	accessPawn, gadgetAvailable = pawn, false
	if uevrUtils.getValid(pawn) == nil then return false end
	local service = getSelectionService()
	if service == nil then return false end
	-- Native scalar out parameters write to the supplied table's result field.
	availabilityResult.result = nil
	service:IsItemWheelAvailable(availabilityResult)
	gadgetAvailable = availabilityResult.result == true
	return gadgetAvailable
end

local function canSpawn()
	return uevrUtils.getValid(pawn) ~= nil and ui.isRemapDisabled() == false
		and not uevrUtils.isGamePaused() and not uevrUtils.isInCutscene()
end

function M.getActiveMesh()
	if not enabled or not gestureBased or (not TOGGLE_GRIP_FOR_ADJUSTMENTS and not gripWasPressed[Handed.Left])
		or activePawn ~= pawn or accessPawn ~= pawn or not gadgetAvailable or not canSpawn() then return nil end
	if uevrUtils.getValid(activeActor) == nil then return nil end
	return uevrUtils.getValid(activeMesh)
end

local function loadMesh(path, skeletal)
	local name = path:match("([^/]+)$")
	local className = skeletal and "SkeletalMesh" or "StaticMesh"
	local asset = uevrUtils.getValid(loadAsset(className .. " " .. path .. "." .. name))
	if asset == nil then return nil, "Could not load " .. path end
	return asset
end

local function configure(component)
	component:SetMobility(2)
	component:SetSimulatePhysics(false)
	component:SetCollisionEnabled(0, false)
	component:SetGenerateOverlapEvents(false)
	component:SetCastShadow(false)
	component:SetVisibility(true, true)
	component:SetHiddenInGame(false, true)
end

local function colorLiquid(component, item)
	local settings = POTION_COLORS[item.name]
	if settings == nil then return true end
	-- Load by asset path; never probe the global UObject hierarchy on a miss.
	local source = uevrUtils.getValid(loadAsset(LIQUID_MATERIAL))
	if source == nil then return false, "Could not load liquid material for " .. item.name end
	-- Always clone a constant material: supplying an existing MID can reuse it,
	-- causing multiple potions to share the last color set on that instance.
	local material = uevrUtils.getValid(component:CreateDynamicMaterialInstance(0, source,
		uevrUtils.fname_from_string("Palette" .. item.name .. "Liquid")))
	if material == nil then return false, "Could not create liquid material for " .. item.name end
	local rgb, brightness = settings.color, settings.brightness
	local color = uevrUtils.color_from_rgba(rgb[1], rgb[2], rgb[3], 1)
	material:SetVectorParameterValue(uevrUtils.fname_from_string("Tint"), color)
	material:SetVectorParameterValue(uevrUtils.fname_from_string("Subsurface Color"), color)
	material:SetScalarParameterValue(uevrUtils.fname_from_string("Emissive Amount"), brightness)
	material:SetScalarParameterValue(uevrUtils.fname_from_string("Slosh Height"), STATIC_LIQUID_SLOSH_HEIGHT)
	return true
end

local function worldTransform(component, transform)
	local native = uevrUtils.get_transform(transform.Translation, nil, transform.Scale3D)
	if native == nil then return false, "Could not create a native placement transform" end
	native.Rotation.X, native.Rotation.Y = transform.Rotation.X, transform.Rotation.Y
	native.Rotation.Z, native.Rotation.W = transform.Rotation.Z, transform.Rotation.W
	-- This setter is void; nil is a normal return, not a placement failure.
	component:K2_SetWorldTransform(native, false, reusable_hit_result, true)
	return true
end

-- Attach a potion's animated Niagara liquid at the bottle's origin, as the game's potion tool
-- does. The effect inherits the bottle's scale and belongs to the bottle's actor, so it is
-- destroyed with it (a live MCP preview confirmed both).
local function attachLiquidEffect(component, item)
	local system = uevrUtils.getValid(loadAsset(item.liquidEffect))
	if system == nil then return false, "Could not load the liquid effect for " .. item.name end
	local library = uevrUtils.getValid(uevrUtils.find_default_instance("Class /Script/Niagara.NiagaraFunctionLibrary"))
	if library == nil then return false, "Niagara function library is unavailable" end
	-- KeepRelativeOffset (0), keep the effect, auto-activate, no pooling, no pre-cull check.
	local effect = library:SpawnSystemAttached(system, component, uevrUtils.fname_from_string("None"),
		uevrUtils.vector(0, 0, 0), uevrUtils.rotator(0, 0, 0), 0, false, true, 0, false)
	if uevrUtils.getValid(effect) == nil then return false, "Could not attach the liquid effect for " .. item.name end
	return true
end

-- Scale the feather wind (a world-space material offset) to the model's size.
local function scaleWind(component, item)
	for _, slot in ipairs(item.windSlots) do
		local material = uevrUtils.getValid(component:CreateDynamicMaterialInstance(slot, component:GetMaterial(slot),
			uevrUtils.fname_from_string("PaletteWind" .. slot)))
		if material == nil then return false, "Could not create the wind material for " .. item.name end
		for _, parameter in ipairs(WIND_PARAMETERS) do
			local name = uevrUtils.fname_from_string(parameter)
			local value = material:K2_GetScalarParameterValue(name)
			if type(value) == "number" then material:SetScalarParameterValue(name, value * item.scale) end
		end
	end
	return true
end

local function attach(component, parent)
	-- Keep world transform, including the model's tuned scale and pivot offset.
	local attached = component:K2_AttachToComponent(parent, uevrUtils.fname_from_string("None"), 1, 1, 1, false)
	if not attached then return false, "Could not attach a palette component" end
	return true
end

local function createParticle(root, options)
	local particle = particles.new(options)
	if particle == nil then return nil, "Could not create the palette particle effect" end
	if not particle:isValid() or not particle:attachTo(root) then
		particle:destroy()
		return nil, "Could not attach the palette particle effect"
	end
	local component = particle:getParticleComponent()
	if component ~= nil then
		component:SetCollisionEnabled(0, false)
		component:SetGenerateOverlapEvents(false)
	end
	return particle
end

local function createEffect(root)
	return createParticle(root, {
		particleSystemAsset = EFFECT,
		scale = {.14, .14, .14},
		rotation = {90, 0, 0},
		location = {5, 0, 0},
		autoActivate = true, collisionEnabled = 0, quiet = true,
		restoreEmittersOnDestroy = false,
	})
end

local function createEffect2(root)
	return createParticle(root, {
		particleSystemAsset = EFFECT2,
		scale = {.22, .22, .22},
		rotation = {90, 0, 0},
		location = {10, 0, 0},
		autoActivate = true, collisionEnabled = 0, quiet = true,
		restoreEmittersOnDestroy = false,
		-- loopStart = 0,
		-- loopEnd = 0.8,
		emitterOverrides = {VFX_NE_PointLight = false, VFX_NE_SimpleSpriteBurst = false},
	})
end

local function beginTransition(isClosing)
	local root = uevrUtils.getValid(parentRoot)
	if #actors == 0 or root == nil or (isClosing and closing) then return end
	closing = isClosing
	if apparition ~= nil then apparition:destroy(); apparition = nil end
	apparitionElapsed = 0
	local ok, particle, reason = pcall(createParticle, apparitionRoot, {
		particleSystemAsset = APPARITION_EFFECT,
		scale = {APPARITION_SCALE, APPARITION_SCALE, APPARITION_SCALE},
		rotation = {0, 90, 0},
		location = {-10, 0, 0},
		autoActivate = true, collisionEnabled = 0, quiet = true,
		restoreEmittersOnDestroy = false,
	})
	if ok then apparition = particle end
	if not ok or particle == nil then
		print("Palette: apparition unavailable: " .. tostring(ok and reason or particle))
	end
	audio.playSwirlSound(root, root:K2_GetComponentLocation())
	local pose = root:K2_GetComponentToWorld()
	local scale = pose.Scale3D
	transition = {elapsed = 0, from = {X = scale.X, Y = scale.Y, Z = scale.Z},
		target = isClosing and APPEAR_MIN_SCALE or 1}
	if not isClosing then
		transition.from = {X = APPEAR_MIN_SCALE, Y = APPEAR_MIN_SCALE, Z = APPEAR_MIN_SCALE}
		root:SetRelativeScale3D(uevrUtils.vector(APPEAR_MIN_SCALE, APPEAR_MIN_SCALE, APPEAR_MIN_SCALE))
		root:SetVisibility(false, true)
	end
end

local function tickTransition(delta)
	if type(delta) ~= "number" or delta <= 0 or delta ~= delta or delta == math.huge then return end
	apparitionElapsed = apparitionElapsed + delta
	local root = transition ~= nil and uevrUtils.getValid(parentRoot) or nil
	if transition ~= nil and root ~= nil then
		transition.elapsed = transition.elapsed + delta
		local t = math.max(0, math.min(1, (transition.elapsed - APPEAR_DELAY) / APPEAR_SECONDS))
		local amount = t * t * (3 - 2 * t)
		local from, target = transition.from, transition.target
		root:SetRelativeScale3D(uevrUtils.vector(from.X + (target - from.X) * amount,
			from.Y + (target - from.Y) * amount, from.Z + (target - from.Z) * amount))
		if not closing and not transition.revealed and transition.elapsed >= APPEAR_DELAY then
			root:SetVisibility(true, true)
			transition.revealed = true
		end
		if t >= 1 then
			if closing then root:SetVisibility(false, true) end
			transition = nil
		end
	end
	if apparition ~= nil and apparitionElapsed >= APPARITION_SECONDS then
		apparition:destroy(); apparition = nil
	end
	if closing and transition == nil and apparition == nil then M.close(true) end
end

local function createItem(item, center, yaw, created, root)
	local actorClass = item.skeletal and "Class /Script/Engine.SkeletalMeshActor" or "Class /Script/Engine.StaticMeshActor"
	-- Child actors attach only to the palette's world-space parent.
	local actor = uevrUtils.spawn_actor_of_class(actorClass, uevrUtils.get_transform(center), 1, nil)
	if actor == nil then return false, "Could not create " .. item.name end
	created[#created + 1] = actor
	actor:SetActorEnableCollision(false)
	local component = item.skeletal and actor.SkeletalMeshComponent or actor.StaticMeshComponent
	if component == nil then return false, "Missing mesh component for " .. item.name end
	configure(component)
	local mesh, err = loadMesh(item.mesh, item.skeletal)
	if mesh == nil then return false, err end
	if item.skeletal then
		component:SetSkeletalMesh(mesh, true)
		component:SetForcedLOD(1)
		if item.animation ~= nil then
			local animation = uevrUtils.getValid(loadAsset(item.animation))
			if animation == nil then return false, "Could not load the animation for " .. item.name end
			component:PlayAnimation(animation, true)
		end
		if item.pinCloth then component:SetClothMaxDistanceScale(0) end
	else
		component:SetStaticMesh(mesh)
	end

	-- Compensate the mesh pivot so the model's centre lies on the ring.
	-- Unreal positive yaw turns clockwise from above; subtract 90 degrees.
	local angle, scale, pivot = yaw + math.pi / 2 + (item.yaw or 0), item.scale, item.pivot
	local c, s = math.cos(angle), math.sin(angle)
	local transform = {
		Rotation = {X = 0, Y = 0, Z = math.sin(angle / 2), W = math.cos(angle / 2)},
		Translation = {
			X = center.X - scale * (c * pivot.X - s * pivot.Y),
			Y = center.Y - scale * (s * pivot.X + c * pivot.Y),
			Z = center.Z - scale * pivot.Z,
		},
		Scale3D = {X = scale, Y = scale, Z = scale},
	}
	local placed
	placed, err = worldTransform(component, transform)
	if not placed then return false, err end
	if item.windSlots ~= nil then
		placed, err = scaleWind(component, item)
		if not placed then return false, err end
	end
	if root ~= nil then
		placed, err = attach(component, root)
		if not placed then return false, err end
	end

	if item.liquid ~= nil then
		local liquid = uevrUtils.create_component_of_class("Class /Script/Engine.StaticMeshComponent", false, uevrUtils.get_transform(), false, actor)
		if liquid == nil then return false, "Could not create liquid for " .. item.name end
		configure(liquid)
		local liquidMesh
		liquidMesh, err = loadMesh(item.liquid, false)
		if liquidMesh == nil then return false, err end
		liquid:SetStaticMesh(liquidMesh)
		local colored
		colored, err = colorLiquid(liquid, item)
		if not colored then return false, err end
		placed, err = worldTransform(liquid, transform)
		if not placed then return false, err end
		placed, err = attach(liquid, component)
		if not placed then return false, err end
	end
	if item.liquidEffect ~= nil then
		placed, err = attachLiquidEffect(component, item)
		if not placed then return false, err end
	end
	return true
end

-- FNames do not change during a game session. Build each inventory/lock name once
-- instead of on every count refresh.
local fnames = {}
local function cachedFName(text)
	local name = fnames[text]
	if name == nil then
		name = uevrUtils.fname_from_string(text)
		fnames[text] = name
	end
	return name
end

local function getInventory()
	local inventory = uevrUtils.getValid(uevrUtils.find_default_instance("Class /Script/Phoenix.InventoryManagerInterface"))
	if inventory == nil then return nil, "Inventory manager is unavailable" end
	return inventory
end

local function readCount(inventory, character, item)
	local count = inventory:GetCount(character, cachedFName(item.id), 0, 0, cachedFName("ActorBackpack"), cachedFName("None"))
	if type(count) ~= "number" or count < 0 or count ~= count or count == math.huge then
		return nil, "Could not read inventory count for " .. item.name
	end
	return math.floor(count)
end

-- The player's current count of one item, or nil when it cannot be read.
local function currentCount(item)
	local inventory = getInventory()
	if inventory == nil then return nil end
	return readCount(inventory, pawn:GetCharacterID(), item)
end

-- Copies the game's selected gadget, or a given diamond item (Felix Felicis), into the left hand.
function M.createSelectedMesh(chosen)
	if not enabled or not gestureBased or (not TOGGLE_GRIP_FOR_ADJUSTMENTS and not gripWasPressed[Handed.Left])
		or not canSpawn() or not hasGadgetAccess() then return false end
	-- No copy while the wheel is open. A successful wheel selection starts closing
	-- before this runs, so gripping an item still copies it immediately.
	if #actors > 0 and not closing then return false end
	if attachMesh == nil then return false, "Palette attachment handler is unavailable" end
	if uevrUtils.getValid(controllers.getController(Handed.Left, true)) == nil then
		return false, "Left hand tracking is unavailable"
	end
	local item = chosen
	if item == nil then
		local defaultManager = uevrUtils.find_default_instance("Class /Script/Phoenix.QuickActionManager")
		local manager = defaultManager and uevrUtils.getValid(defaultManager:Get())
		if manager == nil then return false, "QuickActionManager is unavailable" end
		local selected = manager:GetQuickWheelItem()
		local id = type(selected) == "string" and selected or (selected and selected:to_string())
		for _, candidate in ipairs(items) do
			if candidate.id == id then item = candidate; break end
		end
		-- Nothing selected means the palette's Wiggenweld was chosen.
		if item == nil and id == "None" then item = wiggenweld end
		if item == nil then return false, "No palette mesh for the selected gadget" end
	end
	-- An out-of-stock gadget stays selected but is not put in the hand.
	local inventory, inventoryError = getInventory()
	if inventory == nil then return false, inventoryError end
	local count, countError = readCount(inventory, pawn:GetCharacterID(), item)
	if count == nil then return false, countError end
	if count == 0 then return false end
	local created = {}
	local ok, built, reason = pcall(createItem, item, {X = 0, Y = 0, Z = 0}, -math.pi / 2, created, nil)
	if not ok or not built then
		destroyActors(created)
		return false, tostring(ok and reason or built)
	end
	M.clearActiveMesh()
	activeActor, activePawn = created[1], pawn
	activeMesh = activeActor.RootComponent
	-- The main.lua grip callback supplies this mesh through the same attachment
	-- path as the creature feed can. Never update its hand position in Lua.
	local attached, result = pcall(function()
		if not attachMesh(activeMesh) then return false end
		local data = attachments.getCurrentGrippedAttachmentData(Handed.Left)
		return data ~= nil and data.attachment == activeMesh
			and (data.state ~= nil or uevrUtils.getValid(activeMesh.AttachParent) ~= nil)
	end)
	if not attached or not result then
		M.clearActiveMesh()
		return false, attached and "Could not attach the gadget copy to the left hand" or tostring(result)
	end
	activeItem = item
	if not isPotion(item) then
		-- The first call ends any leftover cooldown or unfinished punch; the second ends
		-- the cooldown that finishing a punch starts. Both reset the last hand position.
		gestures.detectGesture(gestures.Gesture.PUNCH, PUNCH_PRIME_DELTA, Handed.Left)
		gestures.detectGesture(gestures.Gesture.PUNCH, PUNCH_PRIME_DELTA, Handed.Left)
	end
	return true
end

local function functionLibrary()
	return uevrUtils.getValid(uevrUtils.find_default_instance("Class /Script/Phoenix.UIBlueprintFunctionLibrary"))
end

-- Unlocked: progression allows the mount (otherwise it shows the lock).
local function mountUnlocked(item, library)
	return library ~= nil and item.unlocked(library) == true
end

-- Ready: unlocked and summonable here and now (otherwise it shows the no-mount icon).
local function mountReady(item, library)
	return mountUnlocked(item, library) and spells.canMountNow()
		and (item.usableNow == nil or item.usableNow(library) == true)
end

-- Like the stock wheel, an item is available once either its recipe or its pickup lock
-- is open. Without lock data every model is shown; stock confirmation still rejects
-- a locked selection. Mounts show a lock until progression unlocks them.
local function readLocks(list)
	local locked = {}
	local manager = uevrUtils.getValid(uevrUtils.find_default_instance("Class /Script/Phoenix.LockManagerInterface"))
	if manager == nil then print("Palette: lock manager is unavailable; showing all items") end
	local library = nil
	for index, item in ipairs(list) do
		if item.summon ~= nil then
			library = library or functionLibrary()
			locked[index] = not mountUnlocked(item, library)
		elseif manager ~= nil and item.recipeLock ~= nil then
			locked[index] = manager:IsLocked(cachedFName(item.recipeLock)) == true
				and manager:IsLocked(cachedFName(item.pickupLock)) == true
		end
	end
	return locked
end

-- Unlocked mounts that cannot be summoned at the moment, indexed like the list.
local function readMountBlocked(list, locked)
	local blocked = {}
	local library = nil
	for index, item in ipairs(list) do
		if item.summon ~= nil and not locked[index] then
			library = library or functionLibrary()
			blocked[index] = not mountReady(item, library)
		end
	end
	return blocked
end

-- Counts are indexed like the list; summoned mounts have no inventory count.
local function readCounts(list)
	local inventory, reason = getInventory()
	if inventory == nil then return nil, reason end
	local character = pawn:GetCharacterID()
	local counts = {}
	for index, item in ipairs(list) do
		if item.summon == nil then
			local count
			count, reason = readCount(inventory, character, item)
			if count == nil then return nil, reason end
			counts[index] = tostring(count)
		end
	end
	return counts
end

-- Each label slot shows the count of the list item display.slots[slot].
local function updateCounts(display)
	local counts, reason = readCounts(display.layout.items)
	if counts == nil then return false, reason end
	for slot, text in ipairs(display.texts) do
		local value = counts[display.slots[slot]]
		if display.values[slot] ~= value then
			text:setText(value)
			display.values[slot] = value
		end
	end
	return true
end

local function buildCounts(root, positions, display)
	local list = display.layout.items
	local counts, reason = readCounts(list)
	if counts == nil then return false, reason end
	local host = widget.createHostWidget()
	if host == nil then return false, "Could not create the item count widget" end
	local backgroundTexture = uevrUtils.getValid(loadAsset(COUNT_BACKGROUND))
	if backgroundTexture == nil then return false, "Could not load the item count background" end
	for index, center in ipairs(positions) do
		-- Only items with an inventory count get a label; slot maps it back to the item.
		if counts[index] ~= nil then
			local slot = #display.slots + 1
			display.slots[slot] = index
			local offset = uevrUtils.vector2D((center.Y + COUNT_OFFSET_RIGHT) / COUNT_SCALE, (-center.Z + COUNT_OFFSET_DOWN) / COUNT_SCALE)
			local image = widget.Image.new(COUNT_BACKGROUND_SIZE)
			display.images[slot] = image
			-- Image:addToWidget accepts its loaded texture directly. Avoid importing a
			-- PNG copy of the game's asset through Image:setTexture.
			image.texture = backgroundTexture
			if not image:addToWidget(host, {align = widget.Image.ALIGN.CENTER, offset = offset, zOrder = 998}) or image.slot == nil then
				return false, "Could not add an item count background to the widget"
			end
			-- Initialize the real count before adding the TextBlock: one SetText bridge
			-- call per label, instead of writing an empty string and then the count.
			local text = widget.Text.new(counts[index])
			display.texts[slot] = text
			display.values[slot] = counts[index]
			text:setFontSize(COUNT_FONT_SIZE)
			text:setFont(COUNT_FONT, "Body")
			text:setColor(COUNT_COLOR)
			if not text:addToWidget(host, {align = widget.Text.ALIGN.CENTER, offset = offset, zOrder = 999}) then
				return false, "Could not add an item count to the widget"
			end
		elseif list[index].summon ~= nil then
			-- Mounts have no count; their no-mount icon starts visible and is set after building.
			local iconTexture = uevrUtils.getValid(loadAsset(NO_MOUNT_ICON))
			if iconTexture == nil then return false, "Could not load the no-mount icon" end
			local icon = widget.Image.new(NO_MOUNT_ICON_SIZE)
			local slot = #display.icons + 1
			display.icons[slot] = icon
			display.iconSlots[slot] = index
			icon.texture = iconTexture
			local shift = list[index].iconOffset or {right = 0, down = 0}
			local offset = uevrUtils.vector2D((center.Y + shift.right) / COUNT_SCALE, (-center.Z + shift.down) / COUNT_SCALE)
			if not icon:addToWidget(host, {align = widget.Image.ALIGN.CENTER, offset = offset, zOrder = 999}) or icon.slot == nil then
				return false, "Could not add a no-mount icon to the widget"
			end
		end
	end
	-- Give the cached component its own owner so destroying a ring cannot destroy it.
	display.owner = uevrUtils.spawn_actor_of_class("Class /Script/Engine.Actor", uevrUtils.get_transform(), 1, nil)
	if display.owner == nil then return false, "Could not create the item count owner" end
	local ownerRoot = uevrUtils.create_component_of_class("Class /Script/Engine.SceneComponent", false, uevrUtils.get_transform(), false, display.owner)
	if ownerRoot == nil or display.owner.RootComponent ~= ownerRoot then
		return false, "Could not create the item count owner root"
	end
	ownerRoot:SetMobility(2)
	display.owner:SetActorEnableCollision(false)
	display.host, display.pawn = host, pawn
	-- Apply depth directly in ring space. Keep the right/down offsets and scale
	-- independent so depth tuning is visible instead of cancelling its projection.
	display.component = widgetComponent.new({
		widget = host, drawSize = {COUNT_DRAW_SIZE, COUNT_DRAW_SIZE}, twoSided = true,
		location = {-COUNT_OFFSET_TOWARD_VIEWER, 0, 0}, rotation = {0, 180, 0},
		scale = {COUNT_SCALE, COUNT_SCALE, COUNT_SCALE},
		parent = display.owner, manualAttachment = true, useExposure = true, exposure = -1,
	})
	local wc = display.component
	if wc == nil then return false, "Could not create the 3D item count component" end
	wc:attachTo(root)
	local component = wc:getComponent()
	if component == nil or component.AttachParent ~= root then return false, "Could not attach the item counts to the palette" end
	component:SetCollisionEnabled(0, false)
	component:SetGenerateOverlapEvents(false)
	return true
end

local function reuseCounts(root, display, cached)
	for key, value in pairs(cached) do display[key] = value end
	display.component:attachTo(root)
	if display.component:getComponent().AttachParent ~= root then
		return false, "Could not reattach the cached item counts"
	end
	local updated, reason = updateCounts(display)
	if not updated then return false, reason end
	display.component:setVisibility(true)
	return true
end

-- Locked items hide their count and badge, like the stock wheel. Cached displays keep
-- their last state, so only changed slots are written when a reopen follows an unlock.
local function showCountSlots(display, locked)
	display.hidden = display.hidden or {}
	for slot, text in ipairs(display.texts) do
		local hide = locked[display.slots[slot]] == true
		if (display.hidden[slot] == true) ~= hide then -- New labels and badges start visible.
			local visibility = hide and 1 or 0 -- ESlateVisibility Collapsed / Visible
			if text.textBlock ~= nil then text.textBlock:SetVisibility(visibility) end
			local image = display.images[slot]
			if image ~= nil and image.image ~= nil then image.image:SetVisibility(visibility) end
			display.hidden[slot] = hide
		end
	end
end

-- Show the no-mount icon only over mounts that cannot be summoned now; write only changes.
local function showNoMountIcons(display, blocked)
	display.iconHidden = display.iconHidden or {}
	for slot, icon in ipairs(display.icons) do
		local hide = blocked[display.iconSlots[slot]] ~= true
		if display.iconHidden[slot] ~= hide then -- New icons start visible.
			if icon.image ~= nil then icon.image:SetVisibility(hide and 1 or 0) end -- Collapsed / Visible
			display.iconHidden[slot] = hide
		end
	end
end

-- The numbers that are displayed on the palette to show how many are available
local function createCounts(root, positions, display)
	-- A reopen can arrive while the previous four-second apparition is still
	-- finishing. Borrow its counts now instead of waiting for final destruction.
	if closing and displayPawn == pawn and countDisplay ~= nil then
		parkCounts(countDisplay)
		countDisplay = nil
	end
	if cachedCounts ~= nil then
		local cached = cachedCounts
		cachedCounts = nil
		-- The cache holds one layout's labels; another layout builds its own.
		if cached.pawn == pawn and cached.layout == display.layout and uevrUtils.getValid(cached.owner) ~= nil
			and uevrUtils.getValid(cached.host) ~= nil
			and uevrUtils.getValid(cached.component:getComponent()) ~= nil then
			return reuseCounts(root, display, cached)
		end
		destroyCounts(cached)
	end
	return buildCounts(root, positions, display)
end

-- Opens a layout: the eight-gadget ring by default, or layouts.diamond.
function M.show(shown)
	shown = shown or layouts.ring
	if not canSpawn() or not hasGadgetAccess() then return false end
	local left = uevrUtils.getValid(controllers.getController(Handed.Left, true))
	local hmd = uevrUtils.getValid(controllers.getController(2, true))
	local hand = controllers.getControllerLocation(Handed.Left)
	if left == nil or hmd == nil or hand == nil then return false end

	local origin = {X = hand.X, Y = hand.Y, Z = hand.Z}
	local view = controllers.getControllerRotation(2) or controllers.getControllerRotation(Handed.Left)
	if view == nil then return false end
	local yaw = math.rad(view.Yaw)
	origin.X = origin.X + FORWARD_OFFSET * math.cos(yaw)
	origin.Y = origin.Y + FORWARD_OFFSET * math.sin(yaw)
	local list = shown.items
	local created, positions = {}, {}
	local locked = readLocks(list)
	local createdParent, createdRoot, createdEffect, createdEffect2
	local createdFollowActor, createdFollowRoot
	local createdApparitionRoot
	local createdCounts = {texts = {}, images = {}, values = {}, slots = {}, icons = {}, iconSlots = {}, layout = shown}
	local ok, built, err = pcall(function()
		createdParent = uevrUtils.spawn_actor_of_class("Class /Script/Engine.Actor", uevrUtils.get_transform(origin), 1, nil)
		if createdParent == nil then return false, "Could not create the palette parent" end
		createdParent:SetActorEnableCollision(false)
		-- Automatic attachment makes this the empty actor's root component.
		createdRoot = uevrUtils.create_component_of_class("Class /Script/Engine.SceneComponent",
			false, uevrUtils.get_transform(), false, createdParent)
		if createdRoot == nil or createdParent.RootComponent ~= createdRoot then
			return false, "Could not create the palette root"
		end
		createdRoot:SetMobility(2)
		local placed, reason = worldTransform(createdRoot, {
			Rotation = {X = 0, Y = 0, Z = math.sin(yaw / 2), W = math.cos(yaw / 2)},
			Translation = origin,
			Scale3D = {X = 1, Y = 1, Z = 1},
		})
		if not placed then return false, reason end

		-- The HMD's zero-offset child follows translation. Absolute world rotation
		-- and scale prevent the wheel's offset from rotating or scaling with the head.
		local identity = uevrUtils.get_transform()
		if identity == nil then return false, "Could not create the tracking transform" end
		createdFollowActor = uevrUtils.spawn_actor_of_class("Class /Script/Engine.Actor", identity, 1, nil)
		if createdFollowActor == nil then return false, "Could not create the translation anchor actor" end
		createdFollowActor:SetActorEnableCollision(false)
		createdFollowRoot = uevrUtils.create_component_of_class("Class /Script/Engine.SceneComponent",
			false, identity, false, createdFollowActor)
		if createdFollowRoot == nil or createdFollowActor.RootComponent ~= createdFollowRoot then
			return false, "Could not create the translation anchor"
		end
		createdFollowRoot:SetMobility(2)
		createdFollowRoot:SetAbsolute(false, true, true)
		if not createdFollowRoot:K2_AttachToComponent(hmd, uevrUtils.fname_from_string("None"), 0, 0, 0, false) then
			return false, "Could not attach the translation anchor to the HMD"
		end
		createdFollowRoot:K2_SetRelativeTransform(identity, false, reusable_hit_result, true)
		placed, reason = attach(createdRoot, createdFollowRoot)
		if not placed then return false, reason end
		-- An unscaled sibling keeps the apparition full-sized while the wheel grows/shrinks.
		createdApparitionRoot = uevrUtils.create_component_of_class("Class /Script/Engine.SceneComponent",
			true, identity, false, createdParent)
		if createdApparitionRoot == nil then return false, "Could not create the apparition anchor" end
		createdApparitionRoot:SetMobility(2)
		createdApparitionRoot:K2_SetWorldTransform(createdRoot:K2_GetComponentToWorld(), false, reusable_hit_result, true)
		placed, reason = attach(createdApparitionRoot, createdFollowRoot)
		if not placed then return false, reason end
		for index, item in ipairs(list) do
			-- A vertical plane facing the view at spawn: the first item at the top,
			-- then clockwise along the viewer's right and world up axes.
			local angle = (index - 1) * 2 * math.pi / shown.ringCount
			local radius = index <= shown.ringCount and shown.radius or 0
			local right = radius * math.sin(angle)
			local up = radius * math.cos(angle)
			local center = {
				X = origin.X - right * math.sin(yaw),
				Y = origin.Y + right * math.cos(yaw),
				Z = origin.Z + up,
			}
			local createdItem, reason = createItem(locked[index] and shown.locks[index] or item, center, yaw, created, createdRoot)
			if not createdItem then return false, reason end
			positions[index] = {X = 0, Y = right, Z = up}
		end
		local counted, countError = createCounts(createdRoot, positions, createdCounts)
		if not counted then return false, countError end
		showCountSlots(createdCounts, locked)
		showNoMountIcons(createdCounts, readMountBlocked(list, locked))
		local effectError
		createdEffect, effectError = createEffect(createdRoot)
		if createdEffect == nil then return false, effectError end
		createdEffect2, effectError = createEffect2(createdRoot)
		if createdEffect2 == nil then return false, effectError end
		return true
	end)
	if not ok or not built then
		destroyDisplay(created, createdParent, createdEffect, createdEffect2, createdFollowActor, nil, createdCounts)
		print("Palette: " .. tostring(ok and err or built))
		return false
	end
	-- Replace the previous ring only after the new one was built successfully.
	M.close()
	actors = created
	centers = positions
	lockedSlots = locked
	layout = shown
	parentActor, parentRoot, effect, effect2 = createdParent, createdRoot, createdEffect, createdEffect2
	followActor, followRoot, followHmd = createdFollowActor, createdFollowRoot, hmd
	apparitionRoot = createdApparitionRoot
	countDisplay = createdCounts
	displayPawn = pawn
	beginTransition(false)
	print("Palette: placed " .. #list .. " models at the left hand")
	return true
end

local function nameString(value)
	if value == nil or type(value) == "string" then return value end
	return value:to_string()
end

local function createSelectionBackend(service)
	service:CreateItemWheel()
	local widget = uevrUtils.getValid(service.ItemWheelWidget)
	if widget == nil then return nil, "Could not create the selection backend" end
	widget:SetRenderOpacity(0)
	return widget
end

local function confirmSelection(widget)
	local confirm = widget["Confirm Item Selection"]
	if confirm == nil then return false, "Gadget confirmation function is unavailable" end
	confirm(widget)
	return true
end

local QUICK_ITEM_HUD = "WidgetBlueprintGeneratedClass /Game/UI/HUD/QuickAction/UI_BP_QuickItemHUD.UI_BP_QuickItemHUD_C"

-- Select nothing. The manager's setter does not notify the HUD, so the live quick-item
-- widget is told directly; it then shows its empty icon. A live MCP probe showed LB does
-- nothing and the stock wheel still selects normally while None is selected.
local function clearSelection()
	local defaultManager = uevrUtils.find_default_instance("Class /Script/Phoenix.QuickActionManager")
	local manager = defaultManager and uevrUtils.getValid(defaultManager:Get())
	if manager == nil then return false, "QuickActionManager is unavailable" end
	local none = cachedFName("None")
	manager:SetQuickWheelItem(none)
	if nameString(manager:GetQuickWheelItem()) ~= "None" then return false, "The game did not clear the selection" end
	for _, hud in ipairs(uevrUtils.find_all_instances(QUICK_ITEM_HUD, false) or {}) do
		-- The HUD Blueprint's template shares the class; only the live widget is transient.
		if uevrUtils.getValid(hud) ~= nil and hud:get_full_name():find("/Engine/Transient", 1, true) ~= nil then
			hud:SetItem(none)
		end
	end
	return true
end

local function selectItem(item)
	if not hasGadgetAccess() then return false, "The game gadget wheel is unavailable" end
	if item.clearsSelection then return clearSelection() end
	local service = selectionService
	-- Never take over a stock wheel that the game already owns.
	if uevrUtils.getValid(service.ItemWheelWidget) ~= nil then
		return false, "The game gadget wheel is already active"
	end
	local defaultManager = uevrUtils.find_default_instance("Class /Script/Phoenix.QuickActionManager")
	local manager = defaultManager and uevrUtils.getValid(defaultManager:Get())
	if manager == nil then return false, "QuickActionManager is unavailable" end

	-- Create, hide, confirm and remove the stock backend within this game tick.
	-- Confirmation sends the normal HUD notifications; it does not use the gadget.
	local ok, selected, reason = pcall(function()
		local widget, createError = createSelectionBackend(service)
		if widget == nil then return false, createError end
		-- The stock wheel exposes its eight entries as ordinary object properties.
		-- Read them natively instead of marshaling WheelItemArray through the bridge.
		for _, slot in ipairs(WHEEL_SLOTS) do
			local entry = widget[slot]
			if uevrUtils.getValid(entry) ~= nil and nameString(entry.ItemName) == item.id then
				if entry.IsLocked then return false, item.name .. " is locked" end
				widget.SelectedWheelItem = entry
				if widget.SelectedWheelItem ~= entry then return false, "Could not set gadget slot" end
				local confirmed, confirmError = confirmSelection(widget)
				if not confirmed then return false, confirmError end
				if nameString(manager:GetQuickWheelItem()) ~= item.id then
					return false, "The game did not confirm " .. item.name
				end
				return true
			end
		end
		return false, "No gadget slot for " .. item.name
	end)
	-- Also clean up after a failed selection call or Lua exception.
	local cleaned, cleanupError = pcall(function() service:CleanupItemWheel() end)
	if not cleaned then print("Palette: backend cleanup failed: " .. tostring(cleanupError)) end
	if not ok then return false, selected end
	return selected, reason
end

local function nearestItem(hand)
	local root = uevrUtils.getValid(parentRoot)
	if root == nil or layout == nil then return nil end
	if uevrUtils.getValid(controllers.getController(hand, true)) == nil then return nil end
	local location = controllers.getControllerLocation(hand)
	if location ~= nil then
		local transform = root:K2_GetComponentToWorld()
		local nearest, distance = nil, SELECT_DISTANCE * SELECT_DISTANCE
		for index, localCenter in ipairs(centers) do
			-- A grip on a lock leaves the wheel open without selecting anything.
			if not lockedSlots[index] and uevrUtils.getValid(actors[index]) ~= nil then
				local center = kismet_math_library:TransformLocation(transform, uevrUtils.vector(localCenter.X, localCenter.Y, localCenter.Z))
				local squared = mathLib.vectorDistanceSquared(location, center)
				if squared <= distance then nearest, distance = layout.items[index], squared end
			end
		end
		return nearest
	end
end

local function queue(action)
	if #pending < 16 then pending[#pending + 1] = action end
end

local function suppressGrips(state)
	if accessPawn ~= pawn or not gadgetAvailable or ui.isRemapDisabled() ~= false then return end
	for _, grip in ipairs(grips) do
		if consumeGrip[grip.hand] then uevrUtils.unpressButton(state, grip.button) end
	end
end

local function captureInput(retval, userIndex, state)
	if not enabled or userIndex ~= 0 then return end
	local allowed = canSpawn()
	-- Hysteresis avoids repeated clicks near the trigger threshold.
	local trigger = state.Gamepad.bLeftTrigger > (triggerWasPressed and 96 or 128)
	local tapped = trigger and not triggerWasPressed
	-- Refresh on interaction edges, including after an unlock, rather than on tick.
	local checkAccess = accessPawn ~= pawn or tapped
	for _, grip in ipairs(grips) do
		if not gripWasPressed[grip.hand] and uevrUtils.isButtonPressed(state, grip.button)
			and (#actors > 0 or (gestureBased and grip.hand == Handed.Left)) then checkAccess = true end
	end
	if allowed and checkAccess then hasGadgetAccess() end
	allowed = allowed and accessPawn == pawn and gadgetAvailable
	-- Classify taps before acting: a second tap within DOUBLE_TAP_WINDOW opens the diamond
	-- (or swaps the open display); otherwise the single tap acts once the window has passed.
	if tapTime ~= nil and (not allowed or os.clock() - tapTime > DOUBLE_TAP_WINDOW) then
		tapTime = nil
		if allowed then queue({toggle = true}) end
	end
	if tapped and allowed then
		if tapTime ~= nil then
			tapTime = nil
			queue({toggle = true, double = true})
		elseif DOUBLE_TAP_WINDOW > 0 then
			tapTime = os.clock()
		else
			queue({toggle = true})
		end
	end
	triggerWasPressed = trigger
	-- With the wheel closed, LB+RB together is the game's Ancient Magic input. A left grip
	-- that starts with RB held, or is joined by RB within CHORD_WINDOW, passes to the game.
	local wheelOpen = #actors > 0 and not closing and displayPawn == pawn
	local leftPressed = uevrUtils.isButtonPressed(state, XINPUT_GAMEPAD_LEFT_SHOULDER)
	local rightPressed = uevrUtils.isButtonPressed(state, XINPUT_GAMEPAD_RIGHT_SHOULDER)
	if not leftPressed then
		leftChord, leftPressTime = false, nil
		leftAccessory = false
	elseif gestureBased and not wheelOpen then
		if not gripWasPressed[Handed.Left] then
			leftChord, leftPressTime = rightPressed, os.clock()
			-- A grip that attaches to, or starts while holding, an accessory passes through
			-- for the whole hold, so it never makes a copy.
			leftAccessory = allowed and accessories.isGripHandEngaged(Handed.Left)
		elseif not leftChord and rightPressed and not gripWasPressed[Handed.Right]
			and leftPressTime ~= nil and os.clock() - leftPressTime <= CHORD_WINDOW then
			-- RB followed LB quickly: release LB to the game and drop any copy it created.
			leftChord = true
			queue({release = true})
		end
	end
	for _, grip in ipairs(grips) do
		local pressed = uevrUtils.isButtonPressed(state, grip.button)
		if not pressed then
			consumeGrip[grip.hand] = false
			if not TOGGLE_GRIP_FOR_ADJUSTMENTS and gestureBased and grip.hand == Handed.Left and gripWasPressed[grip.hand] then
				-- Decide a plant throw now: the tick removes the copy on release before
				-- queued actions run, clearing the held item and its thrust.
				local thrown = activeItem ~= nil and not isPotion(activeItem)
					and thrustAge ~= nil and thrustAge <= THROW_RELEASE_WINDOW
				queue({release = true, use = thrown and activeItem or nil})
			end
		elseif grip.hand == Handed.Left and (leftChord or leftAccessory) then
			consumeGrip[grip.hand] = false
		elseif allowed and (wheelOpen or (gestureBased and grip.hand == Handed.Left)) then
			-- Retain this latch through closure until release, preventing tap-to-use.
			consumeGrip[grip.hand] = true
			if not gripWasPressed[grip.hand] then
				local item = nil
				if wheelOpen and transition == nil then
					item = nearestItem(grip.hand)
				end
				local copy = gestureBased and grip.hand == Handed.Left
				if item ~= nil or copy then queue({item = item, ring = actors, copy = copy}) end
			end
		end
		gripWasPressed[grip.hand] = pressed
	end
	-- Drinking: a held potion reaching the mouth is used once, or again after a refusal once it
	-- has left the mouth. Read the gesture before the grip is suppressed below.
	if activeItem ~= nil and isPotion(activeItem) and not useQueued and leftPressed and not leftChord then
		if not gestures.getHeadGestures(state, Handed.Left, true) then
			awaitMouthExit = false
		elseif not awaitMouthExit and (cooldownUntil[activeItem.id] == nil or os.clock() >= cooldownUntil[activeItem.id]) then
			useQueued = true
			queue({drink = activeItem, held = activeActor})
		end
	end
	-- Prevent a selecting grip from also firing the mod's mouth/head gestures.
	suppressGrips(state)
end

local function suppressInput(retval, userIndex, state)
	if not enabled or userIndex ~= 0 then return end
	if accessPawn == pawn and gadgetAvailable and ui.isRemapDisabled() == false then state.Gamepad.bLeftTrigger = 0 end
	suppressGrips(state)
end

-- Use the gadget a held copy represented. The grip stays latched until release, so the
-- game never sees an LB tap; only a new grip makes a new copy. Diamond mounts are summoned
-- and Felix Felicis is used by inventory name: neither is a quick-wheel item.
local function useItem(item)
	if item.summon ~= nil then
		if not mountReady(item, functionLibrary()) then print("Palette: " .. item.name .. " is unavailable here"); return false end
		spells[item.summon](pawn)
		print("Palette: summoned " .. item.name)
		return true
	end
	if item.direct then
		local name, holder = cachedFName(item.id), cachedFName("ActorBackpack")
		pawn:LoadInventoryItemByName(name, holder)
		if pawn:UseInventoryItemByName(name, holder) ~= true then
			print("Palette: the game did not use " .. item.name)
			return false
		end
		print("Palette: used " .. item.name)
		return true
	end
	local defaultManager = uevrUtils.find_default_instance("Class /Script/Phoenix.QuickActionManager")
	local manager = defaultManager and uevrUtils.getValid(defaultManager:Get())
	if manager == nil then print("Palette: QuickActionManager is unavailable"); return false end
	-- UseQuickWheelItem acts on the game's selection; skip it if that changed since the copy.
	if nameString(manager:GetQuickWheelItem()) ~= item.id then
		print("Palette: selection changed; " .. item.name .. " was not used")
		return false
	end
	manager:UseQuickWheelItem()
	print("Palette: used " .. item.name)
	return true
end

-- Hide the potion tool whose bottle the game's drink animation raises. Only potion tools
-- have PotionMesh, so the wand or any other active tool is left alone.
local function hideDrinkTool()
	local toolSet = uevrUtils.getValid(pawn.InventoryToolSetComponent)
	local tool = toolSet and uevrUtils.getValid(toolSet:GetActiveTool())
	if tool == nil or tool.PotionMesh == nil then return end
	if not tool.bHidden then tool:SetActorHiddenInGame(true) end
	hiddenDrinkTool = tool
end

-- Shrink the held potion away after a confirmed drink, unless it is released or replaced.
local function shrinkHeld(held)
	local mesh = activeActor == held and uevrUtils.getValid(activeMesh) or nil
	if mesh == nil then return end
	local scale = mesh.RelativeScale3D
	local x, y, z = scale.X, scale.Y, scale.Z
	-- A reused lerp ID keeps its old callback, so replace any earlier shrink.
	uevrUtils.cancelLerp("paletteDrinkShrink")
	uevrUtils.lerp("paletteDrinkShrink", 1, 0, DRINK_SHRINK_SECONDS, nil, function(alpha, progress)
		if activeActor ~= held or uevrUtils.getValid(mesh) == nil then
			uevrUtils.cancelLerp("paletteDrinkShrink")
		elseif progress >= 1 then
			M.clearActiveMesh()
		else
			mesh:SetRelativeScale3D(uevrUtils.vector(x * alpha, y * alpha, z * alpha))
		end
	end)
end

-- From the gulp until DRINK_CONFIRM_SECONDS, shrink the potion once its count drops. Without a
-- count from before the drink, shrink at the gulp as before. No drop means the game refused;
-- the bottle stays in the hand and can be tried again once it has left the mouth.
local function tickDrinkCheck(delta)
	local check = drinkCheck
	if activeActor ~= check.held then drinkCheck = nil; return end
	check.elapsed = check.elapsed + delta
	if check.elapsed < check.nextCheck then return end
	check.nextCheck = check.nextCheck + DRINK_CHECK_INTERVAL
	local count = check.before ~= nil and currentCount(check.item) or nil
	if check.before == nil or (count ~= nil and count < check.before) then
		drinkCheck = nil
		shrinkHeld(check.held)
	elseif check.elapsed >= DRINK_CONFIRM_SECONDS then
		drinkCheck = nil
		print("Palette: the game did not drink " .. check.item.name)
		useQueued, awaitMouthExit = false, true
		cooldownUntil[check.item.id] = nil -- Nothing was drunk, so nothing to cool down.
	end
end

local function processAction(action)
	if action.release then
		M.clearActiveMesh()
		-- Set when the plant was thrust shortly before release.
		if action.use ~= nil then useItem(action.use) end
	elseif action.drink ~= nil then
		local held = action.held
		local before = currentCount(action.drink)
		if useItem(action.drink) then
			drinkToolTime = DRINK_TOOL_HIDE_SECONDS
			-- Start any cooldown now: releasing the bottle early cancels the drink check below.
			if action.drink.cooldown ~= nil then cooldownUntil[action.drink.id] = os.clock() + action.drink.cooldown end
			-- Keep our potion at the mouth until the gulp; the tick then confirms the drink.
			if held ~= nil and activeActor == held then
				drinkCheck = {held = held, item = action.drink, before = before, elapsed = 0, nextCheck = DRINK_GULP_SECONDS}
			end
		elseif held == activeActor then
			M.clearActiveMesh()
		end
	elseif action.toggle then
		local open = #actors > 0 and not closing
		if action.double then
			-- Double tap: open the diamond, or swap whichever display is open.
			M.show(open and layout == layouts.diamond and layouts.ring or layouts.diamond)
		elseif open then
			beginTransition(true)
		else
			M.show(layouts.ring)
		end
	elseif action.copy and TOGGLE_GRIP_FOR_ADJUSTMENTS and uevrUtils.getValid(activeActor) ~= nil then
		M.clearActiveMesh()
	else
		if action.item ~= nil then
			if action.ring ~= actors or closing or transition ~= nil then return end
			-- Diamond items are used rather than selected. In gesture mode a left grip
			-- takes Felix Felicis into the hand to drink; it is gone once released.
			if layout == layouts.diamond then
				if action.item.summon == nil and action.copy and gestureBased then
					beginTransition(true)
					local created, reason = M.createSelectedMesh(action.item)
					if not created and reason ~= nil then print("Palette: " .. tostring(reason)) end
				elseif useItem(action.item) then
					beginTransition(true)
				end
				return
			end
			local selected, reason = selectItem(action.item)
			if not selected then print("Palette: " .. tostring(reason)); return end
			beginTransition(true)
			print("Palette: selected " .. action.item.name)
		end
		if action.copy and gestureBased then
			local created, reason = M.createSelectedMesh()
			if not created and reason ~= nil then print("Palette: " .. tostring(reason)) end
		end
	end
end

local function runTick(engine, delta)
	local actions = pending
	if actions[1] ~= nil then pending = {} end
	local allowed = canSpawn() and accessPawn == pawn and gadgetAvailable
	if activeActor ~= nil and (not allowed or not gestureBased
		or (not TOGGLE_GRIP_FOR_ADJUSTMENTS and not gripWasPressed[Handed.Left]) or activePawn ~= pawn
		or uevrUtils.getValid(activeActor) == nil or uevrUtils.getValid(activeMesh) == nil
		or uevrUtils.getValid(controllers.getController(Handed.Left, true)) == nil) then
		M.clearActiveMesh()
	end
	if not allowed or (#actors > 0 and (displayPawn ~= pawn
		or uevrUtils.getValid(parentActor) == nil or uevrUtils.getValid(parentRoot) == nil
		or uevrUtils.getValid(followActor) == nil or uevrUtils.getValid(followRoot) == nil
		or uevrUtils.getValid(apparitionRoot) == nil
		or uevrUtils.getValid(followHmd) == nil or followHmd ~= controllers.getController(2, true))) then
		if #actors > 0 then M.close() end
		return
	end
	for _, action in ipairs(actions) do
		processAction(action)
	end
	-- Track thrusts while a plant copy is held. The detector needs every frame of the hold.
	if activeItem ~= nil and not isPotion(activeItem) and type(delta) == "number" and delta > 0 and delta < math.huge then
		if thrustAge ~= nil then thrustAge = thrustAge + delta end
		if gestures.detectGesture(gestures.Gesture.PUNCH, delta, Handed.Left) then thrustAge = 0 end
	end
	if drinkCheck ~= nil and type(delta) == "number" and delta > 0 and delta < math.huge then
		tickDrinkCheck(delta)
	end
	if drinkToolTime ~= nil and type(delta) == "number" and delta > 0 and delta < math.huge then
		hideDrinkTool()
		drinkToolTime = drinkToolTime - delta
		if drinkToolTime <= 0 then drinkToolTime = nil end
	end
	if #actors > 0 then
		if transition ~= nil or apparition ~= nil or closing then
			tickTransition(delta)
		end
		if countDisplay ~= nil and layout ~= nil and not closing and type(delta) == "number" and delta > 0 and delta < math.huge then
			countElapsed = countElapsed + delta
			if countElapsed >= COUNT_REFRESH_SECONDS then
				countElapsed = 0
				local updated, reason = updateCounts(countDisplay)
				if not updated and not countReadFailed then print("Palette: " .. tostring(reason)) end
				countReadFailed = not updated
				-- Mount availability changes with the player's state (landing, swimming).
				if countDisplay.icons[1] ~= nil then showNoMountIcons(countDisplay, readMountBlocked(layout.items, lockedSlots)) end
			end
		end
	end
end

local tickWheel, tickClosing, tickHeld, tickActions
local function tick(engine, delta)
	-- Leave this dispatcher unprofiled: idle callbacks must not dilute active
	-- averages or allocate the profiler's results table. No native queries here.
	if not enabled then return end
	if pending[1] ~= nil then
		tickActions(engine, delta)
	elseif #actors > 0 then
		if closing then tickClosing(engine, delta) else tickWheel(engine, delta) end
	elseif activeActor ~= nil or drinkToolTime ~= nil then
		tickHeld(engine, delta)
	end
end

-- Use the shared profiler's toggle/report controls (F1 in main.lua).
-- Nested timings are inclusive; wrappers do not print on input/tick callbacks.
loadMesh = uevrUtils.profiler:wrap("Palette: load mesh", loadMesh)
colorLiquid = uevrUtils.profiler:wrap("Palette: color liquid", colorLiquid)
createItem = uevrUtils.profiler:wrap("Palette: create item", createItem)
createCounts = uevrUtils.profiler:wrap("Palette: create count widgets", createCounts)
buildCounts = uevrUtils.profiler:wrap("Palette: build count widgets", buildCounts)
reuseCounts = uevrUtils.profiler:wrap("Palette: reuse count widgets", reuseCounts)
readCounts = uevrUtils.profiler:wrap("Palette: read inventory", readCounts)
readLocks = uevrUtils.profiler:wrap("Palette: read locks", readLocks)
readMountBlocked = uevrUtils.profiler:wrap("Palette: read mount state", readMountBlocked)
updateCounts = uevrUtils.profiler:wrap("Palette: refresh counts", updateCounts)
createParticle = uevrUtils.profiler:wrap("Palette: create particle", createParticle)
createEffect = uevrUtils.profiler:wrap("Palette: create beacon", createEffect)
beginTransition = uevrUtils.profiler:wrap("Palette: begin animation", beginTransition)
tickTransition = uevrUtils.profiler:wrap("Palette: animate", tickTransition)
destroyCounts = uevrUtils.profiler:wrap("Palette: destroy count widgets", destroyCounts)
parkCounts = uevrUtils.profiler:wrap("Palette: cache count widgets", parkCounts)
destroyDisplay = uevrUtils.profiler:wrap("Palette: destroy display", destroyDisplay)
selectItem = uevrUtils.profiler:wrap("Palette: select item", selectItem)
createSelectionBackend = uevrUtils.profiler:wrap("Palette: create selection backend", createSelectionBackend)
confirmSelection = uevrUtils.profiler:wrap("Palette: confirm selection", confirmSelection)
nearestItem = uevrUtils.profiler:wrap("Palette: nearest item", nearestItem)
processAction = uevrUtils.profiler:wrap("Palette: action", processAction)
useItem = uevrUtils.profiler:wrap("Palette: use held item", useItem)
hideDrinkTool = uevrUtils.profiler:wrap("Palette: hide drink tool", hideDrinkTool)
tickDrinkCheck = uevrUtils.profiler:wrap("Palette: confirm drink", tickDrinkCheck)
captureInput = uevrUtils.profiler:wrap("Palette: capture input", captureInput)
suppressInput = uevrUtils.profiler:wrap("Palette: suppress input", suppressInput)
tickWheel = uevrUtils.profiler:wrap("Palette: tick wheel", runTick)
tickClosing = uevrUtils.profiler:wrap("Palette: tick closing", runTick)
tickHeld = uevrUtils.profiler:wrap("Palette: tick held", runTick)
tickActions = uevrUtils.profiler:wrap("Palette: tick actions", runTick)
M.show = uevrUtils.profiler:wrap("Palette: open", M.show)
M.close = uevrUtils.profiler:wrap("Palette: close", M.close)
M.createSelectedMesh = uevrUtils.profiler:wrap("Palette: create held item", M.createSelectedMesh)
M.clearActiveMesh = uevrUtils.profiler:wrap("Palette: clear held item", M.clearActiveMesh)
M.reset = uevrUtils.profiler:wrap("Palette: reset", M.reset)

function M.init()
	if initialized then return end
	initialized = true
	uevrUtils.registerOnPreInputGetStateCallback(captureInput, 6)
	uevrUtils.registerOnPostInputGetStateCallback(suppressInput, -100)
	uevrUtils.registerPreEngineTickCallback(tick)
	uevrUtils.registerPreLevelChangeCallback(M.reset)
	uevr.params.sdk.callbacks.on_script_reset(M.reset)
end

return M
