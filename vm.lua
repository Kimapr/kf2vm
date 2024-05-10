local lib = {}
local base = (... or "vm"):match("(.-)[^%.]+$")
local num = require(base .. "num")

local mem = {}
mem.__index = mem

do
	assert(num.BITWIDTH%8 == 0, "invalid platform bitwidth")
	local words = math.floor(num.BITWIDTH / 8)
	local bw = num.BITWIDTH
	local tmp = num.new(0,bw)
	local lns = #tmp

	function mem.new(size)
		local obj = setmetatable({}, mem)
		size = math.ceil(size / words) * words
		for n = 1,lns * (size / words) do
			obj[n] = 0
		end
		return obj
	end

	local function tm(self,n)
		local off = n*lns
		for i=off+1,off+lns do
			tmp[i-off] = self[i] or bit.bnot(0)
		end
		for i=off+lns+1,off+math.ceil(tmp.bitwidth / bw) do
			tmp[i-off] = 0
		end
	end

	local function tmw(self,n)
		local off = n*lns
		for i=off+1, off+lns do
			self[i] = tmp[i-off]
		end
	end

	function mem:read(at,to)
		local bitwidth = to.bitwidth
		to:bxor(to,to)
		assert(to.bitwidth % 8 == 0, "not byte addressed")
		local bytew = math.floor(bitwidth / 8)
		local n1,n2 = math.floor(at/words),math.floor((at+bytew-1)/words)
		tmp:set_bitwidth(math.max(bw,bitwidth))
		tm(self,n1)
		tmp:rshift(at%words*8,tmp)
		tmp:movzx(to)
		local off = bw - at%words*8
		local ob
		for n=n1+1,n2 do
			ob = tmp.bitwidth
			tmp:set_bitwidth(bitwidth)
			tm(self,n)
			tmp:lshift(off,tmp)
			tmp:bor(to,to)
			tmp:set_bitwidth(ob)
			off=off+bw
		end
		return to
	end

	local tmpto = num.new(0,bw)
	local tmpfr = num.new(0,bw)
	local mask = num.new(0,bw)

	function mem:write(at,to)
		--[[
		local bitwidth = to.bitwidth
		assert(to.bitwidth % 8 == 0, "not byte addressed")
		local bytew = math.floor(bitwidth / 8)
		local n1,n2 = math.floor(at/words),math.floor((at+bytew-1)/words)
		tmpto.bitwidth = math.max(bw,to.bitwidth)
		tmp.bitwidth = bw
		mask.bitwidth = tmpto.bitwidth
		tmpfr.bitwidth = tmpto.bitwidth
		to:movzx(tmpto)
		tm(self,n1)
		tmp:movzx(tmpfr)
		tmpto:lshift(at%words*8)
		mask:from_lnum(0):bnot(mask)
		:rshift(math.max(0,mask.bitwidth-to.bitwidth),mask)
		mask:lshift(at%words*8,mask):band(tmpto,tmpto)
		mask:bnot(mask):band(tmpfr,tmpfr):bor(tmpto,tmpfr)
		:movzx(tmp)
		local off = bw - at%words*8
		tmw(self,n1)
		for n=n1+1,n2-1 do
			
		end
		return to
		--]] error("todo")
	end

end

lib.__index = lib
setmetatable(lib,lib)

function lib.new(memsize)
	local obj = {}

end

local m = mem.new(1024*64)

m[2] = 1 + 2*2^8 + 3*2^16 + 4*2^24 + 2^31
math.randomseed(os.time())
m[3] = math.random(0,2^31-1)
for n=1,#m do
	m[n] = num.bit.bor(m[n],m[n])
end
---[[
--m[2] = num.bit.bnot(0)

for bw=8,num.BITWIDTH*4,8 do
for n=-2,num.BITWIDTH*4/8-bw/8 do
print((' '):rep((n+2)*8)..m:read(n,num.new(0,bw)):binf():reverse())
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
	for u=0,4 do
		local ocl = os.clock()
		for n=1,steps do
			m:read(u,reg)
		end
		clocks[u] = (clocks[u] or 0) + (os.clock()-ocl)
	end
	ii=ii+1
until os.clock()-ocl > 5
for u=0,#clocks do
	print("*(long long*)"..u,(steps*ii)/(clocks[u])/(1000000) .. " MIPS")
end

return lib
