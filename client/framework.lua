-- Client framework layer for the local player. Exported in client/exports.lua.
local fw = Core.Framework
local ESX, QB
if fw == 'esx' then
    ESX = exports.es_extended:getSharedObject()
elseif fw == 'qb' then
    QB = exports['qb-core']:GetCoreObject()
end
local qbx = fw == 'qbox' and exports.qbx_core or nil

local C = {}
Core.Client = C
Core.Loaded = false

function C.GetFramework() return fw end
function C.GetInventory() return Core.UsesOxInventory() and 'ox_inventory' or 'framework' end
function C.GetObject() return ESX or QB end

function C.IsPlayerLoaded()
    if Core.Loaded then return true end
    -- ESX.PlayerLoaded on the shared object is a copy that never updates, so ask es_extended.
    if ESX then return ESX.IsPlayerLoaded() == true end
    if qbx or QB then return LocalPlayer.state.isLoggedIn == true end
    return NetworkIsPlayerActive(PlayerId())
end

-- Stops spawnmanager from spawning the player on its own (multicharacter scripts spawn them).
function C.DisableSpawnManager()
    if Core.IsRunning('spawnmanager') then exports.spawnmanager:setAutoSpawn(false) end
end

-- The framework's raw player data.
function C.GetPlayerData()
    if ESX then return ESX.GetPlayerData() end
    if qbx then return qbx:GetPlayerData() end
    if QB then return QB.Functions.GetPlayerData() end
    return {}
end

function C.GetIdentifier()
    local data = C.GetPlayerData()
    if ESX then return data.identifier end
    return data.citizenid
end

function C.GetJob()
    return Core.NormalizeJob(C.GetPlayerData().job)
end

function C.HasJob(jobs, minGrade)
    local job = C.GetJob()
    if not job then return false end
    if type(jobs) == 'string' then jobs = { jobs } end
    for key, value in pairs(jobs) do
        local name, grade = value, minGrade
        if type(key) == 'string' then name, grade = key, value end
        if job.name == name and job.grade >= (tonumber(grade) or 0) then return true end
    end
    return false
end

-- { firstname, lastname, dob, sex (0 male / 1 female), phone, nationality }
function C.GetCharacter()
    local data = C.GetPlayerData()
    if ESX then
        local sex = data.sex
        return {
            firstname = data.firstName or '',
            lastname = data.lastName or '',
            dob = data.dateofbirth,
            sex = (sex == 'f' or sex == 1 or sex == '1') and 1 or 0,
            phone = data.phoneNumber or data.phone_number,
            height = data.height,
        }
    end
    local info = data.charinfo or {}
    return {
        firstname = info.firstname or '',
        lastname = info.lastname or '',
        dob = info.birthdate,
        sex = tonumber(info.gender) or 0,
        phone = info.phone,
        nationality = info.nationality,
    }
end

function C.GetName()
    local char = C.GetCharacter()
    return char.firstname, char.lastname
end

function C.GetFullName()
    local first, last = C.GetName()
    local name = ((first or '') .. ' ' .. (last or '')):gsub('^%s+', ''):gsub('%s+$', '')
    if name == '' then return GetPlayerName(PlayerId()) end
    return name
end

-- 0 male, 1 female
function C.GetSex()
    return C.GetCharacter().sex
end

function C.GetMoney(account)
    account = account or 'cash'
    local data = C.GetPlayerData()
    if ESX then
        local name = account == 'cash' and 'money' or account
        for _, acc in ipairs(data.accounts or {}) do
            if acc.name == name then return acc.money or 0 end
        end
        return 0
    end
    if fw == 'standalone' then
        if account == 'cash' and Core.UsesOxInventory() then return exports.ox_inventory:GetItemCount(Config.MoneyItem) or 0 end
        return 0
    end
    return data.money and data.money[account] or 0
end

function C.GetItemCount(item, metadata)
    if Core.UsesOxInventory() then return exports.ox_inventory:GetItemCount(item, metadata) or 0 end
    local data = C.GetPlayerData()
    local count = 0
    for _, entry in pairs(ESX and data.inventory or data.items or {}) do
        if entry.name == item then count = count + (entry.count or entry.amount or 0) end
    end
    return count
end

function C.HasItem(item, count, metadata)
    count = tonumber(count) or 1
    if type(item) == 'table' then
        for _, name in ipairs(item) do
            if C.GetItemCount(name, metadata) >= count then return true end
        end
        return false
    end
    return C.GetItemCount(item, metadata) >= count
end
