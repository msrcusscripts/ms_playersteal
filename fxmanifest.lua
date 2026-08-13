fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'ms_playersteal'
author 'Marcus Scripts'
description 'Player robbery with built-in hands up for ESX, QBCore and Qbox - ox_target, ox_lib, ox_inventory and wasabi_ambulance'
version '1.6.0'

-- Asset Escrow: the files below stay unencrypted so they can be customized.
escrow_ignore {
    'config.lua',
    'server/webhooks.lua',
    'README.md',
}

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
}

client_scripts {
    'client/handsup.lua',
    'client/main.lua',
}

server_scripts {
    'server/bridge.lua',
    'server/webhooks.lua',
    'server/logs.lua',
    'server/main.lua',
}

-- One of es_extended, qbx_core or qb-core must also be started before this
-- resource; it is not listed here so the same build runs on all three.
dependencies {
    'ox_lib',
    'ox_target',
    'ox_inventory',
    'wasabi_ambulance',
}
