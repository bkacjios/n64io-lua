#!/usr/bin/luajit

local n64 = require("n64.controller")

local VERSION = 0.01

local dump_methods = {
	["tpak-rom"] = "dump_tpak_cart_rom",
	["tpak-ram"] = "dump_tpak_cart_ram",
	["memory-pak"] = "dump_memory_pak"
}

local restore_methods = {
	["tpak-ram"] = "restore_tpak_cart_ram",
	["memory-pak"] = "restore_memory_pak",
}

local function print_help(prog, arg)
	if arg then
		io.stderr:write(("unknown argument: %s\n"):format(arg))
	end
	print("Usage: " .. prog ..  " [options]" .. [[ 
Options
	-v, --version               Output the version number
	-h, --help                  Show this help text
	--serial <file>             The serial device we should use to communicate (default /dev/ttyACM0)
	--baud <file>               The baudrate we should use to communicate (default 115200)
	--dump-tpak-rom <file>      Dump the transfer pak cartridge rom
	--dump-tpak-ram <file>      Dump the transfer pak save data
	--dump-memory-pak <file>    Dump the memory pak save data
	--restore-tpak-ram <file>   Restore the transfer pak save data
	--restore-memory-pak <file> Restore the memory pak save data]])
end

local function main(args)
	local prog = args[0]:match("([^/\\]+)$")

	if #args <= 0 then
		print_help(prog)
		return
	end

	local arg
	local check_file_arg = false
	local skip_next_arg = false
	local actions = {}

	local serial = "/dev/ttyACM0"
	local baud = 115200

	for i=1,#args do
		if skip_next_arg then
			skip_next_arg = false
			goto cont
		end

		arg = args[i]
		if arg == "-h" or arg == "--help" then
			print_help(prog)
		elseif arg == "-v" or arg == "--version" then
			print("version: " .. VERSION)
		elseif arg == "--serial" then
			skip_next_arg = true
			serial = args[i+1]
		elseif arg == "--baud" then
			skip_next_arg = true
			baud = tonumber(args[i+1])
		elseif arg == "--test" then
			table.insert(actions, {method = "test"})
		elseif arg:sub(1,6) == "--dump" then
			local method = dump_methods[arg:sub(8)]
			if not method then
				return print_help(prog, arg)
			end
			table.insert(actions, {method = method, file=io.stdout, open="wb"})
			check_file_arg = true
		elseif arg:sub(1,9) == "--restore" then
			local method = restore_methods[arg:sub(11)]
			if not method then
				return print_help(prog, arg)
			end
			table.insert(actions, {method = method, file=io.stdin, open="rb"})
			check_file_arg = true
		elseif check_file_arg then
			local action = actions[#actions]
			local f, err = io.open(arg, action.open)
			action.file = f
			if err then
				return io.stderr:write(("error: %s\n"):format(err))
			end
			check_file_arg = false
		else
			return print_help(prog, arg)
		end
		::cont::
	end

	local controller = n64.Connect(serial, baud)
	controller:reset()
	controller:initialize()

	for k,action in pairs(actions) do
		local status, err = controller[action.method](controller, action.file)
		if not status then
			io.stderr:write(("error: %s\n"):format(err))
		end
	end

	controller:close()
end
main(arg)