-- override this by setting ADABOTS_PROXY_URL environment variable to your own proxy URL
local INSTRUCTION_PROXY_URL = os.getenv("INSTRUCTION_PROXY_BASE_URL") or nil
local userId = os.getenv("USER_ID") or "undefined"
minetest.log("info", "INSTRUCTION_PROXY_URL: " .. INSTRUCTION_PROXY_URL)

local botaccess_max_share_count = 12

-- Load support for factions
local factions_available = minetest.global_exists("factions")

local modpath = minetest.get_modpath("adabots")
local S = minetest.get_translator("adabots")
local F = function (s) return minetest.formspec_escape(s) end

-- https://stackoverflow.com/a/16077650/2144408
local function deepcopy(o, seen)
  seen = seen or {}
  if o == nil then return nil end
  if seen[o] then return seen[o] end

  local no
  if type(o) == 'table' then
    no = {}
    seen[o] = no

    for k, v in next, o, nil do
      no[deepcopy(k, seen)] = deepcopy(v, seen)
    end
    setmetatable(no, deepcopy(getmetatable(o), seen))
  else -- number, string, boolean, etc
    no = o
  end
  return no
end

-- remove protections while doing the action passed in
-- and then re-enable protections again
local function override_protection(action)
  local old_is_protected = minetest.is_protected
  minetest.is_protected = function(_, _) return false end
  local result = action()
  minetest.is_protected = old_is_protected
  return result
end

