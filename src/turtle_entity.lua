local adabots_period = 0.3

local S = minetest.get_translator(minetest.get_current_modname())
local F = minetest.formspec_escape

local FORMNAME_TURTLE_INVENTORY = "adabots:turtle:inventory:"

local TURTLE_INVENTORYSIZE = 4 * 4

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

local function updateBotField(turtle, fields, field_key, is_connection_field)
    field_value = fields[field_key]
    if field_value then
        if turtle[field_key] ~= field_value then
            if is_connection_field then turtle:stopListen() end
            turtle[field_key] = field_value
        end
    end
end

minetest.register_on_player_receive_fields(
    function(player, formname, fields)
        local function isForm(name)
            return string.sub(formname, 1, string.len(name)) == name
        end
        if isForm(FORMNAME_TURTLE_INVENTORY) then
            local id = tonumber(string.sub(formname, 1 +
                                               string.len(
                                                   FORMNAME_TURTLE_INVENTORY)))
            local turtle = getTurtle(id)
            updateBotField(turtle, fields, "name", false)
            updateBotField(turtle, fields, "host_ip", true)
            updateBotField(turtle, fields, "host_port", true)
            if fields.listen then
                turtle.doAction(turtle, player, "listen")
                return true
            end
            if fields.forward then turtle.forward(turtle, true) end
            if fields.backward then turtle.back(turtle, true) end
            if fields.turnleft then turtle.turnLeft(turtle, true) end
            if fields.turnright then turtle.turnRight(turtle, true) end
            return true
        else
            return false -- Unknown formname, input not processed
        end
    end)

-- Code responsible for updating turtles every turtle_tick
local timer = 0
minetest.register_globalstep(function(dtime)
    timer = timer + dtime
    while (timer >= adabots.config.turtle_tick) do
        for _, turtle in pairs(adabots.turtles) do
            if turtle.coroutine then
                if coroutine.status(turtle.coroutine) == "suspended" then

                    -- Auto-Refuel
                    if turtle.fuel < 0 and turtle.autoRefuel then
                        turtle:autoRefuel()
                    end

                    if turtle.fuel > 0 then
                        local status, result =
                            coroutine.resume(turtle.coroutine)
                        turtle:debug("coroutine stat " .. dump(status) ..
                                         " said " .. dump(result) .. "fuel=" ..
                                         turtle.fuel)
                    else
                        turtle:debug("No Fuel in turtle")
                    end
                end
                -- elseif coroutine.status(turtle.coroutine)=="dead" then
                -- minetest.log("turtle #"..id.." has coroutine, but it's already done running")
            elseif turtle.code then
                minetest.log(
                    "turtle has no coroutine but has code! Making coroutine for code... " ..
                        turtle.codeUncompiled)
                -- TODO add some kinda timeout into coroutine
                turtle.coroutine = coroutine.create(function()
                    turtle.code()
                    init(turtle)
                end)
                -- else
                -- minetest.log("turtle #"..id.." has no coroutine or code, who cares...")
            end
        end
        timer = timer - adabots.config.turtle_tick
    end
end)
-- Code responsible for generating turtle entity and turtle interface

