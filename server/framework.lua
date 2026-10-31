-- Server framework layer. Every function takes a player server id first (where it needs one) and works the same
-- on ESX, QBCore, Qbox and standalone. Exported in server/exports.lua.
local fw = Core.Framework
local ESX, QB
if fw == 'esx' then
    ESX = exports.es_extended:getSharedObject()
elseif fw == 'qb' then
    QB = exports['qb-core']:GetCoreObject()
end
local qbx = fw == 'qbox' and exports.qbx_core or nil

local S = {}
Core.Server = S

function S.GetFramework() return fw end
function S.GetInventory() return Core.UsesOxInventory() and 'ox_inventory' or 'framework' end

-- The framework's own object (ESX or QBCore). Qbox has none, use exports.qbx_core.
function S.GetObject() return ESX or QB end

---------------------------------------------------------------------------------------------------------------------
-- Players
---------------------------------------------------------------------------------------------------------------------
function S.GetPlayer(source)
    source = tonumber(source)
    if not source then return nil end
    if ESX then return ESX.GetPlayerFromId(source) end
    if qbx then return qbx:GetPlayer(source) end
    if QB then return QB.Functions.GetPlayer(source) end
    return nil
end

function S.GetPlayerFromIdentifier(identifier)
    if not identifier then return nil end
    if ESX then return ESX.GetPlayerFromIdentifier(identifier) end
    if qbx then return qbx:GetPlayerByCitizenId(identifier) end
    if QB then return QB.Functions.GetPlayerByCitizenId(identifier) end
    return nil
end

-- Server id of the player with this character identifier, if online.
function S.GetSourceFromIdentifier(identifier)
    local player = S.GetPlayerFromIdentifier(identifier)
    if not player then return nil end
    if ESX then return player.source end
    return player.PlayerData and player.PlayerData.source
end

-- Standalone has no "loaded" state, so anyone connected counts.
function S.IsPlayerLoaded(source)
    if fw == 'standalone' then return GetPlayerName(source) ~= nil end
    return S.GetPlayer(source) ~= nil
end

function S.GetLicense(source)
    return GetPlayerIdentifierByType(source, 'license')
end

-- The account the characters belong to, as the framework stores it: ESX's identifier without a character prefix
-- (the license without 'license:'), QBCore / Qbox and standalone 'license:...'. Works before a character is loaded.
function S.GetAccountIdentifier(source)
    if ESX then
        local identifier = ESX.GetIdentifier(source)
        return identifier
    end
    return S.GetLicense(source)
end

-- The character identifier: ESX identifier, QBCore / Qbox citizenid, standalone license.
function S.GetIdentifier(source)
    if fw == 'standalone' then return S.GetLicense(source) end
    local player = S.GetPlayer(source)
    if not player then return nil end
    if ESX then return player.identifier end
    return player.PlayerData.citizenid
end

