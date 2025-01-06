minetest.register_privilege("adabots_admin", {
  description = "Can configure adabots server settings",
  give_to_singleplayer = true
})

minetest.register_chatcommand( "adabots_list_settings", {
  description = "List AdaBots admin settings",
  params = '',
  privs = { adabots_admin = true },
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
