-- Company layer: job grades, employees (online and offline), company (society) accounts and owned vehicles, the same
-- on ESX, QBCore and Qbox. Needs oxmysql for everything that reads the database. Exported in server/exports.lua.
local S = Core.Server
local fw = Core.Framework
local ESX = fw == 'esx' and S.GetObject() or nil
local QB = fw == 'qb' and S.GetObject() or nil
local qbx = fw == 'qbox' and exports.qbx_core or nil

---------------------------------------------------------------------------------------------------------------------
-- Database (oxmysql through its exports, so the core does not need it to start)
---------------------------------------------------------------------------------------------------------------------
local function db(method, query, params)
    if GetResourceState('oxmysql') ~= 'started' then return nil end
    local p = promise.new()
    local ox = exports.oxmysql
    ox[method](ox, query, params or {}, function(result) p:resolve(result) end)
    return Citizen.Await(p)
end
local function query(q, p) return db('query', q, p) or {} end
local function single(q, p) return db('single', q, p) end
local function scalar(q, p) return db('scalar', q, p) end
local function update(q, p) return tonumber(db('update', q, p)) or 0 end
local function insert(q, p) return db('insert', q, p) end

local function decode(value)
    if type(value) ~= 'string' or value == '' then return {} end
    local ok, result = pcall(json.decode, value)
    return ok and type(result) == 'table' and result or {}
end

local bossGrades = {}
for _, grade in ipairs(Config.BossGrades or {}) do bossGrades[grade] = true end

---------------------------------------------------------------------------------------------------------------------
-- Job grades. A grade: { grade, name, label, salary, isBoss }, sorted by grade.
---------------------------------------------------------------------------------------------------------------------
local function sortGrades(list)
    table.sort(list, function(a, b) return a.grade < b.grade end)
    return list
end