-- Server ids of every player with a loaded character.
function S.GetPlayers()
    local list = {}
    if ESX then
        for _, xPlayer in pairs(ESX.GetExtendedPlayers()) do list[#list + 1] = xPlayer.source end
    elseif qbx or QB then
        local players = qbx and qbx:GetQBPlayers() or QB.Functions.GetQBPlayers()
        for source in pairs(players) do list[#list + 1] = tonumber(source) end
    else
        for _, id in ipairs(GetPlayers()) do list[#list + 1] = tonumber(id) end
    end
    return list
end

-- { firstname, lastname, dob, sex (0 male / 1 female), phone, nationality }
function S.GetCharacter(source)
    local player = S.GetPlayer(source)
    if not player then
        if fw == 'standalone' and GetPlayerName(source) then return { firstname = GetPlayerName(source), lastname = '', sex = 0 } end
        return nil
    end
    if ESX then
        local sex = player.get('sex')
        return {
            firstname = player.get('firstName') or '',
            lastname = player.get('lastName') or '',
            dob = player.get('dateofbirth'),
            sex = (sex == 'f' or sex == 1 or sex == '1') and 1 or 0,
            phone = player.get('phoneNumber') or player.get('phone_number'),
            height = player.get('height'),
        }
    end
    local info = player.PlayerData.charinfo or {}
    return {
        firstname = info.firstname or '',
        lastname = info.lastname or '',
        dob = info.birthdate,
        sex = tonumber(info.gender) or 0,
        phone = info.phone,
        nationality = info.nationality,
    }
end

function S.GetName(source)
    local char = S.GetCharacter(source)
    if not char then return nil, nil end
    return char.firstname, char.lastname
end

function S.GetFullName(source)
    local first, last = S.GetName(source)
    if not first then return GetPlayerName(source) end
    local name = (first .. ' ' .. (last or '')):gsub('%s+$', '')
    if name == '' then return GetPlayerName(source) end
    return name
end

---------------------------------------------------------------------------------------------------------------------
-- Jobs
---------------------------------------------------------------------------------------------------------------------
function S.GetJob(source)
    local player = S.GetPlayer(source)
    if not player then return nil end
    if ESX then return Core.NormalizeJob(player.getJob and player.getJob() or player.job) end
    return Core.NormalizeJob(player.PlayerData.job)
end

function S.HasJob(source, jobs, minGrade)
    local job = S.GetJob(source)
    if not job then return false end
    if type(jobs) == 'string' then jobs = { jobs } end
    for key, value in pairs(jobs) do
        -- { 'police', 'sheriff' } or { police = 2, sheriff = 0 } (job = minimum grade)
        local name, grade = value, minGrade
        if type(key) == 'string' then name, grade = key, value end
        if job.name == name and job.grade >= (tonumber(grade) or 0) then return true end
    end
    return false
end

function S.GetJobs()
    if ESX then return ESX.GetJobs() end
    if qbx then return qbx:GetJobs() end
    if QB then return QB.Shared.Jobs end
    return {}
end

-- Job label and grade label of a job name and grade number.
function S.GetJobLabel(job, grade)
    local data = S.GetJobs()[job]
    if not data then return job, '' end
    local grades = data.grades or {}
    local g = grades[tostring(grade or 0)] or grades[tonumber(grade) or 0]
    if not g then return data.label or job, '' end
    return data.label or job, (ESX and g.label or g.name) or ''
end

-- Server ids of the online players in a job (optionally only those on duty).
function S.GetPlayersByJob(jobName, onDutyOnly)
    local list = {}
    for _, source in ipairs(S.GetPlayers()) do
        local job = S.GetJob(source)
        if job and job.name == jobName and (not onDutyOnly or job.onDuty) then list[#list + 1] = source end
    end
    return list
end

function S.SetJob(source, jobName, grade)
    local player = S.GetPlayer(source)
    if not player then return false end
    grade = tonumber(grade) or 0
    if ESX then
        if not ESX.DoesJobExist(jobName, grade) then return false end
        player.setJob(jobName, grade)
        return true
    end
    if qbx then return qbx:SetJob(player.PlayerData.citizenid, jobName, grade) ~= false end
    return player.Functions.SetJob(jobName, grade) ~= false
end

function S.SetDuty(source, onDuty)
    local player = S.GetPlayer(source)
    if not player then return false end
    onDuty = onDuty == true
    if ESX then
        local job = player.getJob()
        player.setJob(job.name, job.grade, onDuty)
    elseif qbx then
        qbx:SetJobDuty(player.PlayerData.citizenid, onDuty)
    else
        player.Functions.SetJobDuty(onDuty)
    end
    return true
end

---------------------------------------------------------------------------------------------------------------------
-- Money. Accounts: 'cash', 'bank' (and any other framework account, e.g. 'black_money', 'crypto').
---------------------------------------------------------------------------------------------------------------------
local function esxAccount(account)
    if account == nil or account == 'cash' then return 'money' end
    return account
end

function S.GetMoney(source, account)
    account = account or 'cash'
    if fw == 'standalone' then
        if account == 'cash' and Core.UsesOxInventory() then return exports.ox_inventory:GetItemCount(source, Config.MoneyItem) or 0 end
        return 0
    end
    local player = S.GetPlayer(source)
    if not player then return 0 end
    if ESX then
        local acc = player.getAccount(esxAccount(account))
        return acc and acc.money or 0
    end
    return player.PlayerData.money and player.PlayerData.money[account] or 0
end

function S.AddMoney(source, amount, account, reason)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false end
    account = account or 'cash'
    if fw == 'standalone' then
        if account == 'cash' and Core.UsesOxInventory() then return exports.ox_inventory:AddItem(source, Config.MoneyItem, amount) == true end
        return false
    end
    local player = S.GetPlayer(source)
    if not player then return false end
    if ESX then
        player.addAccountMoney(esxAccount(account), amount, reason)
        return true
    end
    return player.Functions.AddMoney(account, amount, reason) ~= false
end

-- Only takes the money when the player has enough.
function S.RemoveMoney(source, amount, account, reason)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return true end
    account = account or 'cash'
    if S.GetMoney(source, account) < amount then return false end
    if fw == 'standalone' then
        return Core.UsesOxInventory() and exports.ox_inventory:RemoveItem(source, Config.MoneyItem, amount) == true
    end
    local player = S.GetPlayer(source)
    if not player then return false end
    if ESX then
        player.removeAccountMoney(esxAccount(account), amount, reason)
        return true
    end
    return player.Functions.RemoveMoney(account, amount, reason) ~= false
end

---------------------------------------------------------------------------------------------------------------------
-- Notifications, permissions, login
---------------------------------------------------------------------------------------------------------------------
-- type: 'info' | 'success' | 'error' | 'warning'. Shown with the client's notify (client/notify.lua).
function S.Notify(source, message, notifyType, duration, title, icon)
    TriggerClientEvent('yecoyz_core:client:notify', source, message, notifyType, duration, title, icon)
end

-- Ace permission, or a framework group (ESX group / QBCore permission) such as 'admin'.
function S.HasPermission(source, permission)
    if IsPlayerAceAllowed(source, permission) then return true end
    if ESX then
        local player = S.GetPlayer(source)
        return player ~= nil and player.getGroup() == permission
    end
    if QB then return QB.Functions.HasPermission(source, permission) == true end
    return false
end

-- Loads a character. ESX: identifier is the character prefix (e.g. 'char1'), data is passed to esx:onPlayerJoined.
-- QBCore / Qbox: identifier is the citizenid.
function S.Login(source, identifier, data)
    if ESX then
        TriggerEvent('esx:onPlayerJoined', source, identifier, data)
        return true
    end
    if qbx then return qbx:Login(source, identifier) == true end
    if QB then return QB.Player.Login(source, identifier) == true end
    return false
end

-- Saves and unloads the character; the framework then sends its logout event to the client.
function S.Logout(source)
    if ESX then
        TriggerEvent('esx:playerLogout', source)
    elseif qbx then
        qbx:Logout(source)
    elseif QB then
        QB.Player.Logout(source)
    end
end
