-- The turtle block is only used when holding a turtle as a block in your hand
-- and immediately after placement, to spawn the turtle entity, then it deletes itself
minetest.register_node("adabots:turtle", {
  description = "Turtle",

  tiles = {
    "adabots_top.png", "adabots_bottom.png", "adabots_right.png",
    "adabots_left.png", "adabots_back.png", "adabots_front.png"
  },

  paramtype2 = "facedir",
  after_place_node = function(pos, placer)
    if placer and placer:is_player() then
      local meta = minetest.get_meta(pos)
      meta:set_string("owner", placer:get_player_name())
    end
  end,
  on_construct = function(pos)
    minetest.add_entity(pos, "adabots:turtle")
    minetest.remove_node(pos)
  end
})

local steel = 'default:steelblock'
local chest = 'default:chest'
local diamond = 'default:diamondblock'
local gold = 'default:goldblock'

minetest.register_craft({
  output = 'adabots:turtle',
  recipe = {
    {gold, chest, gold},
    {steel, diamond, steel},
    {gold, steel, gold}
  }
})
