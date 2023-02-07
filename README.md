# [Adabots - adabots.net](adabots.net)

This minetest mod allows you to run [Adabots](https://github.com/TamaMcGlinn/AdaBots). If you want to use Minecraft, follow [these instructions instead](https://github.com/TamaMcGlinn/AdaBots/blob/main/docs/minecraft_installation.md).

## Setup

Install [this version of minetest 5.6.0](https://github.com/TamaMcGlinn/minetest) by following the compilation steps from source.
In the content tab, select MineClone 5. Create a world, and ensure that under Mods, the MineClone 5 mods are selected and also adabots.
Go to Settings > All Settings and search for "secure", in order to set httpmods field to include `adabots`.

## In game usage

Start the world in creative mode and give yourself a turtle, place it and right click it. In the interface, put the IP address and port you would like to listen to.
The host IP address is the IP address of the computer that will run an Adabots program; leave it at localhost if on the same machine.
The host port can be specified in your Adabots program, and will default to 7112:

```Ada
Bot : constant Adabots.Turtle := Adabots.Create_Turtle; -- outputs commands on port 7112
Other_Bot : constant Adabots.Turtle := Adabots.Create_Turtle (7113); -- outputs commands on port 7113
```

## Working Features

- Movement, mining and building
- Detecting if there is a block
- Selecting an inventory slot
- Getting items from chests

## Features to Add

- Looking what kind of block there is
- Crafting
