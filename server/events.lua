-- One set of server events for every framework (listen with Core.OnPlayerLoaded / OnPlayerUnloaded / OnJobUpdated):
--   yecoyz_core:server:playerLoaded   (source)
--   yecoyz_core:server:playerUnloaded (source)
--   yecoyz_core:server:jobUpdated     (source, job, lastJob)  jobs in the Core.NormalizeJob shape
local loaded = {}

local function playerLoaded(source)
    source = tonumber(source)
    if not source or loaded[source] then return end
    loaded[source] = true
    TriggerEvent('yecoyz_core:server:playerLoaded', source)
end

local function playerUnloaded(source)
    source = tonumber(source)
    if not source or not loaded[source] then return end
    loaded[source] = nil
    TriggerEvent('yecoyz_core:server:playerUnloaded', source)
end

local function jobUpdated(source, job, lastJob)
    source = tonumber(source)
    local normalized = Core.NormalizeJob(job)
    if not source or not normalized then return end
    TriggerEvent('yecoyz_core:server:jobUpdated', source, normalized, Core.NormalizeJob(lastJob))
end

if Core.Framework == 'esx' then
    AddEventHandler('esx:playerLoaded', function(source) playerLoaded(source) end)
    AddEventHandler('esx:playerLogout', function(source) playerUnloaded(source) end)
    AddEventHandler('esx:playerDropped', function(source) playerUnloaded(source) end)
    AddEventHandler('esx:setJob', function(source, job, lastJob) jobUpdated(source, job, lastJob) end)
elseif Core.Framework == 'qb' or Core.Framework == 'qbox' then
    AddEventHandler('QBCore:Server:PlayerLoaded', function(player)
        playerLoaded(player and player.PlayerData and player.PlayerData.source)
    end)
    AddEventHandler('QBCore:Server:OnPlayerUnload', function(source) playerUnloaded(source) end)
    AddEventHandler('QBCore:Server:OnJobUpdate', function(source, job) jobUpdated(source, job) end)
else
    AddEventHandler('playerJoining', function() playerLoaded(source) end)
end

AddEventHandler('playerDropped', function() playerUnloaded(source) end)

-- Players already loaded when the core (re)starts.
CreateThread(function()
    for _, id in ipairs(Core.Server.GetPlayers()) do loaded[id] = true end
end)
