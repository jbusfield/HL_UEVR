--[[
Usage
    Drop the libs folder containing this file into your project folder
    Add code like this in your script:
        local grip = require("libs/grip")

    Decides which system owns each press of a hand's grip button, so several systems (menus, gestures, ladders, grabbing,
    chords such as LB+RB) can share the grips without knowing about each other. It holds no game or mod knowledge: systems
    register claims under their own names with their own priorities, and the mod decides the order. Nothing runs until the
    first claim is registered, so projects that never use grip.lua pay nothing.

    Concepts
        Press
            One press of a hand's grip button, from the frame it goes down until the frame it comes up. grip.lua reads the
            button in a pre-input callback at priority grip.PRE_INPUT_PRIORITY (90). A press created or hidden by a callback
            that runs earlier (higher priority) is seen as it is at that point; presses synthesized by callbacks that run later
            (e.g. a spell pressing LB+RB for the game) are not grip presses.

        Claim
            A function a system registers to say "this press is mine". It returns a priority number, or nil for no claim.
            Claims should be cheap and free of side effects: they only decide, the system acts once it owns the press.
            - Start claim (default): asked once, on the frame the press starts. If it wins, it owns the press until the press
              ends or it yields, whatever happens during the press.
            - Continuous claim: asked on every frame of the press. It owns the press only on frames where it returns a priority
              higher than the start owner's and every other claim's, so it can take a press that is already underway, and the
              press returns to the start owner when it stops claiming.
            - Chord claim: covers both grips at once. Asked on every frame both grips are down, with both presses. When it wins,
              it owns both presses on those frames.
            - Shared claim: an observer. It never owns a press and never changes who does, but systems can ask whether it is
              claiming (hasClaim), and it can still hide the press from the game while it claims.

        Owner
            The name of the winning claim for a hand's press on the current frame, or nil when nothing claims it.
            Highest priority wins. Ties: the start owner keeps the press, otherwise the claim registered first wins.

        Hiding
            Each claim says what its press is hidden from while it owns it (or, for a shared claim, while it claims):
            - grip.Hide.Game (default): the grip button is cleared in a post-input callback after all others (priority
              grip.POST_INPUT_PRIORITY, -150), so the game never sees it but every system's input callbacks still do
              (e.g. hand grip animation still closes the hand).
            - grip.Hide.Systems: also cleared right after the owner is decided, so pre-input callbacks that run after grip.lua
              see the button released too (as a ladder that must keep gestures and menus from reacting does).
            - grip.Hide.None: the game sees the press (e.g. a chord the game itself should handle).

        Hiders
            For hiding that does not follow ownership (a system that hides some presses it does not own, or decides frame by
            frame), a system registers a hider instead: a function asked on every frame a hand's press exists, whoever owns it.
            When it returns true the press is hidden from the game, and, with fromPriority, also from every pre-input callback
            with a lower priority (grip.lua clears the button in a pre-input callback of its own at fromPriority). Register at a
            fromPriority just below the system's own input callback when the hider reads state that callback updates.

        Yield
            An owner can give up a press part way through with grip.yield. The press then goes to the next start claim in line, as if
            the yielding claim had never claimed it (every start claim made when the press started is kept in priority order), unless
            a continuous or chord claim beats it; with none left it goes to nobody (the game sees it, unless something else hides it).
            A start claim that yields on the press's first frame (e.g. a ladder whose grab fails) leaves the press exactly as the other
            claims decided it.

        Interact
            A grip that presses the game's interact button for whatever the game's prompt is on, with the prompt showing the grip's
            button instead of the game's (grip.registerInteract). In VR a hand takes hold of things, so a prompt asking for the grip
            fits where one asking for A or X does not. It is an ordinary start claim, so the mod's priorities decide what a press
            does: a higher claim (e.g. libs/grabbable grabbing the item the prompt is on) takes the press, and the prompt still shows
            the grip, which is what gets pressed either way. One check, on an interval on the game thread, decides both what the
            prompt shows and whether the claim claims, so the prompt shows the grip exactly when a grip press will act. The game
            supplies only what is its own: what the prompt is on, the prompt's objects, and the two button values.

        Busy hands
            A hand holding something with its grip released (e.g. libs/grabbable's toggle grip) uses its next press for that. The
            system holding it says so with an event, and an interact then leaves the game's own button on the prompt:
                uevrUtils.executeUEVRCallbacks(grip.HAND_BUSY_EVENT, hand, name, busy)
            name is the system's own name; a hand is busy until every name that marked it busy has cleared it.

        Claimed prompts
            Another system can take the game's prompt for itself (e.g. libs/mechanisms, whose mechanisms are worked by reaching
            out a hand, changes the prompt to say so). It says so with an event, and interacts then leave the prompt and the grip
            alone until it is cleared:
                uevrUtils.executeUEVRCallbacks(grip.PROMPT_CLAIMED_EVENT, name, claimed)

    Rules
        - Priorities are plain numbers chosen by the mod; grip.lua defines no feature-specific values. Conventional levels:
              grip.LOW = 10, grip.NORMAL = 50, grip.HIGH = 100
        - Claims are asked in registration order.
        - Only user index 0 is handled.

    Available functions:

    grip.registerClaim(name, claimFunc, options)
        name: string - the owner name reported for presses this claim wins (unique per claim)
        claimFunc:
            start or continuous claim: function(hand, state, press) -> number|nil
            chord claim:               function(state, leftPress, rightPress) -> number|nil
            hand: Handed.Left or Handed.Right
            state: the XInput state of the current frame
            press: see Press info below
        options (all optional):
            continuous: boolean (default false)
            chord: boolean (default false) - implies continuous
            shared: boolean (default false)
            hide: grip.Hide value (default grip.Hide.Game)

    grip.getOwner(hand) -> string|nil
        The owner of the hand's press on the current frame.
    grip.isOwner(hand, name) -> boolean
    grip.hasClaim(hand, name) -> boolean
        True while a shared claim named name is claiming the hand's press.
    grip.yield(hand, name)
        If name owns the hand's press, it gives it up for the rest of the press.
    grip.isPressed(hand) -> boolean
        The grip as grip.lua read it this frame (before any hiding).
    grip.getPress(hand) -> press|nil
        Press info while the hand's grip is down.
    grip.setGripButton(hand, button)
        The XInput button that counts as the hand's grip. Defaults: LEFT_SHOULDER / RIGHT_SHOULDER.
    grip.registerOwnerChangeCallback(func)
        func(hand, newOwner, oldOwner) - called when a hand's owner changes, including to nil when the press ends.
    grip.registerHider(name, hideFunc, options)
        hideFunc: function(hand, press, state) -> boolean - true hides the hand's press this frame
            state: the XInput state as the other input callbacks have left it at that point (grip.lua decides every hand before
                hiding any, so a hider checking both grips sees them as they were before grip.lua's own hiding)
        options (optional):
            fromPriority: number - also hide from pre-input callbacks below this priority
    grip.isHandBusy(hand) -> boolean
        True while a system has marked the hand busy with grip.HAND_BUSY_EVENT (see Busy hands).
    grip.isPromptClaimed() -> boolean
        True while a system has claimed the game's prompt with grip.PROMPT_CLAIMED_EVENT (see Claimed prompts).

    grip.registerInteract(options) -> Interact|nil
        options:
            name: string (default "interact") - the owner name of its claim
            priority: number (default grip.LOW) - below the claims that should take a press first (grabbing, gestures)
            hands: {Handed, ...} (default {Handed.Left}) - the grips that interact
            button: XINPUT button (required) - the game's interact button, held for as long as an owned grip is held
            getInteractTarget: function() -> any|nil (required)
                What the game's interaction prompt is on right now, or nil: an actor, the prompt's widget, any value that tells one
                target from another. It runs on every interval, so keep it to native property reads (no object scans, find_uobject
                or plugin bridge calls there; cache what those find).
            canClaim: function(hand) -> boolean (optional) - false leaves the grip and the prompt alone (menus, cutscenes)
            prompt: table (optional) - the prompt's button shows the grip's instead (through libs/prompts)
                getPrompts: function(target) -> prompt|{prompt, ...}|nil (required)
                    The target's prompt objects (e.g. the image that shows the button). Called when the target changes, and again
                    while it gave nothing or a prompt it gave has gone away; not on every interval.
                get, set: as in libs/prompts (required), e.g. prompts.brushResource()
                from: value|function() -> value (optional) - the game's own value for the interact button; a prompt showing
                    anything else (another button, another input device) is left alone
                to: value|function(hand, target) -> value (required) - the grip's value
                equals: as in libs/prompts (optional)
            interval: ms (default 250) - how often the target and the prompt are checked
            hide: grip.Hide value (default grip.Hide.Game) - Game keeps the grip's own action (e.g. an item wheel) from the game
            enabled: boolean (default false)
        Returns nil when a required option is missing.

        Interact:setEnabled(value)
            Disabling puts the prompt back and gives up a press it owns.
        Interact:isEnabled() -> boolean
        Interact:isReady(hand) -> boolean
            Whether a press of the hand's grip starting now would be claimed (as of the last check).
        Interact:getTarget() -> any|nil
            The target as of the last check.
        Interact:update()
            Checks now (it also runs on the interval).

        A hand is ready while there is a target, canClaim allows it, the hand is not busy (see Busy hands) and its grip is not
        already down for something else. The prompt shows the first ready hand's value. While another system has claimed the
        prompt (see Claimed prompts) there is no target.

        Example (Silent Hill f: the prompt is one of a few pooled icon widgets, and the one in its Prompt state is the target):

            grip.registerInteract({
                priority = GRIP_PRIORITY.INTERACT,
                button = XINPUT_GAMEPAD_A,
                getInteractTarget = getActivePromptWidget,
                canClaim = canClaim,
                prompt = {
                    getPrompts = function(widget) return uevrUtils.getValid(widget, {"PromptButtonIcon"}) end,
                    get = getIcon, set = setIcon, -- prompts.brushResource()
                    from = function() return prompts.loadAsset(A_ICON) end,
                    to = function() return prompts.loadAsset(LB_ICON) end,
                },
            })

    Press info (read-only table)
        hand: Handed
        startTime: os.clock() when the press started
        age: seconds since the press started (updated every frame)
        startOwner: the name of the start claim that won, or nil
        owner: the current owner, or nil

    Examples (how Hogwarts Legacy uses it)
        The mod keeps its precedence order in one module, helpers/grip_priority.lua, shared by the systems below:

            local M = {
                LADDER = 1000,       -- a grip that starts with a ladder rung in reach
                ITEM_HELD = 200,     -- Physical Item Grab: a press while an item is already flying or held
                PALETTE_WHEEL = 100, -- a left grip that starts with the palette wheel open
                HEAD_GESTURE = 90,   -- a left grip that starts at the ear (menu)
                ITEM_GRAB = 50,      -- Physical Item Grab: grab, or hold X on, what the game's interaction prompt is on
            }
            return M

            local GRIP_PRIORITY = require("helpers/grip_priority")

        Ladder (ladder.lua; a start claim hidden from systems, so gestures, the palette and the grab never react to a climbing grip.
        It takes hold when it wins, and yields if the grab fails so the press goes to whatever else claimed it):

            grip.registerClaim("ladder", function(hand, state, press)
                if enabled and status.ladder ~= nil and isInReach(hand) then return GRIP_PRIORITY.LADDER end
                return nil
            end, {hide = grip.Hide.Systems})

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

            -- On level change the ladder lets go of any press it still owns:
            for _, hand in ipairs({Handed.Left, Handed.Right}) do grip.yield(hand, "ladder") end

        Palette (palette.lua; a start claim for the open wheel, and a hider for its own hiding rules. Its input callback runs at 6 and
        decides consumeGrip, so the hider runs at 5.9: callbacks above 6 (gestures, grip.lua) still see the grip, those below
        (accessories, holster, hand animation, grab) do not):

            grip.registerClaim("palette", function(hand, state, press)
                if hand == Handed.Left and enabled and M.isWheelOpen() then return GRIP_PRIORITY.PALETTE_WHEEL end
                return nil
            end, {hide = grip.Hide.None}) -- the hider below does the palette's hiding

            grip.registerHider("palette", function(hand, press)
                return enabled and consumeGrip[hand] == true and accessPawn == pawn and gadgetAvailable and ui.isRemapDisabled() == false
            end, {fromPriority = 5.9})

            -- The gadget copy stands aside for a grip another system owns (e.g. an item grab), on the press's first frame:
            local owner = grip.getOwner(Handed.Left)
            leftAccessory = allowed and (accessories.isGripHandEngaged(Handed.Left) or (owner ~= nil and owner ~= "palette"))

        Head gestures (main.lua; a start claim keeps the palette copy and the item grab away from a grip that starts at the ear, and a
        hider hides a grip that fires an ear or mouth gesture at any point in the press from the game only, so the palette can still
        drink at the mouth):

            grip.registerClaim("head_gesture", function(hand, state, press)
                if hand ~= Handed.Left then return nil end
                local _, _, _, gripEar = gestures.getHeadGestures(state, Handed.Left, true)
                if gripEar then return GRIP_PRIORITY.HEAD_GESTURE end
                return nil
            end, {hide = grip.Hide.None})

            grip.registerHider("head_gesture", function(hand, press)
                return hand == Handed.Left and status.headGestureGripLeft == true
            end)

        Physical Item Grab (libs/grabbable registers the claim itself; interactions.lua passes the mod's priorities):

            local itemGrab = grabbable.new({
                name = "item_grab",
                claimPriority = GRIP_PRIORITY.ITEM_GRAB,
                heldPriority = GRIP_PRIORITY.ITEM_HELD,
                ...
            })

            -- Inside grabbable: a start claim, hidden from the game for the whole press, acted on only when owned.
            grip.registerClaim(self.name, function(claimHand, state, press)
                if claimHand ~= self.hand then return nil end
                if self.flight ~= nil or self.held ~= nil then return self.heldPriority end
                if getClaimTarget(self, state) ~= nil then return self.claimPriority end
                return nil
            end)
            if grip.isOwner(self.hand, self.name) and self.claimTarget ~= nil then ... grab, or hold the interact button ... end

        Holster (holster.lua; a hider that checks both grips in the state it is given, so LB+RB is hidden while the wand is put away
        only when both still reach the game after the other systems' own hiding):

            grip.registerHider("holster", function(hand, press, state)
                return wandStowed and uevrUtils.isButtonPressed(state, XINPUT_GAMEPAD_LEFT_SHOULDER)
                    and uevrUtils.isButtonPressed(state, XINPUT_GAMEPAD_RIGHT_SHOULDER)
            end)

        Chord claims (not used by Hogwarts Legacy, whose LB+RB Ancient Magic handling stays inside the palette): a claim on both grips,
        e.g. giving LB+RB to the game when the right grip joins the left within a short window:

            grip.registerClaim("two_hand_action", function(state, left, right)
                if math.abs(right.startTime - left.startTime) <= 0.15 then return grip.HIGH end
                return nil
            end, {chord = true, hide = grip.Hide.None})
]]

local uevrUtils = require("libs/uevr_utils")

local M = {}

M.LOW, M.NORMAL, M.HIGH = 10, 50, 100
M.Hide = {Game = "game", Systems = "systems", None = "none"}
M.PRE_INPUT_PRIORITY = 90
M.POST_INPUT_PRIORITY = -150

local OWNER_CHANGED = "grip_owner_changed"
M.HAND_BUSY_EVENT = "grip_hand_busy_change"
M.PROMPT_CLAIMED_EVENT = "grip_prompt_claimed_change"
local interacts = {} -- in registration order: the objects made by registerInteract

local hands = {Handed.Left, Handed.Right}
local gripButtons = {[Handed.Left] = XINPUT_GAMEPAD_LEFT_SHOULDER, [Handed.Right] = XINPUT_GAMEPAD_RIGHT_SHOULDER}
local claims = {} -- in registration order: {name, func, continuous, chord, shared, hide}
local presses = {} -- per hand while its grip is down
local pressed = {} -- per hand, as read this frame
local hooksInstalled = false
local hiders = {} -- in registration order: {name, func, fromPriority}
local hiderHooks = {} -- fromPriority -> true once its pre-input callback is registered

local function isHiddenBy(hider, hand, state)
	local press = presses[hand]
	return press ~= nil and hider.func(hand, press, state) == true
end

-- The first start claim in line that has not yielded ({name, priority, hide}), or nil.
local function currentStart(press)
	for _, candidate in ipairs(press.startCandidates) do
		if not press.yielded[candidate.name] then return candidate end
	end
	return nil
end

-- The name and hiding of the claim that should own the press this frame. The start claim in line holds the press unless a continuous
-- or chord claim beats its priority; among those, the first registered wins a tie.
local function resolveOwner(press, state, chordName, chordPriority, chordHide)
	local owner, priority, hide = nil, nil, nil
	local start = currentStart(press)
	if start ~= nil then owner, priority, hide = start.name, start.priority, start.hide end
	for _, claim in ipairs(claims) do
		if claim.continuous and not claim.chord and not claim.shared and not press.yielded[claim.name] then
			local p = claim.func(press.hand, state, press)
			if p ~= nil and (priority == nil or p > priority) then owner, priority, hide = claim.name, p, claim.hide end
		end
	end
	if chordName ~= nil and not press.yielded[chordName] and (priority == nil or chordPriority > priority) then
		owner, priority, hide = chordName, chordPriority, chordHide
	end
	return owner, hide
end

local function setOwner(press, owner, hide)
	local old = press.owner
	press.owner, press.ownerHide = owner, hide
	if old ~= owner then uevrUtils.executeUEVRCallbacks(OWNER_CHANGED, press.hand, owner, old) end
end

local function startPress(hand, state, now)
	local press = {hand = hand, startTime = now, age = 0, yielded = {}, shared = {}, startCandidates = {}}
	for _, claim in ipairs(claims) do
		if not claim.continuous and not claim.chord then
			local p = claim.func(hand, state, press)
			if p ~= nil then
				if claim.shared then
					press.shared[claim.name] = claim.hide
				else
					-- Start claims are kept in line, highest priority first; on a tie the one registered first stays ahead.
					local line = press.startCandidates
					local at = #line + 1
					for i, candidate in ipairs(line) do
						if p > candidate.priority then
							at = i
							break
						end
					end
					table.insert(line, at, {name = claim.name, priority = p, hide = claim.hide})
				end
			end
		end
	end
	press.startOwner = press.startCandidates[1] ~= nil and press.startCandidates[1].name or nil
	presses[hand] = press
	return press
end

local function endPress(hand)
	local press = presses[hand]
	presses[hand] = nil
	if press ~= nil and press.owner ~= nil then uevrUtils.executeUEVRCallbacks(OWNER_CHANGED, hand, nil, press.owner) end
end

local function onPreInput(retval, userIndex, state)
	if userIndex ~= 0 or state == nil or state.Gamepad == nil then return end
	local now = os.clock()
	for _, hand in ipairs(hands) do
		pressed[hand] = uevrUtils.isButtonPressed(state, gripButtons[hand])
		if pressed[hand] then
			if presses[hand] == nil then startPress(hand, state, now) end
			presses[hand].age = now - presses[hand].startTime
		elseif presses[hand] ~= nil then
			endPress(hand)
		end
	end
	-- Chord claims are asked once per frame with both presses.
	local chordName, chordPriority, chordHide = nil, nil, nil
	local left, right = presses[Handed.Left], presses[Handed.Right]
	if left ~= nil and right ~= nil then
		for _, claim in ipairs(claims) do
			if claim.chord then
				local p = claim.func(state, left, right)
				if p ~= nil and (chordPriority == nil or p > chordPriority) then chordName, chordPriority, chordHide = claim.name, p, claim.hide end
			end
		end
	end
	for _, hand in ipairs(hands) do
		local press = presses[hand]
		if press ~= nil then
			-- Shared continuous claims are recorded every frame; shared start claims keep what they said at the start.
			for _, claim in ipairs(claims) do
				if claim.shared and claim.continuous then
					press.shared[claim.name] = claim.func(hand, state, press) ~= nil and claim.hide or nil
				end
			end
			setOwner(press, resolveOwner(press, state, chordName, chordPriority, chordHide))
			if press.owner ~= nil and press.ownerHide == M.Hide.Systems then uevrUtils.unpressButton(state, gripButtons[hand]) end
			-- A press an interact owns holds the game's interact button.
			for _, interact in ipairs(interacts) do
				if press.owner == interact.name then uevrUtils.pressButton(state, interact.button) end
			end
		end
	end
end

-- Hides owned presses (and presses a hiding shared claim is claiming, or a hider hides) from the game, after every other input
-- callback. Every hand is decided before any is hidden, so hiders see the input as the other systems left it.
local function onPostInput(retval, userIndex, state)
	if userIndex ~= 0 or state == nil or state.Gamepad == nil then return end
	local hide = {}
	for _, hand in ipairs(hands) do
		local press = presses[hand]
		if press ~= nil then
			local hidden = press.owner ~= nil and press.ownerHide ~= M.Hide.None
			for _, sharedHide in pairs(press.shared) do
				if sharedHide ~= M.Hide.None then hidden = true end
			end
			for _, hider in ipairs(hiders) do
				if hidden then break end
				hidden = isHiddenBy(hider, hand, state)
			end
			hide[hand] = hidden
		end
	end
	for _, hand in ipairs(hands) do
		if hide[hand] then uevrUtils.unpressButton(state, gripButtons[hand]) end
	end
end

local function installHooks()
	if hooksInstalled then return end
	hooksInstalled = true
	uevrUtils.registerOnPreInputGetStateCallback(onPreInput, M.PRE_INPUT_PRIORITY)
	uevrUtils.registerOnPostInputGetStateCallback(onPostInput, M.POST_INPUT_PRIORITY)
end

-- Hides presses from the pre-input callbacks below fromPriority, for the hiders registered with it. Every hand is decided before any
-- is hidden.
local function installHiderHook(fromPriority)
	if hiderHooks[fromPriority] then return end
	hiderHooks[fromPriority] = true
	uevrUtils.registerOnPreInputGetStateCallback(function(retval, userIndex, state)
		if userIndex ~= 0 or state == nil or state.Gamepad == nil then return end
		local hide = {}
		for _, hand in ipairs(hands) do
			for _, hider in ipairs(hiders) do
				if hider.fromPriority == fromPriority and isHiddenBy(hider, hand, state) then
					hide[hand] = true
					break
				end
			end
		end
		for _, hand in ipairs(hands) do
			if hide[hand] then uevrUtils.unpressButton(state, gripButtons[hand]) end
		end
	end, fromPriority)
end

function M.registerHider(name, hideFunc, options)
	if type(name) ~= "string" or type(hideFunc) ~= "function" then return end
	options = options or {}
	hiders[#hiders + 1] = {name = name, func = hideFunc, fromPriority = options.fromPriority}
	installHooks()
	if options.fromPriority ~= nil then installHiderHook(options.fromPriority) end
end

function M.registerClaim(name, claimFunc, options)
	if type(name) ~= "string" or type(claimFunc) ~= "function" then return end
	options = options or {}
	local chord = options.chord == true
	claims[#claims + 1] = {
		name = name,
		func = claimFunc,
		chord = chord,
		continuous = chord or options.continuous == true,
		shared = not chord and options.shared == true,
		hide = options.hide or M.Hide.Game,
	}
	installHooks()
end

function M.getOwner(hand)
	local press = presses[hand]
	return press ~= nil and press.owner or nil
end

function M.isOwner(hand, name)
	return M.getOwner(hand) == name
end

function M.hasClaim(hand, name)
	local press = presses[hand]
	return press ~= nil and press.shared[name] ~= nil
end

function M.yield(hand, name)
	local press = presses[hand]
	if press == nil or press.owner ~= name then return end
	press.yielded[name] = true
	-- Until the next frame decides again (when continuous and chord claims are asked), the next start claim in line holds the press.
	local start = currentStart(press)
	setOwner(press, start ~= nil and start.name or nil, start ~= nil and start.hide or nil)
end

function M.isPressed(hand)
	return pressed[hand] == true
end

function M.getPress(hand)
	return presses[hand]
end

function M.setGripButton(hand, button)
	if gripButtons[hand] ~= nil and button ~= nil then gripButtons[hand] = button end
end

function M.registerOwnerChangeCallback(func)
	uevrUtils.registerUEVRCallback(OWNER_CHANGED, func)
end

------------------- Busy hands -------------------
local busyHands = {[Handed.Left] = {}, [Handed.Right] = {}} -- hand -> {name -> true}

uevrUtils.registerUEVRCallback(M.HAND_BUSY_EVENT, function(hand, name, busy)
	if busyHands[hand] == nil or type(name) ~= "string" then return end
	busyHands[hand][name] = busy == true or nil
end)

function M.isHandBusy(hand)
	return busyHands[hand] ~= nil and next(busyHands[hand]) ~= nil
end

------------------- Claimed prompts -------------------
local claimedPrompts = {} -- name -> true

uevrUtils.registerUEVRCallback(M.PROMPT_CLAIMED_EVENT, function(name, claimed)
	if type(name) ~= "string" then return end
	claimedPrompts[name] = claimed == true or nil
end)

function M.isPromptClaimed()
	return next(claimedPrompts) ~= nil
end

------------------- Interact -------------------
-- A grip presses the game's interact button for what the game's prompt is on, and the prompt shows the grip's button. update (on
-- an interval, on the game thread) decides both: it sets each hand's ready flag and what the prompt shows from the same check. The
-- claim only reads the flag, so nothing of the game's is touched in the input callback.
local Interact = {}
Interact.__index = Interact

local function resolve(value, ...)
	if type(value) == "function" then return value(...) end
	return value
end

-- What tells one target from another: a UObject's address, any other value itself.
local function getTargetKey(target)
	if type(target) == "userdata" and target.get_address ~= nil then return target:get_address() end
	return target
end

local function toPromptList(result)
	if result == nil then return nil end
	if type(result) == "table" then return result end
	return {result}
end

local function hasLivePrompts(list)
	if list == nil or #list == 0 then return false end
	for _, prompt in ipairs(list) do
		if uevrUtils.getValid(prompt) == nil then return false end
	end
	return true
end

local function isHandReady(self, hand, target)
	if target == nil or M.isHandBusy(hand) then return false end
	-- A grip already down for something else can't start an interact (it stays ready during a press of its own).
	local press = presses[hand]
	if press ~= nil and press.owner ~= self.name then return false end
	return self.canClaim == nil or self.canClaim(hand) ~= false
end

function Interact:update()
	local target = nil
	-- A prompt another system has claimed (e.g. a mechanism worked by hand) is not an interact's.
	if self.enabled and not M.isPromptClaimed() then
		target = self.getInteractTarget()
		if type(target) == "userdata" then target = uevrUtils.getValid(target) end
	end
	local readyHand = nil
	for _, hand in ipairs(self.hands) do
		local ready = isHandReady(self, hand, target)
		self.ready[hand] = ready
		if ready and readyHand == nil then readyHand = hand end
	end
	self.target, self.readyHand = target, readyHand
	if self.override == nil then return end
	local key = getTargetKey(target)
	if key ~= self.targetKey then
		-- Games reuse prompt objects, so the last target's prompt is put back before it can show up on something else.
		self.override:restore()
		self.targetKey, self.prompts = key, nil
	end
	if target ~= nil and not hasLivePrompts(self.prompts) then self.prompts = toPromptList(self.prompt.getPrompts(target)) end
	self.override:update()
end

function Interact:setEnabled(value)
	self.enabled = value == true
	self:update()
	if not self.enabled then
		for _, hand in ipairs(self.hands) do M.yield(hand, self.name) end
	end
end

function Interact:isEnabled()
	return self.enabled
end

function Interact:isReady(hand)
	return self.ready[hand] == true
end

function Interact:getTarget()
	return self.target
end

function M.registerInteract(options)
	options = options or {}
	local prompt = options.prompt
	if type(options.getInteractTarget) ~= "function" or options.button == nil then return nil end
	if prompt ~= nil and (type(prompt.getPrompts) ~= "function" or type(prompt.get) ~= "function" or type(prompt.set) ~= "function"
		or prompt.to == nil) then return nil end
	local self = setmetatable({
		name = options.name or "interact",
		priority = options.priority or M.LOW,
		hands = options.hands or {Handed.Left},
		button = options.button,
		getInteractTarget = options.getInteractTarget,
		canClaim = options.canClaim,
		prompt = prompt,
		enabled = options.enabled == true,
		ready = {}, -- hand -> boolean, as of the last update
	}, Interact)
	if prompt ~= nil then
		-- Required here so mods that never register an interact don't load libs/prompts. No timer of its own: update drives it, so
		-- the prompt changes in the same check that sets the ready flags.
		local prompts = require("libs/prompts")
		self.override = prompts.new({
			interval = false,
			enabled = true,
			getPrompts = function() return self.prompts end,
			get = prompt.get,
			set = prompt.set,
			equals = prompt.equals,
			getReplacement = function(_, original)
				if self.readyHand == nil then return nil end
				if prompt.from ~= nil then
					local from = resolve(prompt.from)
					if from == nil or not self.override.equals(original, from) then return nil end
				end
				return resolve(prompt.to, self.readyHand, self.target)
			end,
		})
	end
	interacts[#interacts + 1] = self
	M.registerClaim(self.name, function(hand)
		if self.ready[hand] then return self.priority end
		return nil
	end, {hide = options.hide})
	uevrUtils.setInterval(options.interval or 250, function() self:update() end)
	uevrUtils.registerLevelChangeCallback(function()
		self.target, self.targetKey, self.prompts, self.readyHand, self.ready = nil, nil, nil, nil, {}
	end)
	return self
end

return M
