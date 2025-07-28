fx_version 'cerulean'
game 'gta5'

author 'Bagelbites99'
description 'Petty Crime script bundle'
version '2.0'

dependencies {
    'qbx_core',
    'ox_target',
    'ox_lib',
    'ox_inventory',
}

shared_scripts {
    '@ox_lib/init.lua',
    'shared/*.lua'
}

client_scripts {
    'client/*.lua'
}

server_scripts {
    'server/police.lua', 
    'server/*.lua'
}

server_exports {
    'GetOnlinePoliceCount',
    'CheckPoliceRequirement'
}

lua54 'yes'
use_experimental_fxv2_oal 'yes'