Config = {
    -- 'auto' picks the first one running: es_extended (esx), qbx_core (qbox), qb-core (qb), else standalone.
    Framework = 'auto', -- 'auto' | 'esx' | 'qbox' | 'qb' | 'standalone'

    -- 'auto' uses ox_inventory when it runs, otherwise the framework's own inventory.
    Inventory = 'auto', -- 'auto' | 'ox_inventory' | 'framework'

    -- 'yecoyz' is the core's own notification UI. 'auto' uses ox_lib when it runs, then the framework, then the GTA feed.
    Notify = 'yecoyz', -- 'yecoyz' | 'auto' | 'ox_lib' | 'framework' | 'native'
    NotifyTitle = nil, -- default title for notifications (nil = none)
    NotifyDuration = 5000,

    -- Interactions (Core.AddInteraction): a menu on the prop or door handle you walk up to, no target key.
    Interact = {
        Enabled = true,
        Key = 38, -- control that uses the selected option (38 = E). Scrolling switches between the options.
        KeyLabel = 'E', -- shown when the game can't tell which key the control is bound to
        Distance = 2.0, -- default distance in metres
        ScanInterval = 200, -- ms between looking for something in range
        HideInVehicle = true, -- nothing shows in a vehicle, except options with inVehicle = true
        ScrollLabel = 'Scroll', -- text next to the 1 / 3 counter
    },

    -- ESX has no boss flag on jobs: these grade names count as boss in GetJob().isBoss.
    BossGrades = { 'boss' },

    -- Item used for cash when there is no framework but ox_inventory runs.
    MoneyItem = 'money',

    -- Print a console notice when a yecoyz_* resource has a newer version on yecoyz.com (checked on start).
    VersionCheck = true,

    Debug = true,
}
