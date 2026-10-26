-- Frame profiling: wraps every per-frame callback registered after this module loads, including uevr_utils' own
-- dispatchers and setInterval timers, so the profiler report covers all Lua frame time.
-- Require it before any other module, as the first line of main.lua. Without the require nothing here is installed.
-- Timings are recorded only while uevrUtils.profiler is enabled.
-- Labels are "Frame: <hook> <module> #<n>", where module is the one being required when the callback was
-- registered ("main" otherwise) and n counts that module's callbacks for the hook in registration order.
-- UEVR's Lua state has no debug library, so source lines are not available.
-- Timings nest, so a dispatcher includes the callbacks it runs.
-- "Frame: all SDK callbacks" sums the top-level SDK callbacks.

local frameProfiler = nil -- uevrUtils.profiler once uevr_utils has loaded
local profiledCallbacks = {}
local callbackCounts = {}
local loadingModules = {}

local requireUnprofiled = require
require = function(name)
	loadingModules[#loadingModules + 1] = name
	local result = requireUnprofiled(name)
	loadingModules[#loadingModules] = nil
	return result
end

-- Returns the wrapper already made for func, or func itself.
local function profiledCallbackFor(hook, func)
	local byFunc = profiledCallbacks[hook]
	return byFunc ~= nil and byFunc[func] or func
end

local function profileCallback(hook, func, isSdkCallback)
	if type(func) ~= "function" then return func end
	-- The same wrapper is returned for a function so duplicate registration and unregistration still match.
	local byFunc = profiledCallbacks[hook]
	if byFunc == nil then
		byFunc = setmetatable({}, {__mode = "k"})
		profiledCallbacks[hook] = byFunc
	end
	if byFunc[func] ~= nil then return byFunc[func] end
	local source = loadingModules[#loadingModules] or "main"
	local countKey = hook .. " " .. source
	callbackCounts[countKey] = (callbackCounts[countKey] or 0) + 1
	local label = "Frame: " .. countKey .. " #" .. callbackCounts[countKey]
	local timed = nil
	local wrapped = function(...)
		if timed == nil then
			if frameProfiler == nil then return func(...) end
			timed = frameProfiler:wrap(label, func)
			if isSdkCallback then
				timed = frameProfiler:wrap("Frame: all SDK callbacks", timed)
			end
		end
		return timed(...)
	end
	byFunc[func] = wrapped
	return wrapped
end

-- Returns a table that serves overrides and forwards every other lookup to real (a table or userdata).
local function proxyOf(real, overrides)
	return setmetatable(overrides, {__index = function(_, key) return real[key] end})
end

local function profiledSdkCallbacks(callbacks)
	local overrides = {}
	for _, hook in ipairs({"on_pre_engine_tick", "on_post_engine_tick", "on_xinput_get_state", "on_early_calculate_stereo_view_offset", "on_pre_calculate_stereo_view_offset", "on_post_calculate_stereo_view_offset"}) do
		local register = callbacks[hook]
		if register ~= nil then
			overrides[hook] = function(func) return register(profileCallback(hook, func, true)) end
		end
	end
	return proxyOf(callbacks, overrides)
end

-- The SDK callback objects are userdata whose fields cannot be replaced, so scripts get proxies
-- for uevr, uevr.sdk and uevr.params.sdk instead. uevr_utils keeps the proxy it receives here.
local realUevr = uevr
local sdk = proxyOf(realUevr.sdk, {callbacks = profiledSdkCallbacks(realUevr.sdk.callbacks)})
local paramsSdk = proxyOf(realUevr.params.sdk, {callbacks = profiledSdkCallbacks(realUevr.params.sdk.callbacks)})
uevr = proxyOf(realUevr, {sdk = sdk, params = proxyOf(realUevr.params, {sdk = paramsSdk})})

local uevrUtils = require('libs/uevr_utils')
frameProfiler = uevrUtils.profiler

local frameHooks = {
	registerOnInputGetStateCallback = "onInputGetState",
	registerOnPreInputGetStateCallback = "onPreInputGetState",
	registerOnPostInputGetStateCallback = "onPostInputGetState",
	registerPreEngineTickCallback = "preEngineTick",
	registerPostEngineTickCallback = "postEngineTick",
	registerPreCalculateStereoViewCallback = "preCalculateStereoView",
	registerPostCalculateStereoViewCallback = "postCalculateStereoView",
}
local isFrameHook = {}
for registrar, hook in pairs(frameHooks) do
	isFrameHook[hook] = true
	local register = uevrUtils[registrar]
	uevrUtils[registrar] = function(func, priority) return register(profileCallback(hook, func), priority) end
end
local registerUEVRCallback = uevrUtils.registerUEVRCallback
local unregisterUEVRCallback = uevrUtils.unregisterUEVRCallback
uevrUtils.registerUEVRCallback = function(hook, func, priority)
	if isFrameHook[hook] then func = profileCallback(hook, func) end
	return registerUEVRCallback(hook, func, priority)
end
uevrUtils.unregisterUEVRCallback = function(hook, func)
	if isFrameHook[hook] then func = profiledCallbackFor(hook, func) end
	return unregisterUEVRCallback(hook, func)
end
-- uevrUtils.setInterval calls the global, so this covers both.
local setIntervalUnprofiled = setInterval
setInterval = function(msec, func)
	return setIntervalUnprofiled(msec, profileCallback("timer " .. msec .. "ms", func))
end

-- uevr_utils calls these globals from its own dispatchers (scope.lua defines on_post_engine_tick).
-- They are defined while main.lua loads its modules, so wrap them on the first tick, once loading has finished.
setTimeout(0, function()
	on_xinput_get_state = profileCallback("global on_xinput_get_state", on_xinput_get_state)
	on_pre_calculate_stereo_view_offset = profileCallback("global on_pre_calculate_stereo_view_offset", on_pre_calculate_stereo_view_offset)
	on_post_calculate_stereo_view_offset = profileCallback("global on_post_calculate_stereo_view_offset", on_post_calculate_stereo_view_offset)
	on_pre_engine_tick = profileCallback("global on_pre_engine_tick", on_pre_engine_tick)
	on_post_engine_tick = profileCallback("global on_post_engine_tick", on_post_engine_tick)
end)

return {}