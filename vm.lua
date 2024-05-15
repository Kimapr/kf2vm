--[[
8-bit instruction
we are little endian

stack BASED
	stack element is 4 bytes
	1 byte is 8 bits
	registers hold 32 bits.

3 register
	ip, sp, bp
	ip points to instruction
	sp, bp usable as stack (grows downwards)
--]]


local lib = {}
local base = (... or "vm"):match("(.-)[^%.]+$")
local num = require(base .. "num")
local bit = num.bit

local mem = {}
mem.__index = mem
lib.mem = mem

-- 32 is holy number DO NOT CHANGE
local vmbw = 32

do
	local bw = num.BITWIDTH
	assert(bw%vmbw == 0 and bw>0, "invalid platform bitwidth")
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

local function rbn(s)
	return tonumber(s:reverse(),2)
end

lib.__index = lib
setmetatable(lib,lib)
local zero = num.new(0,vmbw)
local one = num.new(1,vmbw)
local es_p = num.new(vmbw/8,vmbw)
local es_n = num.new(-vmbw/8,vmbw)

local nmax = math.floor(2^vmbw)
local vmbb = math.floor(vmbw/8)

assert(vmbw == 32, "HOLY NUMBER CHANGED")
local mrword  = num.new(0,32)
local mrhword = num.new(0,16)
local mrbyte  = num.new(0,8)

local function norptr(ptr)
	return ptr[1]%nmax
end
if num.new(-1,vmbw)[1] > 0 then
	function norptr(ptr)
		return ptr[1]
	end
end

function lib.new(opts)
	local obj = {}
	opts = opts or {}

	obj.clockrate = opts.clockrate or 16*1024
	obj.pagesize  = opts.pagesize  or 1024
	obj.mmusize   = opts.mmusize   or 128
	obj.memsize   = math.ceil((opts.memsize  or 640*1024)/obj.pagesize)
	                -- 640K ought to be enough for anybody
	                --  - bill gae
	obj.reserved  = math.ceil((opts.reserved or 8)/obj.pagesize)
	obj.memsizeb  = obj.memsize * obj.pagesize
	obj.reservedb = obj.reserved * obj.pagesize
	obj.totalmemb = obj.memsizeb + obj.reservedb

	obj.mem  = mem.new(obj.memsize * obj.pagesize)
	obj.resmap = {[0]={
		lib.nullrm
	}}
	obj.cycles = 0

	obj.ip     = num.new(obj.reservedb,vmbw)
	obj.sp     = num.new(obj.totalmemb,vmbw)
	obj.bp     = num.new(0,vmbw)
	obj.tmp1   = num.new(0,vmbw)
	obj.tmp2   = num.new(0,vmbw)
	obj.tmp3   = num.new(0,vmbw)
	obj.mode   = num.new(0,vmbw)
	obj.opcode = num.new(0,vmbw)

	setmetatable(obj,lib)
	if opts.code then
		obj:load(obj.reservedb,opts.code)
	end
	return obj
end

function lib:teat(n)
	self.cycles = self.cycles - n
end

lib.nullrm = {
	pos=0, len=12,
	read = function(o,self,at,to)
		if w ~= vmbb then return end
		if at==vmbb then
			to[1] = self.reservedb
		elseif at==vmbb*2 then
			to[1] = self.reservedb + self.memsizeb
		elseif at==0 then
			to[1] = 1
		else
			return
		end
		to:bor(to,to)
		return to
	end,
	write = function() end
}

lib.isa = {
	[0] = function(self)
		return true
	end,
	function() return false, "halt" end,
	function(self)
		self.ip[1] = self.reservedb
		self.ip:bor(self.ip,self.ip)
		self.opcode:bxor(self.opcode,self.opcode)
		return true
	end
}
lib.isadoc = {[0]="nop"}
local lasti, lastni = 0,0

local function s_imm(reg)
	return function(self)
		local ok,err = self:read(norptr(self.ip),mrbyte)
		if not ok then
			return ok,err
		end
		self.ip:add(one,self.ip)
		mrbyte:movsx(self[reg])
		return true
	end
