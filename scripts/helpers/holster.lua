-- Holster: the holster gesture (wand-hand grip with the controller pointing down) puts the wand away and takes it out
-- again, and on foot swimming or climbing (ladders, ledges) keeps the wand away. Enabled from the config UI.
local uevrUtils = require('libs/uevr_utils')
local gestures = require('libs/gestures')
local attachments = require('libs/attachments')
local mounts = require('helpers/mounts')
local locomotion = require('helpers/locomotion')
local grip = require('libs/grip')

local M = {}

local status = {}

-- Enable Holster in the config UI. Off: no gesture, no put-away state and no movement rules.
local enabled = true
-- Experimental, on foot only: swimming or climbing (ladders, ledges) puts the wand away and normal movement brings
-- it back after a game holster that leaves the arm idle; on a broom the wand also stays out after such a holster.
-- Other mounts, boats and carts are left alone.
local returnWandAfterGameHolster = true -- false = old behavior: only HoldItem, anim flag or a wand ability count as drawn

-- While the wand is put away every cast the mod starts returns early. The grip update moves the wand out of or back
-- into the hand.
local wandStowed = false

function M.setEnabled(value)
	enabled = value == true
	if not enabled then wandStowed = false end
end

function M.isWandStowed()
	return wandStowed
end

-- On creature mounts (hippogriff, graphorn) the possessed pawn is the creature, which has no GetWand; mounts.getMountPawn
-- returns the rider. While mounted its wand stays out (its arm is in a riding pose, not HoldItem), whether or not Holster
-- is enabled. The cart is left alone.
function M.getMountedRiderWand(pawn)
	if mounts.getMountType() == nil or mounts.isRidingCart() then return nil end
	local rider = uevrUtils.getValid(mounts.getMountPawn(pawn))
	if rider == nil or rider == pawn or rider.GetWand == nil or not rider:IsWandEquipped() then return nil end
	return uevrUtils.getValid(rider:GetWand())
end

-- A light buzz on the wand hand confirms the stow or unstow.
local function toggleWandStowed()
	wandStowed = not wandStowed
	attachments.forceGripUpdate()
	uevrUtils.triggerHapticVibration(uevrUtils.getHandedness(), 0, 0.05, 1000, 0.3)
end

local function onFootRules()
	return returnWandAfterGameHolster and enabled and mounts.isWalking()
end

-- The wand stays in the hand unless the player holsters it. An idle arm the game left after putting the wand away (e.g. after
-- swimming) counts as drawn on foot and also on a broom, where mounting would otherwise drop it back to the body. On creature
-- mounts the rider's wand already counts as drawn (getMountedRiderWand).
local function keepsWandAfterGameHolster()
	local mountType = mounts.getMountType()
	return onFootRules() or (returnWandAfterGameHolster and enabled
		and (mountType == mounts.EMountTypes.Broom_Flying or mountType == mounts.EMountTypes.Broom_Ground))
end

-- Called by spells.isWandDrawn outside the tutorial, before its own checks. On foot, swimming (MovementMode 4) or
-- an active climb ability (ABL_ClimbLadder_*, ABL_Climb* ledges, ABL_SwimClimbLedge; the ability locomotion.lua
-- reads each tick) puts the wand away whatever the arm state: on a ladder the arm stays in HoldItem. A jump reports
-- Flying (5) like a ladder but runs no climb ability, so the wand stays.
function M.isAwayForMovement(pawn)
	status.wandAwayForMovement = false
	if not onFootRules() then return false end
	local mode = pawn.CharacterMovement and pawn.CharacterMovement.MovementMode
	local ability = locomotion.getActiveAbilityName()
	if mode == 4 or (ability ~= nil and string.find(ability, "Climb", 1, true) ~= nil) then
		status.wandAwayForMovement = true
		return true
	end
	return false
end

-- Called by spells.isWandDrawn after its own checks failed. After swimming the game leaves the right arm idle (0)
-- with the wand still equipped and never redraws it. Getting off a creature mount (hippogriff, graphorn) leaves it in
-- HideItem (9) instead. An idle arm, or HideItem until the arm leaves it after a dismount, with the wand equipped
-- counts as drawn on foot or on a broom, unless isAwayForMovement put the wand away this check. HideItem is otherwise left
-- alone: the game also uses it to hide the wand on purpose.
function M.isDrawnAfterGameHolster(pawn, arm)
	if not keepsWandAfterGameHolster() or status.wandAwayForMovement then return false end
	if arm ~= 0 and arm ~= 9 then status.hideItemAfterDismount = false end
	if arm == 0 or (arm == 9 and status.hideItemAfterDismount) then
		return pawn.IsWandEquipped ~= nil and pawn:IsWandEquipped()
	end
	return false
end

uevrUtils.registerUEVRCallback("on_mount_changed", function(mountType)
	local types = mounts.EMountTypes
	local last = status.lastMountType
	status.lastMountType = mountType
	status.hideItemAfterDismount = mountType == types.Avatar_Ground and last ~= nil and last >= types.Graphorn_Ground and last <= types.Niffler_Ground
end)

-- Called by getWeaponMesh after spells.isWandDrawn, so the movement state is current. Released, a put-away wand goes
-- back to the invisible pawn hand, so hide the whole actor; HideWand does not stay hidden there. The game still counts
-- the wand as drawn on ladders, so it does not hide it either. Only the actor this hid is shown again; cutscenes still
-- show the wand. The movement flag only counts on foot: on a mount isWandDrawn is not called, so it can be stale
-- from the mount-up.
function M.updateWandHidden(wand)
	local hide = (wandStowed or (status.wandAwayForMovement == true and onFootRules())) and not uevrUtils.isInCutscene()
	if hide ~= (status.hiddenWand == wand) then
		wand:SetActorHiddenInGame(hide)
		status.hiddenWand = hide and wand or nil
	end
end

uevrUtils.registerOnPreInputGetStateCallback(function(retval, user_index, state)
	-- Holster gesture: wand-hand grip with the controller pointing down. Toggles on the next tick, where key binds run.
	if enabled and gestures.detectGestureWithState(gestures.Gesture.HOLSTER, state, uevrUtils.getHandedness(), false) then
		delay(1, toggleWandStowed)
	end
end)

-- A put-away wand cannot cast: hide basic cast/spell sets (RT) and Protego/Stupefy (Y) from the game.
uevrUtils.registerOnPostInputGetStateCallback(function(retval, user_index, state)
	if not wandStowed then return end
	state.Gamepad.bRightTrigger = 0
	uevrUtils.unpressButton(state, XINPUT_GAMEPAD_Y)
end)

-- Grip hiding (libs/grip): Ancient Magic (LB+RB) is hidden from the game while the wand is put away, when both grips still reach the
-- game after the other systems' own hiding (state is the input as they left it).
grip.registerHider("holster", function(hand, press, state)
	return wandStowed and uevrUtils.isButtonPressed(state, XINPUT_GAMEPAD_LEFT_SHOULDER) and uevrUtils.isButtonPressed(state, XINPUT_GAMEPAD_RIGHT_SHOULDER)
end)

-- Level change or script reset takes the wand back out and shows the actor this hid.
local function reset()
	local wand = uevrUtils.getValid(status.hiddenWand)
	if wand ~= nil and wand.SetActorHiddenInGame ~= nil then wand:SetActorHiddenInGame(false) end
	status = {}
	wandStowed = false
end
uevr.params.sdk.callbacks.on_script_reset(reset)
uevrUtils.registerLevelChangeCallback(reset)

return M
