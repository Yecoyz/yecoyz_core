-- Loads the core's real server and client files against mocked ESX, QBCore, Qbox and standalone servers and checks
-- every export returns the same shapes. Run: node tests/run.cjs
local files = ...

local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then passed = passed + 1; print('ok   ' .. name)
    else failed = failed + 1; print('FAIL ' .. name .. ': ' .. tostring(err)) end
end
local function eq(a, b, what) if a ~= b then error(('%s: expected %s, got %s'):format(what or 'value', tostring(b), tostring(a)), 2) end end

---------------------------------------------------------------------------------------------------------------------
-- Mock players: source 1 is a police officer (grade 2, boss, on duty) with $100 cash / $500 bank and 3 bread.
---------------------------------------------------------------------------------------------------------------------
local function esxMock(log)
    local function xPlayer()
        local self = {
            source = 1, identifier = 'char1:abc', job = { name = 'police', label = 'Police', grade = 2, grade_name = 'boss', grade_label = 'Chief', grade_salary = 300, onDuty = true },
            variables = { firstName = 'John', lastName = 'Doe', sex = 'f', dateofbirth = '2000-01-01' },
            accounts = { money = 100, bank = 500 }, items = { bread = 3 },
        }
        function self.get(k) return self.variables[k] end
        function self.getJob() return self.job end
        function self.setJob(name, grade, onDuty) log[#log + 1] = ('setJob %s %s %s'):format(name, grade, tostring(onDuty)); self.job.onDuty = onDuty end
        function self.getAccount(a) return self.accounts[a] and { name = a, money = self.accounts[a] } end
        function self.addAccountMoney(a, m) self.accounts[a] = self.accounts[a] + m end
        function self.removeAccountMoney(a, m) self.accounts[a] = self.accounts[a] - m end
        function self.getInventoryItem(i) return { name = i, count = self.items[i] or 0 } end
        function self.addInventoryItem(i, c) self.items[i] = (self.items[i] or 0) + c end
        function self.removeInventoryItem(i, c) self.items[i] = self.items[i] - c end
        function self.canCarryItem(_, c) return c <= 10 end
        function self.getGroup() return 'admin' end
        return self
    end
    local p = xPlayer()
    return {
        GetPlayerFromId = function(src) return src == 1 and p or nil end,
        GetPlayerFromIdentifier = function(id) return id == 'char1:abc' and p or nil end,
        GetExtendedPlayers = function() return { p } end,
        GetIdentifier = function() return 'abc', 1 end,
        GetJobs = function() return { police = { label = 'Police', grades = { ['2'] = { label = 'Chief' } } } } end,
        DoesJobExist = function(job) return job == 'police' end,
        RegisterUsableItem = function(item, cb) log[#log + 1] = 'usable ' .. item; cb(1, nil, { name = item }) end,
        IsPlayerLoaded = function() return true end,
        GetPlayerData = function() return { identifier = 'char1:abc', job = p.job, sex = 'f', firstName = 'John', lastName = 'Doe', accounts = { { name = 'money', money = 100 } }, inventory = { { name = 'bread', count = 3 } } } end,
        ShowNotification = function(msg, t) log[#log + 1] = ('esxnotify %s %s'):format(msg, t) end,
    }, p
end

local function qbPlayerMock(log)
    local p = {
        PlayerData = {
            source = 1, citizenid = 'ABC123', license = 'license:abc',
            charinfo = { firstname = 'John', lastname = 'Doe', gender = 1, phone = '555', birthdate = '2000-01-01' },
            job = { name = 'police', label = 'Police', payment = 300, onduty = true, isboss = true, grade = { name = 'Chief', level = 2 } },
            money = { cash = 100, bank = 500 }, items = { { name = 'bread', amount = 3 } },
        },
        Functions = {},
    }
    local F = p.Functions
    function F.SetJobDuty(d) log[#log + 1] = 'duty ' .. tostring(d); p.PlayerData.job.onduty = d end
    function F.SetJob(n, g) log[#log + 1] = ('setJob %s %s'):format(n, g); return true end
    function F.AddMoney(a, m) p.PlayerData.money[a] = p.PlayerData.money[a] + m; return true end
    function F.RemoveMoney(a, m) p.PlayerData.money[a] = p.PlayerData.money[a] - m; return true end
    function F.GetItemByName(i) return i == 'bread' and { name = 'bread', amount = 3 } or nil end
    function F.AddItem() return true end
    function F.RemoveItem() return true end
    return p
end

local function newEnv(framework, opts)
    opts = opts or {}
    local log, registered, events, clientEvents, handlers = {}, {}, {}, {}, {}
    local env = setmetatable({}, { __index = _G })
    env.print = function() end
    env.IsDuplicityVersion = function() return not opts.client end
    env.GetCurrentResourceName = function() return 'yecoyz_core' end
    local started = { es_extended = framework == 'esx', qbx_core = framework == 'qbox', ['qb-core'] = framework == 'qb' or framework == 'qbox',
        ox_inventory = opts.ox == true, ox_lib = opts.oxlib == true }
    env.GetResourceState = function(r) return started[r] and 'started' or 'missing' end
    env.CreateThread = function(fn) fn() end
    env.AddEventHandler = function(n, fn) handlers[n] = fn end
    env.RegisterNetEvent = function(n, fn) if fn then handlers[n] = fn end end
    env.TriggerEvent = function(n, ...) events[#events + 1] = { n, ... } end
    env.TriggerClientEvent = function(n, ...) clientEvents[#clientEvents + 1] = { n, ... } end
    env.GetPlayerName = function(src) return (tonumber(src) == 1 or tonumber(src) == 2) and ('Player' .. src) or nil end
    env.GetPlayers = function() return { '1', '2' } end
    env.GetPlayerIdentifierByType = function(src) return 'license:abc' .. (tonumber(src) == 1 and '' or src) end
    env.IsPlayerAceAllowed = function() return false end
    env.LocalPlayer = { state = { isLoggedIn = true } }
    env.NetworkIsPlayerActive = function() return true end
    env.PlayerId = function() return 0 end
    env.BeginTextCommandThefeedPost = function() log[#log + 1] = 'native' end
    env.AddTextComponentSubstringPlayerName = function() end
    env.EndTextCommandThefeedPostTicker = function() end

    local ESX, xPlayer = esxMock(log)
    local qbPlayer = qbPlayerMock(log)
    local QB = { Functions = {
        GetPlayer = function(src) return src == 1 and qbPlayer or nil end,
        GetPlayerByCitizenId = function(id) return id == 'ABC123' and qbPlayer or nil end,
        GetQBPlayers = function() return { [1] = qbPlayer } end,
        CreateUseableItem = function(item, cb) log[#log + 1] = 'usable ' .. item; cb(1, { name = item }) end,
        HasPermission = function() return true end,
        GetPlayerData = function() return qbPlayer.PlayerData end,
        Notify = function(msg, t) log[#log + 1] = ('qbnotify %s %s'):format(msg, t) end,
    }, Shared = { Jobs = { police = { label = 'Police', grades = { ['2'] = { name = 'Chief' } } } } },
        Player = { Login = function(src, cid) log[#log + 1] = 'login ' .. tostring(cid); return true end, Logout = function() log[#log + 1] = 'logout' end } }
    local qbx = {
        GetPlayer = function(_, src) return QB.Functions.GetPlayer(src) end,
        GetPlayerByCitizenId = function(_, id) return QB.Functions.GetPlayerByCitizenId(id) end,
        GetQBPlayers = function() return QB.Functions.GetQBPlayers() end,
        GetJobs = function() return QB.Shared.Jobs end,
        SetJobDuty = function(_, cid, d) log[#log + 1] = ('qbxduty %s %s'):format(cid, tostring(d)) end,
        SetJob = function(_, cid, n, g) log[#log + 1] = ('qbxjob %s %s %s'):format(cid, n, g); return true end,
        Login = function(_, src, cid) log[#log + 1] = 'qbxlogin ' .. tostring(cid); return true end,
        Logout = function() log[#log + 1] = 'qbxlogout' end,
        CreateUseableItem = function(_, item, cb) log[#log + 1] = 'usable ' .. item; cb(1, { name = item }) end,
        GetPlayerData = function() return qbPlayer.PlayerData end,
        Notify = function(_, msg, t) log[#log + 1] = ('qbxnotify %s %s'):format(msg, t) end,
    }
    local ox = {
        GetItemCount = function(_, a, b) local item = opts.client and a or b; return item == 'bread' and 3 or item == 'money' and 100 or 0 end,
        CanCarryItem = function(_, _, _, c) return c <= 10 end,
        AddItem = function() return true end,
        RemoveItem = function() return true end,
    }
    env.exports = setmetatable({
        es_extended = { getSharedObject = function() return ESX end },
        ['qb-core'] = { GetCoreObject = function() return QB end },
        qbx_core = qbx,
        ox_inventory = ox,
        spawnmanager = { setAutoSpawn = function(_, v) log[#log + 1] = 'autospawn ' .. tostring(v) end },
    }, { __call = function(_, name, fn) registered[name] = fn end })

    local list = opts.client
        and { 'config.lua', 'shared/framework.lua', 'client/framework.lua', 'client/notify.lua', 'client/events.lua', 'client/exports.lua' }
        or { 'config.lua', 'shared/framework.lua', 'server/framework.lua', 'server/inventory.lua', 'server/events.lua', 'server/exports.lua' }
    for _, f in ipairs(list) do
        assert(load(files[f], '@' .. f, 't', env))()
    end
    if opts.notify then env.Config.Notify = opts.notify end
    return { api = registered, log = log, events = events, clientEvents = clientEvents, handlers = handlers, env = env, xPlayer = xPlayer, qbPlayer = qbPlayer }
end

local function last(t) return t[#t] end

for _, fw in ipairs({ 'esx', 'qb', 'qbox' }) do
    test(fw .. ' server: framework, identifiers, character', function()
        local e = newEnv(fw); local S = e.api
        eq(S.GetFramework(), fw, 'framework'); eq(S.GetInventory(), 'framework', 'inventory')
        eq(S.GetIdentifier(1), fw == 'esx' and 'char1:abc' or 'ABC123', 'identifier')
        eq(S.GetIdentifier(2), nil, 'not loaded')
        eq(S.GetAccountIdentifier(1), fw == 'esx' and 'abc' or 'license:abc', 'account')
        eq(S.GetSourceFromIdentifier(fw == 'esx' and 'char1:abc' or 'ABC123'), 1, 'source from identifier')
        eq(S.IsPlayerLoaded(1), true); eq(S.IsPlayerLoaded(2), false)
        eq(#S.GetPlayers(), 1, 'players'); eq(S.GetPlayers()[1], 1)
        local c = S.GetCharacter(1)
        eq(c.firstname, 'John'); eq(c.lastname, 'Doe'); eq(c.sex, 1, 'sex')
        eq(S.GetFullName(1), 'John Doe'); eq(S.GetFullName(2), 'Player2', 'fallback to the player name')
    end)

    test(fw .. ' server: jobs', function()
        local e = newEnv(fw); local S = e.api
        local job = S.GetJob(1)
        eq(job.name, 'police'); eq(job.label, 'Police'); eq(job.grade, 2); eq(job.gradeLabel, 'Chief')
        eq(job.onDuty, true, 'onDuty'); eq(job.isBoss, true, 'isBoss'); eq(job.salary, 300)
        eq(S.HasJob(1, 'police'), true); eq(S.HasJob(1, { 'ambulance', 'police' }), true)
        eq(S.HasJob(1, 'police', 3), false, 'min grade'); eq(S.HasJob(1, { police = 2 }), true, 'map form')
        eq(S.HasJob(2, 'police'), false, 'offline')
        local label, grade = S.GetJobLabel('police', 2); eq(label, 'Police'); eq(grade, 'Chief')
        eq(S.GetJobLabel('nope', 0), 'nope')
        eq(#S.GetPlayersByJob('police', true), 1); eq(#S.GetPlayersByJob('ambulance'), 0)
        eq(S.SetDuty(1, false), true)
        eq(last(e.log), fw == 'esx' and 'setJob police 2 false' or fw == 'qb' and 'duty false' or 'qbxduty ABC123 false', 'duty call')
        eq(S.SetJob(1, 'police', 1), true)
        eq(S.SetDuty(2, true), false, 'offline player')
    end)

    test(fw .. ' server: money and items', function()
        local e = newEnv(fw); local S = e.api
        eq(S.GetMoney(1), 100, 'cash'); eq(S.GetMoney(1, 'bank'), 500, 'bank')
        eq(S.RemoveMoney(1, 150, 'cash'), false, 'not enough'); eq(S.GetMoney(1), 100, 'untouched')
        eq(S.RemoveMoney(1, 40, 'cash'), true); eq(S.GetMoney(1), 60)
        eq(S.AddMoney(1, 15, 'bank'), true); eq(S.GetMoney(1, 'bank'), 515)
        eq(S.AddMoney(1, -5), false, 'negative'); eq(S.GetMoney(2), 0, 'offline')
        eq(S.GetItemCount(1, 'bread'), 3); eq(S.HasItem(1, 'bread', 3), true); eq(S.HasItem(1, 'bread', 4), false)
        eq(S.HasItem(1, { 'knife', 'bread' }), true, 'any of'); eq(S.HasItem(1, { 'knife' }), false)
        eq(S.RemoveItem(1, 'bread', 5), false, 'not enough'); eq(S.RemoveItem(1, 'bread', 1), true)
        eq(S.AddItem(1, 'bread', 2), true)
        local used
        eq(S.RegisterUsableItem('cards', function(src) used = src end), true); eq(used, 1, 'usable callback')
    end)

    test(fw .. ' server: notify, login, events', function()
        local e = newEnv(fw); local S = e.api
        S.Notify(1, 'hi', 'success')
        local n = last(e.clientEvents); eq(n[1], 'yecoyz_core:client:notify'); eq(n[2], 1); eq(n[3], 'hi'); eq(n[4], 'success')
        eq(S.Login(1, fw == 'esx' and 'char1' or 'ABC123'), true)
        S.Logout(1)
        if fw == 'esx' then
            eq(last(e.events)[1], 'esx:playerLogout')
            e.handlers['esx:setJob'](1, { name = 'ambulance', grade = 0, grade_name = 'recruit', label = 'EMS' }, nil)
        else
            eq(last(e.log), fw == 'qb' and 'logout' or 'qbxlogout')
            e.handlers['QBCore:Server:OnJobUpdate'](1, { name = 'ambulance', grade = { level = 0, name = 'Recruit' }, label = 'EMS' })
        end
        local ev = last(e.events)
        eq(ev[1], 'yecoyz_core:server:jobUpdated'); eq(ev[2], 1); eq(ev[3].name, 'ambulance'); eq(ev[3].onDuty, false)
        -- loaded / unloaded: once each
        e.handlers['playerDropped'] = e.handlers['playerDropped']
        local before = #e.events
        e.env.source = 1; e.handlers['playerDropped']()
        eq(last(e.events)[1], 'yecoyz_core:server:playerUnloaded', 'unloaded on drop'); eq(#e.events, before + 1)
        e.handlers['playerDropped'](); eq(#e.events, before + 1, 'not twice')
    end)

    test(fw .. ' client: player data, job, sex, money, items, notify', function()
        local e = newEnv(fw, { client = true }); local C = e.api
        eq(C.IsPlayerLoaded(), true)
        eq(C.GetIdentifier(), fw == 'esx' and 'char1:abc' or 'ABC123')
        eq(C.GetJob().name, 'police'); eq(C.GetJob().gradeLabel, 'Chief'); eq(C.HasJob('police', 2), true)
        eq(C.GetSex(), 1); eq(C.GetFullName(), 'John Doe')
        eq(C.GetMoney('cash'), 100); eq(C.GetItemCount('bread'), 3); eq(C.HasItem('bread', 2), true)
        C.Notify('hey', 'inform')
        eq(last(e.log), fw == 'esx' and 'esxnotify hey info' or fw == 'qb' and 'qbnotify hey primary' or 'qbxnotify hey primary', 'framework notify')
        C.DisableSpawnManager()
    end)
end

test('ox_inventory is used for items when it runs', function()
    local e = newEnv('esx', { ox = true }); local S = e.api
    eq(S.GetInventory(), 'ox_inventory'); eq(S.GetItemCount(1, 'bread'), 3); eq(S.AddItem(1, 'bread', 20), false, 'cannot carry')
    local c = newEnv('esx', { ox = true, client = true }).api
    eq(c.GetItemCount('bread'), 3)
end)

test('standalone server: license identifier, cash from ox money, no jobs', function()
    local e = newEnv('standalone', { ox = true }); local S = e.api
    eq(S.GetFramework(), 'standalone'); eq(S.GetIdentifier(1), 'license:abc'); eq(S.IsPlayerLoaded(1), true)
    eq(S.GetJob(1), nil); eq(S.HasJob(1, 'police'), false); eq(#S.GetPlayers(), 2)
    eq(S.GetMoney(1), 100, 'ox money'); eq(S.RemoveMoney(1, 50), true)
    eq(S.RegisterUsableItem('x', function() end), false)
    eq(S.GetFullName(1), 'Player1')
end)

test('client notify picks ox_lib when it runs, the GTA feed without a framework', function()
    local e = newEnv('esx', { client = true, oxlib = true })
    e.api.Notify('hey', 'info', nil, 'Title')
    local ev = last(e.events); eq(ev[1], 'ox_lib:notify'); eq(ev[2].type, 'inform'); eq(ev[2].title, 'Title'); eq(ev[2].description, 'hey')
    local s = newEnv('standalone', { client = true })
    s.api.Notify('hey'); eq(last(s.log), 'native')
end)

print(('%d passed, %d failed'):format(passed, failed))
return failed