end

lib.asms = {}

local function isadoc(i,doc)
	lib.isadoc[i] = doc
	if i > 255 then return end
	lib.asms[doc] = string.char(i)
end

local function insins(doc,f,...)
	lasti=lasti+1
	local fl={...}
	if #fl>0 then
		local ff = f
		local nextf = lastni - 1
		f = function(self,...)
			local ok,err = ff(self,...)
			if not ok then return ok,err end
			self.opcode[1] = nextf
			self.opcode:bor(self.opcode,self.opcode)
			return true
		end
	else
		local ff=f
		function f(self,...)
			local ok,err = ff(self,...)
			if not ok then return ok,err end
			self.opcode:bxor(self.opcode,self.opcode)
			return true
		end
	end
	isadoc(lasti,doc)
	lib.isa[lasti%nmax] = f
	for k,f in ipairs(fl) do
		lastni = lastni - 1
		if k<#fl then
			local ff=f
			local nextf = lastni - 1
			function f(self,...)
				local ok,err = ff(self,...)
				if not ok then return ok,err end
				self.opcode[1] = nextf
				self.opcode:bor(self.opcode,self.opcode)
				return true
			end
		else
			local ff=f
			function f(self,...)
				local ok,err = ff(self,...)
				if not ok then return ok,err end
				self.opcode:bxor(self.opcode,self.opcode)
				return true
			end
		end
		lib.isa[lastni%nmax] = f
		isadoc(lastni%nmax,doc.." cont#"..k)
	end
end

insins("halt",function()
	return false, "halt"
end)

for _,a in ipairs {
	{"reg","ip"},
	{"reg","sp"},
	{"reg","bp"},
	{"stack","sp"},
	{"stack","bp"},
	{"imm",1}
} do
for _,b in ipairs {
	{"reg","ip"},
	{"reg","sp"},
	{"reg","bp"},
	{"stack","sp"},
	{"stack","bp"},
} do (function()
	if (a[1] == b[1]) and not (a[1]=="stack") then return end
	if (a[1] == b[1]) and (a[2] == b[2]) then return end
	local rega,regb = a[2],b[2]
	insins(("mov %s to %s"):format(table.concat(a," "),table.concat(b," ")),
		({
			reg = function(self)
				self[rega]:movzx(self.tmp1)
				return true
			end,
			stack = function(self)
				return self:pop(self[rega],self.tmp1)
			end,
			imm = s_imm("tmp1"),
		})[a[1]],
		({
			reg = function(self)
				self.tmp1:movzx(self[regb])
				return true
			end,
			stack = function(self)
				return self:push(self[regb],self.tmp1)
			end,
			print = function(self)
				print("DEBUG MOV: "..self.tmp1[1])
				return true
			end,
		})[b[1]]
	)
end)() end end
insins("dup stack sp",
	function(self)
		return self:pop(self.sp,self.tmp1)
	end,
	function(self)
		self.sp:add(sp_n,self.sp)
		return self:push(self.sp,self.tmp1)
	end
)
for opk,op in ipairs {"add","sub","band","bor","bxor","lshift","rshift","arshift"} do
for _,a in ipairs {
	{"reg","ip"},
	{"reg","sp"},
	{"reg","bp"},
	{"stack","sp"},
} do
for _,b in ipairs {
	{"stack","sp"},
	{"imm",1},
} do (function()
	if op == "sub" and b[1] == "imm" then return end
	if opk > 2 then for _=1,1 do
		if op == "band" then
			if b[1] == "stack" and a[1] ~= "stack" then return end
			break
		end
		if not ((a[1] == "stack") and (b[1] == "stack")) then return end
	end end
	local rega,regb = a[2],b[2]
	insins(("%s %s to %s"):format(op,table.concat(b," "),table.concat(a," ")),
		({
			stack = function(self)
				return self:pop(self[regb],self.tmp2)
			end,
			imm = s_imm("tmp2"),
		})[b[1]],
		({
			reg = function(self)
				self[rega]:movzx(self.tmp1)
				return true
			end,
			stack = function(self)
				return self:pop(self[rega],self.tmp1)
			end,
		})[a[1]],
		function(self)
			self.tmp1[op](self.tmp1,self.tmp2,self.tmp1)
			return true
		end,
		({
			reg = function(self)
				self.tmp1:movzx(self[rega])
				return true
			end,
			stack = function(self)
				return self:push(self[rega],self.tmp1)
			end,
		})[a[1]]
	)
end)() end end end
for _,op in ipairs {"bnot","neg"} do
(function()
	insins(op.." stack sp"
		function(self)
			return self:pop(self.sp,self.tmp1)
		end,
		function(self)
			self.tmp1[op](self.tmp1,self.tmp1)
			return true
		end,
		function(self)
			return self:push(self.sp,self.tmp1)
		end
	)
end)() end

