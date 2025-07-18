fx_version 'cerulean'
lua54 'yes'
game 'gta5'

author 'Liinux'
description 'Rental'
version '1.0.2'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
}

client_scripts {
    'client/*.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/*.lua'
}
