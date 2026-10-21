local uevrUtils = require("libs/uevr_utils")
local mathLib = require("libs/core/math_lib")
local ui = require("libs/ui")
local plugin = require("libs/core/plugin")
local controllers = require("libs/controllers")

local M = {}

-- Reusable save storage/lifecycle class. Callbacks supply the feature-specific
-- capture, validation, and restoration; nothing here refers to boats.
local serialization = {}
serialization.__index = serialization
M.serialization = serialization

function serialization.new(options)
	assert(type(options.owner) == "string" and options.owner ~= "")
	local self = setmetatable({options = options, enabled = true}, serialization)
	self.owner = options.owner
	self.key = options.key or "State"
	self.version = options.version or 1
	self.handledTag = self.owner .. ".LoadHandled"
	self.handledName = uevrUtils.fname_from_string(self.handledTag)
	return self
end

function serialization:database()
	return uevrUtils.find_first_of("Class /Script/DbGateway.DbGateway", false)
end

function serialization:read()
	local db = self:database()
	if db == nil then return nil, false end
	-- Read this key directly; leaving OutValue omitted gives Unreal a zeroed
	-- FString for the bridge to fill.
	local result = plugin.executeFunctionWithOutputs(db, "DbReadMiscSaveDataItem", {"ReturnValue", "OutValue"},
		self.owner, self.key)
	if result == nil or type(result.ReturnValue) ~= "boolean" then return nil, false end
	if not result.ReturnValue then return nil, true end
	local text = result.OutValue
	if type(text) ~= "string" then return nil, false end
	local ok, record = pcall(json.load_string, text)
	if not ok or type(record) ~= "table" or record.version ~= self.version then
		return nil, true
	end
	if self.options.validate ~= nil and not self.options.validate(record) then
		return nil, true
	end
	return record, true
end

function serialization:write(record)
	local db = self:database()
	if db == nil then return false end
	record.version = self.version
	local result = plugin.executeFunctionWithOutputs(db, "DbWriteMiscSaveDataItem", {"ReturnValue"},
		self.owner, self.key, json.dump_string(record), true)
	return result ~= nil and result.ReturnValue == true
end

function serialization:save()
	-- An autosave during loading must retain the loaded record until restoration.
	if not self.enabled or self.pending ~= nil then return end
	local record = self.options.capture()
	if record ~= nil and not self:write(record) then
		print("Serialization: could not save " .. self.owner)
	end
end