function lib:push(stack,val)
	assert(val.bitwidth == vmbw,"bad stack value")
	stack:add(es_n,stack)
	local ok,err = self:write(norptr(stack),val)
	if not ok then
		stack:add(es_p,stack)
		return ok,err
	end
	return true
end

function lib:pop(stack,to)
	assert(to.bitwidth == vmbw,"bad stack value")
	local ok,err = self:read(norptr(stack),to)
	if not ok then return ok,err end
	stack:add(es_p,stack)
	return true
end

function lib:findres(at)
	local res = self.resmap[math.floor(at/self.pagesize)]
	if res then
		local data
		for k,v in ipairs(res) do
			if at>=v.pos and at<(v.pos+v.len) then
				return v
			end
		end
	end
end

function lib:load(at,str)
	str:gsub(".",function(c)
		mrbyte[1] = c:byte()
		assert(self:write(at,mrbyte))
		at=at+1
	end)
end

function lib:read(at,to)
	local bs = math.floor(to.bitwidth/8)
	if vmbb<(at%vmbb+bs) then
		return false, "memfail"
	end
	local res = self:findres(at)
	if res then
		if not res:read(self,at-res.pos,to) then
			return false, "memfail"
		end
		return true
	end
	if not self.mem:read(at-self.reservedb,to) then
		return false, "memfail"
	end
	return true
end

function lib:write(at,to)
	local bs = math.floor(to.bitwidth/8)
	if vmbb<(at%vmbb+bs) then
		return false, "memfail"
	end
	local res = self:findres(at)
	if res then
		if not res:write(self,at-res.pos,to) then
			return false, "memfail"
		end
		return true
	end
	if not self.mem:write(at-self.reservedb,to) then
		return false, "memfail"
	end
	return true
end

local function gdoc(opcode)
	return (lib.isadoc[norptr(opcode)] or "?")
end

local function trapped(f)
	return function(self,...)
		local ok,err = f(self,...)
		if not ok then error((err or "unknown err").." at "..gdoc(self.opcode)) end
	end
end

lib.step = trapped (-- in my basement )
(function() local function step(self)
	if self.opcode[1] == 0 then
		local ok,err = self:read(norptr(self.ip),mrbyte)
		self:teat(1)
		if not ok then return ok, err end
		mrbyte:movzx(self.opcode)
		self.ip:add(one,self.ip)
	end
	local fn = self.isa[norptr(self.opcode)]
	--print(self.cycles.." executing " .. norptr(self.opcode) .. " " .. gdoc(self.opcode) .. " at "..norptr(self.ip))
	if not fn then
		return false, "badcode"
	end
	local ok,err = fn(self)
	if not ok then return ok,err end
	if self.opcode[1] ~= 0 then
		return step(self)
	end
	return true
end return step end)())

function lib:update(dt)
	self.cycles = self.cycles + self.clockrate * dt
	local cyc = 0
	while self.cycles > 0 do
		self:step()
		cyc = cyc + 1
	end
	return cyc
end

return lib
