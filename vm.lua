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
local num
if minetest then
	num = dofile(minetest.get_modpath(minetest.get_current_modname()).."/num.lua")
else
	local base = (... or "vm"):match("(.-)[^%.]+$")
	num = require(base .. "num")
end
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
		obj.size = math.ceil(size / words) * words
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
      -- say my name
      -- - mr byte

local function norptr(ptr)
	return ptr[1]%nmax
end
if num.new(-1,vmbw)[1] > 0 then
	function norptr(ptr)
		return ptr[1]
	end
end

lib.isa = {}
lib.isadoc = {}
local lasti, lastni = -1,0
lib.asms = {}
lib.insw = {}

function lib.new(opts)
	local obj = {}
	opts = opts or {}

	obj.clockrate = opts.clockrate or 64*1024
	obj.pagesize  = opts.pagesize  or 1024
	obj.mmusize   = opts.mmusize   or 128
	obj.memsize   = math.ceil((opts.memsize  or 640*1024)/obj.pagesize)
	                -- 640K ought to be enough for anybody
	                --  - bill gae
	obj.memsizeb  = obj.memsize * obj.pagesize

	obj.resmap = {}
	obj.memps = {}
	obj.isa = setmetatable({},{__index = lib.isa})
	obj.lastni = lastni
	obj.cycles = 0

	obj.ip     = num.new(0,vmbw)
	obj.sp     = num.new(obj.memsizeb,vmbw)
	obj.bp     = num.new(0,vmbw)
	obj.tmp1   = num.new(0,vmbw)
	obj.tmp2   = num.new(0,vmbw)
	obj.tmp3   = num.new(0,vmbw)
	obj.mode   = num.new(0,vmbw)
	obj.opcode = num.new(0,vmbw)

	setmetatable(obj,lib)
	if opts.code then
		obj:load(0,opts.code)
	end
	return obj
end

function lib:add_memio(obj)
	for p=math.floor(obj.pos/self.pagesize),
	      math.floor((obj.pos-1+obj.len)/self.pagesize) do
		self.resmap[p] = self.resmap[p] or {}
		table.insert(self.resmap[p],1,obj)
	end
end

function lib:del_memio(obj)
	for p=math.floor(obj.pos/self.pagesize),
	      math.floor((obj.pos-1+obj.len)/self.pagesize) do
		local pma = self.resmap[p]
		local good
		repeat
			good=true
			for k,v in pairs(pma) do
				if v==obj then
					table.remove(pma,k)
					good = false
					break
				end
			end
		until good
	end
end

function lib:palloc(at)
	self:pfree(at)
	local p = math.floor(at/self.pagesize)
	local m = mem.new(self.pagesize)
	self.memps[p] = m
	m.pos = p*self.pagesize
	m.len = self.pagesize
	m.rtype = "mem"
	self:add_memio(m)
end

function lib:pfree(at)
	local p = math.floor(at/self.pagesize)
	local m = self.memps[p]
	if not m then return end
	self:del_memio(m)
	self.memps[p] = nil
end

function lib:teat(n)
	self.cycles = self.cycles - n
end

local simmcs = {}
local sones = {}
for n=1,vmbb do
	simmcs[n] = num.new(0,n*8)
	sones[n] = num.new(n,vmbw)
end
local function s_imm(reg,width)
	width = width or 1
	local mr,i = simmcs[width],sones[width]
	return function(self)
		local ok,err = self:readx(norptr(self.ip),mr)
		if not ok then
			return ok,err
		end
		self.ip:add(i,self.ip)
		mr:movsx(self[reg])
		return true
	end
end

local function isadoc(i,doc)
	lib.isadoc[i] = doc
	if i > 255 then return end
	lib.asms[doc] = string.char(i)
end

local function insins_(doc,i,f,...)
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
	lib.insw[lasti%nmax] = i
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
local function insins(doc,i,f,...)
	if type(i)=="function" then
		return insins_(doc,0,i,f,...)
	end
	return insins_(doc,i,f,...)
end

insins("nop",function(self)
	return true
end)

