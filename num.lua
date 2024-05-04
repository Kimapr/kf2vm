local lib = {}

local bit = bit
local BITWIDTH
do
	local function JUDGE_INTEGER_BITWIDTH(bit)
		local n,l=1,1
		while 1 do
			n = bit.lshift(n,1)
			if n==0 then
				return l
			else
				l=l+1
			end
		end
	end

	local function JUDGE_INTEGER_BITLIB_SUITABILITY_FOR_USAGE(bit)
		return (bit and bit.lshift and bit.rshift and bit.arshift
		            and bit.band   and bit.bnot   and bit.bxor)
			and bit or nil
	end

	local bitlibs = {JUDGE_INTEGER_BITLIB_SUITABILITY_FOR_USAGE(bit)}
	local function tryreq(...)
		local ok,err = pcall(require, ...)
		if not ok then return nil end
		return JUDGE_INTEGER_BITLIB_SUITABILITY_FOR_USAGE(err)
	end
	bitlibs[#bitlibs + 1] = tryreq "bit"
	bitlibs[#bitlibs + 1] = tryreq "bit32"
	local l53ls = (loadstring or load or function() end)(
		"local n,s=... return n<<s")
	if l53ls then
		local bit = assert((loadstring or load)(([[
			local bit = {}
			function bit.arshift(n,s)
				return (n >> s) | ((~((n>>(BITWIDTH-1))-1)) << (BITWIDTH-s))
			end
			function bit.bnot(n)
				return ~n
			end
			BINOPS
			return bit
		]]):gsub('BITWIDTH',JUDGE_INTEGER_BITWIDTH {lshift = l53ls})
		   :gsub("BINOPS",("(band#&)(bxor#~)(bor#|)(lshift#<<)(rshift#>>)")
		   :gsub("%((.-)#(.-)%)","function bit.%1(a,b) return a%2b end\n"))))()
		bitlibs[#bitlibs + 1] = JUDGE_INTEGER_BITLIB_SUITABILITY_FOR_USAGE(bit)
	end

	bit = bitlibs[1]
	BITWIDTH = JUDGE_INTEGER_BITWIDTH(bit)
	for n = 2, #bitlibs do
		local libx = bitlibs[n]
		local bw = JUDGE_INTEGER_BITWIDTH(libx)
		if bw > BITWIDTH then
			bit, BITWIDTH = libx, bw
		end
	end
end
if not bit then
	error("no bitlib")
end
--[[
do
	local jbit = bit
	for k,f in pairs(jbit) do
		if type(f)=="function" then
			local m=2^32
			local of=f f=function(...)
				return of(...) % m
			end
		end
		bit[k]=f
	end
end
--]] -- questionable, sus amogus even

lib.bit = bit

lib.__index = lib

lib.BITWIDTH = BITWIDTH
local SIGNED = bit.bnot(0) == -1
lib.SIGNED = SIGNED
print ("BITWIDTH="..BITWIDTH, SIGNED and 'signed' or "unsigned")

local uibiw = 8
--local uibiw = BITWIDTH
local uimax = bit.bor(bit.lshift(1,uibiw) - 1, 0)
if uimax == 0 then
	uimax = bit.bnot(0)
end

local hibiw = bit.rshift(uibiw, 1)
local himlo = bit.lshift(1, hibiw) - 1
local himhi = bit.lshift(himlo, hibiw)

local temps = setmetatable({},{__index = function(self,bitwidth)
	self[bitwidth] = setmetatable({},{__index = function(self, k)
		self[k] = lib.new(0,bitwidth)
		return self[k]
	end})
	return self[bitwidth]
end})

local consts = setmetatable({},{__index = function(self,bitwidth)
	self[bitwidth] = setmetatable({},{__index = function(self, k)
		self[k] = lib.new(k,bitwidth)
		return self[k]
	end})
	return self[bitwidth]
end})

local bwm = setmetatable({},{__index = function(self,bitwidth)
	local mai = math.ceil(bitwidth / uibiw)
	local smsh = bitwidth - (mai-1)*uibiw - 1
	local mama = (smsh+1) < uibiw and bit.bor(bit.lshift(1, smsh + 1)-1,0) or uimax
	self[bitwidth] = {
		mama = mama,
		mai = mai,
		smsh = smsh,
	}
	return self[bitwidth]
end})

function lib.new(n,bitwidth)
	local w = bitwidth -- bitwidth is an epic word but i prefer short names
	local flip = false
	if n<0 then n,flip = -n, not flip end
	n = math.floor(n)
	local obj = setmetatable({}, lib)
	for i = 1, bwm[bitwidth].mai do
		obj[i] = bit.band(n,uimax)
		n = math.floor(n / uimax)
	end
	obj.bitwidth = bitwidth
	obj[bwm[bitwidth].mai] = bit.band(obj[bwm[bitwidth].mai], bwm[bitwidth].mama)
	if flip then obj:negate(obj) end
	return obj
end

function lib.assure_eqbits(a,b,...)
	if not b then return end
	assert(a.bitwidth == b.bitwidth, "bitwidth mismatch")
	return lib.assure_eqbits(b,...)
end

function lib.negate(n,to)
	to = n:bnot(n,to)
	return (to:add(consts[to.bitwidth][1],to))
end

local function split(n)
	return bit.band(n, himlo), bit.rshift(bit.band(n, himhi), hibiw)
end

function lib.sign(a)
	local mai = bwm[a.bitwidth].mai
	local smsh = bwm[a.bitwidth].smsh
	local sign = a[mai]
	--sign = bit.band(bit.rshift(sign,smsh),1)
	--sign = bit.arshift(bit.lshift(sign,BITWIDTH-1),BITWIDTH-1)
	--sign = bit.band(sign, uimax)
	sign = bit.band(bit.rshift(sign,smsh),1)
	sign = bit.bnot(sign - 1)
	return sign
end

function lib.add(a,b,to)
	to = to or lib.new(0, a.bitwidth)
	a:assure_eqbits(b,to)
	local mai = bwm[to.bitwidth].mai
	local mama = bwm[to.bitwidth].mama
	local carry = 0
	for i = 1, mai do
		local alo, ahi = split(a[i])
		local blo, bhi = split(b[i])
		local olo, ohi
		olo, carry = split(alo + blo + carry)
		ohi, carry = split(ahi + bhi + carry)
		to[i] = olo + bit.lshift(ohi, hibiw)
	end
	to[mai] = bit.band(to[mai], mama)
	return to,carry
end

function lib.sub(a,b,to)
	local b = b:negate(temps[b.bitwidth].subn)
	return a:add(b,to)
end

function lib.bnot(n,to)
	to = to or lib.new(0, n.bitwidth)
	n:assure_eqbits(to)
	local mai = bwm[to.bitwidth].mai
	local mama = bwm[to.bitwidth].mama
	for i = 1, mai do
		to[i] = bit.band(bit.bnot(n[i]),uimax)
	end
	to[mai] = bit.band(to[mai], mama)
	print(mama)
	return to
end

for _,name in pairs{"band","bor","bxor"} do
	local fn = bit[name]
	lib[name] = function(a,b,to)
		to = to or lib.new(0, a.bitwidth)
		a:assure_eqbits(b,to)
		local mai = bwm[to.bitwidth].mai
		for i = 1, mai do
			to[i] = fn(a[i],b[i])
		end
		return to
	end
end

function lib.lshift(n,s,to)
	to = to or lib.new(0, n.bitwidth)
	if n == to then
		n = n:movzx(temps[n.bitwidth].subn)
	end
	s = type(s) == "number" and s or s[1]
	n:assure_eqbits(to)
	local mai = bwm[to.bitwidth].mai
	local mama = bwm[to.bitwidth].mama
	local ish, shi = math.floor(s / uibiw), s % uibiw
	for i = 1, mai do
		to[i] = bit.bor(
			bit.rshift(n[i-ish-1]or 0,uibiw-shi),
			bit.band(shi~=0 and bit.lshift(n[i-ish]or 0,shi) or 0,uimax)
		)
	end
	to[mai] = bit.band(to[mai], mama)
	return to
end

function lib.rshift(n,s,to)
	to = to or lib.new(0, n.bitwidth)
	if n == to then
		n = n:movzx(temps[n.bitwidth].subn)
	end
	s = type(s) == "number" and s or s[1]
	n:assure_eqbits(to)
	local mai = bwm[to.bitwidth].mai
	local mama = bwm[to.bitwidth].mama
	local ish, shi = math.floor(s / uibiw), s % uibiw
	for i = 1, mai do
		to[i] = bit.bor(
			bit.rshift(n[i+ish]or uimax,shi),
			bit.band(shi~=0 and bit.lshift(n[i+ish+1]or uimax,uibiw-shi) or 0,uimax)
		)
	end
	to[mai] = bit.band(to[mai], mama)
	return to
end

function lib.arshift(n,s,to)
	to = to or lib.new(0, n.bitwidth)
	if n == to then
		n = n:movzx(temps[n.bitwidth].subn)
	end
	s = type(s) == "number" and s or s[1]
	n:assure_eqbits(to)
	local mai = bwm[to.bitwidth].mai
	local mama = bwm[to.bitwidth].mama
	local ish, shi = math.floor(s / uibiw), s % uibiw
	n[mai] = bit.bor(to[mai],bit.band(n:sign(),bit.bxor(mama, uimax)))
	for i = 1, mai do
		to[i] = bit.bor(
			bit.rshift(n[i+ish]or uimax,shi),
			bit.band(shi~=0 and bit.lshift(n[i+ish+1]or uimax,uibiw-shi) or 0,uimax)
		)
	end
	to[mai] = bit.band(to[mai], mama)
	n[mai] = bit.band(n[mai], mama)
	return to
end

function lib.movzx(a,to)
	to = to or lib.new(0, a.bitwidth)
	local mai = bwm[to.bitwidth].mai
	for i = 1, mai do
		to[i] = a[i] or 0
	end
	return to
end

function lib.movsx(a,to)
	local sign = a:sign()
	local tmai = bwm[to.bitwidth].mai
	local tmama = bwm[to.bitwidth].mama
	for i = 1, tmai do
		to[i] = a[i] or sign
	end
	local mai = bwm[a.bitwidth].mai
	local mama = bwm[a.bitwidth].mama
	to[mai] = bit.bxor(to[mai],bit.band(sign, bit.bnot(mama)))
	to[tmai] = bit.band(to[tmai], tmama)
end

function lib.binf(v)
	local s = {};
	for n=#v,1,-1 do
		local ss = {}
		for bi = uibiw-1,0,-1 do
			ss[#ss+1] = bit.band(bit.rshift(v[n],bi),1)
			if n==#v and bi > bwm[v.bitwidth].smsh then
				ss[#ss] = ({[0]='.','!'})[ss[#ss]]
			end
		end
		s[#s+1] = table.concat(ss)
	end
	return table.concat(s,'')
end

local t={}
t.a = lib.new(4,30)
t.b = lib.new(-2,30)
t.c = lib.new(8,30)
local function pp()
	print("{")
	for k,v in pairs(t) do
		print('',k.." = "..v:binf(),(unpack or table.unpack)(v))
	end
	print("}")
end
pp()
print("sign",t.b:sign())
print('-b -> b',t.b:negate(t.b))
print("sign",t.b:sign())
pp()
print('a+b -> a',t.a:add(t.b,t.a))
pp()
print('a+c -> a',t.a:add(t.c,t.a))
pp()
t.c = lib.new(0,64)
t.a:negate(t.a)
print('-a movsx -> (64b)c',t.a:movsx(t.c))
pp()
print('a << 9 -> a')
t.a:lshift(9,t.a)
pp()
print('a >> 10 -> a')
t.a:arshift(10,t.a)
pp()

return lib
