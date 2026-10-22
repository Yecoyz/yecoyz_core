--[[
    yecoyz_core import. In a resource's fxmanifest.lua:

        shared_script '@yecoyz_core/import.lua'
        dependency 'yecoyz_core'

    Gives the resource a global `Core`:
        Core.Framework              'esx' | 'qbox' | 'qb' | 'standalone'
        Core.<Function>(...)        any yecoyz_core export, e.g. Core.GetIdentifier(source), Core.GetJob()
        Core.Callback.*             server <-> client callbacks (below)
        Core.OnPlayerLoaded(fn), Core.OnPlayerUnloaded(fn), Core.OnJobUpdated(fn)
]]

if Core and Core.Import then return end

local resource = GetCurrentResourceName()
local isServer = IsDuplicityVersion()
local context = isServer and 'server' or 'client'

if GetResourceState('yecoyz_core') ~= 'started' then
    error(("^1[%s] yecoyz_core is not started. Add `dependency 'yecoyz_core'` to the fxmanifest and ensure yecoyz_core first.^7"):format(resource), 0)
end

local core = exports.yecoyz_core

---------------------------------------------------------------------------------------------------------------------
-- Callbacks
--
-- Server:  Core.Callback.Register(name, function(source, ...) return ... end)
--          Core.Callback.Await(name, source, ...)            -> the client's return values (nil on timeout)
--          Core.Callback.Trigger(name, source, cb, ...)      -> cb(...) with the client's return values
-- Client:  Core.Callback.Register(name, function(...) return ... end)
--          Core.Callback.Await(name, ...)                    -> the server's return values (nil on timeout)
--          Core.Callback.Trigger(name, cb, ...)
--
-- Await must run in a thread (event handlers, commands, NUI callbacks and CreateThread are). Names are global across
-- resources, so prefix them with the resource name ('yecoyz_duty:getHistory').
---------------------------------------------------------------------------------------------------------------------
local Callback = {
    Timeout = 10000, -- ms before Await returns nil / Trigger calls back with nothing
}

local REQUEST = '__yecoyz_cb:'
local REPLY = '__yecoyz_cb_reply:'
local handlers, pending = {}, {}
local lastKey = 0

