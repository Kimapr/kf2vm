local lib = {}
local base = (... or "vm"):match("(.-)[^%.]+$")
local num = require(base .. "num")

local mem = {}
mem.__index = mem

do
	local bw = num.BITWIDTH
	assert(bw%32 == 0 and bw>0, "invalid platform bitwidth")
	local words = math.floor(bw / 8)
	local tmp = num.new(0,bw)
	local lns = #tmp

	function mem.new(size)
		local obj = setmetatable({}, mem)
		size = math.ceil(size / words) * words
		obj.digs = lns * (size/words)
		for n = 1, obj.digs do
			obj[n] = 0
		end
		return obj
	end

	function mem:read(at,to)
		local bitwidth = to.bitwidth
		to:bxor(to,to)
		local bytew = math.floor(bitwidth / 8)
		local n1,n2 = math.floor(at/words)+1,math.floor((at+bytew-1)/words)+1
		if n2 > n1 then return end
		if n1 <= 0 or n1>self.digs then return end
		tmp[1] = bit.rshift(self[n1], at%words*8)
		tmp:movzx(to)
		return to
	end

	function mem:write(at,to)
		local bitwidth = to.bitwidth
		local bytew = math.floor(bitwidth / 8)
		local n1,n2 = math.floor(at/words)+1,math.floor((at+bytew-1)/words)+1
		if n2 > n1 then return end
		if n1 <= 0 or n2>self.digs then return end
		local sh = at%words*8
		local mask = bit.lshift(bit.rshift(bit.bnot(0), bw-bitwidth),sh)
		local val = bit.band(bit.lshift(to[1],sh),mask)
		self[n1] = bit.bor(bit.band(self[n1],bit.bnot(mask)),val)
		return to
	end

end

lib.__index = lib
setmetatable(lib,lib)

function lib.new(opts)
	local obj = {}
	obj.clockrate = opts.clockrate or 16384
end

local m = mem.new(1024)

--[[
m[2] = 1 + 2*2^8 + 3*2^16 + 4*2^24 + 2^31
math.randomseed(os.time())
m[3] = math.random(0,2^31-1)
for n=1,#m do
	m[n] = num.bit.bor(m[n],m[n])
end
]]
m:write(0,num.new(1+2+4+8+16+32+64+1024,32))
m:write(2,num.new(65535,16))

local function bbinf(m,bw)
	if m then
		return m:binf():reverse()
	end
	return num.new(0,bw):binf():reverse():gsub("[0-9]","_")
end
---[[
--m[2] = num.bit.bnot(0)

for bw=8,num.BITWIDTH*4,8 do
for n=-2,num.BITWIDTH*4/8-bw/8 do
print((' '):rep((n+2)*8)..bbinf(m:read(n,num.new(0,bw)),bw))
end
print('('..bw..'b) 0..'..(num.BITWIDTH*4/8-bw/8))
end
do return end
--]]

local reg = num.new(0,32)
local steps=100000
local clocks={}
local ii=0
local ocl=os.clock()
repeat
	for u=8,0,-1 do
		local ocl = os.clock()
		for n=1,steps do
			m:read(u,reg)
		end
		clocks[u] = (clocks[u] or 0) + (os.clock()-ocl)
	end
	ii=ii+1
until os.clock()-ocl > 2
for u=0,#clocks do
	print("*(long long*)"..u,(steps*ii)/(clocks[u])/(1000000) .. " MIPS: "..bbinf(m:read(u,reg),reg.bitwidth))
end

return lib
