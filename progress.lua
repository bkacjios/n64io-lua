local progress = {
	start_time = 0,
}

function progress.start()
	progress.start_time = os.clock()
end

function progress.nice_size(size)
	if size <= 0 then return "0" end
	if size < 1024 then return string.format("%0.2f Bytes", size) end
	if size < 1024 * 1024 then return string.format("%0.2f KB", size / 1024) end
	if size < 1024 * 1024 * 1024 then return string.format("%0.2f MB", size / (1024 * 1024)) end
	return string.format("%0.2f GB", size / (1024 * 1024 * 1024))
end

function progress.update(cur, max, width)
	local maxbars = width or 30
	local perc = cur/max

	local bars		= string.rep("=", math.floor(perc*maxbars))
	local spaces	= string.rep(" ", math.ceil((1-perc)*maxbars))

	local elapsed	= os.clock() - progress.start_time
	local speed		= cur / elapsed
	local estimate	= elapsed * max / cur

	local percNum = math.floor(perc * 100)

	-- Clear the line
	io.stdout:write("\27[2K")
	-- Print status
	io.stdout:write(("%4s%% [%s>%s] (%d/%d) %s/s (%d secs)\r"):format(percNum, bars, spaces, cur, max, progress.nice_size(speed), estimate - elapsed))
	io.stdout:flush()
end

function progress.finish()
	-- End the line
	io.stdout:write("\n")
end

return progress