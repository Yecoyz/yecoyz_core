-- Controls card: shows the keys of a mode and what they do (bottom-right).
--   Core.ShowControls({ { keys = { 'E' }, label = 'Place' }, { keys = { 'Shift', 'Scroll' }, label = 'Rotate' } }, 'Editor')
--   Core.HideControls()
-- Each resource has its own card (the id defaults to the calling resource). The most recently shown one is on screen,
-- and hiding it brings back the one underneath. A resource's card is removed when it stops.
local C = Core.Client

local cards = {} -- ordered, the last one is shown

local function push()
    local top = cards[#cards]
    if top then
        Core.SendUI('controls:set', { title = top.title, rows = top.rows })
    else
        Core.SendUI('controls:hide')
    end
end

local function remove(id)
    for i = #cards, 1, -1 do
        if cards[i].id == id then table.remove(cards, i) end
    end
end

local function cleanRows(rows)
    local out = {}
    for _, row in ipairs(type(rows) == 'table' and rows or {}) do
        local keys = row.keys
        if type(keys) == 'string' then keys = { keys } end
        if type(keys) == 'table' and #keys > 0 and row.label ~= nil then
            local clean = {}
            for _, key in ipairs(keys) do clean[#clean + 1] = tostring(key) end
            out[#out + 1] = { keys = clean, label = tostring(row.label), dim = row.dim == true or nil }
        end
    end
    return out
end

-- rows: { { keys = { 'E' }, label = 'Use', dim = false }, ... }. Showing again replaces the resource's card.
function C.ShowControls(rows, title, id)
    id = id or GetInvokingResource() or Core.Name
    rows = cleanRows(rows)
    remove(id)
    if #rows > 0 then
        cards[#cards + 1] = { id = id, title = title and tostring(title) or nil, rows = rows }
    end
    push()
end

function C.HideControls(id)
    remove(id or GetInvokingResource() or Core.Name)
    push()
end

AddEventHandler('onResourceStop', function(resource)
    local before = #cards
    remove(resource)
    if #cards ~= before then push() end
end)
