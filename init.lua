adabots = {
    config = {
        -- Turtles are yielded after every instruction
        -- This is how long timed turtle actions take, such as mining, moving, and placing
        turtle_tick = .3, -- Default: 0.3 seconds
        --Fuel inside of turtles when they spawn
        fuel_initial = 1000, --Default: 1000 actions
        --Allows turtle:debug(string) to go to debug.txt
        debug = true,
    },
    turtles = {},
    num_turtles = 0,
}

http_api = minetest.request_http_api()
if http_api == nil then
  print("ERROR: HTTP disabled. In minetest Settings > All Settings > HTTP mods, list adabots")
end

local modpath = minetest.get_modpath("adabots")
dofile(modpath.."/src/turtle_block.lua")
dofile(modpath.."/src/turtle_entity.lua")
