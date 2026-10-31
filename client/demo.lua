-- Config.Debug: /yecoyz_demo puts a three-option interaction, a notification and a controls card where you stand.
if not Config.Debug then return end

RegisterCommand('yecoyz_demo', function()
    local ped = PlayerPedId()
    local spot = GetOffsetFromEntityInWorldCoords(ped, 0.0, 2.0, 0.0)
    Core.Client.AddInteraction({
        id = 'yecoyz_core:demo',
        coords = spot,
        distance = 4.0,
        options = {
            { name = 'open', label = 'Open door', icon = 'door-open', onSelect = function() Core.Client.Notify('Door opened', 'success', 3000, 'Demo') end },
            { name = 'lock', label = 'Lock door', icon = 'lock', onSelect = function() Core.Client.Notify('Door locked', 'warning', 3000) end },
            { name = 'knock', label = 'Knock', icon = 'hand', onSelect = function() Core.Client.Notify('Nobody home', 'error', 3000) end },
        },
    })
    Core.Client.ShowControls({
        { keys = { 'E' }, label = 'Use' },
        { keys = { 'Scroll' }, label = 'Switch' },
    }, 'Demo')
    Core.Client.Notify('Walk to the marked spot in front of you.', 'info', 6000, 'yecoyz_core')
end, false)
