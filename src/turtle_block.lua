-- The turtle block is only used when holding a turtle as a block in your hand
-- on placement it spawns a turtle entity
minetest.register_node("adabots:turtle", {
  description = "Turtle",

  tiles = {
    "adabots_top.png", "adabots_bottom.png", "adabots_right.png",
    "adabots_left.png", "adabots_back.png", "adabots_front.png"
  },

  paramtype2 = "facedir",
  on_place = function(itemstack, placer, pointed_thing)
    local pos = pointed_thing.above
    if pos == nil then
      return itemstack
    end
    if minetest.is_protected(pos, placer:get_player_name()) then
      return itemstack
    end
    minetest.add_entity(pos, "adabots:turtle")
    if not (creative and creative.is_enabled_for
      and creative.is_enabled_for(placer:get_player_name())) then
      itemstack:take_item()
    end
    return itemstack
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
