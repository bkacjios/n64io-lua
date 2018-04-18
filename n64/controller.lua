local bit = require("bit")
local Serial = require('periphery').Serial

local progress = require("progress")

local byte = string.byte
local char = string.char
local rep  = string.rep
local sub  = string.sub

local band = bit.band
local bor  = bit.bor
local bnot = bit.bnot
local bxor = bit.bxor
local lshift = bit.lshift
local rshift = bit.rshift

local floor = math.floor

local controller = {
	RAM_SIZES = {
		[0x00] = 0,
		[0x01] = 512,
		[0x02] = 8192,
		[0x03] = 32768,		-- 2 banks
		[0x04] = 131072,	-- 16 banks
		[0x05] = 65536,		-- 8 banks
	},
	ROM_SIZES = {
		[0x00] = 32768,		-- 0 banks
		[0x01] = 65536,		-- 4 banks
		[0x02] = 131072,	-- 8 banks
		[0x03] = 262144,	-- 16 banks
		[0x04] = 524288,	-- 32 banks
		[0x05] = 1048576,	-- 64 banks
		[0x06] = 2097152,	-- 128 banks
		[0x07] = 4194304,	-- 256 banks
		[0x08] = 8388608,	-- 512 banks
	},
	CART_TYPES = {
		[0x00] = "ROM",
		[0x01] = "MBC1",
		[0x02] = "MBC1+RAM",
		[0x03] = "MBC1+RAM+BATTERY",
		[0x05] = "MBC2",
		[0x06] = "MBC2+BATTERY",
		[0x08] = "ROM+RAM",
		[0x09] = "ROM+RAM+BATTERY",
		[0x0B] = "MMM01",
		[0x0C] = "MMM01+RAM",
		[0x0D] = "MMM01+RAM+BATTERY",
		[0x0F] = "MBC3+TIMER+BATTERY",
		[0x10] = "MBC3+TIMER+RAM+BATTERY",
		[0x11] = "MBC3",
		[0x12] = "MBC3+RAM",
		[0x13] = "MBC3+RAM+BATTERY",
		[0x19] = "MBC5",
		[0x1A] = "MBC5+RAM",
		[0x1B] = "MBC5+RAM+BATTERY",
		[0x1C] = "MBC5+RUMBLE",
		[0x1D] = "MBC5+RUMBLE+RAM",
		[0x1E] = "MBC5+RUMBLE+RAM+BATTERY",
		[0x20] = "MBC6",
		[0x22] = "MBC7+SENSOR+RUMBLE+RAM+BATTERY",
		[0xFC] = "POCKET CAMERA",
		[0xFD] = "BANDAI TAMA5",
		[0xFE] = "HuC3",
		[0xFF] = "HuC1+RAM+BATTERY",
	},
	BUTTONS = {
		[1] = {
			[0x01] = "DPAD_RIGHT",
			[0x02] = "DPAD_LEFT",
			[0x04] = "DPAD_DOWN",
			[0x08] = "DPAD_UP",
			[0x10] = "START",
			[0x20] = "Z",
			[0x40] = "B",
			[0x80] = "A",
		},

		[2] = {
			[0x01] = "C_RIGHT",
			[0x02] = "C_LEFT",
			[0x04] = "C_DOWN",
			[0x08] = "C_UP",
			[0x10] = "R",
			[0x20] = "L",
		}
	}
}
controller.__index = controller

function controller.Connect(serial, baud)
	local obj = {
		serial = Serial(serial or "/dev/ttyACM0", baud or 115200),
		tpak_high_bits = -1,
		reg_state = {},
		pressed_buttons = {
			[1] = {},
			[2] = {},
		},
	}
	--os.execute("sleep 1")
	return setmetatable(obj, controller)
end

function controller.addr_crc(addr)
	-- CRC Table
	local xor_table = { 0x0, 0x0, 0x0, 0x0, 0x0, 0x15, 0x1F, 0x0B, 0x16, 0x19, 0x07, 0x0E, 0x1C, 0x0D, 0x1A, 0x01 }
	local crc = 0

	addr = band(addr, bnot(0x1F))

	-- Go through each bit in the address
	for i=5,15 do
		-- check if bit is set
		if band(rshift(addr, i), 0x1) ~= 0 then
			-- xor the right value into the output
			crc = bxor(crc, xor_table[i+1])
		end
	end

	return bor(addr, crc)
