local modname = minetest.get_current_modname()
local modpath = minetest.get_modpath(modname)
local S = minetest.get_translator(minetest.get_current_modname())
local F = minetest.formspec_escape

local FORMNAME_TURTLE_INVENTORY = "adabots:turtle:inventory:"
local FORMNAME_TURTLE_CONTROLPANEL = "adabots:turtle:controlpanel:"
local FORMNAME_TURTLE_SLOTSELECT = "adabots:turtle:slotselect:"
local turtle_forms = {
  [FORMNAME_TURTLE_INVENTORY] = { ["formspec_function"] = function (turtle) return turtle:get_formspec_inventory() end },
  [FORMNAME_TURTLE_CONTROLPANEL] = { ["formspec_function"] = function (turtle) return turtle:get_formspec_controlpanel() end },
  [FORMNAME_TURTLE_SLOTSELECT] = { ["formspec_function"] = function (turtle) return turtle:get_formspec_slotselect() end },
}
local supported_tools = {
  "mcl_tools:pick_wood",
  "mcl_tools:pick_stone",
  "mcl_tools:pick_iron",
  "mcl_tools:pick_gold",
  "mcl_tools:pick_diamond"
}

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

---@returns whether the host-port pair is free (only one turtle can listen on each host-port pair)
local function checkPortFree(host, port_number)
    for i = 1, adabots.num_turtles do
        local bot = adabots.turtles[i]
        if bot == nil then
            minetest.debug("Error: nil bot")
        else
            if bot.is_listening and (host == bot.host_ip) and
                (port_number == bot.host_port) then
                minetest.debug("Error: " .. bot.name ..
                                   " is already listening on " .. host .. ":" ..
                                   port_number)
                return false
            end
        end
    end
    return true
end

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
    field_value = fields[field_key]
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
        for form_name, form in pairs(turtle_forms) do
          if isForm(form_name) then
            turtleform = form_name
          end
        end
        local function get_turtle()
          local number_suffix = string.sub(formname, 1 + string.len(turtleform))
          local id = tonumber(number_suffix)
          return getTurtle(id)
        end
        local turtle = get_turtle()
        local player_name = player:get_player_name()
        local function refresh(turtleform)
            turtle:open_form(player_name, turtleform)
        end
        local function respond_to_common_controls()
          if fields.close then minetest.close_formspec(player_name, formname) end
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
          if fields.open_inventory then turtle:open_inventory(player_name) end
          if fields.open_controlpanel then turtle:open_controlpanel(player_name) end
          if fields.open_slotselect then turtle:open_slotselect(player_name) end
          if fields.craft then turtle:craft(1) end
          if fields.listen then
              if turtle.is_listening or
                  checkPortFree(turtle.host_ip, turtle.host_port) then
                  turtle:toggle_is_listening()
                  refresh(turtleform)
              end
              return true
          end
        end
        if isForm(FORMNAME_TURTLE_INVENTORY) then
            updateBotField(turtle, fields, "name",
                           function() turtle:update_nametag() end)
            updateBotField(turtle, fields, "host_ip", function()
                if turtle.is_listening then
                    turtle:stopListen()
                    refresh(turtleform)
                end
            end)
            updateBotField(turtle, fields, "host_port", function()
                if turtle.is_listening then
                    turtle:stopListen()
                    refresh(turtleform)
                end
            end)
            respond_to_common_controls()
            return true
        elseif isForm(FORMNAME_TURTLE_CONTROLPANEL) then
            respond_to_common_controls()
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
  if tool_stack == nil then
    return nil
  end
  local table = tool_stack:to_table()
  if table == nil then
    return nil
  end
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

function node_walkable(nodeLocation)
    if nodeLocation == nil then
        minetest.debug("Error: testing nil node for walkability")
        return false
    end
    local node = minetest.get_node(nodeLocation)
    local node_name = node.name
    local node_registration = minetest.registered_nodes[node_name]
    return node_registration.walkable
end

function TurtleEntity:move(nodeLocation)
    -- Verify new pos is empty
    if node_walkable(nodeLocation) then return false end
    -- Take Action
    self.object:move_to(nodeLocation, true)
    return true
