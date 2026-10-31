-- Precedence of the systems that share the VR grips through libs/grip: the claim with the highest number owns a press.
-- Kept in one table so the order is visible and adjustable in one place.
local M = {
	LADDER = 1000,       -- ladder.lua: a grip that starts with a ladder rung in reach (hidden from other systems until released)
	ITEM_HELD = 200,     -- interactions.lua (Physical Item Grab): a press while an item is already flying or held
	PALETTE_WHEEL = 100, -- palette.lua: a left grip that starts with the palette wheel open selects from it
	HEAD_GESTURE = 90,   -- main.lua: a left grip that starts at the ear opens the menu
	ITEM_GRAB = 50,      -- interactions.lua (Physical Item Grab): grab, or hold X on, what the game's interaction prompt is on
}

return M