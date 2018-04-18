local bit = require("bit")

local band = bit.band
local bor  = bit.bor
local bnot = bit.bnot
local bxor = bit.bxor
local lshift = bit.lshift
local rshift = bit.rshift

for i=1, 32 do
	if lshift(i, 4) ~= i << 4 then
		return error("something went wrong with lshift")
	end
	if rshift(i, 4) ~= i >> 4 then
		return error("something went wrong with rshift")
	end
	if band(i, 0xF) ~= i & 0xF then
		return error("something went wrong with rshift")
	end
end

print("ALL GOOD")