local uevrUtils = require('libs/uevr_utils')
local configui = require('libs/configui')
local hands = require('libs/hands')
local ik = require('libs/ik')

-- Keeps the hands' materials in step with SkinFX on the pawn (potions, Disillusionment, Invisibility).
-- Uses main.lua's global getCustomIKComponent() to find the pawn meshes the hands were built from.
local M = {}

-- Values of main.lua's hands_type selection
local HandsType = {
	Forearms = 1,
	IKArms = 2,
}

local function getHandsMeshes()
	local meshes = {}
	local handsType = configui.getValue("hands_type")
	if handsType == HandsType.IKArms then
		local index = 1
		local mesh = ik.exists() and ik.getCurrentMesh(index) or nil
		while mesh ~= nil do
			meshes[#meshes + 1] = mesh
			index = index + 1
			mesh = ik.getCurrentMesh(index)
		end
	elseif handsType == HandsType.Forearms then
		for _, hand in ipairs({Handed.Left, Handed.Right}) do
			for _, mesh in ipairs(hands.getHandComponentsForHand(hand)) do
				meshes[#meshes + 1] = mesh
			end
		end
	end
	return meshes
end

-- Pairs each hands mesh with the pawn mesh it was built from.
-- The IK descriptors also cover every mesh getCustomHandComponent() can return (which has side effects).
local function getHandsMaterialSources()
	local handsSources = {}
	local meshes = getHandsMeshes()
	if #meshes == 0 then return handsSources end
	local sources = {}
	for _, template in ipairs(getCustomIKComponent() or {}) do
		local source = uevrUtils.getValid(uevrUtils.getObjectFromDescriptor(template.descriptor, false))
		if source ~= nil and source.SkeletalMesh ~= nil then
			sources[source.SkeletalMesh:get_address()] = source
		end
	end
	for _, mesh in ipairs(meshes) do
		local source = uevrUtils.getValid(mesh) ~= nil and mesh.SkeletalMesh ~= nil and sources[mesh.SkeletalMesh:get_address()]
		if source then
			handsSources[#handsSources + 1] = {mesh = mesh, source = source}
		end
	end
	return handsSources
end

-- Copy the current materials (e.g. a SkinFX effect) from the pawn meshes the hands were built from
local function setHandsMaterials(handsSources)
	for _, hand in ipairs(handsSources or getHandsMaterialSources()) do
		uevrUtils.copyMaterials(hand.source, hand.mesh)
	end
end
setHandsMaterials = uevrUtils.profiler:wrap("Hands: sync materials", setHandsMaterials)

-- SkinFX effects (potions, disillusionment, invisibility potion, snow) swap every pawn material in the same frame when
-- they start and again when they end, so one material slot on one hands source mesh is enough to detect them.
local SKINFX_CHECK_MS = 200
local handsMaterialWatch = {}

local function checkHandsSkinFX()
	local currentPawn = uevrUtils.getValid(pawn)
	local pawnAddress = currentPawn ~= nil and currentPawn:get_address() or nil
	local source = uevrUtils.getValid(handsMaterialWatch.source)
	-- A mesh of an earlier pawn can stay valid but never change, so pick the watch again for a new pawn
	if source == nil or handsMaterialWatch.pawn ~= pawnAddress then
		-- New hands copy the current materials when they are created, so the first material seen is the baseline
		local hand = getHandsMaterialSources()[1]
		local material = hand ~= nil and hand.source:GetMaterial(0) or nil
		handsMaterialWatch = {source = hand ~= nil and hand.source or nil, material = material and material:get_address() or 0, pawn = pawnAddress}
		return
	end
	local material = source:GetMaterial(0)
	local address = material and material:get_address() or 0
	if address ~= handsMaterialWatch.material then
		handsMaterialWatch.material = address
		setHandsMaterials()
	end
end
checkHandsSkinFX = uevrUtils.profiler:wrap("Hands: check SkinFX", checkHandsSkinFX)
setInterval(SKINFX_CHECK_MS, checkHandsSkinFX)

uevrUtils.registerPreLevelChangeCallback(function(level)
	handsMaterialWatch = {}
end)

return M