fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'Yecoyz'
description 'Shared framework layer, callback system, notifications and interactions for the yecoyz resources'
version '1.2.0'

-- Resources load the API with: shared_script '@yecoyz_core/import.lua' and dependency 'yecoyz_core'.
shared_scripts { 'config.lua', 'shared/framework.lua' }
server_scripts { 'server/framework.lua', 'server/inventory.lua', 'server/events.lua', 'server/exports.lua', 'server/version.lua' }
client_scripts {
    'client/framework.lua', 'client/ui.lua', 'client/notify.lua', 'client/controls.lua', 'client/interact.lua',
    'client/events.lua', 'client/demo.lua', 'client/exports.lua',
}

ui_page 'web/dist/index.html'

files { 'import.lua', 'web/dist/**/*' }
