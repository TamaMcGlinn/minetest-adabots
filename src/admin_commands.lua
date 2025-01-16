minetest.register_privilege("adabots_admin", {
  description = "Can configure adabots server settings",
  give_to_singleplayer = true
})

minetest.register_chatcommand( "adabots_list_settings", {
  description = "List AdaBots admin settings",
  params = '',
  privs = {},
  func = function( playername, param )
    local args = string.split( param, " " )
    if #args ~= 0 then
      return false, "Usage: /adabots_list_settings (no arguments)"
    end
    adabots.list_settings(playername)
    return true
  end
} )

minetest.register_chatcommand( "adabots_set", {
  description = "Change AdaBots admin setting",
  params = '<settingname> <value>',
  privs = { adabots_admin = true },
  func = function( _, param )
    local args = string.split( param, " " )
    if #args ~= 2 then
      return false, "Usage: /adabots_set <settingname> <multiplier>. E.g. /adabots_set energy_cost_multiplier 0.1 (see /adabots_list_settings)"
    end
    if adabots.config[args[1]] == nil then
      return false, "<settingname> must be a valid adabots setting (see /adabots_list_settings)"
    end
    local newvalue = tonumber(args[2])
    if newvalue == nil then
      return false, "<multiplier> must be a number"
    end
    adabots.change_setting(args[1], newvalue)
    return true
  end
} )

minetest.register_chatcommand( "adabots_list_bots", {
  description = "List bots",
  params = '[--verbose] [--own/--accessible] [bot_id]',
  privs = { adabots_admin = true },
  func = function( playername, param )
    local args = string.split( param, " " )
    if #args > 4 then
      return false, "Usage: /adabots_list_bots [--verbose] [--own|accessible] [--listening] [bot_id]. E.g. /adabots_list_bots --verbose --accessible"
    end
    local verbose = false
    local filter_listening = false
    local filter_own = false
    local filter_accessible = false
    local bot_id = nil
    for _, arg in ipairs(args) do
      if arg == "--verbose" then
        verbose = true
      end
      if arg == "--listening" then
        filter_listening = true
      end
      if arg == "--own" then
        filter_own = true
      end
      if arg == "--accessible" then
        filter_accessible = true
      end
      local as_number = tonumber(arg)
      if as_number then
        if bot_id ~= nil then
          return false, "/adabots_list_bots only allows one bot_id (or none to list all)"
        end
        bot_id = as_number
      end
    end
    adabots.list_bots(playername, bot_id, verbose, filter_own, filter_accessible, filter_listening)
  end
} )

minetest.register_chatcommand( "adabots_bot_cmd", {
  description = "Remotely operate bot",
  params = '<bot_id|all> <cmdname> [values...]',
  privs = { adabots_admin = true },
  func = function( player_name, param )
    local args = string.split( param, " " )
    local usage_info = "Usage: /adabots_bot_cmd <bot_id|all> <cmdname> [values...]. E.g. /adabots_bot_cmd all stoplisten (see /adabots_list_bots)"
    if #args < 2 then
      return false, usage_info
    end
    local bot_id = args[1]
    if bot_id ~= "all" then
      bot_id = tonumber(bot_id)
      if bot_id == nil then
        return false, "<bot_id> must be either 'all' or a number. " .. usage_info
      end
    end
    local cmd = args[2]
    local cmd_args = {}
    if #args > 2 then
      cmd_args = {unpack(args, 3)}
    end
    return adabots.bot_cmd(player_name, bot_id, cmd, cmd_args)
  end
} )

local rpad = function(str, len, char)
  str = tostring(str)
  if char == nil then char = ' ' end
  if str == nil then return string.rep(char, len) end
  local real_stringlen = #str + str:gsub("[a-z]", ""):len() / 2
  return str .. string.rep(char, len - real_stringlen)
end

local function bot_passes_filter(playername, turtle, bot_id, filter_own, filter_accessible, filter_listening)
  if bot_id ~= nil and turtle.id ~= bot_id then return false end
  if filter_own and turtle.owner ~= playername then return false end
  if filter_accessible and not turtle:player_allowed_to_control_bot(playername) then return false end
  if filter_listening and not turtle.is_listening then return false end
  return true
end

