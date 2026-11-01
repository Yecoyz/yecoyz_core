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

-- Puts a vehicle in the player's garage. job (optional) marks it as a job vehicle where the table supports it.
function S.GiveVehicle(source, model, plate, job)
    local identifier = S.GetIdentifier(source)
    if not identifier or type(model) ~= 'string' or type(plate) ~= 'string' then return false end
    local hash = joaat(model)
    if ESX then
        local props = json.encode({ model = hash, plate = plate })
        if job and hasColumn('owned_vehicles', 'job') then
            return insert('INSERT INTO `owned_vehicles` (`owner`, `plate`, `vehicle`, `type`, `job`, `stored`) VALUES (?, ?, ?, ?, ?, 1)', {
                identifier, plate, props, 'car', job,
            }) ~= nil
        end
        return insert('INSERT INTO `owned_vehicles` (`owner`, `plate`, `vehicle`, `stored`) VALUES (?, ?, ?, 1)', { identifier, plate, props }) ~= nil
    end
    if QB or qbx then
        return insert('INSERT INTO `player_vehicles` (`license`, `citizenid`, `vehicle`, `hash`, `mods`, `plate`, `state`) VALUES (?, ?, ?, ?, ?, ?, 1)', {
            S.GetLicense(source), identifier, model, hash, '{}', plate,
        }) ~= nil
    end
    return false
end
