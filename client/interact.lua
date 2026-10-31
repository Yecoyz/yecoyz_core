-- Interactions: a target system without the target key. Walk up to a prop, a door handle or a spot and a menu appears
-- on it. Scroll to switch between its options and press the interact key (E) to use the selected one.
--
--   local id = Core.AddInteraction({
--       id = 'cityhall_door',              -- optional; adding the same id again replaces it
--       coords = vec3(0.0, 0.0, 70.0),     -- a spot ...
--       -- entity = ped, netId = 123,      -- ... one entity ...
--       -- models = { "prop_atm_01" },   -- ... every entity of these models ...
--       -- global = 'vehicle',             -- ... or every 'vehicle' | 'ped' | 'player' | 'object' (objects are heavy)
--       distance = 2.0,                    -- how close the player has to be to the spot (default Config.Interact.Distance)
--       bone = 'door_dside_f',             -- entities: pin the menu to a bone (a list picks the closest one)
--       offset = vec3(0.0, 0.0, 1.0),      -- entities: or to an offset from the entity
--       options = {
--           { name = 'open', label = 'Open door', icon = 'door-open',
--             onSelect = function(data) end,          -- data: { entity, netId, coords, distance, name, id }
--             -- event = 'x:open', serverEvent = 'x:open', command = 'open',   (alternatives to onSelect)
--             -- distance = 1.5, jobs = 'police', items = 'lockpick', inVehicle = true,
--             -- canInteract = function(entity, distance, coords, name) return true end,
--         },
--       },
--   })
--   Core.RemoveInteraction(id)
--   Core.SetInteractionsDisabled(true)   -- e.g. during a minigame
--
-- The options of one spot are shown together. When several spots are in range the closest one is shown. Icons are
-- lucide names ('door-open', 'lock', 'hand'). Registrations are removed when the resource that added them stops.
local C = Core.Client
local cfg = Config.Interact or {}

local regs = {}          -- id -> registration
local disabled = false
local nextId, nextUid = 0, 0
local current            -- the spot being shown
local shown              -- what the page has been sent: { key, sig, index, x, y }
local selectedUid        -- the selected option, kept across rescans
local nextScan, lastUse, targetSeq = 0, 0, 0

local POOLS = { vehicle = 'CVehicle', ped = 'CPed', object = 'CObject' }
-- Scroll up / down: the mouse wheel in every context the game has for it.
local SCROLL_UP = { 15, 17, 241 }
local SCROLL_DOWN = { 14, 16, 242 }
local SCROLL_BLOCK = { 14, 15, 16, 17, 81, 82, 99, 100, 241, 242, 261, 262 }

---------------------------------------------------------------------------------------------------------------------
-- Registrations
---------------------------------------------------------------------------------------------------------------------
local function modelHash(model)
    if type(model) == 'string' then return joaat(model) end
    return tonumber(model)
end

local function modelKind(hash)
    if IsModelAVehicle(hash) then return 'vehicle' end
    if IsModelAPed(hash) then return 'ped' end
    return 'object'
end

local function normalizeOptions(list)
    if type(list) ~= 'table' then return {} end
    if list.label then list = { list } end

    local out = {}
    for _, o in ipairs(list) do
        if o.label ~= nil then
            nextUid = nextUid + 1
            out[#out + 1] = {
                uid = nextUid,
                name = o.name or tostring(nextUid),
                label = tostring(o.label),
                icon = o.icon,
                onSelect = o.onSelect,
                event = o.event,
                serverEvent = o.serverEvent,
                command = o.command,
                distance = tonumber(o.distance),
                jobs = o.jobs,
                items = o.items,
                canInteract = o.canInteract,
                inVehicle = o.inVehicle == true,
            }
        end
    end
    return out
end

