
--[[function n64.addr_crc(addr)
	-- CRC Table
	local xor_table = { 0x0, 0x0, 0x0, 0x0, 0x0, 0x15, 0x1F, 0x0B, 0x16, 0x19, 0x07, 0x0E, 0x1C, 0x0D, 0x1A, 0x01 }
	local crc = 0

	addr = bit.band(addr, bit.bnot(0x1F))

	-- Go through each bit in the address, and if set, xor the right value into the output
	for i=15,5,-1 do
		-- Is the bit set?
		if bit.band(bit.rshift(addr, i), 0x1) ~= 0 then
			crc = bit.bxor(xor_table[i+1])
		end
	end

	return bit.bor(addr, crc)
end]]

--[[
32768
32794
]]

--[[function n64.addr_crc(addr)
	assert(bit.band(addr, 0x1F) == 0, "Address must be 32-bit aligned")

	local table = {0x15, 0x1F, 0x0B, 0x16, 0x19, 0x07, 0x0E, 0x1C, 0x0D, 0x1A, 0x01}

	addr = bit.band(addr, 0xFFE0)

	for i=1,11 do
		if bit.band(addr, bit.lshift(1, i+5)) ~= 0 then
			addr = bit.bxor(addr, table[i])
		end
	end

	return addr
end]]
