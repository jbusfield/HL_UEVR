-- Ladders: grab a rung with either grip and pull to climb. The climbing itself is libs/mechanisms' Ladder type (a mechanism of type
-- Ladder made in the Mechanisms Dev Config, with Use Get On off), with helpers/interactions as its game adapter; this module tells it
-- which ladder the player is climbing and the ladder facts it needs (M.mechanismFacts). Mounting and dismounting stay with the game:
-- the stick still climbs, and pulling past either end of the ladder presses the stick toward it so the game plays its own dismount.
-- Enabled from the config UI.
--
-- Verified live on the player's ladders: a location write during ABL_ClimbLadder_Idle holds, and the game's Up/Down/DismountTop steps
-- start from wherever the pawn is, so the stick keeps working after hand climbing.
local uevrUtils = require('libs/uevr_utils')
local locomotion = require('helpers/locomotion')
local grip = require('libs/grip')
local mechanisms = require('libs/mechanisms')
local plugin = require('libs/core/plugin')
local GRIP_PRIORITY = require('helpers/grip_priority')

local M = {}

local enabled = true

-- Pawn (capsule centre) heights the ladder Idle ability rests between, measured on the player's ladders: bottomZ + 150 after
-- MountBottom and topZ - 100 for the last stop before DismountTop. Hand climbing stays inside this range.
local LOWEST_IDLE_ABOVE_BOTTOM = 150
local HIGHEST_IDLE_BELOW_TOP = 100

-- Disabled, the player is never climbing a ladder for libs/mechanisms, so it lets go.
function M.setEnabled(value)
	enabled = value == true
end

-- The ladder ability now running, or nil when not on a ladder (or ladder climbing is disabled).
local function getClimbAbility()
	if not enabled then return nil end
	local ability = locomotion.getActiveAbilityName()
	if ability == nil or string.find(ability, "ABL_ClimbLadder_", 1, true) == nil then return nil end
	return ability
end

-- The ladder the player is climbing, or nil.
function M.getCurrentLadder()
	if getClimbAbility() == nil then return nil end
	local ladder = uevrUtils.getValid(pawn, {"LadderActor"})
	if ladder == nil or ladder.GetLadderBottomZ == nil then return nil end
	return ladder
end

-- The player is climbing this ladder. Asked for each ladder while the library scans, and on every tick while it climbs.
function M.isClimbing(actor)
	local ladder = M.getCurrentLadder()
	return ladder ~= nil and actor ~= nil and ladder:get_address() == actor:get_address()
end