-- { name, label, grades = { ... } } or nil.
function S.GetJobData(jobName)
    if type(jobName) ~= 'string' then return nil end
    if ESX then
        local job = single('SELECT `name`, `label` FROM `jobs` WHERE `name` = ?', { jobName })
        if not job then return nil end
        local grades = {}
        for _, row in ipairs(query('SELECT `grade`, `name`, `label`, `salary` FROM `job_grades` WHERE `job_name` = ?', { jobName })) do
            grades[#grades + 1] = {
                grade = tonumber(row.grade), name = row.name, label = row.label, salary = tonumber(row.salary) or 0,
                isBoss = bossGrades[row.name] == true,
            }
        end
        return { name = job.name, label = job.label, grades = sortGrades(grades) }
    end

    local job = (qbx and qbx:GetJob(jobName)) or (QB and QB.Shared.Jobs[jobName])
    if not job then return nil end
    local grades = {}
    for key, g in pairs(job.grades or {}) do
        local grade = tonumber(key)
        if grade then
            grades[#grades + 1] = { grade = grade, name = g.name, label = g.name, salary = tonumber(g.payment) or 0, isBoss = g.isboss == true }
        end
    end
    return { name = jobName, label = job.label or jobName, grades = sortGrades(grades) }
end

-- Online players keep their old grade label and salary until their job is set again.
local function refreshJob(jobName)
    if ESX then ESX.RefreshJobs() end
    for _, src in ipairs(S.GetPlayersByJob(jobName)) do
        local job = S.GetJob(src)
        if job then S.SetJob(src, jobName, job.grade) end
    end
end

-- QBCore / Qbox keep jobs in a shared file: grade changes are applied at runtime and saved in
-- yecoyz_core_job_grades, which is applied again on every start.
local overrides = {}

local function qbApply(jobName, grade, data)
    local entry = data and { name = data.label, payment = data.salary, isboss = data.isBoss or nil } or nil
    if qbx then
        if entry then qbx:UpsertJobGrade(jobName, grade, entry) else qbx:RemoveJobGrade(jobName, grade) end
        return true
    end
    local job = QB.Shared.Jobs[jobName]
    if not job then return false end
    job.grades = job.grades or {}
    job.grades[tostring(grade)] = entry
    if QB.Functions.UpdateJob then
        QB.Functions.UpdateJob(jobName, job)
    else
        QB.Shared.Jobs[jobName] = job
        TriggerClientEvent('QBCore:Client:OnSharedUpdate', -1, 'Jobs', jobName, job)
    end
    return true
end

local function saveOverride(jobName, grade, data)
    overrides[jobName] = overrides[jobName] or {}
    overrides[jobName][tostring(grade)] = data or false
    db('query', 'INSERT INTO `yecoyz_core_job_grades` (`job`, `grades`) VALUES (?, ?) ON DUPLICATE KEY UPDATE `grades` = VALUES(`grades`)', {
        jobName, json.encode(overrides[jobName]),
    })
end

-- Creates or changes a grade. data = { name, label, salary }. Returns true on success.
function S.SaveJobGrade(jobName, grade, data)
    grade = tonumber(grade)
    if type(jobName) ~= 'string' or not grade or type(data) ~= 'table' then return false end
    local salary = math.max(0, math.floor(tonumber(data.salary) or 0))
    local label = tostring(data.label or data.name or grade)
    local name = tostring(data.name or label:lower():gsub('[^%w]+', '_'))
    if ESX then
        -- job_grades has no unique key on (job_name, grade), so update the row when there is one.
        if (tonumber(scalar('SELECT COUNT(*) FROM `job_grades` WHERE `job_name` = ? AND `grade` = ?', { jobName, grade })) or 0) > 0 then
            update('UPDATE `job_grades` SET `name` = ?, `label` = ?, `salary` = ? WHERE `job_name` = ? AND `grade` = ?', { name, label, salary, jobName, grade })
        else
            insert("INSERT INTO `job_grades` (`job_name`, `grade`, `name`, `label`, `salary`, `skin_male`, `skin_female`) VALUES (?, ?, ?, ?, ?, '{}', '{}')", {
                jobName, grade, name, label, salary,
            })
        end
    elseif QB or qbx then
        local job = S.GetJobData(jobName)
        if not job then return false end
        local isBoss = false
        for _, g in ipairs(job.grades) do if g.grade == grade then isBoss = g.isBoss end end
        local entry = { label = label, salary = salary, isBoss = isBoss }
        if not qbApply(jobName, grade, entry) then return false end
        saveOverride(jobName, grade, entry)
    else
        return false
    end
    refreshJob(jobName)
    return true
end

function S.DeleteJobGrade(jobName, grade)
    grade = tonumber(grade)
    if type(jobName) ~= 'string' or not grade then return false end
    if ESX then
        update('DELETE FROM `job_grades` WHERE `job_name` = ? AND `grade` = ?', { jobName, grade })
    elseif QB or qbx then
        if not qbApply(jobName, grade, nil) then return false end
        saveOverride(jobName, grade, nil)
    else
        return false
    end
    refreshJob(jobName)
    return true
end

-- Swaps the places of two grades (e.g. Officer 1 and Sergeant 2 become Sergeant 1 and Officer 2). Everyone with one
-- of them, online or offline, moves along so they keep their rank. Returns true on success.
function S.SwapJobGrades(jobName, a, b)
    a, b = tonumber(a), tonumber(b)
    if type(jobName) ~= 'string' or not a or not b or a == b then return false end
    local job = S.GetJobData(jobName)
    if not job then return false end
    local ga, gb
    for _, g in ipairs(job.grades) do
        if g.grade == a then ga = g elseif g.grade == b then gb = g end
    end
    if not ga or not gb then return false end

    -- Who has them now (online players by their live job, the rest from the database).
    local moves = {}
    for _, e in ipairs(S.GetJobEmployees(jobName)) do moves[e.identifier] = e.grade end
    for _, src in ipairs(S.GetPlayersByJob(jobName)) do
        local id, pjob = S.GetIdentifier(src), S.GetJob(src)
        if id and pjob then moves[id] = pjob.grade end
    end

    if ESX then
        -- job_grades may have no unique key, so move one grade out of the way first.
        update('UPDATE `job_grades` SET `grade` = -999 WHERE `job_name` = ? AND `grade` = ?', { jobName, a })
        update('UPDATE `job_grades` SET `grade` = ? WHERE `job_name` = ? AND `grade` = ?', { a, jobName, b })
        update('UPDATE `job_grades` SET `grade` = ? WHERE `job_name` = ? AND `grade` = -999', { b, jobName })
        ESX.RefreshJobs()
    elseif QB or qbx then
        local da = { label = ga.label, salary = ga.salary, isBoss = ga.isBoss }
        local db_ = { label = gb.label, salary = gb.salary, isBoss = gb.isBoss }
        if not qbApply(jobName, a, db_) or not qbApply(jobName, b, da) then return false end
        saveOverride(jobName, a, db_)
        saveOverride(jobName, b, da)
    else
        return false
    end

    for identifier, grade in pairs(moves) do
        if grade == a then S.SetJobByIdentifier(identifier, jobName, b)
        elseif grade == b then S.SetJobByIdentifier(identifier, jobName, a) end
    end
    refreshJob(jobName)
    return true
end

if (QB or qbx) and GetResourceState('oxmysql') == 'started' then
    CreateThread(function()
        db('query', [[
            CREATE TABLE IF NOT EXISTS `yecoyz_core_job_grades` (
                `job` varchar(64) NOT NULL,
                `grades` longtext NOT NULL,
                PRIMARY KEY (`job`)
            )
        ]])
        for _, row in ipairs(query('SELECT `job`, `grades` FROM `yecoyz_core_job_grades`')) do
            overrides[row.job] = decode(row.grades)
            for key, data in pairs(overrides[row.job]) do
                local ok, err = pcall(qbApply, row.job, tonumber(key), data or nil)
                if not ok then print(('^3[yecoyz_core] could not apply grade %s of %s: %s^7'):format(key, row.job, err)) end
            end
        end
    end)
end

---------------------------------------------------------------------------------------------------------------------
-- Employees
---------------------------------------------------------------------------------------------------------------------
local columns = {}
local function hasColumn(tableName, column)
    if not columns[tableName] then
        columns[tableName] = {}
        for _, row in ipairs(query('SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?', { tableName })) do
            columns[tableName][row.COLUMN_NAME] = true
        end
    end
    return columns[tableName][column] == true
end
local function hasUserColumn(column) return hasColumn('users', column) end

-- Every character with this job in the database, online or not:
-- { identifier, firstname, lastname, grade, phone, lastSeen (epoch seconds or nil) }
function S.GetJobEmployees(jobName)
    local list = {}
    if type(jobName) ~= 'string' then return list end
    if ESX then
        local phone = hasUserColumn('phone_number') and ', `phone_number`' or ''
        local seen = hasUserColumn('last_seen') and ', UNIX_TIMESTAMP(`last_seen`) AS `last_seen`' or ''
        for _, row in ipairs(query(('SELECT `identifier`, `firstname`, `lastname`, `job_grade`%s%s FROM `users` WHERE `job` = ?'):format(phone, seen), { jobName })) do
            list[#list + 1] = {
                identifier = row.identifier, firstname = row.firstname or '', lastname = row.lastname or '',
                grade = tonumber(row.job_grade) or 0, phone = row.phone_number, lastSeen = tonumber(row.last_seen),
            }
        end
    elseif QB or qbx then
        local rows = query([[
            SELECT `citizenid`, `charinfo`, `job`, UNIX_TIMESTAMP(`last_updated`) AS `last_seen` FROM `players`
            WHERE JSON_UNQUOTE(JSON_EXTRACT(`job`, '$.name')) = ?
        ]], { jobName })
        for _, row in ipairs(rows) do
            local info, job = decode(row.charinfo), decode(row.job)
            local grade = type(job.grade) == 'table' and job.grade.level or job.grade
            list[#list + 1] = {
                identifier = row.citizenid, firstname = info.firstname or '', lastname = info.lastname or '',
                grade = tonumber(grade) or 0, phone = info.phone, lastSeen = tonumber(row.last_seen),
            }
        end
    end
    return list
end

-- The job a fired player gets: name, grade.
function S.GetDefaultJob()
    return 'unemployed', 0
end

-- Sets the job of a character, online or offline. Returns true on success.
function S.SetJobByIdentifier(identifier, jobName, grade)
    grade = tonumber(grade) or 0
    local src = S.GetSourceFromIdentifier(identifier)
    if src then return S.SetJob(src, jobName, grade) end
    if ESX then
        return update('UPDATE `users` SET `job` = ?, `job_grade` = ? WHERE `identifier` = ?', { jobName, grade, identifier }) > 0
    end
    if qbx then return qbx:SetJob(identifier, jobName, grade) ~= false end
    if QB then
        local job = QB.Shared.Jobs[jobName]
        if not job then return false end
        local g = job.grades[tostring(grade)] or {}
        local data = {
            name = jobName, label = job.label, payment = g.payment or 0, onduty = false, type = job.type,
            isboss = g.isboss or false, grade = { name = g.name or 'None', level = grade },
        }
        return update('UPDATE `players` SET `job` = ? WHERE `citizenid` = ?', { json.encode(data), identifier }) > 0
    end
    return false
end

---------------------------------------------------------------------------------------------------------------------
-- Company (society) accounts. Config.Society.System picks the banking script.
---------------------------------------------------------------------------------------------------------------------
local societies = {}

societies['internal'] = {
    Get = function(job)
        return tonumber(scalar('SELECT `balance` FROM `yecoyz_core_society` WHERE `job` = ?', { job })) or 0
    end,
    Add = function(job, amount)
        db('query', 'INSERT INTO `yecoyz_core_society` (`job`, `balance`) VALUES (?, ?) ON DUPLICATE KEY UPDATE `balance` = `balance` + VALUES(`balance`)', { job, amount })
        return true
    end,
    Remove = function(job, amount)
        return update('UPDATE `yecoyz_core_society` SET `balance` = `balance` - ? WHERE `job` = ? AND `balance` >= ?', { amount, job, amount }) > 0
    end,
}

local function addonAccount(job)
    local p = promise.new()
    TriggerEvent('esx_addonaccount:getSharedAccount', (Config.Society.AccountPrefix or 'society_') .. job, function(account) p:resolve(account or false) end)
    SetTimeout(3000, function() if p.state == 0 then p:resolve(false) end end)
    return Citizen.Await(p) or nil
end

societies['esx_addonaccount'] = {
    Get = function(job)
        local account = addonAccount(job)
        return account and account.money or 0
    end,
    Add = function(job, amount)
        local account = addonAccount(job)
        if not account then
            -- A job without a society account gets one.
            local name = (Config.Society.AccountPrefix or 'society_') .. job
            db('query', 'INSERT IGNORE INTO `addon_account` (`name`, `label`, `shared`) VALUES (?, ?, 1)', { name, job })
            db('query', 'INSERT INTO `addon_account_data` (`account_name`, `money`) VALUES (?, 0)', { name })
            TriggerEvent('esx_addonaccount:refreshAccounts')
            Wait(500)
            account = addonAccount(job)
            if not account then return false end
        end
        account.addMoney(amount)
        return true
    end,
    Remove = function(job, amount)
        local account = addonAccount(job)
        if not account or account.money < amount then return false end
        account.removeMoney(amount)
        return true
    end,
}

societies['renewed-banking'] = {
    Get = function(job) return exports['Renewed-Banking']:getAccountMoney(job) or 0 end,
    Add = function(job, amount) return exports['Renewed-Banking']:addAccountMoney(job, amount) ~= false end,
    Remove = function(job, amount) return exports['Renewed-Banking']:removeAccountMoney(job, amount) ~= false end,
}

societies['qb-banking'] = {
    Get = function(job) return exports['qb-banking']:GetAccountBalance(job) or 0 end,
    Add = function(job, amount, reason) return exports['qb-banking']:AddMoney(job, amount, reason) ~= false end,
    Remove = function(job, amount, reason) return exports['qb-banking']:RemoveMoney(job, amount, reason) ~= false end,
}

societies['qb-management'] = {
    Get = function(job) return exports['qb-management']:GetAccount(job) or 0 end,
    Add = function(job, amount) return exports['qb-management']:AddMoney(job, amount) ~= false end,
    Remove = function(job, amount) return exports['qb-management']:RemoveMoney(job, amount) ~= false end,
}

local society
local function societyName()
    if society then return society end
    local wanted = Config.Society.System
    if wanted and wanted ~= 'auto' then
        society = societies[wanted] and wanted or 'internal'
    elseif ESX and Core.IsRunning('esx_addonaccount') then society = 'esx_addonaccount'
    elseif Core.IsRunning('Renewed-Banking') then society = 'renewed-banking'
    elseif Core.IsRunning('qb-banking') then society = 'qb-banking'
    elseif Core.IsRunning('qb-management') then society = 'qb-management'
    else society = 'internal' end
    if society == 'internal' then
        db('query', [[
            CREATE TABLE IF NOT EXISTS `yecoyz_core_society` (
                `job` varchar(64) NOT NULL,
                `balance` bigint(20) NOT NULL DEFAULT 0,
                PRIMARY KEY (`job`)
            )
        ]])
    end
    return society
end

-- The banking script used for company accounts: 'esx_addonaccount', 'renewed-banking', 'qb-banking', ...
function S.GetSocietySystem() return societyName() end

function S.GetSocietyMoney(job)
    if type(job) ~= 'string' then return 0 end
    local ok, result = pcall(societies[societyName()].Get, job)
    if not ok then print(('^1[yecoyz_core] society balance of %s failed: %s^7'):format(job, result)) return 0 end
    return math.floor(tonumber(result) or 0)
end

function S.AddSocietyMoney(job, amount, reason)
    amount = math.floor(tonumber(amount) or 0)
    if type(job) ~= 'string' or amount <= 0 then return false end
    local ok, result = pcall(societies[societyName()].Add, job, amount, reason)
    return ok and result == true
end

-- Only takes the money when the account has enough.
function S.RemoveSocietyMoney(job, amount, reason)
    amount = math.floor(tonumber(amount) or 0)
    if type(job) ~= 'string' or amount <= 0 then return false end
    local ok, result = pcall(societies[societyName()].Remove, job, amount, reason)
    return ok and result == true
end

---------------------------------------------------------------------------------------------------------------------
-- Owned vehicles
---------------------------------------------------------------------------------------------------------------------
function S.IsPlateTaken(plate)
    if ESX then return (tonumber(scalar('SELECT COUNT(*) FROM `owned_vehicles` WHERE `plate` = ?', { plate })) or 0) > 0 end
    if QB or qbx then return (tonumber(scalar('SELECT COUNT(*) FROM `player_vehicles` WHERE `plate` = ?', { plate })) or 0) > 0 end
    return false
end

-- A free plate of 8 characters: the prefix and digits, or 3 letters and digits without one.
function S.GeneratePlate(prefix)
    prefix = tostring(prefix or ''):upper():gsub('[^%w ]', ''):sub(1, 6)
    for _ = 1, 50 do
        local plate = prefix
        if prefix == '' then
            for _ = 1, 3 do plate = plate .. string.char(math.random(65, 90)) end
        end
        while #plate < 8 do plate = plate .. tostring(math.random(0, 9)) end
        if not S.IsPlateTaken(plate) then return plate end
    end
    return prefix .. tostring(math.random(10, 99))
end

---------------------------------------------------------------------------------------------------------------------
-- Garages. Config.Garage.System picks the garage script; vehicles are put straight in a garage so they show up there.
---------------------------------------------------------------------------------------------------------------------
local garageSystems = { 'jg-advancedgarages', 'zyke_garages', 'qbx_garages', 'qb-garages', 'esx_garage' }
local garageAlias = { esx_garages = 'esx_garage' }
local garageSystem

local function garageName()
    if garageSystem then return garageSystem end
    local wanted = Config.Garage and Config.Garage.System or 'auto'
    wanted = garageAlias[wanted] or wanted
    if wanted ~= 'auto' then
        garageSystem = wanted
    else
        garageSystem = 'default'
        for _, name in ipairs(garageSystems) do
            if Core.IsRunning(name) or (name == 'esx_garage' and Core.IsRunning('esx_garages')) then garageSystem = name break end
        end
    end
    return garageSystem
end

-- The garage script used by GiveVehicle: 'jg-advancedgarages', 'zyke_garages', ..., or 'default'.
function S.GetGarageSystem() return garageName() end

local defaultGarage = {
    ['qb-garages'] = 'motelgarage',
    ['qbx_garages'] = 'motelgarage',
    ['jg-advancedgarages'] = 'Legion Square',
}

local function esxGarageDefault()
    local res = Core.IsRunning('esx_garage') and 'esx_garage' or 'esx_garages'
    local ok, garages = pcall(function() return exports[res]:getGarages() end)
    if ok and type(garages) == 'table' then
        local names = {}
        for name in pairs(garages) do names[#names + 1] = name end
        table.sort(names)
        return names[1]
    end
end

-- The garage a new vehicle goes to: the one asked for, Config.Garage.Default, or the garage script's default.
local function pickGarage(system, garage)
    if type(garage) == 'string' and garage ~= '' then return garage end
    local configured = Config.Garage and Config.Garage.Default
    if type(configured) == 'string' and configured ~= '' then return configured end
    if system == 'esx_garage' then return esxGarageDefault() end
    return defaultGarage[system]
end

-- Inserts the row with the columns this server's table has. extra = { column = value } (skipped when missing).
local function insertVehicle(tableName, base, extra)
    local cols, values = {}, {}
    for col, value in pairs(base) do cols[#cols + 1] = col values[#values + 1] = value end
    for col, value in pairs(extra or {}) do
        if value ~= nil and hasColumn(tableName, col) then cols[#cols + 1] = col values[#values + 1] = value end
    end
    local marks = {}
    for i = 1, #cols do marks[i] = '?' cols[i] = '`' .. cols[i] .. '`' end
    return insert(('INSERT INTO `%s` (%s) VALUES (%s)'):format(tableName, table.concat(cols, ', '), table.concat(marks, ', ')), values) ~= nil
end

-- Puts a vehicle in the player's garage. job (optional) marks it as a job vehicle where the table supports it.
-- garage (optional) = garage name/id, otherwise Config.Garage.Default or the garage script's default.
-- Returns true, the garage id it went to and that garage's name (for messages).
function S.GiveVehicle(source, model, plate, job, garage)
    local identifier = S.GetIdentifier(source)
    if not identifier or type(model) ~= 'string' or type(plate) ~= 'string' then return false end
    local system = garageName()
    garage = pickGarage(system, garage)
    local hash = joaat(model)

    if system == 'zyke_garages' then
        local ok, success, result = pcall(function()
            return exports.zyke_garages:GiveVehicle(model, source, { plate = plate, garage = garage })
        end)
        if not ok or not success then
            print(('^1[yecoyz_core] zyke_garages GiveVehicle failed: %s^7'):format(ok and tostring(result) or tostring(success)))
            return false
        end
        local id = type(result) == 'table' and result.garage or garage
        local label = id and scalar('SELECT `label` FROM `zyke_garages` WHERE `id` = ?', { id })
        return true, id, label or id
    end

    if system == 'qbx_garages' and Core.IsRunning('qbx_vehicles') then
        local ok, id = pcall(function()
            return exports.qbx_vehicles:CreatePlayerVehicle({ model = model, citizenid = identifier, garage = garage, props = { plate = plate } })
        end)
        return ok and id ~= nil, garage, garage
    end

    local jg = system == 'jg-advancedgarages'
    if ESX then
        local base = { owner = identifier, plate = plate, vehicle = json.encode({ model = hash, plate = plate }), stored = 1 }
        local ok = insertVehicle('owned_vehicles', base, {
            type = 'car',
            job = job,
            parking = system == 'esx_garage' and garage or nil,
            garage_id = jg and garage or nil,
            in_garage = jg and 1 or nil,
        })
        return ok, garage, garage
    end
    if QB or qbx then
        local base = { license = S.GetLicense(source), citizenid = identifier, vehicle = model, hash = hash, mods = '{}', plate = plate, state = 1 }
        local ok = insertVehicle('player_vehicles', base, {
            garage = (not jg) and garage or nil,
            garage_id = jg and garage or nil,
            in_garage = jg and 1 or nil,
        })
        return ok, garage, garage
    end
    return false
end

-- Puts a vehicle in a job (work) garage instead of the buyer's own garage. How shared it is depends on the garage
-- script:
--   zyke_garages        owned by the job itself, in one of the job's garages (zyke picks it when garage is nil)
--   jg-advancedgarages  owned by the job (job vehicle, used from rank minGrade), in the job garage
--   qbx_garages         in the job garage (key = job name by default); everyone in the job sees it if that garage has
--                       shared = true, otherwise the buyer
--   qb-garages          in the job garage (key = job name by default), listed for the buyer
--   esx_garage / ESX    marked with the job (owned_vehicles.job) so job garages list it, owned by the buyer
-- garage = garage name/id (nil = Config.Garage.JobGarages[job], then the default above). Returns true, the garage id
-- and its name.
function S.GiveJobVehicle(source, job, model, plate, garage, minGrade)
    local identifier = S.GetIdentifier(source)
    if not identifier or type(job) ~= 'string' or type(model) ~= 'string' or type(plate) ~= 'string' then return false end
    local system = garageName()
    local jobGarages = Config.Garage and Config.Garage.JobGarages or {}
    if type(garage) ~= 'string' or garage == '' then garage = jobGarages[job] end
    if (type(garage) ~= 'string' or garage == '') and system ~= 'zyke_garages' and system ~= 'esx_garage' and system ~= 'default' then
        garage = job
    end
    minGrade = math.max(0, math.floor(tonumber(minGrade) or 0))
    local hash = joaat(model)

    if system == 'zyke_garages' then
        -- zyke only picks a job garage by itself for restricted jobs, so look for a garage made for this job.
        if not garage then
            for _, row in ipairs(query('SELECT `id`, `access` FROM `zyke_garages` WHERE `active` IS NULL OR `active` <> 0')) do
                local access = decode(row.access)
                if access.value == 'profession' then
                    for _, p in ipairs(access.professions or {}) do
                        if p.profession == job and (p.professionType or 'job') == 'job' then garage = row.id break end
                    end
                end
                if garage then break end
            end
        end
        local ok, success, result = pcall(function()
            return exports.zyke_garages:GiveVehicle(model, job, { plate = plate, garage = garage, professionType = 'job' })
        end)
        if not ok or not success then
            print(('^1[yecoyz_core] zyke_garages job vehicle for %s failed: %s (does the job have a garage in zyke_garages?)^7')
                :format(job, ok and tostring(result) or tostring(success)))
            return false
        end
        local id = type(result) == 'table' and result.garage or garage
        local label = id and scalar('SELECT `label` FROM `zyke_garages` WHERE `id` = ?', { id })
        return true, id, label or id
    end

    if system == 'qbx_garages' and Core.IsRunning('qbx_vehicles') then
        local ok, id = pcall(function()
            return exports.qbx_vehicles:CreatePlayerVehicle({ model = model, citizenid = identifier, garage = garage, props = { plate = plate } })
        end)
        return ok and id ~= nil, garage, garage
    end

    local jg = system == 'jg-advancedgarages'
    if ESX then
        local base = { owner = jg and job or identifier, plate = plate, vehicle = json.encode({ model = hash, plate = plate }), stored = 1 }
        local ok = insertVehicle('owned_vehicles', base, {
            type = 'car',
            job = job,
            parking = system == 'esx_garage' and garage or nil,
            garage_id = jg and garage or nil,
            in_garage = jg and 1 or nil,
            job_vehicle = jg and 1 or nil,
            job_vehicle_rank = jg and minGrade or nil,
        })
        return ok, garage, garage
    end
    if QB or qbx then
        local base = { license = S.GetLicense(source), citizenid = jg and job or identifier, vehicle = model, hash = hash, mods = '{}', plate = plate, state = 1 }
        local ok = insertVehicle('player_vehicles', base, {
            garage = (not jg) and garage or nil,
            garage_id = jg and garage or nil,
            in_garage = jg and 1 or nil,
            job_vehicle = jg and 1 or nil,
            job_vehicle_rank = jg and minGrade or nil,
        })
        return ok, garage, garage
    end
    return false
end

---------------------------------------------------------------------------------------------------------------------
-- Vehicle keys. Config.VehicleKeys picks the key script; 'auto' finds the first running one.
---------------------------------------------------------------------------------------------------------------------
local keySystems = { 'qbx_vehiclekeys', 'wasabi_carlock', 'Renewed-Vehiclekeys', 'qb-vehiclekeys' }

local function keySystem()
    local wanted = Config.VehicleKeys or 'auto'
    if wanted ~= 'auto' then return wanted end
    for _, name in ipairs(keySystems) do
        if Core.IsRunning(name) then return name end
    end
    return 'none'
end

-- The key script used by GiveVehicleKeys, or 'none'.
function S.GetVehicleKeySystem() return keySystem() end

-- Gives the player the keys of a spawned vehicle. netId = the vehicle's network id; plate (optional) defaults to the
-- vehicle's plate. Returns true when a key script took it.
function S.GiveVehicleKeys(source, netId, plate)
    source = tonumber(source)
    if not source or not GetPlayerName(source) or not tonumber(netId) then return false end
    local vehicle = NetworkGetEntityFromNetworkId(tonumber(netId))
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return false end
    plate = type(plate) == 'string' and plate or GetVehicleNumberPlateText(vehicle)
    plate = plate and plate:gsub('^%s+', ''):gsub('%s+$', '')

    local system = keySystem()
    local ok, result = pcall(function()
        if system == 'qbx_vehiclekeys' then
            -- false when the player has the keys already
            exports.qbx_vehiclekeys:GiveKeys(source, vehicle)
            return true
        elseif system == 'wasabi_carlock' then
            exports.wasabi_carlock:GiveKey(source, plate)
            return true
        elseif system == 'Renewed-Vehiclekeys' then
            exports['Renewed-Vehiclekeys']:addKey(source, plate)
            return true
        elseif system == 'qb-vehiclekeys' then
            TriggerClientEvent('vehiclekeys:client:SetOwner', source, plate)
            return true
        end
        return false
    end)
    if not ok then print(('^1[yecoyz_core] %s could not give keys: %s^7'):format(system, tostring(result))) end
    return ok and result == true
end
