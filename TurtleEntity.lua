

local FORMNAME_TURTLE_INVENTORY = "computertest:turtle:inventory:"
local FORMNAME_TURTLE_TERMINAL  = "computertest:turtle:terminal:"
local FORMNAME_TURTLE_UPLOAD    = "computertest:turtle:upload:"

--TODO sandbox this!
--Currently returns function that defines init and loop. In the future, this should probably just initialize it using some callbacks
local function sandbox(codeString)
    return loadstring(codeString)
end

local function getTurtle(id) return computertest.turtles[id] end
local function runTurtleCommand(turtle, command)
    if command==nil or command=="" then return nil end
    --TODO eventually replace this with some kinda lua sandbox
    command = "function init(turtle) return "..command.." end"
    minetest.log("COMMAND IS \""..command.."\"")
    sandbox(command)()
    local res = init(turtle)
    if (res==nil) then
        return "Returned nil"
    elseif (type(res)=="string") then
        return res
    end
    return "Done. Didn't return string."
end
local function get_formspec_inventory(self)
    return "size[12,5;]"
            .."button[0,0;2,1;open_terminal;Open Terminal]"
            .."button[2,0;2,1;upload_code;Upload Code]"
            .."set_focus[open_terminal;true]"
            .."list["..self.inv_fullname..";main;8,1;4,4;]"
            .."background[8,1;4,4;computertest_inventory.png]"
            .."list[current_player;main;0,1;8,4;]";
end
local function get_formspec_terminal(turtle)
    local previous_answers = turtle.previous_answers
    local lastCommandRan = turtle.lastCommandRan or ""
    local parsed_output = "";
    for i=1, #previous_answers do parsed_output = parsed_output .. minetest.formspec_escape(previous_answers[i]).."," end
    local saved_output = "";
    for i=1, #previous_answers do saved_output = saved_output .. minetest.formspec_escape(previous_answers[i]).."\n" end
    return
    "size[12,9;]"
            .."field_close_on_enter[terminal_in;false]"
            .."field[0,0;12,1;terminal_in;;"..lastCommandRan.."]"
            .."set_focus[terminal_in;true]"
            .."textlist[0,1;12,8;terminal_out;"..parsed_output.."]";
end
local function get_formspec_upload(turtle)
    --TODO could indicate if code is already uploaded
    return
    "size[12,9;]"
            .."button[0,0;2,1;button_upload;Upload Code to #"..turtle.id.."]"
            .."field_close_on_enter[upload;false]"
            .."textarea[0,1;12,8;upload;;"..minetest.formspec_escape(turtle.codeUncompiled or "").."]"
            .."set_focus[upload;true]"
    ;
end

