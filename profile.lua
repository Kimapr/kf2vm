local profile = require "jit.profile"
local start, stop, dumpstack =
	profile.start, profile.stop, profile.dumpstack
local tonumber = tonumber
function profiler_start(period, outfile)
	local function record(thread, samples, vmstate)
		outfile:write(dumpstack(thread, "pF;", -100), vmstate,
			" ", samples, "\n")
	end
	start("vfi" .. tonumber(period), record)
end
function profiler_stop()
	stop()
end
outfile = io.open("profile","w")
profiler_start(1,outfile)
dofile("bench.lua")
profiler_stop()
outfile:close()
os.execute("flamegraph.pl profile > gr.svg")