function C.AddInteraction(data)
    assert(type(data) == 'table', 'AddInteraction: data must be a table')
    local owner = GetInvokingResource() or Core.Name

    local reg = {
        owner = owner,
        distance = tonumber(data.distance) or cfg.Distance or 2.0,
        options = normalizeOptions(data.options),
        offset = data.offset,
    }
    assert(#reg.options > 0, 'AddInteraction: options needs at least one entry with a label')

    local bones = data.bone or data.bones
    if type(bones) == 'string' then bones = { bones } end
    reg.bones = type(bones) == 'table' and bones or nil

    if data.coords then
        reg.coords = vec3(data.coords.x, data.coords.y, data.coords.z)
    elseif data.entity then
        reg.entity = data.entity
    elseif data.netId then
        reg.netId = data.netId
    elseif data.models then
        reg.models = {}
        for _, model in ipairs(type(data.models) == 'table' and data.models or { data.models }) do
            local hash = modelHash(model)
            if hash then reg.models[hash] = modelKind(hash) end
        end
    elseif data.global then
        assert(data.global == 'player' or POOLS[data.global], "AddInteraction: global must be 'vehicle', 'ped', 'player' or 'object'")
        reg.global = data.global
    else
        error('AddInteraction: needs one of coords, entity, netId, models or global')
    end

    local id = data.id
    if not id then
        nextId = nextId + 1
        id = ('%s:%d'):format(owner, nextId)
    end
    regs[id] = reg
    return id
end

function C.RemoveInteraction(id)
    regs[id] = nil
end

function C.SetInteractionsDisabled(state)
    disabled = state == true
end

-- The menu on screen right now: nil, or { index, options = { { name, label }, ... } }.
function C.GetActiveInteraction()
    if not current or not shown then return nil end
    local options = {}
    for i, entry in ipairs(current.options) do
        options[i] = { name = entry.opt.name, label = entry.opt.label }
    end
    return { index = shown.index, options = options }
end

AddEventHandler('onResourceStop', function(resource)
    for id, reg in pairs(regs) do
        if reg.owner == resource then regs[id] = nil end
    end
end)

---------------------------------------------------------------------------------------------------------------------
-- Finding the spot to show
---------------------------------------------------------------------------------------------------------------------
local function playerState()
    local ped = PlayerPedId()
    if IsEntityDead(ped) or IsPauseMenuActive() or IsNuiFocused() or not IsPlayerControlOn(PlayerId()) then return nil end
    return ped
end

-- The position of the menu on an entity, and the bone it is pinned to. nil: the entity has none of the wanted bones.
local function entityAnchor(reg, entity, from)
    if reg.bones then
        local best, bestBone, bestDist
        for _, name in ipairs(reg.bones) do
            local bone = GetEntityBoneIndexByName(entity, name)
            if bone ~= -1 then
                local pos = GetWorldPositionOfEntityBone(entity, bone)
                local dist = #(pos - from)
                if not bestDist or dist < bestDist then best, bestBone, bestDist = pos, bone, dist end
            end
        end
        return best, bestBone
    end
    if reg.offset then
        return GetOffsetFromEntityInWorldCoords(entity, reg.offset.x, reg.offset.y, reg.offset.z)
    end
    return GetEntityCoords(entity)
end

local function optionAvailable(opt, entity, dist, coords, inVehicle)
    if opt.distance and dist > opt.distance then return false end
    if inVehicle and cfg.HideInVehicle ~= false and not opt.inVehicle then return false end
    if opt.jobs and not C.HasJob(opt.jobs) then return false end
    if opt.items and not C.HasItem(opt.items) then return false end
    if opt.canInteract then
        local ok, result = pcall(opt.canInteract, entity, dist, coords, opt.name)
        if not ok or not result then return false end
    end
    return true
end

local function scan(ped)
    local from = GetEntityCoords(ped)
    local inVehicle = IsPedInAnyVehicle(ped, false)
    local spots = {}
    local pools, pooled = {}, {}

    local function pool(kind, reg)
        pools[kind] = pools[kind] or {}
        pooled[kind] = pooled[kind] or {}
        if not pooled[kind][reg] then
            pooled[kind][reg] = true
            pools[kind][#pools[kind] + 1] = reg
        end
    end

    -- Adds the options of `reg` that apply to the spot, grouping registrations that share the same spot.
    local function offer(reg, entity, pos, bone)
        local dist = #(pos - from)
        if dist > reg.distance then return end

        local key = entity
            and ('e%d:%s:%s'):format(entity, bone or '', reg.offset and ('%.2f,%.2f,%.2f'):format(reg.offset.x, reg.offset.y, reg.offset.z) or '')
            or ('c%.2f,%.2f,%.2f'):format(pos.x, pos.y, pos.z)
        local spot = spots[key]
        for _, opt in ipairs(reg.options) do
            if optionAvailable(opt, entity, dist, pos, inVehicle) then
                if not spot then
                    spot = { key = key, entity = entity, bone = bone, offset = reg.offset, pos = pos, dist = dist, options = {} }
                    spots[key] = spot
                end
                spot.options[#spot.options + 1] = { opt = opt, reg = reg }
            end
        end
    end

    local function offerEntity(reg, entity)
        if not entity or entity == 0 or not DoesEntityExist(entity) then return end
        local pos, bone = entityAnchor(reg, entity, from)
        if pos then offer(reg, entity, pos, bone) end
    end

    for id, reg in pairs(regs) do
        if reg.coords then
            offer(reg, nil, reg.coords)
        elseif reg.entity then
            if DoesEntityExist(reg.entity) then offerEntity(reg, reg.entity) else regs[id] = nil end
        elseif reg.netId then
            if NetworkDoesNetworkIdExist(reg.netId) then offerEntity(reg, NetworkGetEntityFromNetworkId(reg.netId)) end
        elseif reg.global then
            pool(reg.global == 'player' and 'ped' or reg.global, reg)
        else
            for hash, kind in pairs(reg.models) do
                if kind == 'object' then
                    -- Cheap: the game finds the closest object of the model itself.
                    local entity = GetClosestObjectOfType(from.x, from.y, from.z, reg.distance + 4.0, hash, false, false, false)
                    offerEntity(reg, entity)
                else
                    pool(kind, reg)
                end
            end
        end
    end

    for kind, list in pairs(pools) do
        for _, entity in ipairs(GetGamePool(POOLS[kind])) do
            if entity ~= ped then
                local center = GetEntityCoords(entity)
                -- Cull by the entity's centre first; a bone can sit a few metres away from it (vehicles).
                if #(center - from) <= 12.0 then
                    local model = GetEntityModel(entity)
                    local isPlayer = kind == 'ped' and IsPedAPlayer(entity)
                    for _, reg in ipairs(list) do
                        local match
                        if reg.global == 'player' then match = isPlayer
                        elseif reg.global == 'ped' then match = not isPlayer
                        elseif reg.global then match = true
                        else match = reg.models[model] == kind end
                        if match then offerEntity(reg, entity) end
                    end
                end
            end
        end
    end

    -- The closest spot wins. The spot already shown is kept unless another one is clearly closer, so two spots at
    -- about the same distance do not flicker.
    local best
    for _, spot in pairs(spots) do
        table.sort(spot.options, function(a, b) return a.opt.uid < b.opt.uid end)
        if not best or spot.dist < best.dist then best = spot end
    end
    if current and spots[current.key] and best and best.key ~= current.key and spots[current.key].dist - best.dist < 0.35 then
        best = spots[current.key]
    end
    return best
end

---------------------------------------------------------------------------------------------------------------------
-- Showing it
---------------------------------------------------------------------------------------------------------------------
-- Config.Interact.UI = 'ox_lib' shows the selected option as ox_lib's text UI instead of the menu on the spot. It has
-- nothing to pin to the world, so it shows whenever a spot is in range.
local function oxLib()
    return cfg.UI == 'ox_lib' and Core.IsRunning('ox_lib')
end

local function hide()
    if shown then
        local ox = shown.ox
        shown = nil
        if ox then exports.ox_lib:hideTextUI() else Core.SendUI('interact:hide') end
    end
end

local function keyLabel()
    local label = GetControlInstructionalButton(0, cfg.Key or 38, true) or ''
    label = label:gsub('^t_', '')
    if label == '' or label:find('_') then return cfg.KeyLabel or 'E' end
    return label
end

local function selectedIndex()
    if current then
        for i, entry in ipairs(current.options) do
            if entry.opt.uid == selectedUid then return i end
        end
    end
    return 1
end

local function anchorPosition()
    local entity = current.entity
    if not entity then return current.pos end
    if not DoesEntityExist(entity) then return nil end
    if current.bone then return GetWorldPositionOfEntityBone(entity, current.bone) end
    if current.offset then return GetOffsetFromEntityInWorldCoords(entity, current.offset.x, current.offset.y, current.offset.z) end
    return GetEntityCoords(entity)
end

local function signature()
    local uids = {}
    for i, entry in ipairs(current.options) do uids[i] = entry.opt.uid end
    return table.concat(uids, ',')
end

local function use(entry)
    local opt, reg = entry.opt, entry.reg
    local entity = current.entity
    local data = {
        entity = entity,
        netId = entity and NetworkGetEntityIsNetworked(entity) and NetworkGetNetworkIdFromEntity(entity) or nil,
        coords = current.pos,
        distance = current.dist,
        name = opt.name,
    }
    for id, r in pairs(regs) do
        if r == reg then data.id = id break end
    end

    CreateThread(function()
        local ok, err = pcall(function()
            if opt.onSelect then opt.onSelect(data) end
            if opt.event then TriggerEvent(opt.event, data) end
            if opt.serverEvent then
                -- An entity handle means nothing to the server, it gets the netId.
                TriggerServerEvent(opt.serverEvent, { id = data.id, netId = data.netId, coords = data.coords, distance = data.distance, name = data.name })
            end
            if opt.command then ExecuteCommand(opt.command) end
        end)
        if not ok then
            print(('^1[%s] interaction "%s" (%s) failed: %s^7'):format(Core.Name, opt.name, reg.owner, tostring(err)))
        end
    end)
end

local function pressed(controls)
    for _, control in ipairs(controls) do
        if IsDisabledControlJustPressed(0, control) then return true end
    end
    return false
end

-- Runs every frame while a spot is in range.
local function frame()
    local pos = anchorPosition()
    if not pos then current = nil return end

    local ox = oxLib()
    local x, y
    if not ox then
        local onScreen
        onScreen, x, y = GetScreenCoordFromWorldCoord(pos.x, pos.y, pos.z)
        if not onScreen then hide() return end
    end

    local count = #current.options
    local index = selectedIndex()

    -- The keys are only taken from the game while the menu is on screen.
    DisableControlAction(0, cfg.Key or 38, true)
    if count > 1 then
        for _, control in ipairs(SCROLL_BLOCK) do DisableControlAction(0, control, true) end
        HudWeaponWheelIgnoreSelection()
        if pressed(SCROLL_UP) then index = index == 1 and count or index - 1
        elseif pressed(SCROLL_DOWN) then index = index == count and 1 or index + 1 end
        selectedUid = current.options[index].opt.uid
    end

    local sig = signature()
    if not shown or shown.ox ~= ox or shown.key ~= current.key or shown.sig ~= sig or shown.index ~= index then
        if shown and shown.ox ~= ox then hide() end
        if not shown or shown.key ~= current.key then targetSeq = targetSeq + 1 end
        if ox then
            local entry = current.options[index]
            local text = ('**[%s]** %s'):format(keyLabel(), entry.opt.label)
            -- Two spaces and a line break: a new line in markdown.
            if count > 1 then text = ('%s  \n%s %d / %d'):format(text, cfg.ScrollLabel or 'Scroll', index, count) end
            exports.ox_lib:showTextUI(text, { position = cfg.OxPosition or 'right-center', icon = entry.opt.icon })
            shown = { ox = true, key = current.key, sig = sig, index = index }
            goto pressedKey
        end
        local options = {}
        for i, entry in ipairs(current.options) do
            options[i] = { id = entry.opt.uid, label = entry.opt.label, icon = entry.opt.icon }
        end
        Core.SendUI('interact:show', {
            target = targetSeq,
            options = options,
            index = index,
            key = keyLabel(),
            scrollLabel = cfg.ScrollLabel,
            x = x,
            y = y,
        })
        shown = { ox = false, key = current.key, sig = sig, index = index, x = x, y = y }
    elseif not ox and math.abs(x - shown.x) + math.abs(y - shown.y) > 0.0008 then
        Core.SendUI('interact:move', { x = x, y = y })
        shown.x, shown.y = x, y
    end

    ::pressedKey::
    if IsDisabledControlJustPressed(0, cfg.Key or 38) then
        local now = GetGameTimer()
        if now - lastUse > 300 then
            lastUse = now
            use(current.options[index])
            nextScan = 0 -- options may have changed
        end
    end
end

CreateThread(function()
    if cfg.Enabled == false then return end
    local interval = cfg.ScanInterval or 200

    while true do
        local sleep = interval
        local ped = not disabled and next(regs) and playerState()
        if ped then
            local now = GetGameTimer()
            if now >= nextScan then
                nextScan = now + interval
                local spot = scan(ped)
                if spot ~= current then
                    -- Same spot as before: take the new data but keep the selection.
                    if not (current and spot and spot.key == current.key) then selectedUid = nil end
                    if not spot then hide() end
                end
                current = spot
            end
            if current then
                frame()
                sleep = current and 0 or interval
            end
        else
            current = nil
            hide()
        end
        Wait(sleep)
    end
end)
