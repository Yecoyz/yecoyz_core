-- One set of client events for every framework (listen with Core.OnPlayerLoaded / OnPlayerUnloaded / OnJobUpdated):
--   yecoyz_core:client:playerLoaded
--   yecoyz_core:client:playerUnloaded
--   yecoyz_core:client:jobUpdated (job)  in the Core.NormalizeJob shape
local function playerLoaded()
    if Core.Loaded then return end
    Core.Loaded = true
    TriggerEvent('yecoyz_core:client:playerLoaded')
end

local function playerUnloaded()
    if not Core.Loaded then return end
    Core.Loaded = false
    TriggerEvent('yecoyz_core:client:playerUnloaded')
end

local function jobUpdated(job)
    local normalized = Core.NormalizeJob(job)
    if normalized then TriggerEvent('yecoyz_core:client:jobUpdated', normalized) end
end

if Core.Framework == 'esx' then
    RegisterNetEvent('esx:playerLoaded', playerLoaded)
    RegisterNetEvent('esx:onPlayerLogout', playerUnloaded)
    RegisterNetEvent('esx:setJob', jobUpdated)
elseif Core.Framework == 'qb' or Core.Framework == 'qbox' then
    RegisterNetEvent('QBCore:Client:OnPlayerLoaded', playerLoaded)
    RegisterNetEvent('QBCore:Client:OnPlayerUnload', playerUnloaded)
    RegisterNetEvent('QBCore:Client:OnJobUpdate', jobUpdated)
else
    AddEventHandler('playerSpawned', playerLoaded)
end

-- Already loaded when the core (re)starts.
CreateThread(function()
    if Core.Client.IsPlayerLoaded() then Core.Loaded = true end
end)
