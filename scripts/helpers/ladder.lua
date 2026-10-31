-- Ladders: grab the ladder with either grip and pull to climb. While the game's ladder Idle ability runs, the holding
-- hand's real-world height change moves the pawn the opposite way along the ladder, so the hand stays on its rung.
-- Mounting and dismounting stay with the game: the stick still climbs, and pulling past either end of the ladder
-- presses the stick toward it so the game plays its own dismount. Enabled from the config UI.
--
-- Verified live on the player's ladders: a location write during ABL_ClimbLadder_Idle holds, and the game's
-- Up/Down/DismountTop steps start from wherever the pawn is, so the stick keeps working after hand climbing.
local uevrUtils = require('libs/uevr_utils')
local controllers = require('libs/controllers')
local locomotion = require('helpers/locomotion')
local grip = require('libs/grip')
local GRIP_PRIORITY = require('helpers/grip_priority')

local M = {}

----------------------------------------------------------------------------------------------------------------------
-- Climbing: game-agnostic hand-over-hand vertical climbing. Tracks which hands hold on and turns the most recent
-- grab's tracking-space height change into a body height change. Knows nothing about ladders or this game, so it can
-- move to libs/climbing.lua.
local Climbing = {}
Climbing.__index = Climbing

function Climbing.new(unitsPerMeter)
	return setmetatable({
		unitsPerMeter = unitsPerMeter or 100,
		heights = {}, -- tracking-space height (meters) of each holding hand when last read
		order = {}, -- holding hands, most recent grab last
		pos = Vector3f.new(0, 0, 0),
		rot = Quaternionf.new(0, 0, 0, 0),
	}, Climbing)
end

-- Tracking-space height of a controller in meters, unaffected by pawn movement. nil while tracking is lost, which
-- reports the identity pose at the origin.
function Climbing:readHandHeight(hand)
	local index = uevrUtils.getControllerIndex(hand)
	if index == nil then return nil end
	uevr.params.vr.get_pose(index, self.pos, self.rot)
	local p = self.pos
	if p.X * p.X + p.Y * p.Y + p.Z * p.Z < 1e-8 then return nil end
	return p.Y
end

function Climbing:grab(hand)
	local height = self:readHandHeight(hand)
	if height == nil then return false end
	self:release(hand)
	self.heights[hand] = height
	table.insert(self.order, hand)
	return true
end

function Climbing:release(hand)
	self.heights[hand] = nil
	for i = #self.order, 1, -1 do
		if self.order[i] == hand then table.remove(self.order, i) end
	end
end

