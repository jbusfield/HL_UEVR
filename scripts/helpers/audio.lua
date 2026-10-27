local uevrUtils = require("libs/uevr_utils")

local M = {}
-- .tools/shared-audio-lib-notes.md

-- Wwise "swoosh" that accompanies the apparition swirl (boats and palette).
local SWIRL_SOUND = "AkAudioEvent /Game/WWise/Events/Transfiguration/Conjuration/Transfiguration_Conjuration_Placement_Appear_Play.Transfiguration_Conjuration_Placement_Appear_Play"

local swirlSound = nil

-- Play the apparition swirl's sound at a world location. worldContext is any live object in the world.
function M.playSwirlSound(worldContext, location)
	swirlSound = uevrUtils.getValid(swirlSound) or uevrUtils.getValid(uevrUtils.getLoadedAsset(SWIRL_SOUND))
	local statics = uevrUtils.find_default_instance("Class /Script/AkAudio.AkGameplayStatics")
	if swirlSound == nil or statics == nil then print("Audio: swirl sound unavailable"); return false end
	return statics:PostEventAtLocation(swirlSound, location, uevrUtils.rotator(0, 0, 0), "", worldContext) ~= 0
end

return M
