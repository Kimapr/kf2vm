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
		return (bit and bit.lshift and bit.rshift and bit.bor
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
	BITWIDTH = bit and JUDGE_INTEGER_BITWIDTH(bit)
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

lib.bit = bit

local     lshift,     rshift,     band,     bnot,     bxor,     bor
=     bit.lshift, bit.rshift, bit.band, bit.bnot, bit.bxor, bit.bor

lib.__index = lib

lib.BITWIDTH = BITWIDTH
local SIGNED = bnot(0) == -1
lib.SIGNED = SIGNED

local uibiw = BITWIDTH
local uimax = bor(lshift(1,uibiw) - 1, 0)
if uimax == 0 then
	uimax = bnot(0)
end

local hibiw = rshift(uibiw, 1)
local himlo = lshift(1, hibiw) - 1
local himhi = lshift(himlo, hibiw)

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

local function counted(f)
	local cc=0
	return function(...)
		cc=cc+1
		return f(cc,...)
	end
end

--[[
local debugging = true
--[=[]]
local debugging = false
--]=]
local function debugged(n,f)
	if not debugging then return f end
	return function(...)
		print(n,...)
		return f(...)
	end
end

local bwm = setmetatable({},{__index = function(self,bitwidth)
	local mai = math.ceil(bitwidth / uibiw)
	local smsh = bitwidth - (mai-1)*uibiw - 1
	local mama = (smsh+1) < uibiw and bor(lshift(1, smsh + 1)-1,0) or uimax
	local meta = setmetatable({}, lib)
	meta.__index = meta
	local split = function(n)
		return ("band(N, HIMLO), rshift(band(N, HIMHI), HIBIW)")
			:gsub("N",n)
			:gsub("HIMLO",himlo)
			:gsub("HIMHI",himhi)
			:gsub("HIBIW",hibiw)
	end
	local function fixmama(a,b)
		a=a or "" b=b or ""
		return mama ~= uimax
			and a.."\nto["..mai.."] = band(to["..mai.."], "..mama..")\n"..b.."\n"
			or  ""
	end
	local function fixsize(a,b,...)
		if not a then return "" end
		return ("assert("..a..".bitwidth == "..bitwidth..",'bitwidth mismatch')")..fixsize(b,...)
	end
	local function fixui(a)
		return uibiw ~= BITWIDTH
			and "band("..a..","..uimax..")"
			or a
	end
	local function add()
		return [[
			local carry = carry or 0
			local an,ab
			local alo,ahi,blo,bhi
			local olo,ohi
			]]..("."):rep(mai):gsub('.',counted(function(i)
				return [[
					an,ab = a[]]..i..[[],b[]]..i..[[]
					alo,ahi = ]]..split('an')..[[ 
					blo,bhi = ]]..split('ab')..[[ 
					olo = alo + blo + carry
					olo, carry = ]]..split('olo')..[[ 
					ohi = ahi + bhi + carry
					ohi, carry = ]]..split('ohi')..[[ 
					to[]]..i..[[] = olo + lshift(ohi, ]]..hibiw..[[)
				]]
			end))..(mama ~= uimax
				and "carry = rshift(to["..mai.."],"..(smsh+1)..")\n"
				or "")..[[
			]]..fixmama()..[[
		]]
	end
	local function bnot()
		return ("."):rep(mai):gsub('.',counted(function(i)
			return [[
				to[]]..i..[[] = ]]..fixui([[bnot(a[]]..i..[[])]])..[[ 
			]]
		end))..fixmama()..[[ 
		]]
	end
	local function binop(name)
		return ("."):rep(mai):gsub('.',counted(function(i)
			return [[
				to[]]..i..[[] = ]]..fixui(name..[[(a[]]..i..[[],b[]]..i..[[])]])..[[ 
			]]
		end))..fixmama()..[[ 
		]]
	end
	self[bitwidth] = {
		mama = mama,
		mai = mai,
		smsh = smsh,
		meta = meta,
	}
	local function tshift(f,a,b)
		return [[
			to = to or lib.new(0, ]]..bitwidth..[[)
			if n == to then n=n:movzx(shtmp) end
			s = type(s) == "number" and s or s[1]
			]]..fixsize('n','to')..[[ 
			local ish,shi = floor(s / ]]..uibiw..[[), s % ]]..uibiw..[[ 
			]]..(a or "")..[[ 
			]]..("."):rep(mai):gsub('.',counted(f))..[[ 
			]]..fixmama()..[[ 
			]]..(b or "")..[[ 
			return to
		]]
	end
	assert((debugged("(load)",load or loadstring))([[
		local meta, bit, lib = ...
		local     lshift,     rshift,     band,     bnot,     bxor,     bor
		=     bit.lshift, bit.rshift, bit.band, bit.bnot, bit.bxor, bit.bor
		meta.add = function(a, b, to, carry)
			to = to or lib.new(0, ]]..bitwidth..[[)
			]]..fixsize('a','b','to')..[[ 
			]]..add()..[[ 
			return to, carry
		end
		local subn = lib.new(0,]]..bitwidth..[[)
		local one = lib.new(1,]]..bitwidth..[[)
		meta.bnot = function(a, to)
			to = to or lib.new(0, ]]..bitwidth..[[)
			]]..fixsize('a','to')..[[ 
			]]..bnot()..[[ 
			return to
		end
		]]..("band;bor;bxor;"):gsub("(.-);",function(n)
			return [[
				meta.]]..n..[[ = function(a, b, to)
					to = to or lib.new(0, ]]..bitwidth..[[)
					]]..fixsize('a','to')..[[ 
					]]..binop(n)..[[ 
					return to
				end
			]]
		end)..[[
		meta.negate = function(a, to)
			local b = one
			]]..bnot()..[[ 
			a = to
			local carry = 0
			]]..add()..[[ 
			return to
		end
		meta.sub = function(a, b, to)
			to = to or lib.new(0, ]]..bitwidth..[[)
			]]..fixsize('a','b','to')..[[ 
			do
				local a,b,to = b,one,subn
				]]..bnot()..[[ 
				a = to
			end
			b = subn
			local carry = 1
			]]..add()..[[ 
			return to, carry
		end
		local shtmp = lib.new(0, ]]..bitwidth..[[)
		local floor = math.floor
		meta.lshift = function(n,s,to)
			]]..tshift(function(i)
				return [[
					to[]]..i..[[] = bor(
						shi~=0 and rshift(n[]]..(i-1)..[[-ish]or 0,]]..uibiw..[[-shi) or 0,
						]]..fixui([[lshift(n[]]..(i)..[[-ish]or 0,shi)]])..[[ 
					)
				]]
			end)..[[ 
		end
		meta.rshift = function(n,s,to)
			]]..tshift(function(i)
				return [[
					to[]]..i..[[] = bor(
						rshift(n[]]..i..[[+ish]or 0,shi),
						]]..fixui([[shi~=0 and lshift(n[]]..(i+1)..[[+ish]or 0,]]..uibiw..[[-shi) or 0]])..[[ 
					)
				]]
			end)..[[ 
		end
		meta.arshift = function(n,s,to)
			]]..tshift(function(i)
				return [[
					to[]]..i..[[] = bor(
						rshift(n[]]..i..[[+ish]or sign,shi),
						]]..fixui([[shi~=0 and lshift(n[]]..(i+1)..[[+ish]or sign,]]..uibiw..[[-shi) or 0]])..[[ 
					)
				]]
			end,[[
				local sign = n[]]..mai..[[]
				sign = band(rshift(sign,]]..smsh..[[),1)
				sign = ]]..fixui([[bnot(sign - 1)]])..[[ 
				]]..(mama ~= uimax and "n["..mai.."] = bor(n["..mai.."],band(sign,bxor("..mama..","..uimax..")))" or "")..[[ 
			]],[[
				]]..fixmama("n,to = to,n","n,to = to,n")..[[ 
			]])..[[ 
		end
	]]))(meta,bit,lib)
	return self[bitwidth]
end})

function lib.new(n,bitwidth)
	local w = bitwidth -- bitwidth is an epic word but i prefer short names
	local obj = setmetatable({}, bwm[bitwidth].meta)
	obj.bitwidth = bitwidth
	return obj:from_lnum(n)
end

function lib.set_bitwidth(obj,bitwidth)
	obj.bitwidth = bitwidth
	setmetatable(obj,bwm[bitwidth].meta)
	for n=1,bwm[bitwidth].mai do
		obj[n] = obj[n] or 0
	end
	return obj
end

function lib.from_lnum(obj,n)
	local bitwidth = obj.bitwidth
	local flip = false
	if n<0 then n,flip = -n, not flip end
	n = math.floor(n)
	for i = 1, bwm[bitwidth].mai do
		obj[i] = band(n,uimax)
		n = math.floor(n / (2^uibiw))
	end
	obj[bwm[bitwidth].mai] = band(obj[bwm[bitwidth].mai], bwm[bitwidth].mama)
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
	return band(n, himlo), rshift(band(n, himhi), hibiw)
end

function lib.sign(a)
	local mai = bwm[a.bitwidth].mai
	local smsh = bwm[a.bitwidth].smsh
	local sign = a[mai]
	sign = band(rshift(sign,smsh),1)
	sign = band(bnot(sign - 1),uimax)
	return sign
end

function lib.add(a,b,to,carry)
	to = to or lib.new(0, a.bitwidth)
	a:assure_eqbits(b,to)
	local mai = bwm[to.bitwidth].mai
	local mama = bwm[to.bitwidth].mama
	local carry = carry or 0
	for i = 1, mai do
		local alo, ahi = split(a[i])
		local blo, bhi = split(b[i])
		local olo, ohi
		olo, carry = split(alo + blo + carry)
		ohi, carry = split(ahi + bhi + carry)
		to[i] = olo + lshift(ohi, hibiw)
	end
	if mama ~= uimax then
		carry = lshift(to[mai], bwm[to.bitwidth].smsh + 1)
	end
	to[mai] = band(to[mai], mama)
	return to,carry
end

function lib.sub(a,b,to,carry)
	local b = b:negate(temps[b.bitwidth].subn)
	return a:add(b,to,carry)
end

function lib.bnot(n,to)
	to = to or lib.new(0, n.bitwidth)
	n:assure_eqbits(to)
	local mai = bwm[to.bitwidth].mai
	local mama = bwm[to.bitwidth].mama
	for i = 1, mai do
		to[i] = band(bnot(n[i]),uimax)
	end
	to[mai] = band(to[mai], mama)
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

function lib.mul(a,b,to)
	to = to or lib.new(0, a.bitwidth)
	if a == to then
		a = a:movzx(temps[a.bitwidth].mula)
	end
	if b == to then
		b = b:movzx(temps[b.bitwidth].mulb)
	end
	a:assure_eqbits(b,to)
	local tmp = temps[a.bitwidth].mul
	local mai = bwm[a.bitwidth].mai
	local mama = bwm[a.bitwidth].mama
	local ima = math.ceil(a.bitwidth/uibiw)*uibiw-hibiw
	to:bxor(to,to)
	for i=0,ima,hibiw do
		for j=0,ima-i,hibiw do
			a:rshift(i,tmp)
			local aa = band(tmp[1],himlo)
			b:rshift(j,tmp)
			local bb = band(tmp[1],himlo)
			tmp[1] = bor(aa * bb,0)
			tmp:lshift(i+j,tmp)
			to:add(tmp,to)
		end
	end
	return to
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
		to[i] = bor(
			shi~=0 and rshift(n[i-ish-1]or 0,uibiw-shi) or 0,
			band(lshift(n[i-ish]or 0,shi),uimax)
		)
	end
	to[mai] = band(to[mai], mama)
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
		to[i] = bor(
			rshift(n[i+ish]or 0,shi),
			band(shi~=0 and lshift(n[i+ish+1]or 0,uibiw-shi) or 0,uimax)
		)
	end
	to[mai] = band(to[mai], mama)
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
	local sign = n:sign()
	n[mai] = bor(n[mai],band(sign,bxor(mama, uimax)))
	for i = 1, mai do
		to[i] = bor(
			rshift(n[i+ish]or sign,shi),
			band(shi~=0 and lshift(n[i+ish+1]or sign,uibiw-shi) or 0,uimax)
		)
	end
	to[mai] = band(to[mai], mama)
	n[mai] = band(n[mai], mama)
	return to
end

function lib.movzx(a,to)
	to = to or lib.new(0, a.bitwidth)
	local mai = bwm[to.bitwidth].mai
	local mama = bwm[to.bitwidth].mama
	for i = 1, mai do
		to[i] = a[i] or 0
	end
	to[mai] = band(to[mai], mama)
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
	to[mai] = bxor(to[mai],band(sign, bnot(mama)))
	to[tmai] = band(to[tmai], tmama)
end

function lib.binf(v)
	local s = {};
	for n=#v,1,-1 do
		local ss = {}
		for bi = uibiw-1,0,-1 do
			ss[#ss+1] = band(rshift(v[n],bi),1)
			if n==#v and bi > bwm[v.bitwidth].smsh then
				ss[#ss] = ({[0]='.','!'})[ss[#ss]]
			end
		end
		s[#s+1] = table.concat(ss)
	end
	return table.concat(s,'')
end

return lib