minetest.register_on_player_receive_fields(function(player, formname, fields)
    local function isForm(name)
        return string.sub(formname,1,string.len(name))==name
    end
    --minetest.debug("FORM SUBMITTED",dump(formname),dump(fields))
    if isForm(FORMNAME_TURTLE_INVENTORY) then
        local id = tonumber(string.sub(formname,1+string.len(FORMNAME_TURTLE_INVENTORY)))
        local turtle = getTurtle(id)
        if (fields.upload_code=="Upload Code") then
            minetest.show_formspec(player:get_player_name(),FORMNAME_TURTLE_UPLOAD..id,get_formspec_upload(turtle));
        elseif (fields.open_terminal=="Open Terminal") then
            minetest.show_formspec(player:get_player_name(),FORMNAME_TURTLE_TERMINAL..id,get_formspec_terminal(turtle));
        end
    elseif isForm(FORMNAME_TURTLE_TERMINAL) then
        if (fields.terminal_out ~= nil) then return true end
        local id = tonumber(string.sub(formname,1+string.len(FORMNAME_TURTLE_TERMINAL)))
        local turtle = getTurtle(id)
        turtle.lastCommandRan = fields.terminal_in
        local commandResult = runTurtleCommand(turtle, fields.terminal_in)
        if (commandResult==nil) then
            minetest.close_formspec(player:get_player_name(),FORMNAME_TURTLE_TERMINAL..id)
            return true
        end
        commandResult = fields.terminal_in.." -> "..commandResult
        turtle.previous_answers[#turtle.previous_answers+1] = commandResult
        minetest.show_formspec(player:get_player_name(),FORMNAME_TURTLE_TERMINAL..id,get_formspec_terminal(turtle));
    elseif isForm(FORMNAME_TURTLE_UPLOAD) then
        local id = tonumber(string.sub(formname,1+string.len(FORMNAME_TURTLE_UPLOAD)))
        if (fields.button_upload == nil or fields.upload == nil) then return true end
        local turtle = getTurtle(id)
        --minetest.debug("CODE UPLOADED, NEAT",dump(id),dump(formname),dump(fields),dump(turtle))
        turtle.codeUncompiled = fields.upload
        turtle.code = sandbox(turtle.codeUncompiled)
        if turtle.code==nil then return true end--Given malformed code
    --    This turtle.code is used later
    else
        return false--Unknown formname, input not processed
    end
    return true--Known formname, input processed "If function returns `true`, remaining functions are not called"
end)
minetest.register_entity("computertest:turtle", {
    initial_properties = {
        hp_max = 1,
        is_visible = true,
        makes_footstep_sound = false,
        physical = true,
        collisionbox = { -0.5, -0.5, -0.5, 0.5, 0.5, 0.5 },
        visual = "cube",
        visual_size = { x = 0.9, y = 0.9 },
        textures = {
            "computertest_top.png",
            "computertest_bottom.png",
            "computertest_right.png",
            "computertest_left.png",
            "computertest_back.png",
            "computertest_front.png",
        },
        automatic_rotate = 0,
        id = -1,
    },
    --- From 0 to 3
    set_heading = function(turtle,heading)
        heading = (tonumber(heading) or 0)%4
        if turtle.heading ~= heading then
            turtle.heading = heading
            turtle.object:set_yaw(turtle.heading * 3.14159265358979323/2)
            if (coroutine.running() == turtle.coroutine) then turtle:yield("Turning") end
        end
    end,
    get_heading = function(turtle)
        return turtle.heading
    end,
    on_activate = function(self, staticdata, dtime_s)
        --TODO use staticdata to load previous state, such as inventory and whatnot

        --Give ID
        computertest.num_turtles = computertest.num_turtles+1
        self.id = computertest.num_turtles
        self.heading = 0
        self.previous_answers = {}
        self.coroutine = nil
        --Give her an inventory
        self.inv_name = "computertest:turtle:"..self.id
        self.inv_fullname = "detached:"..self.inv_name
        local inv = minetest.create_detached_inventory(self.inv_name,{})
        if inv == nil or inv == false then error("Could not spawn inventory")end
        inv:set_size("main", 4*4)
        if self.inv ~= nil then inv.set_lists(self.inv) end
        self.inv = inv
        -- Add to turtle list
        computertest.turtles[self.id] = self
    end,
    on_rightclick = function(self, clicker)
        if not clicker or not clicker:is_player() then return end
        minetest.show_formspec(clicker:get_player_name(), FORMNAME_TURTLE_INVENTORY..self.id, get_formspec_inventory(self))
    end,
    get_staticdata = function(self)
    --    TODO convert inventory and internal code to string and back somehow, or else it'll be deleted every time the entity gets unloaded
    end,

    ---
    ---@returns true on success
    ---
    turtle_move_withHeading = function (turtle,numForward,numRight,numUp)
        --minetest.log("YAW"..dump(turtle.object:get_yaw()))
        --minetest.log("NUMFORWARD"..dump(numForward))
        --minetest.log("NUMRIGHT"..dump(numRight))
        local new_pos = turtle:getNearbyPos(numForward,numRight,numUp)
        --Verify new pos is empty
        if (minetest.get_node(new_pos).name~="air") then
            turtle:yield("Moving")
            return false
        end
        --Take Action
        turtle.object:set_pos(new_pos)
        turtle:yield("Moving")
        return true
    end,
    getNearbyPos = function(turtle, numForward, numRight, numUp)
        local pos = turtle.object:get_pos()
        local new_pos = vector.new(pos)
        if turtle:get_heading()%4==0 then new_pos.z=pos.z-numForward;new_pos.x=pos.x-numRight; end
        if turtle:get_heading()%4==1 then new_pos.x=pos.x+numForward;new_pos.z=pos.z-numRight; end
        if turtle:get_heading()%4==2 then new_pos.z=pos.z+numForward;new_pos.x=pos.x+numRight; end
        if turtle:get_heading()%4==3 then new_pos.x=pos.x-numForward;new_pos.z=pos.z+numRight; end
        new_pos.y = pos.y + (numUp or 0)
        return new_pos
    end,
    mine = function(turtle, nodeLocation)
        local node = minetest.get_node(nodeLocation)
        local drops = minetest.get_node_drops(node)

        for _, itemname in ipairs(drops) do
            local stack = ItemStack(itemname)
            --TODO This doesn't actually need to drop-then-undrop the item for no reason
            minetest.log("dropping "..stack:get_count().."x "..itemname)
            local item = minetest.add_item(nodeLocation, stack)
            if item ~= nil then
                local i = ItemStack(item:get_luaentity().itemstring)
                if turtle.inv:room_for_item("main",i) then
                    item:get_luaentity().collect = true
                    turtle.inv:add_item("main",i)
                    item:get_luaentity().itemstring = ""
                    item:remove()
                else
                    minetest.log("Cannot pickup digged item, no room left in inventory!")
                end
            end
        end

        minetest.remove_node(nodeLocation)
        turtle:yield("Mining")

    end,
--    MAIN TURTLE INTERFACE    ---------------------------------------
--    TODO put turtle interface into a stack, so the turtle can't immediately mine hundreds of blocks (only one mine per second and move two blocks per second or something)
    --    Wouldn't work since the player couldn't use stateful functions such as getting the fuel level
--    TODO The TurtleEntity thread would need to pause itself after calling any of these functions. This pause would then return state back to the
--    TODO move this to a literal OO interface wrapper thingy
    yield = function(turtle,reason) if (coroutine.running() == turtle.coroutine) then coroutine.yield(reason) end end,
    moveForward = function(turtle)  turtle:turtle_move_withHeading( 1, 0, 0) end,
    moveBackward = function(turtle) turtle:turtle_move_withHeading(-1, 0, 0) end,
    moveRight = function(turtle)    turtle:turtle_move_withHeading( 0, 1, 0) end,
    moveLeft = function(turtle)     turtle:turtle_move_withHeading( 0,-1, 0) end,
    moveUp = function(turtle)       turtle:turtle_move_withHeading( 0, 0, 1) end,
    moveDown = function(turtle)     turtle:turtle_move_withHeading( 0, 0,-1) end,
    turnLeft = function(turtle)     turtle:set_heading(turtle:get_heading()+1) end,
    turnRight = function(turtle)    turtle:set_heading(turtle:get_heading()-1) end,
    mineForward = function(turtle)  turtle:mine(turtle:getNearbyPos(1,0,0)) end,
    mineUp = function(turtle)       turtle:mine(turtle:getNearbyPos(0,0,1)) end,
    mineDown = function(turtle)     turtle:mine(turtle:getNearbyPos(0,0,-1)) end,
--    MAIN TURTLE INTERFACE END---------------------------------------
})

local timer = 0
minetest.register_globalstep(function(dtime)
    timer = timer + dtime
    if (timer >= computertest.config.globalstep_interval) then
        for id,turtle in pairs(computertest.turtles) do
            if turtle.coroutine then
                if coroutine.status(turtle.coroutine)=="dead" then
                    --minetest.log("turtle #"..id.." has coroutine, but it's already done running")
                elseif coroutine.status(turtle.coroutine)=="suspended" then
                    --minetest.log("turtle #"..id.." has suspended/new coroutine!")
                    local status, result = coroutine.resume(turtle.coroutine)
                    minetest.log("coroutine stat "..dump(status).." said "..dump(result))
                end
            elseif turtle.code then
                --minetest.log("turtle #"..id.." has no coroutine but has code! Making coroutine...")
                --TODO add some kinda timeout into coroutine
                turtle.coroutine = coroutine.create(function()
                    turtle.code()
                    init(turtle)
                end)
            else
                --minetest.log("turtle #"..id.." has no coroutine or code, who cares...")
            end
        end
        timer = timer - computertest.config.globalstep_interval
    end
end)