local function pack(...) return { n = select('#', ...), ... } end
local function unpack(t) if t then return table.unpack(t, 1, t.n or #t) end end

local function nextKey()
    lastKey = lastKey + 1
    if lastKey > 0x3FFFFFFF then lastKey = 1 end
    return lastKey
end

-- Runs a handler and returns its results packed; errors are printed and answered with no values.
local function run(name, handler, ...)
    local result = pack(pcall(handler, ...))
    if not result[1] then
        print(('^1[%s] callback "%s" failed: %s^7'):format(resource, name, tostring(result[2])))
        return { n = 0 }
    end
    local out = { n = result.n - 1 }
    for i = 2, result.n do out[i - 1] = result[i] end
    return out
end

local function validOrigin(origin, key)
    return type(origin) == 'string' and origin:find('^[%w_%-%.]+$') ~= nil and math.type(key) == 'integer'
end

function Callback.Register(name, handler)
    assert(type(name) == 'string', 'Callback.Register: name must be a string')
    assert(type(handler) == 'function' or (type(handler) == 'table' and getmetatable(handler) and getmetatable(handler).__call),
        'Callback.Register: handler must be a function')

    local exists = handlers[name] ~= nil
    handlers[name] = handler
    if exists then return end -- the event is already registered, it now calls the new handler

    if isServer then
        RegisterNetEvent(REQUEST .. name, function(origin, key, args)
            local src = source
            if not validOrigin(origin, key) then return end
            local fn = handlers[name]
            if not fn then return end
            args = type(args) == 'table' and args or { n = 0 }
            TriggerClientEvent(REPLY .. origin, src, key, run(name, fn, src, unpack(args)))
        end)
    else
        RegisterNetEvent(REQUEST .. name, function(origin, key, args)
            if not validOrigin(origin, key) then return end
            local fn = handlers[name]
            if not fn then return end
            args = type(args) == 'table' and args or { n = 0 }
            TriggerServerEvent(REPLY .. origin, key, run(name, fn, unpack(args)))
        end)
    end
end

function Callback.Unregister(name)
    handlers[name] = nil
end

function Callback.IsRegistered(name)
    return handlers[name] ~= nil
end

-- Replies to this resource's requests.
if isServer then
    RegisterNetEvent(REPLY .. resource, function(key, result)
        local src = tonumber(source)
        local entry = pending[key]
        -- Only the player that was asked may answer.
        if not entry or entry.target ~= src then return end
        pending[key] = nil
        entry.done(type(result) == 'table' and result or { n = 0 })
    end)

    AddEventHandler('playerDropped', function()
        local src = tonumber(source)
        for key, entry in pairs(pending) do
            if entry.target == src then
                pending[key] = nil
                entry.done(nil)
            end
        end
    end)
else
    RegisterNetEvent(REPLY .. resource, function(key, result)
        local entry = pending[key]
        if not entry then return end
        pending[key] = nil
        entry.done(type(result) == 'table' and result or { n = 0 })
    end)
end

-- done(result) gets the packed results, or nil when the callback timed out / the player left.
local function request(name, target, done, ...)
    assert(type(name) == 'string', 'Callback: name must be a string')
    if isServer then
        target = tonumber(target)
        if not target or not GetPlayerName(target) then return done(nil) end
    end

    local key = nextKey()
    local entry = { name = name, target = target, done = done }
    pending[key] = entry

    if isServer then
        TriggerClientEvent(REQUEST .. name, target, resource, key, pack(...))
    else
        TriggerServerEvent(REQUEST .. name, resource, key, pack(...))
    end

    local timeout = Callback.Timeout
    SetTimeout(timeout, function()
        if pending[key] ~= entry then return end
        pending[key] = nil
        print(('^3[%s] callback "%s" timed out after %d ms (is it registered on the %s?)^7'):format(
            resource, name, timeout, isServer and 'client' or 'server'))
        done(nil)
    end)
end

if isServer then
    function Callback.Await(name, source, ...)
        local p = promise.new()
        request(name, source, function(result) p:resolve(result or false) end, ...)
        local result = Citizen.Await(p)
        if result then return unpack(result) end
    end

    function Callback.Trigger(name, source, cb, ...)
        request(name, source, function(result)
            if cb then if result then cb(unpack(result)) else cb() end end
        end, ...)
    end
else
    function Callback.Await(name, ...)
        local p = promise.new()
        request(name, nil, function(result) p:resolve(result or false) end, ...)
        local result = Citizen.Await(p)
        if result then return unpack(result) end
    end

    function Callback.Trigger(name, cb, ...)
        request(name, nil, function(result)
            if cb then if result then cb(unpack(result)) else cb() end end
        end, ...)
    end
end

---------------------------------------------------------------------------------------------------------------------
-- Core
---------------------------------------------------------------------------------------------------------------------
local events = {
    PlayerLoaded = ('yecoyz_core:%s:playerLoaded'):format(context),
    PlayerUnloaded = ('yecoyz_core:%s:playerUnloaded'):format(context),
    JobUpdated = ('yecoyz_core:%s:jobUpdated'):format(context),
}

Core = setmetatable({
    Import = true,
    Resource = resource,
    Context = context,
    Framework = core:GetFramework(),
    Callback = Callback,
    Events = events,
}, {
    -- Core.Fn(...) calls exports.yecoyz_core:Fn(...). Looked up on every call, so it survives a core restart.
    __index = function(self, key)
        if type(key) ~= 'string' or not key:find('^%u') then return nil end
        local fn = function(...) return core[key](core, ...) end
        rawset(self, key, fn)
        return fn
    end,
})

-- Server: fn(source). Client: fn().
function Core.OnPlayerLoaded(fn) return AddEventHandler(events.PlayerLoaded, fn) end
function Core.OnPlayerUnloaded(fn) return AddEventHandler(events.PlayerUnloaded, fn) end
-- Server: fn(source, job, lastJob). Client: fn(job).
function Core.OnJobUpdated(fn) return AddEventHandler(events.JobUpdated, fn) end
