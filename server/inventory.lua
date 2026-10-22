-- Server inventory layer: ox_inventory when it runs (Config.Inventory), otherwise the framework inventory.
local S = Core.Server
local fw = Core.Framework
local ox = function() return Core.UsesOxInventory() end

local function qbItem(player, item)
    local data = player.Functions.GetItemByName(item)
    return data and (data.amount or data.count) or 0
end

function S.GetItemCount(source, item, metadata)
    if ox() then return exports.ox_inventory:GetItemCount(source, item, metadata) or 0 end
    local player = S.GetPlayer(source)
    if not player then return 0 end
    if fw == 'esx' then
        local data = player.getInventoryItem(item)
        return data and data.count or 0
    end
    return qbItem(player, item)
end

function S.HasItem(source, item, count, metadata)
    count = tonumber(count) or 1
    if type(item) == 'table' then
        -- Any of the items.
        for _, name in ipairs(item) do
            if S.GetItemCount(source, name, metadata) >= count then return true end
        end
        return false
    end
    return S.GetItemCount(source, item, metadata) >= count
end

function S.CanCarryItem(source, item, count, metadata)
    count = tonumber(count) or 1
    if ox() then return exports.ox_inventory:CanCarryItem(source, item, count, metadata) == true end
    local player = S.GetPlayer(source)
    if not player then return false end
    if fw == 'esx' then return not player.canCarryItem or player.canCarryItem(item, count) end
    if Core.IsRunning('qb-inventory') then
        local ok, result = pcall(function() return exports['qb-inventory']:CanAddItem(source, item, count) end)
        if ok then return result ~= false end
    end
    return true
end

function S.AddItem(source, item, count, metadata)
    count = tonumber(count) or 1
    if ox() then
        if not exports.ox_inventory:CanCarryItem(source, item, count, metadata) then return false end
        return exports.ox_inventory:AddItem(source, item, count, metadata) == true
    end
    local player = S.GetPlayer(source)
    if not player then return false end
    if fw == 'esx' then
        if player.canCarryItem and not player.canCarryItem(item, count) then return false end
        player.addInventoryItem(item, count)
        return true
    end
    return player.Functions.AddItem(item, count, false, metadata) ~= false
end

-- Only removes when the player has enough.
function S.RemoveItem(source, item, count, metadata)
    count = tonumber(count) or 1
    if S.GetItemCount(source, item, metadata) < count then return false end
    if ox() then return exports.ox_inventory:RemoveItem(source, item, count, metadata) == true end
    local player = S.GetPlayer(source)
    if not player then return false end
    if fw == 'esx' then
        player.removeInventoryItem(item, count)
        return true
    end
    return player.Functions.RemoveItem(item, count) ~= false
end

-- Usable item through the framework: cb(source, item). With ox_inventory, items are made usable in its item
-- definitions (client export), but ox_inventory also runs ESX / QBCore usable items through its bridge.
function S.RegisterUsableItem(item, cb)
    if fw == 'esx' then
        local ESX = S.GetObject()
        ESX.RegisterUsableItem(item, function(source, _, data) cb(source, data) end)
        return true
    elseif fw == 'qbox' then
        exports.qbx_core:CreateUseableItem(item, function(source, data) cb(source, data) end)
        return true
    elseif fw == 'qb' then
        S.GetObject().Functions.CreateUseableItem(item, function(source, data) cb(source, data) end)
        return true
    end
    return false
end
