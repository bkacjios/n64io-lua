local progress = {
	last_amount = 0,
	start_time = 0,
}

function progress.start()
	progress.start_time = os.clock()
end

function progress.round(num, places)
	local mult = 10 ^ (places or 0)
	return math.floor(num * mult + 0.5) / mult
end

function progress.nice_size(size)
	if size <= 0 then return "0" end
	if size < 1024 then return size .. " Bytes" end
	if size < 1024 * 1024 then return progress.round(size / 1024, 2) .. " KB" end
	if size < 1024 * 1024 * 1024 then return progress.round(size / (1024 * 1024), 2) .. " MB" end
	return progress.round(size / (1024 * 1024 * 1024), 2) .. " GB"
end

function progress.print(cur, max, width)
	local maxbars = width or 30
	local perc = cur/max

	local bars		= string.rep("=", math.floor(perc*maxbars))
	local spaces	= string.rep(" ", math.ceil((1-perc)*maxbars))

	local elapsed	= os.clock() - progress.start_time
	local speed		= cur / elapsed
	local estimate	= elapsed * max / cur

	local percNum = math.floor(perc * 100)

	if progress.last_amount ~= cur then -- Only update when a new bar is needed
		io.stdout:write(("%4s%% [%s>%s] (%d/%d) %s/s (%d secs) %s"):format(percNum, bars, spaces, cur, max, progress.nice_size(speed), estimate - elapsed, percNum < 100 and "\r" or "\n"))
		io.stdout:flush()
		progress.last_amount = cur
	end
end

return progress