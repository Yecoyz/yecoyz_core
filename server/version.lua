-- Update notice: on start, asks yecoyz.com for the latest version of every running yecoyz_* resource and prints a
-- console message for the ones that are behind. Scripts need nothing extra, only a `version` in their fxmanifest.
--   Turn it off:            Config.VersionCheck = false
--   Skip a single resource: yecoyz_version_check 'no'   in that resource's fxmanifest
local API = GetConvar('yecoyz_version_url', 'https://yecoyz.com/api/version')
local CACHE_MS = 30 * 60 * 1000

local cache = {} -- resource -> { at = ms, data = table|false }
local notified = {} -- 'resource@version' -> true, so a restart doesn't print the same notice twice

local function parse(v)
    local a, b, c = tostring(v or ''):match('^v?(%d+)%.(%d+)%.(%d+)')
    if not a then return nil end
    return { tonumber(a), tonumber(b), tonumber(c) }
end

-- true when `latest` is newer than `current`
local function isNewer(latest, current)
    local l, c = parse(latest), parse(current)
    if not l or not c then return false end
    for i = 1, 3 do
        if l[i] ~= c[i] then return l[i] > c[i] end
    end
    return false
end

local function wanted(name)
    if name:sub(1, 7) ~= 'yecoyz_' or GetResourceState(name) ~= 'started' then return false end
    if (GetResourceMetadata(name, 'yecoyz_version_check', 0) or ''):lower() == 'no' then return false end
    return parse(GetResourceMetadata(name, 'version', 0)) ~= nil
end

local function report(name, latest)
    local current = GetResourceMetadata(name, 'version', 0)
    if not latest or not isNewer(latest.version, current) then return end
    local key = name .. '@' .. latest.version
    if notified[key] then return end
    notified[key] = true

    local lines = { ('^3[%s]^7 Update available: ^1%s^7 -> ^2%s^7'):format(name, current, latest.version) }
    if type(latest.notes) == 'string' and latest.notes ~= '' then lines[#lines + 1] = '  ' .. latest.notes end
    if type(latest.download) == 'string' then
        lines[#lines + 1] = '  Download: ^5' .. latest.download .. '^7'
    elseif type(latest.url) == 'string' then
        lines[#lines + 1] = '  More: ^5' .. latest.url .. '^7'
    end
    print(table.concat(lines, '\n'))
end

local function check(names)
    local now, ask = GetGameTimer(), {}
    for _, name in ipairs(names) do
        local c = cache[name]
        if c and now - c.at < CACHE_MS then
            report(name, c.data or nil)
        else
            ask[#ask + 1] = name
        end
    end
    if #ask == 0 then return end

    PerformHttpRequest(API .. '?resource=' .. table.concat(ask, ','), function(status, body)
        if status ~= 200 or not body then
            Core.Debug(('version check failed (HTTP %s)'):format(tostring(status)))
            return
        end
        local ok, data = pcall(json.decode, body)
        if not ok or type(data) ~= 'table' then return end
        local at = GetGameTimer()
        for _, name in ipairs(ask) do
            local latest = type(data[name]) == 'table' and data[name] or false
            cache[name] = { at = at, data = latest }
            report(name, latest or nil)
        end
    end, 'GET', '', { ['Accept'] = 'application/json' })
end

if Config.VersionCheck ~= false then
    local ready = false

    -- Give the other resources time to start, then check them in one request.
    CreateThread(function()
        Wait(5000)
        ready = true
        local names = {}
        for i = 0, GetNumResources() - 1 do
            local name = GetResourceByFindIndex(i)
            if name and wanted(name) then names[#names + 1] = name end
        end
        check(names)
    end)

    -- Resources (re)started later, e.g. after an update.
    AddEventHandler('onResourceStart', function(name)
        if not ready or name == GetCurrentResourceName() then return end
        SetTimeout(1000, function()
            if wanted(name) then check({ name }) end
        end)
    end)
end