local TurtleEntity = {
    initial_properties = {
        hp_max = 20,
        is_visible = true,
        makes_footstep_sound = false,
        physical = true,
        collisionbox = {-0.5, -0.5, -0.5, 0.5, 0.5, 0.5},
        visual = "cube",
        visual_size = {x = 0.9, y = 0.9},
        static_save = true, -- Make sure it gets saved statically
        textures = {
            "adabots_top.png", "adabots_bottom.png", "adabots_right.png",
            "adabots_left.png", "adabots_back.png", "adabots_front.png"
        },
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
function TurtleEntity:move(nodeLocation, no_yield)
    -- Verify new pos is empty
    if nodeLocation == nil or minetest.get_node(nodeLocation).name ~= "air" then
        self:after_action("Moving", false, false)
        return false
    end
    -- Take Action
    self.object:move_to(nodeLocation, true)
    self:after_action("Moving", true, not no_yield)
    return true
end
function TurtleEntity:mine(nodeLocation)
    if nodeLocation == nil then return false end
    local node = minetest.get_node(nodeLocation)
    if node.name == "air" then return false end
    local drops = minetest.get_node_drops(node)
    -- TODO NOTE This violates spawn protection, but I know of no way to mine that abides by spawn protection AND picks up all items and contents (dig_node drops items and I don't know how to pick them up)
    minetest.remove_node(nodeLocation)
    for _, iteminfo in pairs(drops) do
        local stack = ItemStack(iteminfo)
        if self.inv:room_for_item("main", stack) then
            self.inv:add_item("main", stack)
        else
            minetest.add_item(nodeLocation, stack.name)
        end
    end
    self:after_action("Mining", true, true)
    return true
end

-- needed interface to mcl_inventory to be able to drop things

function TurtleEntity:get_inventory() return nil end

function TurtleEntity:is_player() return false end

-- end interface to mcl_inventory to be able to drop things

function TurtleEntity:build(nodeLocation)
    if nodeLocation == nil then return false end

    local node = minetest.get_node(nodeLocation)
    if node.name ~= "air" then return false end

    -- Build and consume item
    local stack = self:getTurtleslot(self.selected_slot)
    if stack:is_empty() then return false end
    local newstack, position_placed = minetest.item_place_node(stack, nil, {
        type = "node",
        under = nodeLocation,
        above = self:getLoc()
    })

    -- consume item
    stack:set_count(stack:get_count() - 1)
    self.inv:set_stack("main", self.selected_slot, stack)

    if position_placed == nil then
        self:after_action("Building", true, true)
        return false
    end

    self:after_action("Building", true, true)
    return true
end
function TurtleEntity:inspectnode(nodeLocation)
    local result = minetest.get_node(nodeLocation)
    return "minecraft:" .. result.name
end
function TurtleEntity:detectnode(nodeLocation)
    return self:inspectnode(nodeLocation) ~= "minecraft:air"
end
function TurtleEntity:itemDrop(nodeLocation, amount)
    local stack = self:getTurtleslot(self.selected_slot)
    if stack:is_empty() then return false end

    -- add item to world
    item_name = stack:to_table().name
    minetest.debug("dropping " .. amount .. " " .. item_name)
    for item_count = 1, amount do minetest.add_item(nodeLocation, item_name) end

    -- adjust inventory stack
    stack:set_count(stack:get_count() - amount)
    self.inv:set_stack("main", self.selected_slot, stack)
    -- local drop_pos = minetest.find_node_near(nodeLocation, 1, {"air"}) or
    --                      nodeLocation
    -- TODO test if dropping into chests works
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
        -- TODO sandbox this!
        -- Currently returns function that defines init and loop. In the future, this should probably just initialize it using some callbacks
        if code == "" then return nil end
        return loadstring(code)
    end
    self.codeUncompiled = code_string
    self.coroutine = nil
    self.code = sandbox(self.codeUncompiled)
    if run_for_result then
        -- TODO run subroutine once, if it returns a value, return that here
        return "Ran"
    end
    return self.code ~= nil
end

-- MAIN TURTLE USER INTERFACE------------------------------------------
function TurtleEntity:get_formspec_inventory()
    local turtle_inv_x = 5
    local turtle_inv_y = 0.4
    local selected_x = ((self.selected_slot - 1) % 4) + turtle_inv_x
    local selected_y = math.floor((self.selected_slot - 1) / 4) + turtle_inv_y
    local listening = false
    local sleeping_image = "" -- TODO check listening and set Zzz image
    local general_settings = "size[9,9.75]" .. "options[key_event=true]" ..
                                 "background[-0.19,-0.25;9.41,9.49;turtle_inventory_bg.png]"
    local turtle_image = "set_focus[listen;true]" ..
                             "image[0,0;2,2;turtle_icon2.png]" .. sleeping_image

    local turtle_name = "style_type[field;font_size=26]" ..
                            "field[2.0,0.8;3,1;name;" ..
                            F(minetest.colorize("#313131", "AdaBot name")) ..
                            ";" .. F(self.name) .. "]"

    local play_button =
        "image_button[4,2.4;1,1;play_btn.png;listen;]tooltip[listen;Start/stop listening]"

    local movement_buttons =
        "image_button[0,3.4;1,1;arrow_forward.png;forward;]" ..
            "tooltip[forward;Move forward]" ..
            "image_button[1,3.4;1,1;arrow_backward.png;backward;]" ..
            "tooltip[backward;Move backward]" ..
            "image_button[2,3.4;1,1;arrow_turnleft.png;turnleft;]" ..
            "tooltip[turnleft;Turn left]" ..
            "image_button[3,3.4;1,1;arrow_turnright.png;turnright;]" ..
            "tooltip[turnright;Turn right]"

    local connection_settings = "style_type[field;font_size=20]" ..
                                    "label[0.4,2.0;" ..
                                    F(
                                        minetest.colorize("#313131",
                                                          "Connection settings")) ..
                                    "]" .. "field[0.6,2.9;2.7,0.5;host_ip;;" ..
                                    F(
                                        minetest.colorize("#313131",
                                                          self.host_ip or
                                                              "localhost")) ..
                                    "]" .. "field[3.2,2.9;1,0.5;host_port;;" ..
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

    return general_settings .. turtle_image .. turtle_name .. play_button ..
               movement_buttons .. connection_settings .. turtle_inventory ..
               turtle_selection .. turtle_inventory_items .. player_inventory ..
               player_inventory_items
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
    -- self.owner = minetest.get_meta(pos):get_string("owner")
    self.heading = data.heading or 0
    self.previous_answers = data.previous_answers or {}
    self.coroutine = data.coroutine or nil
    self.fuel = data.fuel or adabots.config.fuel_initial
    self.selected_slot = data.selected_slot or 1
    self.autoRefuel = data.autoRefuel or true
    self.codeUncompiled = data.codeUncompiled or ""

    -- Give her an inventory
    self.inv_name = "adabots:turtle:" .. self.id
    self.inv_fullname = "detached:" .. self.inv_name
    self.inv = minetest.create_detached_inventory(self.inv_name, {})
    if self.inv == nil or self.inv == false then
        error("Could not spawn inventory")
    end

    -- Keep items from save
    if data.inv ~= nil then deserializeInventory(self.inv, data.inv) end
    self.inv:set_size("main", TURTLE_INVENTORYSIZE)

    -- Add to turtle list
    adabots.turtles[self.id] = self
end

function TurtleEntity:on_rightclick(clicker)
    if not clicker or not clicker:is_player() then return end
    minetest.show_formspec(clicker:get_player_name(),
                           FORMNAME_TURTLE_INVENTORY .. self.id,
                           self:get_formspec_inventory())
end
function TurtleEntity:get_staticdata()
    minetest.debug("Serializing turtle " .. self.name)
    return minetest.serialize({
        id = self.id,
        name = self.name,
        host_ip = self.host_ip,
        host_port = self.host_port,
        heading = self.heading,
        previous_answers = self.previous_answers,
        coroutine = nil, -- self.coroutine,
        fuel = self.fuel,
        selected_slot = self.selected_slot,
        autoRefuel = self.autoRefuel,
        inv = serializeInventory(self.inv),
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
function TurtleEntity:setHeading(heading, no_yield)
    heading = (tonumber(heading) or 0) % 4
    if self.heading ~= heading then
        self.heading = heading
        self.object:set_yaw(self.heading * 3.14159265358979323 / 2)
        if not no_yield then
            self:after_action("Turning", false, not no_yield)
        end
    end
    return true
end
function TurtleEntity:getHeading() return self.heading end
function TurtleEntity:turnLeft(no_yield)
    return self:setHeading(self:getHeading() + 1, no_yield)
end
function TurtleEntity:turnRight(no_yield)
    return self:setHeading(self:getHeading() - 1, no_yield)
end

function TurtleEntity:getLocForward() return self:getLocRelative(1, 0, 0) end
function TurtleEntity:getLocBackward() return self:getLocRelative(-1, 0, 0) end
function TurtleEntity:getLocUp() return self:getLocRelative(0, 1, 0) end
function TurtleEntity:getLocDown() return self:getLocRelative(0, -1, 0) end
function TurtleEntity:getLocRight() return self:getLocRelative(0, 0, 1) end
function TurtleEntity:getLocLeft() return self:getLocRelative(0, 0, -1) end

function TurtleEntity:place() return self:build(self:getLocForward()) end
function TurtleEntity:placeUp() return self:build(self:getLocUp()) end
function TurtleEntity:placeDown() return self:build(self:getLocDown()) end

function TurtleEntity:forward(no_yield)
    return self:move(self:getLocForward(), no_yield)
end
function TurtleEntity:back(no_yield)
    return self:move(self:getLocBackward(), no_yield)
end
function TurtleEntity:up(no_yield) return self:move(self:getLocUp(), no_yield) end
function TurtleEntity:down(no_yield)
    return self:move(self:getLocDown(), no_yield)
end

function TurtleEntity:select(slot)
    if isValidInventoryIndex(slot) then
        self.selected_slot = slot;
        return true
    else
        return false
    end
end

function TurtleEntity:getSelectedSlot() return self.selected_slot end

function TurtleEntity:dig() return self:mine(self:getLocForward()) end
function TurtleEntity:digUp() return self:mine(self:getLocUp()) end
function TurtleEntity:digDown() return self:mine(self:getLocDown()) end

function TurtleEntity:detect() return self:detectnode(self:getLocForward()) end
function TurtleEntity:detectUp() return self:detectnode(self:getLocUp()) end
function TurtleEntity:detectDown() return self:detectnode(self:getLocDown()) end

function TurtleEntity:inspect() return self:inspectnode(self:getLocForward()) end
function TurtleEntity:inspectUp() return self:inspectnode(self:getLocUp()) end
function TurtleEntity:inspectDown() return self:inspectnode(self:getLocDown()) end

function TurtleEntity:drop(amount)
    return self:itemDrop(self:getLocForward(), amount)
end
function TurtleEntity:dropUp(amount)
    return self:itemDrop(self:getLocUp(), amount)
end
function TurtleEntity:dropDown(amount)
    return self:itemDrop(self:getLocDown(), amount)
end

function TurtleEntity:stopListen()
    self.adabots_server = ""
    minetest.debug("Stopped listening")
end

function TurtleEntity:doAction(player, action)
    local command = "function init(turtle) return turtle:" .. action .. "() end"
    self:upload_code_to_turtle(player, command, false)
end

local function is_command_approved(turtle_command)
    local direct_commands = {
        "forward", "turnLeft", "turnRight", "back", "up", "down"
    }
    for _, dc in pairs(direct_commands) do
        if turtle_command == "turtle%." .. dc .. "%(%)" then return true end
    end
    local single_number_commands = {"select", "drop", "dropUp", "dropDown"}
    for _, snc in pairs(single_number_commands) do
        if turtle_command:find("^turtle%." .. snc .. "%( *%d+%)$") ~= nil then
            return true
        end
    end
    local location_commands = {"dig", "place", "detect", "inspect"}
    local locations = {"", "Up", "Down"}
    for _, lc in pairs(location_commands) do
        for _, loc in pairs(locations) do
            local pattern = "^turtle%." .. lc .. loc .. "%(%)$"
            if turtle_command:find(pattern) ~= nil then return true end
        end
    end
    return false
end

local function update_adabots(self)
    if self.adabots_server == "" then return end
    http_api.fetch({url = self.adabots_server, timeout = 1}, function(res)
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
                url = self.adabots_server .. "/return_value/" .. result,
                timeout = 1
            }, function(_) end)
        end

        if self.adabots_server ~= "" then
            minetest.after(adabots_period, function()
                update_adabots(self)
            end)
        end
    end)
end

function TurtleEntity:listen()
    self.adabots_server = "http://" .. self.host_ip .. ":" .. self.host_port
    minetest.debug("listening on " .. self.adabots_server)
    update_adabots(self)
end

function TurtleEntity:after_action(action, useFuel, yield)
    -- Yield at least once
    if yield and coroutine.running() == self.coroutine then
        coroutine.yield(reason)
    end
    -- Use a fuel if requested
    if useFuel then self:useFuel() end
end

-- Inventory Interface
-- MAIN INVENTORY COMMANDS--------------------------

---Ex: turtle:itemGet(3):get_name() -> "default:stone"
function TurtleEntity:itemGet(turtleslot) return self:getTurtleslot(turtleslot) end
---    Swaps itemstacks in slots A and B
function TurtleEntity:itemSwapTurtleslot(turtleslotA, turtleslotB)
    if (not isValidInventoryIndex(turtleslotA)) or
        (not isValidInventoryIndex(turtleslotB)) then
        self:after_action("Inventorying", false, true)
        return false
    end

    local stackA = self:getTurtleslot(turtleslotA)
    local stackB = self:getTurtleslot(turtleslotB)

    self:setTurtleslot(turtleslotA, stackB)
    self:setTurtleslot(turtleslotB, stackA)

    self:after_action("Inventorying", false, true)
    return true
end

function TurtleEntity:itemSplitTurtleslot(turtleslotSrc, turtleslotDst, amount)
    if (not isValidInventoryIndex(turtleslotSrc)) or
        (not isValidInventoryIndex(turtleslotDst)) or
        (not self:isTurtleslotEmpty(turtleslotDst)) then
        self:after_action("Inventorying", false, true)
        return false
    end

    local stackToSplit = self:getTurtleslot(turtleslotSrc)

    amount = math.min(math.floor(tonumber(amount or 1)),
                      stackToSplit:get_count())

    stackToSplit:set_count(stackToSplit:get_count() - amount)
    self:setTurtleslot(turtleslotSrc, stackToSplit)
    stackToSplit:set_count(amount)
    self:setTurtleslot(turtleslotDst, stackToSplit)

    self:after_action("Inventorying", false, true)
    return true
end

---    TODO craft using top right 3x3 grid, and put result in itemslotResult
function TurtleEntity:itemCraft(turtleslotResult)
    if not isValidInventoryIndex(turtleslotResult) then return false end
    local craftSquares = {2, 3, 4, 6, 7, 8, 10, 11, 12}
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
    local leftover_craft = self:getTurtleslot(turtleslotResult):add_item(
                               output.item)
    -- TODO Deal with leftover craft and output.replacements
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
    self:after_action("Fueling", false, true)
    return true
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
function TurtleEntity:setName(name)
    self.name = minetest.formspec_escape(name)
    self.nametag = self.name
end

function TurtleEntity:debug(string)
    if adabots.config.debug then
        minetest.debug("adabots turtle #" .. self.id .. ": " ..
                           (string or "nil string"))
    end
end
function TurtleEntity:dump(object) return dump(object) end

minetest.register_entity("adabots:turtle", TurtleEntity)