end

function contains(list, x)
  for _, v in pairs(list) do
    if v == x then return true end
  end
  return false
end

function is_supported_tool(tool_info)
  local tool_name = tool_info["name"]
  return is_supported_toolname(tool_name)
end

function is_supported_toolname(tool_name)
  if not contains(supported_tools, tool_name) then
    minetest.debug("Error: " .. tool_name .. " is not a supported Adabots turtle tool")
    return false
  end
  return true
end

function get_tool_hardness(tool_info)
  if not is_supported_tool(tool_info) then
    return 0
  end
  local capabilities = tool_info["tool_capabilities"]
  if capabilities == nil then
    return 0
  end
  return capabilities["max_drop_level"]
end

function get_node_hardness(node)
  local node_name = node.name
  local node_registration = minetest.registered_nodes[node_name]
  local hardness = node_registration["_mcl_hardness"]
  if hardness == nil then
    return 0
  end
  return math.floor(hardness)
end

function TurtleEntity:pickaxe_can_dig(node)
  local tool_info = self:getToolInfo()
  if tool_info == nil then
    return false
  end
  local tool_hardness = get_tool_hardness(tool_info)
  local node_hardness = get_node_hardness(node)
  -- minetest.debug("Tool: " .. tool_hardness .. " vs node: " .. node_hardness)
  return tool_hardness >= node_hardness
end

function TurtleEntity:mine(nodeLocation)
    if nodeLocation == nil then return false end
    local node = minetest.get_node(nodeLocation)
    if node.name == "air" then return false end
    -- check pickaxe strong enough
    if not self:pickaxe_can_dig(node) then
      return false
    end
    return minetest.dig_node(nodeLocation)
end

function TurtleEntity:pickup(stack)
  if self.inv:room_for_item("main", stack) then
    self.inv:add_item("main", stack)
    return true
  else
    return false
  end
end

