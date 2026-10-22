-- Notifications: Config.Notify picks ox_lib, the framework or the GTA feed.
-- type: 'info' | 'success' | 'error' | 'warning' ('inform' and 'primary' are read as 'info').
local C = Core.Client
local fw = Core.Framework

local aliases = { inform = 'info', primary = 'info', warn = 'warning' }
local oxTypes = { info = 'inform', success = 'success', error = 'error', warning = 'warning' }
local qbTypes = { info = 'primary', success = 'success', error = 'error', warning = 'warning' }

local function provider()
    local wanted = Config.Notify
    if wanted == 'auto' or not wanted then
        if Core.IsRunning('ox_lib') then return 'ox_lib' end
        if fw ~= 'standalone' then return 'framework' end
        return 'native'
    end
    return wanted
end

local function native(message)
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(message)
    EndTextCommandThefeedPostTicker(false, true)
end

function C.Notify(message, notifyType, duration, title)
    if message == nil then return end
    message = tostring(message)
    notifyType = aliases[notifyType] or notifyType or 'info'
    duration = tonumber(duration) or Config.NotifyDuration

    local use = provider()
    if use == 'ox_lib' then
        TriggerEvent('ox_lib:notify', {
            title = title or Config.NotifyTitle,
            description = message,
            type = oxTypes[notifyType] or 'inform',
            duration = duration,
        })
    elseif use == 'framework' and fw == 'esx' then
        C.GetObject().ShowNotification(message, notifyType, duration)
    elseif use == 'framework' and fw == 'qbox' then
        exports.qbx_core:Notify(message, qbTypes[notifyType] or 'primary', duration)
    elseif use == 'framework' and fw == 'qb' then
        C.GetObject().Functions.Notify(message, qbTypes[notifyType] or 'primary', duration)
    else
        native(message)
    end
end

RegisterNetEvent('yecoyz_core:client:notify', function(message, notifyType, duration, title)
    C.Notify(message, notifyType, duration, title)
end)