-- get all player objects that are more-or-less
-- standing at that nodelocation
local function get_players_at(nodeLocation)
  local players_list = {}
  local objectsthere = minetest.get_objects_inside_radius(nodeLocation, 0.85)
  for _,object in ipairs(objectsthere) do
    if minetest.is_player(object) then
      players_list[#players_list + 1] = object
    end
  end
  return players_list
end

local FORMNAME_TURTLE_INVENTORY = "adabots:turtle:inventory:"
local FORMNAME_TURTLE_CONTROLPANEL = "adabots:turtle:controlpanel:"
local FORMNAME_TURTLE_ACCESSCONTROL = "adabots:turtle:accesscontrol:"
local FORMNAME_TURTLE_SLOTSELECT = "adabots:turtle:slotselect:"
local FORMNAME_TURTLE_NOTYOURBOT = "adabots:turtle:notyourbot:"
local turtle_forms = {
  [FORMNAME_TURTLE_INVENTORY] = {
    ["formspec_function"] = function(turtle, player_name)
      return turtle:get_formspec_inventory(player_name)
    end
  },
  [FORMNAME_TURTLE_CONTROLPANEL] = {
    ["formspec_function"] = function(turtle, _)
      return turtle:get_formspec_controlpanel()
    end
  },
  [FORMNAME_TURTLE_ACCESSCONTROL] = {
    ["formspec_function"] = function(turtle, _)
      return turtle:get_formspec_accesscontrol()
    end
  },
  [FORMNAME_TURTLE_SLOTSELECT] = {
    ["formspec_function"] = function(turtle, _)
      return turtle:get_formspec_slotselect()
    end
  },
  [FORMNAME_TURTLE_NOTYOURBOT] = {
    ["formspec_function"] = function(turtle, _)
      return turtle:get_formspec_notyourbot()
    end
  }
}
local supported_tools = {
  "mcl_tools:pick_wood", "mcl_tools:pick_stone", "mcl_tools:pick_iron",
  "mcl_tools:pick_gold", "mcl_tools:pick_diamond",
  "default:pick_wood", "default:pick_stone", "default:pick_steel",
  "default:pick_bronze", "default:pick_mese", "default:pick_diamond"
}

local furnace_node_types = {
  ["default:furnace"] = true, ["default:furnace_active"] = true
}

-- returns the wear for one use,
-- such that the given number of uses will break the tool
local function get_wear_for_uses(uses) return 65535 / (uses - 1) end

local tool_usages = {
  ["mcl_tools:pick_wood"] = 30,
  ["mcl_tools:pick_stone"] = 60,
  ["mcl_tools:pick_iron"] = 180,
  ["mcl_tools:pick_gold"] = 20,
  ["mcl_tools:pick_diamond"] = 810,
  ["default:pick_wood"] = 30,
  ["default:pick_stone"] = 60,
  ["default:pick_steel"] = 180,
  ["default:pick_bronze"] = 180,
  ["default:pick_mese"] = 540,
  ["default:pick_diamond"] = 810
}
local tool_wear_rates = {}
for i = 1, #supported_tools do
  local tool = supported_tools[i]
  local usage = tool_usages[tool]
  local wear_rate = get_wear_for_uses(usage)
  tool_wear_rates[tool] = wear_rate
  -- minetest.debug(tool .. " wear rate " .. wear_rate)
end

function adabots.map(f, t)
  local t1 = {}
  local next = 1
  for _, v in ipairs(t) do
    t1[next] = f(v)
    next = next + 1
  end
  return t1
end

function adabots.get_workspace_names()
  local result = adabots.map((function(element) return element["name"] end),
    adabots.workspaces)
  return result
end

local function round(num) return math.floor(num + 0.5) end

local craftSquares = {1, 2, 3, 5, 6, 7, 9, 10, 11}
local TURTLE_INVENTORYSIZE = 4 * 4

-- lifted from mcl_signs
local SIGN_WIDTH = 115
local LINE_LENGTH = 15
local CHAR_WIDTH = 5

local chars_file = io.open(modpath .. "/characters.txt", "r")
-- FIXME: Support more characters (many characters are missing). Currently ASCII and Latin-1 Supplement are supported.
local charmap = {}
if not chars_file then
  minetest.log("error", "[mcl_signs] : character map file not found")
else
  while true do
    local char = chars_file:read("*l")
    if char == nil then break end
    local img = chars_file:read("*l")
    chars_file:read("*l")
    charmap[char] = img
  end
end

local NAMETAG_DELTA_X = 0
local NAMETAG_DELTA_Y = 0
local NAMETAG_DELTA_Z = -2

---@returns TurtleEntity of that ID
local function getTurtle(id) return adabots.turtles[id] end

---@returns true if given index is in range [1, TURTLE_INVENTORYSIZE]
local function isValidInventoryIndex(index)
  return 0 < index and index <= TURTLE_INVENTORYSIZE
end

-- advtrains inventory serialization helper (c) 2017 orwell96
local function serializeInventory(inv)
  local data = {}
  for listName, listStack in pairs(inv:get_lists()) do
    data[listName] = {}
    for index, item in ipairs(listStack) do
      local itemString = item:to_string()
      data[listName][index] = itemString
    end
  end
  return minetest.serialize(data)
end

local function deserializeInventory(inv, str)
  local data = minetest.deserialize(str)
  if data then
    inv:set_lists(data)
    return true
  end
  return false
end

local function updateBotField(turtle, fields, field_key, field_changed_functor)
  local field_value = fields[field_key]
  if field_value then
    if turtle[field_key] ~= field_value then
      turtle[field_key] = field_value
      if field_changed_functor ~= nil then
        field_changed_functor()
      end
    end
  end
end

minetest.register_on_player_receive_fields(
  function(player, formname, fields)
    local function isForm(name)
      return string.sub(formname, 1, string.len(name)) == name
    end
    local turtleform = ""
    for form_name, _ in pairs(turtle_forms) do
      if isForm(form_name) then turtleform = form_name end
    end
    if turtleform == "" then
      return false
    end
    local function get_turtle()
      local number_suffix =
      string.sub(formname, 1 + string.len(turtleform))
      local id = tonumber(number_suffix)
      return getTurtle(id)
    end
    local turtle = get_turtle()
    local player_name = player:get_player_name()
    if not isForm(FORMNAME_TURTLE_NOTYOURBOT) and not turtle:player_allowed_to_control_bot(player_name) then
      -- close immediately, don't process any inputs
      -- this can happen if you open something but then your access is revoked while
      -- you still have the menu open.
      minetest.close_formspec(player_name, formname)
      minetest.after(0.2, turtle.open_form, turtle, player_name, FORMNAME_TURTLE_NOTYOURBOT)
      return true
    end
    local function refresh(form)
      turtle:open_form(player_name, form)
    end
    local function respond_to_common_controls()
      if fields.close then
        minetest.close_formspec(player_name, formname)
      end
      if fields.open_controlpanel then
        turtle:open_controlpanel(player_name)
      end
    end
    if isForm(FORMNAME_TURTLE_INVENTORY) then
      respond_to_common_controls()
      if fields.close or fields.quit or fields.open_controlpanel or fields.access_control then turtle:stop_updating_inventory(player_name) end
      if fields.workspace then
        turtle:select_workspace(fields.workspace)
      end
      updateBotField(turtle, fields, "name",
        function() turtle:update_nametag() end)
      if fields.listen then
        turtle:toggle_is_listening()
        refresh(turtleform)
        return true
      end
      if fields.refuel then
        if turtle.autoRefuel == true then
          turtle:setAutoRefuel(false)
          refresh(turtleform)
        else
          turtle:setAutoRefuel(true)
          turtle:refuel_from_any_slot()
          refresh(turtleform)
        end
        return true
      end
      if fields.access_control then
        turtle:open_access_control(player_name)
      end
      return true
    elseif isForm(FORMNAME_TURTLE_CONTROLPANEL) then
      respond_to_common_controls()
      if fields.close or fields.quit or fields.open_slotselect then turtle:stop_look_tracking(player_name) end
      if fields.arrow_forward then turtle:forward(true) end
      if fields.arrow_backward then turtle:back(true) end
      if fields.arrow_turnleft then turtle:turnLeft(true) end
      if fields.arrow_turnright then turtle:turnRight(true) end
      if fields.arrow_up then turtle:up(true) end
      if fields.arrow_down then turtle:down(true) end
      if fields.mine then turtle:dig(true) end
      if fields.mine_up then turtle:digUp(true) end
      if fields.mine_down then turtle:digDown(true) end
      if fields.place then turtle:place(true) end
      if fields.place_up then turtle:placeUp(true) end
      if fields.place_down then turtle:placeDown(true) end
      if fields.open_inventory then
        turtle:stop_look_tracking(player_name)
        turtle:open_inventory(player_name)
      end
      if fields.craft then
        turtle:craft(1)
        refresh(FORMNAME_TURTLE_CONTROLPANEL)
      end
      if fields.suck then turtle:suck(0) end
      if fields.drop then turtle:drop(0) end
      if fields.open_slotselect then
        turtle:open_slotselect(player_name)
      end
      return true
    elseif isForm(FORMNAME_TURTLE_SLOTSELECT) then
      for i = 1, TURTLE_INVENTORYSIZE do
        if fields["select_" .. i] then
          turtle:select(i)
          refresh(FORMNAME_TURTLE_SLOTSELECT)
        end
      end
      respond_to_common_controls()
      return true
    elseif isForm(FORMNAME_TURTLE_NOTYOURBOT) then
      if fields.ok_button then
        minetest.close_formspec(player_name, formname)
      end
    elseif isForm(FORMNAME_TURTLE_ACCESSCONTROL) then
      local add_member_input = fields.adabotaccess_add_member
      -- reset formspec until close button pressed
      if (fields.close_me or fields.quit) and (not add_member_input or add_member_input == "") then
        return false
      end
      -- only owner can add names
      if turtle.owner ~= player_name then
        return false
      end
      -- add faction members
      if factions_available and fields.faction_members ~= nil then
        turtle:set_allow_faction_members_access(fields.faction_members == "true")
      end
      -- add member [+]
      if add_member_input then
        for _, i in pairs(add_member_input:split(" ")) do
          turtle:add_member(i)
        end
      end
      -- remove member [x]
      for field, _ in pairs(fields) do
        if string.sub(field, 0,
          string.len("adabotaccess_del_member_")) == "adabotaccess_del_member_" then
          local disallowed_player = string.sub(field,string.len("adabotaccess_del_member_") + 1)
          turtle:del_member(disallowed_player)
        end
      end

      refresh(FORMNAME_TURTLE_ACCESSCONTROL)
      return true
    else
      return false -- Unknown formname, input not processed
    end
  end)

-- Code responsible for generating turtle entity and turtle interface

local TurtleEntity = {
  initial_properties = {
    is_visible = true,
    makes_footstep_sound = false,
    physical = true,
    collisionbox = {-0.5, -0.5, -0.5, 0.5, 0.5, 0.5},

    visual = "mesh",
    mesh = "turtle_base.b3d",
    textures = {"turtle_base_model_texture.png"},

    static_save = true, -- Make sure it gets saved statically
    automatic_rotate = 0,
    id = -1
  }
}

-- MAIN TURTLE HELPER FUNCTIONS------------------------------------------
function TurtleEntity:getTurtleslot(turtleslot)
  if not isValidInventoryIndex(turtleslot) then return nil end
  return self.inv:get_stack("main", turtleslot)
end

function TurtleEntity:setTurtleslot(turtleslot, stack)
  if not isValidInventoryIndex(turtleslot) then return false end
  self.inv:set_stack("main", turtleslot, stack)
  return true
end

function TurtleEntity:getToolInfo()
  local tool_stack = self.toolinv:get_stack("toolmain", 1)
  if tool_stack == nil then return nil end
  local table = tool_stack:to_table()
  if table == nil then return nil end
  local tool_name = table.name
  local tool_info = minetest.registered_items[tool_name]
  return tool_info
  -- return {"name": tool_name, "level": tool_info["tool_capabilities"]["max_drop_level"]}
end

function dump(o)
  if type(o) == 'table' then
    local s = '{ '
    for k, v in pairs(o) do
      if type(k) ~= 'number' then k = '"' .. k .. '"' end
      s = s .. '[' .. k .. '] = ' .. dump(v) .. ','
    end
    return s .. '} '
  else
    return tostring(o)
  end
end

-- checks if the location is blocked by any non-player objects
local function is_location_blocked_by_objects(nodeLocation)
  local objectsthere = minetest.get_objects_inside_radius(nodeLocation, 0.85)
  for _, object in ipairs(objectsthere) do
    local props = object:get_properties()
    if not object:is_player() and props ~= nil and props.collide_with_objects then
      return true
    end
  end
  return false
end

-- "walkable" actually means the player could stand on TOP of the node
-- and not fall. So if it returns true, that means the bot cannot move
-- into that node.
local function node_walkable(nodeLocation)
  if nodeLocation == nil then
    minetest.debug("Error: testing nil node for walkability")
    return false
  end
  local node = minetest.get_node(nodeLocation)
  local node_name = node.name
  local node_registration = minetest.registered_nodes[node_name]
  if node_registration.walkable then
    -- solid block the player could walk ON,
    -- the bot cannot enter it
    return true
  end
  if is_location_blocked_by_objects(nodeLocation) then
    return true
  end
  return false
end

-- returns true if the player could stand at the position
-- that means the node itself has to be air,
-- and also the node above it
local function player_can_stand_at(pos)
  local above = vector.new(pos.x, pos.y + 1, pos.z)
  return not node_walkable(pos) and not node_walkable(above)
end

-- returns true if the bot could stand on top of that location
-- i.e. either it is walkable by the player, or
-- there are blocking objects there, or there is a player there
local function bot_can_stand_on(pos)
  if node_walkable(pos) then
    return true
  end
  local players_there = get_players_at(pos)
  if #players_there > 0 then
    return true
  end
  return false
end

function Union(t1, t2)
  local handled_items = {}
  local output = {}
  for i = 1, #t1 do
    local item = t1[i]
    if handled_items[item] == nil then
      handled_items[item] = true
      output[#output + 1] = item
    end
  end
  for i = 1, #t2 do
    local item = t2[i]
    if handled_items[item] == nil then
      handled_items[item] = true
      output[#output + 1] = item
    end
  end
  return output
end

local function find_protector_owner_for(pos)
  local r = tonumber(minetest.settings:get("protector_radius")) or 5
  pos = minetest.find_nodes_in_area(
    {x = pos.x - r, y = pos.y - r, z = pos.z - r},
    {x = pos.x + r, y = pos.y + r, z = pos.z + r},
    {"protector:protect", "protector:protect2", "protector:protect_hidden"})
  for n = 1, #pos do
    local meta = minetest.get_meta(pos[n])
    local owner = meta:get_string("owner")
    return owner
  end
  return nil
end

function TurtleEntity:allowed_to_move_to(nodeLocation)
  if self:is_allowed_to_modify(nodeLocation) then
    return true
  end
  -- an exception; if you are already inside the protection area,
  -- we will allow you to keep moving to get out of the protection
  -- again (of that player).
  -- this is to prevent players placing a protection just to block
  -- your bot that is already there
  local currentLocation = self:get_pos()
  if not self:is_allowed_to_modify(currentLocation) then
    local current_protector_owner = find_protector_owner_for(currentLocation)
    local new_protector_owner = find_protector_owner_for(nodeLocation)
    if new_protector_owner == nil or  -- moving outside protection
      current_protector_owner == new_protector_owner or -- moving within same player's protection
      self:player_allowed_to_control_bot(new_protector_owner) -- into protection of Bot's own members
    then
      -- exception granted, you can keep moving until you're no longer
      -- inside that owner's protections
      return true
    end
  end
  return false
end

local function get_energy_cost_for_movement_delta(delta)
  if delta.y > 0 then
    return adabots.config.upward_energy_cost
  end
  if delta.y < 0 then
    return adabots.config.downward_energy_cost
  end
  return adabots.config.horizontal_energy_cost
end

function TurtleEntity:get_players_above_bot()
  local self_location = self.object:get_pos()
  local above = vector.new(self_location.x, self_location.y + 1.0, self_location.z)
  return get_players_at(above)
end

---check the bot has enough energy for the given cost,
---return true if so. If necessary, and autoRefuel enabled,
---do that first. Return false if not able to get the required energy
---@param energy_cost any
---@return boolean
function TurtleEntity:ensureEnergyFor(energy_cost)
  if self.autoRefuel then
    while not self:hasEnergyFor(energy_cost) do
      -- refuel_from_any_slot is called only after checking
      -- we don't have enough energy for the task at hand
      if not self:refuel_from_any_slot() then
        return false
      end
    end
  elseif not self:hasEnergyFor(energy_cost) then
    return false
  end
  return true
end

function TurtleEntity:move(nodeLocation)
  -- disallow movement while falling
  local acceleration = self.object:get_acceleration()
  if acceleration.y < -0.1 then
    return false
  end

  -- Verify new pos is empty
  if node_walkable(nodeLocation) then return false end
  if not self:allowed_to_move_to(nodeLocation) then return false end
  -- check we have energy
  local movement_delta = nodeLocation - self.object:get_pos()
  local energy_cost = get_energy_cost_for_movement_delta(movement_delta)
  if not self:ensureEnergyFor(energy_cost) then return false end

  -- Push player if present
  local below = vector.new(nodeLocation.x, nodeLocation.y - 1.0,
    nodeLocation.z)
  -- TODO make this more robustly push the player the right way
  -- so that you can't drop through when it is carrying you up,
  -- and so it always takes you along when you are on top of it
  local players_there = get_players_at(nodeLocation)
  local players_below = get_players_at(below)
  local players_to_push = Union(players_there, players_below)
  for _,player in ipairs(players_to_push) do
    -- if movement_delta.y > 0.9 then movement_delta.y = 1.2 end
    local new_player_pos = player:get_pos() + movement_delta
    -- disallow pushing player into walls
    if not player_can_stand_at(new_player_pos) then
      return false
    end
    player:move_to(new_player_pos, true)
  end

  -- Take Action
  if not self:useEnergy(energy_cost) then return false end
  self.object:move_to(nodeLocation, true)
  self:trigger_hover_check()
  return true
end

local function contains(list, x)
  for _, v in pairs(list) do if v == x then return true end end
  return false
end

local function is_supported_toolname(tool_name)
  if not contains(supported_tools, tool_name) then
    minetest.debug("Error: " .. tool_name ..
      " is not a supported Adabots turtle tool")
    return false
  end
  return true
end

local function get_remaining_uses(tool_name, wear_value)
  if not is_supported_toolname(tool_name) then return 0 end
  local total_uses = tool_usages[tool_name]
  local single_use = tool_wear_rates[tool_name]
  local spent_uses = round(wear_value / single_use)
  return total_uses - spent_uses
end

local function is_supported_tool(tool_info)
  local tool_name = tool_info["name"]
  return is_supported_toolname(tool_name)
end

local function get_tool_hardness(tool_info)
  if not is_supported_tool(tool_info) then return 0 end
  local capabilities = tool_info["tool_capabilities"]
  if capabilities == nil then return 0 end
  return capabilities["max_drop_level"]
end

local function get_node_hardness(node)
  local node_name = node.name
  local node_registration = minetest.registered_nodes[node_name]
  local hardness = node_registration["_mcl_hardness"]
  if hardness == nil then return 0 end
  return math.floor(hardness)
end

function TurtleEntity:pickaxe_can_dig(node)
  local tool_info = self:getToolInfo()
  if tool_info == nil then return false end
  local tool_hardness = get_tool_hardness(tool_info)
  local node_hardness = get_node_hardness(node)
  -- minetest.debug("Tool: " .. tool_hardness .. " vs node: " .. node_hardness)
  return tool_hardness >= node_hardness
end

function TurtleEntity:increment_tool_uses()
  local tool_stack = self.toolinv:get_stack("toolmain", 1)
  local table = tool_stack:to_table()
  local wear_increment = tool_wear_rates[table.name]
  if table.wear > 65535 - wear_increment then
    -- tool is spent
    self.toolinv:set_stack("toolmain", 1, nil)
    self:remove_pickaxe()
  else
    table.wear = table.wear + wear_increment -- must be <= 65535, the max value
    local new_tool_stack = ItemStack(table)
    self.toolinv:set_stack("toolmain", 1, new_tool_stack)
  end
end

function TurtleEntity:get_liquid_from(node_name)
  local registered_liquid = bucket.liquids[node_name]
  if registered_liquid == nil then return nil end
  if registered_liquid["source"] == node_name then return registered_liquid["itemname"] end
  return nil -- it's not the source, can't pick it up
end

function TurtleEntity:can_pickup_liquid()
  local stack = self:getTurtleslot(self.selected_slot)
  if stack == nil then
    return false
  end
  return stack:get_name() == "bucket:bucket_empty"
end

function TurtleEntity:mine(nodeLocation)
  if nodeLocation == nil then return false end
  local node = minetest.get_node(nodeLocation)
  if node.name == "air" then return false end
  if not self:is_allowed_to_modify(nodeLocation) then return false end

  if self:can_pickup_liquid() then
    local filled_bucket = self:get_liquid_from(node.name)
    if filled_bucket ~= nil then
      minetest.set_node(nodeLocation, {name="air"})
      local current_buckets = self.inv:get_stack("main", self.selected_slot)
      local num_buckets = current_buckets:get_count()
      self.inv:set_stack("main", self.selected_slot, filled_bucket)
      if num_buckets > 1 then
        current_buckets:set_count(num_buckets - 1)
        local leftover_stack = self:add_item(current_buckets)
        self:drop_items_in_world(leftover_stack)
      end
      return true
    end
  end

  -- check pickaxe strong enough
  if not self:pickaxe_can_dig(node) then return false end
  if not self:ensureEnergyFor(adabots.config.mine_energy_cost) then return false end
  if override_protection(function () return minetest.dig_node(nodeLocation) end) then
    if not self:useEnergy(adabots.config.mine_energy_cost) then return false end
    self:increment_tool_uses()
    return true
  else
    return false
  end
end

function TurtleEntity:pickup(stack)
  if self.inv:room_for_item("main", stack) then
    self.inv:add_item("main", stack)
    return true
  else
    return false
  end
end

function TurtleEntity:is_adabots_turtle()
  return true
end

function TurtleEntity:is_player()
  return false
end

function TurtleEntity:get_owner()
  return self.owner
end

function TurtleEntity:get_player_name()
  return self.name
end

function TurtleEntity:get_player_control()
  return {["sneak"]=false}
end

local function get_decoration_from_item(item_name)
  for _, decoration in pairs(minetest.registered_decorations) do
    if decoration["decoration"] == item_name then
      return decoration
    end
  end
  return nil
end

function TurtleEntity:get_players_that_can_control_bot()
  local players = deepcopy(self.allowed_players)
  if players == nil then players = {} end
  table.insert(players, self.owner)
  -- if factions_available and self.allow_faction_access then
  -- -- TODO add all players in the owner's factions
  -- end
  return players
end

function TurtleEntity:is_allowed_to_modify(nodeLocation)
  for _, player in ipairs(self:get_players_that_can_control_bot()) do
    if minetest.is_protected(nodeLocation, player) then
      return false
    end
  end
  return true
end

function TurtleEntity:build(nodeLocation)
  local stack = self:getTurtleslot(self.selected_slot)
  if stack == nil then
    return false
  end
  if not self:is_allowed_to_modify(nodeLocation) then
    return false
  end
  if stack:is_empty() then return false end
  local item_name = stack:get_name()
  local item_registration = minetest.registered_items[item_name]
  local decoration = get_decoration_from_item(item_name)
  if decoration ~= nil then
    nodeLocation = {
      ["x"] = nodeLocation.x,
      ["y"] = nodeLocation.y + (decoration["place_offset_y"] or 0),
      ["z"] = nodeLocation.z
    }
  end
  if not self:ensureEnergyFor(adabots.config.build_energy_cost) then return false end
  local newstack = override_protection(function () return item_registration.on_place(stack, nil, {
    type = "node",
    under = nodeLocation,
    above = nodeLocation
  }) end)
  if newstack == nil then
    return false
  end
  if not self:useEnergy(adabots.config.build_energy_cost) then return false end
  self.inv:set_stack("main", self.selected_slot, newstack)
  return true
end

function TurtleEntity:inspectnode(nodeLocation)
  local result = minetest.get_node(nodeLocation)
  return result.name
end

-- Get items loose in the world, up to maxAmount (pass 0 for infinite)
-- Put them into the turtle inventory at the first viable location starting
-- from the selected slot.
-- Returns true if any items were retrieved
-- Returns false only if unable to get any items
function TurtleEntity:gather_items(nodeLocation, maxAmount)
  local picked_up_items = 0
  local objectlist = minetest.get_objects_inside_radius(nodeLocation, 1)
  for i = 1, #objectlist do
    local object = objectlist[i]
    local ent = object:get_luaentity()
    if ent then
      local itemstring = ent.itemstring
      if itemstring and itemstring ~= "" then
        local item = ItemStack(itemstring)
        if self:pickup(item) then
          picked_up_items = picked_up_items + 1
          object:remove() -- remove object floating in the world
          if maxAmount > 0 and picked_up_items >= maxAmount then
            return true
          end
        end
      end
    end
  end
  return picked_up_items > 0
end

-- Add the stack to the first available slot starting at the selected slot
-- return a stack of the items that could not fit
function TurtleEntity:add_item(stack)
  local slots = {}
  for i = 0, TURTLE_INVENTORYSIZE - 1 do
    local slot = ((self.selected_slot + i - 1) % TURTLE_INVENTORYSIZE) + 1
    slots[#slots + 1] = slot
  end
  return self:add_item_to_slots(stack, slots)
end

function TurtleEntity:add_item_to_slots(stack, slots)
  local leftover_stack = stack
  for i = 1, #slots, 1 do
    local slot = slots[i]
    local current_stack = self.inv:get_stack("main", slot)
    if current_stack == nil then
      minetest.debug("Error: turtle slot " .. slot .. " has nil stack")
      return leftover_stack
    end
    leftover_stack = current_stack:add_item(leftover_stack)
    self.inv:set_stack("main", slot, current_stack)
    if leftover_stack:get_count() == 0 then return leftover_stack end
  end
  return leftover_stack
end

-- Get items from an inventory (e.g. chest / furnace)
-- or loose in the world if there's no inventory
-- at the nodeLocation given. As many items as possible are retrieved,
-- up to the amount specified.
-- Pass 1 iteratively for more precision, or pass 0 to retrieve infinite items.
-- If loose items are present, only those are picked up.
-- Put them into the turtle inventory at the first viable location starting
-- from the selected slot.
-- Returns true if any items were retrieved
-- Returns false only if unable to get any items
function TurtleEntity:sucknode(nodeLocation, maxAmount)
  local inventory = minetest.get_inventory({type = "node", pos = nodeLocation})
  if inventory ~= nil then return self:suck_from_inventory_at(nodeLocation, maxAmount) end
  return self:gather_items(nodeLocation, maxAmount)
end

-- returns list of inventories to suck from that node
-- the list is ordered, so that the turtle will only suck
-- from the next inventory in the list when the previous ones
-- came up empty.
function TurtleEntity:get_inventories_to_suck_from(nodeLocation)
  local node = minetest.get_node(nodeLocation)
  if furnace_node_types[node.name] ~= nil then
    return {"dst", "src", "fuel"}
  end
  return {"main"}
end

-- see sucknode for behaviour
-- only difference is that this function will not pick up loose items in the world
-- but only suck from the inventory at that location
function TurtleEntity:suck_from_inventory_at(nodeLocation, maxAmount)
  local inventory = minetest.get_inventory({type = "node", pos = nodeLocation})
  if inventory == nil then return false end

  local inventory_lists = self:get_inventories_to_suck_from(nodeLocation)
  for _, inventory_listname in ipairs(inventory_lists) do
    if self:suck_from_inventory_list_at(inventory, maxAmount, inventory_listname) then
      return true
    end
  end
  return false
end

-- take items from the list in the inventory specified
-- return whether we were able to grab any items from that list
function TurtleEntity:suck_from_inventory_list_at(inventory, maxAmount, inventory_listname)
  local inventorysize = inventory:get_size(inventory_listname)

  local remaining_items = maxAmount -- can't directly modify maxAmount because 0 means 'take infinite'
  local picked_up_items = 0
  for i = 1, inventorysize do
    local inventory_stack = inventory:get_stack(inventory_listname, i)
    if inventory_stack == nil then
      minetest.debug("unexpected error in sucknode: stack is nil")
      return false
    end

    local stack_count = inventory_stack:get_count()
    if stack_count > 0 then
      -- do you want the whole stack?
      if maxAmount == 0 or stack_count <= remaining_items then
        local remaining_stack = self:add_item(inventory_stack)
        local remaining_count = remaining_stack:get_count()
        local picked_up_this_iteration = stack_count - remaining_count
        picked_up_items = picked_up_items + picked_up_this_iteration
        inventory:set_stack(inventory_listname, i, remaining_stack)
        remaining_items = remaining_items - picked_up_this_iteration
      else
        local remaining_count = stack_count - remaining_items
        local stack_to_add = inventory_stack
        stack_to_add:set_count(remaining_items)
        local leftover_stack = self:add_item(stack_to_add)
        -- leftover_itemcount is normally 0, otherwise it means we couldn't fit the desired amount from this inventory stack
        local leftover_itemcount = leftover_stack:get_count()
        local picked_up_this_iteration = remaining_count -
        leftover_itemcount
        picked_up_items = picked_up_items + picked_up_this_iteration
        local remaining_stack = inventory_stack
        remaining_stack:set_count(remaining_count + leftover_itemcount)
        inventory:set_stack(inventory_listname, i, remaining_stack)
        remaining_items = remaining_items - picked_up_this_iteration
      end
      -- if we asked for a specific amount and that amount has been met, return true
      if maxAmount ~= 0 and remaining_items == 0 then return true end
      -- if we asked for any amount and we have picked up anything (as much as fit from 1 stack), return true
      if maxAmount == 0 and picked_up_items > 0 then return true end
    end
  end

  return picked_up_items > 0
end

function TurtleEntity:detectnode(nodeLocation)
  return node_walkable(nodeLocation)
end

function TurtleEntity:get_inv_to_drop_into(item_name, node_name)
  if furnace_node_types[node_name] ~= nil then
    local item = minetest.registered_items[item_name]
    if item["groups"]["flammable"] ~= nil then
      return "fuel"
    end
    return "src"
  end
  return "main"
end

function TurtleEntity:drop_into_inventory(nodeLocation, inventory, item_name, drop_amount)
  local node = minetest.get_node(nodeLocation)
  local node_name = node["name"]
  local inv_stack = ItemStack(item_name)
  inv_stack:set_count(drop_amount)
  local inventory_id = self:get_inv_to_drop_into(item_name, node_name)
  local remainingItemStack = inventory:add_item(inventory_id, inv_stack)
  -- start timer for the furnace to check if it should turn on
  minetest.get_node_timer(nodeLocation):start(1.0)
  return remainingItemStack
end

function TurtleEntity:drop_into_world(nodeLocation, item_name, amount)
  if amount <= 0 then
    return
  end
  -- add items to world
  for _ = 1, amount do
    minetest.add_item(nodeLocation, item_name)
  end
end

function TurtleEntity:itemDrop(nodeLocation, amount)
  local stack = self:getTurtleslot(self.selected_slot)
  if stack == nil then
    minetest.log("error", "turtleslot " .. self.selected_slot .. " has nil stack")
    return false
  end
  if stack:is_empty() then return false end
  local drop_amount = amount
  if amount == 0 or stack:get_count() < amount then
    drop_amount = stack:get_count()
  end

  -- dump items
  local item_name = stack:to_table().name
  -- check for inventory
  local inventory = minetest.get_inventory({type = "node", pos = nodeLocation})
  local remainingStack = nil
  if inventory then
    remainingStack = self:drop_into_inventory(nodeLocation, inventory, item_name, drop_amount)
  else
    -- dropping into world always drops everything
    self:drop_into_world(nodeLocation, item_name, drop_amount)
    remainingStack = ItemStack("")
  end
  self.inv:set_stack("main", self.selected_slot, remainingStack)
  return true
end

--- Pushes a single turtleslot, unfiltered
--- @returns true if stack completely pushed
function TurtleEntity:itemPushTurtleslot(nodeLocation, turtleslot, listname)
  listname = listname or "main"
  local nodeInventory = minetest.get_inventory({
    type = "node",
    pos = nodeLocation
  }) -- InvRef
  if not nodeInventory then
    return false -- If no node inventory (Ex: Not a chest)
  end
  -- Try putting my stack somewhere
  local toPush = self:getTurtleslot(turtleslot)
  if toPush == nil then
    return false
  end
  local remainingItemStack = nodeInventory:add_item(listname, toPush)
  self:setTurtleslot(turtleslot, remainingItemStack)
  return remainingItemStack:is_empty()
end

-- MAIN TURTLE USER INTERFACE------------------------------------------
function TurtleEntity:get_formspec_inventory(player_name)
  local turtle_inv_x = 5
  local turtle_inv_y = 0.4
  local selected_x = ((self.selected_slot - 1) % 4) + turtle_inv_x
  local selected_y = math.floor((self.selected_slot - 1) / 4) + turtle_inv_y
  local listening = self.is_listening
  local sleeping_image = ""
  local playpause_image = "pause_btn.png"
  if not listening then
    sleeping_image = "image[0.9,0.12;0.6,0.6;zzz.png]"
    playpause_image = "play_btn.png"
  end
  local general_settings = "size[9,9.25]" .. "options[key_event=true]" ..
  "background[-0.19,-0.25;9.41,9.49;turtle_inventory_bg.png]"
  local turtle_image = "set_focus[listen;true]" ..
  "image[0,0;2,2;turtle_icon.png]" .. sleeping_image

  local turtle_name = "style_type[field;font_size=26]" ..
  "field[2.03,0.8;3,1;name;AdaBot name;" .. F(self.name) .. "]"

  local fuel_level = math.min(math.max(0, self.energy / adabots.config.energy_max), 1)
  local nonfull_fuel_images = 29
  -- even linear distribution so that the max image has an equal range
  local index = math.min(math.floor(fuel_level * (nonfull_fuel_images+1)), nonfull_fuel_images)
  local fuelbutton_suffix = tostring(index)
  local active = ""
  if self.autoRefuel then
    active = "active_"
  end
  local autorefuel_img = "image[0.98,3.38;1.04,1.04;button_" .. active .. "outline.png]"
  local refuel_button = "image_button[1,3.4;1,0.96;refuel_" .. fuelbutton_suffix .. ".png;refuel;]tooltip[refuel;Refuel / toggle autoRefuel]"
  local refueling = autorefuel_img .. refuel_button

  local playpause_button = "image_button[4,2.2;1,1;" .. playpause_image ..
  ";listen;]tooltip[listen;Start/stop listening]"

  local tool_label =
  "label[0,2.95;Tool]"
  local tool_bg = mcl_formspec.get_itemslot_bg(0, 3.4, 1, 1)
  local tool_inventory_slot = "list[" .. self.toolinv_fullname ..
  ";toolmain;0,3.4;1,1;]"
  local tool = tool_label .. tool_bg .. tool_inventory_slot
  local access_control_button = ""
  if self.owner == player_name then
    access_control_button = "image_button[3,3.4;1,1;lock.png;access_control;]tooltip[access_control;Set allowed players]"
  end
  local controlpanel_button =
  "image_button[4,3.4;1,1;open_controlpanel.png;open_controlpanel;]" ..
  "tooltip[open_controlpanel;Open controlpanel]"

  local connection_settings = "style_type[field;font_size=16]" ..
  "label[0.3,1.74;Workspace]" .. "dropdown[0,2.2;4.0;workspace;" ..
  table.concat(adabots.get_workspace_names(),
    ",") .. ";" ..
  self:get_workspace_index() .. ";true]"

  local turtle_inventory = "label[" .. turtle_inv_x .. "," .. turtle_inv_y -
  0.55 .. ";AdaBot Inventory]" ..
  mcl_formspec.get_itemslot_bg(turtle_inv_x,
    turtle_inv_y, 4, 4)

  local turtle_selection = "background[" .. selected_x .. "," .. selected_y -
  0.05 ..
  ";1,1.1;mcl_inventory_hotbar_selected.png]"

  local turtle_inventory_items = "list[" .. self.inv_fullname .. ";main;" ..
  turtle_inv_x .. "," .. turtle_inv_y ..
  ";4,4;]"

  local player_inventory = "label[0,4.5;Player Inventory]" ..
  mcl_formspec.get_itemslot_bg(0, 5.0, 9, 3) ..
  mcl_formspec.get_itemslot_bg(0, 8.24, 9, 1)

  local player_inventory_items = "list[current_player;main;0,5.0;9,3;9]" ..
  "list[current_player;main;0,8.24;9,1;0]"

  return
    general_settings .. turtle_image .. turtle_name .. refueling .. playpause_button ..
    tool .. access_control_button .. controlpanel_button .. connection_settings ..
    turtle_inventory .. turtle_selection .. turtle_inventory_items ..
    player_inventory .. player_inventory_items
end

local function render_buttons(start, button_table)
  local buttons = ""
  for i = 1, #button_table do
    local b = button_table[i]
    buttons = buttons .. "image_button[" .. start.x + b.offset.x .. "," ..
    start.y + b.offset.y .. ';1,1;' .. b.name .. ".png;" ..
    b.name .. ";]" .. "tooltip[" .. b.name .. ";" .. b.tooltip ..
    "]"
  end
  return buttons
end

function TurtleEntity:get_workspace_index()
  if self.workspace == nil then
    return 0
  end
  local index = 1
  for _, workspace in ipairs(adabots.workspaces) do
    if workspace["id"] == self.workspace["id"] then return index end
    index = index + 1
  end
  -- minetest.debug("Error: Current workspace not in list! " ..
  --                    dump(self.workspace))
  return 0
end

function TurtleEntity:select_workspace(index)
  local index = tonumber(index)
  local i = 1
  for _, workspace in ipairs(adabots.workspaces) do
    if i == index then
      self.workspace = workspace
      return
    end
    print(i .. " != " .. index)
    i = i + 1
  end
  minetest.debug(
    "Error: index " .. index .. " out of range for workspaces: " ..
    dump(adabots.workspaces))
end

function TurtleEntity:get_formspec_controlpanel()
  local general_settings = "formspec_version[4]" .. "size[26,12]" ..
  "no_prepend[]" .. "bgcolor[#00000000]" ..
  "background[0,0;25,12;controlpanel_bg.png]" ..
  "style_type[button;noclip=true]"

  --
  -- X  ↑  ↟  ⇑  ⇈  c
  -- ↶     ↷  m  p
  -- ↖  ↓  ↡  ⇓  ⇊

  local start = {['x'] = 18.65, ['y'] = 7.6}

  local craft_tooltip = 'Craft ' .. self:peek_craft_result()
  local button_table = {
    {
      ['name'] = 'close',
      ['offset'] = {['x'] = 0, ['y'] = 1},
      ['tooltip'] = 'Close'
    }, {
      ['name'] = 'arrow_forward',
      ['offset'] = {['x'] = 1, ['y'] = 1},
      ['tooltip'] = 'Move forward'
    }, {
      ['name'] = 'arrow_backward',
      ['offset'] = {['x'] = 1, ['y'] = 3},
      ['tooltip'] = 'Move backward'
    }, {
      ['name'] = 'arrow_turnleft',
      ['offset'] = {['x'] = 0, ['y'] = 2},
      ['tooltip'] = 'Turn left'
    }, {
      ['name'] = 'arrow_turnright',
      ['offset'] = {['x'] = 2, ['y'] = 2},
      ['tooltip'] = 'Turn right'
    }, {
      ['name'] = 'arrow_up',
      ['offset'] = {['x'] = 2, ['y'] = 1},
      ['tooltip'] = 'Move up'
    }, {
      ['name'] = 'arrow_down',
      ['offset'] = {['x'] = 2, ['y'] = 3},
      ['tooltip'] = 'Move down'
    }, {
      ['name'] = 'mine_up',
      ['offset'] = {['x'] = 3, ['y'] = 1},
      ['tooltip'] = 'Dig up'
    }, {
      ['name'] = 'mine',
      ['offset'] = {['x'] = 3, ['y'] = 2},
      ['tooltip'] = 'Dig forward'
    }, {
      ['name'] = 'mine_down',
      ['offset'] = {['x'] = 3, ['y'] = 3},
      ['tooltip'] = 'Dig down'
    }, {
      ['name'] = 'place_up',
      ['offset'] = {['x'] = 4, ['y'] = 1},
      ['tooltip'] = 'Place up'
    }, {
      ['name'] = 'place',
      ['offset'] = {['x'] = 4, ['y'] = 2},
      ['tooltip'] = 'Place forward'
    }, {
      ['name'] = 'place_down',
      ['offset'] = {['x'] = 4, ['y'] = 3},
      ['tooltip'] = 'Place down'
    }, {
      ['name'] = 'open_inventory',
      ['offset'] = {['x'] = 0, ['y'] = 3},
      ['tooltip'] = 'Open inventory'
    }, {
      ['name'] = 'open_slotselect',
      ['offset'] = {['x'] = 1, ['y'] = 2},
      ['tooltip'] = 'Select slot'
    }, {
      ['name'] = 'craft',
      ['offset'] = {['x'] = 5, ['y'] = 1},
      ['tooltip'] = craft_tooltip
    }, {
      ['name'] = 'suck',
      ['offset'] = {['x'] = 5, ['y'] = 2},
      ['tooltip'] = 'Suck'
    }, {
      ['name'] = 'drop',
      ['offset'] = {['x'] = 5, ['y'] = 3},
      ['tooltip'] = 'Drop'
    }
  }

  local buttons = render_buttons(start, button_table)

  return general_settings .. buttons
end

function TurtleEntity:del_member(name)
  for i, n in pairs(self.allowed_players) do
    if n == name then
      table.remove(self.allowed_players, i)
      break
    end
  end
end

-- add player name to list of members that are
-- allowed access to control the bot
function TurtleEntity:add_member(name)
  -- Validate player name for MT compliance
  if name ~= string.match(name, "[%w_-]+") then
    return
  end

  -- Constant (20) defined by player.h
  if name:len() > 25 then
    return
  end

  -- does name already exist?
  if self.owner == name or self:is_member(name) then
    return
  end

  local members = self.allowed_players or {}
  if #members >= botaccess_max_share_count then
    return
  end

  table.insert(members, name)
  self.allowed_players = members
end

function TurtleEntity:set_allow_faction_members_access(allow_faction_access)
  self.allow_faction_access = allow_faction_access
end

function TurtleEntity:is_member(name)
  if factions_available
    and self.allow_faction_access then
    if factions.version == nil then
      -- backward compatibility
      if factions.get_player_faction(name) ~= nil
        and factions.get_player_faction(self.owner) ==
        factions.get_player_faction(name) then
        return true
      end
    else
      -- is member if player and owner share at least one faction
      local player_factions = factions.get_player_factions(name)
      local owner = self.owner

      if player_factions ~= nil and player_factions ~= false then
        for _, f in ipairs(player_factions) do
          if factions.player_is_in_faction(f, owner) then
            return true
          end
        end
      end
    end
  end

  local members = self.allowed_players or {}
  for _, n in pairs(members) do
    if n == name then
      return true
    end
  end

  return false
end

function TurtleEntity:get_formspec_accesscontrol()
  local formspec = "size[8,7]"
  .. default.gui_bg
  .. default.gui_bg_img
  .. "label[2.5,0;" .. F(S("Access control") .. " for bot " .. self.name) .. "]"
  .. "label[0,2;" .. F(S("Allowed players:")) .. "]"
  .. "button_exit[2.5,6.2;3,0.5;close_me;" .. F(S("Close")) .. "]"
  .. "field_close_on_enter[adabotaccess_add_member;false]"

  local members = self.allowed_players or {}
  local npp = botaccess_max_share_count -- max users added to protector list
  local checkbox_faction = false

  -- Display the checkbox only if the owner is member of at least 1 faction
  if factions_available then
    if factions.version == nil then
      -- backward compatibility
      if factions.get_player_faction(self.owner) then
        checkbox_faction = true
      end
    else
      local player_factions = factions.get_player_factions(self.owner)
      if player_factions ~= nil and #player_factions >= 1 then
        checkbox_faction = true
      end
    end
  end
  if checkbox_faction then
    formspec = formspec .. "checkbox[0,5;faction_members;"
    .. F(S("Allow faction access"))
    .. ";" .. (meta:get_int("faction_members") == 1 and
    "true" or "false") .. "]"
    if npp > 8 then
      npp = 8
    end
  end

  local i = 0
  for n = 1, #members do
    if i < npp then
      -- show username
      formspec = formspec .. "button[" .. (i % 4 * 2)
      .. "," .. math.floor(i / 4 + 3)
      .. ";1.5,.5;adabotaccess_member;" .. F(members[n]) .. "]"
      -- username remove button
      .. "button[" .. (i % 4 * 2 + 1.25) .. ","
      .. math.floor(i / 4 + 3)
      .. ";.75,.5;adabotaccess_del_member_" .. F(members[n]) .. ";X]"
    end
    i = i + 1
  end

  if i < npp then
    -- user name entry field
    formspec = formspec .. "field[" .. (i % 4 * 2 + 1 / 3) .. ","
    .. (math.floor(i / 4 + 3) + 1 / 3)
    .. ";1.433,.5;adabotaccess_add_member;;]"
    -- username add button
    .."button[" .. (i % 4 * 2 + 1.25) .. ","
    .. math.floor(i / 4 + 3) .. ";.75,.5;adabotaccess_submit;+]"
  end

  return formspec
end

function TurtleEntity:get_formspec_slotselect()
  local general_settings = "formspec_version[4]" .. "size[25,12]" ..
  "no_prepend[]" .. "bgcolor[#00000000]" ..
  "background[0,0;25,12;slotselect_bg.png]" ..
  "style_type[button;noclip=true]"

  -- X  1  2  3  4
  -- ↘  5  6  7  8
  --    9  10 11 12
  --    13 14 15 16

  local start = {['x'] = 19.6, ['y'] = 7.6}
  local button_table = {
    {
      ['name'] = 'close',
      ['offset'] = {['x'] = 0, ['y'] = 0},
      ['tooltip'] = 'Close'
    }, {
      ['name'] = 'open_controlpanel',
      ['offset'] = {['x'] = 0, ['y'] = 1},
      ['tooltip'] = 'Open controlpanel'
    }
  }
  local buttons = render_buttons(start, button_table)

  local selected_x = ((self.selected_slot - 1) % 4) + start.x + 1
  local selected_y = math.floor((self.selected_slot - 1) / 4) + start.y + 0.02

  local turtle_selection = "background[" .. selected_x .. "," .. selected_y -
  0.02 ..
  ";1.1,1.1;mcl_inventory_hotbar_selected.png]"

  local slot_tiles = ""
  for i = 1, TURTLE_INVENTORYSIZE do
    local x = ((i - 1) % 4) + start.x + 1.1
    local y = math.floor((i - 1) / 4) + start.y + 0.1
    local stack = self.inv:get_stack("main", i)
    local stack_tooltip = stack:get_short_description()
    local stack_name = stack:get_name()
    local button = "item_image_button[" .. x .. "," .. y .. ";0.9,0.9;" ..
    stack_name .. ";select_" .. i .. ";]"
    local tooltip =
    "tooltip[select_" .. i .. ";Select slot " .. i .. " (" ..
    stack_tooltip .. ")]"
    local amount = stack:get_count()
    local itemcount = ""
    if amount > 1 then
      local amountstring = tostring(amount)
      if amount < 10 then
        -- move it over a little so it looks right-aligned
        -- https://github.com/minetest/minetest/issues/7613
        x = x + 0.18
      end
      itemcount = "label[" .. x + 0.5 .. "," .. y + 0.7 .. ";" .. amountstring ..  "]"
    end
    slot_tiles = slot_tiles .. button .. tooltip .. itemcount
  end

  return general_settings .. buttons .. slot_tiles .. turtle_selection
end

function TurtleEntity:get_formspec_notyourbot()
  local general_settings = "size[9,9.25]" .. "options[key_event=true]" ..
  "background[-0.19,-0.25;9.41,9.49;turtle_inventory_bg.png]"
  local owner_name = self.owner
  if owner_name == nil then
    owner_name = "nil"
    minetest.log("error", "[adabots] : opening formspec for nil owner bot")
  end
  local style = "style_type[label;font=bold]"
  local locked = "label[3.5,1.0;" .. F(minetest.colorize("#FF0000", "LOCKED")) .. "]"
  local unstyle = "style_type[label;font=]"
  local lock_image = "image[3.6,0;1.25,1.25;lock.png;false]"
  local not_your_bot = "label[2.0,1.5;You cannot control " .. self.name .. ".]"
  local belongs_to = "label[2.0,2.0;This bot belongs to " .. owner_name .. ".]"
  local ask_access = "label[2.0,2.5;You can ask " .. owner_name .. " to grant you access]"
  local craft_own = "label[2.0,3.0;or you can craft your own:]"
  local craft_recipe = "image[1.0,3.8;8.5,5;turtle_craft_recipe.png;false]"
  local ok_button = "button[3.0,8.5;3,0.6;ok_button;OK]"
  return general_settings .. style .. locked .. unstyle .. lock_image ..
    not_your_bot .. belongs_to .. ask_access .. craft_own .. craft_recipe .. ok_button
end

-- Called when a player wants to put something into tool inventory.
-- Return value: number of items allowed to put.
-- Return value -1: Allow and don't modify item count in inventory.
function TurtleEntity:toolinv_allow_put(inv, listname, index, stack, player)
  local player_name = player:get_player_name()
  if not self:player_allowed_to_control_bot(player_name) then
    return 0
  end
  if is_supported_toolname(stack:get_name()) then
    return 1
  else
    return 0
  end
end

-- Called when a player wants to take something from the tool inventory.
-- Return value: number of items allowed to take.
-- Return value -1: Allow and don't modify item count in inventory.
function TurtleEntity:toolinv_allow_take(inv, listname, index, stack, player)
  local player_name = player:get_player_name()
  if not self:player_allowed_to_control_bot(player_name) then
    return 0
  end
  return 1
end

-- Called when a player wants to put something in the bot inventory.
-- Return value: number of items allowed to put.
-- Return value -1: Allow and don't modify item count in inventory.
function TurtleEntity:inv_allow_put(inv, listname, index, stack, player)
  local player_name = player:get_player_name()
  if not self:player_allowed_to_control_bot(player_name) then
    return 0
  end
  return 999
end

-- Called when a player wants to take something from the bot inventory.
-- Return value: number of items allowed to put.
-- Return value -1: Allow and don't modify item count in inventory.
function TurtleEntity:inv_allow_take(inv, listname, index, stack, player)
  local player_name = player:get_player_name()
  if not self:player_allowed_to_control_bot(player_name) then
    return 0
  end
  return 999
end

function TurtleEntity:toolinv_on_put(inv, listname, index, stack, player)
  self:refresh_pickaxe()
end

function TurtleEntity:toolinv_on_take(inv, listname, index, stack, player)
  self:refresh_pickaxe()
end

-- https://rosettacode.org/wiki/Partial_function_application#Lua
local function partial(f, arg) return function(...) return f(arg, ...) end end

-- MAIN TURTLE ENTITY FUNCTIONS------------------------------------------
function TurtleEntity:on_activate(staticdata, dtime_s)
  local data = minetest.deserialize(staticdata)
  if type(data) ~= "table" then data = {} end
  -- Give ID
  adabots.num_turtles = adabots.num_turtles + 1
  self.id = adabots.num_turtles
  self.name = data.name or "Bob"
  self.workspace = data.workspace
  self.is_listening = data.is_listening or false
  self.owner = data.owner
  self.heading = data.heading or 0
  self.energy = data.energy or adabots.config.energy_initial
  self.selected_slot = data.selected_slot or 1
  self.autoRefuel = data.autoRefuel
  if self.autoRefuel == nil then self.autoRefuel = true end
  self.allowed_players = minetest.deserialize(data.allowed_players or "{}")
  self.allow_faction_access = data.allow_faction_access or false

  -- Create inventory
  self.inv_name = "adabots:turtle:" .. self.id
  self.inv_fullname = "detached:" .. self.inv_name
  self.inv = minetest.create_detached_inventory(self.inv_name, {
    allow_put = partial(TurtleEntity.inv_allow_put, self),
    allow_take = partial(TurtleEntity.inv_allow_take, self)
  })
  if self.inv == nil or self.inv == false then
    error("Could not spawn inventory")
  end

  -- Create inventory for tool
  self.toolinv_name = "adabots:turtle_tool:" .. self.id
  self.toolinv_fullname = "detached:" .. self.toolinv_name
  self.toolinv = minetest.create_detached_inventory(self.toolinv_name, {
    allow_put = partial(TurtleEntity.toolinv_allow_put, self),
    allow_take = partial(TurtleEntity.toolinv_allow_take, self),
    on_put = partial(TurtleEntity.toolinv_on_put, self),
    on_take = partial(TurtleEntity.toolinv_on_take, self)
  })
  if self.toolinv == nil or self.toolinv == false then
    error("Could not spawn tool inventory")
  end

  -- Reset state
  self.state = "standby"

  -- Restart listening
  if self.is_listening then
    self:listen()
    self:setAwakeTexture()
  else
    self:setSleepingTexture()
  end

  self:update_nametag()

  -- Keep items from save
  if data.inv ~= nil then deserializeInventory(self.inv, data.inv) end
  self.inv:set_size("main", TURTLE_INVENTORYSIZE)
  if data.toolinv ~= nil then
    deserializeInventory(self.toolinv, data.toolinv)
  end
  self.toolinv:set_size("toolmain", 1)

  -- Add to turtle list
  adabots.turtles[self.id] = self

  self:add_pickaxe_model()
end

function TurtleEntity:refresh_pickaxe()
  self:remove_pickaxe()
  self:add_pickaxe_model()
end

local function get_pickaxe_entity_name(tool_name)
  -- mcl_tools:pick_wood => adabots:pick_wood
  -- default:pick_wood => adabots:pick_wood
  return tool_name:gsub("^.*:", "adabots:")
end

function TurtleEntity:add_pickaxe_model()
  local tool_info = self:getToolInfo()
  if tool_info == nil then return end
  if not is_supported_tool(tool_info) then return end
  local tool_name = tool_info["name"]
  -- minetest.debug("Tool name: " .. tool_name)
  local pickaxe_entity = get_pickaxe_entity_name(tool_name)
  self.pickaxe = minetest.add_entity({x = 0, y = 0, z = 0}, pickaxe_entity)
  local relative_position = {x = 0, y = 0, z = 0}
  local relative_rotation = {x = 0, y = 0, z = 0}
  self.pickaxe:set_attach(self.object, "", relative_position,
    relative_rotation)
end

function TurtleEntity:remove_pickaxe()
  if self.pickaxe ~= nil then self.pickaxe:remove() end
end

function TurtleEntity:on_deactivate() self:remove_pickaxe() end

function TurtleEntity:is_hovering()
  local pos = self:get_pos()
  local below = vector.new(pos.x, pos.y - 1.0, pos.z)
  -- if we can't stand on the node we're standing on,
  -- then we're hovering
  return not bot_can_stand_on(below)
end

-- fall to the ground
function TurtleEntity:fall_down()
  self.object:set_acceleration({x=0,y=-9.81,z=0})
end

-- check every 0.3 s whether we hit the ground, in
-- which case we set acceleration to 0
function TurtleEntity:ground_check_tick(dtime)
  if not self.wait_since_last_ground_check then self.wait_since_last_ground_check = 0 end
  self.wait_since_last_ground_check = self.wait_since_last_ground_check + dtime
  if self.wait_since_last_ground_check >= 0.3 then
    self.wait_since_last_ground_check = 0
    if not self:is_hovering() then
      self.object:set_acceleration({x=0,y=0,z=0})
    end
  end
end

-- consume hover energy for every second
-- the bot is floating
function TurtleEntity:hover_tick(dtime)
  if not self.wait_since_last_hover_consume then self.wait_since_last_hover_consume = 0 end
  self.wait_since_last_hover_consume = self.wait_since_last_hover_consume + dtime
  if self.wait_since_last_hover_consume >= 1 then
    self.wait_since_last_hover_consume = 0
    if self:is_hovering() then
      local hover_success = self:useEnergy(adabots.config.hover_energy_cost)
      if not hover_success then
        self:fall_down()
      end
    end
  end
end

-- the wait time is reset on every movement,
-- so that the time it takes to fall down when empty
-- is consistent
function TurtleEntity:trigger_hover_check()
  self.wait_since_last_hover_consume = 1
end

function TurtleEntity:start_look_tracking(player_name)
  if self.players_look_tracking == nil then
    self.players_look_tracking = {}
  end
  for _,name in ipairs(self.players_look_tracking) do
    if name == player_name then
      return
    end
  end
  self.players_look_tracking[#self.players_look_tracking+1] = player_name
  -- minetest.log("Players tracking: " .. dump(self.players_look_tracking))
end

function TurtleEntity:stop_look_tracking(player_name)
  if self.players_look_tracking == nil then
    return
  end
  for i, name in ipairs(self.players_look_tracking) do
    if name == player_name then
      table.remove(self.players_look_tracking, i)
      break
    end
  end
  -- minetest.log("Players tracking: " .. dump(self.players_look_tracking))
end

-- from https://github.com/minetest/minetest/issues/8868#issuecomment-526399859
local function get_player_head_pos(player)
  local pos = vector.add(player:get_pos(), player:get_eye_offset())
  pos.y = pos.y + player:get_properties().eye_height
  return pos
end

-- see also https://github.com/minetest/minetest/commit/fa0bbbf96df17f0d7911274ea85e5c049c20d07b
-- the old player:get_look_yaw/pitch() are deprecated because they were quite broken
local function make_player_look_at_position(player, pos)
  local player_pos = get_player_head_pos(player)
  local diff = pos - player_pos

  -- horizontal angle (usually called yaw)
  local new_horizontal_angle = (math.pi * 2) - math.atan(diff.x / diff.z)
  if diff.z < 0 then
    new_horizontal_angle = new_horizontal_angle + math.pi
  end
  player:set_look_horizontal(new_horizontal_angle)

  -- to work out vertical angle, get arctangent of ydiff / horizontal distance
  -- horizontal (xz) distance is the bottom line in atan triangle
  local xz_dist = math.sqrt(diff.x * diff.x + diff.z * diff.z)
  local new_vertical_angle = -math.atan(diff.y / xz_dist)
  player:set_look_vertical(new_vertical_angle)
end

function TurtleEntity:make_player_look_at_bot(player)
  local bot_pos = self:get_pos()
  make_player_look_at_position(player, bot_pos)
end

function TurtleEntity:player_lookat_tick(dtime)
  if not self.wait_since_last_player_lookat then self.wait_since_last_player_lookat = 0 end
  self.wait_since_last_player_lookat = self.wait_since_last_player_lookat + dtime
  if self.wait_since_last_player_lookat >= 0.2 then
    self.wait_since_last_player_lookat = 0
    if self.players_look_tracking == nil then
      return
    end
    for _,player_name in ipairs(self.players_look_tracking) do
      local p = minetest.get_player_by_name(player_name)
      self:make_player_look_at_bot(p)
    end
  end
end

function TurtleEntity:start_updating_inventory(player_name)
  if self.players_with_inventory_open == nil then
    self.players_with_inventory_open = {}
  end
  for _,name in ipairs(self.players_with_inventory_open) do
    if name == player_name then
      return
    end
  end
  self.players_with_inventory_open[#self.players_with_inventory_open+1] = player_name
end

function TurtleEntity:stop_updating_inventory(player_name)
  if self.players_with_inventory_open == nil then
    return
  end
  for i, name in ipairs(self.players_with_inventory_open) do
    if name == player_name then
      table.remove(self.players_with_inventory_open, i)
      break
    end
  end
end

function TurtleEntity:inventory_update_tick(dtime)
  if not self.wait_since_last_inventory_update then self.wait_since_last_inventory_update = 0 end
  self.wait_since_last_inventory_update = self.wait_since_last_inventory_update + dtime
  if self.wait_since_last_inventory_update >= 0.2 then
    self.wait_since_last_inventory_update = 0
    if self.players_with_inventory_open == nil then
      return
    end
    for _,player_name in ipairs(self.players_with_inventory_open) do
      self:open_form(player_name, FORMNAME_TURTLE_INVENTORY)
    end
  end
end

function TurtleEntity:on_step(dtime)
  if adabots.config.hover_energy_cost > 0 then
    self:hover_tick(dtime)
    self:ground_check_tick(dtime)
  end

  self:player_lookat_tick(dtime)
  self:inventory_update_tick(dtime)

  -- init to 0
  if not self.wait_since_last_step then self.wait_since_last_step = 0 end

  -- increment
  self.wait_since_last_step = self.wait_since_last_step + dtime

  -- periodically...
  if self.wait_since_last_step >= adabots.config.turtle_tick then
    -- suck
    self:sucknode(self:get_pos(), 0)
    -- and maybe listen
    if self.is_listening then
      self:fetch_adabots_instruction()
    end
    self.wait_since_last_step = 0
  end
end

function TurtleEntity:player_allowed_to_control_bot(player_name)
  if player_name == self.owner then
    return true
  end
  if minetest.check_player_privs(player_name, {adabots_override_bot_lock=true}) then
    return true
  end
  if self:is_member(player_name) then
    return true
  end
  return false
end

function TurtleEntity:on_rightclick(clicker)
  if not clicker or not clicker:is_player() then return end
  local player_name = clicker:get_player_name()
  if self:player_allowed_to_control_bot(player_name) then
    self:open_inventory(player_name)
  else
    self:open_form(player_name, FORMNAME_TURTLE_NOTYOURBOT)
  end
end

function TurtleEntity:on_punch(puncher, time_from_last_punch, tool_capabilities, direction, damage)
  if not puncher or not puncher:is_player() then
    minetest.log("warning", "[adabots] : Non-player punched bot; this does nothing")
    return true -- returning true ensures the bot doesn't disappear when it gets to 0 hp. It should stop damage entirely according to lua_api.txt
  end
  local player_name = puncher:get_player_name()
  if self:player_allowed_to_control_bot(player_name) then
    self:open_controlpanel(player_name)
  else
    self:open_form(player_name, FORMNAME_TURTLE_NOTYOURBOT)
  end
  return true
end

local function generate_line(s, ypos)
  local i = 1
  local parsed = {}
  local width = 0
  local chars = 0
  local printed_char_width = CHAR_WIDTH + 1
  while chars < LINE_LENGTH and i <= #s do
    local file
    -- Get and render character
    if charmap[s:sub(i, i)] then
      file = charmap[s:sub(i, i)]
      i = i + 1
    elseif i < #s and charmap[s:sub(i, i + 1)] then
      file = charmap[s:sub(i, i + 1)]
      i = i + 2
    else
      -- No character image found.
      -- Use replacement character:
      file = "_rc"
      i = i + 1
      minetest.log("verbose",
        "[mcl_signs] Unknown symbol in '" .. s .. "' at " .. i)
    end
    if file then
      width = width + printed_char_width
      table.insert(parsed, file)
      chars = chars + 1
    end
  end
  width = width - 1

  local texture = ""
  local xpos = math.floor((SIGN_WIDTH - width) / 2)
  for j = 1, #parsed do
    texture = texture .. ":" .. xpos .. "," .. ypos .. "=" .. parsed[j] ..
    ".png"
    xpos = xpos + printed_char_width
  end
  return texture
end

-- modified from mcl_signs in MineClone5
local function generate_texture(text)
  local ypos = 0
  local texture = "[combine:" .. SIGN_WIDTH .. "x" .. SIGN_WIDTH ..
  generate_line(text, ypos)
  return texture
end

function TurtleEntity:update_nametag()
  if not minetest.get_modpath("mcl_signs") then return end

  -- remove if we already have one
  if self.text_entity then self.text_entity:remove() end

  self.text_entity = minetest.add_entity({x = 0, y = 0, z = 0},
    "mcl_signs:text")
  local relative_position = {
    x = NAMETAG_DELTA_X,
    y = NAMETAG_DELTA_Y,
    z = NAMETAG_DELTA_Z
  }
  local relative_rotation = {x = 0, y = 0, z = 0}
  self.text_entity:set_attach(self.object, "", relative_position,
    relative_rotation)
  self.text_entity:get_luaentity()._signnodename = "mcl_signs:standing_sign"
  self.text_entity:set_properties({textures = {generate_texture(self.name)}})

  self.text_entity:set_yaw(0)
end

-- Find first path to value inside input
-- with type 'userdata' by calling itself for each element
-- of lists and dictionaries
local function path_to_userdata(input)
  if type(input) == 'userdata' then
    return ""
  end
  if type(input) == 'table' then
    for key, value in pairs(input) do
      local subpath = path_to_userdata(value)
      if subpath ~= nil then
        return "." .. key .. subpath
      end
    end
  end
  return nil
end

function TurtleEntity:get_staticdata()
  local data = {
    id = self.id,
    name = self.name,
    workspace = self.workspace,
    is_listening = self.is_listening,
    heading = self.heading,
    owner = self.owner,
    energy = self.energy,
    selected_slot = self.selected_slot,
    autoRefuel = self.autoRefuel,
    allowed_players = minetest.serialize(self.allowed_players or {}),
    allow_faction_access = self.allow_faction_access,
    inv = serializeInventory(self.inv),
    toolinv = serializeInventory(self.toolinv),
  }
  local userdata_path = path_to_userdata(data)
  if userdata_path ~= nil then
    minetest.log("error", "attempted to serialize userdata at " .. userdata_path)
  end
  return minetest.serialize(data)
end
-- MAIN PLAYER INTERFACE (CALL THESE)------------------------------------------
function TurtleEntity:get_pos() return self.object:get_pos() end

function TurtleEntity:getLocRelative(numForward, numUp, numRight)
  local pos = self:get_pos()
  if pos == nil then
    return nil -- To prevent unloaded turtles from trying to load things
  end
  local new_pos = vector.new(pos)
  if self:getHeading() % 4 == 0 then
    new_pos.z = pos.z - numForward;
    new_pos.x = pos.x - numRight;
  end
  if self:getHeading() % 4 == 1 then
    new_pos.x = pos.x + numForward;
    new_pos.z = pos.z - numRight;
  end
  if self:getHeading() % 4 == 2 then
    new_pos.z = pos.z + numForward;
    new_pos.x = pos.x + numRight;
  end
  if self:getHeading() % 4 == 3 then
    new_pos.x = pos.x - numForward;
    new_pos.z = pos.z + numRight;
  end
  new_pos.y = pos.y + (numUp or 0)
  return new_pos
end

-- returns true if it was possible to add any energy
function TurtleEntity:addEnergy(amount)
  if self.energy >= adabots.config.energy_max then
    self.energy = adabots.config.energy_max;
    return false;
  end
  if self.energy + amount > adabots.config.energy_max then
    -- waste of energy
    self.energy = adabots.config.energy_max;
    return true;
  end
  self.energy = self.energy + amount;
  return true
end

---@returns true if it has enough energy to use the specified amount
--- after correcting with cost multiplier, but does not change energy level
function TurtleEntity:hasEnergyFor(amount)
  local corrected_amount = amount * adabots.config.energy_cost_multiplier
  return self.energy >= corrected_amount
end

---@returns true if it successfully spent specified amount (correcting first with multiplier)
function TurtleEntity:useEnergy(amount)
  self:ensureEnergyFor(amount)
  local corrected_amount = amount * adabots.config.energy_cost_multiplier
  if self.autoRefuel and self.energy < corrected_amount then
    self:refuel_from_any_slot()
  end
  local energy_after = self.energy - corrected_amount;
  if energy_after >= 0 then
    self.energy = energy_after
    return true
  end
  return false
end

function TurtleEntity:turn_players_above(yaw_diff)
  local players_above_bot = self:get_players_above_bot()
  for _,player in ipairs(players_above_bot) do
    local yaw = player:get_look_horizontal()
    player:set_look_yaw(yaw + yaw_diff)
  end
end

--- From 0 to 3
function TurtleEntity:setHeading(heading)
  if not self:useEnergy(adabots.config.turn_energy_cost) then return false end
  heading = (tonumber(heading) or 0) % 4
  if self.heading ~= heading then
    local old_heading = self.heading
    self.heading = heading
    local yaw_diff = (self.heading - old_heading) * 3.14159265358979323 / 2
    self:turn_players_above(yaw_diff)
    self.object:set_yaw(self.heading * 3.14159265358979323 / 2)
  end
  return true
end

function TurtleEntity:getHeading() return self.heading end
function TurtleEntity:turnLeft() return self:setHeading(self:getHeading() + 1) end
function TurtleEntity:turnRight() return self:setHeading(self:getHeading() - 1) end

function TurtleEntity:getLocForward() return self:getLocRelative(1, 0, 0) end
function TurtleEntity:getLocBackward() return self:getLocRelative(-1, 0, 0) end
function TurtleEntity:getLocUp() return self:getLocRelative(0, 1, 0) end
function TurtleEntity:getLocDown() return self:getLocRelative(0, -1, 0) end
function TurtleEntity:getLocRight() return self:getLocRelative(0, 0, 1) end
function TurtleEntity:getLocLeft() return self:getLocRelative(0, 0, -1) end

function TurtleEntity:place() return self:build(self:getLocForward()) end
function TurtleEntity:placeUp() return self:build(self:getLocUp()) end
function TurtleEntity:placeDown() return self:build(self:getLocDown()) end

function TurtleEntity:forward() return self:move(self:getLocForward()) end
function TurtleEntity:back() return self:move(self:getLocBackward()) end
function TurtleEntity:up() return self:move(self:getLocUp()) end
function TurtleEntity:down() return self:move(self:getLocDown()) end

function TurtleEntity:select(slot)
  if isValidInventoryIndex(slot) then
    self.selected_slot = slot;
    return true
  else
    return false
  end
end

function TurtleEntity:getSelectedSlot() return self.selected_slot end
function TurtleEntity:getItemCount(slot_number)
  local stack = self:getTurtleslot(slot_number)
  if stack == nil then
    return -1
  end
  return stack:get_count()
end

function TurtleEntity:dig() return self:mine(self:getLocForward()) end
function TurtleEntity:digUp() return self:mine(self:getLocUp()) end
function TurtleEntity:digDown() return self:mine(self:getLocDown()) end

function TurtleEntity:detect() return self:detectnode(self:getLocForward()) end
function TurtleEntity:detectUp() return self:detectnode(self:getLocUp()) end
function TurtleEntity:detectDown() return self:detectnode(self:getLocDown()) end
function TurtleEntity:detectLeft() return self:detectnode(self:getLocLeft()) end
function TurtleEntity:detectRight() return self:detectnode(self:getLocRight()) end

function TurtleEntity:inspect() return self:inspectnode(self:getLocForward()) end
function TurtleEntity:inspectUp() return self:inspectnode(self:getLocUp()) end
function TurtleEntity:inspectDown() return self:inspectnode(self:getLocDown()) end

function TurtleEntity:suck(max_amount)
  return self:sucknode(self:getLocForward(), max_amount)
end
function TurtleEntity:suckUp(max_amount)
  return self:sucknode(self:getLocUp(), max_amount)
end
function TurtleEntity:suckDown(max_amount)
  return self:sucknode(self:getLocDown(), max_amount)
end

function TurtleEntity:drop(amount)
  return self:itemDrop(self:getLocForward(), amount)
end
function TurtleEntity:dropUp(amount)
  return self:itemDrop(self:getLocUp(), amount)
end
function TurtleEntity:dropDown(amount)
  return self:itemDrop(self:getLocDown(), amount)
end

local function get_stack_json(name, count, remaining_uses)
  return '{"name":"' .. name .. '","remaining_uses":' .. remaining_uses ..
    ',"count":' .. count .. '}'
end

local function get_stack_description(stack)
  local nilstack = get_stack_json("", 0, 0)
  if stack == nil then return nilstack end
  local table = stack:to_table()
  if table == nil then return nilstack end
  local name = table.name
  local wear = table.wear or 0
  local remaining_uses = get_remaining_uses(name, wear)
  -- note minetest.write_json erroneously converts integers to floats
  return get_stack_json(name, stack:get_count(), remaining_uses)
  -- return json.encode({
  --   ["name"] = tool_name,
  --   ["remaining_uses"] = remaining_uses
  -- })
end

function TurtleEntity:getCurrentTool()
  local tool_stack = self.toolinv:get_stack("toolmain", 1)
  return get_stack_description(tool_stack)
end

function TurtleEntity:getItemDetail(slot)
  if slot == nil then
    slot = self:getSelectedSlot()
  end
  if not isValidInventoryIndex(slot) then
    return "error: invalid slot number"
  end
  local stack = self:getTurtleslot(slot)
  return get_stack_description(stack)
end

function TurtleEntity:listen() self:update_is_listening(true) end

function TurtleEntity:stopListen() self:update_is_listening(false) end

function TurtleEntity:toggle_is_listening()
  self:update_is_listening(not self.is_listening)
end

function TurtleEntity:update_is_listening(value)
  self.is_listening = value
  self:update_listening_appearance()
end

function TurtleEntity:update_listening_appearance()
  if self.is_listening then
    self:setAwakeTexture()
  else
    self:setSleepingTexture()
  end
end

function TurtleEntity:open_form(player_name, form_name)
  local form = turtle_forms[form_name]
  local formspec = form.formspec_function(self, player_name)
  minetest.show_formspec(player_name, form_name .. self.id, formspec)
end

function TurtleEntity:open_inventory(player_name)
  self:start_updating_inventory(player_name)
  self:open_form(player_name, FORMNAME_TURTLE_INVENTORY)
end

function TurtleEntity:open_controlpanel(player_name)
  self:start_look_tracking(player_name)
  self:open_form(player_name, FORMNAME_TURTLE_CONTROLPANEL)
end

function TurtleEntity:open_access_control(player_name)
  self:open_form(player_name, FORMNAME_TURTLE_ACCESSCONTROL)
end

function TurtleEntity:open_slotselect(player_name)
  self:open_form(player_name, FORMNAME_TURTLE_SLOTSELECT)
end

local function is_command_approved(turtle_command)
  local direct_commands = {
    "forward", "turnLeft", "turnRight", "back", "up", "down",
    "getSelectedSlot", "detectLeft", "detectRight", "getCurrentTool",
    "getItemDetail"
  }
  for _, dc in pairs(direct_commands) do
    if turtle_command == "turtle." .. dc .. "()" then return true end
  end
  local single_number_commands = {
    "select", "getItemCount", "craft", "getItemDetail"
  }
  for _, snc in pairs(single_number_commands) do
    if turtle_command:find("^turtle%." .. snc .. "%( *%d+%)$") ~= nil then
      return true
    end
  end
  local location_commands = {"dig", "place", "detect", "inspect", "suck"}
  local locations = {"", "Up", "Down"}
  for _, lc in pairs(location_commands) do
    for _, loc in pairs(locations) do
      local pattern = "^turtle%." .. lc .. loc .. "%(%)$"
      if turtle_command:find(pattern) ~= nil then return true end
    end
  end
  local single_number_location_commands = {"drop", "suck"}
  for _, snlc in pairs(single_number_location_commands) do
    for _, loc in pairs(locations) do
      local pattern = "^turtle%." .. snlc .. loc .. "%( *%d+%)$"
      if turtle_command:find(pattern) ~= nil then return true end
      -- minetest.debug(turtle_command .. " does not match " .. pattern)
    end
  end
  return false
end

local function post_instruction_result(server_url, workspaceId, result,
  bot_name, state_reset_functor)
  local set_result_options = {
    url = server_url .. "/patch?workspaceId=" .. workspaceId ..
      "&botName=" .. bot_name .. "&returnValue=" .. result ..
      "&userId=" .. userId,
    method = "GET",
    timeout = 1
  }
  http_api.fetch(set_result_options, function(res)
    state_reset_functor()
  end)
end

function TurtleEntity:do_instruction(command)
  local result = ""
  if not is_command_approved(command) then
    result = "error: unsupported command " .. command
  else
    command = command:gsub("^turtle.", "self:")
    local functor = loadstring("return function(self) return " .. command ..
      " end")
    if functor then
      local turtle_functor = functor()
      local val = turtle_functor(self)
      if val ~= nil then
        result = tostring(val)
      else
        result = "nil"
      end
    else
      result = "error: invalid lua expression " .. command
    end
  end
  self.state = "returning"
  -- minetest.debug(command .. " returned " .. result)
  return result
end

function TurtleEntity:fetch_adabots_instruction()
  if self.state ~= "standby" then return end
  self.state = "fetching"
  local server_url = self:get_server_url()
  if self.workspace == nil then return end
  local workspaceId = self.workspace["id"]
  local fetch_options = {
    url = server_url .. "/get?workspaceId=" .. workspaceId .. "&botName=" ..
      self.name .. "&userId=" .. userId,
    method = "GET",
    timeout = 1
  }
  -- minetest.debug("Fetching from " .. fetch_options.url)
  http_api.fetch(fetch_options, function(res)
    if res.code == 200 and res.succeeded and string.sub(res.data, 1, 6) ~=
      "error:" and res.data ~= "" then
      local result = self:do_instruction(res.data)
      post_instruction_result(self:get_server_url(), workspaceId, result,
        self.name,
        function() self.state = "standby" end)
    else
      self.state = "standby"
    end
  end)
end

function TurtleEntity:get_server_url() return INSTRUCTION_PROXY_URL end

-- Inventory Interface
-- MAIN INVENTORY COMMANDS--------------------------

---    Swaps itemstacks in slots A and B
function TurtleEntity:itemSwapTurtleslot(turtleslotA, turtleslotB)
  if (not isValidInventoryIndex(turtleslotA)) or
    (not isValidInventoryIndex(turtleslotB)) then return false end

  local stackA = self:getTurtleslot(turtleslotA)
  local stackB = self:getTurtleslot(turtleslotB)

  self:setTurtleslot(turtleslotA, stackB)
  self:setTurtleslot(turtleslotB, stackA)

  return true
end

function TurtleEntity:peek_craft_result()
  local output, _ = minetest.get_craft_result({
    method = "normal",
    width = 3,
    items = {
      self:getTurtleslot(craftSquares[1]),
      self:getTurtleslot(craftSquares[2]),
      self:getTurtleslot(craftSquares[3]),
      self:getTurtleslot(craftSquares[4]),
      self:getTurtleslot(craftSquares[5]),
      self:getTurtleslot(craftSquares[6]),
      self:getTurtleslot(craftSquares[7]),
      self:getTurtleslot(craftSquares[8]),
      self:getTurtleslot(craftSquares[9])
    }
  })
  return output.item:get_short_description()
end

function TurtleEntity:drop_items_in_world(leftover_stack)
  if leftover_stack == nil then return end
  if leftover_stack:get_count() == 0 then
    return
  end
  -- drop items into world
  local item_name = leftover_stack:to_table().name
  local amount = leftover_stack:get_count()
  local pos = self:get_pos()
  local below = vector.new(pos.x, pos.y - 1, pos.z)
  local drop_pos = minetest.find_node_near(below, 1, {"air"}) or below
  for _ = 1, amount do
    minetest.add_item(drop_pos, item_name)
  end
end

-- craft using top left 3x3 grid
-- defaults to single item
-- puts output into selected square, or otherwise
-- any non-craft-grid square that is free, or otherwise
-- drops it into the world
function TurtleEntity:craft(times)
  local craft_amount = times or 1
  for _ = 1, craft_amount, 1 do
    local outputSlots = {4, 8, 12, 13, 14, 15, 16}
    local output, decremented_input =
    minetest.get_craft_result({
      method = "normal",
      width = 3,
      items = {
        self:getTurtleslot(craftSquares[1]),
        self:getTurtleslot(craftSquares[2]),
        self:getTurtleslot(craftSquares[3]),
        self:getTurtleslot(craftSquares[4]),
        self:getTurtleslot(craftSquares[5]),
        self:getTurtleslot(craftSquares[6]),
        self:getTurtleslot(craftSquares[7]),
        self:getTurtleslot(craftSquares[8]),
        self:getTurtleslot(craftSquares[9])
      }
    })
    if output.item:is_empty() then return false end
    -- Put rest of ingredients back
    for i, turtleslot in pairs(craftSquares) do
      self:setTurtleslot(turtleslot, decremented_input.items[i])
    end
    -- Put output in output slot
    local leftover_stack = self:add_item_to_slots(output.item, outputSlots)
    self:drop_items_in_world(leftover_stack)
  end
  return true
end

--- stick = 1, wood = 7, tree = 30  (4 sticks to a wood, 4 wood to a tree)
--- coal = 40, lava bucket = 60
---@returns burn value of slot contents as fuel (for 1 item)
function TurtleEntity:get_fuel_time(turtleslot)
  if not isValidInventoryIndex(turtleslot) then return 0 end
  local fuel, _ = minetest.get_craft_result({
    method = "fuel",
    width = 1,
    items = {self:getTurtleslot(turtleslot)}
  })
  return fuel.time
end

--- @returns True if fuel was consumed. False if itemslot did not have fuel.
--- consumes up to amount specified; but if amount = 0 or nil, enough is
--- consumed to fill the tank without wasting, or the whole stack is consumed
function TurtleEntity:itemRefuel(turtleslot, amount)
  if not isValidInventoryIndex(turtleslot) then return false end

  local slot_contents = self:getTurtleslot(turtleslot)
  if slot_contents == nil then return false end
  local fuel, afterfuel = minetest.get_craft_result({
    method = "fuel",
    width = 1,
    items = {slot_contents}
  })
  if fuel.time == 0 then return false end

  local energy_per_item = fuel.time * adabots.config.fuel_multiplier
  local max_to_consume = amount or 0
  if max_to_consume == 0 then
    -- 0 means "use the whole stack"
    max_to_consume = slot_contents:get_count()
  end
  local energy_room = adabots.config.energy_max - self.energy
  local max_items_for_energy_room = math.floor(energy_room / energy_per_item)
  if max_items_for_energy_room == 0 then
    -- but still burn 1 item even if that would overflow the energy tank
    max_items_for_energy_room = 1
  end
  if max_items_for_energy_room < max_to_consume then
    -- restrict in order not to waste
    max_to_consume = max_items_for_energy_room
  end

  local burn_result_item = afterfuel.items[1]
  if burn_result_item ~= nil then
    burn_result_item:set_count(slot_contents:get_count() - max_to_consume)
  end
  self:setTurtleslot(turtleslot, burn_result_item)

  for _ = 1, max_to_consume do
    -- Process replacements (Such as buckets from lava buckets)
    local replacements = fuel.replacements
    if replacements[1] then
      local leftover = self.inv:add_item("main", replacements[1])
      if not leftover:is_empty() then
        local pos = self:get_pos()
        local above = vector.new(pos.x, pos.y + 1, pos.z)
        local drop_pos = minetest.find_node_near(above, 1, {"air"}) or above
        minetest.item_drop(replacements[1], nil, drop_pos)
      end
    end
  end
  self:addEnergy(energy_per_item * max_to_consume)
  return true
end

function TurtleEntity:setSleepingTexture()
  if not minetest.get_modpath("mcl_signs") then return end
  if self.light_blocker ~= nil then self.light_blocker:remove() end
  self.light_blocker = minetest.add_entity({x = 0, y = 0, z = 0},
    "mcl_signs:text")
  local relative_position = {x = 2.25, y = -23.25, z = 3.625}
  local relative_rotation = {x = 0, y = 0, z = 0}
  self.light_blocker:set_attach(self.object, "", relative_position,
    relative_rotation)
  self.light_blocker:set_properties({visual_size = {x = 1, y = 5}})
  self.light_blocker:get_luaentity()._signnodename = "mcl_signs:standing_sign"
  self.light_blocker:set_properties({textures = {generate_texture("__")}})
  self.light_blocker:set_yaw(0)
end

function TurtleEntity:setAwakeTexture()
  if self.light_blocker ~= nil then self.light_blocker:remove() end
end

function TurtleEntity:getFuel() return self.fuel end

function TurtleEntity:isTurtleslotEmpty(turtleslot)
  return self:getTurtleslot(turtleslot):is_empty()
end

function TurtleEntity:setAutoRefuel(autoRefuel)
  self.autoRefuel = autoRefuel
end

---@returns the slot with the best fuel type - i.e. prefer coal over wood
function TurtleEntity:get_preferred_fuel_slot()
  local highest_fuel_value = 0
  local chosen_fuel_index = nil
  for turtleslot_offset = 0, TURTLE_INVENTORYSIZE - 1 do
    -- start at the selected slot, then all slots after selected_slot
    -- and then the slots from 1 up to the selected_slot
    local turtleslot = (self.selected_slot - 1 + turtleslot_offset) % TURTLE_INVENTORYSIZE + 1
    local fuel_value = self:get_fuel_time(turtleslot)
    if fuel_value > highest_fuel_value then
      highest_fuel_value = fuel_value
      chosen_fuel_index = turtleslot
    end
  end
  return chosen_fuel_index
end

function TurtleEntity:refuel_from_any_slot()
  local slot = self:get_preferred_fuel_slot()
  if slot == nil then
    return false
  end
  return self:itemRefuel(slot, 0)
end

function TurtleEntity:dump(object) return dump(object) end

local function register_or_override_entity(entity_name, entity_definition)
  if minetest.registered_entities[entity_name] then
    -- override
    minetest.registered_entities[entity_name] = entity_definition
  else
    -- define new entity
    minetest.register_entity(entity_name, entity_definition)
  end
end

register_or_override_entity("adabots:turtle", TurtleEntity)

local PickaxeEntity = {
  initial_properties = {
    is_visible = true,
    makes_footstep_sound = false,
    physical = false,

    visual = "mesh",
    mesh = "pickaxe.b3d",
    textures = {"pick_diamond.png"},
    visual_size = {x = 1, y = 1, z = 1},

    static_save = false,
    automatic_rotate = 0,
    id = -1,

    -- ensure clicks go through to the turtle
    pointable = false
  }
}

local function set_pickaxe_properties(texture)
  local entity = deepcopy(PickaxeEntity)
  entity["initial_properties"]["textures"] = {texture}
  return entity
end

register_or_override_entity("adabots:pick_wood",
  set_pickaxe_properties("pick_wood.png"))
register_or_override_entity("adabots:pick_stone",
  set_pickaxe_properties("pick_stone.png"))
register_or_override_entity("adabots:pick_steel",
  set_pickaxe_properties("pick_iron.png"))
register_or_override_entity("adabots:pick_bronze",
  set_pickaxe_properties("pick_bronze.png"))
register_or_override_entity("adabots:pick_gold",
  set_pickaxe_properties("pick_gold.png"))
register_or_override_entity("adabots:pick_mese",
  set_pickaxe_properties("pick_mese.png"))
register_or_override_entity("adabots:pick_diamond",
  set_pickaxe_properties("pick_diamond.png"))

minetest.register_privilege("adabots_override_bot_lock", {
  description = "Can access other player's bots without their permission.",
  give_to_singleplayer = true
})