end

function controller.data_crc(data)
	local crc = 0

	for i=1,33 do
		for j=7,0,-1 do
			local tmp = 0
			if band(crc, 0x80) ~= 0 then
				tmp = 0x85
			end
			crc = lshift(crc, 1)
			if i < 33 then
				local b = byte(data, i)
				if band(b, lshift(0x01, j)) ~= 0 then
					crc = bor(crc, 0x01)
				end
			end
			crc = bxor(crc, tmp)
		end
	end

	return band(crc, 0xFF)
end

function controller:close()
	return self.serial:close()
end

function controller:do_cmd(cmdbuf, resplen)
	self.serial:write(char(#cmdbuf, resplen) .. cmdbuf)
	return self.serial:read(resplen)
end

function controller:reset()
	self.tpak_high_bits = -1
	return self:do_cmd("\xFF", 3)
end

function controller:get_status()
	return self:do_cmd("\x00", 3)
end

function controller:get_button_status()
	return self:do_cmd("\x01", 4)
end

function controller:initialize()
	local status
	repeat
		-- wait until pak is ready
		status = byte(self:get_status(), 3)
	until status ~= 0x03
end

function controller:has_pak()
	local status = byte(self:get_status(), 3)
	-- 0x01 = Inserted+Initialized
	-- 0x02 = Nothing inserted
	-- 0x03 = Newly inserted, used for checking state changes while a game is running
	-- 0x04 = CRC error in last transmission (UNCONFIRMED)
	return status == 0x01
end

function controller:poll_button_pressed()
	local data = self:get_button_status()

	local status = byte(self:get_status(), 3)

	if status == 0x03 then
		-- New pak inserted, try to enable rumble
		if self:rumble_init(true) then
			print("RUMBLE PAK INSERTED")
		end
	end

	for i=1,2 do
		for button, name in pairs(controller.BUTTONS[i]) do
			if band(byte(data, i, i), button) ~= 0 then
				if not self.pressed_buttons[i][button] then
					self.pressed_buttons[i][button] = true
					print("PRESSED " .. name)
					self:rumble_set_power(true)
				end
			elseif self.pressed_buttons[i][button] then
				self.pressed_buttons[i][button] = false
				print("RELEASED " .. name)
				self:rumble_set_power(false)
			end
		end
	end
end

function controller:pak_read(addr)
	addr = controller.addr_crc(addr)

	local cmd = char(2, rshift(addr, 8), band(addr, 0xFF))
	local read = self:do_cmd(cmd, 33)

	local crc = byte(read, 33)
	local data_crc = controller.data_crc(read)

	-- return crc status then data read
	return crc == data_crc, sub(read, 1, 32)
end

function controller:pak_write(addr, data)
	addr = controller.addr_crc(addr)
	local crc = controller.data_crc(data)
	local cmd = char(3, rshift(addr, 8), band(addr, 0xFF)) .. data
	local read = byte(self:do_cmd(cmd, 1))
	-- return crc status
	return read == crc
end

function controller:register_push_state(reg)
	self.reg_state[reg] = self.reg_state[reg] or {}
	local status, read = self:pak_register_read(reg)
	if not status then
		return error(("failed to push register 0x%X (CRC mismatch)"):format(reg))
	end
	table.insert(self.reg_state[reg], 1, read)
end

function controller:register_pop_state(reg)
	self.reg_state[reg] = self.reg_state[reg] or {}
	if #self.reg_state[reg] <= 0 then
		return error("nothing to pop")
	end
	return self:pak_register_write(reg, table.remove(self.reg_state[reg], 1))
end

function controller:pak_register_read(reg)
	local status, read = self:pak_read(lshift(reg, 12))
	-- Return the status and last value of the read, since the return value is repeated 32 times
	return status, byte(read, #read)
end

function controller:pak_register_write(reg, value)
	-- The value we want to write is repeated 32 times to fill out the buffer
	local write = rep(char(value), 32)
	return self:pak_write(lshift(reg, 12), write)
end

function controller:has_memory_pak()
	-- From my tests, games that use a memory pak check it by writing random data to it then read it back

	-- Save the last 32 bytes of memory ram for later
	local status, original_block = self:pak_read(0x7FE0)
	if not status then return false end

	-- Our test string we use is 0 through 31
	-- This is exactly what LEGO Racers does
	local test_write = "\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0A\x0B\x0C\x0D\x0E\x0F\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1A\x1B\x1C\x1D\x1E\x1F"

	-- Write our test string
	self:pak_write(0x7FE0, test_write)

	-- Read it back
	local status, new_block = self:pak_read(0x7FE0)

	-- The test string should match our read if a mempak is inserted
	if new_block == test_write then
		-- Restore the original save data
		local status = self:pak_write(0x7FE0, original_block)
		-- Return if we successfully wrote back the original data
		return status
	end

	-- The test string doesn't match because it wasn't able to read anything back
	return false
end

function controller:has_rumble_pak()
	-- Get state of pak before modifications
	self:register_push_state(0x8)

	self:pak_register_write(0x8, 0xFE)
	local status, val = self:pak_register_read(0x8)

	-- Reading from 0x8, after writing 0xFE should be 0x00
	-- Some third party controllers, when a mempak is inserted, return whatever is in the register.
	-- So for example..
	-- writing 0x80 and reading the register back would return 0x80, making it think the rumble pak is in.
	-- This check fixes false positives.
	if val ~= 0x00 then
		-- Return pak state to what it was previously
		self:register_pop_state(0x8)
		return false
	end

	-- Write pak identifier
	self:pak_register_write(0x8, 0x80)

	-- Check register is equal to pak identifier
	-- This will only be true if the pak inserted is the one we're checking,
	-- because the register also enables the device
	local status, val = self:pak_register_read(0x8)
	if val == 0x80 then
		-- Return pak state to what it was previously
		self:register_pop_state(0x8)
		return true
	end

	-- Return pak state to what it was previously
	self:register_pop_state(0x8)
	return false
end

function controller:has_transfer_pak()
	-- Get state of pak before modifications
	self:register_push_state(0x8)

	self:pak_register_write(0x8, 0xFE)
	local status, val = self:pak_register_read(0x8)

	-- Reading from 0x8, after writing 0xFE should be 0x00
	-- Some third party controllers, when a mempak is inserted, return whatever is in the register.
	-- So for example..
	-- writing 0x84 and reading the register back would return 0x84, making it think the transfer pak is in.
	-- This check fixes false positives.
	if val ~= 0x00 then
		-- Return pak state to what it was previously
		self:register_pop_state(0x8)
		return false
	end

	-- Write pak identifier
	self:pak_register_write(0x8, 0x84)

	-- Check register is equal to pak identifier
	-- This will only be true if the pak inserted is the one we're checking,
	-- because the register also enables the device
	local status, val = self:pak_register_read(0x8)
	if val == 0x84 then
		-- Return pak state to what it was previously
		self:register_pop_state(0x8)
		return true
	end

	-- Return pak state to what it was previously
	self:register_pop_state(0x8)
	return false
end

function controller:rumble_init(power)
	local status = self:pak_register_write(0x8, power and 0x80 or 0xFE)
	return status and self:rumble_is_init()
end

function controller:rumble_is_init()
	local status, val = self:pak_register_read(0x8)
	return status and val == 0x80
end

function controller:rumble_set_power(enabled)
	-- Turn on/off power to the motor
	return self:pak_register_write(0xC, enabled and 0x01 or 0x00)
end

function controller:rumble_get_power()
	local status, val = self:pak_register_read(0xC)
	return status and val == 0x01
end

function controller:tpak_init()
	local status = self:pak_register_write(0x8, 0x84)
	return status and self:tpak_is_init()
end

function controller:tpak_is_init()
	local status, val = self:pak_register_read(0x8)
	return status and val == 0x84
end

-- 0xB flags
local TPAK_HAS_POWER	= 0x01 -- The only flag we can actually control, I think..
local TPAK_RESET		= 0x04
local TPAK_READY		= 0x08
local TPAK_CART_REMOVED	= 0x40 -- Set when a cart is pulled out
local TPAK_HAS_CART		= 0x80 -- Set when a cart is inserted

function controller:tpak_set_flag(flag, enabled)
	local status, flags = self:pak_register_read(0xB)
	if enabled then
		flags = bor(flags, flag)
	else
		flags = band(flags, bnot(flag))
	end
	return self:pak_register_write(0xB, flags)
end

function controller:tpak_get_flags()
	local status, flags = self:pak_register_read(0xB)
	return flags
end

function controller:tpak_has_flag(flag)
	local status, flags = self:pak_register_read(0xB)
	return status and band(flags, flag) ~= 0
end

function controller:tpak_set_ram_enabled(enabled)
	return self:tpak_write(0x0000, enabled and 0x0A or 0x00)
end

function controller:tpak_read(addr)
	local rshift_14 = rshift(addr, 14)

	if rshift_14 ~= self.tpak_high_bits then
		self.tpak_high_bits = rshift_14
		self:pak_register_write(0xA, self.tpak_high_bits)
	end

	return self:pak_read(bor(addr, 0xC000))
end

function controller:tpak_safe_read(addr)
	-- Always check cart status
	-- A removed cart will just return 0's without errors
	if not self:tpak_has_flag(TPAK_HAS_CART) then
		return false, "failed to read from cart, cart not inserted"
	end

	local status, read = self:tpak_read(addr)

	if not status then
		-- Return error on unsuccessful read
		return false, ("failed reading from address %04X"):format(addr)
	end

	return status, read
end

function controller:tpak_write(addr, value)
	local rshift_14 = rshift(addr, 14)

	if rshift_14 ~= self.tpak_high_bits then
		self.tpak_high_bits = rshift_14
		self:pak_register_write(0xA, self.tpak_high_bits)
	end

	local write = rep(char(value), 32)
	return self:pak_write(bor(addr, 0xC000), write)
end

function controller:tpak_push_state()
	self:register_push_state(0x8)
	self:register_push_state(0xB)
end

function controller:tpak_pop_state()
	self:register_pop_state(0x8)
	self:register_pop_state(0xB)
end

function controller:dump_tpak_cart_ram(f)
	if not self:tpak_init() then
		return false, "failed to initialize transfer pak, is it inserted?"
	end

	-- Get state of pak before modifications
	self:tpak_push_state()

	-- Enable power
	self:tpak_set_flag(TPAK_HAS_POWER, true)

	if not self:tpak_has_flag(TPAK_HAS_POWER) then
		-- Return pak state to what it was previously
		self:tpak_pop_state()
		return false, "failed to enable transfer pak power"
	end

	if not self:tpak_has_flag(TPAK_HAS_CART) then
		-- Return pak state to what it was previously
		self:tpak_pop_state()
		return false, "transfer pak has no cartridge"
	end

	if not self:tpak_set_ram_enabled(true) then
		-- Return pak state to what it was previously
		self:tpak_pop_state()
		return false, "failed to enable transfer pak ram"
	end

	local status, cart_header = self:tpak_read(0x0140)
	local cart_type = byte(cart_header, 8)
	local ram_code = byte(cart_header, 10)
	local ram_size = controller.RAM_SIZES[ram_code] or 0

	-- MBC2 (0x05/0x06) carts should have ram built in
	-- This chip contains 512/4bit, built in, memory banks
	-- See below for how this should be handled
	if cart_type == 0x05 or cart_type == 0x06 then
		-- This size isn't defined in the cart header
		ram_size = 512
	end

	if ram_size <= 0 then
		-- Return pak state to what it was previously
		self:tpak_pop_state()
		return false, "invalid ram size: " .. ram_size
	end

	progress.start()

	if cart_type == 0x05 or cart_type == 0x06 then
		-- MBC2 uses built in 512 4bit ram
		-- However the save data is returned in bits, meaning
		-- only the lower 4 bits actually contain the data we need
		for addr=0xA000, 0xA1FF, 32 do
			local status, read = self:tpak_safe_read(addr)
			if not status then return status, read end
			-- Loop through the data 2 bytes at a time
			for i=1,#read, 2 do
				-- Get the first byte and strip the insignificant upper 4 bits
				local lb = band(string.byte(read, i, i), 0x0F)
				-- Get the second byte and strip the insignificant upper 4 bits
				local hb = band(string.byte(read, i+1, i+1), 0x0F)
				-- Combine the two into a single byte
				local byte = bor(lb, lshift(hb, 4))

				-- Write!
				f:write(string.char(byte))
			end
			progress.print(addr+32-0xA000, ram_size)
		end
	else
		-- Other memory controllers are easy
		local banks = floor(ram_size / 0x2000)
		for i=1,banks do
			-- Set RAM bank number
			if not self:tpak_write(0x4000, i-1) then
				return false, "failed to set cart RAM bank number: " .. i-1
			end

			-- Read from RAM addresses, 32 bytes at a time
			for addr=0xA000, 0xBFFF, 32 do
				local status, read = self:tpak_safe_read(addr)
				if not status then return status, read end
				f:write(read)
				progress.print((addr+32-0xA000) + ((i-1)*(0xC000-0xA000)), ram_size)
			end
		end
	end

	-- Return pak state to what it was previously
	self:tpak_pop_state()
	return true
end

function controller:dump_tpak_cart_rom(f)
	if not self:tpak_init() then
		return false, "failed to initialize transfer pak, is it inserted?"
	end

	-- Get state of pak before modifications
	self:tpak_push_state()

	-- Enable power
	self:tpak_set_flag(TPAK_HAS_POWER, true)

	-- Check power
	if not self:tpak_has_flag(TPAK_HAS_POWER) then
		-- Return pak state to what it was previously
		self:tpak_pop_state()
		return false, "failed to enable transfer pak power"
	end

	-- Check if cart is inserted
	if not self:tpak_has_flag(TPAK_HAS_CART) then
		-- Return pak state to what it was previously
		self:tpak_pop_state()
		return false, "transfer pak has no cartridge"
	end

	local status, cart_header = self:tpak_read(0x0140)
	local cart_type = byte(cart_header, 8)
	local rom_code = byte(cart_header, 9)
	local rom_bytes = controller.ROM_SIZES[rom_code]

	if rom_bytes <= 0 then
		-- Return transfer pak state to what it was previously
		self:tpak_pop_state()
		return false, "rom has an invalid size"
	end

	progress.start()

	-- Dump first bank 32 bytes at a time
	for addr=0x0000,0x3FFF,32 do
		local status, read = self:tpak_safe_read(addr)
		if not status then return status, read end

		-- Write it to the file!
		f:write(read)
		-- Update progress
		progress.print(addr+32, rom_bytes)
	end

	-- Dump remaining banks using bank switching
	for i=1,((rom_bytes-0x4000) / 0x4000) do
		if cart_type == 0x05 or cart_type == 0x06 then
			-- MBC2 seems to use 0x2100-0x3FFF for ROM bank
			self:tpak_write(0x2100, i)
		else
			-- Everything else should use 0x2000-0x3FFF
			self:tpak_write(0x2000, i)
		end
		-- Read ROM bank 32 bytes at a time
		for addr=0x4000, 0x7FFF, 32 do
			local status, read = self:tpak_safe_read(addr)
			if not status then return status, read end

			-- Write it to the file!
			f:write(read)
			-- Update progress
			progress.print(addr + 32 + ((i-1)*(0x8000-0x4000)), rom_bytes)
		end
	end

	-- Return pak state to what it was previously
	self:tpak_pop_state()
	return true
end

function controller:dump_memory_pak(f)
	if not self:has_memory_pak() then return false, "memory pak not inserted" end

	progress.start()

	-- Loop through the 32Kib of RAM, 32 bytes at a time
	for addr=0x0000,0x7FFF,32 do
		-- Read 32 bytes at the address
		local status, data = self:pak_read(addr)
		if not status then
			-- Return error on unsuccessful read
			return false, ("failed reading from address %04X"):format(addr)
		end
		-- Write it to the file!
		f:write(data)
		-- Update progress
		progress.print(addr + 32, 0x8000)
	end

	return true
end

function controller:restore_memory_pak(f)
	if not self:has_memory_pak() then return false, "memory pak not inserted" end

	progress.start()

	for addr=0x0000,0x7FFF,32 do
		-- Set position in file to address
		f:seek("set", addr) -- Not entirely necessary
		-- Read the 32 bytes of data from our backup file
		local data = f:read(32)
		-- Write it to the corresponding address in RAM
		if not self:pak_write(addr, data) then
			-- Return error on unsuccessful write
			return false, ("failed writing to address %04X"):format(addr)
		end
		-- Update progress
		progress.print(addr + 32, 0x8000)
	end

	return true
end

function controller:test()
	print("has_pak", self:has_pak())
	print("has_memory_pak", self:has_memory_pak())
	print("has_rumble_pak", self:has_rumble_pak())
	print("has_transfer_pak", self:has_transfer_pak())
	return true
end

return controller