local sig = require("signal")
local n64 = require("n64.controller")

local controller = n64.Connect("/dev/ttyACM0", 2000000)

local running = true

sig.signal("SIGINT", function()
	running = false
end)

while running do
	controller:poll_button_pressed()
end