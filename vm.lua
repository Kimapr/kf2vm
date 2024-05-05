local lib = {}
local base = (... or "vm"):match("(.-)[^%.]+$")
local num = require(base .. "num")

function lib.new()
end

return lib
