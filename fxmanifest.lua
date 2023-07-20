fx_version  'adamant'
use_experimental_fxv2_oal 'yes'
lua54       'yes'
game        'gta5'

name        'smb_properties'
author      '0xSimba'
version     '1.0'
license     'No License'
description 'Enhanced property management for FiveM, integrated with QBUS. Enables player property ownership, tenant management, and dynamic interactions.'

shared_scripts {
    'config.lua',
}

client_scripts {
    '@PolyZone/client.lua',
    '@PolyZone/BoxZone.lua',
    '@PolyZone/EntityZone.lua',
    '@PolyZone/CircleZone.lua',
    '@PolyZone/ComboZone.lua',
    'smb_properties_cl.lua'
}