function serialization:markHandled(p)
	if p:ActorHasTag(self.handledName) then return end
	local tags = plugin.getProperty(p, "Tags")
	if type(tags) ~= "table" then return end
	tags[#tags + 1] = self.handledTag
	plugin.setProperty(p, "Tags", tags)
end

function serialization:cancel()
	self.pending = nil
	if self.timer ~= nil then
		uevrUtils.clearInterval(self.timer)
		self.timer = nil
	end
end

function serialization:run(method, ...)
	local ok, err = pcall(method, self, ...)
	if not ok then
		self:cancel()
		print("Serialization: " .. self.owner .. ": " .. tostring(err))
	end
end

function serialization:queueLoad(fromEvent)
	if not self.enabled then return end
	local p = uevrUtils.getValid(uevr.api:get_local_pawn(0))
	local pending = {elapsed = 0, stable = 0, startup = not fromEvent,
		oldPawn = fromEvent and p ~= nil and p:get_full_name() or nil,
		oldPawnAddress = fromEvent and p ~= nil and p:get_address() or nil}
	self.pending = pending
	if fromEvent then
		-- The notification precedes the dynamic database swap. Read only after
		-- the new world's pawn is ready, rather than caching the outgoing save.
		if self.options.beforeLoad ~= nil then self.options.beforeLoad() end
	end
	if self.timer == nil then
		self.timer = uevrUtils.setInterval(250, function() self:run(self.poll) end)
	end
end

function serialization:poll()
	local pending = self.pending
	if pending == nil then return end
	pending.elapsed = pending.elapsed + 0.25
	if pending.elapsed > 120 then
		self:cancel()
		print("Serialization: timed out waiting to restore " .. self.owner)
		return
	end
	local p = uevrUtils.getValid(uevr.api:get_local_pawn(0))
	if p == nil then return end
	local address = p:get_address()
	-- Only resolve the full name when an address may still refer to the old
	-- pawn. The name distinguishes a new object at a reused native address.
	if address == pending.oldPawnAddress and p:get_full_name() == pending.oldPawn then return end
	-- A transient pawn tag survives Reset Scripts, but a newly loaded pawn does
	-- not have it. Never replay an old saved state just because scripts reset.
	if pending.startup and p:ActorHasTag(self.handledName) then self:cancel(); return end
	if uevrUtils.isGamePaused() or uevrUtils.isInCutscene() then return end
	if pending.pawn ~= address then
		pending.pawn, pending.stable = address, 0
	end
	pending.stable = pending.stable + 0.25
	if pending.stable < 1 then return end
	if not pending.read then
		pending.record, pending.read = self:read()
		if not pending.read then return end
	end
	local record = pending.record
	if record == nil or not self.options.shouldRestore(record) then
		self:markHandled(p)
		self:cancel()
		return
	end
	if pending.nextRestore ~= nil and pending.elapsed < pending.nextRestore then return end
	pending.nextRestore = pending.elapsed + (self.options.restoreInterval or 0.25)
	if self.options.restore(record, p) then
		self:markHandled(p)
		self:cancel()
	end
end

function serialization:start()
	local class = uevrUtils.get_class("Class /Script/Phoenix.PhoenixGameInstance")
	local save = class ~= nil and class:find_function("OnAboutToSaveGame") or nil
	local load = class ~= nil and class:find_function("OnSaveGameLoaded") or nil
	if save == nil or load == nil then
		print("Serialization: save/load callbacks unavailable for " .. self.owner)
		return
	end
	-- Capture BEFORE the native handler, which can take the database snapshot.
	-- Returning true preserves the game's native handler and save processing.
	save:hook_ptr(function()
		if self.enabled then self:run(self.save) end
		return true
	end, nil)
	load:hook_ptr(nil, function()
		if self.enabled then self:run(self.queueLoad, true) end
	end)
	self:queueLoad(false) -- also supports injecting UEVR after a save has loaded
end

function serialization:stop()
	self.enabled = false
	self:dismiss()
end

function serialization:dismiss()
	local p = uevrUtils.getValid(uevr.api:get_local_pawn(0))
	if p ~= nil then self:markHandled(p) end
	self:cancel()
end

local BOAT_CLASS = "BlueprintGeneratedClass /Game/Gameplay/Blueprints/Universal/BP_Boat.BP_Boat_C"
local WATER_VOLUME_CLASS = "Class /Script/Phoenix.WaterVolumeBase"
local OBJECT_STATE_MANAGER_CLASS = "Class /Script/Phoenix.ObjectStateManager"
local MANAGED_BOAT_TAG = "HL_UEVR.ManagedBoat"
local MANAGED_BOAT_TAG_NAME = uevrUtils.fname_from_string(MANAGED_BOAT_TAG)
-- Plain sit pose (no book / SceneRig / InCinematic). Station stories are cinematic.
local SIT_POSE = "AnimSequence /Game/Animation/Human/Stations/Sitting/STUM_STN_SIT_ArmChair_Proper_ANM.STUM_STN_SIT_ArmChair_Proper_ANM"

local BOAT_NEAR_DIST_SQ = 600 * 600 -- 6m
local BOAT_WATER_MAX_DIST = 2000 -- 20m, including height difference
local BOAT_WATER_MIN_DIST = 200 -- keep placement at least 2m in front of the pawn
local BOAT_WATER_SEARCH_STEP = 50
local BOAT_PLACEMENT_BUDGET = 0.002 -- seconds of search work per frame
local BOAT_WATER_SEARCH_ANGLES = {0, -15, 15, -30, 30}
local BOAT_SHORE_CLEARANCE = 350 -- hull is about 5.6m long; leave room around its centre
local BOAT_MIN_WATER_DEPTH = 35 -- keep the keel clear of the shallow bank (cm)
local BOAT_STATION_SOCKET = uevrUtils.fname_from_string("Station")
local HIPS_SOCKET = uevrUtils.fname_from_string("Hips")
-- Station socket sits at the front edge; push hips back into the seat (cm).
local SEAT_BACK_CM = 25
local BOAT_SEAT_FADE_SECONDS = 0.3
local STICK_DEADZONE = 4000
local BOAT_MAX_SPEED = 400 -- cm/s at full throttle
local BOAT_ACCEL = 110 -- cm/s^2 while holding forward/back
local BOAT_COAST_DECEL = 55 -- cm/s^2 when stick released
-- Rudder authority scales with water speed — slow boats barely turn.
local BOAT_YAW_RATE = 20 -- deg/s at full stick + speed
local BOAT_YAW_ACCEL = 60 -- deg/s^2; ease the motor's turning effort in/out
local BOAT_YAW_REF_SPEED = 350 -- cm/s for full turn authority
local BOAT_YAW_MIN_SCALE = 0.12
local NONE_BONE = uevrUtils.fname_from_string("None")
-- Standalone apparition: no mount handler, rider animation, or auto-boarding.
local BOAT_APPEAR_EFFECT = "NiagaraSystem /Game/VFX/Particles/Magic/Apparition/VFX_NS_Apparate_Universal_Master_Lg_In_V1.VFX_NS_Apparate_Universal_Master_Lg_In_V1"
local BOAT_APPEAR_DELAY = 0.18
local BOAT_APPEAR_SECONDS = 1.0
local BOAT_APPEAR_MIN_SCALE = 0.02
local BOAT_APPEAR_EFFECT_SCALE = 1.5
local BOAT_APPEAR_EFFECT_HEIGHT = 75 -- cm above the water
local BOAT_APPEAR_EFFECT_SECONDS = 3.0
local BOAT_FLOAT_SETUP_TIMEOUT = 2.0
local BOAT_FLOAT_SETUP_RETRY = 0.1

local spawnedBoat = nil
local seatBoat = nil
local seated = false
local pawnCollisionWasEnabled = true
local stickLX = 0
local stickLY = 0
local driveSpeed = 0
local driveYaw = 0
local boatButtonWasPressed = false
local boatButtonConsumed = false
local boatSerialization = nil
local boatAppearance = nil
local boatPlacement = nil

function M.isSeated()
	return seated
end

local function setManagedBoatTag(boat, enabled)
	if boat:ActorHasTag(MANAGED_BOAT_TAG_NAME) == enabled then return true end
	local tags = plugin.getProperty(boat, "Tags")
	if type(tags) ~= "table" then return false end
	local updated = {}
	for _, tag in ipairs(tags) do
		if string.lower(tag) ~= string.lower(MANAGED_BOAT_TAG) then
			updated[#updated + 1] = tag
		end
	end
	if enabled then updated[#updated + 1] = MANAGED_BOAT_TAG end
	plugin.setProperty(boat, "Tags", updated)
	-- The setter is void; verify that the actor actually received the change.
	return boat:ActorHasTag(MANAGED_BOAT_TAG_NAME) == enabled
end

local function rememberBoat(boat)
	local previous = uevrUtils.getValid(spawnedBoat)
	local alreadyTagged = boat:ActorHasTag(MANAGED_BOAT_TAG_NAME)
	if not setManagedBoatTag(boat, true) then
		print("Boat: could not save the managed-boat tag")
		return false
	end
	-- Boarding another boat transfers ownership instead of leaving two tagged.
	if previous ~= nil and previous ~= boat and not setManagedBoatTag(previous, false) then
		if not alreadyTagged then setManagedBoatTag(boat, false) end
		print("Boat: could not transfer the managed-boat tag")
		return false
	end
	spawnedBoat = boat
	return true
end

local function isFiniteNumber(value)
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function getBoatSpawnLocation(p, checkpoint)
	local ksl = uevrUtils.find_default_instance("Class /Script/Engine.KismetSystemLibrary")
	if ksl == nil or not uevrUtils.checkPluginExists() then return nil end
	local loc = p:K2_GetActorLocation()
	if not isFiniteNumber(loc.X) or not isFiniteNumber(loc.Y) or not isFiniteNumber(loc.Z) then return nil end
	local head = controllers.getControllerRotation(2)
	local fx, fy
	if head ~= nil and isFiniteNumber(head.Yaw) then
		local yaw = math.rad(head.Yaw)
		fx, fy = math.cos(yaw), math.sin(yaw)
	else
		local fwd = p:GetActorForwardVector()
		if not isFiniteNumber(fwd.X) or not isFiniteNumber(fwd.Y) then return nil end
		local length = math.sqrt(fwd.X * fwd.X + fwd.Y * fwd.Y)
		if length < 0.001 then return nil end
		fx, fy = fwd.X / length, fwd.Y / length
	end
	local directions = {}
	for _, angle in ipairs(BOAT_WATER_SEARCH_ANGLES) do
		local a = math.rad(angle)
		directions[#directions + 1] = {X = fx * math.cos(a) - fy * math.sin(a), Y = fx * math.sin(a) + fy * math.cos(a)}
	end
	local footprint = {}
	-- Check toward shore first so unsuitable positions fail cheaply.
	for _, angle in ipairs({180, 135, -135, 90, -90, 45, -45, 0}) do
		local a = math.rad(angle)
		footprint[#footprint + 1] = {
			X = (fx * math.cos(a) - fy * math.sin(a)) * BOAT_SHORE_CLEARANCE,
			Y = (fx * math.sin(a) + fy * math.cos(a)) * BOAT_SHORE_CLEARANCE,
		}
	end
	local ignoreActors = {p}
	local existing = uevrUtils.getValid(spawnedBoat)
	if existing ~= nil then ignoreActors[#ignoreActors + 1] = existing end
	local color = uevrUtils.color_from_rgba(0, 0, 0, 0)
	local maxDistSq = BOAT_WATER_MAX_DIST * BOAT_WATER_MAX_DIST
	local best, bestDistSq, bestAlong = nil, maxDistSq, nil
	-- Cache only within this request; never reuse terrain/water across placements.
	local waterCache, clearCache = {}, {}
	local function pointKey(x, y)
		return string.format("%.1f:%.1f", x, y) -- millimetre key precision
	end
	local function waterHeightAt(x, y)
		local key = pointKey(x, y)
		local cached = waterCache[key]
		if cached ~= nil then return cached or nil end
		local hit = {}
		local ok = ksl:GetWaterHeight(p, 0, hit, uevrUtils.vector(x, y, loc.Z), BOAT_WATER_MAX_DIST, BOAT_WATER_MAX_DIST, true, color, color, 0)
		local impact = hit.result or hit
		local distance = impact and impact.Distance
		local valid = ok and isFiniteNumber(distance) and distance >= 0 and distance <= BOAT_WATER_MAX_DIST * 2
		-- This is a vertical trace from QueryPosition + SearchUp. Distance avoids
		-- relying on nested FHitResult vector types that some Lua bindings misread.
		local z = valid and loc.Z + BOAT_WATER_MAX_DIST - distance or nil
		waterCache[key] = z or false
		if checkpoint ~= nil then checkpoint() end
		return z
	end
	local function isClearTo(x, y, z, bottomOffset)
		-- Check above the surface at the perimeter and down to keel depth at
		-- the centre, rejecting both dry shore and submerged shallow ground.
		local key = pointKey(x, y) .. ":" .. string.format("%.1f", z + bottomOffset)
		if clearCache[key] ~= nil then return clearCache[key] end
		local clear = plugin.executeFunctionWithOutputs(ksl, "LineTraceSingle", {"ReturnValue"}, p,
			uevrUtils.vector(x, y, math.max(loc.Z + BOAT_WATER_MAX_DIST, z + 50)),
			uevrUtils.vector(x, y, z + bottomOffset), 0, true, ignoreActors, 0, {}, true, color, color, 0)
		local result = clear ~= nil and clear.ReturnValue == false
		clearCache[key] = result
		if checkpoint ~= nil then checkpoint() end
		return result
	end
	local function consider(x, y, along)
		local z = waterHeightAt(x, y)
		if z == nil then return end
		local distSq = (x - loc.X)^2 + (y - loc.Y)^2 + (z - loc.Z)^2
		if distSq > maxDistSq then return end
		-- Keep the headset-facing ray on near-ties instead of jumping sideways
		-- because of floating-point noise at large world coordinates.
		if best ~= nil and math.sqrt(distSq) >= math.sqrt(bestDistSq) - 1 then return end
		if not isClearTo(x, y, z, -BOAT_MIN_WATER_DEPTH) then return end
		for _, offset in ipairs(footprint) do
			local sx, sy = x + offset.X, y + offset.Y
			local waterZ = waterHeightAt(sx, sy)
			if waterZ == nil or math.abs(waterZ - z) > 20 or not isClearTo(sx, sy, waterZ, 5) then
				return
			end
		end
		best, bestDistSq, bestAlong = uevrUtils.vector(x, y, z), distSq, along
	end
	local function searchAt(along)
		for _, direction in ipairs(directions) do
			consider(loc.X + direction.X * along, loc.Y + direction.Y * along, along)
		end
	end
	-- Search nearest first in a forward 60-degree arc, only for a placement request.
	for along = BOAT_WATER_MIN_DIST, BOAT_WATER_MAX_DIST, BOAT_WATER_SEARCH_STEP do
		if along * along > bestDistSq then break end
		searchAt(along)
	end
	if bestAlong ~= nil and bestAlong > BOAT_WATER_MIN_DIST then
		-- Refine the nearest coarse band to 10cm radial spacing at the shore.
		for along = math.max(BOAT_WATER_MIN_DIST, bestAlong - BOAT_WATER_SEARCH_STEP), bestAlong - 10, 10 do
			searchAt(along)
		end
	end
	if best == nil then return nil end
	-- Present the long side to the player's approach, even if the water search
	-- picked a point slightly to one side of the headset-facing ray.
	local approachYaw = math.deg(math.atan(best.Y - loc.Y, best.X - loc.X))
	return best, approachYaw + 90
end

-- A search may span frames, but only one request exists and all native reads
-- run on the engine thread. Profiling measures each slice, excluding the wait.
local function resumeBoatPlacement(job)
	job.sliceStart = os.clock()
	local ok, pos, yaw = coroutine.resume(job.search)
	if not ok then
		job.failed, job.error, job.done = true, pos, true
	elseif coroutine.status(job.search) == "dead" then
		job.pos, job.yaw, job.done = pos, yaw, true
	end
end

local function tickBoatPlacement()
	local job = boatPlacement
	if job == nil or job.done then return end
	local p = uevrUtils.getValid(job.pawn)
	if p == nil or p ~= uevr.api:get_local_pawn(0) then boatPlacement = nil; return end
	if uevrUtils.isGamePaused() or uevrUtils.isInCutscene() then return end
	-- A result belongs to the position at which it was requested.
	if mathLib.vectorDistanceSquared(p:K2_GetActorLocation(), job.origin) > 100 * 100 then
		boatPlacement = nil
		return
	end
	resumeBoatPlacement(job)
	if job.failed then
		boatPlacement = nil
		print("Boat placement: " .. tostring(job.error))
	elseif job.done and job.callback ~= nil then
		boatPlacement = nil
		job.callback(job.pos, job.yaw)
	end
end

local function beginBoatPlacement(p, purpose, callback)
	local loc = p:K2_GetActorLocation()
	local job = {pawn = p, purpose = purpose, callback = callback,
		origin = {X = loc.X, Y = loc.Y, Z = loc.Z}, done = false}
	job.search = coroutine.create(function()
		return getBoatSpawnLocation(p, function()
			if os.clock() - job.sliceStart >= BOAT_PLACEMENT_BUDGET then coroutine.yield() end
		end)
	end)
	boatPlacement = job
	return job
end

local function configureBoatWater(boat, mesh, osi)
	-- This runs only on placement. Let native overlap events handle travel afterward.
	-- Read arrays through the bridge: native Lua cannot reliably marshal TArray.
	if not uevrUtils.checkPluginExists() then
		print("Boat flotation: uevr_utils bridge is unavailable")
		return false
	end
	-- Cached contact can be empty after resizing, and the keel starts above its
	-- settled floating position. Query the full hull just below the waterline;
	-- waiting for contact while holding physics off would prevent it settling.
	local ksl = uevrUtils.find_default_instance("Class /Script/Engine.KismetSystemLibrary")
	local boxClass = uevrUtils.get_class("Class /Script/Engine.BoxComponent")
	if ksl == nil or boxClass == nil then return false end
	local transform = mesh:K2_GetComponentToWorld()
	local location = mesh:K2_GetComponentLocation()
	transform.Translation = uevrUtils.vector(location.X, location.Y, location.Z - BOAT_MIN_WATER_DEPTH)
	local overlap = plugin.executeFunctionWithOutputs(ksl, "ComponentOverlapComponents", {"OutComponents"},
		mesh, transform, {0, 1}, boxClass, {boat}, {})
	if overlap == nil or type(overlap.OutComponents) ~= "table" then return false end
	local waterOverlaps = {}
	for _, component in ipairs(overlap.OutComponents) do
		if uevrUtils.getValid(component) ~= nil then waterOverlaps[component:get_address()] = true end
	end
	local entries = {}
	local hasOverlap = false
	local boatAddress = boat:get_address()
	for _, volume in ipairs(uevrUtils.find_all_of(WATER_VOLUME_CLASS, false) or {}) do
		local box = uevrUtils.getValid(volume.WaterBox)
		if box ~= nil then
			local actors = plugin.getProperty(volume, "BuoyancyActors")
			if type(actors) ~= "table" then
				-- A failed container read must not be treated as an empty array.
				print("Boat flotation: could not read water registrations")
				return false
			end
			local registered = false
			for _, actor in ipairs(actors) do
				if actor:get_address() == boatAddress then
					registered = true
					break
				end
			end
			local overlaps = waterOverlaps[box:get_address()] == true
			hasOverlap = hasOverlap or overlaps
			entries[#entries + 1] = {
				volume = volume, box = box, registered = registered,
				overlaps = overlaps,
			}
		end
	end
	-- Remove registrations outside the hull's current water before adding new
	-- ones. Placement can move a boat from one water volume to another.
	for _, entry in ipairs(entries) do
		if entry.registered and not entry.overlaps then
			entry.volume:OnOverlapEnd(entry.box, boat, mesh, 0)
		end
	end
	for _, entry in ipairs(entries) do
		if entry.overlaps and not entry.registered then
			entry.volume:SetupObject(boat, mesh, osi, true, true, true, nil)
		end
	end
	return hasOverlap
end

local function enableBoatFloating(boat)
	if uevrUtils.getValid(boat) == nil then return false end
	local mesh = uevrUtils.getValid(boat, {"Boat"})
	if mesh == nil then return false end

	local constraint = uevrUtils.getValid(boat, {"PhysicsConstraint"})
	if constraint ~= nil and constraint.BreakConstraint ~= nil then
		constraint:BreakConstraint()
	end

	local osmCdo = uevrUtils.find_default_instance(OBJECT_STATE_MANAGER_CLASS)
	local osm = osmCdo ~= nil and osmCdo:Get(uevrUtils.get_world()) or nil
	local osi = osm ~= nil and osm:GetObjectStateInfo(boat) or nil
	if osi ~= nil then
		osi:SetCanBecomeMovable(true)
	end

	local bi = mesh.BodyInstance
	if bi ~= nil then
		bi.bLockTranslation = false
		bi.bLockRotation = false
		bi.bLockXTranslation = false
		bi.bLockYTranslation = false
		bi.bLockZTranslation = false
	end
	mesh:SetSimulatePhysics(true)
	mesh:SetEnableGravity(true)

	local floating = osi ~= nil and configureBoatWater(boat, mesh, osi)
	-- Placement must not inherit a previous falling body's momentum.
	local zero = uevrUtils.vector(0, 0, 0)
	mesh:SetPhysicsLinearVelocity(zero, false, NONE_BONE)
	mesh:SetPhysicsAngularVelocityInDegrees(zero, false, NONE_BONE)
	mesh:SetEnableGravity(true)
	mesh:WakeAllRigidBodies()
	return floating
end

local function boatNearPoint(boat)
	local mesh = uevrUtils.getValid(boat, {"Boat"})
	if mesh ~= nil then
		local xf = mesh:GetSocketTransform(BOAT_STATION_SOCKET)
		local t = xf and xf.Translation
		if mathLib.vectorSizeSquared(t) > 0 then return t end
		local mloc = mesh.K2_GetComponentLocation ~= nil and mesh:K2_GetComponentLocation() or nil
		if mathLib.vectorSizeSquared(mloc) > 0 then return mloc end
	end
	return boat:K2_GetActorLocation()
end

local function findAnyNearestBoat(p)
	local best, bestD = nil, math.huge
	local ploc = p:K2_GetActorLocation()
	for _, b in ipairs(uevrUtils.find_all_of(BOAT_CLASS, false) or {}) do
		if uevrUtils.getValid(b) ~= nil then
			local d = mathLib.vectorDistanceSquared(ploc, boatNearPoint(b))
			if d < bestD then
				best, bestD = b, d
			end
		end
	end
	return best
end

local function queryTaggedBoats(p)
	-- Level reloads can replace this Blueprint UClass while Lua's class cache
	-- survives. Refresh before querying; spawning and fallback scans share it.
	local class = uevrUtils.get_class(BOAT_CLASS, true)
	if class == nil then return {} end
	local statics = uevrUtils.find_default_instance("Class /Script/Engine.GameplayStatics")
	if statics == nil or not uevrUtils.checkPluginExists() then return nil end
	local result = plugin.executeFunctionWithOutputs(statics, "GetAllActorsOfClassWithTag", {"OutActors"},
		p, class, MANAGED_BOAT_TAG, {})
	return result ~= nil and type(result.OutActors) == "table" and result.OutActors or nil
end

local function recoverBoat(p)
	local boat = uevrUtils.getValid(spawnedBoat)
	if boat ~= nil then return boat, true end
	local boats = queryTaggedBoats(p)
	if boats == nil then
		print("Boat: could not read managed boats; skipping creation")
		return nil, false
	end
	local best, bestDist = nil, math.huge
	local loc = p:K2_GetActorLocation()
	for _, candidate in ipairs(boats) do
		if uevrUtils.getValid(candidate) ~= nil then
			local distance = mathLib.vectorDistanceSquared(loc, boatNearPoint(candidate))
			if distance < bestDist then best, bestDist = candidate, distance end
		end
	end
	if best ~= nil then
		if not rememberBoat(best) then return nil, false end
	end
	return best, true
end

local function finishBoatAppearance()
	local appearance = boatAppearance
	if appearance == nil then return end
	local boat = uevrUtils.getValid(appearance.boat)
	if boat ~= nil then boat:SetActorHiddenInGame(appearance.hidden) end
	local proxyActor = uevrUtils.getValid(appearance.proxyActor)
	appearance.proxyActor, appearance.proxy = nil, nil
	if proxyActor ~= nil then proxyActor:K2_DestroyActor() end
	appearance.growing = false
end

local function clearBoatAppearance()
	finishBoatAppearance()
	local effect = boatAppearance ~= nil and uevrUtils.getValid(boatAppearance.effect) or nil
	boatAppearance = nil
	if effect ~= nil then effect:K2_DestroyComponent(effect) end
end

local function spawnBoatAppearanceEffect(boat, pos)
	local asset = uevrUtils.getValid(uevrUtils.find_required_object(BOAT_APPEAR_EFFECT))
	if asset == nil then asset = uevrUtils.getLoadedAsset(BOAT_APPEAR_EFFECT) end
	local library = uevrUtils.find_default_instance("Class /Script/Niagara.NiagaraFunctionLibrary")
	if asset == nil or library == nil or not uevrUtils.checkPluginExists() then return nil end
	-- Use the native bridge; direct Niagara spawn calls through sol are unreliable.
	-- World-space placement keeps the swirl independent of the shrinking hull.
	local effectPos = uevrUtils.vector(pos.X, pos.Y, pos.Z + BOAT_APPEAR_EFFECT_HEIGHT)
	local result = plugin.executeFunctionWithOutputs(library, "SpawnSystemAtLocation", {"ReturnValue"},
		boat, asset, effectPos, uevrUtils.rotator(0, 0, 0),
		uevrUtils.vector(BOAT_APPEAR_EFFECT_SCALE, BOAT_APPEAR_EFFECT_SCALE, BOAT_APPEAR_EFFECT_SCALE),
		true, true, 0, false)
	return result ~= nil and uevrUtils.getValid(result.ReturnValue) or nil
end

local function updateBoatAppearanceProxy(appearance, mesh, amount)
	local proxy = uevrUtils.getValid(appearance.proxy)
	if proxy == nil then return false end
	local transform = mesh:K2_GetComponentToWorld()
	local scale = appearance.scale
	transform.Scale3D = uevrUtils.vector(scale.X * amount, scale.Y * amount, scale.Z * amount)
	proxy:K2_SetWorldTransform(transform, false, {}, true)
	return true
end

local function createBoatAppearanceProxy(appearance, mesh)
	-- Animate a separate, collision-free visual. Never resize or disable the
	-- actual hull: its native physics and water state stay at full size.
	appearance.proxyActor = uevrUtils.spawn_actor()
	if appearance.proxyActor == nil then return false end
	local proxy = uevrUtils.create_component_of_class("Class /Script/Engine.StaticMeshComponent",
		true, nil, false, appearance.proxyActor)
	if proxy == nil then return false end
	appearance.proxy = proxy
	proxy:SetHiddenInGame(true)
	proxy:SetCollisionEnabled(0, false)
	if not proxy:SetStaticMesh(mesh.StaticMesh) then return false end
	for index = 0, mesh:GetNumMaterials() - 1 do proxy:SetMaterial(index, mesh:GetMaterial(index)) end
	return updateBoatAppearanceProxy(appearance, mesh, BOAT_APPEAR_MIN_SCALE)
end

local function beginBoatAppearance(boat, mesh, pos, floating)
	clearBoatAppearance()
	local scale = mesh:K2_GetComponentScale()
	boatAppearance = {boat = boat, scale = {X = scale.X, Y = scale.Y, Z = scale.Z},
		hidden = boat.bHidden, elapsed = 0, growing = true, floating = floating,
		nextFloatAttempt = BOAT_FLOAT_SETUP_RETRY}
	local created, proxyReady = pcall(createBoatAppearanceProxy, boatAppearance, mesh)
	if created and proxyReady then
		boat:SetActorHiddenInGame(true)
	else
		finishBoatAppearance()
		print("Boat: growth visual unavailable; using apparition only")
	end
	-- Missing VFX must still leave a usable boat; growth works independently.
	local ok, effect = pcall(spawnBoatAppearanceEffect, boat, pos)
	if ok then boatAppearance.effect = effect end
	if not ok or effect == nil then print("Boat: apparition effect unavailable") end
end

local function tickBoatAppearance(delta)
	local appearance = boatAppearance
	if appearance == nil then return end
	local boat = uevrUtils.getValid(appearance.boat)
	local mesh = boat ~= nil and uevrUtils.getValid(boat.Boat) or nil
	if mesh == nil then clearBoatAppearance(); return end
	-- Pause the reveal along with the game. Engine delta is seconds here.
	if uevrUtils.isGamePaused() then return end
	if not isFiniteNumber(delta) or delta <= 0 then return end
	appearance.elapsed = appearance.elapsed + delta
	if not appearance.floating and appearance.elapsed >= appearance.nextFloatAttempt then
		appearance.floating = enableBoatFloating(boat)
		appearance.nextFloatAttempt = appearance.elapsed + BOAT_FLOAT_SETUP_RETRY
		if not appearance.floating and appearance.elapsed >= BOAT_FLOAT_SETUP_TIMEOUT then
			print("Boat flotation: water registration unavailable")
			appearance.nextFloatAttempt = math.huge
		end
	end
	if appearance.growing then
		local t = math.max(0, math.min(1, (appearance.elapsed - BOAT_APPEAR_DELAY) / BOAT_APPEAR_SECONDS))
		if t >= 1 then
			finishBoatAppearance()
		else
			local amount = BOAT_APPEAR_MIN_SCALE + (1 - BOAT_APPEAR_MIN_SCALE) * t * t * (3 - 2 * t)
			if updateBoatAppearanceProxy(appearance, mesh, amount) then
				if not appearance.proxyVisible and appearance.elapsed >= BOAT_APPEAR_DELAY then
					appearance.proxy:SetHiddenInGame(false)
					appearance.proxyVisible = true
				end
			else
				finishBoatAppearance()
			end
		end
	end
	if not appearance.growing and appearance.elapsed >= BOAT_APPEAR_EFFECT_SECONDS then clearBoatAppearance() end
end

local function placeBoatAt(p, pos, spawnYaw, boat, magical)
	local x, y, z = pos.X, pos.Y, pos.Z

	if boat == nil then
		uevrUtils.getLoadedAsset(BOAT_CLASS)
		spawnedBoat = uevrUtils.spawn_actor_of_class(BOAT_CLASS, uevrUtils.get_transform({X = x, Y = y, Z = z}), 1, nil)
		boat = uevrUtils.getValid(spawnedBoat)
		if boat == nil then
			-- BP_Boat often refuses deferred spawn; reuse a level boat instead.
			boat = findAnyNearestBoat(p)
			spawnedBoat = boat
			if boat == nil then
				print("Failed to spawn boat")
				return
			end
			print("Boat spawn failed; adopting nearest existing boat")
		end
	end
	if not rememberBoat(boat) then return end

	local mesh = uevrUtils.getValid(boat, {"Boat"})
	if mesh ~= nil then
		mesh:SetSimulatePhysics(false)
		-- Reset any beaching tilt and turn the hull broadside to the player.
		local rotation = uevrUtils.rotator(0, spawnYaw, 0)
		mesh:K2_SetWorldRotation(rotation, false, reusable_hit_result, true)
		mesh:K2_SetWorldLocation(pos, false, {}, true)
	end
	boat:K2_SetActorLocation(pos, false, {}, true)

	local floating = enableBoatFloating(boat)
	if magical and mesh ~= nil then
		beginBoatAppearance(boat, mesh, pos, floating)
	end
	return boat, floating
end

function M.placeOrSpawnBoat()
	if seated or (boatAppearance ~= nil and boatAppearance.growing) then return end
	if boatPlacement ~= nil and boatPlacement.purpose == "conjure" then return end
	boatPlacement = nil
	if boatSerialization ~= nil then boatSerialization:dismiss() end
	local p = uevrUtils.getValid(pawn)
	if p == nil then return end
	local boat, recovered = recoverBoat(p)
	if not recovered then return end
	-- Don't shrink the floor under a player who is standing on the hull.
	local hull = boat ~= nil and uevrUtils.getValid(boat.Boat) or nil
	local movement = uevrUtils.getValid(p.CharacterMovement)
	if hull ~= nil and movement ~= nil and movement:GetMovementBase() == hull then
		print("Boat: step ashore before conjuring")
		return
	end
	return beginBoatPlacement(p, "conjure", function(pos, spawnYaw)
		if pos == nil then
			print(string.format("Boat placement: no open water within %gm ahead", BOAT_WATER_MAX_DIST / 100))
			return
		end
		local current, recovered = recoverBoat(p)
		if recovered then return placeBoatAt(p, pos, spawnYaw, current, true) end
	end)
end

local function getAnim(p)
	local mesh = p ~= nil and uevrUtils.getValid(p.Mesh) or nil
	if mesh == nil or mesh.GetAnimInstance == nil then return nil end
	return mesh:GetAnimInstance()
end

local function applySitPose(p, anim)
	anim = anim or getAnim(p)
	if anim == nil then return false end
	local pose = uevrUtils.getLoadedAsset(SIT_POSE)
	if pose == nil then
		pose = uevrUtils.find_required_object(SIT_POSE)
	end
	if pose == nil then
		print("Boat seat: missing sit pose", SIT_POSE)
		return false
	end
	anim.OverridePose = pose
	anim.bUsePoseOverride = true
	return true
end

local function clearSitPose(p)
	local anim = getAnim(p)
	if anim == nil then return end
	anim.bUsePoseOverride = false
	anim.OverridePose = nil
end

local function lockPlayerMovement(p)
	local move = uevrUtils.getValid(p, {"CharacterMovement"})
	if move == nil then return end
	if move.DisableMovement ~= nil then
		move:DisableMovement()
	elseif move.Deactivate ~= nil then
		move:Deactivate()
	end
end

local function restorePlayerMovement(p)
	local move = uevrUtils.getValid(p, {"CharacterMovement"})
	if move == nil then return end
	if move.Activate ~= nil then
		move:Activate(true)
	end
	if move.SetMovementMode ~= nil then
		-- Resume gravity first; native floor/water contact selects walking or swimming.
		move:SetMovementMode(3, 0) -- falling
	end
end

local function stickAxis(value)
	if math.abs(value) < STICK_DEADZONE then return 0 end
	return value / 32767
end

local function approach(current, target, maxDelta)
	local d = target - current
	if d > maxDelta then return current + maxDelta end
	if d < -maxDelta then return current - maxDelta end
	return target
end

local function tickDelta(delta)
	if delta == nil or delta <= 0 then return 0.016 end
	-- Some callbacks report ms.
	if delta > 0.5 then return delta / 1000 end
	return delta
end

-- Apply motor effort before physics. Native contact, buoyancy, and currents
-- resolve the resulting movement; never set the hull transform or velocity.
local function driveBoat(mesh, delta)
	local throttle = stickAxis(stickLY)
	local turn = stickAxis(stickLX)
	if throttle == 0 and turn == 0 and driveSpeed == 0 and driveYaw == 0 then return end
	delta = tickDelta(delta)
	local previousSpeed = driveSpeed
	driveSpeed = approach(driveSpeed, throttle * BOAT_MAX_SPEED, ((throttle ~= 0) and BOAT_ACCEL or BOAT_COAST_DECEL) * delta)
	if driveSpeed ~= 0 or previousSpeed ~= 0 then
		local fwd = mesh:GetForwardVector()
		local length = fwd ~= nil and math.sqrt(fwd.X * fwd.X + fwd.Y * fwd.Y) or 0
		if length > 0.001 then
			-- Offset drag for the motor's commanded speed only. This preserves
			-- acceleration/coasting without cancelling the river's contribution.
			local accel = (driveSpeed - previousSpeed) / delta + mesh:GetLinearDamping() * driveSpeed
			mesh:AddForce(uevrUtils.vector(fwd.X / length * accel, fwd.Y / length * accel, 0), NONE_BONE, true)
		end
	end

	local targetYaw = 0
	if turn ~= 0 then
		local velocity = mesh:GetPhysicsLinearVelocity(NONE_BONE)
		local speed = math.sqrt(velocity.X * velocity.X + velocity.Y * velocity.Y)
		local yawScale = math.max(BOAT_YAW_MIN_SCALE, math.min(1, speed / BOAT_YAW_REF_SPEED))
		targetYaw = turn * BOAT_YAW_RATE * yawScale
	end
	local previousYaw = driveYaw
	driveYaw = approach(driveYaw, targetYaw, BOAT_YAW_ACCEL * delta)
	if driveYaw ~= 0 or previousYaw ~= 0 then
		local accel = (driveYaw - previousYaw) / delta + mesh:GetAngularDamping() * driveYaw
		mesh:AddTorqueInRadians(uevrUtils.vector(0, 0, math.rad(accel)), NONE_BONE, true)
	end
end

local function syncPawnToBoat(p, pawnMesh, boatMesh, attached)
	-- RTS_Actor gives the animated/VR-adjusted hips directly in pawn space.
	local hips = pawnMesh:GetSocketTransform(HIPS_SOCKET, 1)
	local offset = hips and hips.Translation
	if offset == nil then return end
	offset.X, offset.Y, offset.Z = -SEAT_BACK_CM - offset.X, -offset.Y, -offset.Z
	if attached then
		-- The native Station attachment already carries seat rotation and scale.
		p:K2_SetActorRelativeLocation(offset, false, reusable_hit_result, true)
	else
		local xf = boatMesh:GetSocketTransform(BOAT_STATION_SOCKET)
		if xf == nil or mathLib.vectorSizeSquared(xf.Translation) == 0 then return end
		xf.Translation = kismet_math_library:TransformLocation(xf, offset)
		p:K2_SetActorTransform(xf, false, reusable_hit_result, true)
	end
end

local function exitBoatSeat(p)
	seated = false
	local boat = uevrUtils.getValid(seatBoat)
	local mesh = boat ~= nil and uevrUtils.getValid(boat.Boat) or nil
	if p ~= nil and boat ~= nil and p:GetAttachParentActor() == boat then
		p:K2_DetachFromActor(1, 1, 1) -- keep world pose before restoring collision/movement
	end
	if mesh ~= nil then mesh:WakeRigidBody(NONE_BONE) end
	seatBoat = nil
	stickLX, stickLY = 0, 0
	driveSpeed = 0
	driveYaw = 0
	clearSitPose(p)
	if p ~= nil then
		if p.InCinematic ~= nil then
			p.InCinematic = false
		end
		if p.SetActorEnableCollision ~= nil then
			p:SetActorEnableCollision(pawnCollisionWasEnabled)
		end
		restorePlayerMovement(p)
	end
end

local function findNearestBoat(p)
	local boat, recovered = recoverBoat(p)
	if not recovered then return nil end
	local ploc = p:K2_GetActorLocation()
	if boat ~= nil and mathLib.vectorDistanceSquared(ploc, boatNearPoint(boat)) <= BOAT_NEAR_DIST_SQ then
		return boat
	end
	local best, bestD = nil, BOAT_NEAR_DIST_SQ
	for _, b in ipairs(uevrUtils.find_all_of(BOAT_CLASS, false) or {}) do
		if uevrUtils.getValid(b) ~= nil then
			local d = mathLib.vectorDistanceSquared(ploc, boatNearPoint(b))
			if d <= bestD then
				best, bestD = b, d
			end
		end
	end
	if best ~= nil then
		if not rememberBoat(best) then return nil end
	end
	return best
end

local function sitInBoat(p, boat)
	seatBoat = boat
	pawnCollisionWasEnabled = p.GetActorEnableCollision == nil or p:GetActorEnableCollision()
	p:SetActorEnableCollision(false)
	lockPlayerMovement(p)
	if p.InCinematic ~= nil then
		p.InCinematic = false
	end
	local pawnMesh = uevrUtils.getValid(p.Mesh)
	local boatMesh = uevrUtils.getValid(boat.Boat)
	if pawnMesh == nil or boatMesh == nil then
		exitBoatSeat(p)
		return
	end
	syncPawnToBoat(p, pawnMesh, boatMesh)
	if not applySitPose(p) then
		exitBoatSeat(p)
		return
	end
	-- Follow the simulated hull during physics, before the game's camera update.
	-- Keep world pose and leave the bodies unwelded; post-tick sync adjusts hips.
	p:K2_AttachToComponent(boatMesh, BOAT_STATION_SOCKET, 1, 1, 1, false)
	if p:GetAttachParentActor() ~= boat then
		print("Boat seat: could not attach to hull")
		exitBoatSeat(p)
		return
	end
	seated = true
	return true
end

function M.sitOrStandBoat()
	if boatAppearance ~= nil and boatAppearance.growing then return end
	boatPlacement = nil
	if boatSerialization ~= nil then boatSerialization:dismiss() end
	local p = uevrUtils.getValid(pawn)
	if p == nil then return end
	if seated and uevrUtils.getValid(seatBoat) ~= nil then
		exitBoatSeat(p)
		return true
	end
	local boat = findNearestBoat(p)
	if boat ~= nil then
		-- Snap to black (FromAlpha is already ~1) and hold, then reveal.
		uevrUtils.fadeCamera(BOAT_SEAT_FADE_SECONDS, true)
		delay(BOAT_SEAT_FADE_SECONDS * 1000, function()
			uevrUtils.fadeCamera(BOAT_SEAT_FADE_SECONDS, false, false, true, false, 0)
		end)
		return sitInBoat(p, boat)
	end
end

function M.reset()
	boatPlacement = nil
	clearBoatAppearance()
	local p = uevrUtils.getValid(pawn)
	if seated then
		exitBoatSeat(p)
	else
		seatBoat = nil
		seated = false
		stickLX, stickLY = 0, 0
		driveSpeed = 0
		driveYaw = 0
		clearSitPose(p)
		if p ~= nil and p.InCinematic ~= nil then
			p.InCinematic = false
		end
	end
	-- Actor tags outlive this Lua state; recover the reference on the next F3/F4.
	spawnedBoat = nil
	boatButtonWasPressed = false
	boatButtonConsumed = false
end

local function finitePoint(point)
	return type(point) == "table" and isFiniteNumber(point.X) and
		isFiniteNumber(point.Y) and isFiniteNumber(point.Z)
end

local function currentCharacterId()
	local data = uevrUtils.find_first_of("Class /Script/PersistentData.PersistentData", false)
	return data ~= nil and data:GetCurrentPlayerID() or nil
end

local function captureBoatState()
	local p = uevrUtils.getValid(uevr.api:get_local_pawn(0))
	local world = uevrUtils.getValid(uevrUtils.get_world())
	if p == nil or world == nil then return nil end
	if not seated then return {seated = false} end
	local boat = uevrUtils.getValid(seatBoat)
	local mesh = boat ~= nil and uevrUtils.getValid(boat.Boat) or nil
	if mesh == nil then return {seated = false} end
	local loc, rot = mesh:K2_GetComponentLocation(), mesh:K2_GetComponentRotation()
	local ploc = p:K2_GetActorLocation()
	-- Disabled seated movement does not refresh the game's safe-spawn cache.
	-- Update it before native save collection so loading uses this position.
	p:RecordSafeLocation()
	return {seated = true, world = world:get_fname():to_string(), character = currentCharacterId(),
		boat = {X = loc.X, Y = loc.Y, Z = loc.Z}, yaw = rot.Yaw, damping = mesh:GetLinearDamping(),
		pawn = {X = ploc.X, Y = ploc.Y, Z = ploc.Z}}
end

local function validateBoatState(record)
	if type(record.seated) ~= "boolean" then return false end
	if not record.seated then return true end
	return finitePoint(record.boat) and finitePoint(record.pawn) and isFiniteNumber(record.yaw) and
		type(record.world) == "string" and type(record.character) == "number" and
		isFiniteNumber(record.damping) and record.damping >= 0 and record.damping <= 100 and
		mathLib.vectorDistanceSquared(record.boat, record.pawn) <= 1000 * 1000
end

local function restoreBoatState(record, p)
	local world = uevrUtils.getValid(uevrUtils.get_world())
	if world == nil or world:get_fname():to_string() ~= record.world or currentCharacterId() ~= record.character then return false end
	if uevrUtils.getValid(p.Mesh) == nil or getAnim(p) == nil then return false end
	local boat, recovered = recoverBoat(p)
	if not recovered then return false end
	-- The game's saved spawn may lag behind a seated pawn. Restore on safe
	-- water near the loaded pawn, using the same placement checks as F3.
	local search = boatPlacement
	if search == nil then search = beginBoatPlacement(p, "restore") end
	if search.purpose ~= "restore" or search.pawn ~= p or not search.done then return false end
	boatPlacement = nil
	if mathLib.vectorDistanceSquared(p:K2_GetActorLocation(), search.origin) > 100 * 100 then return false end
	local pos, spawnYaw = search.pos, search.yaw
	if pos == nil then return false end
	local floating
	boat, floating = placeBoatAt(p, pos, spawnYaw, boat)
	if boat == nil then return false end
	local mesh = uevrUtils.getValid(boat.Boat)
	if mesh == nil then return false end
	if not floating then mesh:SetSimulatePhysics(false); return false end
	if not sitInBoat(p, boat) then return false end
	return true
end

-- Use the shared profiler's toggle/report controls. Nested timings are inclusive.
resumeBoatPlacement = uevrUtils.profiler:wrap("Boats: water placement", resumeBoatPlacement)
configureBoatWater = uevrUtils.profiler:wrap("Boats: water registration", configureBoatWater)
tickBoatAppearance = uevrUtils.profiler:wrap("Boats: appearance", tickBoatAppearance)
driveBoat = uevrUtils.profiler:wrap("Boats: propulsion", driveBoat)
syncPawnToBoat = uevrUtils.profiler:wrap("Boats: seat alignment", syncPawnToBoat)
captureBoatState = uevrUtils.profiler:wrap("Boats: save capture", captureBoatState)
restoreBoatState = uevrUtils.profiler:wrap("Boats: load restoration", restoreBoatState)
serialization.read = uevrUtils.profiler:wrap("Serialization: read", serialization.read)
serialization.write = uevrUtils.profiler:wrap("Serialization: write", serialization.write)
serialization.poll = uevrUtils.profiler:wrap("Serialization: load polling", serialization.poll)

boatSerialization = serialization.new({owner = "HL_UEVR.Boats", version = 1, restoreInterval = 1,
	capture = captureBoatState, validate = validateBoatState,
	shouldRestore = function(record) return record.seated end,
	restore = restoreBoatState, beforeLoad = M.reset})
boatSerialization:start()

-- Read physical X before spell/stick remaps can synthesize button presses.
uevrUtils.registerOnPreInputGetStateCallback(function(retval, user_index, state)
	if user_index ~= 0 then return end
	local pressed = uevrUtils.isButtonPressed(state, XINPUT_GAMEPAD_X)
	local justPressed = pressed and not boatButtonWasPressed
	boatButtonWasPressed = pressed
	if not pressed then
		boatButtonConsumed = false
		return
	end
	if justPressed and not ui.isRemapDisabled() and not uevrUtils.isGamePaused() and not uevrUtils.isInCutscene() then
		boatButtonConsumed = M.sitOrStandBoat() == true
	end
	-- Consume the entire hold, including the press that exits the boat.
	if boatButtonConsumed then
		uevrUtils.unpressButton(state, XINPUT_GAMEPAD_X)
	end
end, 30)

uevr.sdk.callbacks.on_xinput_get_state(function(retval, user_index, state)
	if not seated then return end
	stickLX = state.Gamepad.sThumbLX
	stickLY = state.Gamepad.sThumbLY
	-- Tank steer on the boat; don't let game locomotion strafe/turn the pawn.
	state.Gamepad.sThumbLX = 0
	state.Gamepad.sThumbLY = 0
end)

local function tickSeatedBoat(engine, delta)
	if uevrUtils.isGamePaused() or uevrUtils.isInCutscene() then return end
	local p = uevrUtils.getValid(pawn)
	local boat = uevrUtils.getValid(seatBoat)
	if p == nil or boat == nil then
		exitBoatSeat(p)
		return
	end
	if p.InCinematic then
		p.InCinematic = false
	end
	local anim = getAnim(p)
	if anim ~= nil and not anim.bUsePoseOverride then
		applySitPose(p, anim)
	end
	-- With no motor/rudder effort, leave the drifting hull entirely to physics.
	if driveSpeed == 0 and driveYaw == 0 and math.abs(stickLX) < STICK_DEADZONE and
		math.abs(stickLY) < STICK_DEADZONE then return end
	local mesh = uevrUtils.getValid(boat.Boat)
	if mesh ~= nil then driveBoat(mesh, delta) end
end
tickSeatedBoat = uevrUtils.profiler:wrap("Boats: seated pre tick", tickSeatedBoat)

uevr.sdk.callbacks.on_pre_engine_tick(function(engine, delta)
	if not seated then return end
	tickSeatedBoat(engine, delta)
end)

-- Follow the hull after physics has resolved propulsion, buoyancy, and contact.
local function tickSeatedPawn()
	local p = uevrUtils.getValid(pawn)
	local boat = uevrUtils.getValid(seatBoat)
	if p == nil or boat == nil then return end
	-- Relative seat offsets are valid only while this attachment still exists.
	if p:GetAttachParentActor() ~= boat then exitBoatSeat(p); return end
	-- Resolve and validate each component once for this tick; never retain them
	-- across level changes, pawn replacement, or garbage collection.
	local boatMesh = uevrUtils.getValid(boat.Boat)
	local pawnMesh = uevrUtils.getValid(p.Mesh)
	if boatMesh == nil or pawnMesh == nil then return end
	syncPawnToBoat(p, pawnMesh, boatMesh, true)
end
tickSeatedPawn = uevrUtils.profiler:wrap("Boats: seated post tick", tickSeatedPawn)

uevr.sdk.callbacks.on_post_engine_tick(function(engine, delta)
	if boatPlacement ~= nil and not boatPlacement.done then tickBoatPlacement() end
	if boatAppearance ~= nil then tickBoatAppearance(delta) end
	if not seated then return end
	tickSeatedPawn()
end)

uevr.params.sdk.callbacks.on_script_reset(function()
	boatSerialization:stop()
	M.reset()
end)

uevrUtils.registerLevelChangeCallback(M.reset)

return M
