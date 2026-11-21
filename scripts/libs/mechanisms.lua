--[[
Usage
    Drop the libs folder containing this file into your project folder
    Add code like this in your script:
        local mechanisms = require("libs/mechanisms")

    Lets VR hands work the game's own mechanisms (things to push, levers, buttons, handles) with a hand movement instead of a
    button press. It holds no game knowledge. A mechanism is described by three independent parts:

        Kind        how a hand's position counts as working the mechanism (its constraint). Registered by name with
                    registerKind, so new kinds are added without changing anything else. Supplied here: "push", "contact",
                    "ladder".
        Driver      how the game is told, and how the game's own state is read back. A table of functions, so each game (or
                    each mechanism) supplies its own. Supplied here: holdButtonDriver, for mechanisms the game works while a
                    button is held, tapButtonDriver, for mechanisms the game works on its own after one press, and climbDriver,
                    for things the hands climb while the game rests between its own steps.
        Engagement  how the hands connect. Supplied here: contact (hands in the kind's zone, no button), grip (a hand in the
                    zone takes hold with its grip button and holds on while the button is held; options.grip), and Engage
                    With, a setting of every other mechanism (options.engageWith): Reach, contact as above, or Grip, where a
                    grip press that starts with the hand in contact starts it, and its release setting says when it lets go.

    The game stays in charge of the mechanism: its animation, timing and result are the game's own. This module only decides
    when the hands are working it, and has the driver act for as long as they are.

    How a mechanism runs
        Idle: every scanInterval, find() is asked for the actor the game would act on now (e.g. the one showing its prompt).
        With an actor: each tick the hands are placed in the actor's frame and the kind says which are in contact. With `hands`
        of them in contact it engages: the driver's onInput runs on every input frame (the hold button driver presses its
        button).
        Engaged: it stays engaged while `keepHands` hands are in contact. Contact lost for longer than releaseGrace releases it
        (the driver stops), as does the actor going away or isAllowed turning false. When the driver says the game finished it,
        it is done. When the driver says the game is not (or no longer) working it after startTimeout, it is released and the
        hands must leave the zone before it can engage again, so a refused mechanism is not pressed over and over.

    Available functions:

    mechanisms.new(options) -> Mechanism|nil
        options:
            name: string (default "mechanism") - for log messages
            kind: string (required) - a registered kind, e.g. "push"
            find: function() -> actor|nil (required)
                The actor the game would act on now, or nil. Asked every scanInterval while not engaged.
            driver: table (required) - see Drivers
            getFrame: function(actor) -> actor|scene component (optional)
                What the kind's zone is fixed to. Default: the actor itself. Positions are in its axes (x forward, y right,
                z up, cm, unscaled).
            isAllowed: function() -> boolean (optional) - false keeps it from engaging and releases it (menus, cutscenes)
            getContactPoint: function(actor, hand) -> world location|nil (optional)
                Where the hand starts working the mechanism (e.g. where a hand accessory will place it). A hand within
                contactDistance of it is in contact, in place of the kind's own start test. nil for a hand: the kind's test
                is used for that hand. Only asked while not engaged (with latchContact, while engaged too, so a hand can
                join); staying engaged is otherwise the kind's test.
            contactDistance: cm (default 15)
            latchContact: boolean (default false) - once engaged, a hand in contact stays in contact until the mechanism is
                released or done, wherever it goes. For mechanisms the game works on its own once started (one press), where
                the hands ride along on the mechanism rather than keep working it. For a mechanism made in code it only sets
                the default release (GameFinishes, see release), which decides.
            hands: number (default 2) - hands that must be in contact to engage
            keepHands: number (default 1) - hands that must stay in contact to remain engaged
            grip: table (optional) - the hands take hold with their grip buttons (libs/grip) instead of by contact alone. A grip
                press that starts with the hand in contact (the kind's zone, or its contact point or hand spot) is claimed for the
                mechanism, and the hand is then in contact for as long as it holds that press, wherever it goes; hands and keepHands
                count the hands holding on. When an engagement ends, a press still held no longer counts: the hand takes hold again
                with a new press. A claimed press stays the mechanism's (hidden as below) until it is let go of.
                priority: number (required) - the claim's priority in libs/grip (the mod's own order of grip claims)
                hide: grip.Hide value (default grip.Hide.Systems) - what the press is hidden from while the mechanism owns it
            engageWith: mechanisms.EngageWith value (default Reach) - how a hand starts working it. Not with options.grip. Its
                saved setting comes first (see Entries).
                Reach: a hand in contact starts it.
                Grip: a grip press that starts with the hand in contact (its contact point or hand spot within contactDistance,
                    else the kind's zone) starts it. libs/grip asks on the press's first frame, so nothing is measured on the tick
                    until a hand takes hold. The press is hidden from the other systems (grip.Hide.Systems) until it is let go of.
                    A hand joins an engaged mechanism the same way, and a hand that loses contact has to press again.
            engageGripPriority: number (optional) - the Grip claim's priority in libs/grip. Default: the game adapter's
                engageGripPriority, else mechanisms.ENGAGE_GRIP_PRIORITY.
            release: mechanisms.Release value - when the hands let go. Its saved setting comes first (see Entries). Default:
                AfterTime with a releaseAfter, else GameFinishes with latchContact, else PullBack.
                GameFinishes: latched until the driver says the game finished it.
                AfterTime: latched, and done releaseAfter seconds after engaging.
                PullBack: the kind's own test says when a hand is no longer in contact.
                GripReleased: only with Grip (otherwise as GameFinishes): a hand is in contact while it holds its press,
                    wherever it goes.
            releaseGrace: seconds (default 0.4) - how long contact may be lost before it is released
            startTimeout: seconds (default 0.5) - how long the game has to start working it before it counts as refused
            scanInterval: seconds (default 0.5)
            releaseAfter: seconds (optional) - with release AfterTime, done this long after engaging, whatever the driver says
                (for mechanisms the game keeps busy a while after the hands have nothing left to do). Off when 0. The hands then
                have to leave before it engages again, as after a refused press, so one the game still offers isn't grabbed
                again at once.
            label: string (default name) - the mechanism's name in the config UI
            findNearest: function() -> actor|nil (optional) - the nearest actor of this mechanism, found or not (e.g. one not
                showing its prompt yet), for testing hand spots in the config UI. Only asked while needed.
            accessoryKey: string (optional) - the mechanism has hand spots (see Entries), saved under this accessory key. A hand
                within contactDistance of its nearest spot is in contact, as with getContactPoint (which comes first if both are
                given), and is put on that spot while it works the mechanism.
            getAccessoryComponent: function(actor) -> component (optional) - what the hand spots are on (default: the game
                adapter's answer, else the actor's root)
            placeHands: table (optional) - the hand spots only place the hands, on a component the game chooses for each hand as
                it takes hold (e.g. the rung it took); the kind's zone (and options.grip) decides contact, not the spots. When a
                hand comes into contact, its spot is the one for that hand nearest it (measured on the spot component above), and
                getTarget is asked once for what to put it on; both are kept until the hand leaves contact. A hand with no spot
                or no target is not placed. Without placeHands nothing here changes.
                getTarget: function(actor, hand, handLocation, spot) -> component|false|nil (required) - what the hand's spot is
                    put on; false: the hand may not hold on there (it is not in contact and, with options.grip, lets go of its grip
                    press, not claimed again until a new press); nil: it holds on where it is, not placed. Asked with spot nil
                    when the hand has no spot: false still refuses the hand, any other answer leaves it where it is.
                    spot: {key, id, location = {x, y, z}, rotation = {x, y, z}}, the spot as saved (relative to the spot
                    component).
                getSpotKeys: function(actor, hand, handLocation, key) -> list (optional) - the accessory keys to look for the
                    hand's spot under, in order: the first with a spot for that hand is used, and is the key libs/accessories is
                    given for the hand. Default {key}, the mechanism's own.
            haptics: table|false (optional) - a short pulse on the hands in contact at each of these events, each
                {duration = seconds, frequency = Hz, amplitude = 0-1} or false:
                engage (default {duration = 0.05, amplitude = 0.5}), phase (default {duration = 0.08, amplitude = 0.7}),
                done (default {duration = 0.15, amplitude = 1})
            onEvent: function(event, actor, ...) (optional)
                "engage", actor
                "phase", actor, phase, oldPhase
                "release", actor|nil, reason      reason: "hands", "refused", "lost", "not_allowed", "disabled", "reset"
                "done", actor
            prompt: table (optional) - the game's prompt for the actor asks for a hand instead of a button while this mechanism
                has the actor (enabled, allowed, found). This module decides when; the game-specific functions do the showing:
                getPrompt: function(actor) -> prompt|nil (required)
                    The game's prompt for the actor (e.g. its widget), or nil while it shows none. It runs on every interval,
                    so keep it to native property reads. The game adapter's is also asked with no actor (nil) by
                    mechanisms.setScanOptimize: any prompt the game shows now, or nil.
                show: function(prompt, text) (required)
                    Makes the prompt ask for a hand (e.g. hides its button and shows text). Called on every interval while it
                    applies, because games rewrite their prompts, so compare before setting.
                hide: function(prompt) (required) - puts the game's own back
                text: string (optional) - passed to show
                gripText: string (optional) - passed to show in place of text while the mechanism engages with Grip
                The mechanism's saved promptText (see Entries), while its promptTextCustom is true, is passed in place of both.
                interval: seconds (default 0.25)
                While a prompt is shown this way the mechanism says so through libs/grip
                (uevrUtils.executeUEVRCallbacks(grip.PROMPT_CLAIMED_EVENT, name, claimed)), so grip.registerInteract leaves that
                prompt and the grip alone.
            plus the kind's own options (see Kinds)

    Mechanism:setPromptText(text)   The text passed to prompt.show in place of prompt.text, for special situations. nil: prompt.text again.
    Mechanism:setEnabled(value)     Disabling releases it. New mechanisms start disabled.
    Mechanism:isEnabled() -> boolean
    Mechanism:isEngaged() -> boolean
    Mechanism:isHandEngaged(hand) -> boolean    The hand is in contact with the engaged mechanism.
    Mechanism:getActor() -> actor|nil           The actor found, engaged or not.
    Mechanism:getProgress() -> number|nil       The driver's progress (0-1) while engaged.
    Mechanism:getPhase() -> any                 The driver's phase while engaged.
    Mechanism:getValue() -> number|nil          The kind's value while engaged (push: cm the hands are past the surface).
    Mechanism:reset()                           Also runs on level change and script reset.
    Mechanism:getName() -> string
    Mechanism:getEntryID() -> string            The saved entry with its settings (see Entries).
    Mechanism:isDataDefined() -> boolean        Made from a saved entry, not in code.
    Mechanism:getType() -> string|nil           Its entry's type (see Types); nil for one made in code.
    Mechanism:getStage() -> string|nil          Its stage of that type; nil for one made in code.
    Mechanism:getLabel() -> string
    Mechanism:findNearest() -> actor|nil        Its nearest actor within 5 meters, offered by the game or not.
    Mechanism:getAccessoryComponent(actor) -> component|nil
    Mechanism:getVariations() -> list           The class names of its variations, sorted.
    Mechanism:usesDefault(className) -> boolean
    Mechanism:isAddedVariation(className) -> boolean
    Mechanism:getSettings(className) -> table   The settings as they apply to a variation (nil: the Default).
    Mechanism:getAccessoryKey(className) -> string|nil      Where a variation's (nil: the Default's) hand spots are saved.
    Mechanism:getAccessoryKeys() -> list
    Mechanism:getSideAccessoryKey(className) -> string|nil  A Ladder's: where a variation's (nil: the Default's) side hand spots
                                                are saved (Climbing's sides); nil for any other type.
    Mechanism:getSideAccessoryKeys() -> list    A Ladder's side accessory keys, the Default's and each variation's; empty otherwise.
    Mechanism:getHandSpotDistance(hand) -> cm|nil, label     The hand's nearest hand spot: how far, and its label.
    Mechanism:getGripAnimation() -> id|nil      The grip animation its stage chose for a hand in contact (Ladder's Climbing:
                                                climbGripAnimation), or nil for the Default: the hand spot's own.
    Mechanism:canEngageWithGrip() -> boolean    Whether Engage With applies to it: not with options.grip, and for an entry only
                                                in a stage with Button's settings.
    Mechanism:getPromptTexts() -> text, gripText    Its prompt option's text ("" when it gives none) and gripText; both nil
                                                without a prompt. For the config UI (what a blank promptText shows).

    mechanisms.init(isDeveloperMode, logLevel)
        Makes the mechanisms of the saved entries and, in developer mode (default: uevrUtils.getDeveloperMode()), shows
        config/mechanisms_config_dev. Call it after mechanisms.setGameAdapter.
    mechanisms.getMechanisms() -> list          Every mechanism made in code, and one for each saved entry (its type's first
                                                stage; the entry's other stages answer the same for everything about the entry).

    mechanisms.isHandEngaged(hand) -> boolean
        True while the hand is in contact with any engaged mechanism. For other systems that share the hands.
    mechanisms.getEngagedMechanism(hand) -> Mechanism|nil
        The engaged mechanism (any stage of an entry) the hand is in contact with, e.g. to give a hand climbing a ladder a pose of
        its own (getType() == "ladder" and getStage() == "climb").

    mechanisms.toFrameSpace(frame, location) -> x, y, z | nil
        A world location in the axes of an actor or scene component.

    Kinds
        mechanisms.registerKind(name, kind)
            kind: table
                configure: function(options) -> settings
                    Called once by mechanisms.new with its options; returns whatever evaluate needs.
                evaluate: function(settings, x, y, z, engaged, headX, headY, headZ, actor) -> inContact, value
                    headX, headY, headZ: the head's position in the frame (nil when it is not known), for kinds that judge a hand
                    against the player's body.
                    actor: the mechanism's actor, for kinds whose zone depends on the thing (e.g. a ladder's height).
                    x, y, z: a hand's position in the mechanism's frame. engaged: whether the mechanism is engaged, so a kind
                    can be easier to stay in than to enter.

        "push": the hands push on a flat surface. options:
            surface: table (required)
                origin: {x, y, z} - the centre of the surface, in the frame
                normal: {x, y, z} - pointing from the surface toward the player, in the frame (default {1, 0, 0})
                radius: cm (default 50) - how far from the centre, along the surface, a hand may be
            enterDistance: cm (default 10) - a hand this close in front of the surface (or past it) is in contact
            exitDistance: cm (default 40) - once engaged, a hand stays in contact up to this far in front
            exitMargin: cm (default 25) - once engaged, added to the radius
            maxDepth: cm (default 100) - how far past the surface a hand may be
            keepReach: cm (optional) - once engaged, a hand stays in contact while it is at least this far ahead of the head,
                toward the surface, in place of exitDistance. For mechanisms where the game moves the player while they are
                worked (a distance from the surface then says nothing about whether the arm is still stretched out).

        "contact": no zone of its own. A hand is in contact only within contactDistance of its contact point (getContactPoint),
            so a mechanism of this kind needs getContactPoint, and usually latchContact (otherwise no hand stays in contact
            once engaged). No options.

        "ladder": the hands take hold of a ladder's rungs (usually with options.grip and climbDriver). A hand is in contact in a
            strip in front of the rung plane: at most reach in front of it on the player's side and at most behind past it, within
            halfWidth of its centre line, and between the ladder's bottom and aboveTop over its top. Its value is the hand's height
            above the bottom, in cm. options:
            ladder: table
                origin: {x, y, z} (default {0, 0, 0}) - a point on the rung plane's centre line, in the frame
                normal: "x" or "y" (default "x") - the frame axis the rung plane faces along (the rungs run along the other one)
                side: 1 or -1 (default 1) - the player climbs on the + (1) or - (-1) side of the rungs, along normal
                reach: cm (default 30), behind: cm (default 30), halfWidth: cm (default 45), aboveTop: cm (default 40)
                getBounds: function(actor) -> bottom, top (optional) - the ladder's bottom and top in the frame's z, in cm. Asked
                    once per ladder (kept by its address) once it gives them. Without it the strip has no height limits, and the
                    value is the height above origin.
                getAxes: function(actor) -> normal, side (optional) - normal and side for each ladder, in place of the ones
                    above. Asked and kept with getBounds.
                allowAt: function(actor, across) -> boolean (optional) - false: a hand at across (cm along the rungs from the
                    centre line, signed) is not in contact, e.g. on a part of the ladder that is switched off. Asked each time.

    Drivers
        A table with any of (engagedFor: seconds since the mechanism engaged):
            onInput: function(actor, state, engagedFor) - called on every input frame (XInput state, user 0) while engaged
            isActive: function(actor, engagedFor) -> boolean - the game is working the mechanism now
            isDone: function(actor, engagedFor) -> boolean - the game finished it
            getProgress: function(actor, engagedFor) -> number - 0 to 1
            getPhase: function(actor, engagedFor) -> any - a value that changes as the game moves through the mechanism's stages
            onTick: function(actor, delta, engagedFor, mechanism) - called on every engine tick while engaged, after the checks
                that can release it or finish it, for drivers that act every tick (e.g. moving the player). Not called while
                paused (mechanisms.setPaused).
            onEngage: function(actor, mechanism) - called when the mechanism engages
            onEnd: function(actor|nil, reason, mechanism) - called when an engagement ends; reason is "done" or a release reason
                (see onEvent). With onEngage, for drivers that keep state for each engagement.

        mechanisms.holdButtonDriver(options) -> driver
            Holds a button for as long as the mechanism is engaged, for mechanisms the game works while a button is held.
            The button is pressed after the other input callbacks (post-input, priority mechanisms.POST_INPUT_PRIORITY), so
            remaps don't change it.
            options:
                button: XINPUT button (required)
                isActive, isDone, getProgress, getPhase: as above (optional)

        mechanisms.tapButtonDriver(options) -> driver
            Presses a button once, for the first `duration` seconds of an engagement, for mechanisms the game works on its
            own after one press. Pressed post-input like holdButtonDriver. Give it an isActive, so a press the game refuses
            (a locked door) releases the mechanism and waits for the hands to leave instead of pressing again.
            options:
                button: XINPUT button (required)
                duration: seconds (default 0.15)
                isActive, isDone, getProgress, getPhase: as above (optional)

        mechanisms.climbDriver(options) -> driver
            Moves the player with the hands, for things the game climbs a step at a time (a ladder). While the game rests on the
            thing (isIdle), the most recent hand to take hold keeps its place: its real-world height change moves the player the
            opposite way. Letting go with one hand never makes the player jump. The player stays inside the range the game rests
            in; pulling dismountOvershoot past either end pushes the stick toward that end, until the game starts its own way off
            (isDismounting) or for dismountStickSeconds, while the mechanism stays engaged. While a hand holds on at rest, the
            stick's up/down is cleared so the game doesn't also step. The game has to keep a location written while it rests and
            start its next step from there. Each call makes a driver for one mechanism (it keeps that mechanism's climbing).
            Usually with kind "ladder", options.grip and hands = 1.
            options:
                isIdle: function(actor) -> boolean (required) - the game is resting on the thing, between its own steps. Asked on
                    every tick while engaged.
                getRange: function(actor) -> lowZ, highZ (required) - the player's world Z (actor location) range the game rests
                    in. Asked when it engages, and again until it gives both.
                getRungPitch: function(actor) -> cm (optional) - for a pulse at each rung passed (counted up from lowZ)
                isDismounting: function(actor) -> boolean (optional) - the game started its own way off; ends the stick push
                dismountOvershoot: cm (default 15)
                dismountStickSeconds: seconds (default 1.5)
                getPawn: function() -> actor (default: the local pawn)
                moveBody: function(pawn, location) (optional) - moves the player (default: K2_SetActorLocation, teleporting)
                grabHaptic: {duration, frequency, amplitude} | false (default a short pulse) - on the hand, as it takes hold
                rungHaptic: {duration, frequency, amplitude} | false (default a faint pulse) - on the holding hand, at each rung
                steps: table (optional) - plays the game's own step while the hands climb, so the body steps instead of sliding.
                    At rest, a pull of startDistance from where the game came to rest pushes the stick for one step that way (only
                    while the next rest, length on, is inside the range). As the game's step starts it is held still at the hands'
                    share of length, and the body goes on moving with the hands. It plays on from near its end once the hands are
                    finishPhase of length on, back reverseDistance past where it started, or have let go, and the game comes to
                    rest where the body is. Off for an engagement that isEnabled says no to; without every function, always off.
                    isEnabled: function(actor) -> boolean - asked as it engages
                    getLength: function(actor) -> cm - how far one of the game's steps moves the player; asked as it engages
                    getStep: function(actor) -> step, direction - the game's step now playing (1 up, -1 down), or nil
                    hold: function(actor, step, phase) - keeps the step still at phase (0 to 1) of it, and the player from moving
                        on by itself. Called on every tick while it is held.
                    finish: function(actor, step) - lets the step play on from near its end. Also called when the engagement ends
                        with a step held.
                    start: function(actor, direction) (optional) - the stick is about to be pushed for a step (1 up, -1 down), the
                        tick before the game starts it (e.g. to keep the step's first tick from moving the player).
                    cancel: function(actor) (optional) - a step asked for with start ended without finish: the game didn't step
                        within startSeconds, came to rest by itself while it was held, or the engagement ended before it started.
                    startDistance: cm (default 3), finishPhase: 0 to 1 (default 0.95), reverseDistance: cm (default 3),
                    startSeconds: how long to wait for the step after pushing the stick (default 0.5), finishSeconds: how long to
                        wait for the rest after finish (default 1)
                isActive, isDone, getProgress, getPhase: as above (optional)

    Entries (mechanisms without code)
        Most mechanisms need no code of their own. A game describes its interactions once, with mechanisms.setGameAdapter, and each
        mechanism is then a saved entry (libs/core/params, in mechanisms_parameters.json, read in every mode) that
        config/mechanisms_config_dev adds and edits in developer mode: stand at the thing and press Add.

        A mechanism is one way of working things (e.g. "Sliding Door"). Its entry has:
            type                how its things are worked: one of the library's types (see Types). Not saved: "button".
            class               its own class. Every actor of that class, or of a class derived from it, belongs to the mechanism
                                (unless a mechanism with a nearer class of its own takes it).
            the Default         its settings, which are its type's. Button's (mechanisms.SETTING_KEYS):
                action, button      what reaching does: tap the button once (M.Action.Tap) or hold it (M.Action.Hold); button
                                    is an index into mechanisms.BUTTONS
                contactDistance     reach, cm: how near its hand spot a hand has to be
                engageWith          how a hand starts it (M.EngageWith): reaching its spot (Reach), or a grip press that starts
                                    within reach of it (Grip; see mechanisms.new's engageWith). Reach while button is a grip
                                    (mechanisms.isGripButton): libs/grip would clear the button pressed for the game.
                promptText          what the prompt says for it (options.prompt) while promptTextCustom is true, in place of
                                    prompt.text or, with Grip, prompt.gripText (an empty text too)
                promptTextCustom    true: promptText is its own text; false (default): the prompt's own, whatever promptText is
                release             when the hands let go: when the game finishes (M.Release.GameFinishes), after releaseAfter
                                    seconds (AfterTime), when the hand is pulled back from its spot (PullBack), or, with Grip,
                                    when the hand lets go of its grip (GripReleased; with Reach, as GameFinishes)
                accessoryKey        where its hand spots are saved (default: the entry's ID)
            variations          by class name, the kinds of thing the mechanism works. One uses the Default (useDefault) or has
                                the same settings, and hand spots, of its own: the first time it stops using the Default it gets
                                a copy of them to change, and its own are kept from then on, used or not. A class that belongs
                                to the mechanism works without being listed; in developer mode the config UI lists each one it
                                sees (mechanisms.discoverVariations). A class that is not derived from the mechanism's own can
                                be put under it by hand (added).
        Hand spots are accessories (libs/accessories) saved under the accessory key, placed with the accessory editor in the config
        UI, on the game adapter's getAccessoryComponent(actor). A hand is in contact within reach of the nearest spot for that hand,
        and is put on that spot while it works the mechanism, so a thing worked from several places (each side of a door) just has a
        spot at each. This module answers libs/accessories' target callback itself, at the game adapter's accessoryPriority.

        A mechanism made in code (mechanisms.new) also has a saved entry, under its name, for its reach (contactDistance), its
        engageWith, release and releaseAfter (in place of the options of the same names) and its hand spots
        (options.accessoryKey). Its PullBack is its kind's own test. It has no variations.

    Types
        A type is a way things are worked, supplied by this library (mechanisms.getTypes); a game never defines one. A type has
        stages: parts of working the thing, each active while the thing is in the stage's state, what the game is doing with it
        now (mechanisms.State):
            offered     the game offers it (e.g. its prompt shows)
            busy        the game is working it (e.g. the player is on the ladder)
        The game adapter tells an actor's state (getState, or isBusy and isOffered). Each stage of an entry is a mechanism of its
        own, which finds the entry's actors (its class, its added variations, not its removed ones) that are in the stage's state.
        The type's first stage is named after the entry's ID, the others "<entry ID>:<stage>". The stages of an entry share its
        settings, variations and hand spots. A stage can be optional: a setting of its type (true or false, for each variation)
        switches it on or off, and it then leaves out the actors whose variation has it off. A stage that needs adapter functions
        the game doesn't supply finds nothing; mechanisms.getMissingAdapterFunctions lists them, for the config UI. Nothing falls
        back to another type.
            "button" (Button, the default): one stage, while the thing is offered: reach a hand spot (or, with Grip, grip within
                reach of it), then tap or hold the button, and let go when the game finishes, after a set time, when the hand
                pulls back, or when it lets go of its grip. Needs the offered state, and
                the busy state for the game taking the press (isFinished: optional). Settings: as listed under the Default above.
            "ladder" (Ladder): two stages.
                Getting on ("geton", the entry's ID), while the game offers the ladder: Button's stage, with Button's settings and
                    the entry's hand spots. Off for a variation with useGetOn = false (a game that puts the player on a ladder by
                    itself), and while the player is at the ladder's top (above the middle of the adapter's ladder.getRange),
                    where nothing is changed: the game's own prompt and button get the player on.
                Climbing ("climb"), while the ladder is busy (the player is on it): a grip on the ladder takes hold (kind "ladder",
                    options.grip), and pulling down with it climbs (climbDriver): only while the game rests between its own steps,
                    inside the range it rests in; pulling past either end pushes the stick so the game plays its own way off; the
                    stick's up/down is cleared while a hand holds on; a pulse only as a hand takes hold. Needs the busy state and
                    the adapter's ladder functions. A hand holds one of two parts of the ladder, each with settings of its own:
                    Rungs (rungGrip, default true; with sideGrip off, the whole width): with snapHands (default true), a hand
                        that takes hold is put on its hand spot (the entry's), moved by whole rungs to
                        the rung it took; with rungKeepAlong (default false) also moved along the rung to the hand, so only its
                        height and depth are snapped. With snapNear (default false), only a hand that takes hold within snapDistance (cm, up
                        or down; default 5) of its rung takes hold (and is put on it); a grip further away doesn't take hold, so
                        it doesn't climb. climbGripAnimation (an id of the hands parameters file's grip animations; default "",
                        the Default) is the grip animation the game gives a hand holding a rung (Mechanism:getGripAnimation);
                        with the Default the hand uses its hand spot's.
                    Sides (sideGrip, default false): from sideStart (cm, default 16) out from the rungs' centre line, either
                        way. A hand holds on where it took hold; with sideSnap (default false) it is put on its side hand spot
                        (Mechanism:getSideAccessoryKey; with none for that hand, its hand spot) at the height it took hold at:
                        lined up with the side, never moved up or down. Its grip animation is its spot's.
                    With animateSteps (default false) and the
                    adapter's step functions, the game's own step plays as the hands pull (climbDriver's steps), so the body
                    steps instead of sliding; off, climbing is as above.
                Settings: useGetOn (default true), Button's, snapHands, snapNear, snapDistance, climbGripAnimation, animateSteps,
                    rungGrip, rungKeepAlong, sideGrip, sideStart, sideSnap.

        mechanisms.setGameAdapter(adapter)
            adapter: table, any of
                getState: function(actor) -> state|nil - what the game is doing with the actor now (a mechanisms.State value,
                    see Types). Without it, an actor's state is built from isBusy (busy) and isOffered (offered), busy first.
                isOffered: function(actor) -> boolean - the game would act on the actor now (e.g. it shows its prompt and is not
                    in use)
                isBusy: function(actor) -> boolean - the game is working the actor
                isFinished: function(actor) -> boolean - the game finished it
                isAllowed: function() -> boolean - false keeps every entry from engaging (menus, cutscenes)
                getAccessoryComponent: function(actor) -> component - what hand spots are on (default: the actor's root)
                isHandReady: function(hand) -> boolean - false while a hand can't be put on anything (e.g. being rebuilt)
                isScanNeeded: function() -> boolean (optional) - with mechanisms.setScanOptimize(true), true when the game has
                    something for a mechanism although it shows no prompt (e.g. the player is interacting). The prompt check
                    itself is made by this module with prompt.getPrompt.
                ladder: table - what the Ladder type's Climbing needs to know (see Types):
                    isIdle: function(actor) -> boolean - the game rests between its own steps (asked on every tick while climbing)
                    getRange: function(actor) -> lowZ, highZ - the player's world Z (actor location) range the game rests in
                    getRungs: function(actor) -> count, topZ, pitch - how many rungs, the top one's world Z, and their spacing
                        (cm). The ladder stands upright. Asked once per ladder.
                    getFrame: function(actor) -> frame, normal, side - what the rung zone is fixed to (the actor or a scene
                        component, with the rungs' centre line through its origin), the frame axis the rungs face along ("x" or
                        "y"), and the player's side along it (1 or -1)
                    isDismounting: function(actor) -> boolean (optional) - the game started its own way off
                    gripPriority: number (optional, default 1000) - the climb's grip claim priority in libs/grip
                    For animateSteps (optional; without all four, steps stay off):
                    getStep: function(actor) -> step, direction - the game's climbing step now playing (1 up, -1 down), or nil
                    holdStep: function(actor, step, phase) - keeps it still at phase (0 to 1), and the player from moving by itself
                    finishStep: function(actor, step) - lets it play on from near its end
                    startStep: function(actor, direction) (optional) - the stick is about to be pushed for a step (climbDriver's
                        steps.start)
                    cancelStep: function(actor) (optional) - a step asked for ended without finishStep (climbDriver's steps.cancel)
                    stepLength: cm - how far one of the game's steps moves the player
                prompt: table - as mechanisms.new's prompt option, for every entry
                engageGripPriority: number (optional) - the Grip claim's priority in libs/grip, for every mechanism that gives
                    none (mechanisms.new's engageGripPriority)
                accessoryPriority: number (optional) - the priority of this module's answer to libs/accessories' target callback,
                    against the game's other targets (e.g. a vehicle's). Default mechanisms.ACCESSORY_TARGET_PRIORITY.
                baseClass: string - the class every interactable derives from (e.g. "Class /Script/Game.InteractableBase"), or
                getOffered: function() -> actor|nil - the actor the game offers now. For the config UI's "In front of you".
                getCurrent: function() -> actor|nil, state - the actor the game offers or the player is using now, and its state
                    (optional: asked otherwise with getState). Without it: getOffered's actor, else the first actor of baseClass
                    that is offered, else the first that has any other state.
        mechanisms.hasGameAdapter() -> boolean      Whether the game set one (the config UI then can find things with it).
        mechanisms.setEntriesEnabled(value)         Enables or disables every mechanism made from a saved entry (default: enabled).
        mechanisms.setPaused(value), mechanisms.isPaused()     Mechanisms work as usual but never press the game's button
                                                    (the config UI's Disable Mechanisms).
        mechanisms.setScanOptimize(value)           The mechanisms not in use scan only while the game adapter's prompt.getPrompt
                                                    shows a prompt or its isScanNeeded says true (default: off). An adapter with
                                                    neither always scans.
        mechanisms.getAccessoryTarget(hand) -> component, accessoryKey      What a hand is put on now (this module's answer to
                                                    libs/accessories' target callback).
        mechanisms.getHandAnimations() -> ids, labels | nil     The hand grip animations of the hands parameters file: paired
                                                    lists sorted by label (no Default or None entry), asked from
                                                    libs/hands_animation's get_hand_animation_ids event; nil while it isn't
                                                    loaded. Its on_hand_animation_ids_changed event (info.ids, info.labels)
                                                    says when they change. Save the id, not the list position.
        mechanisms.getOfferedActor() -> actor|nil
        mechanisms.getCurrentActor() -> actor|nil, state    What the game offers or the player is using now (adapter getCurrent).
        mechanisms.getActorState(actor) -> state|nil        What the game is doing with the actor now (see Types).
        mechanisms.getMechanismForActor(actor) -> Mechanism|nil, className      For an entry: its first stage's mechanism.
        mechanisms.getTypes() -> list of {name, label}      Every type, in the library's order.
        mechanisms.getSettingKeys(typeName) -> list         A type's settings, in order.
        mechanisms.getMissingAdapterFunctions(mechanism) -> list    The adapter functions its entry's stages need that the game
                                                    doesn't supply (a stage switched off everywhere is left out); empty when none.
        For the config module:
        mechanisms.addEntry(actor) -> id            A new mechanism for the actor's class.
        mechanisms.removeEntry(id) -> boolean
        mechanisms.addVariation(mechanism, actor) -> className      Puts the actor's class under the mechanism by hand.
        mechanisms.removeVariation(mechanism, className) -> boolean
        mechanisms.setVariationUseDefault(mechanism, className, useDefault) -> boolean
        mechanisms.setSetting(mechanism, className, key, value)     className nil: the Default.
        mechanisms.isGripButton(index) -> boolean   Whether an index into mechanisms.BUTTONS is a grip (Left or Right Bumper).
        mechanisms.setType(mechanism, typeName) -> boolean  Changes an entry's type. Its class, variations, settings and hand spots
                                                    are kept. Its mechanisms are made again, so get them again afterwards.
        mechanisms.discoverVariations() -> boolean  Lists the classes of live actors not listed yet; true when one was added.
        mechanisms.getParamManager(), mechanisms.notifyEntriesChanged()     After changing an entry directly.

    Example (how Silent Hill f pushes a log bundle the game moves while A is held for 5.5 seconds):

        local pushPlank = mechanisms.new({
            name = "push_plank",
            kind = "push",
            find = function()
                -- getPushPlanks: the game's own lookup of the bundles. A class that is unloaded and loaded again with parts of
                -- the world must not be looked up through uevrUtils.find_all_of, which keeps the first class object it found.
                for _, actor in ipairs(getPushPlanks()) do
                    if actor.IsShowingPrompt == true and actor.Succeed ~= true then return actor end
                end
                return nil
            end,
            surface = {origin = {50, 0, 110}, normal = {1, 0, 0}, radius = 80},
            driver = mechanisms.holdButtonDriver({
                button = XINPUT_GAMEPAD_A,
                isActive = function(actor) return actor.IsCurrentUsing == true end,
                isDone = function(actor) return actor.Succeed == true end,
                getProgress = function(actor) return actor.CurrentDuration / actor.CheckDuration end,
            }),
        })
        pushPlank:setEnabled(true)
]]

local uevrUtils = require("libs/uevr_utils")
local controllers = require("libs/controllers")
local grip = require("libs/grip")
local paramModule = require("libs/core/params")
local configui = require("libs/configui")

local M = {}

M.POST_INPUT_PRIORITY = -100

local HANDS = {Handed.Left, Handed.Right}
local HMD = 2 -- controller ID of the headset in libs/controllers
local kinds = {}
local instances = {}
-- The Ladder type (see Types): what each hand's hand spot is put on while it holds the ladder, and the rungs of the last ladder
-- asked.
local ladderState = {rungTargets = {}, rungs = nil}
-- A Ladder's side hand spots are saved under its hand spots' accessory key with this added (Mechanism:getSideAccessoryKey).
local SIDE_SPOTS_SUFFIX = "_sides"
-- Grip claims by name, and the mechanism each is for now: libs/grip can't take a claim back, and an entry's mechanisms are made
-- again (with the same names) when its type changes.
local gripClaims = {}
local hooksInstalled = false

local currentLogLevel = LogLevel.Error
function M.setLogLevel(val)
	currentLogLevel = val
end
function M.print(text, logLevel)
	if logLevel == nil then logLevel = LogLevel.Debug end
	if logLevel <= currentLogLevel then
		uevrUtils.print("[mechanisms] " .. text, logLevel)
	end
end

local function default(value, fallback)
	if value == nil then return fallback end
	return value
end

-- {x, y, z} from a table given either as {1, 2, 3} or {x = 1, y = 2, z = 3}.
local function xyz(value, fallback)
	if type(value) ~= "table" then return fallback end
	return {x = tonumber(value.x or value[1]) or 0, y = tonumber(value.y or value[2]) or 0, z = tonumber(value.z or value[3]) or 0}
end

------------------- Frames -------------------
-- A mechanism's zone is fixed to a frame: an actor or a scene component. Hand positions are expressed in its axes.
-- The frame's origin and axes, read from the game once so several locations can be put in them (readFrameAxes, then
-- toAxesSpace for each location). nil when the frame is neither an actor nor a scene component, or a read fails.
local function readFrameAxes(frame)
	if frame == nil then return nil end
	local origin, forward, right, up
	if frame.K2_GetActorLocation ~= nil then
		origin, forward, right, up = frame:K2_GetActorLocation(), frame:GetActorForwardVector(), frame:GetActorRightVector(), frame:GetActorUpVector()
	elseif frame.K2_GetComponentLocation ~= nil then
		origin, forward, right, up = frame:K2_GetComponentLocation(), frame:GetForwardVector(), frame:GetRightVector(), frame:GetUpVector()
	end
	if origin == nil or forward == nil or right == nil or up == nil then return nil end
	return {origin = origin, forward = forward, right = right, up = up}
end
readFrameAxes = uevrUtils.profiler:wrap("MECHANISMS: readFrameAxes", readFrameAxes)

-- A world location in axes from readFrameAxes. No game calls.
local function toAxesSpace(axes, location)
	if axes == nil or location == nil then return nil end
	local origin, forward, right, up = axes.origin, axes.forward, axes.right, axes.up
	local dx, dy, dz = location.X - origin.X, location.Y - origin.Y, location.Z - origin.Z
	return dx * forward.X + dy * forward.Y + dz * forward.Z, dx * right.X + dy * right.Y + dz * right.Z, dx * up.X + dy * up.Y + dz * up.Z
end

function M.toFrameSpace(frame, location)
	if frame == nil or location == nil then return nil end
	return toAxesSpace(readFrameAxes(frame), location)
end
M.toFrameSpace = uevrUtils.profiler:wrap("MECHANISMS: toFrameSpace", M.toFrameSpace)

------------------- Kinds -------------------
function M.registerKind(name, kind)
	if type(name) ~= "string" or type(kind) ~= "table" or type(kind.configure) ~= "function" or type(kind.evaluate) ~= "function" then
		M.print("registerKind: expected (string name, {configure = function, evaluate = function})", LogLevel.Warning)
		return false
	end
	kinds[name] = kind
	return true
end

-- Push: the hands push on a flat surface. A hand is in contact when it is near enough in front of the surface (or past it) and
-- within the surface's radius. Its value is how far past the surface it is, in cm.
M.registerKind("push", {
	configure = function(options)
		local surface = type(options.surface) == "table" and options.surface or {}
		local normal = xyz(surface.normal, {x = 1, y = 0, z = 0})
		local length = math.sqrt(normal.x * normal.x + normal.y * normal.y + normal.z * normal.z)
		if length < 0.0001 then normal, length = {x = 1, y = 0, z = 0}, 1 end
		return {
			origin = xyz(surface.origin, {x = 0, y = 0, z = 0}),
			normal = {x = normal.x / length, y = normal.y / length, z = normal.z / length},
			radius = default(tonumber(surface.radius), 50),
			enterDistance = default(tonumber(options.enterDistance), 10),
			exitDistance = default(tonumber(options.exitDistance), 40),
			exitMargin = default(tonumber(options.exitMargin), 25),
			maxDepth = default(tonumber(options.maxDepth), 100),
			keepReach = tonumber(options.keepReach),
		}
	end,
	evaluate = function(settings, x, y, z, engaged, headX, headY, headZ)
		local origin, normal = settings.origin, settings.normal
		local dx, dy, dz = x - origin.x, y - origin.y, z - origin.z
		-- Distance in front of the surface (negative: past it), and distance from its centre along it.
		local distance = dx * normal.x + dy * normal.y + dz * normal.z
		local lx, ly, lz = dx - distance * normal.x, dy - distance * normal.y, dz - distance * normal.z
		local lateral = math.sqrt(lx * lx + ly * ly + lz * lz)
		-- Outside the surface's radius, or too far past it.
		local radius = settings.radius + (engaged and settings.exitMargin or 0)
		if lateral > radius or distance < -settings.maxDepth then return false, -distance end
		-- Engaged with keepReach: the hand must stay ahead of the head, toward the surface, wherever the game has moved the player.
		if engaged and settings.keepReach ~= nil and headX ~= nil then
			local headDistance = (headX - origin.x) * normal.x + (headY - origin.y) * normal.y + (headZ - origin.z) * normal.z
			return headDistance - distance >= settings.keepReach, -distance
		end
		local reach = engaged and settings.exitDistance or settings.enterDistance
		return distance <= reach, -distance
	end,
})

-- Contact: only the mechanism's contact points count (see evaluateHands), so the kind itself never reports contact.
M.registerKind("contact", {
	-- No zone: the hands are not placed in the actor's frame for it.
	noZone = true,
	configure = function(options) return {} end,
	evaluate = function(settings, x, y, z, engaged) return false, nil end,
})

-- A ladder's bottom and top (frame z) and its axes (normal along y, side), from options.ladder's getBounds and getAxes (else the
-- options' own normal and side). Kept by the ladder's address once it gives them, so one not ready yet is asked again.
local function getLadderShape(settings, actor)
	local address = actor:get_address()
	if settings.shape.address == address then return settings.shape end
	local bottom, top, normal, side = nil, nil, nil, nil
	if settings.getBounds ~= nil then bottom, top = settings.getBounds(actor) end
	if settings.getAxes ~= nil then normal, side = settings.getAxes(actor) end
	bottom, top = tonumber(bottom), tonumber(top)
	local shape = {address = nil, bottom = bottom, top = top, normalY = settings.normalY, side = settings.side}
	if normal ~= nil then shape.normalY = normal == "y" end
	if side ~= nil then shape.side = (tonumber(side) or 1) < 0 and -1 or 1 end
	local ready = (settings.getBounds == nil or bottom ~= nil or top ~= nil) and (settings.getAxes == nil or normal ~= nil)
	if ready then
		shape.address = address
		settings.shape = shape
	end
	return shape
end

-- Ladder: the hands take hold of a ladder's rungs. A hand is in contact in a strip in front of the rung plane, on the player's side of
-- it (or a little past it), near its centre line, and between the ladder's bottom and a little above its top. Its value is the hand's
-- height above the bottom, in cm.
M.registerKind("ladder", {
	configure = function(options)
		local ladder = type(options.ladder) == "table" and options.ladder or {}
		return {
			origin = xyz(ladder.origin, {x = 0, y = 0, z = 0}),
			normalY = ladder.normal == "y",
			side = (tonumber(ladder.side) or 1) < 0 and -1 or 1,
			reach = default(tonumber(ladder.reach), 30),
			behind = default(tonumber(ladder.behind), 30),
			halfWidth = default(tonumber(ladder.halfWidth), 45),
			aboveTop = default(tonumber(ladder.aboveTop), 40),
			getBounds = type(ladder.getBounds) == "function" and ladder.getBounds or nil,
			getAxes = type(ladder.getAxes) == "function" and ladder.getAxes or nil,
			allowAt = type(ladder.allowAt) == "function" and ladder.allowAt or nil,
			-- The shape of the last ladder asked (getLadderShape), by its address: a ladder doesn't change.
			shape = {address = nil},
		}
	end,
	evaluate = function(settings, x, y, z, engaged, headX, headY, headZ, actor)
		local origin = settings.origin
		local normalY, side, bottom, top = settings.normalY, settings.side, nil, nil
		if actor ~= nil and (settings.getBounds ~= nil or settings.getAxes ~= nil) then
			local shape = getLadderShape(settings, actor)
			normalY, side, bottom, top = shape.normalY, shape.side, shape.bottom, shape.top
		end
		-- Along the rung plane's normal and along the rungs, in the frame.
		local along, across = x - origin.x, y - origin.y
		if normalY then along, across = across, along end
		-- How far the hand is in front of the rung plane, on the player's side (negative: past it).
		local depth = along * side
		if depth > settings.reach or depth < -settings.behind or math.abs(across) > settings.halfWidth then return false, nil end
		-- A part of the ladder the hands may not hold (allowAt), e.g. one switched off.
		if settings.allowAt ~= nil and actor ~= nil and not settings.allowAt(actor, across) then return false, nil end
		local height = z - (bottom or origin.z)
		if bottom ~= nil and z < bottom then return false, height end
		if top ~= nil and z > top + settings.aboveTop then return false, height end
		return true, height
	end,
})

------------------- Drivers -------------------
function M.holdButtonDriver(options)
	options = options or {}
	local button = options.button
	if button == nil then M.print("holdButtonDriver: no button given", LogLevel.Warning) end
	return {
		isActive = options.isActive,
		isDone = options.isDone,
		getProgress = options.getProgress,
		getPhase = options.getPhase,
		onInput = function(actor, state)
			if button ~= nil then uevrUtils.pressButton(state, button) end
		end,
	}
end

function M.tapButtonDriver(options)
	options = options or {}
	local button = options.button
	local duration = default(tonumber(options.duration), 0.15)
	if button == nil then M.print("tapButtonDriver: no button given", LogLevel.Warning) end
	return {
		isActive = options.isActive,
		isDone = options.isDone,
		getProgress = options.getProgress,
		getPhase = options.getPhase,
		onInput = function(actor, state, engagedFor)
			if button ~= nil and (tonumber(engagedFor) or 0) < duration then uevrUtils.pressButton(state, button) end
		end,
	}
end

-- Climbing (climbDriver). A controller's height in tracking space, in metres: unaffected by the player moving in the world, so a hand
-- holding still on a rung reads the same while the body climbs. nil while it isn't tracked (the identity pose at the origin then).
local climbPosition, climbRotation = nil, nil
local function readHandHeight(hand)
	local index = uevrUtils.getControllerIndex(hand)
	if index == nil then return nil end
	if climbPosition == nil then climbPosition, climbRotation = Vector3f.new(0, 0, 0), Quaternionf.new(0, 0, 0, 0) end
	uevr.params.vr.get_pose(index, climbPosition, climbRotation)
	local p = climbPosition
	if p.X * p.X + p.Y * p.Y + p.Z * p.Z < 1e-8 then return nil end
	return p.Y
end
readHandHeight = uevrUtils.profiler:wrap("MECHANISMS: readHandHeight", readHandHeight)

local function getWorldScale()
	return tonumber(string.match(uevr.params.vr:get_mod_value("VR_WorldScale") or "", "[%-%d%.]+")) or 1
end

local STICK_FULL = 32767
local CLIMB_GRAB_HAPTIC = {duration = 0.04, frequency = 1000, amplitude = 0.4}
local CLIMB_RUNG_HAPTIC = {duration = 0.02, frequency = 1000, amplitude = 0.15}

local function climbPulse(hand, haptic)
	if haptic then uevrUtils.triggerHapticVibration(hand, 0, haptic.duration, haptic.frequency, haptic.amplitude) end
end

function M.climbDriver(options)
	options = options or {}
	local isIdle, getRange = options.isIdle, options.getRange
	if type(isIdle) ~= "function" or type(getRange) ~= "function" then
		M.print("climbDriver: isIdle and getRange functions are required", LogLevel.Warning)
		isIdle = function(_) return false end
	end
	local getRungPitch, isDismounting, moveBody = options.getRungPitch, options.isDismounting, options.moveBody
	local getPawn = type(options.getPawn) == "function" and options.getPawn or function() return pawn end
	local overshootLimit = default(tonumber(options.dismountOvershoot), 15)
	local stickSeconds = default(tonumber(options.dismountStickSeconds), 1.5)
	local grabHaptic = default(options.grabHaptic, CLIMB_GRAB_HAPTIC)
	local rungHaptic = default(options.rungHaptic, CLIMB_RUNG_HAPTIC)
	-- options.steps, kept only with every function it needs (otherwise the driver works as without it).
	local steps = type(options.steps) == "table" and options.steps or nil
	if steps ~= nil then
		for _, name in ipairs({"isEnabled", "getLength", "getStep", "hold", "finish"}) do
			if type(steps[name]) ~= "function" then
				M.print("climbDriver: steps." .. name .. " is missing, so steps are off", LogLevel.Warning)
				steps = nil
				break
			end
		end
	end
	local stepOptions = steps or {}
	local stepStartDistance = default(tonumber(stepOptions.startDistance), 3)
	local stepFinishPhase = default(tonumber(stepOptions.finishPhase), 0.95)
	local stepReverseDistance = default(tonumber(stepOptions.reverseDistance), 3)
	local stepStartSeconds = default(tonumber(stepOptions.startSeconds), 0.5)
	local stepFinishSeconds = default(tonumber(stepOptions.finishSeconds), 1)
	-- A step asked for ended without finish (steps.cancel, optional).
	local function cancelStep(actor)
		if steps ~= nil and type(steps.cancel) == "function" then steps.cancel(actor) end
	end

	-- This driver's climbing: each holding hand's height when last read (metres), the holding hands (most recent grab last), the
	-- motion pulled past an end of the range, and the stick pushed toward that end.
	---@class MechanismClimbState
	---@field heights table<integer, number>
	---@field order integer[]
	---@field overshoot number
	---@field idle boolean
	---@field unitsPerMeter number
	---@field dismountStick integer|nil
	---@field dismountFor number
	---@field lowZ number|nil
	---@field highZ number|nil
	---@field pitch number|nil
	---@field rung integer|nil
	---@field stepLength number|nil
	---@field restZ number|nil
	---@field step MechanismClimbStep|nil
	-- With options.steps (stepLength: this engagement plays steps): where the game came to rest, and the game's step the hands
	-- play: starting (the stick pushed, waiting for it), held (kept still at the hands' share of it), or finishing (playing on,
	-- waiting for the rest). z is where the body is put.
	---@class MechanismClimbStep
	---@field state string
	---@field direction integer
	---@field startZ number
	---@field z number
	---@field elapsed number
	---@field handle any
	---@type MechanismClimbState
	local climb = {heights = {}, order = {}, overshoot = 0, idle = false, unitsPerMeter = 100, dismountFor = 0}
	local function clear()
		climb.heights, climb.order, climb.overshoot, climb.idle = {}, {}, 0, false
		climb.unitsPerMeter, climb.dismountStick, climb.dismountFor = 100, nil, 0
		climb.lowZ, climb.highZ, climb.pitch, climb.rung = nil, nil, nil, nil
		climb.stepLength, climb.restZ, climb.step = nil, nil, nil
	end
	clear()

	local function letGo(hand)
		climb.heights[hand] = nil
		for i = #climb.order, 1, -1 do
			if climb.order[i] == hand then table.remove(climb.order, i) end
		end
	end

	local function grab(hand)
		local height = readHandHeight(hand)
		if height == nil then return end
		letGo(hand)
		climb.heights[hand] = height
		climb.order[#climb.order + 1] = hand
		climbPulse(hand, grabHaptic)
	end

	-- The body's height change (world cm, up positive) since the last tick, from the most recent grab still holding. Every holding
	-- hand is read again, so letting go with one hand never makes the body jump.
	local function consumeBodyDelta()
		local active = climb.order[#climb.order]
		local delta = 0
		for _, hand in ipairs(climb.order) do
			local height = readHandHeight(hand)
			if height ~= nil then
				if hand == active then delta = (climb.heights[hand] - height) * climb.unitsPerMeter end
				climb.heights[hand] = height
			end
		end
		return delta
	end

	local function readRange(actor)
		local low, high = getRange(actor)
		climb.lowZ, climb.highZ = tonumber(low), tonumber(high)
	end

	local function rungPulse(z, hand)
		if climb.pitch == nil or climb.pitch <= 0 or climb.lowZ == nil then return end
		local rung = math.floor((z - climb.lowZ) / climb.pitch)
		if climb.rung ~= nil and rung ~= climb.rung then climbPulse(hand, rungHaptic) end
		climb.rung = rung
	end

	-- Steps (options.steps): a pull of startDistance from where the game came to rest starts one of its steps that way, while the
	-- next rest is inside the range. z: where the body is now.
	local function startStep(actor, z)
		local restZ, lowZ, highZ, length = climb.restZ, climb.lowZ, climb.highZ, climb.stepLength
		if restZ == nil or lowZ == nil or highZ == nil or length == nil then return end
		local moved = z - restZ
		if math.abs(moved) < stepStartDistance then return end
		local direction = moved > 0 and 1 or -1
		local nextRest = restZ + direction * length
		if nextRest > highZ + 1 or nextRest < lowZ - 1 then return end
		climb.step = {state = "starting", direction = direction, startZ = restZ, z = z, elapsed = 0}
		if steps ~= nil and type(steps.start) == "function" then steps.start(actor, direction) end
	end

	-- While a step is played: the body keeps going with the hands (written on every tick, over the game's own motion), the step is
	-- held at the hands' share of it, and it plays on from near its end once they are past it, back past where it started, or gone.
	local function stepTick(actor, delta, bodyDelta, hand)
		local step = climb.step
		local length = climb.stepLength
		if step == nil or length == nil or steps == nil then
			climb.step = nil
			return
		end
		step.elapsed = step.elapsed + (tonumber(delta) or 0)
		local player = uevrUtils.getValid(getPawn())
		if player ~= nil then
			local location = player:K2_GetActorLocation()
			-- Never push the player further outside the range than they are.
			local low, high = math.min(climb.lowZ or step.z, step.z), math.max(climb.highZ or step.z, step.z)
			step.z = math.max(low, math.min(high, step.z + bodyDelta))
			if location.Z ~= step.z then
				location.Z = step.z
				if moveBody ~= nil then
					moveBody(player, location)
				else
					player:K2_SetActorLocation(location, false, reusable_hit_result, true)
				end
				if hand ~= nil and bodyDelta ~= 0 then rungPulse(step.z, hand) end
			end
		end
		if step.state == "starting" then
			local handle, direction = steps.getStep(actor)
			if handle == nil then
				-- The game didn't step: the next pull from where the body is tries again.
				if step.elapsed > stepStartSeconds then
					climb.step, climb.restZ = nil, nil
					cancelStep(actor)
				end
				return
			end
			step.state, step.handle, step.elapsed = "held", handle, 0
			if direction == 1 or direction == -1 then step.direction = direction end
		end
		if step.state == "held" then
			-- The game rests again by itself: nothing left to play.
			if climb.idle then
				climb.step, climb.restZ = nil, step.z
				cancelStep(actor)
				return
			end
			local progress = (step.z - step.startZ) * step.direction
			if hand == nil or progress >= stepFinishPhase * length or progress <= -stepReverseDistance then
				steps.finish(actor, step.handle)
				step.state, step.elapsed = "finishing", 0
			else
				steps.hold(actor, step.handle, math.max(0, math.min(1, progress / length)))
			end
			return
		end
		-- Finishing: done once the game rests again, where the body is.
		if climb.idle or step.elapsed > stepFinishSeconds then climb.step, climb.restZ = nil, step.z end
	end

	return {
		isActive = options.isActive,
		isDone = options.isDone,
		getProgress = options.getProgress,
		getPhase = options.getPhase,
		onEngage = function(actor)
			clear()
			climb.unitsPerMeter = 100 * getWorldScale()
			climb.pitch = getRungPitch ~= nil and tonumber(getRungPitch(actor)) or nil
			readRange(actor)
			-- Steps (options.steps) are on or off for the whole engagement.
			if steps ~= nil and steps.isEnabled(actor) == true then
				local length = tonumber(steps.getLength(actor))
				if length ~= nil and length > 0 then climb.stepLength = length end
			end
		end,
		-- A step held still is let play on, so the game isn't left in the middle of it; one asked for that hasn't started is
		-- cancelled.
		onEnd = function(actor)
			local step = climb.step
			if steps ~= nil and step ~= nil and step.state == "held" and step.handle ~= nil then
				steps.finish(actor, step.handle)
			elseif step ~= nil and step.state == "starting" then
				cancelStep(actor)
			end
			clear()
		end,
		onTick = function(actor, delta, engagedFor, mechanism)
			-- Hands that took hold or let go since the last tick (a grab while a hand isn't tracked is tried again next tick).
			for _, hand in ipairs(HANDS) do
				local holding = mechanism:isHandEngaged(hand)
				if holding and climb.heights[hand] == nil then
					grab(hand)
				elseif not holding and climb.heights[hand] ~= nil then
					letGo(hand)
				end
			end
			-- The stick push toward an end stops once the game starts its own way off, or after stickSeconds. The hands' heights are
			-- read again on every tick (below), so motion during the push or a game step is never applied afterwards.
			if climb.dismountStick ~= nil then
				climb.dismountFor = climb.dismountFor + (tonumber(delta) or 0)
				if (isDismounting ~= nil and isDismounting(actor) == true) or climb.dismountFor > stickSeconds then
					climb.dismountStick = nil
				end
			end

			climb.idle = isIdle(actor) == true
			local bodyDelta = consumeBodyDelta()
			local hand = climb.order[#climb.order]
			if climb.step ~= nil then
				stepTick(actor, delta, bodyDelta, hand)
				return
			end
			-- Where the game came to rest (steps only) is taken again after each of its own steps.
			if not climb.idle then climb.restZ = nil end
			if not climb.idle or hand == nil or climb.dismountStick ~= nil then
				climb.overshoot = 0
				return
			end
			if bodyDelta == 0 then return end
			if climb.lowZ == nil or climb.highZ == nil then readRange(actor) end
			local player = uevrUtils.getValid(getPawn())
			local lowZ, highZ = climb.lowZ, climb.highZ
			if player == nil or lowZ == nil or highZ == nil then return end

			local location = player:K2_GetActorLocation()
			if climb.stepLength ~= nil and climb.restZ == nil then climb.restZ = location.Z end
			-- Never push the player further outside the range than the game put them.
			local low, high = math.min(lowZ, location.Z), math.max(highZ, location.Z)
			-- Motion past an end adds up in overshoot, and has to be undone before the player moves back.
			local wanted = location.Z + climb.overshoot + bodyDelta
			local z = math.max(low, math.min(high, wanted))
			climb.overshoot = wanted - z
			if math.abs(climb.overshoot) >= overshootLimit then
				climb.dismountStick = climb.overshoot > 0 and STICK_FULL or -STICK_FULL
				climb.dismountFor = 0
				climb.overshoot = 0
			end
			if z ~= location.Z then
				location.Z = z
				if moveBody ~= nil then
					moveBody(player, location)
				else
					player:K2_SetActorLocation(location, false, reusable_hit_result, true)
				end
				rungPulse(z, hand)
			end
			if climb.stepLength ~= nil and climb.dismountStick == nil then startStep(actor, z) end
		end,
		-- While a hand holds on at rest the hands climb, so the stick can't start a step under them; a pull past an end pushes it.
		onInput = function(actor, state)
			if climb.dismountStick ~= nil then
				state.Gamepad.sThumbLX = 0
				state.Gamepad.sThumbLY = climb.dismountStick
			elseif climb.step ~= nil then
				-- A step being started is asked for with the stick; while one is played, the stick can't start another.
				state.Gamepad.sThumbLX = 0
				state.Gamepad.sThumbLY = climb.step.state == "starting" and climb.step.direction * STICK_FULL or 0
			elseif climb.idle and #climb.order > 0 then
				state.Gamepad.sThumbLY = 0
			end
		end,
	}
end

------------------- Entries -------------------
-- See Entries above. The entries are read here in every mode; config/mechanisms_config_dev edits them in developer mode.
local PARAMETERS_FILE = "mechanisms_parameters"
local RESERVED_KEYS = {_profileState = true, _profileLabels = true}
local WIDGET_PREFIX = "uevr_mechanism_"
local TAP_DURATION = 0.15 -- seconds a tapped button is held
local HOLD_NEAR_MARGIN = 15 -- cm past its reach a hand may drift before it counts as pulled back
local NEAREST_DISTANCE = 500 -- cm
local SPOT_PRIORITY = 100 -- above libs/accessories' own choice of accessory, below its editor's preview

M.Action = {Tap = 1, Hold = 2}
M.Release = {GameFinishes = 1, AfterTime = 2, PullBack = 3, GripReleased = 4}
M.EngageWith = {Reach = 1, Grip = 2}
M.BUTTONS = {"A", "B", "X", "Y", "Left Bumper", "Right Bumper", "Left Thumbstick", "Right Thumbstick"}
-- The entries of M.BUTTONS that are the grips (libs/grip's default grip buttons).
local GRIP_BUTTONS = {[5] = true, [6] = true}
-- The Button type's settings (its Default's, and those a variation can have of its own), and what an entry uses for any it doesn't
-- say.
M.SETTING_KEYS = {"action", "button", "contactDistance", "engageWith", "release", "releaseAfter", "promptText", "promptTextCustom"}
M.ENTRY_DEFAULTS = {action = 1, button = 1, contactDistance = 20, engageWith = 1, release = 1, releaseAfter = 1.5, promptText = "",
	promptTextCustom = false}
-- The Grip claim's priority in libs/grip when neither the mechanism nor the game adapter gives one.
M.ENGAGE_GRIP_PRIORITY = 100
-- The priority of this module's answer to libs/accessories' target callback when the game adapter gives none
-- (accessories.TargetPriority.Normal).
M.ACCESSORY_TARGET_PRIORITY = 50

function M.isGripButton(index)
	local key = tonumber(index)
	return key ~= nil and GRIP_BUTTONS[key] == true
end

-- The library's types (see Types), by name and in the order they are defined (defineType, below).
M.DEFAULT_TYPE = "button"
local types, typeOrder = {}, {}

-- An entry's type: its saved one, else the default.
local function getEntryTypeName(entry)
	local name = entry ~= nil and entry.type or nil
	if type(name) ~= "string" or name == "" then return M.DEFAULT_TYPE end
	return name
end

-- A type's setting keys in order, and each one's value when an entry doesn't say. An unknown type has Button's.
local function getTypeSettings(typeName)
	local def = types[typeName] or types[M.DEFAULT_TYPE]
	if def == nil then return M.SETTING_KEYS, M.ENTRY_DEFAULTS end
	return def.settingKeys, def.settingDefaults
end

local buttonValues = nil
local function getButtonValue(index)
	if buttonValues == nil then
		buttonValues = {XINPUT_GAMEPAD_A, XINPUT_GAMEPAD_B, XINPUT_GAMEPAD_X, XINPUT_GAMEPAD_Y, XINPUT_GAMEPAD_LEFT_SHOULDER,
			XINPUT_GAMEPAD_RIGHT_SHOULDER, XINPUT_GAMEPAD_LEFT_THUMB, XINPUT_GAMEPAD_RIGHT_THUMB}
	end
	return buttonValues[tonumber(index) or 1] or buttonValues[1]
end

local paramManager = nil
-- Raised whenever an entry changes, so what was worked out from the entries is worked out again.
local entriesVersion = 0
local configDev = nil
local adapter = nil
local entriesEnabled = true
-- Mechanisms work as usual but never press the game's button (M.setPaused): for setting them up without the game acting on a test.
local paused = false
-- Scans skipped while the game shows no prompt and the game adapter's isScanNeeded doesn't say true (M.setScanOptimize). The
-- answer is asked once per tick for every mechanism (the mechanisms scan on the same ticks), and forgotten at the start of the next.
local scanOptimize = false
local scanNeeded = nil
local syncing = false

local function getParamManager()
	if paramManager == nil then
		paramManager = paramModule.new(PARAMETERS_FILE, {}, true)
		paramManager:load(false)
	end
	return paramManager
end

-- The game adapter's prompt, checked once by M.setGameAdapter (nil when it has none or it lacks a function).
local adapterPrompt = nil

-- The prompt, or nil (with a warning) when it lacks getPrompt, show or hide.
local function checkPrompt(prompt, from)
	if prompt == nil or (type(prompt) == "table" and type(prompt.getPrompt) == "function" and type(prompt.show) == "function"
		and type(prompt.hide) == "function") then return prompt end
	M.print(from .. ": prompt needs getPrompt, show and hide functions; ignoring it", LogLevel.Warning)
	return nil
end

-- What a prompt's getPrompt gave, or nil when it shows none or its object is gone.
local function validPrompt(shown)
	if type(shown) == "userdata" then return uevrUtils.getValid(shown) end
	return shown
end

function M.setGameAdapter(value)
	adapter = type(value) == "table" and value or nil
	adapterPrompt = checkPrompt(adapter ~= nil and adapter.prompt or nil, "setGameAdapter")
end

function M.hasGameAdapter()
	return adapter ~= nil
end

-- The game adapter's answer, or nil when it has no such function.
local function adapterCall(name, ...)
	local fn = adapter ~= nil and adapter[name] or nil
	if type(fn) ~= "function" then return nil end
	return fn(...)
end
adapterCall = uevrUtils.profiler:wrap("MECHANISMS: adapterCall", adapterCall)

-- What the game is doing with a thing now (see Types).
M.State = {Offered = "offered", Busy = "busy"}

-- An actor's state: the game adapter's getState, else built from isBusy (busy) and isOffered (offered), busy first.
local function getActorState(actor)
	if adapter == nil then return nil end
	if type(adapter.getState) == "function" then return adapter.getState(actor) end
	if type(adapter.isBusy) == "function" and adapter.isBusy(actor) == true then return M.State.Busy end
	if type(adapter.isOffered) == "function" and adapter.isOffered(actor) == true then return M.State.Offered end
	return nil
end
getActorState = uevrUtils.profiler:wrap("MECHANISMS: getActorState", getActorState)

-- Whether the game adapter can tell a state.
local function supportsState(state)
	if adapter == nil then return false end
	if type(adapter.getState) == "function" then return true end
	if state == M.State.Offered then return type(adapter.isOffered) == "function" end
	if state == M.State.Busy then return type(adapter.isBusy) == "function" end
	return false
end

-- Whether the game adapter has a function, by its path (e.g. "ladder.isIdle").
local function hasAdapterFunction(path)
	local value = adapter
	for part in string.gmatch(path, "[^%.]+") do
		if type(value) ~= "table" then return false end
		value = value[part]
	end
	return type(value) == "function"
end

local function getEntry(id)
	local entry = id ~= nil and getParamManager():get(id) or nil
	return type(entry) == "table" and entry or nil
end
getEntry = uevrUtils.profiler:wrap("MECHANISMS: getEntry", getEntry)

-- An entry's saved variation for a class, or nil.
local function getVariation(entry, className)
	local variations = entry ~= nil and entry.variations or nil
	local variation = type(variations) == "table" and className ~= nil and variations[className] or nil
	return type(variation) == "table" and variation or nil
end

-- The variation, when it has settings of its own in use (Use Default Settings unticked).
local function getOverride(entry, className)
	local variation = getVariation(entry, className)
	if variation ~= nil and variation.useDefault == false then return variation end
	return nil
end

-- The class object for a saved class name, while the game has it loaded. A Blueprint class comes from the asset registry
-- (uevrUtils.getClassIfLoaded). A native class is always loaded, so it is looked up by name once and kept (a miss is kept too).
local nativeClasses = {}
local function getEntryClass(path)
	if type(path) ~= "string" or path == "" then return nil end
	if path:sub(1, 6) ~= "Class " then return uevrUtils.getClassIfLoaded(path) end
	local class = nativeClasses[path]
	if class == nil then
		class = uevrUtils.get_class(path) or false
		nativeClasses[path] = class
	end
	return class or nil
end
getEntryClass = uevrUtils.profiler:wrap("MECHANISMS: getEntryClass", getEntryClass)

-- The saved entries that name a class: {id, class, added, removed}, sorted by id. class is the entry's own (it and everything
-- derived from it belong to the entry); added are the classes put under the entry by hand, which belong to it whatever they derive
-- from; removed (a set) are the classes taken out of the entry by hand, which don't belong to it. Kept until an entry changes.
local dataEntries = {version = -1, list = {}, byID = {}}
local function getDataEntries()
	if dataEntries.version ~= entriesVersion then
		local list, byID = {}, {}
		for id, entry in pairs(getParamManager():getAll() or {}) do
			if not RESERVED_KEYS[id] and type(entry) == "table" and type(entry.class) == "string" and entry.code ~= true then
				local added, removed = {}, {}
				for className, variation in pairs(type(entry.variations) == "table" and entry.variations or {}) do
					if type(variation) == "table" then
						if variation.removed == true then
							removed[className] = true
						elseif variation.added == true then
							added[#added + 1] = className
						end
					end
				end
				table.sort(added)
				local item = {id = id, type = getEntryTypeName(entry), class = entry.class, added = added, removed = removed}
				list[#list + 1] = item
				byID[id] = item
			end
		end
		table.sort(list, function(a, b) return a.id < b.id end)
		dataEntries = {version = entriesVersion, list = list, byID = byID}
	end
	return dataEntries.list, dataEntries.byID
end
getDataEntries = uevrUtils.profiler:wrap("MECHANISMS: getDataEntries", getDataEntries)

-- The entry an actor belongs to, and the actor's class name: the entry its class was added to by hand, else the entry whose own
-- class is its nearest parent (so a class of things with an entry of its own is not taken by the entry of what it derives from).
-- Kept per class until an entry changes.
local resolved = {version = -1, byClass = {}}
local function resolveEntryID(actor)
	local actorClass = actor:get_class()
	if actorClass == nil then return nil end
	if resolved.version ~= entriesVersion then resolved = {version = entriesVersion, byClass = {}} end
	local address = actorClass:get_address()
	local cached = resolved.byClass[address]
	if cached ~= nil then return cached.id, cached.className end
	local name = actorClass:get_full_name()
	local best, bestClass = nil, nil
	local list = getDataEntries()
	for _, item in ipairs(list) do
		for _, className in ipairs(item.added) do
			if className == name then best = item.id end
		end
	end
	if best == nil then
		for _, item in ipairs(list) do
			local class = not item.removed[name] and getEntryClass(item.class) or nil
			if class ~= nil and actor:is_a(class) then
				-- Nearer than the best so far when it derives from it.
				local nearer = bestClass == nil
				if not nearer then
					local defaultObject = class:get_class_default_object()
					nearer = defaultObject ~= nil and defaultObject:is_a(bestClass)
				end
				if nearer then best, bestClass = item.id, class end
			end
		end
	end
	resolved.byClass[address] = {id = best, className = name}
	return best, name
end
resolveEntryID = uevrUtils.profiler:wrap("MECHANISMS: resolveEntryID", resolveEntryID)

-- Calls fn(actor) for the live actors of an entry's classes (its own and those added to it), until fn returns true.
local function forEachEntryActor(id, fn)
	local _, byID = getDataEntries()
	local item = byID[id]
	if item == nil then return end
	local function visit(path)
		local class = getEntryClass(path)
		if class == nil then return false end
		for _, actor in ipairs(UEVR_UObjectHook.get_objects_by_class(class, false) or {}) do
			if uevrUtils.getValid(actor) ~= nil and not actor.bActorIsBeingDestroyed and fn(actor) == true then return true end
		end
		return false
	end
	if visit(item.class) then return end
	for _, className in ipairs(item.added) do
		if visit(className) then return end
	end
end
forEachEntryActor = uevrUtils.profiler:wrap("MECHANISMS: forEachEntryActor", forEachEntryActor)

-- The entry's actor in a state now (e.g. the one the game offers), leaving out those isIncluded (optional) says no to.
local function findEntryActor(id, state, isIncluded)
	if not supportsState(state) then return nil end
	local found = nil
	forEachEntryActor(id, function(actor)
		if getActorState(actor) == state and resolveEntryID(actor) == id and (isIncluded == nil or isIncluded(actor)) then
			found = actor
			return true
		end
		return false
	end)
	return found
end
findEntryActor = uevrUtils.profiler:wrap("MECHANISMS: findEntryActor", findEntryActor)

-- The entry's nearest actor within 5 meters of the player, offered or not.
local function findNearestEntryActor(id)
	local player = uevrUtils.getValid(pawn)
	if player == nil then return nil end
	local location = player:K2_GetActorLocation()
	local best, bestDistance = nil, NEAREST_DISTANCE
	forEachEntryActor(id, function(actor)
		local distance = uevrUtils.distanceBetween(location, actor:K2_GetActorLocation())
		if distance < bestDistance and resolveEntryID(actor) == id then best, bestDistance = actor, distance end
		return false
	end)
	return best
end
findNearestEntryActor = uevrUtils.profiler:wrap("MECHANISMS: findNearestEntryActor", findNearestEntryActor)

------------------- Hand spots -------------------
-- A mechanism's hand spots are the accessories (libs/accessories) saved under its accessory key. Required here, not at the top:
-- only mechanisms with hand spots use it.
local function getAccessories()
	return require("libs/accessories")
end

-- libs/accessories' activation values name a hand in threes from 2: left, right, either (1 is none).
local function isSpotForHand(marker, hand)
	local mode = tonumber(marker.activation_hand) or 1
	if mode < 2 then return false end
	local which = (mode - 2) % 3
	return which == 2 or (which == 0 and hand == Handed.Left) or (which == 1 and hand == Handed.Right)
end

-- What the hand spots are on: the mechanism's own answer, else the game adapter's, else the actor's root.
local function getSpotComponent(self, actor)
	if self.getAccessoryComponentFn ~= nil then return uevrUtils.getValid(self.getAccessoryComponentFn(actor)) end
	local component = adapterCall("getAccessoryComponent", actor)
	if component ~= nil then return uevrUtils.getValid(component) end
	return uevrUtils.getValid(actor, {"RootComponent"})
end
getSpotComponent = uevrUtils.profiler:wrap("MECHANISMS: getSpotComponent", getSpotComponent)

-- The hand's spot nearest a location: its world location, its accessory ID, the distance squared, and its label.
local function findHandSpot(self, key, actor, hand, location)
	local component = getSpotComponent(self, actor)
	if component == nil then return nil end
	local accessories = getAccessories()
	local best, bestID, bestDistance, bestLabel = nil, nil, nil, nil
	for id, params in pairs(accessories.getAccessoriesForAttachment(key) or {}) do
		local marker = accessories.getPrimaryMarkerParams(params)
		if marker ~= nil and isSpotForHand(marker, hand) then
			local point = accessories.getTargetAccessoryLocation(key, id, component)
			if point ~= nil then
				local dx, dy, dz = location.X - point.X, location.Y - point.Y, location.Z - point.Z
				local distance = dx * dx + dy * dy + dz * dz
				if bestDistance == nil or distance < bestDistance then best, bestID, bestDistance, bestLabel = point, id, distance, params.label end
			end
		end
	end
	return best, bestID, bestDistance, bestLabel
end
findHandSpot = uevrUtils.profiler:wrap("MECHANISMS: findHandSpot", findHandSpot)

-- A setting: the variation's own when it has settings of its own, else the entry's (the Default).
local function pickSetting(override, entry, key)
	local value = nil
	if override ~= nil then value = override[key] end
	if value == nil and entry ~= nil then value = entry[key] end
	return value
end

-- The prompt text of its own (an empty one too) while custom is true, else nil: the prompt option's.
local function getCustomText(custom, text)
	if custom ~= true then return nil end
	return type(text) == "string" and text or ""
end

-- A mechanism's settings as they apply to an actor (nil: its Default): the actor's variation's own when it has them, else the
-- saved entry's, else the values the mechanism was made with. Kept until the actor or an entry changes.
local function getRuntime(self, actor)
	local address = actor ~= nil and actor:get_address() or 0
	local runtime = self.runtime
	if runtime ~= nil and runtime.version == entriesVersion and runtime.address == address then return runtime end
	local entry = getEntry(self.entryID)
	runtime = {version = entriesVersion, address = address}
	if self.isData then
		local override = nil
		if actor ~= nil then
			local _, className = resolveEntryID(actor)
			override = getOverride(entry, className)
		end
		runtime.contactDistance = tonumber(pickSetting(override, entry, "contactDistance")) or M.ENTRY_DEFAULTS.contactDistance
		runtime.action = tonumber(pickSetting(override, entry, "action")) or M.ENTRY_DEFAULTS.action
		runtime.button = tonumber(pickSetting(override, entry, "button")) or M.ENTRY_DEFAULTS.button
		-- Engage With and when the hands let go are Button's settings: a stage that doesn't use them (Ladder's Climbing) keeps its
		-- own rules. Grip is Reach while the button is a grip: libs/grip would clear the button pressed for the game.
		local mode, engageGrip = nil, false
		if self.usesButtonSettings then
			mode = tonumber(pickSetting(override, entry, "release")) or M.ENTRY_DEFAULTS.release
			engageGrip = self.gripName == nil and not M.isGripButton(runtime.button)
				and tonumber(pickSetting(override, entry, "engageWith")) == M.EngageWith.Grip
		end
		-- When I release grip is only for Grip; with Reach it is as when the game finishes.
		if mode == M.Release.GripReleased and not engageGrip then mode = M.Release.GameFinishes end
		runtime.engageGrip, runtime.release = engageGrip, mode
		runtime.releaseAfter = mode == M.Release.AfterTime and (tonumber(pickSetting(override, entry, "releaseAfter")) or M.ENTRY_DEFAULTS.releaseAfter) or nil
		runtime.holdNear = mode == M.Release.PullBack
		runtime.latch = self.latchContact
		-- What its prompt says (nil: the prompt option's own text).
		runtime.promptText = getCustomText(pickSetting(override, entry, "promptTextCustom"), pickSetting(override, entry, "promptText"))
		runtime.accessoryKey = (override ~= nil and override.accessoryKey) or (entry ~= nil and entry.accessoryKey) or self.entryID
	else
		runtime.contactDistance = tonumber(entry ~= nil and entry.contactDistance or nil) or self.contactDistance
		-- Its saved settings, else its options. Engage With is not for one with a grip engagement of its own (options.grip).
		local engageWith = tonumber(entry ~= nil and entry.engageWith or nil) or self.defaults.engageWith
		local engageGrip = self.gripName == nil and engageWith == M.EngageWith.Grip
		local mode = tonumber(entry ~= nil and entry.release or nil) or self.defaults.release
		if mode == M.Release.GripReleased and not engageGrip then mode = M.Release.GameFinishes end
		runtime.engageGrip, runtime.release = engageGrip, mode
		runtime.releaseAfter = mode == M.Release.AfterTime and (tonumber(entry ~= nil and entry.releaseAfter or nil)
			or self.defaults.releaseAfter or M.ENTRY_DEFAULTS.releaseAfter) or nil
		-- Pulled back: the kind's own test says when (there is no hand spot distance, as an entry's). Latched until the game
		-- finishes it or the time is up.
		runtime.holdNear = false
		runtime.latch = mode == M.Release.GameFinishes or mode == M.Release.AfterTime
		runtime.promptText = entry ~= nil and getCustomText(entry.promptTextCustom, entry.promptText) or nil
		runtime.accessoryKey = entry ~= nil and entry.accessoryKey or self.accessoryKey
	end
	-- Held until the hand pulls back or lets go of its grip: whether the game took the press doesn't matter.
	runtime.handHeld = runtime.holdNear or runtime.release == M.Release.GripReleased
	self.runtime = runtime
	return runtime
end
getRuntime = uevrUtils.profiler:wrap("MECHANISMS: getRuntime", getRuntime)

------------------- Mechanisms -------------------
local Mechanism = {}
Mechanism.__index = Mechanism

local DEFAULT_HAPTICS = {
	engage = {duration = 0.05, amplitude = 0.5},
	phase = {duration = 0.08, amplitude = 0.7},
	done = {duration = 0.15, amplitude = 1},
}

local function notify(self, event, ...)
	if self.onEvent ~= nil then self.onEvent(event, ...) end
end

-- A pulse on the hands in contact.
local function pulse(self, haptic)
	if not haptic then return end
	for _, hand in ipairs(HANDS) do
		if self.touching[hand] then uevrUtils.triggerHapticVibration(hand, 0, haptic.duration, haptic.frequency, haptic.amplitude) end
	end
end

-- A mechanism engaged or let go, or a hand took hold or let go, this tick: what a hand is put on (getAccessoryTarget) may have
-- changed, so libs/accessories is asked again at the tick's end instead of on its timer.
local handsChanged = false

local function clearEngagement(self)
	handsChanged = true
	self.engaged, self.engagedFor, self.lostFor = false, 0, 0
	self.phase, self.progress, self.value = nil, nil, nil
end

-- When an engagement ends: grip presses still held no longer count (the hands take hold again with new presses), and the driver is
-- told.
local function endEngagement(self, actor, reason)
	if self.gripName ~= nil then self.gripped[Handed.Left], self.gripped[Handed.Right] = false, false end
	if self.engageGripName ~= nil then self.engageGripped[Handed.Left], self.engageGripped[Handed.Right] = false, false end
	if self.placeHands ~= nil then
		self.spotTarget[Handed.Left], self.spotTarget[Handed.Right] = nil, nil
		self.spotID[Handed.Left], self.spotID[Handed.Right] = nil, nil
		self.spotKey[Handed.Left], self.spotKey[Handed.Right] = nil, nil
	end
	if self.driver.onEnd ~= nil then self.driver.onEnd(actor, reason, self) end
end

local function release(self, reason)
	if not self.engaged then return end
	clearEngagement(self)
	local actor = uevrUtils.getValid(self.actor)
	endEngagement(self, actor, reason)
	M.print(self.name .. " released: " .. tostring(reason))
	notify(self, "release", actor, reason)
end
release = uevrUtils.profiler:wrap("MECHANISMS: release", release)

local function engage(self, actor)
	clearEngagement(self)
	self.engaged = true
	M.print(self.name .. " engaged")
	pulse(self, self.haptics.engage)
	notify(self, "engage", actor)
	if self.driver.onEngage ~= nil then self.driver.onEngage(actor, self) end
end
engage = uevrUtils.profiler:wrap("MECHANISMS: engage", engage)

-- waitForClear: keep the actor and have the hands leave before it engages again (released by time, not finished by the game: the
-- game may still offer it, e.g. a door that didn't open, and would otherwise be grabbed again at once).
local function finish(self, actor, waitForClear)
	clearEngagement(self)
	if waitForClear then
		self.waitForClear = true
	else
		self.actor = nil
	end
	endEngagement(self, actor, "done")
	M.print(self.name .. " done")
	pulse(self, self.haptics.done)
	notify(self, "done", actor)
end
finish = uevrUtils.profiler:wrap("MECHANISMS: finish", finish)

-- Hands placed by the game (options.placeHands): as a hand takes hold, its spot (the one for that hand nearest it, on the spot
-- component, under the first of getSpotKeys that has one) and what the game puts it on. getTarget is asked with or without a spot,
-- so it can refuse the hand either way. Neither is kept when either is missing.
local function placeHand(self, actor, hand, location, key)
	self.spotTarget[hand], self.spotID[hand], self.spotKey[hand] = nil, nil, nil
	if location == nil then return end
	local spot = nil
	if key ~= nil then
		local keys = type(self.placeHands.getSpotKeys) == "function" and self.placeHands.getSpotKeys(actor, hand, location, key) or {key}
		local accessories = getAccessories()
		for _, spotKey in ipairs(keys) do
			local _, spotID = findHandSpot(self, spotKey, actor, hand, location)
			local params = spotID ~= nil and (accessories.getAccessoriesForAttachment(spotKey) or {})[spotID] or nil
			local marker = params ~= nil and accessories.getPrimaryMarkerParams(params) or nil
			if marker ~= nil then
				spot = {key = spotKey, id = spotID, location = xyz(marker.location, {x = 0, y = 0, z = 0}), rotation = xyz(marker.rotation, {x = 0, y = 0, z = 0})}
				break
			end
		end
	end
	local answer = self.placeHands.getTarget(actor, hand, location, spot)
	-- false: the hand may not hold on here (see evaluateHands).
	if answer == false then return false end
	if spot == nil then return end
	local target = uevrUtils.getValid(answer)
	if target == nil then return end
	self.spotTarget[hand], self.spotID[hand], self.spotKey[hand] = target, spot.id, spot.key
end
placeHand = uevrUtils.profiler:wrap("MECHANISMS: placeHand", placeHand)

-- The axes of the kind's zone frame (readFrameAxes), and the head's position in them; nil for a kind with no zone of its own
-- (contact), or while the frame can't be read. The axes are read once here and used for the head and each hand (evaluateKind).
local function getZoneFrame(self, actor)
	if self.kind.noZone == true then return nil end
	local frame = actor
	if self.getFrame ~= nil then frame = uevrUtils.getValid(self.getFrame(actor)) end
	local axes = readFrameAxes(frame)
	if axes == nil then return nil end
	local headX, headY, headZ = toAxesSpace(axes, controllers.getControllerLocation(HMD))
	return axes, headX, headY, headZ
end
getZoneFrame = uevrUtils.profiler:wrap("MECHANISMS: getZoneFrame", getZoneFrame)

-- The kind's answer for a hand at a world location: inContact, value. axes: from getZoneFrame.
local function evaluateKind(self, actor, axes, headX, headY, headZ, location, engaged)
	local x, y, z = toAxesSpace(axes, location)
	if x == nil then return false, nil end
	return self.kind.evaluate(self.settings, x, y, z, engaged, headX, headY, headZ, actor)
end
evaluateKind = uevrUtils.profiler:wrap("MECHANISMS: evaluateKind", evaluateKind)

-- Where a hand starts working the mechanism, in place of the kind's own start test: its contact point, else its nearest hand spot
-- (and that spot's accessory ID). nil: none for this hand. With placeHands the spots only place the hands, so they are not asked.
local function getStartPoint(self, actor, hand, location, accessoryKey)
	if self.getContactPoint ~= nil then return self.getContactPoint(actor, hand), nil end
	if accessoryKey ~= nil and self.placeHands == nil then
		local point, spotID = findHandSpot(self, accessoryKey, actor, hand, location)
		return point, spotID
	end
	return nil, nil
end
getStartPoint = uevrUtils.profiler:wrap("MECHANISMS: getStartPoint", getStartPoint)

local function isWithin(location, point, reach)
	local dx, dy, dz = location.X - point.X, location.Y - point.Y, location.Z - point.Z
	return dx * dx + dy * dy + dz * dz <= reach * reach
end

-- Engage With Grip: whether a grip press starting now is the mechanism's. The hand has to pass the start test (its contact point or
-- hand spot within reach, else the kind's zone) with the actor and settings the last tick left. libs/grip asks once, on the press's
-- first frame, so nothing is measured on the tick while the hands wait. The spot reached is kept for the hand.
local function claimsEngageGrip(self, hand)
	if not self.enabled or not self.engageGrip or self.waitForClear or (self.engaged and self.touching[hand]) then return false end
	local actor, runtime = uevrUtils.getValid(self.actor), self.runtime
	local location = controllers.getControllerLocation(hand)
	if actor == nil or runtime == nil or location == nil then return false end
	local point, spotID = getStartPoint(self, actor, hand, location, runtime.accessoryKey)
	local inContact = false
	if point ~= nil then
		inContact = isWithin(location, point, runtime.contactDistance)
	else
		local frame, headX, headY, headZ = getZoneFrame(self, actor)
		if frame ~= nil then inContact = evaluateKind(self, actor, frame, headX, headY, headZ, location, false) == true end
	end
	if inContact then self.claimSpot[hand] = spotID end
	return inContact
end
claimsEngageGrip = uevrUtils.profiler:wrap("MECHANISMS: claimsEngageGrip", claimsEngageGrip)

-- Which hands are in contact, how many, and the average of their values.
local function evaluateHands(self, actor, runtime)
	local contactDistance, holdNear, latch, accessoryKey = runtime.contactDistance, runtime.holdNear, runtime.latch, runtime.accessoryKey
	local engageGrip, gripRelease = runtime.engageGrip, runtime.release == M.Release.GripReleased
	-- The kind's zone, for the hands measured against it: with Grip, none is until one takes hold.
	local frame, headX, headY, headZ = nil, nil, nil, nil
	if not engageGrip or self.engaged then frame, headX, headY, headZ = getZoneFrame(self, actor) end
	local count, total = 0, 0
	for _, hand in ipairs(HANDS) do
		local inContact, value, location = false, nil, nil
		if engageGrip and not (self.engaged and self.touching[hand]) then
			-- Engage With Grip: a hand takes hold (or joins) with a press its claim took within reach (claimsEngageGrip); nothing
			-- is measured here.
			inContact = self.engageGripped[hand] == true
			if inContact and not self.touching[hand] then self.spotID[hand] = self.claimSpot[hand] end
			if self.placeHands ~= nil then location = controllers.getControllerLocation(hand) end
		else
			location = controllers.getControllerLocation(hand)
			if frame ~= nil and location ~= nil then
				inContact, value = evaluateKind(self, actor, frame, headX, headY, headZ, location, self.engaged)
			end
			if engageGrip and gripRelease then
				-- When I release grip: in contact while it holds its press, wherever it goes.
				inContact = self.engageGripped[hand] == true
			elseif self.engaged and latch and not holdNear and self.touching[hand] then
				-- Latched: a hand that was in contact while engaged stays in contact.
				inContact = true
			elseif (not self.engaged or latch) and location ~= nil then
				-- Not engaged yet, with a contact point or hand spot for this hand: the hand starts there, in place of the kind's
				-- own start test. Latched, it is asked while engaged too, so a hand that was not there at the start can join.
				local point, spotID = getStartPoint(self, actor, hand, location, accessoryKey)
				if point ~= nil then
					-- Holding while near: a hand already on it may drift a little further before it counts as pulled back.
					local reach = contactDistance
					if holdNear and self.engaged and self.touching[hand] then reach = reach + HOLD_NEAR_MARGIN end
					inContact = isWithin(location, point, reach)
					-- The spot the hand reached is the one it is put on, until it lets go.
					if inContact and not self.touching[hand] then self.spotID[hand] = spotID end
				end
			end
		end
		-- Held by grip: being in the zone only decides whether a press is claimed (the claim reads inZone); the hand is in contact
		-- while it holds its press.
		if self.gripName ~= nil then
			self.inZone[hand] = inContact == true
			inContact = self.gripped[hand] == true
		end
		-- Hands placed by the game: a hand that takes hold gets its spot and what it is put on, kept while it holds on; a hand that
		-- lets go loses them.
		if self.placeHands ~= nil then
			if inContact == true and not self.touching[hand] then
				-- getTarget false: the hand may not hold on here. It lets go of its grip press, which isn't claimed again until a new
				-- press.
				if placeHand(self, actor, hand, location, accessoryKey) == false then
					inContact = false
					if self.gripName ~= nil then
						grip.yield(hand, self.gripName)
						self.gripped[hand] = false
					end
				end
			elseif inContact ~= true then
				self.spotTarget[hand], self.spotID[hand], self.spotKey[hand] = nil, nil, nil
			end
		end
		-- Engage With Grip: a hand that loses contact has to press again (the press stays hidden until it is let go of).
		if engageGrip and self.touching[hand] and inContact ~= true then self.engageGripped[hand] = false end
		if self.touching[hand] ~= (inContact == true) then handsChanged = true end
		self.touching[hand] = inContact == true
		if inContact == true then
			count = count + 1
			total = total + (tonumber(value) or 0)
		end
	end
	return count, count > 0 and total / count or nil
end
evaluateHands = uevrUtils.profiler:wrap("MECHANISMS: evaluateHands", evaluateHands)

local function isAllowed(self)
	return self.isAllowed == nil or self.isAllowed() ~= false
end
isAllowed = uevrUtils.profiler:wrap("MECHANISMS: isAllowed", isAllowed)

-- Scan optimize: a scan is needed while the game shows a prompt (the game adapter's prompt.getPrompt, asked with no actor), or
-- while the adapter's isScanNeeded says so. An adapter with neither always scans.
local function isScanNeeded()
	if adapterPrompt ~= nil and validPrompt(adapterPrompt.getPrompt(nil)) ~= nil then return true end
	local needed = adapterCall("isScanNeeded")
	return needed == true or (needed == nil and adapterPrompt == nil)
end
isScanNeeded = uevrUtils.profiler:wrap("MECHANISMS: isScanNeeded", isScanNeeded)

-- Engage With Grip's claim, registered the first time a mechanism's settings choose it (defined with the grip engagement, below).
local registerEngageGripClaim

local function update(self, delta)
	if not self.enabled then return end
	local actor = uevrUtils.getValid(self.actor)
	if self.engaged and actor == nil then release(self, "lost") end
	if not self.engaged then
		self.scanElapsed = self.scanElapsed + delta
		if self.scanElapsed >= self.scanInterval then
			self.scanElapsed = 0
			if scanOptimize and scanNeeded == nil then scanNeeded = isScanNeeded() end
			actor = isAllowed(self) and scanNeeded ~= false and uevrUtils.getValid(self.find()) or nil
			self.actor = actor
		end
	end
	-- With no actor there is nothing to do, so isAllowed is not asked on these ticks: only on the scan above and, once an actor
	-- is found, on every tick.
	if actor == nil or not isAllowed(self) then
		release(self, "not_allowed")
		self.touching[Handed.Left], self.touching[Handed.Right] = false, false
		self.inZone[Handed.Left], self.inZone[Handed.Right] = false, false
		self.waitForClear = false
		-- Nothing for a Grip press to take hold of, and a press taken before no longer counts.
		self.engageGrip = false
		self.engageGripped[Handed.Left], self.engageGripped[Handed.Right] = false, false
		return
	end

	local runtime = getRuntime(self, actor)
	-- For the Grip claim, which reads only what the last tick left (claimsEngageGrip).
	self.engageGrip = runtime.engageGrip
	if runtime.engageGrip and self.engageGripName == nil then registerEngageGripClaim(self) end
	local count, value = evaluateHands(self, actor, runtime)
	if not self.engaged then
		if self.waitForClear then
			if count == 0 then self.waitForClear = false end
		elseif count >= self.hands then
			engage(self, actor)
		end
		return
	end

	self.engagedFor = self.engagedFor + delta
	local driver = self.driver
	if driver.isDone ~= nil and driver.isDone(actor, self.engagedFor) == true then
		finish(self, actor)
		return
	end
	local releaseAfter = runtime.releaseAfter
	if releaseAfter ~= nil and releaseAfter > 0 and self.engagedFor >= releaseAfter then
		finish(self, actor, true)
		return
	end
	-- The game didn't start working it, or stopped on its own: let go, and wait for the hands to leave before trying again. Not
	-- while paused: the game was never asked.
	if not paused and driver.isActive ~= nil and self.engagedFor >= self.startTimeout and driver.isActive(actor, self.engagedFor) ~= true then
		self.waitForClear = true
		release(self, "refused")
		return
	end
	if count >= self.keepHands then
		self.lostFor = 0
	else
		self.lostFor = self.lostFor + delta
		if self.lostFor >= self.releaseGrace then
			release(self, "hands")
			return
		end
	end
	self.value = value
	if driver.getProgress ~= nil then self.progress = driver.getProgress(actor, self.engagedFor) end
	if driver.getPhase ~= nil then
		local phase = driver.getPhase(actor, self.engagedFor)
		if phase ~= self.phase then
			local old = self.phase
			self.phase = phase
			pulse(self, self.haptics.phase)
			notify(self, "phase", actor, phase, old)
		end
	end
	-- Not while paused: like the button drivers, a driver that acts every tick leaves the game alone.
	if not paused and driver.onTick ~= nil then driver.onTick(actor, delta, self.engagedFor, self) end
end
update = uevrUtils.profiler:wrap("MECHANISMS: update", update)

------------------- Prompt -------------------
-- While a mechanism has its actor, the game's prompt for it asks for a hand instead of a button (options.prompt). Whether it applies
-- is decided here; what the prompt then shows is the game-specific show and hide.
local function getPromptKey(prompt)
	if type(prompt) == "userdata" and prompt.get_address ~= nil then return prompt:get_address() end
	return prompt
end

-- Says through libs/grip's event that this mechanism has (or no longer has) the prompt, so an interact leaves it and the grip alone.
local function setPromptClaimed(self, claimed)
	if claimed == (self.promptClaimed == true) then return end
	self.promptClaimed = claimed
	uevrUtils.executeUEVRCallbacks(grip.PROMPT_CLAIMED_EVENT, self.name, claimed)
end

local function clearPrompt(self)
	local shown = self.promptShown
	self.promptShown = nil
	if validPrompt(shown) ~= nil then self.prompt.hide(shown) end
	setPromptClaimed(self, false)
end
clearPrompt = uevrUtils.profiler:wrap("MECHANISMS: clearPrompt", clearPrompt)

local function updatePrompt(self, delta)
	if self.prompt == nil then return end
	self.promptElapsed = self.promptElapsed + delta
	if self.promptElapsed < self.promptInterval then return end
	self.promptElapsed = 0
	local actor = self.enabled and uevrUtils.getValid(self.actor) or nil
	local prompt = nil
	if actor ~= nil and isAllowed(self) then
		prompt = validPrompt(self.prompt.getPrompt(actor))
	end
	if prompt == nil then
		clearPrompt(self)
		return
	end
	-- Games reuse prompt objects: one that now belongs to something else is put back first.
	if self.promptShown ~= nil and getPromptKey(self.promptShown) ~= getPromptKey(prompt) then clearPrompt(self) end
	self.promptShown = prompt
	-- setPromptText's text, else the saved promptText, else the prompt option's for its Engage With.
	local saved = getRuntime(self, actor).promptText
	self.prompt.show(prompt, self.promptText or saved or (self.engageGrip and self.prompt.gripText) or self.prompt.text)
	setPromptClaimed(self, true)
end
updatePrompt = uevrUtils.profiler:wrap("MECHANISMS: updatePrompt", updatePrompt)

local function onInput(retval, userIndex, state)
	if paused or userIndex ~= 0 or state == nil or state.Gamepad == nil then return end
	for _, self in ipairs(instances) do
		if self.engaged and self.driver.onInput ~= nil then
			local actor = uevrUtils.getValid(self.actor)
			if actor ~= nil then self.driver.onInput(actor, state, self.engagedFor) end
		end
	end
end
onInput = uevrUtils.profiler:wrap("MECHANISMS: onInput", onInput)

local function resetAll()
	for _, self in ipairs(instances) do self:reset() end
	-- Classes are loaded again as new objects after a level change.
	resolved = {version = -1, byClass = {}}
end
resetAll = uevrUtils.profiler:wrap("MECHANISMS: resetAll", resetAll)

local function isHandReady(hand)
	return adapterCall("isHandReady", hand) ~= false
end

-- For libs/accessories: the hand spot a hand reached on an engaged mechanism is the accessory that hand is put on.
local function getActiveSpot(hand)
	for _, self in ipairs(instances) do
		if self.engaged and self.touching[hand] == true and self.spotID[hand] ~= nil and isHandReady(hand) then
			return self.spotID[hand], SPOT_PRIORITY
		end
	end
end
getActiveSpot = uevrUtils.profiler:wrap("MECHANISMS: getActiveSpot", getActiveSpot)

-- For libs/accessories' target callback: getAccessoryTarget as an answer (one table per hand, refilled) and its priority. The
-- callback's name is written here so libs/accessories is still only required by mechanisms with hand spots.
local ACCESSORY_TARGET_CALLBACK = "accessory_target"
local targetAnswers = {}
local function getAccessoryTargetAnswer(hand)
	local component, key = M.getAccessoryTarget(hand)
	if component == nil then return nil end
	local answer = targetAnswers[hand]
	if answer == nil then answer = {}; targetAnswers[hand] = answer end
	answer.target, answer.key = component, key
	return answer, tonumber(adapter ~= nil and adapter.accessoryPriority or nil) or M.ACCESSORY_TARGET_PRIORITY
end

-- Nothing runs until the first mechanism is created.
local function installHooks()
	if hooksInstalled then return end
	hooksInstalled = true
	uevrUtils.registerPostEngineTickCallback(function(engine, delta)
		scanNeeded = nil
		for _, self in ipairs(instances) do
			update(self, tonumber(delta) or 0)
			updatePrompt(self, tonumber(delta) or 0)
		end
		-- The hands move to (or off) their spots on this tick, not on libs/accessories' timer up to 300 ms later. Only once it is
		-- loaded: a mechanism with no hand spots never loads it.
		if handsChanged then
			handsChanged = false
			local accessories = package.loaded["libs/accessories"]
			if accessories ~= nil then accessories.forceUpdate() end
		end
	end)
	uevrUtils.registerOnPostInputGetStateCallback(onInput, M.POST_INPUT_PRIORITY)
	uevrUtils.registerUEVRCallback("active_left_accessory", function() return getActiveSpot(Handed.Left) end)
	uevrUtils.registerUEVRCallback("active_right_accessory", function() return getActiveSpot(Handed.Right) end)
	uevrUtils.registerUEVRCallback(ACCESSORY_TARGET_CALLBACK, getAccessoryTargetAnswer)
	uevrUtils.registerPreLevelChangeCallback(resetAll)
	uevr.params.sdk.callbacks.on_script_reset(resetAll)
	-- The Ladder type's rung targets go with the level (their actor is the level's); on a script reset they are destroyed.
	uevrUtils.registerPreLevelChangeCallback(function()
		ladderState.rungTargets, ladderState.rungs = {}, nil
	end)
	uevr.params.sdk.callbacks.on_script_reset(function()
		for _, component in pairs(ladderState.rungTargets) do
			if uevrUtils.getValid(component) ~= nil then uevrUtils.destroyComponent(component, true) end
		end
		ladderState.rungTargets, ladderState.rungs = {}, nil
	end)
end

------------------- Grip engagement -------------------
-- A mechanism with options.grip claims a grip press (libs/grip) that starts with the hand in its zone, and the hand holds on while
-- it owns that press. Nothing here runs until the first such mechanism is made.
local gripHooked = false

local function onGripOwnerChange(hand, newOwner, oldOwner)
	for _, self in ipairs(instances) do
		if self.gripName ~= nil then
			if newOwner == self.gripName then
				self.gripped[hand] = true
			elseif oldOwner == self.gripName then
				self.gripped[hand] = false
			end
		end
		-- Engage With Grip: a press its claim took, until it is let go of (or yielded).
		if self.engageGripName ~= nil then
			if newOwner == self.engageGripName then
				self.engageGripped[hand] = true
			elseif oldOwner == self.engageGripName then
				self.engageGripped[hand] = false
			end
		end
	end
end
onGripOwnerChange = uevrUtils.profiler:wrap("MECHANISMS: onGripOwnerChange", onGripOwnerChange)

local function hookGripOwners()
	if gripHooked then return end
	gripHooked = true
	grip.registerOwnerChangeCallback(onGripOwnerChange)
end

-- The claim only reads what the last tick decided (enabled, in the zone, not waiting for the hands to leave), so it is cheap and
-- touches nothing of the game's in the input callback.
local function registerGripClaim(self, priority, hide)
	hookGripOwners()
	-- A name claimed before (a mechanism made again) only changes the mechanism its claim is for.
	local name = self.gripName
	local registered = gripClaims[name] ~= nil
	gripClaims[name] = {mechanism = self, priority = priority}
	if registered then return end
	grip.registerClaim(name, function(hand)
		local claim = gripClaims[name]
		local owner = claim.mechanism
		if owner.enabled and owner.inZone[hand] == true and not owner.waitForClear then return claim.priority end
		return nil
	end, {hide = hide})
end

-- Engage With Grip: a start claim on a press that starts within reach (claimsEngageGrip), hidden from the other systems until it is
-- let go of, as options.grip's. Registered the first time the mechanism's settings choose Grip, so a project that never does
-- registers none.
registerEngageGripClaim = function(self)
	hookGripOwners()
	local name = "mechanism_engage_" .. self.name
	self.engageGripName = name
	local priority = tonumber(self.engageGripPriority) or (adapter ~= nil and tonumber(adapter.engageGripPriority)) or M.ENGAGE_GRIP_PRIORITY
	-- A name claimed before (a mechanism made again) only changes the mechanism its claim is for.
	local registered = gripClaims[name] ~= nil
	gripClaims[name] = {mechanism = self, priority = priority}
	if registered then return end
	grip.registerClaim(name, function(hand)
		local claim = gripClaims[name]
		if claimsEngageGrip(claim.mechanism, hand) then return claim.priority end
		return nil
	end, {hide = grip.Hide.Systems})
end

-- Gives up the grip presses the mechanism owns (disabled, reset), and forgets which hands were in its zone.
local function letGoOfGrips(self)
	self.inZone[Handed.Left], self.inZone[Handed.Right] = false, false
	self.spotTarget[Handed.Left], self.spotTarget[Handed.Right] = nil, nil
	self.spotKey[Handed.Left], self.spotKey[Handed.Right] = nil, nil
	self.claimSpot[Handed.Left], self.claimSpot[Handed.Right] = nil, nil
	if self.engageGripName ~= nil then
		for _, hand in ipairs(HANDS) do grip.yield(hand, self.engageGripName) end
		self.engageGripped[Handed.Left], self.engageGripped[Handed.Right] = false, false
	end
	if self.gripName == nil then return end
	for _, hand in ipairs(HANDS) do grip.yield(hand, self.gripName) end
	self.gripped[Handed.Left], self.gripped[Handed.Right] = false, false
end

function M.new(options)
	if type(options) ~= "table" then
		M.print("new: expected an options table", LogLevel.Warning)
		return nil
	end
	local kind = kinds[options.kind]
	if kind == nil or type(options.find) ~= "function" or type(options.driver) ~= "table" then
		M.print("new: a registered kind, a find function and a driver table are required", LogLevel.Warning)
		return nil
	end
	-- The game adapter's prompt was checked by M.setGameAdapter.
	local prompt = options.prompt
	if prompt ~= adapterPrompt then prompt = checkPrompt(prompt, "new") end
	local gripOptions = options.grip
	if gripOptions ~= nil and (type(gripOptions) ~= "table" or tonumber(gripOptions.priority) == nil) then
		M.print("new: grip needs a priority; ignoring it", LogLevel.Warning)
		gripOptions = nil
	end
	local placeHands = options.placeHands
	if placeHands ~= nil and (type(placeHands) ~= "table" or type(placeHands.getTarget) ~= "function") then
		M.print("new: placeHands needs a getTarget function; ignoring it", LogLevel.Warning)
		placeHands = nil
	end
	local haptics = {}
	if options.haptics ~= false then
		local given = type(options.haptics) == "table" and options.haptics or {}
		for key, fallback in pairs(DEFAULT_HAPTICS) do haptics[key] = default(given[key], fallback) end
	end
	local name = default(options.name, "mechanism")
	local contactDistance = default(tonumber(options.contactDistance), 15)
	local engageWith = default(tonumber(options.engageWith), M.EngageWith.Reach)
	-- The release a mechanism made in code has until one is saved: as given, else what its options meant before there was one.
	local releaseMode = tonumber(options.release)
	if releaseMode == nil then
		if (tonumber(options.releaseAfter) or 0) > 0 then
			releaseMode = M.Release.AfterTime
		elseif options.latchContact == true then
			releaseMode = M.Release.GameFinishes
		else
			releaseMode = M.Release.PullBack
		end
	end
	local self = setmetatable({
		name = name,
		label = default(options.label, name),
		-- The saved entry with this mechanism's settings: its own name, or (made from a saved entry) that entry's ID.
		entryID = default(options.entryID, name),
		isData = options.isData == true,
		defaults = {contactDistance = contactDistance, releaseAfter = tonumber(options.releaseAfter), engageWith = engageWith,
			release = releaseMode},
		findNearestFn = options.findNearest,
		accessoryKey = options.accessoryKey,
		getAccessoryComponentFn = options.getAccessoryComponent,
		kind = kind,
		settings = kind.configure(options),
		find = options.find,
		driver = options.driver,
		getFrame = options.getFrame,
		isAllowed = options.isAllowed,
		getContactPoint = options.getContactPoint,
		contactDistance = contactDistance,
		latchContact = options.latchContact == true,
		onEvent = options.onEvent,
		hands = default(tonumber(options.hands), 2),
		keepHands = default(tonumber(options.keepHands), 1),
		releaseGrace = default(tonumber(options.releaseGrace), 0.4),
		startTimeout = default(tonumber(options.startTimeout), 0.5),
		scanInterval = default(tonumber(options.scanInterval), 0.5),
		haptics = haptics,
		prompt = prompt,
		promptInterval = prompt ~= nil and default(tonumber(prompt.interval), 0.25) or nil,
		promptElapsed = 0,
		enabled = false,
		engaged = false,
		engagedFor = 0,
		lostFor = 0,
		scanElapsed = 0,
		waitForClear = false,
		touching = {[Handed.Left] = false, [Handed.Right] = false},
		spotID = {},
		-- Grip engagement (options.grip): the claim's name, the hands holding a press it owns, and the hands in the zone.
		gripName = gripOptions ~= nil and ("mechanism_" .. name) or nil,
		gripped = {[Handed.Left] = false, [Handed.Right] = false},
		inZone = {[Handed.Left] = false, [Handed.Right] = false},
		-- Engage With Grip: its claim's name (once registered), whether the last tick chose Grip, the hands holding a press its claim
		-- took, and the spot each of those reached.
		engageGripName = nil,
		engageGrip = false,
		engageGripPriority = tonumber(options.engageGripPriority),
		engageGripped = {[Handed.Left] = false, [Handed.Right] = false},
		claimSpot = {},
		-- Hands placed by the game (options.placeHands): what each hand's spot is on while it holds on.
		placeHands = placeHands,
		spotTarget = {},
		-- The accessory key each placed hand's spot was found under (placeHands.getSpotKeys).
		spotKey = {},
	}, Mechanism)
	instances[#instances + 1] = self
	if gripOptions ~= nil then registerGripClaim(self, tonumber(gripOptions.priority), gripOptions.hide or grip.Hide.Systems) end
	-- A mechanism made in code gets a saved entry under its name, for its settings.
	if not self.isData then
		local params = getParamManager()
		local entry = getEntry(name)
		if entry == nil or entry.code ~= true then params:set(name, {code = true}, true) end
		if params:get({"_profileLabels", name}) == nil then params:set({"_profileLabels", name}, self.label, true) end
	end
	installHooks()
	if configDev ~= nil and not syncing then configDev.refresh() end
	return self
end

function Mechanism:setEnabled(value)
	self.enabled = value == true
	if self.enabled then return end
	release(self, "disabled")
	self.actor = nil
	self.touching[Handed.Left], self.touching[Handed.Right] = false, false
	letGoOfGrips(self)
	if self.prompt ~= nil then clearPrompt(self) end
end
Mechanism.setEnabled = uevrUtils.profiler:wrap("MECHANISMS: Mechanism:setEnabled", Mechanism.setEnabled)

function Mechanism:setPromptText(text)
	self.promptText = text
end

function Mechanism:isEnabled()
	return self.enabled
end

function Mechanism:isEngaged()
	return self.engaged
end

function Mechanism:isHandEngaged(hand)
	return self.engaged and self.touching[hand] == true
end

function Mechanism:getActor()
	return uevrUtils.getValid(self.actor)
end

function Mechanism:getProgress()
	return self.progress
end

function Mechanism:getPhase()
	return self.phase
end

function Mechanism:getValue()
	return self.value
end

function Mechanism:reset()
	release(self, "reset")
	self.actor = nil
	if self.prompt ~= nil then clearPrompt(self) end
	self.scanElapsed, self.waitForClear = 0, false
	self.touching[Handed.Left], self.touching[Handed.Right] = false, false
	letGoOfGrips(self)
end
Mechanism.reset = uevrUtils.profiler:wrap("MECHANISMS: Mechanism:reset", Mechanism.reset)

function M.isHandEngaged(hand)
	for _, self in ipairs(instances) do
		if self:isHandEngaged(hand) then return true end
	end
	return false
end
M.isHandEngaged = uevrUtils.profiler:wrap("MECHANISMS: isHandEngaged", M.isHandEngaged)

-- The engaged mechanism the hand is in contact with (any stage of an entry), or nil.
function M.getEngagedMechanism(hand)
	for _, self in ipairs(instances) do
		if self:isHandEngaged(hand) then return self end
	end
	return nil
end
M.getEngagedMechanism = uevrUtils.profiler:wrap("MECHANISMS: getEngagedMechanism", M.getEngagedMechanism)

------------------- Entries: mechanisms made from saved entries, and what the config UI needs -------------------
function Mechanism:getName()
	return self.name
end

function Mechanism:getEntryID()
	return self.entryID
end

-- Made from a saved entry (not in code).
function Mechanism:isDataDefined()
	return self.isData
end

-- Its entry's type and its stage of that type (both nil: made in code).
function Mechanism:getType()
	return self.typeName
end

function Mechanism:getStage()
	return self.stageName
end

function Mechanism:getLabel()
	return getParamManager():get({"_profileLabels", self.entryID}) or self.label
end

function Mechanism:findNearest()
	if self.findNearestFn == nil then return nil end
	return uevrUtils.getValid(self.findNearestFn())
end
Mechanism.findNearest = uevrUtils.profiler:wrap("MECHANISMS: Mechanism:findNearest", Mechanism.findNearest)

function Mechanism:getAccessoryComponent(actor)
	actor = uevrUtils.getValid(actor)
	if actor == nil then return nil end
	return getSpotComponent(self, actor)
end

-- The class names of the mechanism's variations (not those removed), sorted.
function Mechanism:getVariations()
	local names = {}
	local entry = getEntry(self.entryID)
	for className, variation in pairs(entry ~= nil and type(entry.variations) == "table" and entry.variations or {}) do
		if type(variation) == "table" and variation.removed ~= true then names[#names + 1] = className end
	end
	table.sort(names)
	return names
end

-- Whether a variation uses the mechanism's Default settings (true for one with no saved settings of its own).
function Mechanism:usesDefault(className)
	return getOverride(getEntry(self.entryID), className) == nil
end

-- Whether the class was put under the mechanism by hand (not one derived from the mechanism's own class).
function Mechanism:isAddedVariation(className)
	local variation = getVariation(getEntry(self.entryID), className)
	return variation ~= nil and variation.added == true
end

-- The settings of its type (made in code: M.SETTING_KEYS) as they apply to a variation (nil: the Default).
function Mechanism:getSettings(className)
	local entry = getEntry(self.entryID)
	local override = className ~= nil and getOverride(entry, className) or nil
	local settings = {}
	local keys, defaults = getTypeSettings(self.isData and getEntryTypeName(entry) or M.DEFAULT_TYPE)
	for _, key in ipairs(keys) do
		local value = pickSetting(override, entry, key)
		if value == nil then value = defaults[key] end
		settings[key] = value
	end
	if not self.isData then
		settings.contactDistance = tonumber(entry ~= nil and entry.contactDistance or nil) or self.contactDistance
		settings.releaseAfter = tonumber(entry ~= nil and entry.releaseAfter or nil) or self.defaults.releaseAfter or 0
		settings.engageWith = tonumber(entry ~= nil and entry.engageWith or nil) or self.defaults.engageWith
		settings.release = tonumber(entry ~= nil and entry.release or nil) or self.defaults.release
	end
	return settings
end

-- Whether Engage With applies to it: not with a grip engagement of its own (options.grip), and for an entry only in a stage with
-- Button's settings.
function Mechanism:canEngageWithGrip()
	return self.gripName == nil and (not self.isData or self.usesButtonSettings == true)
end

-- Its prompt option's text ("" when it gives none) and gripText; both nil without a prompt.
function Mechanism:getPromptTexts()
	if self.prompt == nil then return nil, nil end
	return self.prompt.text or "", self.prompt.gripText
end

-- The accessory key of a variation's hand spots (nil: the Default's): its own when it has settings of its own, else the Default's.
function Mechanism:getAccessoryKey(className)
	local entry = getEntry(self.entryID)
	local override = className ~= nil and getOverride(entry, className) or nil
	if override ~= nil and override.accessoryKey ~= nil then return override.accessoryKey end
	if self.isData then return entry ~= nil and entry.accessoryKey or self.entryID end
	return entry ~= nil and entry.accessoryKey or self.accessoryKey
end

-- Every accessory key the mechanism has hand spots under: the Default's, then each variation's own.
function Mechanism:getAccessoryKeys()
	local keys, seen = {}, {}
	local function add(key)
		if key ~= nil and not seen[key] then
			seen[key] = true
			keys[#keys + 1] = key
		end
	end
	add(self:getAccessoryKey())
	local entry = getEntry(self.entryID)
	for _, className in ipairs(self:getVariations()) do
		local variation = getVariation(entry, className)
		if variation ~= nil then add(variation.accessoryKey) end
	end
	return keys
end
Mechanism.getAccessoryKeys = uevrUtils.profiler:wrap("MECHANISMS: Mechanism:getAccessoryKeys", Mechanism.getAccessoryKeys)

-- A Ladder's side hand spots (Climbing's sides): the accessory key of a variation's (nil: the Default's), its hand spots' key with
-- SIDE_SPOTS_SUFFIX. nil for any other type.
function Mechanism:getSideAccessoryKey(className)
	if self.typeName ~= "ladder" then return nil end
	local key = self:getAccessoryKey(className)
	return key ~= nil and key .. SIDE_SPOTS_SUFFIX or nil
end

-- Every side accessory key of a Ladder (getSideAccessoryKey): the Default's, then each variation's own. Empty for any other type.
function Mechanism:getSideAccessoryKeys()
	local keys = {}
	if self.typeName ~= "ladder" then return keys end
	for _, key in ipairs(self:getAccessoryKeys()) do keys[#keys + 1] = key .. SIDE_SPOTS_SUFFIX end
	return keys
end

-- How far (cm) the hand is from its nearest hand spot on the actor found (or the nearest actor), and that spot's label; nil with
-- no actor or spot.
function Mechanism:getHandSpotDistance(hand)
	local actor = uevrUtils.getValid(self.actor) or self:findNearest()
	local location = controllers.getControllerLocation(hand)
	if actor == nil or location == nil then return nil end
	local key = getRuntime(self, actor).accessoryKey
	if key == nil then return nil end
	local _, _, distance, label = findHandSpot(self, key, actor, hand, location)
	if distance == nil then return nil end
	return math.sqrt(distance), label
end
Mechanism.getHandSpotDistance = uevrUtils.profiler:wrap("MECHANISMS: Mechanism:getHandSpotDistance", Mechanism.getHandSpotDistance)

-- Those made in code, and the first stage of each entry (isPrimary): the entry's other stages are not listed.
function M.getMechanisms()
	local list = {}
	for _, self in ipairs(instances) do
		if self.isPrimary ~= false then list[#list + 1] = self end
	end
	return list
end

-- The mechanism of an entry's first stage, or one made in code.
local function getMechanismByEntry(id)
	for _, self in ipairs(instances) do
		if self.entryID == id and self.isPrimary ~= false then return self end
	end
	return nil
end

local function getMechanismByName(name)
	for _, self in ipairs(instances) do
		if self.name == name then return self end
	end
	return nil
end

------------------- Types -------------------
-- See Types above. defineType(name, def), def:
--   label         the type's name in the config UI
--   settingKeys   its settings, in order; settingDefaults: each one's value when an entry doesn't say
--   stages        list, in order, of:
--       name      e.g. "press"; label: its name in the config UI
--       state     the state (M.State) its things are in while it is active
--       switch    (optional) a setting of the type that switches the stage off, for a variation, when false
--       leaveOut  (optional) function(actor) -> true: the stage leaves the actor to the game for now (it is not found)
--       needs     (optional) the game adapter functions it needs besides its state, by path (e.g. "ladder.isIdle")
--       buttonSettings  (optional) true: it uses Button's settings (its button, and when the hands let go: release, releaseAfter)
--       build     function(stage) -> mechanisms.new options for its kind, driver, engagement and the like; the name, entry,
--                 find, findNearest and (when not given) isAllowed are filled in here. stage: {id = entry ID, name, mechanism},
--                 mechanism set once it is made (for its drivers).
local function defineType(name, def)
	types[name] = {name = name, label = def.label or name, settingKeys = def.settingKeys or {}, settingDefaults = def.settingDefaults or {},
		stages = def.stages or {}}
	typeOrder[#typeOrder + 1] = name
end

-- The game adapter functions a stage needs that the game doesn't supply.
local function getStageMissing(stage)
	local missing = {}
	if not supportsState(stage.state) then missing[#missing + 1] = "getState (" .. tostring(stage.state) .. ")" end
	for _, path in ipairs(stage.needs or {}) do
		if not hasAdapterFunction(path) then missing[#missing + 1] = path end
	end
	return missing
end

-- A setting of an entry as it applies to an actor's variation: the variation's own, else the Default's, else the type's value.
local function getActorSetting(id, actor, key)
	local entry = getEntry(id)
	local _, className = resolveEntryID(actor)
	local value = pickSetting(getOverride(entry, className), entry, key)
	if value == nil then
		local _, defaults = getTypeSettings(getEntryTypeName(entry))
		value = defaults[key]
	end
	return value
end
getActorSetting = uevrUtils.profiler:wrap("MECHANISMS: getActorSetting", getActorSetting)

-- The grip animation its stage chose for a hand in contact, for its actor's variation (Ladder's Climbing: climbGripAnimation),
-- or nil for the Default: the hand spot's own.
function Mechanism:getGripAnimation()
	if self.typeName ~= "ladder" or self.stageName ~= "climb" then return nil end
	local actor = uevrUtils.getValid(self.actor)
	if actor == nil then return nil end
	local id = getActorSetting(self.entryID, actor, "climbGripAnimation")
	if type(id) ~= "string" or id == "" then return nil end
	return id
end
Mechanism.getGripAnimation = uevrUtils.profiler:wrap("MECHANISMS: Mechanism:getGripAnimation", Mechanism.getGripAnimation)

-- Whether a stage that can be switched off is on for the Default or for any variation with settings of its own.
local function isStageUsed(entry, stage)
	if stage.switch == nil then return true end
	local _, defaults = getTypeSettings(getEntryTypeName(entry))
	local function isOn(value)
		if value == nil then value = defaults[stage.switch] end
		return value ~= false
	end
	local own = nil
	if entry ~= nil then own = entry[stage.switch] end
	if isOn(own) then return true end
	for _, variation in pairs(entry ~= nil and type(entry.variations) == "table" and entry.variations or {}) do
		if type(variation) == "table" and variation.useDefault == false and variation.removed ~= true then
			local value = variation[stage.switch]
			if value == nil then value = own end
			if isOn(value) then return true end
		end
	end
	return false
end

-- One stage of a saved entry, as a mechanism. It finds the entry's actors in the stage's state (with the stage switched on for
-- their variation), and nothing while the game adapter lacks a function the stage needs.
local function newStageMechanism(item, def, stage, name, isPrimary)
	local id = item.id
	local context = {id = id, name = stage.name, mechanism = nil}
	local options = stage.build(context)
	if type(options) ~= "table" then return nil end
	local isIncluded = nil
	if stage.switch ~= nil or stage.leaveOut ~= nil then
		isIncluded = function(actor)
			if stage.switch ~= nil and getActorSetting(id, actor, stage.switch) == false then return false end
			return stage.leaveOut == nil or stage.leaveOut(actor) ~= true
		end
	end
	options.name = name
	options.entryID = id
	options.isData = true
	options.find = function()
		if #getStageMissing(stage) > 0 then return nil end
		return findEntryActor(id, stage.state, isIncluded)
	end
	options.findNearest = function() return findNearestEntryActor(id) end
	if options.isAllowed == nil then options.isAllowed = function() return adapterCall("isAllowed") ~= false end end
	local self = M.new(options)
	if self == nil then return nil end
	self.typeName, self.stageName, self.isPrimary = def.name, stage.name, isPrimary
	self.usesButtonSettings = stage.buttonSettings == true
	context.mechanism = self
	self:setEnabled(entriesEnabled)
	return self
end

-- Button: reach a hand spot, then the button is tapped or held (as set for the actor's variation), with the game adapter saying
-- whether the game is working the actor and whether it finished.
local function buildButtonStage(stage)
	return {
		kind = "contact",
		driver = {
			onInput = function(actor, state, engagedFor)
				local runtime = getRuntime(stage.mechanism, actor)
				if runtime.action == M.Action.Hold or (tonumber(engagedFor) or 0) < TAP_DURATION then
					uevrUtils.pressButton(state, getButtonValue(runtime.button))
				end
			end,
			isActive = function(actor)
				-- Held until the hand pulls back or lets go of its grip: whether the game took the press doesn't matter.
				if getRuntime(stage.mechanism, actor).handHeld then return true end
				return getActorState(actor) == M.State.Busy
			end,
			isDone = function(actor)
				return adapterCall("isFinished", actor) == true
			end,
		},
		prompt = adapterPrompt,
		-- One hand at a spot starts it; the other can join at a spot of its own, or stay off.
		hands = 1,
		latchContact = true,
		-- Time for the game to take the press before it counts as refused.
		startTimeout = 1.5,
	}
end

defineType("button", {
	label = "Button",
	settingKeys = M.SETTING_KEYS,
	settingDefaults = M.ENTRY_DEFAULTS,
	stages = {
		{name = "press", label = "Pressing", state = M.State.Offered, buttonSettings = true, build = buildButtonStage},
	},
})

-- Ladder (see Types). The game's facts come from the adapter's ladder table.
local LADDER_GRIP_PRIORITY = 1000 -- the climb's grip claim, when the adapter's ladder table gives none
local SCENE_COMPONENT_CLASS = "Class /Script/Engine.SceneComponent"

-- The answer of a function of the adapter's ladder table, or nil when it has none.
local function ladderCall(name, ...)
	local ladder = adapter ~= nil and adapter.ladder or nil
	local fn = type(ladder) == "table" and ladder[name] or nil
	if type(fn) ~= "function" then return nil end
	return fn(...)
end
ladderCall = uevrUtils.profiler:wrap("MECHANISMS: ladderCall", ladderCall)

-- The player is at the ladder's top, not its foot: above the middle of the range the game rests in while climbing (getRange).
local function isAtLadderTop(actor)
	local player = uevrUtils.getValid(pawn)
	local low, high = ladderCall("getRange", actor)
	low, high = tonumber(low), tonumber(high)
	if player == nil or low == nil or high == nil then return false end
	return player:K2_GetActorLocation().Z > (low + high) / 2
end
isAtLadderTop = uevrUtils.profiler:wrap("MECHANISMS: isAtLadderTop", isAtLadderTop)

-- A ladder's rungs: {address, count, topZ (world), pitch}. Kept for the last ladder asked, once it gives them.
local function getLadderRungs(actor)
	local address = actor:get_address()
	local cached = ladderState.rungs
	if cached ~= nil and cached.address == address then return cached end
	local count, topZ, pitch = ladderCall("getRungs", actor)
	count, topZ, pitch = tonumber(count), tonumber(topZ), tonumber(pitch)
	if count == nil or count < 1 or topZ == nil or pitch == nil or pitch <= 0 then return nil end
	ladderState.rungs = {address = address, count = count, topZ = topZ, pitch = pitch}
	return ladderState.rungs
end
getLadderRungs = uevrUtils.profiler:wrap("MECHANISMS: getLadderRungs", getLadderRungs)

-- What a hand's spot is put on while it holds a rung: one scene component per hand, made when first needed (a hand holds one rung
-- of one ladder at a time).
local function getRungTarget(hand)
	local component = uevrUtils.getValid(ladderState.rungTargets[hand])
	if component == nil then
		component = uevrUtils.create_component_of_class(SCENE_COMPONENT_CLASS)
		ladderState.rungTargets[hand] = component
	end
	return uevrUtils.getValid(component)
end
getRungTarget = uevrUtils.profiler:wrap("MECHANISMS: getRungTarget", getRungTarget)

-- Climbing: a grip on the ladder takes hold and pulling climbs. A hand holds its rungs or (sideGrip) its sides, each with settings of
-- its own. On a rung (snapHands), a hand that takes hold is put on its hand spot moved by whole rungs to the rung it took, so the
-- spot's pose and grip are the same on every rung. On a side, it holds on where it took hold, or (sideSnap) is put on its hand spot
-- at that height.
local function buildClimbStage(stage)
	local function getFrame(actor)
		local frame = ladderCall("getFrame", actor)
		return uevrUtils.getValid(frame) or actor
	end
	-- The part of the ladder at a distance along the rungs from their centre line: "side" from sideStart out (with sideGrip on),
	-- else "rung".
	local function getPartAcross(actor, across)
		if getActorSetting(stage.id, actor, "sideGrip") ~= true then return "rung" end
		local start = tonumber(getActorSetting(stage.id, actor, "sideStart")) or 0
		return math.abs(across) >= start and "side" or "rung"
	end
	-- The part of the ladder at a world location.
	local function getPartAt(actor, location)
		if getActorSetting(stage.id, actor, "sideGrip") ~= true then return "rung" end
		local x, y = M.toFrameSpace(getFrame(actor), location)
		if x == nil then return "rung" end
		local _, normal = ladderCall("getFrame", actor)
		return getPartAcross(actor, normal == "y" and x or y)
	end
	-- A side grip with sideSnap: the spot component moved straight up or down, so the spot is at the height the hand took hold at
	-- (lined up with the side, never moved along it). Without sideSnap, or with no spot, the hand holds on where it is.
	local function getSideTarget(actor, hand, handLocation, spot)
		if spot == nil or getActorSetting(stage.id, actor, "sideSnap") ~= true then return nil end
		local spotComponent = stage.mechanism ~= nil and stage.mechanism:getAccessoryComponent(actor) or nil
		local target = getRungTarget(hand)
		if spotComponent == nil or target == nil then return nil end
		local origin = spotComponent:K2_GetComponentLocation()
		-- The spot is spot.location.z above the component (the ladder stands upright).
		local z = handLocation.Z - spot.location.z
		target:K2_SetWorldLocationAndRotation(uevrUtils.vector(origin.X, origin.Y, z), spotComponent:K2_GetComponentRotation(), false, reusable_hit_result, true)
		return target
	end
	local facts = adapter ~= nil and adapter.ladder or nil
	local priority = type(facts) == "table" and tonumber(facts.gripPriority) or nil
	return {
		kind = "ladder",
		-- Hidden from the game only: the mod's own input callbacks still see the grip, so a hand animation can close the hand.
		grip = {priority = priority or LADDER_GRIP_PRIORITY, hide = grip.Hide.Game},
		-- One hand holding on climbs; letting go with both lets go of the ladder.
		hands = 1,
		keepHands = 1,
		-- The driver pulses each hand as it takes hold.
		haptics = {engage = false},
		getFrame = getFrame,
		ladder = {
			halfWidth = 35,
			reach = 30,
			behind = 20,
			-- The bottom and top rungs, in the frame's z (the ladder stands upright).
			getBounds = function(actor)
				local rungs = getLadderRungs(actor)
				local frame = getFrame(actor)
				if rungs == nil or frame == nil then return nil end
				local location = frame.K2_GetActorLocation ~= nil and frame:K2_GetActorLocation() or frame:K2_GetComponentLocation()
				return rungs.topZ - (rungs.count - 1) * rungs.pitch - location.Z, rungs.topZ - location.Z
			end,
			getAxes = function(actor)
				local _, normal, side = ladderCall("getFrame", actor)
				return normal or "x", side or 1
			end,
			-- A part switched off (rungGrip, sideGrip) isn't held.
			allowAt = function(actor, across)
				if getPartAcross(actor, across) == "side" then return true end
				return getActorSetting(stage.id, actor, "rungGrip") ~= false
			end,
		},
		placeHands = {
			-- A side grip takes the side hand spots (the hand spots' key with SIDE_SPOTS_SUFFIX), else, with none for that hand, the
			-- hand spots, as a rung grip does.
			getSpotKeys = function(actor, hand, handLocation, key)
				if getPartAt(actor, handLocation) == "side" then return {key .. SIDE_SPOTS_SUFFIX, key} end
				return {key}
			end,
			-- On a side: getSideTarget. On a rung: the spot component (where the spots were placed) moved by whole rungs, from the
			-- spot's rung to the rung nearest the hand.
			getTarget = function(actor, hand, handLocation, spot)
				if getPartAt(actor, handLocation) == "side" then return getSideTarget(actor, hand, handLocation, spot) end
				if spot == nil or getActorSetting(stage.id, actor, "snapHands") == false then return nil end
				local rungs = getLadderRungs(actor)
				local spotComponent = stage.mechanism ~= nil and stage.mechanism:getAccessoryComponent(actor) or nil
				if rungs == nil or spotComponent == nil then return nil end
				local target = getRungTarget(hand)
				if target == nil then return nil end
				local origin = spotComponent:K2_GetComponentLocation()
				local spotRung = math.floor((rungs.topZ - (origin.Z + spot.location.z)) / rungs.pitch + 0.5)
				local handRung = math.floor((rungs.topZ - handLocation.Z) / rungs.pitch + 0.5)
				handRung = math.max(0, math.min(rungs.count - 1, handRung))
				-- snapNear: a hand further than snapDistance (up or down) from that rung doesn't take hold, so it doesn't climb.
				if getActorSetting(stage.id, actor, "snapNear") == true then
					local limit = tonumber(getActorSetting(stage.id, actor, "snapDistance")) or 0
					if math.abs(handLocation.Z - (rungs.topZ - handRung * rungs.pitch)) > limit then return false end
				end
				local x, y, z = origin.X, origin.Y, origin.Z + (spotRung - handRung) * rungs.pitch
				-- rungKeepAlong: also moved along the rung to the hand, so the hand keeps its place along it.
				if getActorSetting(stage.id, actor, "rungKeepAlong") == true then
					local axes = readFrameAxes(getFrame(actor))
					local spotPoint = getAccessories().getTargetAccessoryLocation(spot.key, spot.id, spotComponent)
					if axes ~= nil and spotPoint ~= nil then
						local _, normal = ladderCall("getFrame", actor)
						local handX, handY = toAxesSpace(axes, handLocation)
						local spotX, spotY = toAxesSpace(axes, spotPoint)
						local along, shift = axes.right, handY - spotY
						if normal == "y" then along, shift = axes.forward, handX - spotX end
						x, y, z = x + along.X * shift, y + along.Y * shift, z + along.Z * shift
					end
				end
				target:K2_SetWorldLocationAndRotation(uevrUtils.vector(x, y, z), spotComponent:K2_GetComponentRotation(), false, reusable_hit_result, true)
				return target
			end,
		},
		driver = M.climbDriver({
			isActive = function(actor) return getActorState(actor) == M.State.Busy end,
			isIdle = function(actor) return ladderCall("isIdle", actor) == true end,
			getRange = function(actor) return ladderCall("getRange", actor) end,
			getRungPitch = function(actor)
				local rungs = getLadderRungs(actor)
				return rungs ~= nil and rungs.pitch or nil
			end,
			isDismounting = function(actor) return ladderCall("isDismounting", actor) == true end,
			-- The hand stays on the rung it holds, so nothing passes under it: only taking hold pulses.
			rungHaptic = false,
			-- animateSteps: the game's own step plays as the hands pull (only with the adapter's step functions).
			steps = {
				isEnabled = function(actor)
					return getActorSetting(stage.id, actor, "animateSteps") == true and hasAdapterFunction("ladder.getStep")
						and hasAdapterFunction("ladder.holdStep") and hasAdapterFunction("ladder.finishStep")
				end,
				getLength = function()
					local ladder = adapter ~= nil and adapter.ladder or nil
					return type(ladder) == "table" and tonumber(ladder.stepLength) or nil
				end,
				getStep = function(actor) return ladderCall("getStep", actor) end,
				hold = function(actor, step, phase) ladderCall("holdStep", actor, step, phase) end,
				finish = function(actor, step) ladderCall("finishStep", actor, step) end,
				start = function(actor, direction) ladderCall("startStep", actor, direction) end,
				cancel = function(actor) ladderCall("cancelStep", actor) end,
			},
		}),
	}
end

-- Ladder's settings: useGetOn, Button's (for Getting on), then Climbing's.
local ladderSettingKeys = {"useGetOn"}
---@type table<string, any>
local ladderDefaults = {useGetOn = true}
for _, key in ipairs(M.SETTING_KEYS) do
	ladderSettingKeys[#ladderSettingKeys + 1] = key
	ladderDefaults[key] = M.ENTRY_DEFAULTS[key]
end
ladderSettingKeys[#ladderSettingKeys + 1] = "snapHands"
ladderDefaults.snapHands = true
-- Snapping only a hand that takes hold near a rung, and how near (cm, up or down).
ladderSettingKeys[#ladderSettingKeys + 1] = "snapNear"
ladderSettingKeys[#ladderSettingKeys + 1] = "snapDistance"
ladderDefaults.snapNear = false
ladderDefaults.snapDistance = 5
-- The grip animation of a hand holding the rungs (an id of the hands parameters file's); "" (Default): its hand spot's.
ladderSettingKeys[#ladderSettingKeys + 1] = "climbGripAnimation"
ladderDefaults.climbGripAnimation = ""
-- Playing the game's own step as the hands pull (climbDriver's steps).
ladderSettingKeys[#ladderSettingKeys + 1] = "animateSteps"
ladderDefaults.animateSteps = false
-- Holding the rungs (off: a ladder held only by its sides).
ladderSettingKeys[#ladderSettingKeys + 1] = "rungGrip"
ladderDefaults.rungGrip = true
-- Snapping to a rung keeps the hand's place along it (only its height and depth are snapped).
ladderSettingKeys[#ladderSettingKeys + 1] = "rungKeepAlong"
ladderDefaults.rungKeepAlong = false
-- Holding the sides: from sideStart (cm) out from the rungs' centre line, either way. sideSnap: a hand is lined up with the side on
-- its hand spot, at the height it took hold at.
ladderSettingKeys[#ladderSettingKeys + 1] = "sideGrip"
ladderSettingKeys[#ladderSettingKeys + 1] = "sideStart"
ladderSettingKeys[#ladderSettingKeys + 1] = "sideSnap"
ladderDefaults.sideGrip = false
ladderDefaults.sideStart = 16
ladderDefaults.sideSnap = false

defineType("ladder", {
	label = "Ladder",
	settingKeys = ladderSettingKeys,
	settingDefaults = ladderDefaults,
	stages = {
		-- At the top the hands can't reach the rungs, so the game's own prompt and button get the player on there.
		{name = "geton", label = "Getting on", state = M.State.Offered, switch = "useGetOn", buttonSettings = true, build = buildButtonStage,
			leaveOut = isAtLadderTop},
		{name = "climb", label = "Climbing", state = M.State.Busy, needs = {"ladder.isIdle", "ladder.getRange", "ladder.getRungs", "ladder.getFrame"},
			build = buildClimbStage},
	},
})

-- Makes a mechanism for each stage of each saved entry's type that has none, and removes those whose entry is gone or now has
-- another type. A stage switched off, or missing adapter functions, is still made: it finds nothing until that changes.
local unknownTypes = {}
local function syncEntries()
	syncing = true
	local list, byID = getDataEntries()
	for i = #instances, 1, -1 do
		local self = instances[i]
		if self.isData then
			local item = byID[self.entryID]
			if item == nil or item.type ~= self.typeName then
				self:setEnabled(false)
				table.remove(instances, i)
			end
		end
	end
	for _, item in ipairs(list) do
		local def = types[item.type]
		if def == nil then
			if not unknownTypes[item.type] then
				unknownTypes[item.type] = true
				M.print("Entry " .. tostring(item.id) .. " has a type this library doesn't have: " .. tostring(item.type), LogLevel.Warning)
			end
		else
			for index, stage in ipairs(def.stages) do
				local name = index == 1 and item.id or (item.id .. ":" .. stage.name)
				if getMechanismByName(name) == nil then newStageMechanism(item, def, stage, name, index == 1) end
			end
		end
	end
	syncing = false
end
syncEntries = uevrUtils.profiler:wrap("MECHANISMS: syncEntries", syncEntries)

function M.getTypes()
	local list = {}
	for _, name in ipairs(typeOrder) do list[#list + 1] = {name = name, label = types[name].label} end
	return list
end

function M.getSettingKeys(typeName)
	local keys = getTypeSettings(typeName)
	local list = {}
	for i, key in ipairs(keys) do list[i] = key end
	return list
end

function M.getMissingAdapterFunctions(mechanism)
	local missing, seen = {}, {}
	if mechanism == nil or not mechanism.isData then return missing end
	local entry = getEntry(mechanism.entryID)
	local def = types[getEntryTypeName(entry)]
	if def == nil then return missing end
	for _, stage in ipairs(def.stages) do
		if isStageUsed(entry, stage) then
			for _, path in ipairs(getStageMissing(stage)) do
				if not seen[path] then
					seen[path] = true
					missing[#missing + 1] = path
				end
			end
		end
	end
	return missing
end

function M.getActorState(actor)
	actor = uevrUtils.getValid(actor)
	if actor == nil then return nil end
	return getActorState(actor)
end

function M.getParamManager()
	return getParamManager()
end

-- After a saved entry is changed, added or removed.
function M.notifyEntriesChanged()
	entriesVersion = entriesVersion + 1
	syncEntries()
end

function M.setEntriesEnabled(value)
	entriesEnabled = value == true
	for _, self in ipairs(instances) do
		if self.isData then self:setEnabled(entriesEnabled) end
	end
end

-- Every mechanism (made in code or from an entry) works as usual (prompt, reaching, hands put on their spots, release) but never
-- presses the game's button, so the game doesn't act.
function M.setPaused(value)
	paused = value == true
end

function M.isPaused()
	return paused
end

function M.setScanOptimize(value)
	scanOptimize = value == true
end

-- The actor the game offers to interact with now (the game adapter's getOffered, or the first actor of its baseClass that
-- isOffered), or nil.
local function isActorOffered(actor, isOffered)
	return uevrUtils.getValid(actor) ~= nil and not actor.bActorIsBeingDestroyed and isOffered(actor) == true
end

function M.getOfferedActor()
	if adapter == nil then return nil end
	if type(adapter.getOffered) == "function" then return uevrUtils.getValid(adapter.getOffered()) end
	if type(adapter.isOffered) ~= "function" then return nil end
	local class = getEntryClass(adapter.baseClass)
	if class == nil then return nil end
	for _, actor in ipairs(UEVR_UObjectHook.get_objects_by_class(class, false) or {}) do
		-- An actor being torn down can still be listed and pass exists(), yet reading it hits a null pointer and throws: skip it.
		local ok, offered = pcall(isActorOffered, actor, adapter.isOffered)
		if ok and offered then return actor end
	end
	return nil
end
M.getOfferedActor = uevrUtils.profiler:wrap("MECHANISMS: getOfferedActor", M.getOfferedActor)

local function getLiveActorState(actor)
	if uevrUtils.getValid(actor) == nil or actor.bActorIsBeingDestroyed then return nil end
	return getActorState(actor)
end

-- The actor the game offers or the player is using now, and its state: the game adapter's getCurrent, else the first actor of
-- its baseClass that is offered, else the first with any other state.
function M.getCurrentActor()
	if adapter == nil then return nil end
	if type(adapter.getCurrent) == "function" then
		local actor, state = adapter.getCurrent()
		actor = uevrUtils.getValid(actor)
		if actor == nil then return nil end
		if state == nil then state = getActorState(actor) end
		return actor, state
	end
	-- A game that only says what it offers (getOffered).
	if type(adapter.getOffered) == "function" then
		local actor = uevrUtils.getValid(adapter.getOffered())
		if actor ~= nil then return actor, M.State.Offered end
	end
	local class = getEntryClass(adapter.baseClass)
	if class == nil then return nil end
	local other, otherState = nil, nil
	for _, actor in ipairs(UEVR_UObjectHook.get_objects_by_class(class, false) or {}) do
		-- As in getOfferedActor: an actor being torn down can throw when read.
		local ok, state = pcall(getLiveActorState, actor)
		if ok and state ~= nil then
			if state == M.State.Offered then return actor, state end
			if other == nil then other, otherState = actor, state end
		end
	end
	return other, otherState
end
M.getCurrentActor = uevrUtils.profiler:wrap("MECHANISMS: getCurrentActor", M.getCurrentActor)

-- Changes an entry's type. Its class, variations, settings and hand spots are kept; its mechanisms are made again.
function M.setType(mechanism, typeName)
	if mechanism == nil or not mechanism.isData or types[typeName] == nil then return false end
	getParamManager():set({mechanism.entryID, "type"}, typeName ~= M.DEFAULT_TYPE and typeName or nil, true)
	M.notifyEntriesChanged()
	return true
end

-- The mechanism that handles an actor (the one made from the saved entry it belongs to, or one made in code that found it), and
-- the actor's class name (its variation).
function M.getMechanismForActor(actor)
	actor = uevrUtils.getValid(actor)
	if actor == nil then return nil end
	local id, className = resolveEntryID(actor)
	if id ~= nil then return getMechanismByEntry(id), className end
	local address = actor:get_address()
	for _, self in ipairs(instances) do
		local found = uevrUtils.getValid(self.actor)
		if not self.isData and found ~= nil and found:get_address() == address then return self, className end
	end
	return nil, className
end
M.getMechanismForActor = uevrUtils.profiler:wrap("MECHANISMS: getMechanismForActor", M.getMechanismForActor)

-- "BP_Door_AutoAdvancing_C" from a class's full name.
function M.getShortClassName(path)
	if type(path) ~= "string" then return nil end
	return path:match("%.([^%.]+)$") or path
end

-- Adds a saved entry (a new mechanism) for the actor's class and returns its ID. Everything of that class, and of classes derived
-- from it, belongs to it.
function M.addEntry(actor)
	actor = uevrUtils.getValid(actor)
	local class = actor ~= nil and actor:get_class() or nil
	if class == nil then return nil end
	local className = class:get_full_name()
	local id = uevrUtils.guid()
	local params = getParamManager()
	params:set(id, {class = className}, true)
	local label = (M.getShortClassName(className) or id):gsub("^BP_", ""):gsub("_C$", ""):gsub("_", " ")
	params:set({"_profileLabels", id}, label, true)
	M.notifyEntriesChanged()
	return id
end

-- Removes a saved entry (not one of a mechanism made in code).
function M.removeEntry(id)
	local self = getMechanismByEntry(id)
	if self == nil or not self.isData then return false end
	local params = getParamManager()
	params:set(id, nil, true)
	params:set({"_profileLabels", id}, nil, true)
	M.notifyEntriesChanged()
	return true
end

-- Puts the actor's class under a mechanism by hand, as a variation that uses its Default: for something that works like the
-- mechanism but is not derived from the mechanism's own class. Returns the class name.
function M.addVariation(mechanism, actor)
	actor = uevrUtils.getValid(actor)
	local class = actor ~= nil and actor:get_class() or nil
	if class == nil or mechanism == nil or not mechanism.isData then return nil end
	local className = class:get_full_name()
	getParamManager():set({mechanism.entryID, "variations", className}, {useDefault = true, added = true}, true)
	M.notifyEntriesChanged()
	return className
end

-- Removes a variation and its own settings. It is saved as removed: the mechanism no longer handles it and it is not listed again
-- when next seen. It can be added back by hand (M.addVariation).
function M.removeVariation(mechanism, className)
	if mechanism == nil or not mechanism.isData or className == nil then return false end
	getParamManager():set({mechanism.entryID, "variations", className}, {removed = true}, true)
	M.notifyEntriesChanged()
	return true
end

-- Whether a variation uses the mechanism's Default settings. The first time it stops using them it gets a copy of them, and of
-- the Default's hand spots, to change; after that its own are kept, used or not.
function M.setVariationUseDefault(mechanism, className, useDefault)
	if mechanism == nil or not mechanism.isData or className == nil then return false end
	local params = getParamManager()
	local entry = getEntry(mechanism.entryID)
	local variation = getVariation(entry, className)
	if variation == nil then
		params:set({mechanism.entryID, "variations", className}, {useDefault = true}, true)
		variation = getVariation(getEntry(mechanism.entryID), className)
	end
	if variation == nil then return false end
	if useDefault ~= true and variation.copied ~= true then
		local keys, defaults = getTypeSettings(getEntryTypeName(entry))
		for _, key in ipairs(keys) do
			local value = nil
			if entry ~= nil then value = entry[key] end
			if value == nil then value = defaults[key] end
			variation[key] = value
		end
		local key = mechanism.entryID .. "_" .. (M.getShortClassName(className) or className)
		getAccessories().copyAccessories(mechanism:getAccessoryKey(), key)
		-- A Ladder's side hand spots go with them.
		local sideKey = mechanism:getSideAccessoryKey()
		if sideKey ~= nil then getAccessories().copyAccessories(sideKey, key .. SIDE_SPOTS_SUFFIX) end
		variation.accessoryKey = key
		variation.copied = true
	end
	variation.useDefault = useDefault == true
	params:set({mechanism.entryID, "variations", className}, variation, true)
	M.notifyEntriesChanged()
	return true
end

-- Saves a setting (one of its type's) of a variation that has settings of its own, or (className nil, or a variation using the
-- Default) of the mechanism's Default.
function M.setSetting(mechanism, className, key, value)
	if mechanism == nil then return end
	local path = {mechanism.entryID, key}
	if className ~= nil and getOverride(getEntry(mechanism.entryID), className) ~= nil then
		path = {mechanism.entryID, "variations", className, key}
	end
	getParamManager():set(path, value, true)
	M.notifyEntriesChanged()
end

-- For the config UI (developer mode): lists, as a variation using the Default, every class of live actor that belongs to a
-- mechanism and isn't listed yet. Returns true when one was added. Each class is looked at once until an entry changes.
local discovered = {version = -1, classes = {}}
function M.discoverVariations()
	if discovered.version ~= entriesVersion then discovered = {version = entriesVersion, classes = {}} end
	local params = getParamManager()
	local changed = false
	for _, item in ipairs(getDataEntries()) do
		forEachEntryActor(item.id, function(actor)
			local class = actor:get_class()
			local address = class ~= nil and class:get_address() or nil
			if address ~= nil and not discovered.classes[address] then
				discovered.classes[address] = true
				local id, className = resolveEntryID(actor)
				if id == item.id and className ~= nil and getVariation(getEntry(id), className) == nil then
					params:set({id, "variations", className}, {useDefault = true}, true)
					changed = true
				end
			end
			return false
		end)
	end
	if changed then
		local classes = discovered.classes
		M.notifyEntriesChanged()
		-- The classes looked at are still listed or belong elsewhere.
		discovered = {version = entriesVersion, classes = classes}
	end
	return changed
end
M.discoverVariations = uevrUtils.profiler:wrap("MECHANISMS: discoverVariations", M.discoverVariations)

-- The config widget prefix of the accessory editor for an accessory key.
function M.getAccessoryWidgetPrefix(key)
	return WIDGET_PREFIX .. tostring(key) .. "_"
end

-- For libs/accessories' target callback (getAccessoryTargetAnswer): what a hand is put on,
-- and the accessory key its hand spots are saved under. A hand working a mechanism gets the mechanism's actor; in developer
-- mode a hand whose Test box is ticked in one of a mechanism's accessory editors gets it too (the actor found or, with none, the
-- nearest), so a spot can be tuned without working the mechanism.
-- The hand grip animations, from libs/hands_animation through its event (it is not required here). nil while it isn't loaded.
function M.getHandAnimations()
	local out = {}
	uevrUtils.executeUEVRCallbacks("get_hand_animation_ids", out)
	if out.ids == nil then return nil end
	return out.ids, out.labels
end

function M.getAccessoryTarget(hand)
	if not isHandReady(hand) then return nil end
	local testID = hand == Handed.Left and "accessory_item_test_left_hand" or "accessory_item_test_right_hand"
	for _, self in ipairs(instances) do
		local actor = uevrUtils.getValid(self.actor)
		if self.engaged and self.touching[hand] == true and actor ~= nil then
			local key = getRuntime(self, actor).accessoryKey
			local component = nil
			if key ~= nil then
				-- Hands placed by the game are each on what the game chose for that hand as it took hold.
				if self.placeHands ~= nil then
					component = uevrUtils.getValid(self.spotTarget[hand])
					-- Under the key its spot was found under (getSpotKeys).
					key = self.spotKey[hand] or key
				else
					component = getSpotComponent(self, actor)
				end
			end
			if component ~= nil then return component, key end
		end
		if configDev ~= nil then
			local keys = self:getAccessoryKeys()
			for _, key in ipairs(self:getSideAccessoryKeys()) do keys[#keys + 1] = key end
			for _, key in ipairs(keys) do
				if configui.getValue(M.getAccessoryWidgetPrefix(key) .. testID) == true then
					local target = actor or self:findNearest()
					local component = target ~= nil and getSpotComponent(self, target) or nil
					if component ~= nil then return component, key end
				end
			end
		end
	end
	return nil
end
M.getAccessoryTarget = uevrUtils.profiler:wrap("MECHANISMS: getAccessoryTarget", M.getAccessoryTarget)

function M.init(isDeveloperMode, logLevel)
	if logLevel ~= nil then M.setLogLevel(logLevel) end
	if isDeveloperMode == nil and uevrUtils.getDeveloperMode() ~= nil then
		isDeveloperMode = uevrUtils.getDeveloperMode()
	end
	getParamManager()
	syncEntries()
	if isDeveloperMode and configDev == nil then
		configDev = require("libs/config/mechanisms_config_dev")
		configDev.init(M)
	end
end

return M
