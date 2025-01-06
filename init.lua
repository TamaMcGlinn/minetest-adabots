adabots = {
  config = {
    -- Turtles are yielded after every instruction
    -- This is how long timed turtle actions take, such as mining, moving, and placing
    turtle_tick = tonumber(minetest.settings:get("adabots_turtle_tick_time")) or .3,
    fuel_multiplier = tonumber(minetest.settings:get("adabots_fuel_multiplier")) or 1.0,
    energy_cost_multiplier = tonumber(minetest.settings:get("adabots_energy_cost_multiplier")) or 1.0,

    -- Energy settings
    energy_initial = tonumber(minetest.settings:get("adabots_energy_initial")) or 0,
    -- Refueling above this wastes energy
    energy_max = tonumber(minetest.settings:get("adabots_energy_max")) or 4000,
    turn_energy_cost = tonumber(minetest.settings:get("adabots_turn_energy_cost")) or 0,
    horizontal_energy_cost = tonumber(minetest.settings:get("adabots_horizontal_energy_cost")) or 6,
    upward_energy_cost = tonumber(minetest.settings:get("adabots_upward_energy_cost")) or 30,
    downward_energy_cost = tonumber(minetest.settings:get("adabots_downward_energy_cost")) or 0,
    hover_energy_cost = tonumber(minetest.settings:get("adabots_hover_energy_cost")) or 4,
    think_energy_cost = tonumber(minetest.settings:get("adabots_think_energy_cost")) or 0,
    build_energy_cost = tonumber(minetest.settings:get("adabots_build_energy_cost")) or 20,
    mine_energy_cost = tonumber(minetest.settings:get("adabots_mine_energy_cost")) or 20,
  },
  turtles = {},
  num_turtles = 0,
  workspaces = {}
}

-- config sanity checks
adabots.config.range_restrictions = {}
local function range_restrict(setting_name)
  local min, max = unpack(adabots.config.range_restrictions[setting_name])
  if min ~= nil and adabots.config[setting_name] < min then
    minetest.log("warning", "setting adabots_" .. setting_name .. " = " .. adabots.config[setting_name] .. " below minimum (" .. min .. ")")
    adabots.config[setting_name] = min
  end
  if max ~= nil and adabots.config[setting_name] > max then
    minetest.log("warning", "setting adabots_" .. setting_name .. " = " .. adabots.config[setting_name] .. " above maximum (" .. max .. ")")
    adabots.config[setting_name] = max
  end
end

local function set_range(setting_name, min, max)
  adabots.config.range_restrictions[setting_name] = {min, max}
  range_restrict(setting_name)
end

function adabots.list_settings(playername)
  minetest.chat_send_player(playername, "AdaBots settings:")
  for name,values in pairs(adabots.config.range_restrictions) do
    local min, max = unpack(values)
    minetest.chat_send_player(playername, name .. ", currently set to " .. adabots.config[name] .. " allowed range [" .. min .. ", " .. max .. "] (inclusive)")
  end
end

function adabots.change_setting(setting_name, new_value)
  adabots.config[setting_name] = new_value
  range_restrict(setting_name)
end

set_range("fuel_multiplier", 0, 1000)
set_range("energy_cost_multiplier", 0, 10)
set_range("energy_max", 100, 1000000)
set_range("energy_initial", 0, adabots.config.energy_max)
set_range("turn_energy_cost", 0, 1000)
set_range("horizontal_energy_cost", 0, 1000)
set_range("upward_energy_cost", 0, 1000)
set_range("downward_energy_cost", 0, 1000)
set_range("hover_energy_cost", 0, 1000)
set_range("think_energy_cost", 0, 1000)
set_range("build_energy_cost", 0, 1000)
set_range("mine_energy_cost", 0, 1000)

http_api = minetest.request_http_api()
if http_api == nil then
  print(
    "ERROR: HTTP disabled. In minetest Settings > All Settings > HTTP mods, list adabots")
end

local modpath = minetest.get_modpath("adabots")
dofile(modpath .. "/src/turtle_block.lua")
dofile(modpath .. "/src/turtle_entity.lua")
dofile(modpath .. "/src/admin_commands.lua")

-- for debugging, use e.g. minetest.debug("D: " .. json.encode(sometable))
-- json = dofile(modpath .. "/json.lua/json.lua")
-- json.lua/ is gitignored, you need to:
-- git clone git@github.com:rxi/json.lua