-- Animated steps (libs/mechanisms' animateSteps): the game's own step plays as the hands pull. Measured live on BP_Ladder3
-- (2026-11-19): a step is the Able ability ABL_ClimbLadder_Up_C or _Down_C (no montage), about 46.3 cm at a steady ~107 cm/s.
-- The game moves the body two ways during it: the animation's root motion, and the ability's ablMotionAdjustTask, which pulls a
-- location written during the step back to where the step has got. libs/mechanisms writes the body to the hands on every tick of
-- a held step, so the two fought and the body jittered. With the anim instance's root motion ignored and the motion adjust's
-- bCanAdjustZAxis off, the body stood still mid-step while the animation played on, and the step came to rest where the body
-- was. So while the hands play a step both are off (put back once the game's step is over), and only the hands move the body.
-- The animation is kept with the hands by the ability component's GlobalPlayRate (a write mid-step takes), and paused with
-- PauseAbility (it freezes the pose) while the hands are not ahead of it: nothing found plays a step backwards. Its progress is
-- counted from the rate it played at over time.
local STEP_LENGTH = 46.3
local STEP_SPEED = 107 -- cm/s at play rate 1
local STEP_CATCH_UP_SECONDS = 0.1 -- the rate asks the step to close its gap to the hands in this time
local STEP_MAX_RATE = 2
local STEP_RATE_QUANTUM = 0.05 -- the rate is written in these steps, so it isn't written again on every tick
local ROOT_MOTION_IGNORE = 1 -- ERootMotionMode::IgnoreRootMotion
local ROOT_MOTION_DEFAULT = 2 -- ERootMotionMode::RootMotionFromEverything, the pawn's mode when measured
local EMPTY_NAME = uevrUtils.fname_from_string("")

-- 1 for an Up step, -1 for a Down step, nil for any other ability name.
local function getStepDirection(name)
	if name == nil then return nil end
	if string.find(name, "ABL_ClimbLadder_Up_C", 1, true) ~= nil then return 1 end
	if string.find(name, "ABL_ClimbLadder_Down_C", 1, true) ~= nil then return -1 end
	return nil
end

---@class LadderStep
---@field component any
---@field ability any
---@field baseRate number GlobalPlayRate before the step, put back when it is let go
---@field rate number GlobalPlayRate written last
---@field paused boolean
---@field played number cm of the step played so far
---@field clock number os.clock() when played was last brought up to date
---@type LadderStep|nil
local currentStep = nil -- the step libs/mechanisms holds, until it is finished or cancelled
local stepAsked = false -- libs/mechanisms asked for a step (startStep) that hasn't started yet

-- What playing a step with the hands changed, put back once the game's step is over (the pre-engine tick at the end).
---@class LadderStepOverrides
---@field animInstance any
---@field rootMotionMode integer
---@field tasks any[] motion adjust tasks whose bCanAdjustZAxis was turned off
---@type LadderStepOverrides|nil
local stepOverrides = nil
local motionAdjustTasks = {} -- ability address -> its motion adjust tasks (read once)
local tasksWarned = false

-- The ability's motion adjust tasks, or nil when they can't be read. m_Tasks is a TArray, so it is read with libs/core/plugin.
local function getMotionAdjustTasks(ability)
	local address = ability:get_address()
	local tasks = motionAdjustTasks[address]
	if tasks ~= nil then return tasks end
	local all = plugin.getProperty(ability, "m_Tasks")
	if type(all) ~= "table" then return nil end
	tasks = {}
	for _, task in ipairs(all) do
		local class = task ~= nil and task.get_class ~= nil and task:get_class() or nil
		if class ~= nil and string.find(class:get_fname():to_string(), "MotionAdjustTask", 1, true) ~= nil then
			tasks[#tasks + 1] = task
		end
	end
	motionAdjustTasks[address] = tasks
	return tasks
end

-- Keeps the game from moving the body while the hands play a step: root motion is ignored, and the ability's (when given) motion
-- adjust leaves Z alone.
local function holdBodyStill(ability)
	if stepOverrides == nil then
		local mesh = uevrUtils.getValid(pawn, {"Mesh"})
		local animInstance = mesh ~= nil and mesh:GetAnimInstance() or nil
		if animInstance == nil then return end
		stepOverrides = {animInstance = animInstance, rootMotionMode = tonumber(animInstance.RootMotionMode) or ROOT_MOTION_DEFAULT,
			tasks = {}}
		animInstance:SetRootMotionMode(ROOT_MOTION_IGNORE)
	end
	if ability == nil then return end
	local tasks = getMotionAdjustTasks(ability)
	if tasks == nil then
		if not tasksWarned then
			tasksWarned = true
			uevrUtils.print("Ladder: could not read the step's tasks, so the game still moves the body during it", LogLevel.Warning)
		end
		return
	end
	for _, task in ipairs(tasks) do
		if task.bCanAdjustZAxis == true then
			task.bCanAdjustZAxis = false
			stepOverrides.tasks[#stepOverrides.tasks + 1] = task
		end
	end
end

-- Lets the game move the body again.
local function letBodyMove()
	if stepOverrides == nil then return end
	local animInstance = uevrUtils.getValid(stepOverrides.animInstance)
	if animInstance ~= nil then animInstance:SetRootMotionMode(stepOverrides.rootMotionMode) end
	for _, task in ipairs(stepOverrides.tasks) do
		if uevrUtils.getValid(task) ~= nil then task.bCanAdjustZAxis = true end
	end
	stepOverrides = nil
end

local function pauseStep(step, value)
	if step.paused == value then return end
	local component = uevrUtils.getValid(step.component)
	if component ~= nil then component:PauseAbility(value, step.ability) end
	step.paused = value
end

local function setStepRate(step, rate)
	if step.rate == rate then return end
	local component = uevrUtils.getValid(step.component)
	if component ~= nil then component.GlobalPlayRate = rate end
	step.rate = rate
end

-- Lets the step play on at the rate it had and forgets it. The body is let move once the game's step is over.
local function releaseStep()
	stepAsked = false
	if currentStep ~= nil then
		setStepRate(currentStep, currentStep.baseRate)
		pauseStep(currentStep, false)
	end
	currentStep = nil
end

-- The game adapter's ladder table (libs/mechanisms' Ladder type).
M.mechanismFacts = {
	gripPriority = GRIP_PRIORITY.LADDER,
	isIdle = function()
		local ability = getClimbAbility()
		return ability ~= nil and string.find(ability, "ABL_ClimbLadder_Idle", 1, true) ~= nil
	end,
	isDismounting = function()
		local ability = getClimbAbility()
		return ability ~= nil and string.find(ability, "Dismount", 1, true) ~= nil
	end,
	getRange = function(actor)
		return actor:GetLadderBottomZ() + LOWEST_IDLE_ABOVE_BOTTOM, actor:GetLadderTopZ() - HIGHEST_IDLE_BELOW_TOP
	end,
	-- One rung per segment. Measured live on BP_Ladder3 (2026-11-19): the ladder is GetLadderHeight() stacked segments of
	-- GetMeshHeight() each (12 x 25 cm = top - bottom: SM_UN_Ladder_Bot, 10 instances of SM_UN_Ladder_Mid, SM_UN_Ladder_Top_A,
	-- each mesh 0 to 25 cm tall). The rung is taken to be at the middle of its segment, which fits the hand spots placed on a
	-- rung (112 cm above the root, 12 cm into a segment).
	getRungs = function(actor)
		local bottom, count, pitch = actor:GetLadderBottomZ(), actor:GetLadderHeight(), actor:GetMeshHeight()
		if bottom == nil or count == nil or pitch == nil or count < 2 or pitch <= 0 then return nil end
		return count, bottom + (count - 1) * pitch + pitch / 2, pitch
	end,
	-- The actor's origin is the bottom of the rung axis and its forward faces away from the player: the rungs face along x, and
	-- the player is on the - side.
	getFrame = function(actor) return actor, "x", -1 end,
	stepLength = STEP_LENGTH,
	-- The tick before the game starts the step, so its first tick doesn't move the body either.
	startStep = function()
		stepAsked = true
		holdBodyStill(nil)
	end,
	getStep = function()
		local direction = getStepDirection(getClimbAbility())
		if direction == nil then return nil end
		local component = uevrUtils.getValid(pawn, {"AblAbilityComponent"})
		if component == nil then return nil end
		local ability = component:GetActiveAbility_New(EMPTY_NAME)
		if ability == nil then return nil end
		releaseStep()
		holdBodyStill(ability)
		local baseRate = tonumber(component.GlobalPlayRate)
		if baseRate == nil or baseRate <= 0 then baseRate = 1 end
		currentStep = {component = component, ability = ability, baseRate = baseRate, rate = baseRate, paused = false, played = 0,
			clock = os.clock()}
		return currentStep, direction
	end,
	-- Steers the step's play rate so it closes its gap to the hands' share of it, paused while it is not behind them (it can't go
	-- back).
	holdStep = function(_, step, phase)
		if step == nil or step ~= currentStep then return end
		local now = os.clock()
		if not step.paused then step.played = math.min(STEP_LENGTH, step.played + (now - step.clock) * step.rate * STEP_SPEED) end
		step.clock = now
		local rate = (phase * STEP_LENGTH - step.played) / STEP_CATCH_UP_SECONDS / STEP_SPEED
		rate = math.floor(math.max(0, math.min(STEP_MAX_RATE, rate)) / STEP_RATE_QUANTUM + 0.5) * STEP_RATE_QUANTUM
		if rate <= 0 then
			pauseStep(step, true)
		else
			setStepRate(step, rate)
			pauseStep(step, false)
		end
	end,
	finishStep = function() releaseStep() end,
	cancelStep = function() releaseStep() end,
}

-- A climbing grip is hidden from main.lua's head gestures (its input callback at priority 20 reads the left hand's ear and mouth
-- grips on every frame of a press) and from every pre-input callback after them, so pulling a hand down past the face while
-- climbing never opens the menu or drinks a potion: libs/mechanisms hides it from the game only. The library's climb claim is
-- named "mechanism_<entry ID>:climb" (a stage's mechanism is "<entry ID>:<stage>", its grip claim "mechanism_" .. that name).
local HEAD_GESTURE_INPUT_PRIORITY = 20
local climbOwners = {} -- grip owner name -> whether it is a Ladder entry's climb (worked out once per name)
local function isClimbOwner(owner)
	if owner == nil then return false end
	local known = climbOwners[owner]
	if known == nil then
		known = false
		for _, mechanism in ipairs(mechanisms.getMechanisms()) do
			if mechanism:getType() == "ladder" and owner == "mechanism_" .. mechanism:getName() .. ":climb" then known = true end
		end
		climbOwners[owner] = known
	end
	return known
end
grip.registerHider("ladder_mechanism", function(hand)
	return enabled and isClimbOwner(grip.getOwner(hand))
end, {fromPriority = HEAD_GESTURE_INPUT_PRIORITY + 1})

-- Once a step the hands played is over (the game plays some other ability, or the player is off the ladder), the game moves the body
-- again. Nothing to do on most ticks.
uevr.sdk.callbacks.on_pre_engine_tick(function()
	if stepOverrides == nil or currentStep ~= nil or stepAsked then return end
	if getStepDirection(getClimbAbility()) == nil then letBodyMove() end
end)

-- A step paused, or the body held still, when the scripts reset would leave the player stuck on the ladder.
uevr.params.sdk.callbacks.on_script_reset(function()
	releaseStep()
	letBodyMove()
end)

return M