function adabots.list_bots(playername, bot_id, verbose, filter_own, filter_accessible, filter_listening)
  minetest.log(" ID  | Name       | Owner     | Workspace    | Listening ")
  for _,turtle in ipairs(adabots.turtles) do
    if bot_passes_filter(playername, turtle, bot_id, filter_own, filter_accessible, filter_listening) then
      local listening = "false"
      if turtle.listening then listening = "true " end
      local workspace = ""
      if turtle.workspace ~= nil then
        workspace = turtle.workspace.name
      end
      minetest.log(" " .. rpad(tostring(turtle.id), 4) .. "  | "
        .. rpad(turtle.name or "", 12) .. " | " .. rpad(turtle.owner or "", 10) .. " | "
        .. rpad(workspace or "", 10) .. " | " .. listening)
      if verbose then
        local energy_info = ""
        if adabots.config.energy_cost_multiplier > 0 then
          energy_info = "ϟ: " .. turtle.energy .. "/" .. adabots.config.energy_max
        end
        local pickname = "(none)"
        local tool_info = turtle:getToolInfo()
        if tool_info ~= nil then
          pickname = tool_info.name
        end
        local pick_info = " Tool: " .. rpad(pickname, 20)
        local coordinates = " Coordinates: " .. tostring(turtle:get_pos() or "nil")
        local verbose_info = energy_info .. pick_info .. coordinates
        minetest.log(verbose_info)
      end
    end
  end
  minetest.log("______________________________")
end

-- returns the position of an air block at about 8 blocks distance from the player,
-- such that there's no other bot or blocking object or player there
-- extrapolated_position is optional and defaults to North. If specified, the
-- returned position will be in that direction - pass the old bot location so that the
-- effect is to pull the bots in towards the player
function adabots.get_position_near_player(player_name, extrapolated_position)
  local player = minetest.get_player_by_name(player_name)
  if player == nil then
    minetest.log("error", "No such player " .. player_name)
    return nil
  end
  local player_pos = player:get_pos()
  if player_pos == nil then
    minetest.log("error", "Player " .. player_name .. ":get_pos() returned nil")
    return nil
  end
  if extrapolated_position == nil then
    extrapolated_position = player_pos + vector.new(0, 0, 8)
  else
    local diff = extrapolated_position - player_pos
    local offset = vector.normalize(diff) * 8
    extrapolated_position = player_pos + offset
  end
  local pos = adabots.find_empty_space_near(extrapolated_position)
  if pos == nil then
    minetest.log("error", "Unable to find air near " .. player_name)
    return nil
  end
  minetest.log("info", "Found new position " .. dump(pos))
  return pos
end

-- returns nearest air block to pos that isn't already occupied by a bot
-- or blocking entity (e.g. horses, players)
function adabots.find_empty_space_near(pos)
  if pos == nil then return nil end
  pos = vector.new(math.floor(pos.x), math.floor(pos.y), math.floor(pos.z))
  for distance = 1,15,2 do
    local distvec = vector.new(distance, distance, distance)
    local min = pos - distvec
    local max = pos + distvec
    local air_nodes, _ = minetest.find_nodes_in_area(min, max, {"air"}, false)
    minetest.log("searching in distance " .. distance)
    for _,air_node in ipairs(air_nodes) do
      if not adabots.node_walkable(air_node) then
        return air_node
      end
    end
  end
  minetest.log("error", "Unable to bring bot; no empty space near " .. dump(pos))
  return nil
end

function adabots.single_bot_cmd(player_name, turtle, cmd, cmd_args)
  if cmd == "stoplisten" then
    turtle:update_is_listening(false)
    return true
  end
  if cmd == "listen" then
    turtle:update_is_listening(true)
    return true
  end
  if cmd == "bring" then
    local new_pos = adabots.get_position_near_player(player_name, turtle:get_pos())
    if new_pos == nil then
      return false, "Unable to find suitable place to jump to"
    else
      turtle.object:move_to(new_pos, false)
      return true
    end
  end
  if cmd == "control" then
    turtle:open_controlpanel(player_name)
    return true
  end
end

function adabots.bot_cmd(player_name, bot_id, cmd, cmd_args)
  if bot_id == "all" then
    local first_fail_id, first_error_msg = nil, ""
    local result, errormsg = true, ""
    for _,turtle in ipairs(adabots.turtles) do
      result, errormsg = adabots.single_bot_cmd(player_name, turtle, cmd, cmd_args)
      if not result then
        first_fail_id = turtle.id
        first_error_msg = errormsg
      end
    end
    if first_fail_id ~= nil then
      return false, "Bot " .. tostring(first_fail_id) .. " failed with " .. dump(first_error_msg)
    end
    return true, ""
  else
    local turtle = adabots.turtles[bot_id]
    if turtle == nil then
      return false, "No bot found with id " .. bot_id
    end
    return adabots.single_bot_cmd(player_name, turtle, cmd, cmd_args)
  end
end