for _,a in ipairs {
	{"reg","ip"},
	{"reg","sp"},
	{"reg","bp"},
	{"stack","sp"},
	{"stack","bp"},
	{"imm",1},
	{"imm",2},
	{"imm",3},
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
		a[1]=="imm" and a[2] or 0,
		({
			reg = function(self)
				self[rega]:movzx(self.tmp1)
				return true
			end,
			stack = function(self)
				return self:pop(self[rega],self.tmp1)
			end,
			imm = s_imm("tmp1",a[2]),
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
for _,ty in ipairs {
	"fetch","store"
} do
for _,bus in ipairs {
	{"word",mrword},
	{"hword",mrhword},
	{"byte",mrbyte},
} do
for _,addr in ipairs {
	{"stack","sp"},
	{"imm",1},
	{"imm",2},
	{"imm",3},
} do
for _,rel in ipairs {
	0,
	"ip",
	"sp",
	"bp",
} do
for _,ex in ipairs {
	{"zx","movzx"},
	{"sx","movsx"},
} do (function()
	if rel==0 and addr[1] == "imm" then return end
	if rel~=0 and addr[1] == "stack" then return end
	local to = bus[2]
	local exf = ex[2]
	if ty == "fetch" and ((bus[2].bitwidth < vmbw) or (ex[1] == "zx")) then
		insins(("fetch%s %s %s %s-rel to stack sp")
			:format((bus[2].bitwidth < vmbw) and ex[1] or "",bus[1],table.concat(addr," "),rel),
			addr[1] == "imm" and addr[2] or 0,
			({
				stack = function(self)
					return self:pop(self.sp,self.tmp1)
				end,
				imm = s_imm("tmp1",addr[2])
			})[addr[1]],
			function(self)
				self.tmp1:add(rel==0 and zero or self[rel],self.tmp1)
				return true
			end,
			function(self)
				local ok, err = self:read(norptr(self.tmp1),to)
				if not ok then return ok,err end
				to[exf](to,self.tmp1)
				return self:push(self.sp,self.tmp1)
			end
		)
	end
	if ty == "store" and ex[1] == "zx" then
		insins(("store %s stack sp to %s %s-rel")
			:format(bus[1],table.concat(addr," "),rel),
			addr[1]=="imm" and 1 or 0,
			({
				stack = function(self)
					return self:pop(self.sp,self.tmp1)
				end,
				imm = s_imm("tmp1")
			})[addr[1]],
			function(self)
				self.tmp1:add(rel==0 and zero or self[rel], self.tmp1)
				return true
			end,
			function(self)
				return self:pop(self.sp,self.tmp2)
			end,
			function(self)
				local ok,err = self:write(norptr(self.tmp1),self.tmp2)
				if not ok then return ok,err end
				return true
			end
		)
	end
end)() end end end end end
for opk,op in ipairs {
	"add","sub",
	"band","bor","bxor",
	"lshift","rshift","arshift"
} do
for _,a in ipairs {
	{"reg","ip"},
	{"reg","sp"},
	{"reg","bp"},
	{"stack","sp"},
	{"stack","bp"},
} do
for _,b in ipairs {
	{"stack","sp"},
	{"imm",1},
	{"imm",2},
	{"imm",3},
} do (function()
	if op == "sub" and b[1] == "imm" then return end
	if a[1]=="stack" and a[2]=="bp" and b[1]~="imm" then return end
	if opk > 2 then for _=1,1 do
		if op == "band" then
			if b[1] == "stack" and a[1] ~= "stack" then return end
			break
		end
		if not ((a[1] == "stack") and (b[1] == "stack")) then return end
	end end
	local rega,regb = a[2],b[2]
	insins(("%s %s to %s"):format(op,table.concat(b," "),table.concat(a," ")),
		b[1]=="imm" and b[2] or 0,
		({
			stack = function(self)
				return self:pop(self[regb],self.tmp2)
			end,
			imm = s_imm("tmp2",b[2]),
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
insins("add carry stack sp",
	function(self)
		return self:pop(self.sp,self.tmp3)
	end,
	function(self)
		return self:pop(self.sp,self.tmp2)
	end,
	function(self)
		return self:pop(self.sp,self.tmp1)
	end,
	function(self)
		local _,carry = self.tmp1:add(self.tmp2,self.tmp1,bit.band(self.tmp3[1],1))
		self.tmp2[1] = carry
		return true
	end,
	function(self)
		return self:push(self.sp,self.tmp1)
	end,
	function(self)
		return self:push(self.sp,self.tmp2)
	end
)
for _,op in ipairs {"bnot","neg"} do
(function()
	insins(op.." stack sp",
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
insins("mul stack sp",
	function(self)
		return self:pop(self.sp,self.tmp1)
	end,
	function(self)
		return self:pop(self.sp,self.tmp2)
	end,
	function(self)
		self.tmp1:mul(self.tmp2,self.tmp1)
		self:teat(3)
		return true
	end,
	function(self)
		return self:push(self.sp,self.tmp1)
	end
)
insins("div/mod stack sp",
	function(self)
		return self:pop(self.sp,self.tmp1)
	end,
	function(self)
		return self:pop(self.sp,self.tmp2)
	end,
	function(self)
		self.tmp1[1],self.tmp2[1]
		= norptr(self.tmp1),norptr(self.tmp2)
		self.tmp1[1],self.tmp2[1]
		= math.floor(self.tmp1[1]/self.tmp2[1]),
		  self.tmp1[1] % self.tmp2[1]
		self.tmp1:bor(self.tmp1,self.tmp1)
		self.tmp2:bor(self.tmp2,self.tmp2)
		self:teat(7)
		return true
	end,
	function(self)
		return self:push(self.sp,self.tmp1)
	end,
	function(self)
		return self:push(self.sp,self.tmp2)
	end
)
for _,op in ipairs {
	{"if==",function(sf,cf,of,zf) return zf end},
	{"if!=",function(sf,cf,of,zf) return not zf end},
	{"if<u",function(sf,cf,of,zf) return cf end},
	{"if>=u",function(sf,cf,of,zf) return not cf end},
	{"if<=u",function(sf,cf,of,zf) return cf and zf end},
	{"if>u",function(sf,cf,of,zf) return (not cf) and (not zf) end},
	{"if<s",function(sf,cf,of,zf) return sf ~= of end},
	{"if>=s",function(sf,cf,of,zf) return sf == of end},
	{"if<=s",function(sf,cf,of,zf) return zf or (sf ~= of) end},
	{"if>s",function(sf,cf,of,zf) return (not zf) and (sf == of) end},
} do (function()
	insins(op[1],
		function(self)
			return self:pop(self.sp,self.tmp1)
		end,
		function(self)
			return self:pop(self.sp,self.tmp2)
		end,
		function(self)
			local _,car = self.tmp1:sub(self.tmp2,self.tmp3)
			local as,bs,os = self.tmp1:sign(),self.tmp2:sign(),self.tmp3:sign()
			as,bs,os = as~=0, bs==0, bs~=0
			local over = as==bs and as~=os
			local zero = self.tmp3[1] == 0
			self.tmp1[1] = op[2](os,car,over,zero) and 1 or 0
			return true
		end,
		function(self)
			if self.tmp1[1] == 1 then return true end
			local ok,err = self:readx(norptr(self.ip),mrbyte)
			if not ok then return ok,err end
			mrbyte:movzx(self.opcode)
			self:teat(1)
			self.ip:add(one,self.ip)
			local w = self.insw[norptr(self.opcode)] or 0
			mrword[1] = w
			self.ip:add(mrword,self.ip)
			return true
		end
	)
end)() end
function lib:push(stack,val)
	assert(val.bitwidth == vmbw,"bad stack value")
	local a = stack[1]
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
		for k=#res,1,-1 do
			local v = res[k]
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
mem.load = lib.load

function lib:readx(at,to)
	-- todo: no-execute mmu bit
	return self:read(at,to)
end

function lib:read(at,to)
	local bs = math.floor(to.bitwidth/8)
	if vmbb<(at%vmbb+bs) then
		return false, "memfail"
	end
	local res = self:findres(at)
	if res then
		if not res:read(at-res.pos,to,self) then
			return false, "memfail"
		end
		return true
	end
	if at>=self.memsizeb then
		return false, "memfail"
	end
	to[1] = 0
	return true
end

function lib:write(at,to)
	local bs = math.floor(to.bitwidth/8)
	if vmbb<(at%vmbb+bs) then
		return false, "memfail"
	end
	local res = self:findres(at)
	if res then
		if not res:write(at-res.pos,to,self) then
			return false, "memfail"
		end
		return true
	end
	if at<self.memsizeb then
		self:palloc(at)
		return self:write(at,to)
	end
	return false, "memfail"
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
		local ok,err = self:readx(norptr(self.ip),mrbyte)
		self:teat(1)
		if not ok then return ok, err end
		mrbyte:movzx(self.opcode)
		---[[
		if self.debugging and norptr(self.opcode)<=255 then
			local dstr = {self.cycles.." executing "
			.. norptr(self.opcode) .. " " .. gdoc(self.opcode)
			.. " at "..norptr(self.ip)}
			do
				for k,v in ipairs{"ip","sp","bp"} do
					local ip = norptr(self[v])
					local str = {v..": "..("%.8x"):format(ip).."\t"}
					for x=ip-16,ip+16 do
						local n = x%nmax
						local suc = self:read(n,mrbyte)
						str[#str+1] = (n==ip and ">" or " ") .. (suc and ("%.2x"):format(mrbyte[1]) or "..")
					end
					dstr[#dstr+1]=table.concat(str)
				end
			end
			self.debug_str = table.concat(dstr,"\n")
		end
		--]]
		self.ip:add(one,self.ip)
	end
	local fn = self.isa[norptr(self.opcode)]
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
	local cycbeg = self.cycles
	local cyc = 0
	while self.cycles >= 1 do
		self:step()
		cyc = cyc + 1
	end
	return cyc, self.cycles - cycbeg
end

return lib
