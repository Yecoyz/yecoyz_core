Config = {
    -- 'auto' picks the first one running: es_extended (esx), qbx_core (qbox), qb-core (qb), else standalone.
    Framework = 'auto', -- 'auto' | 'esx' | 'qbox' | 'qb' | 'standalone'

    -- 'auto' uses ox_inventory when it runs, otherwise the framework's own inventory.
    Inventory = 'auto', -- 'auto' | 'ox_inventory' | 'framework'

    -- 'auto' uses ox_lib when it runs, then the framework, then the GTA feed.
    Notify = 'auto', -- 'auto' | 'ox_lib' | 'framework' | 'native'
    NotifyTitle = nil, -- default title for ox_lib notifications (nil = none)
    NotifyDuration = 5000,

    -- ESX has no boss flag on jobs: these grade names count as boss in GetJob().isBoss.
    BossGrades = { 'boss' },

    -- Item used for cash when there is no framework but ox_inventory runs.
    MoneyItem = 'money',

    -- Print a console notice when a yecoyz_* resource has a newer version on yecoyz.com (checked on start).
    VersionCheck = true,

    Debug = false,
}
