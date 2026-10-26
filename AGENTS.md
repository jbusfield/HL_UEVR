# Project instructions

## Required user coding preference: no production assertions

- Do not add assertions (`assert`, debug assertions, or equivalent checks that deliberately throw/abort) to the user's production/runtime code.
- Handle expected failures with ordinary guards, explicit return values, cleanup, and bounded diagnostic logging.
- Assertions are permitted only in isolated test code or temporary testing instrumentation with a specific, stated testing reason. Remove temporary instrumentation before delivering runtime code.
- Do not replace an assertion with an unconditional `error`/throw that has the same effect.
- Apply this rule during implementation, review, delegation, and handoffs. Before finishing, check changed runtime code for newly introduced assertions.

## Required UEVR coding preference: native calls first

- Use native UEVR Lua methods and property access by default. Supply correctly typed native arguments such as FName, FVector, FRotator, and FTransform when required.
- Use the existing global `reusable_hit_result` for ignored hit-result outputs instead of allocating a new FHitResult. Use a separate result only when its contents must be retained independently.
- Use `scripts/libs/core/plugin.lua` helpers only when necessary: Unreal `TArray`, `TMap`, or `TSet` properties/parameters/returns that native Lua cannot marshal reliably, or a specific native-binding limitation supported by applicable evidence.
- Do not use the bridge for ordinary function calls, transforms, attachments, scalar properties, or asset operations merely for convenience or consistency with existing code.
- An inherited comment or another helper's implementation is not proof that a native call is unsupported. Check the actual signature, argument types, and relevant recorded evidence before introducing a workaround; do not repeat a known crashing probe just to reconfirm it.
- MCP's reflected calls and separate Lua bindings do not establish whether direct calls work in the game's native UEVR Lua state. Distinguish isolated tests, MCP probes, and native gameplay verification in reports.
- Document the concrete reason for each non-container bridge workaround. Apply this rule during implementation, review, and handoffs; check newly added bridge calls before finishing.

## Project context

- Runtime asset lookups must never fall back to scanning the game object hierarchy. A failed full-name lookup can pause the game for over a second. Do not use `find_required_object` or raw `uevr.api:find_uobject` to probe whether a palette asset is loaded; use the existing path-based asset loader and ordinary failure guards. Removing the warning alone does not solve the scan. Leave `uevr_lib` unchanged.
- Do not add `pcall` wrappers to palette's tick or its per-frame update helpers. Use ordinary guards and explicit return values for expected failures; do not hide a per-frame protected call by moving it to another function. Existing event-driven build/selection rollback is separate from per-frame updates.
- Keep palette's idle tick dispatcher outside profiler wrappers. Closed/inactive frames must not perform native queries or dilute active profiling averages. Report open-wheel, closing-effect, held-item-only and queued-action ticks separately.
- Ask the user before changing logging levels or suppressing existing diagnostic output, including as a performance optimization. Do not silently disable animation debug logging.

- This repository is the Hogwarts Legacy UEVR mod. Follow the user's shared UEVR guidance and verify game-specific assets and objects against the running build.
- Gameplay Lua files are hard-linked into the live profile; follow the shared "preserve hard-linked files" rule (edit in place only, never relink or recreate files). Preserve user edits and request UEVR **Reset Scripts** when activation is needed.
- `PALETTE_PLAN.md` records the current palette design. `.tools/gadget-activation-investigation.md` records verified gadget selection/use calls.