function Climbing:getActiveHand()
	return self.order[#self.order]
end

function Climbing:reset()
	self.heights = {}
	self.order = {}
end

-- Body height change (world units, up positive) since the last call, from the most recent grab still holding.
-- Every holding hand is re-anchored, so letting go with one hand never makes the body jump.
function Climbing:consumeBodyDelta()
	local active = self.order[#self.order]
	local delta = 0
	for _, hand in ipairs(self.order) do
		local height = self:readHandHeight(hand)
		if height ~= nil then
			if hand == active then delta = (self.heights[hand] - height) * self.unitsPerMeter end
			self.heights[hand] = height
		end
	end
	return delta
end

----------------------------------------------------------------------------------------------------------------------
-- Hogwarts Legacy ladders.

local enabled = true

-- Pawn (capsule centre) heights the ladder Idle ability rests between, measured on the player's ladders: bottomZ + 150
-- after MountBottom and topZ - 100 for the last stop before DismountTop. Hand climbing stays inside this range.
local LOWEST_IDLE_ABOVE_BOTTOM = 150
local HIGHEST_IDLE_BELOW_TOP = 100
-- A grip grabs the ladder when the hand is within REACH_DEPTH of the rung plane (the climbing pawn hangs 42 back),
-- within REACH_HALF_WIDTH of its centre line, and no more than REACH_ABOVE_TOP above its top.
local REACH_DEPTH = 30
local REACH_HALF_WIDTH = 45
local REACH_ABOVE_TOP = 40
-- Pulling this far past either end presses the stick toward it until the game starts a dismount, or for at most
-- DISMOUNT_STICK_SECONDS.
local DISMOUNT_OVERSHOOT = 15
local DISMOUNT_STICK_SECONDS = 1.5
local STICK_FULL = 32767

local climber = Climbing.new()
local status = { overshoot = 0 }
-- Grips that grabbed the ladder stay hidden from the game and other modules until released, even after a dismount.
local claimedGrips = {}

local function releaseLadder()
	climber:reset()
	status = { overshoot = 0 }
end

function M.setEnabled(value)
	enabled = value == true
	if not enabled then releaseLadder() end
end

local function worldScale()
	return tonumber(string.match(uevr.params.vr:get_mod_value("VR_WorldScale") or "", "[%-%d%.]+")) or 1
end

-- Caches the ladder the pawn is on. Its origin is the bottom of the rung axis; its forward faces away from the pawn.
local function beginLadder(currentPawn)
	local ladder = uevrUtils.getValid(currentPawn.LadderActor)
	if ladder == nil or ladder.GetLadderBottomZ == nil then return false end
	local origin = ladder:K2_GetActorLocation()
	local forward = ladder:GetActorForwardVector()
	status.ladder = ladder
	status.originX, status.originY = origin.X, origin.Y
	status.forwardX, status.forwardY = forward.X, forward.Y
	status.bottomZ, status.topZ = ladder:GetLadderBottomZ(), ladder:GetLadderTopZ()
	status.lowZ = status.bottomZ + LOWEST_IDLE_ABOVE_BOTTOM
	status.highZ = status.topZ - HIGHEST_IDLE_BELOW_TOP
	status.rungPitch = ladder:GetMeshHeight()
	climber.unitsPerMeter = 100 * worldScale()
	return true
end

local function isInReach(hand)
	local loc = controllers.getControllerLocation(hand)
	if loc == nil then return false end
	local dx, dy = loc.X - status.originX, loc.Y - status.originY
	-- The pawn is on the ladder's back side: depth is how far the hand is behind the rung plane.
	local depth = -(dx * status.forwardX + dy * status.forwardY)
	local side = dx * -status.forwardY + dy * status.forwardX
	return depth <= REACH_DEPTH and math.abs(side) <= REACH_HALF_WIDTH
		and loc.Z >= status.bottomZ and loc.Z <= status.topZ + REACH_ABOVE_TOP
end

local function updateRungHaptics(z, hand)
	if status.rungPitch == nil or status.rungPitch <= 0 then return end
	local rung = math.floor((z - status.bottomZ) / status.rungPitch)
	if status.rung ~= nil and rung ~= status.rung then
		uevrUtils.triggerHapticVibration(hand, 0, 0.02, 1000, 0.15)
	end
	status.rung = rung
end

-- Moves the pawn by the holding hand's height change. Runs after locomotion's pre-engine tick (registered when that
-- module loaded), so the ability name is this frame's.
uevr.sdk.callbacks.on_pre_engine_tick(function(engine, delta)
	if not enabled then return end
	local ability = locomotion.getActiveAbilityName()
	if ability == nil or string.find(ability, "ABL_ClimbLadder_", 1, true) == nil then
		if status.ladder ~= nil then releaseLadder() end
		return
	end
	local currentPawn = uevrUtils.getValid(pawn)
	if currentPawn == nil then return end
	if status.ladder == nil and not beginLadder(currentPawn) then return end

	if status.dismountStick ~= nil and (string.find(ability, "Dismount", 1, true) ~= nil
		or os.clock() - status.dismountStickTime > DISMOUNT_STICK_SECONDS) then
		status.dismountStick = nil
		climber:reset()
	end

	status.idle = string.find(ability, "ABL_ClimbLadder_Idle", 1, true) ~= nil
	local bodyDelta = climber:consumeBodyDelta()
	local hand = climber:getActiveHand()
	if not status.idle or hand == nil or status.dismountStick ~= nil then
		status.overshoot = 0
		return
	end
	if bodyDelta == 0 then return end

	local loc = currentPawn:K2_GetActorLocation()
	-- Never push the pawn further outside the range than the game put it.
	local low, high = math.min(status.lowZ, loc.Z), math.max(status.highZ, loc.Z)
	-- Motion past an end accumulates in overshoot and has to be undone before the pawn moves back.
	local wanted = loc.Z + status.overshoot + bodyDelta
	local z = math.max(low, math.min(high, wanted))
	status.overshoot = wanted - z
	if math.abs(status.overshoot) >= DISMOUNT_OVERSHOOT then
		status.dismountStick = status.overshoot > 0 and STICK_FULL or -STICK_FULL
		status.dismountStickTime = os.clock()
		status.overshoot = 0
	end
	if z ~= loc.Z then
		loc.Z = z
		currentPawn:K2_SetActorLocation(loc, false, reusable_hit_result, true)
		updateRungHaptics(z, hand)
	end
end)

-- Grip arbitration (libs/grip): a grip that starts with the ladder in reach belongs to the ladder, above everything else. It is
-- hidden from the game and from the input callbacks after grip.lua (gestures, palette, grab), so a grip that grabs the ladder never also
-- spawns a gadget or fires a gesture, and it stays hidden until released, even after a dismount.
grip.registerClaim("ladder", function(hand, state, press)
	if enabled and status.ladder ~= nil and isInReach(hand) then return GRIP_PRIORITY.LADDER end
	return nil
end, {hide = grip.Hide.Systems})

-- The ladder takes hold when it wins a press. If the grab fails it yields, and the press goes to whatever else claimed it, as if the
-- ladder never had.
grip.registerOwnerChangeCallback(function(hand, newOwner, oldOwner)
	if newOwner == "ladder" then
		if climber:grab(hand) then
			claimedGrips[hand] = true
			uevrUtils.triggerHapticVibration(hand, 0, 0.04, 1000, 0.4)
		else
			grip.yield(hand, "ladder")
		end
	elseif oldOwner == "ladder" and claimedGrips[hand] then
		claimedGrips[hand] = nil
		climber:release(hand)
	end
end)

-- While holding on in Idle the hands climb, so the stick cannot start Up/Down under them. A pull past an end presses
-- the stick instead.
uevrUtils.registerOnPostInputGetStateCallback(function(retval, userIndex, state)
	if userIndex ~= 0 or status.ladder == nil then return end
	if status.dismountStick ~= nil then
		state.Gamepad.sThumbLX = 0
		state.Gamepad.sThumbLY = status.dismountStick
	elseif status.idle and climber:getActiveHand() ~= nil then
		state.Gamepad.sThumbLY = 0
	end
end)

local function reset()
	releaseLadder()
	claimedGrips = {}
	-- A grip still held from climbing is no longer the ladder's (it was only hidden while claimed).
	for _, hand in ipairs({Handed.Left, Handed.Right}) do grip.yield(hand, "ladder") end
end
uevr.params.sdk.callbacks.on_script_reset(reset)
uevrUtils.registerLevelChangeCallback(reset)

return M