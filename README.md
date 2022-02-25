# Adabots

This fork of [computertest](https://github.com/zaners123/Computertest) allows you to run [Adabots](https://github.com/TamaMcGlinn/AdaBots) using minetest instead of minecraft.
I have also done a few fixes as necessary to get the [ComputerCraft turtle API](https://tweaked.cc/module/turtle.html) working.

After installing, go to Settings > All Settings and search for "secure", in order to set httpmods to include `computertest` (not adabots - I am too lazy to rename everything).

Then give yourself a turtle, place it and right click it. In the command window, enter `turtle:listen()` to start listening on the default server/port/tickrate.

turtle:listen takes three parameters:
- ip address (defaults to "localhost")
- port (defaults to "7112")
- tickrate in seconds (defaults to 0.3)

Another example call to put in the turtle's command window would be `turtle:listen("192.168.0.22", "7112", 0.1)`
to get a faster turtle listening to a different machine on your LAN.

## Working Features

- Movement, mining and placing works

## Features to Add

- Selecting an inventory slot
- Inventory management commands, such as crafting and sorting
- The turtle code isn't sandboxed, so turtles could call dangerous functions. This has been mitigated by the "computertest" privilege, but proper sandboxing would work best.
