-- Tests for the callback system in import.lua: a mocked FiveM runtime with a server and two clients, each with its
-- own globals, a simulated network (payloads are deep-copied like msgpack would) and virtual timers.
-- Run: node tests/run.cjs
local source_code = ...

local now, timers, queue, threads = 0, {}, {}, {}
local logs = {}

local function copy(v)
    if type(v) ~= 'table' then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = copy(x) end
    return t
end

local function spawn(fn, ...)
    local co = coroutine.create(fn)
    threads[#threads + 1] = { co = co, args = table.pack(...) }
end

local runtimes = {}

local function newRuntime(name, isServer, playerId)
    local env = setmetatable({}, { __index = _G })
    local net, localEvents = {}, {}
    env.IsDuplicityVersion = function() return isServer end
    env.GetCurrentResourceName = function() return 'test_res' end
    env.GetResourceState = function() return 'started' end
    env.GetPlayerName = function(id) return (id == 1 or id == 2) and ('Player' .. id) or nil end
    env.print = function(msg) logs[#logs + 1] = msg end
    env.SetTimeout = function(ms, fn) timers[#timers + 1] = { at = now + ms, fn = fn } end
    env.RegisterNetEvent = function(evt, fn) net[evt] = net[evt] or {}; table.insert(net[evt], fn) end
    env.AddEventHandler = function(evt, fn) localEvents[evt] = localEvents[evt] or {}; table.insert(localEvents[evt], fn) end
    env.promise = {
        new = function()
            local p = { done = false }
            function p:resolve(v) self.done = true; self.value = v end
            return p
        end
    }
    env.Citizen = {
        Await = function(p)
            while not p.done do coroutine.yield() end
            return p.value
        end
    }
    env.exports = {
        yecoyz_core = setmetatable({}, {
            __index = function(_, key)
                if key == 'GetFramework' then return function() return 'esx' end end
                if key == 'GetIdentifier' then return function(_, src) return 'char1:' .. tostring(src) end end
                return function() error('no export ' .. key) end
            end
        })
    }
    if isServer then
        env.TriggerClientEvent = function(evt, target, ...)
            queue[#queue + 1] = { to = runtimes['client' .. target], evt = evt, args = copy(table.pack(...)) }
        end
    else
        env.TriggerServerEvent = function(evt, ...)
            queue[#queue + 1] = { to = runtimes.server, evt = evt, args = copy(table.pack(...)), source = playerId }
        end
    end
    local rt = { name = name, env = env, net = net, localEvents = localEvents }
    local chunk = assert(load(source_code, '@import.lua', 't', env))
    chunk()
    return rt
end

local function deliver(msg)
    for _, fn in ipairs(msg.to.net[msg.evt] or {}) do
        spawn(function()
            msg.to.env.source = msg.source
            fn(table.unpack(msg.args, 1, msg.args.n))
        end)
    end
end

local function step()
    local progressed = false
    while #queue > 0 do deliver(table.remove(queue, 1)); progressed = true end
    local list = threads; threads = {}
    for _, t in ipairs(list) do
        local ok, err = coroutine.resume(t.co, table.unpack(t.args, 1, t.args.n))
        t.args = { n = 0 }
        if not ok then error(err) end
        if coroutine.status(t.co) == 'dead' then progressed = true else threads[#threads + 1] = t end
    end
    return progressed or #queue > 0
end

-- Runs until nothing moves; with `advance` it then fires timers in order until idle.
local function settle(advance)
    for _ = 1, 1000 do
        while step() do end
        if not advance or #timers == 0 then return end
        table.sort(timers, function(a, b) return a.at < b.at end)
        local t = table.remove(timers, 1)
        now = t.at
        t.fn()
    end
end

local function run(fn) spawn(fn); settle(false) end

local server = newRuntime('server', true)
local client1 = newRuntime('client1', false, 1)
local client2 = newRuntime('client2', false, 2)
runtimes.server, runtimes.client1, runtimes.client2 = server, client1, client2

local S, C1, C2 = server.env.Core, client1.env.Core, client2.env.Core
local passed, failed = 0, 0
local function test(name, fn)
    logs = {}
    local ok, err = pcall(fn)
    if ok then passed = passed + 1; print('ok   ' .. name)
    else failed = failed + 1; print('FAIL ' .. name .. ': ' .. tostring(err)) end
end
local function eq(a, b, what) if a ~= b then error(('%s: expected %s, got %s'):format(what or 'value', tostring(b), tostring(a)), 2) end end

test('Core basics', function()
    eq(S.Framework, 'esx', 'framework'); eq(S.Context, 'server', 'context'); eq(C1.Context, 'client', 'context')
    eq(S.GetIdentifier(5), 'char1:5', 'export proxy')
    eq(S.lowercase, nil, 'only exported (capitalised) names are proxied')
end)

test('client awaits a server callback with several values and a nil in the middle', function()
    S.Callback.Register('t:multi', function(src, a, b) return src, a + b, nil, { list = { 1, 2 } } end)
    local r
    run(function() r = table.pack(C1.Callback.Await('t:multi', 2, 3)) end)
    eq(r.n, 4, 'count'); eq(r[1], 1, 'source'); eq(r[2], 5, 'sum'); eq(r[3], nil, 'nil'); eq(r[4].list[2], 2, 'table')
end)

test('server awaits a client callback', function()
    C2.Callback.Register('t:client', function(x) return 'pong:' .. x end)
    local r
    run(function() r = S.Callback.Await('t:client', 2, 'ping') end)
    eq(r, 'pong:ping', 'reply')
end)

test('Trigger calls back asynchronously', function()
    S.Callback.Register('t:async', function(_, x) return x * 2 end)
    local r
    C1.Callback.Trigger('t:async', function(v) r = v end, 21)
    settle(false)
    eq(r, 42, 'reply')
end)

test('a handler can wait (yield) before returning', function()
    S.Callback.Register('t:slow', function(_, x)
        local p = server.env.promise.new()
        server.env.SetTimeout(500, function() p:resolve(x + 1) end)
        return server.env.Citizen.Await(p)
    end)
    local r
    spawn(function() r = C1.Callback.Await('t:slow', 1) end)
    settle(true)
    eq(r, 2, 'reply')
end)

test('concurrent requests resolve to the right caller', function()
    S.Callback.Register('t:echo', function(src, x) return src, x end)
    local a, b, c
    spawn(function() a = table.pack(C1.Callback.Await('t:echo', 'a')) end)
    spawn(function() b = table.pack(C2.Callback.Await('t:echo', 'b')) end)
    spawn(function() c = table.pack(C1.Callback.Await('t:echo', 'c')) end)
    settle(false)
    eq(a[1], 1); eq(a[2], 'a'); eq(b[1], 2); eq(b[2], 'b'); eq(c[2], 'c')
end)

test('an unregistered callback times out with nil and a warning', function()
    local r, finished = 'unset', false
    spawn(function() r = C1.Callback.Await('t:missing'); finished = true end)
    settle(false)
    eq(finished, false, 'still waiting before the timeout')
    settle(true)
    eq(finished, true, 'finished'); eq(r, nil, 'value')
    assert(tostring(logs[#logs]):find('timed out'), 'warning printed')
end)

test('a failing handler answers with no values and prints the error', function()
    S.Callback.Register('t:error', function() error('boom') end)
    local r, finished
    run(function() r = table.pack(C1.Callback.Await('t:error')); finished = true end)
    eq(finished, true, 'finished without waiting for the timeout'); eq(r.n, 0, 'no values')
    assert(tostring(logs[1]):find('boom'), 'error printed')
end)

test('a reply from another player is ignored', function()
    C1.Callback.Register('t:who', function() return 'real' end)
    -- Player 2 answers the request made to player 1 before player 1 does.
    local r
    spawn(function() r = S.Callback.Await('t:who', 1) end)
    step() -- the request is queued to client 1 and the server waits
    for key in pairs({ [1] = true, [2] = true, [3] = true, [100] = true }) do
        queue[#queue + 1] = { to = server, evt = '__yecoyz_cb_reply:test_res', args = { n = 2, key, { n = 1, 'spoofed' } }, source = 2 }
    end
    settle(false)
    eq(r, 'real', 'reply')
end)

test('server Await to an offline player returns nil at once', function()
    local r, finished
    run(function() r = S.Callback.Await('t:client', 99, 'x'); finished = true end)
    eq(finished, true); eq(r, nil)
end)

test('re-registering replaces the handler without a second event handler', function()
    S.Callback.Register('t:swap', function() return 1 end)
    S.Callback.Register('t:swap', function() return 2 end)
    eq(#server.net['__yecoyz_cb:t:swap'], 1, 'one net handler')
    local r
    run(function() r = C1.Callback.Await('t:swap') end)
    eq(r, 2, 'new handler')
end)

test('malformed requests are dropped', function()
    S.Callback.Register('t:safe', function() return 'x' end)
    queue[#queue + 1] = { to = server, evt = '__yecoyz_cb:t:safe', args = { n = 3, 'bad name!', 1, {} }, source = 1 }
    queue[#queue + 1] = { to = server, evt = '__yecoyz_cb:t:safe', args = { n = 3, 'test_res', 'notanumber', {} }, source = 1 }
    local before = #queue
    settle(false)
    eq(#queue, 0, 'no reply sent'); assert(before == 2)
end)

print(('%d passed, %d failed'):format(passed, failed))
return failed
