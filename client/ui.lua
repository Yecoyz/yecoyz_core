-- Bridge to the NUI page (web/): notifications, the interaction menu and the controls card.
-- Messages sent before the page has loaded are queued and delivered when it reports ready.
local ready = false
local queue = {}
local MAX_QUEUE = 50

function Core.SendUI(action, data)
    local message = { action = action, data = data }
    if ready then
        SendNUIMessage(message)
        return
    end
    queue[#queue + 1] = message
    if #queue > MAX_QUEUE then table.remove(queue, 1) end
end

-- The page has loaded and receives messages (before that they are queued).
function Core.Client.IsUIReady() return ready end

RegisterNUICallback('ready', function(_, cb)
    ready = true
    local pending = queue
    queue = {}
    for _, message in ipairs(pending) do SendNUIMessage(message) end
    cb({ ok = true })
end)
