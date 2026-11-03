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
        UI = 'yecoyz', -- 'yecoyz' (a menu on the spot) | 'ox_lib' (ox_lib's text UI shows the selected option)
        OxPosition = 'right-center', -- where ox_lib's text UI sits: 'right-center' | 'left-center' | 'top-center' | 'bottom-center'
        Key = 38, -- control that uses the selected option (38 = E). Scrolling switches between the options.
        KeyLabel = 'E', -- shown when the game can't tell which key the control is bound to
        Distance = 2.0, -- default distance in metres
        ScanInterval = 200, -- ms between looking for something in range
        HideInVehicle = true, -- nothing shows in a vehicle, except options with inVehicle = true
        ScrollLabel = 'Scroll', -- text next to the 1 / 3 counter
    },

    -- ESX has no boss flag on jobs: these grade names count as boss in GetJob().isBoss.
    BossGrades = { 'boss' },

    -- Company (society) accounts used by GetSocietyMoney / AddSocietyMoney / RemoveSocietyMoney.
    -- 'auto' picks esx_addonaccount (ESX), Renewed-Banking, qb-banking, qb-management, else 'internal' (the core's
    -- own yecoyz_core_society table). Needs oxmysql.
    Society = {
        System = 'auto', -- 'auto' | 'internal' | 'esx_addonaccount' | 'renewed-banking' | 'qb-banking' | 'qb-management'
        AccountPrefix = 'society_', -- esx_addonaccount account name: society_<job>
    },

    -- Garage script used when a resource gives a player a vehicle (GiveVehicle). 'auto' picks the first running one of
    -- jg-advancedgarages, zyke_garages, qbx_garages, qb-garages and esx_garage, else 'default' (the framework's
    -- vehicle table only). Default = garage name/id new vehicles go to; nil = the garage script's own default
    -- (qb/qbx: motelgarage, jg: Legion Square, esx_garage: its first garage, zyke: the player's default garage).
    Garage = {
        System = 'auto', -- 'auto' | 'default' | 'jg-advancedgarages' | 'zyke_garages' | 'qbx_garages' | 'qb-garages' | 'esx_garage'
        Default = nil,
        -- Job (work) garages for GiveJobVehicle: [job] = garage name/id. Not listed = the job name for qb-garages,
        -- qbx_garages and jg-advancedgarages (their job garages are named after the job by default), zyke_garages
        -- picks one of the job's own garages.
        JobGarages = {
            -- police = 'police',
        },
    },

    -- Item used for cash when there is no framework but ox_inventory runs.
    MoneyItem = 'money',

    -- Print a console notice when a yecoyz_* resource has a newer version on yecoyz.com (checked on start).
    VersionCheck = true,

    Debug = false,
}
