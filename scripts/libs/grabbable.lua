--[[
Usage
    Drop the libs folder containing this file into your project folder
    Add code like this in your script:
        local grabbable = require("libs/grabbable")

    Lets a VR hand grab world items. A grip flies the item into the hand, it is carried while the grip is held, and releasing
    throws it with the hand's velocity (or drops it), or collects it when released during a collect gesture. The game-specific
    parts (what can be grabbed, what the game currently offers to interact with, how it collects) are supplied as callbacks.

    How holding works
        Item meshes may refuse attachment, so the real item is never attached. When a grab starts, a hidden copy of the item's
        static mesh (with its materials) is created and exposed through getHeldMesh(); the mod's attachments grip update callback
        attaches it like any other hand attachment, so its transform is configured per item in the attachments UI. The real item
        flies to the copy's live transform (location, rotation and scale) and is then hidden while the copy is shown. Releasing
        puts the real item back at the copy's transform, where it falls under gravity and eases back to its own size. The fall is
        kinematic (swept steps with the gravity option) unless grabbable.useRealPhysics(true) is set; then the released item simulates
        physics, starting with the throw velocity.

    Grip arbitration
        Uses libs/grip. Each grabbable registers a start claim under its name: claimPriority when a starting press would grab or
        interact, and heldPriority when an item is already flying or held (so toggle mode presses keep going to it). It only acts on
        presses it owns, and grip.lua hides owned presses from the game for the whole press. Other systems take precedence over it
        by claiming above claimPriority (e.g. an open menu), or by returning false from canClaim.

    Available functions:

    grabbable.new(options) -> Grabbable
        options:
            name: string (default "grabbable") - owner name used in grip claims
            claimPriority: number (default grip.NORMAL) - grip claim for a press that would grab or interact
            heldPriority: number (default 200) - grip claim for a press while an item is flying or held
            hand: Handed (default Handed.Left)
            gripButton: XINPUT button (default the hand's shoulder button)
            isGrabbable: function(actor) -> boolean (required)
            canClaim: function(state) -> boolean (optional)
                Return false to leave a starting grip to something else (e.g. head gestures).
            getInteractTarget: function(state) -> actor|nil (optional)
                The game's current interaction target (e.g. what its prompt is on). A grip on a grabbable target grabs it;
                any other target gets interactButton held for as long as the grip.
            interactButton: XINPUT button (optional)
            isCollectGesture: function(state) -> boolean (optional)
                Checked every frame while carrying; releasing the grip during the gesture collects the item.
            collectButton: XINPUT button (optional)
                Pressed for collectFrames on a collect release. The game is expected to collect (destroy) the item within
                collectTimeout seconds, otherwise it is dropped.
            collectFrames: number (default 6)
            collectTimeout: seconds (default 0.5)
            toggleGrip: boolean (default false)
                Dev: the grip toggles (press to grab, the item stays after release, press again to collect or drop), for
                adjusting attachment transforms hands-free. No throwing in this mode.
            pointing: table (optional) - choose items by pointing the palm at them instead of by interaction target
                enabled: boolean
                highlight: function(actor, on) (optional)
                shouldScan: function() -> boolean (optional) - gate for the overlap scan, which goes through the plugin bridge
                objectTypes: {EObjectTypeQuery} (default {1, 3}: WorldDynamic, PhysicsBody)
                maxDistance: cm (default 400)
                selectAngle: degrees (default 15) - cone around the palm axis that selects an item
                keepAngle: degrees (default 20) - wider cone that keeps the current item selected
                switchMargin: cosine (default 0.02) - another item must be this much closer to the palm axis to take over
                palmSign: 1|-1 (default 1) - the palm faces along the controller's right vector times palmSign
                scanInterval: ms (default 250)
            flightTime: seconds (default 0.4)
            arcHeight: cm (default 15)
            sampleHistory: seconds of hand positions kept while carrying (default 0.2)
            throwWindow: seconds of hand movement measured for a throw (default 0.06)
            throwScale: (default 1.3) - VR throws feel weak at the hand's raw speed
            throwMinSpeed: cm/s (default 100) - slower releases just drop
            throwMaxSpeed: cm/s (default 1500)
            gravity: cm/s^2 (default 980)
            maxFallDistance: cm (default 1000)
            floorNormalZ: (default 0.7) - a hit surface whose normal points at least this far up counts as ground
            dropRescaleTime: seconds (default 0.5) - time a released item takes to ease back to its own size

    grabbable.useRealPhysics(value)
        true: released items simulate physics (engine gravity, bouncing, tumbling) instead of the kinematic fall. Default false.
        The gravity, maxFallDistance and floorNormalZ options only apply to the kinematic fall.

    Grabbable:setEnabled(value)
        Disabling drops anything held where it is and removes any highlight.
    Grabbable:isEnabled() -> boolean
    Grabbable:getHeldMesh() -> component|nil
        The copy to attach to the hand, from the start of a grab (hidden during the flight).
    Grabbable:isHolding() -> boolean
        True while an item is in the hand, and for the rest of a grip press that grabbed, collected or dropped one.
    Grabbable:reset()
        Also runs on level change and script reset.
]]

local uevrUtils = require("libs/uevr_utils")
local controllers = require("libs/controllers")
local attachments = require("libs/attachments")
local plugin = require("libs/core/plugin")
local grip = require("libs/grip")

local M = {}

local realPhysics = false

-- true: released items are handed to the physics engine (SetSimulatePhysics) instead of the built-in kinematic fall.
function M.useRealPhysics(value)
	realPhysics = value == true
end

local Grabbable = {}
Grabbable.__index = Grabbable

local function default(value, fallback)
	if value == nil then return fallback end
	return value
end

-- A collected item stays valid while the game destroys it, so being destroyed counts as gone.
local function getLiveActor(actor)
	actor = uevrUtils.getValid(actor)
	if actor == nil or actor.bActorIsBeingDestroyed then return nil end
	return actor
end

local function canGrab(self, actor)
	return actor ~= nil and not actor.bActorIsBeingDestroyed and self.isGrabbable(actor) == true
end

------------------- Palm pointing -------------------
-- Self-contained: pointing the palm at a grabbable item highlights it, and a grip grabs it. Candidates come from an overlap
-- scan around the hand. Everything outside this block reaches it only through getSelected, clearPointing, scanPointing and
-- updatePointing.
local actorClass = nil

local function selectItem(self, actor)
	local pointing = self.pointing
	if actor == pointing.selected then return end
	if pointing.highlight ~= nil then
		if uevrUtils.getValid(pointing.selected) ~= nil then pointing.highlight(pointing.selected, false) end
		if actor ~= nil then pointing.highlight(actor, true) end
	end
	pointing.selected = actor
end

-- The highlighted item a grip should grab, or nil.
local function getSelected(self)
	return self.pointing.enabled and self.pointing.selected or nil
end

-- Removes the highlight and forgets the candidates (a grab started, or the grabbable stopped).
local function clearPointing(self)
	selectItem(self, nil)
	self.pointing.candidates = {}
end

-- Finds grabbable items around the hand. Runs on the scan interval, and only while nothing is flying or held.
local function scanPointing(self)
	local pointing = self.pointing
	if not pointing.enabled or not self.enabled or self.flight ~= nil or self.held ~= nil or uevrUtils.getValid(pawn) == nil
		or (pointing.shouldScan ~= nil and not pointing.shouldScan()) then
		pointing.candidates = {}
		return
	end
	local hand = controllers.getControllerLocation(self.hand)
	if hand == nil then
		pointing.candidates = {}
		return
	end
	actorClass = actorClass or uevrUtils.get_class("Class /Script/Engine.Actor")
	-- SphereOverlapActors takes and returns TArrays, which native Lua does not marshal, so it goes through the plugin bridge.
	local result = plugin.executeFunction(kismet_system_library, "SphereOverlapActors", uevrUtils.get_world(), hand, pointing.maxDistance, pointing.objectTypes, actorClass, {pawn}, {})
	local found = {}
	for _, actor in ipairs(result and result.OutActors or {}) do
		if canGrab(self, actor) then found[#found + 1] = actor end
	end
	pointing.candidates = found
end
scanPointing = uevrUtils.profiler:wrap("Grabbable: pointing scan", scanPointing)

-- Highlights the candidate closest to the palm axis. Runs every tick while nothing is flying or held.
local function updatePointing(self)
	local pointing = self.pointing
	if not pointing.enabled then return end
	if #pointing.candidates == 0 then
		selectItem(self, nil)
		return
	end
	local hand = controllers.getControllerLocation(self.hand)
	local palm = controllers.getControllerRightVector(self.hand)
	if hand == nil or palm == nil then return end
	local best, bestCos, currentCos = nil, pointing.selectCos, nil
	for _, actor in ipairs(pointing.candidates) do
		if uevrUtils.getValid(actor) ~= nil then
			local loc = actor:K2_GetActorLocation()
			local dx, dy, dz = loc.X - hand.X, loc.Y - hand.Y, loc.Z - hand.Z
			local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
			if distance > 1 and distance <= pointing.maxDistance then
				local cos = (dx * palm.X + dy * palm.Y + dz * palm.Z) * pointing.palmSign / distance
				if actor == pointing.selected then currentCos = cos end
				if cos >= bestCos then best, bestCos = actor, cos end
			end
		end
	end
	-- Keep the current item inside the wider cone unless another is clearly closer to the palm axis, so items side by side don't flicker.
	if currentCos ~= nil and currentCos >= pointing.keepCos and (best == nil or bestCos < currentCos + pointing.switchMargin) then
		best = pointing.selected
	end
	selectItem(self, best)
end
------------------- End palm pointing -------------------

-- Ends a flight or a hold: removes the copy from the hand and gives the real item back its visibility, collision and size.
-- An item in the hand is first put at the copy's transform. With dropToGround it then falls from where it is, moving with the
-- optional throw velocity and easing back to its own size. With useRealPhysics the engine moves it instead, starting with the throw
-- velocity.
local function clearHeld(self, updateGrip, dropToGround, velocity)
	local copy = uevrUtils.getValid(self.copy)
	if copy == nil then return end
	local actor = getLiveActor(self.heldActor)
	if actor ~= nil then
		local scale = self.heldScale
		local inHand = self.held ~= nil and copy ~= nil
		local simulate = dropToGround and realPhysics
		if inHand then
			local location, rotation = copy:K2_GetComponentLocation(), copy:K2_GetComponentRotation()
			actor:K2_SetActorLocationAndRotation(uevrUtils.vector(location.X, location.Y, location.Z), uevrUtils.rotator(rotation.Pitch, rotation.Yaw, rotation.Roll), false, reusable_hit_result, true)
		end
		if dropToGround and scale ~= nil then
			local from = inHand and copy:K2_GetComponentScale() or actor:GetActorScale3D()
			local fromScale = uevrUtils.vector(from.X, from.Y, from.Z)
			actor:SetActorScale3D(fromScale)
			local location = actor:K2_GetActorLocation()
			-- With real physics the engine moves the item, so its entry only eases the size back (it starts out landed).
			self.falling[#self.falling + 1] = {actor = actor, x = location.X, y = location.Y, z = location.Z, minZ = location.Z - self.maxFallDistance,
				vx = velocity and velocity.x or 0, vy = velocity and velocity.y or 0, vz = velocity and velocity.z or 0,
				fromScale = fromScale, toScale = scale, elapsed = 0, landed = simulate or nil}
			scale = nil -- the fall eases it back
		end
		if scale ~= nil then actor:SetActorScale3D(scale) end
		actor:SetActorHiddenInGame(false)
		local mesh = uevrUtils.getValid(actor, {"RootComponent"})
		if mesh ~= nil and self.heldCollision ~= nil then mesh:SetCollisionEnabled(self.heldCollision) end
		if mesh ~= nil and simulate then
			mesh:SetSimulatePhysics(true)
			if dropToGround and velocity ~= nil then
				mesh:SetPhysicsLinearVelocity(uevrUtils.vector(velocity.x, velocity.y, velocity.z), false, uevrUtils.fname_from_string(""))
			end
		end
	end
	self.flight, self.held, self.copy, self.heldActor, self.heldCollision, self.heldScale = nil, nil, nil, nil, nil, nil
	self.collectDeadline, self.handSamples = nil, {}
	-- Let the grip update detach the copy before it is destroyed.
	if copy ~= nil and updateGrip then attachments.forceGripUpdate() end
	if copy ~= nil then uevrUtils.destroyComponent(copy, true) end
end

-- The copy is made and attached to the hand, hidden, when the grab starts, so the real item can fly to the copy's transform
-- (including its attachment config scale) and be swapped for it on arrival.
local function startFlight(self, actor)
	local mesh = uevrUtils.getValid(actor, {"RootComponent"})
	if mesh == nil or mesh.StaticMesh == nil then return end
	-- An item caught while still falling stops falling, and its own size is the one it was easing back to.
	local ownScale = nil
	for i = #self.falling, 1, -1 do
		if self.falling[i].actor == actor then
			ownScale = self.falling[i].toScale
			table.remove(self.falling, i)
		end
	end
	local copy = uevrUtils.createStaticMeshComponent(mesh.StaticMesh, {visible = false, collisionEnabled = false})
	if copy == nil then return end
	for i = 0, mesh:GetNumMaterials() - 1 do copy:SetMaterial(i, mesh:GetMaterial(i)) end
	copy:SetVisibility(false, true)
	local location, rotation, scale = actor:K2_GetActorLocation(), actor:K2_GetActorRotation(), actor:GetActorScale3D()
	self.copy, self.heldActor, self.heldCollision = copy, actor, mesh:GetCollisionEnabled()
	self.handSamples, self.collectDeadline = {}, nil
	self.heldScale = ownScale or uevrUtils.vector(scale.X, scale.Y, scale.Z)
	mesh:SetCollisionEnabled(ECollisionEnabled.NoCollision)
	self.flight = {actor = actor, elapsed = 0, location = uevrUtils.vector(location.X, location.Y, location.Z),
		rotation = uevrUtils.rotator(rotation.Pitch, rotation.Yaw, rotation.Roll), scale = uevrUtils.vector(scale.X, scale.Y, scale.Z)}
	attachments.forceGripUpdate()
	if copy.AttachParent == nil then clearHeld(self, true) end
end

-- Moves the real item from where it was toward the hidden copy's current transform, then swaps them.
local function updateFlight(self, delta)
	local flight = self.flight
	local copy = uevrUtils.getValid(self.copy)
	if getLiveActor(flight.actor) == nil or copy == nil then
		clearHeld(self, true)
		return
	end
	flight.elapsed = flight.elapsed + delta
	local t = math.min(flight.elapsed / self.flightTime, 1)
	local eased = t * t * (3 - 2 * t)
	local toLocation, toRotation, toScale = copy:K2_GetComponentLocation(), copy:K2_GetComponentRotation(), copy:K2_GetComponentScale()
	local s, sc = flight.location, flight.scale
	local location = uevrUtils.vector(s.X + (toLocation.X - s.X) * eased, s.Y + (toLocation.Y - s.Y) * eased, s.Z + (toLocation.Z - s.Z) * eased + math.sin(math.pi * t) * self.arcHeight)
	flight.actor:K2_SetActorLocationAndRotation(location, kismet_math_library:RLerp(flight.rotation, toRotation, eased, true), false, reusable_hit_result, true)
	flight.actor:SetActorScale3D(uevrUtils.vector(sc.X + (toScale.X - sc.X) * eased, sc.Y + (toScale.Y - sc.Y) * eased, sc.Z + (toScale.Z - sc.Z) * eased))
	if t >= 1 then
		flight.actor:SetActorHiddenInGame(true)
		copy:SetVisibility(true, true)
		self.flight, self.held = nil, copy
	end
end

-- Released items move under gravity and ease back to their own size. Each step is swept with the item's own collision, so it
-- stops on whatever it would rest on (a Visibility trace misses some terrain and lets items fall through it).
local function updateFalling(self, delta)
	for i = #self.falling, 1, -1 do
		local fall = self.falling[i]
		local actor = getLiveActor(fall.actor)
		local done = actor == nil
		if actor ~= nil then
			if not fall.landed then
				fall.vz = fall.vz - self.gravity * delta
				local x, y, z = fall.x + fall.vx * delta, fall.y + fall.vy * delta, math.max(fall.z + fall.vz * delta, fall.minZ)
				actor:K2_SetActorLocation(uevrUtils.vector(x, y, z), true, reusable_hit_result, false)
				if reusable_hit_result.bBlockingHit then
					local location = actor:K2_GetActorLocation()
					x, y, z = location.X, location.Y, location.Z
					local normalZ = reusable_hit_result.ImpactNormal.Z
					-- A floor (or starting inside something) ends the fall; a wall stops the sideways motion and a ceiling the upward motion.
					if reusable_hit_result.bStartPenetrating or normalZ > self.floorNormalZ then
						fall.landed = true
					else
						fall.vx, fall.vy = 0, 0
						if normalZ < 0 and fall.vz > 0 then fall.vz = 0 end
					end
				end
				fall.x, fall.y, fall.z = x, y, z
				if z <= fall.minZ then fall.landed = true end
			end
			fall.elapsed = fall.elapsed + delta
			local t = math.min(fall.elapsed / self.dropRescaleTime, 1)
			local a, b = fall.fromScale, fall.toScale
			actor:SetActorScale3D(uevrUtils.vector(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t, a.Z + (b.Z - a.Z) * t))
			done = fall.landed and t >= 1
		end
		if done then table.remove(self.falling, i) end
	end
end

-- Puts items that are still falling on their ground at once, with one sweep down to where they would stop, at their own size.
local function landFalling(self)
	for _, fall in ipairs(self.falling) do
		local actor = getLiveActor(fall.actor)
		if actor ~= nil then
			if not fall.landed then actor:K2_SetActorLocation(uevrUtils.vector(fall.x, fall.y, fall.minZ), true, reusable_hit_result, false) end
			actor:SetActorScale3D(fall.toScale)
		end
	end
	self.falling = {}
end

-- Recent hand positions while an item is carried, for the throw velocity at release.
local function sampleHand(self)
	local hand = controllers.getControllerLocation(self.hand)
	if hand == nil then return end
	local samples = self.handSamples
	samples[#samples + 1] = {t = self.clock, x = hand.X, y = hand.Y, z = hand.Z}
	while self.clock - samples[1].t > self.sampleHistory do table.remove(samples, 1) end
end

-- Throw velocity from the hand's movement over about throwWindow; nil for a gentle release, which just drops.
local function getThrowVelocity(self)
	local samples = self.handSamples
	local last, first = samples[#samples], nil
	if last == nil then return nil end
	for i = #samples - 1, 1, -1 do
		first = samples[i]
		if last.t - first.t >= self.throwWindow then break end
	end
	local dt = first ~= nil and last.t - first.t or 0
	if dt <= 0 then return nil end
	local scale = self.throwScale
	local vx, vy, vz = (last.x - first.x) / dt * scale, (last.y - first.y) / dt * scale, (last.z - first.z) / dt * scale
	local speed = math.sqrt(vx * vx + vy * vy + vz * vz)
	if speed < self.throwMinSpeed then return nil end
	local k = math.min(1, self.throwMaxSpeed / speed)
	return {x = vx * k, y = vy * k, z = vz * k}
end

-- Collects the carried item during the collect gesture, otherwise throws it with the given velocity (or drops it when nil).
local function releaseItem(self, atCollect, velocity)
	if self.held ~= nil and atCollect and self.collectButton ~= nil then
		self.collectFrames = self.collectFramesTotal
		self.collectDeadline = self.clock + self.collectTimeout
	else
		clearHeld(self, true, true, velocity)
	end
end

-- The item a starting grip would grab or interact with, or nil. Remembered for the input callback that acts on the claim.
local function getClaimTarget(self, state)
	self.claimTarget = nil
	if not self.enabled or (self.canClaim ~= nil and not self.canClaim(state)) then return nil end
	local target = getSelected(self)
	if target == nil and self.getInteractTarget ~= nil then
		target = self.getInteractTarget(state)
		-- Without an interact button, only a grabbable target is worth claiming the grip for.
		if target ~= nil and self.interactButton == nil and (self.pointing.enabled or not canGrab(self, target)) then target = nil end
	end
	self.claimTarget = target
	return target
end

-- Hold to carry: a grip grabs the item, and it is carried while the grip is held. Releasing during the collect gesture collects it;
-- releasing anywhere else throws it with the hand's velocity, or drops it if the hand is nearly still. A grip on an interaction
-- target that is not grabbed holds interactButton for as long as the grip.
local function onInput(self, state)
	local pressed = uevrUtils.isButtonPressed(state, self.gripButton)
	local carrying = self.flight ~= nil or (self.held ~= nil and self.collectDeadline == nil)
	if pressed and not self.gripWasPressed then
		if self.toggleGrip and carrying then
			-- Dev toggle mode: the next press collects (during the collect gesture) or drops.
			releaseItem(self, self.isCollectGesture ~= nil and self.isCollectGesture(state), nil)
			self.gripLatched = true
		elseif not carrying and self.held == nil and grip.isOwner(self.hand, self.name) and self.claimTarget ~= nil then
			local target, selected = self.claimTarget, getSelected(self)
			if selected ~= nil then
				clearPointing(self)
				startFlight(self, selected)
			elseif not self.pointing.enabled and canGrab(self, target) then
				startFlight(self, target)
			else
				self.interacting = true
			end
			self.gripLatched = true
		end
	elseif pressed and carrying then
		-- The grip is already up at release, so remember each frame whether the collect gesture is being made.
		self.atCollect = self.isCollectGesture ~= nil and self.isCollectGesture(state) == true
	elseif not pressed and self.gripWasPressed and carrying and not self.toggleGrip then
		releaseItem(self, self.atCollect, getThrowVelocity(self))
	end
	if not pressed then self.gripLatched, self.atCollect, self.interacting = nil, nil, nil end
	self.gripWasPressed = pressed
	if self.interacting and self.interactButton ~= nil then uevrUtils.pressButton(state, self.interactButton) end
	if self.collectFrames ~= nil then
		uevrUtils.pressButton(state, self.collectButton)
		self.collectFrames = self.collectFrames > 1 and self.collectFrames - 1 or nil
	end
end

local function onTick(self, delta)
	self.clock = self.clock + delta
	if #self.falling > 0 then updateFalling(self, delta) end
	if self.flight ~= nil then
		sampleHand(self)
		updateFlight(self, delta)
	elseif self.held ~= nil then
		sampleHand(self)
		-- The real item can be destroyed while its copy is held (e.g. collected); drop the copy too.
		if uevrUtils.getValid(self.held) == nil or getLiveActor(self.heldActor) == nil then
			clearHeld(self, true)
		elseif self.collectDeadline ~= nil and self.clock >= self.collectDeadline then
			-- The collect press went to something else; drop the item instead.
			clearHeld(self, true, true)
		end
	else
		updatePointing(self)
	end
end

function M.new(options)
	options = options or {}
	local hand = default(options.hand, Handed.Left)
	local pointingOptions = options.pointing or {}
	local self = setmetatable({
		name = default(options.name, "grabbable"),
		claimPriority = default(options.claimPriority, grip.NORMAL),
		heldPriority = default(options.heldPriority, 200),
		hand = hand,
		gripButton = default(options.gripButton, hand == Handed.Right and XINPUT_GAMEPAD_RIGHT_SHOULDER or XINPUT_GAMEPAD_LEFT_SHOULDER),
		isGrabbable = options.isGrabbable or function() return false end,
		canClaim = options.canClaim,
		getInteractTarget = options.getInteractTarget,
		interactButton = options.interactButton,
		isCollectGesture = options.isCollectGesture,
		collectButton = options.collectButton,
		collectFramesTotal = default(options.collectFrames, 6),
		collectTimeout = default(options.collectTimeout, 0.5),
		toggleGrip = options.toggleGrip == true,
		flightTime = default(options.flightTime, 0.4),
		arcHeight = default(options.arcHeight, 15),
		sampleHistory = default(options.sampleHistory, 0.2),
		throwWindow = default(options.throwWindow, 0.06),
		throwScale = default(options.throwScale, 1.3),
		throwMinSpeed = default(options.throwMinSpeed, 100),
		throwMaxSpeed = default(options.throwMaxSpeed, 1500),
		gravity = default(options.gravity, 980),
		maxFallDistance = default(options.maxFallDistance, 1000),
		floorNormalZ = default(options.floorNormalZ, 0.7),
		dropRescaleTime = default(options.dropRescaleTime, 0.5),
		pointing = {
			enabled = pointingOptions.enabled == true,
			highlight = pointingOptions.highlight,
			shouldScan = pointingOptions.shouldScan,
			objectTypes = default(pointingOptions.objectTypes, {1, 3}),
			maxDistance = default(pointingOptions.maxDistance, 400),
			selectCos = math.cos(math.rad(default(pointingOptions.selectAngle, 15))),
			keepCos = math.cos(math.rad(default(pointingOptions.keepAngle, 20))),
			switchMargin = default(pointingOptions.switchMargin, 0.02),
			palmSign = default(pointingOptions.palmSign, 1),
			candidates = {},
		},
		enabled = false,
		falling = {},
		handSamples = {},
		clock = 0,
	}, Grabbable)

	-- Start claim (libs/grip): grip.lua hides an owned press from the game for the whole press.
	grip.registerClaim(self.name, function(claimHand, state, press)
		if claimHand ~= self.hand then return nil end
		if self.flight ~= nil or self.held ~= nil then return self.heldPriority end
		if getClaimTarget(self, state) ~= nil then return self.claimPriority end
		return nil
	end)
	uevrUtils.registerOnPreInputGetStateCallback(function(retval, userIndex, state) onInput(self, state) end)
	uevrUtils.registerPostEngineTickCallback(function(engine, delta) onTick(self, delta) end)
	if self.pointing.enabled then
		uevrUtils.setInterval(default(pointingOptions.scanInterval, 250), function() scanPointing(self) end)
	end
	-- Rebuilding the hands hides everything attached to them; show the copy again when it is reattached.
	attachments.registerAttachmentChangeCallback(function(id, gripHand, attachment)
		if attachment ~= nil and attachment == self.held then attachment:SetVisibility(true, true) end
	end)
	uevrUtils.registerLevelChangeCallback(function() self:reset() end)
	uevr.params.sdk.callbacks.on_script_reset(function() self:reset() end)
	return self
end

function Grabbable:setEnabled(value)
	self.enabled = value == true
	if self.enabled then return end
	clearPointing(self)
	clearHeld(self, true)
	landFalling(self)
end

function Grabbable:isEnabled()
	return self.enabled
end

function Grabbable:getHeldMesh()
	return uevrUtils.getValid(self.copy)
end

function Grabbable:isHolding()
	return self.held ~= nil or self.gripLatched == true
end

function Grabbable:reset()
	clearPointing(self)
	clearHeld(self, false)
	landFalling(self)
	self.collectFrames, self.gripLatched, self.atCollect, self.interacting, self.claimTarget = nil, nil, nil, nil, nil
end

return M
