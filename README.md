# yecoyz_core

The shared framework layer and callback system for the yecoyz resources. Each resource used to carry its own bridge;
now they all load this one, so ESX / QBCore / Qbox / standalone support lives in one place. It also has the shared
in-game UI: notifications, interactions (a target-like menu without the target key) and a controls card.

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
| `Notify(message, type, duration, title)` | The core's own notification UI by default (`Config.Notify`) |
| `AddInteraction(data)` / `RemoveInteraction(id)` | See [Interactions](#interactions) |
| `GetActiveInteraction()` | The menu on screen: `{ index, options = { { name, label } } }`, or nil |
| `SetInteractionsDisabled(state)` | Hide and pause every interaction, e.g. during a minigame |
| `IsUIReady()` | The NUI page has loaded (messages sent before that are queued) |
| `ShowControls(rows, title, id)` / `HideControls(id)` | See [Controls card](#controls-card) |
| `DisableSpawnManager()` | Turns off spawnmanager's auto spawn |

## Notifications

`Core.Notify(message, type, duration, title)` shows a small toast at the top of the screen with a coloured bar for the
type (`info`, `success`, `error`, `warning`). From the server it is `Core.Notify(source, message, type, duration, title)`.
`Config.Notify = 'yecoyz'` is the default; set `'auto'`, `'ox_lib'`, `'framework'` or `'native'` to use something else.

## Interactions

A target system without the target key. Walk up to a prop, a door handle or a spot, and a menu appears on it. If it has
several options, scroll the mouse wheel to switch between them and press `E` to use the selected one.

```lua
local id = Core.AddInteraction({
    id = 'cityhall_door',            -- optional; adding the same id again replaces it
    coords = vec3(-544.9, -204.4, 38.2),
    distance = 2.0,                  -- how close the player has to be (default Config.Interact.Distance)
    options = {
        { name = 'open', label = 'Open door', icon = 'door-open', onSelect = function(data) end },
        { name = 'lock', label = 'Lock door', icon = 'lock', jobs = 'police', serverEvent = 'cityhall:lock' },
        { name = 'knock', label = 'Knock', icon = 'hand', command = 'knock' },
    },
})
Core.RemoveInteraction(id)
```

Where the menu appears (use one of them):

| Field | Spot |
|---|---|
| `coords` | A fixed position |
| `entity` / `netId` | One entity. `bone = 'door_dside_f'` (or a list, the closest is used) or `offset = vec3(...)` pins the menu to a part of it, like a door handle |
| `models = { 'prop_atm_01' }` | Every entity of these models |
| `global = 'vehicle'` | Every `'vehicle'`, `'ped'` (not players), `'player'` or `'object'` (heavy, prefer `models`) |

Per option:

| Field | |
|---|---|
| `label` | Required. `name` identifies the option, `icon` is a [lucide](https://lucide.dev/icons) name |
| `onSelect(data)` | Called with `{ entity, netId, coords, distance, name, id }` |
| `event` / `serverEvent` / `command` | Alternatives to `onSelect`. `serverEvent` gets the data without `entity` (use `netId`) |
| `distance` | Shorter range than the registration |
| `jobs`, `items` | Same forms as `Core.HasJob` / `Core.HasItem` |
| `canInteract(entity, distance, coords, name)` | Return false to hide the option |
| `inVehicle` | Also show while the player is in a vehicle (hidden by default) |

The options of one spot are shown together, and when several spots are in range the closest one is shown.
Registrations are removed when the resource that added them stops. The key, distance and scan rate are in
`Config.Interact`.

## Controls card

Shows the keys of a mode and what they do, bottom-right. Each resource has its own card and the latest one is shown;
hiding it brings back the one below.

```lua
Core.ShowControls({
    { keys = { 'LMB' }, label = 'Select' },
    { keys = { 'Shift', 'Scroll' }, label = 'Rotate' },
    { keys = { 'Del' }, label = 'Delete', dim = true },   -- dim: not available right now
}, 'Editor')
Core.HideControls()
```

## Events

Use these instead of `esx:playerLoaded` / `QBCore:Client:OnPlayerLoaded` and the rest. They fire the same way on every framework.

```lua
Core.OnPlayerLoaded(function(source) end)              -- server; the client gets no arguments
Core.OnPlayerUnloaded(function(source) end)            -- server; the client gets no arguments
Core.OnJobUpdated(function(source, job, lastJob) end)  -- server; client: function(job)
```

Event names: `yecoyz_core:server:playerLoaded`, `:playerUnloaded`, `:jobUpdated`, and the same names with `client`.

## Config

`config.lua`: `Framework` and `Inventory` are `'auto'` by default and `Notify` is `'yecoyz'`. There's also the default
notification title and duration, the `Interact` settings (key, distance, scan rate), `BossGrades` (ESX grade names that count as boss, since ESX jobs have no boss flag), the cash item
used without a framework, `VersionCheck` and `Debug`.

## Update notices

On start, Core asks `https://yecoyz.com/api/version` for the latest version of every running `yecoyz_*` resource and
prints a console notice for the ones whose fxmanifest `version` is behind. A resource only needs a semver `version`
in its fxmanifest. Turn it off with `Config.VersionCheck = false`, or skip one resource with
`yecoyz_version_check 'no'` in its fxmanifest. The URL can be overridden with the `yecoyz_version_url` convar.

## UI

The NUI page is in `web/` (React + Vite, built from the shared `yecoyz_uilibrary` components). `web/dist` is committed,
so a fresh clone needs no build. After changing `web/src`, run `npm install && npm run build` in `web/`.
