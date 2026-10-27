fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'Yecoyz'
description 'Shared framework layer and callback system for the yecoyz resources'
version '1.1.0'

-- Resources load the API with: shared_script '@yecoyz_core/import.lua' and dependency 'yecoyz_core'.
shared_scripts { 'config.lua', 'shared/framework.lua' }
server_scripts { 'server/framework.lua', 'server/inventory.lua', 'server/events.lua', 'server/exports.lua', 'server/version.lua' }
client_scripts { 'client/framework.lua', 'client/notify.lua', 'client/events.lua', 'client/exports.lua' }

files { 'import.lua' }
