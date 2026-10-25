# yecoyz_core

The shared framework layer and callback system for the yecoyz resources. Each resource used to carry its own bridge;
now they all load this one, so ESX / QBCore / Qbox / standalone support lives in one place.

Used by `yecoyz_duty`, `yecoyz_minigames`, `yecoyz_radar`, `yecoyz_characters`, `yecoyz_appearance` and `yecoyz_jukebox`.

## Install

Start it after your framework (and ox_inventory / ox_lib if you use them) and before the resources that use it:

```cfg
ensure es_extended   # or qb-core / qbx_core
ensure ox_lib        # optional
ensure ox_inventory  # optional
ensure yecoyz_core
ensure yecoyz_duty
```

The resources declare `dependency 'yecoyz_core'`, so FiveM also starts it first on its own.

## Using it in a resource

```lua
-- fxmanifest.lua
shared_script '@yecoyz_core/import.lua'
dependency 'yecoyz_core'
```

That gives the resource a global `Core`:

```lua
Core.Framework                  -- 'esx' | 'qbox' | 'qb' | 'standalone'
Core.GetIdentifier(source)      -- any export below, called as Core.<Name>(...)
Core.Callback.Await(...)        -- callbacks
Core.OnPlayerLoaded(fn)         -- lifecycle events
```

Every function is also a plain export (`exports.yecoyz_core:GetIdentifier(source)`) for resources that don't load the import.

## Callbacks

Replaces `lib.callback`. Names are global across resources, so prefix them with the resource name.

```lua
-- server
Core.Callback.Register('yecoyz_duty:getHistory', function(source, filter)
    return MySQL.query.await('...'), os.time()   -- any number of values, nil included
end)

-- client
local history, now = Core.Callback.Await('yecoyz_duty:getHistory', 'week')
Core.Callback.Trigger('yecoyz_duty:getHistory', function(history, now) end, 'week')
```

The other direction works the same, with the player as the second argument:

```lua
-- client
Core.Callback.Register('yecoyz_radar:getPlate', function() return GetVehicleNumberPlateText(...) end)
-- server
local plate = Core.Callback.Await('yecoyz_radar:getPlate', source)
Core.Callback.Trigger('yecoyz_radar:getPlate', source, function(plate) end)
```

| | Server | Client |
|---|---|---|
| Register | `Register(name, fn(source, ...))` | `Register(name, fn(...))` |
| Await | `Await(name, source, ...)` | `Await(name, ...)` |
| Trigger | `Trigger(name, source, cb, ...)` | `Trigger(name, cb, ...)` |

- `Await` must run in a thread. Event handlers, commands, NUI callbacks and `CreateThread` all are.
- No answer within `Core.Callback.Timeout` ms (10000 by default, per resource) gives `nil` and a console warning, which usually means the callback isn't registered.
- A handler that errors prints the error and answers with no values right away, so the caller doesn't hang until the timeout.
- On the server, only the player who was asked can answer, and pending requests to a player who leaves end with `nil`.
- Registering a name again replaces the handler. `Unregister(name)` and `IsRegistered(name)` are there too.

## Server API

| Function | Returns |
|---|---|
| `GetFramework()` / `GetInventory()` | `'esx'`, `'qb'`, `'qbox'`, `'standalone'` / `'ox_inventory'`, `'framework'` |
| `GetObject()` | The ESX or QBCore object (nil on Qbox; use `exports.qbx_core`) |
| `GetPlayer(source)` | The framework's player object |
| `GetPlayerFromIdentifier(id)` / `GetSourceFromIdentifier(id)` | Player object / server id of an online character |
| `IsPlayerLoaded(source)` | A character is loaded |
| `GetIdentifier(source)` | Character id: ESX identifier, QBCore / Qbox citizenid, standalone license |
| `GetAccountIdentifier(source)` | The account the characters belong to (ESX license without prefix, QB `license:...`) |
| `GetLicense(source)` | `license:...` |
| `GetPlayers()` | Server ids of every loaded player |
| `GetCharacter(source)` | `{ firstname, lastname, dob, sex, phone, nationality }`, with `sex` 0 male / 1 female |
| `GetName(source)` / `GetFullName(source)` | `first, last` / `'First Last'` (falls back to the player name) |
| `GetJob(source)` | `{ name, label, grade, gradeName, gradeLabel, salary, onDuty, isBoss }` |
| `HasJob(source, jobs, minGrade)` | `jobs`: `'police'`, `{ 'police', 'sheriff' }` or `{ police = 2 }` (minimum grade) |
| `GetJobs()` / `GetJobLabel(job, grade)` | All jobs / `jobLabel, gradeLabel` |
| `GetPlayersByJob(job, onDutyOnly)` | Server ids |
| `SetJob(source, job, grade)` / `SetDuty(source, onDuty)` | `true` on success |
| `GetMoney(source, account)` | Accounts: `'cash'` (default), `'bank'`, or any framework account |
| `AddMoney(source, amount, account, reason)` | `true` on success |
| `RemoveMoney(source, amount, account, reason)` | `false` if the player doesn't have enough |
| `GetItemCount(source, item, metadata)` | ox_inventory, otherwise the framework inventory |
| `HasItem(source, item, count, metadata)` | `item` can be a list: true if they have any of them |
| `CanCarryItem` / `AddItem` / `RemoveItem` `(source, item, count, metadata)` | `RemoveItem` only removes when the player has enough |
| `RegisterUsableItem(item, fn(source, data))` | Framework usable item (ox_inventory items are set in its item data) |
| `Notify(source, message, type, duration, title)` | `type`: `'info'`, `'success'`, `'error'` or `'warning'` |
| `HasPermission(source, permission)` | Ace, or the ESX group / QBCore permission |
| `Login(source, identifier, data)` / `Logout(source)` | For multicharacter: ESX `identifier` is the prefix (`char1`), QB / Qbox the citizenid |

## Client API

| Function | Returns |
|---|---|
| `GetFramework()` / `GetInventory()` / `GetObject()` | Same as the server |
| `IsPlayerLoaded()` | A character is loaded |
| `GetPlayerData()` | The framework's raw player data |
| `GetIdentifier()`, `GetJob()`, `HasJob(jobs, minGrade)` | Same shapes as the server |
| `GetCharacter()`, `GetName()`, `GetFullName()`, `GetSex()` | `GetSex()`: 0 male / 1 female |
| `GetMoney(account)`, `GetItemCount(item)`, `HasItem(item, count)` | From the player data or ox_inventory. Do the real checks on the server. |
| `Notify(message, type, duration, title)` | ox_lib, the framework, or the GTA feed (`Config.Notify`) |
| `DisableSpawnManager()` | Turns off spawnmanager's auto spawn |

## Events

Use these instead of `esx:playerLoaded` / `QBCore:Client:OnPlayerLoaded` and the rest. They fire the same way on every framework.

```lua
Core.OnPlayerLoaded(function(source) end)              -- server; the client gets no arguments
Core.OnPlayerUnloaded(function(source) end)            -- server; the client gets no arguments
Core.OnJobUpdated(function(source, job, lastJob) end)  -- server; client: function(job)
```

Event names: `yecoyz_core:server:playerLoaded`, `:playerUnloaded`, `:jobUpdated`, and the same names with `client`.

## Config

`config.lua`: `Framework`, `Inventory` and `Notify` are all `'auto'` by default. There's also the default notification
title and duration, `BossGrades` (ESX grade names that count as boss, since ESX jobs have no boss flag), the cash item
used without a framework, and `Debug`.