function TurtleEntity:build(nodeLocation)
    if node_walkable(nodeLocation) then return false end

    -- Build and consume item
    local stack = self:getTurtleslot(self.selected_slot)
    if stack:is_empty() then return false end
    local newstack, position_placed = minetest.item_place(stack, nil, {
        type = "node",
        under = nodeLocation,
        above = self:getLoc()
    })
    -- Consume item
    newstack:set_count(newstack:get_count() - 1)
    self.inv:set_stack("main", self.selected_slot, newstack)

    if position_placed == nil then return false end

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
    for i = 1,#objectlist do
      local object = objectlist[i]
      local properties = object:get_properties()
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
    slots[#slots+1] = slot
  end
  add_item_to_slots(stack, slots)
end

function TurtleEntity:add_item_to_slots(stack, slots)
    local leftover_stack = stack
    for i = 1,#slots,1 do
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

-- Get items, either those loose in the world, or in an inventory
-- at the nodeLocation given. As many items as possible are retrieved,
-- up to the amount specified.
-- Pass 1 iteratively for more precision, or pass 0 to retrieve infinite items.
-- If loose items are present, only those are picked up.
-- Put them into the turtle inventory at the first viable location starting
-- from the selected slot.
-- Returns true if any items were retrieved
-- Returns false only if unable to get any items
function TurtleEntity:sucknode(nodeLocation, maxAmount)
    if self:gather_items(nodeLocation, maxAmount) then return true end

    local chest = minetest.get_inventory({type = "node", pos = nodeLocation})
    if chest == nil then return false end

    local chest_listname = "main"
    local chestsize = chest:get_size(chest_listname)

    local remaining_items = maxAmount -- can't directly modify maxAmount because 0 means 'take infinite'
    local picked_up_items = 0
    for i = 1, chestsize do
        local chest_stack = chest:get_stack(chest_listname, i)
        if chest_stack == nil then
            minetest.debug("unexpected error in sucknode: stack is nil")
            return false
        end

        local stack_count = chest_stack:get_count()

        -- do you want the whole stack?
        if maxAmount == 0 or stack_count <= remaining_items then
            remaining_stack = self:add_item(chest_stack)
            local remaining_count = remaining_stack:get_count()
            local picked_up_this_iteration = stack_count - remaining_count
            picked_up_items = picked_up_items + picked_up_this_iteration
            chest:set_stack(chest_listname, i, remaining_stack)
            remaining_items = remaining_items - picked_up_this_iteration
        else
            local remaining_count = stack_count - remaining_items
            local stack_to_add = chest_stack
            stack_to_add:set_count(remaining_items)
            local leftover_stack = self:add_item(stack_to_add)
            -- leftover_itemcount is normally 0, otherwise it means we couldn't fit the desired amount from this inventory stack
            local leftover_itemcount = leftover_stack:get_count()
            local picked_up_this_iteration = remaining_count -
                                                 leftover_itemcount
            picked_up_items = picked_up_items + picked_up_this_iteration
            local remaining_stack = chest_stack
            remaining_stack:set_count(remaining_count + leftover_itemcount)
            chest:set_stack(chest_listname, i, remaining_stack)
            remaining_items = remaining_items - picked_up_this_iteration
        end
        if remaining_items == 0 then return true end
    end

    return picked_up_items > 0
end

function TurtleEntity:detectnode(nodeLocation)
    return not node_walkable(nodeLocation)
end

function TurtleEntity:itemDrop(nodeLocation, amount)
    local stack = self:getTurtleslot(self.selected_slot)
    if stack:is_empty() then return false end
    if stack:get_count() < amount then amount = stack:get_count() end

    -- adjust inventory stack
    new_amount = stack:get_count() - amount
    if new_amount > 0 then
        stack:set_count(new_amount)
        self.inv:set_stack("main", self.selected_slot, stack)
    else
        self.inv:set_stack("main", self.selected_slot, ItemStack(""))
    end

    -- dump items
    item_name = stack:to_table().name
    -- check for chest
    local chest = minetest.get_inventory({type = "node", pos = nodeLocation})
    if chest then
        local chest_stack = ItemStack(item_name)
        chest_stack:set_count(amount)
        local remainingItemStack = chest:add_item("main", chest_stack)
        amount = remainingItemStack:get_count()
    end
    if amount > 0 then
        -- add items to world
        for item_count = 1, amount do
            minetest.add_item(nodeLocation, item_name)
        end
    end
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
    local remainingItemStack = nodeInventory:add_item(listname, toPush)
    self:setTurtleslot(turtleslot, remainingItemStack)
    return remainingItemStack:is_empty()
end

---
---@returns true on success
---
function TurtleEntity:upload_code_to_turtle(player, code_string, run_for_result)
    local function sandbox(code)
        if code == "" then return nil end
        return loadstring(code)
    end
    self.codeUncompiled = code_string
    self.coroutine = nil
    self.code = sandbox(self.codeUncompiled)
    if run_for_result then return "Ran" end
    return self.code ~= nil
end

-- MAIN TURTLE USER INTERFACE------------------------------------------
function TurtleEntity:get_formspec_inventory()
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
                            "field[2.0,0.8;3,1;name;" ..
                            F(minetest.colorize("#313131", "AdaBot name")) ..
                            ";" .. F(self.name) .. "]"

    local playpause_button = "image_button[4,2.2;1,1;" .. playpause_image ..
                                 ";listen;]tooltip[listen;Start/stop listening]"

    local tool_label = "label[0,3.0;" .. F(minetest.colorize("#313131", "Tool")) .. "]"
    local tool_bg = mcl_formspec.get_itemslot_bg(0, 3.4, 1, 1)
    local tool_inventory_slot = "list[" .. self.toolinv_fullname .. ";toolmain;0,3.4;1,1;]"
    local tool = tool_label .. tool_bg .. tool_inventory_slot
    local controlpanel_button =
        "image_button[4,3.4;1,1;open_controlpanel.png;open_controlpanel;]" ..
        "tooltip[open_controlpanel;Open controlpanel]"

    local connection_settings = "style_type[field;font_size=16]" ..
                                    "label[0.4,1.8;" ..
                                    F(
                                        minetest.colorize("#313131",
                                                          "Connection settings")) ..
                                    "]" .. "field[0.3,2.7;3.0,0.5;host_ip;;" ..
                                    F(
                                        minetest.colorize("#313131",
                                                          self.host_ip or
                                                              "localhost")) ..
                                    "]" .. "field[3.2,2.7;1.1,0.5;host_port;;" ..
                                    F(
                                        minetest.colorize("#313131",
                                                          self.host_port or
                                                              "7112")) .. "]"

    local turtle_inventory = "label[" .. turtle_inv_x .. "," .. turtle_inv_y -
                                 0.55 .. ";" ..
                                 F(
                                     minetest.colorize("#313131", "AdaBot " ..
                                                           S("Inventory"))) ..
                                 "]" ..
                                 mcl_formspec.get_itemslot_bg(turtle_inv_x,
                                                              turtle_inv_y, 4, 4)

    local turtle_selection = "background[" .. selected_x .. "," .. selected_y -
                                 0.05 ..
                                 ";1,1.1;mcl_inventory_hotbar_selected.png]"

    local turtle_inventory_items = "list[" .. self.inv_fullname .. ";main;" ..
                                       turtle_inv_x .. "," .. turtle_inv_y ..
                                       ";4,4;]"

    -- local help_button =
    --   "image_button[4,3.4;1,1;doc_button_icon_lores.png;__mcl_doc;]"..
    --   "tooltip[__mcl_doc;"..F(S("Help")).."]"

    local player_inventory = "label[0,4.5;" ..
                                 F(
                                     minetest.colorize("#313131", "Player " ..
                                                           S("Inventory"))) ..
                                 "]" ..
                                 mcl_formspec.get_itemslot_bg(0, 5.0, 9, 3) ..
                                 mcl_formspec.get_itemslot_bg(0, 8.24, 9, 1)

    local player_inventory_items = "list[current_player;main;0,5.0;9,3;9]" ..
                                       "list[current_player;main;0,8.24;9,1;0]"

    return
        general_settings .. turtle_image .. turtle_name .. playpause_button ..
            tool .. controlpanel_button .. connection_settings .. turtle_inventory ..
            turtle_selection .. turtle_inventory_items .. player_inventory ..
            player_inventory_items
end

local function render_buttons(start, button_table)
  local buttons = ""
  for i=1,#button_table do
    local b = button_table[i]
    buttons = buttons .. "image_button[" .. start.x + b.offset.x .. "," .. start.y + b.offset.y .. ';1,1;' .. b.name .. ".png;" .. b.name .. ";]" ..
               "tooltip[" .. b.name .. ";" .. b.tooltip .. "]"
  end
  return buttons
end

function TurtleEntity:get_formspec_controlpanel()
  local listening = self.is_listening
  local sleeping_image = ""
  local playpause_image = "pause_btn.png"
  if not listening then
    playpause_image = "play_btn.png"
  end

  local general_settings =
	  "formspec_version[4]" ..
	  "size[26,12]" ..
	  "no_prepend[]" ..
	  "bgcolor[#00000000]" ..
	  "background[0,0;25,12;controlpanel_bg.png]" ..
	  "style_type[button;noclip=true]"

  -- 
  -- X  ↑  ↟  ⇑  ⇈  c
  -- ↶     ↷  m  p
  -- ↖  ↓  ↡  ⇓  ⇊
  
  local start = { ['x'] = 18.65, ['y'] = 7.6 }
  
  local craft_tooltip = 'Craft ' .. self:peek_craft_result()
  local button_table = {
    { ['name'] = 'close',           ['offset'] = { ['x'] = 0, ['y'] = 1 }, ['tooltip'] = 'Close' },
    { ['name'] = 'arrow_forward',   ['offset'] = { ['x'] = 1, ['y'] = 1 }, ['tooltip'] = 'Move forward' },
    { ['name'] = 'arrow_backward',  ['offset'] = { ['x'] = 1, ['y'] = 3 }, ['tooltip'] = 'Move backward' },
    { ['name'] = 'arrow_turnleft',  ['offset'] = { ['x'] = 0, ['y'] = 2 }, ['tooltip'] = 'Turn left' },
    { ['name'] = 'arrow_turnright', ['offset'] = { ['x'] = 2, ['y'] = 2 }, ['tooltip'] = 'Turn right' },
    { ['name'] = 'arrow_up',        ['offset'] = { ['x'] = 2, ['y'] = 1 }, ['tooltip'] = 'Move up' },
    { ['name'] = 'arrow_down',      ['offset'] = { ['x'] = 2, ['y'] = 3 }, ['tooltip'] = 'Move down' },
    { ['name'] = 'mine_up',         ['offset'] = { ['x'] = 3, ['y'] = 1 }, ['tooltip'] = 'Dig up' },
    { ['name'] = 'mine',            ['offset'] = { ['x'] = 3, ['y'] = 2 }, ['tooltip'] = 'Dig forward' },
    { ['name'] = 'mine_down',       ['offset'] = { ['x'] = 3, ['y'] = 3 }, ['tooltip'] = 'Dig down' },
    { ['name'] = 'place_up',        ['offset'] = { ['x'] = 4, ['y'] = 1 }, ['tooltip'] = 'Place up' },
    { ['name'] = 'place',           ['offset'] = { ['x'] = 4, ['y'] = 2 }, ['tooltip'] = 'Place forward' },
    { ['name'] = 'place_down',      ['offset'] = { ['x'] = 4, ['y'] = 3 }, ['tooltip'] = 'Place down' },
    { ['name'] = 'open_inventory',  ['offset'] = { ['x'] = 0, ['y'] = 3 }, ['tooltip'] = 'Open inventory' },
    { ['name'] = 'open_slotselect', ['offset'] = { ['x'] = 1, ['y'] = 2 }, ['tooltip'] = 'Select slot' },
    { ['name'] = 'craft',           ['offset'] = { ['x'] = 5, ['y'] = 1 }, ['tooltip'] = craft_tooltip },
  }

  local buttons = render_buttons(start, button_table)

  return general_settings .. buttons
end

function TurtleEntity:get_formspec_slotselect()
  local general_settings =
    "formspec_version[4]" ..
    "size[25,12]" ..
    "no_prepend[]" ..
    "bgcolor[#00000000]" ..
    "background[0,0;25,12;slotselect_bg.png]" ..
    "style_type[button;noclip=true]"

  -- X  1  2  3  4
  -- ↘  5  6  7  8
  --    9  10 11 12
  --    13 14 15 16
  
  local start = { ['x'] = 19.6, ['y'] = 7.6 }
  local button_table = {
    { ['name'] = 'close',              ['offset'] = { ['x'] = 0, ['y'] = 0 }, ['tooltip'] = 'Close' },
    { ['name'] = 'open_controlpanel',  ['offset'] = { ['x'] = 0, ['y'] = 1 }, ['tooltip'] = 'Open controlpanel' },
  }
  local buttons = render_buttons(start, button_table)

  local selected_x = ((self.selected_slot - 1) % 4) + start.x + 0.98
  local selected_y = math.floor((self.selected_slot - 1) / 4) + start.y + 0.02

  local turtle_selection = "background[" .. selected_x .. "," .. selected_y -
                              0.05 ..
                              ";1.1,1.1;mcl_inventory_hotbar_selected.png]"

  slot_tiles = ""
  for i = 1, TURTLE_INVENTORYSIZE do
    local x = ((i - 1) % 4) + start.x + 1.1
    local y = math.floor((i - 1) / 4) + start.y + 0.1
    local stack = self.inv:get_stack("main", i)
    local stack_tooltip = stack:get_short_description()
    local stack_name = stack:get_name()
    local images = "empty.png"
    local button = "item_image_button[" .. x .. "," .. y .. ";0.9,0.9;" .. stack_name .. ";select_" .. i .. ";]"
    local tooltip = "tooltip[select_" .. i .. ";Select slot " .. i .. " (" .. stack_tooltip .. ")]"
    slot_tiles = slot_tiles .. button .. tooltip
  end

  return general_settings .. buttons .. slot_tiles .. turtle_selection
end

-- Called when a player wants to put something into the inventory.
-- Return value: number of items allowed to put.
-- Return value -1: Allow and don't modify item count in inventory.
function toolinv_allow_put(inv, listname, index, stack, player)
  if is_supported_toolname(stack:get_name()) then
    return 1
  else
    return 0
  end
end

function TurtleEntity:toolinv_on_put(inv, listname, index, stack, player)
  self:refresh_pickaxe()
end

function TurtleEntity:toolinv_on_take(inv, listname, index, stack, player)
  self:refresh_pickaxe()
end

-- https://rosettacode.org/wiki/Partial_function_application#Lua
function partial(f, arg)
    return function(...)
        return f(arg, ...)
    end
end

-- MAIN TURTLE ENTITY FUNCTIONS------------------------------------------
function TurtleEntity:on_activate(staticdata, dtime_s)
    local data = minetest.deserialize(staticdata)
    if type(data) ~= "table" or not data.complete then data = {} end
    -- Give ID
    adabots.num_turtles = adabots.num_turtles + 1
    self.id = adabots.num_turtles
    self.name = data.name or "Bob"
    self.host_ip = data.host_ip or "localhost"
    self.host_port = data.host_port or 7112
    self.is_listening = data.is_listening or false
    -- self.owner = minetest.get_meta(pos):get_string("owner")
    self.heading = data.heading or 0
    self.previous_answers = data.previous_answers or {}
    self.coroutine = data.coroutine or nil
    self.fuel = data.fuel or adabots.config.fuel_initial
    self.selected_slot = data.selected_slot or 1
    self.autoRefuel = data.autoRefuel or true
    self.codeUncompiled = data.codeUncompiled or ""

    -- Create inventory
    self.inv_name = "adabots:turtle:" .. self.id
    self.inv_fullname = "detached:" .. self.inv_name
    self.inv = minetest.create_detached_inventory(self.inv_name, {})
    if self.inv == nil or self.inv == false then
        error("Could not spawn inventory")
    end

    -- Create inventory for tool
    self.toolinv_name = "adabots:turtle_tool:" .. self.id
    self.toolinv_fullname = "detached:" .. self.toolinv_name
    self.toolinv = minetest.create_detached_inventory(self.toolinv_name,
    {
        allow_put = toolinv_allow_put,
        -- on_move = function(inv, from_list, from_index, to_list, to_index, count, player),
        on_put = partial(TurtleEntity.toolinv_on_put, self),
        on_take = partial(TurtleEntity.toolinv_on_take, self),
    })
    if self.toolinv == nil or self.toolinv == false then
        error("Could not spawn tool inventory")
    end

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
    if data.toolinv ~= nil then deserializeInventory(self.toolinv, data.toolinv) end
    self.toolinv:set_size("toolmain", 1)

    -- Add to turtle list
    adabots.turtles[self.id] = self

    self:add_pickaxe_model()
end

function TurtleEntity:refresh_pickaxe()
  self:remove_pickaxe()
  self:add_pickaxe_model()
end

function get_pickaxe_entity_name(tool_name)
  -- mcl_tools:pick_wood => adabots:pick_wood
  return "adabots" .. string.sub(tool_name, 10, -1)
end

function TurtleEntity:add_pickaxe_model()
  local tool_info = self:getToolInfo()
  if tool_info == nil then
    return
  end
  if not is_supported_tool(tool_info) then
    return
  end
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
  if self.pickaxe ~= nil then
    self.pickaxe:remove()
  end
end

function TurtleEntity:on_deactivate()
  self:remove_pickaxe()
end

function TurtleEntity:on_step(dtime)
    self:sucknode(self:getLoc(), 0)
    if not self.wait_since_last_step then self.wait_since_last_step = 0 end
    if self.is_listening then
        self.wait_since_last_step = self.wait_since_last_step + dtime
        if self.wait_since_last_step >= adabots.config.turtle_tick then
            self:fetch_adabots_instruction()
            self.wait_since_last_step = 0
        end
    end
end

function TurtleEntity:on_rightclick(clicker)
    if not clicker or not clicker:is_player() then return end
    self:open_inventory(clicker:get_player_name())
end

function TurtleEntity:on_punch(puncher, time_from_last_punch, tool_capabilities,
                               direction, damage)
    if not puncher or not puncher:is_player() then return end
    self:open_controlpanel(puncher:get_player_name())
    -- if time_from_last_punch < 0.5 then
    --     minetest.debug("double clicked " .. self.name)
    -- end
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
    for i = 1, #parsed do
        texture = texture .. ":" .. xpos .. "," .. ypos .. "=" .. parsed[i] ..
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
    local pos = self:getLocRelative(0, 1, 0)

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

function TurtleEntity:get_staticdata()
    return minetest.serialize({
        id = self.id,
        name = self.name,
        host_ip = self.host_ip,
        host_port = self.host_port,
        is_listening = self.is_listening,
        heading = self.heading,
        previous_answers = self.previous_answers,
        coroutine = nil, -- self.coroutine,
        fuel = self.fuel,
        selected_slot = self.selected_slot,
        autoRefuel = self.autoRefuel,
        inv = serializeInventory(self.inv),
        toolinv = serializeInventory(self.toolinv),
        codeUncompiled = self.codeUncompiled,
        complete = true
    })
end
-- MAIN PLAYER INTERFACE (CALL THESE)------------------------------------------
function TurtleEntity:getLoc() return self.object:get_pos() end
function TurtleEntity:getLocRelative(numForward, numUp, numRight)
    local pos = self:getLoc()
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
---Consumes a fuel point
function TurtleEntity:useFuel()
    if self.fuel > 0 then self.fuel = self.fuel - 1; end
end
--- From 0 to 3
function TurtleEntity:setHeading(heading)
    heading = (tonumber(heading) or 0) % 4
    if self.heading ~= heading then
        self.heading = heading
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

function TurtleEntity:suck(slot_number)
    return self:sucknode(self:getLocForward(), slot_number)
end
function TurtleEntity:suckUp(slot_number)
    return self:sucknode(self:getLocUp(), slot_number)
end
function TurtleEntity:suckDown(slot_number)
    return self:sucknode(self:getLocDown(), slot_number)
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
  local formspec = form.formspec_function(self)
  minetest.show_formspec(player_name, form_name .. self.id, formspec)
end

function TurtleEntity:open_inventory(player_name)
  self:open_form(player_name, FORMNAME_TURTLE_INVENTORY)
end

function TurtleEntity:open_controlpanel(player_name)
  self:open_form(player_name, FORMNAME_TURTLE_CONTROLPANEL)
end

function TurtleEntity:open_slotselect(player_name)
  self:open_form(player_name, FORMNAME_TURTLE_SLOTSELECT)
end

local function is_command_approved(turtle_command)
    local direct_commands = {
        "forward", "turnLeft", "turnRight", "back", "up", "down",
        "getSelectedSlot", "detectLeft", "detectRight"
    }
    for _, dc in pairs(direct_commands) do
        if turtle_command == "turtle." .. dc .. "()" then return true end
    end
    local single_number_commands = {"select", "getItemCount", "craft"}
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

function TurtleEntity:fetch_adabots_instruction()
    local server_url = self:get_server_url()
    if server_url == nil or server_url == "" then return end
    -- minetest.debug("fetching from " .. server_url)
    http_api.fetch({url = server_url, timeout = 1}, function(res)
        if res.succeeded then
            local result = ""
            if not is_command_approved(res.data) then
                result = "error: unsupported command " .. res.data
            else
                local command = res.data:gsub("^turtle.", "self:")
                local functor = loadstring(
                                    "return function(self) return " .. command ..
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
            minetest.debug(res.data .. " returned " .. result)

            http_api.fetch({
                url = server_url .. "/return_value/" .. result,
                timeout = 1
            }, function(_) end)
        end
    end)
end

function TurtleEntity:get_server_url()
    return "http://" .. self.host_ip .. ":" .. self.host_port
end

-- Inventory Interface
-- MAIN INVENTORY COMMANDS--------------------------

---Ex: turtle:itemGet(3):get_name() -> "default:stone"
function TurtleEntity:itemGet(turtleslot) return self:getTurtleslot(turtleslot) end
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

function TurtleEntity:itemSplitTurtleslot(turtleslotSrc, turtleslotDst, amount)
    if (not isValidInventoryIndex(turtleslotSrc)) or
        (not isValidInventoryIndex(turtleslotDst)) or
        (not self:isTurtleslotEmpty(turtleslotDst)) then return false end

    local stackToSplit = self:getTurtleslot(turtleslotSrc)

    amount = math.min(math.floor(tonumber(amount or 1)),
                      stackToSplit:get_count())

    stackToSplit:set_count(stackToSplit:get_count() - amount)
    self:setTurtleslot(turtleslotSrc, stackToSplit)
    stackToSplit:set_count(amount)
    self:setTurtleslot(turtleslotDst, stackToSplit)

    return true
end

function TurtleEntity:peek_craft_result()
  local output, decremented_input = minetest.get_craft_result({
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

-- craft using top left 3x3 grid
-- defaults to single item
-- puts output into selected square, or otherwise
-- any non-craft-grid square that is free, or otherwise
-- drops it into the world
function TurtleEntity:craft(times)
    craft_amount = times or 1
    for i = 1,craft_amount,1 do
      local outputSlots = {4, 8, 12, 13, 14, 15, 16}
      local output, decremented_input = minetest.get_craft_result({
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
      if leftover_stack:get_count() > 0 then 
        -- drop items into world
        item_name = leftover_stack:to_table().name
        amount = leftover_stack:get_count()
        local pos = self:getLoc()
        local below = vector.new(pos.x, pos.y - 1, pos.z)
        local drop_pos = minetest.find_node_near(below, 1, {"air"}) or below
        for item_count = 1, amount do
            minetest.add_item(drop_pos, item_name)
        end
      end
  end
    return true
end
--- @returns True if fuel was consumed. False if itemslot did not have fuel.
function TurtleEntity:itemRefuel(turtleslot)
    if not isValidInventoryIndex(turtleslot) then return false end

    local fuel, afterfuel = minetest.get_craft_result({
        method = "fuel",
        width = 1,
        items = {self:getTurtleslot(turtleslot)}
    })
    if fuel.time == 0 then return false end

    self:setTurtleslot(turtleslot, afterfuel.items[1])

    -- Process replacements (Such as buckets from lava buckets)
    local replacements = fuel.replacements
    if replacements[1] then
        local leftover = self.inv:add_item("main", replacements[1])
        if not leftover:is_empty() then
            local pos = self:getLoc()
            local above = vector.new(pos.x, pos.y + 1, pos.z)
            local drop_pos = minetest.find_node_near(above, 1, {"air"}) or above
            minetest.item_drop(replacements[1], nil, drop_pos)
        end
    end
    self.fuel = self.fuel + fuel.time * adabots.config.fuel_multiplier
    return true
end

function TurtleEntity:setSleepingTexture()
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
    self.autoRefuel = not not autoRefuel
end
function TurtleEntity:autoRefuel()
    for turtleslot = 1, 16 do
        if turtle:getFuel() > 100 then return true end
        turtle:itemRefuel(turtleslot)
    end
    return false
end

function TurtleEntity:dump(object) return dump(object) end

minetest.register_entity("adabots:turtle", TurtleEntity)

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

function set_pickaxe_properties(texture)
  local entity = deepcopy(PickaxeEntity)
  entity["initial_properties"]["textures"] = {texture}
  return entity
end

minetest.register_entity("adabots:pick_wood", set_pickaxe_properties("pick_wood.png"))
minetest.register_entity("adabots:pick_stone", set_pickaxe_properties("pick_stone.png"))
minetest.register_entity("adabots:pick_iron", set_pickaxe_properties("pick_iron.png"))
minetest.register_entity("adabots:pick_gold", set_pickaxe_properties("pick_gold.png"))
minetest.register_entity("adabots:pick_diamond", set_pickaxe_properties("pick_diamond.png"))

