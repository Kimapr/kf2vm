local num = require "num"

local function adder(a,b,s)
	local o = a+b+s
	local c=0
	if o>=2 then
		o=o-2
		c=1
	end
	return o,c
end

local function binf(n)
	local b = n:binf()
	b = assert(b:match("^%.*([0-9]*)$"),"bad number: "..b)
	return b:reverse()
end

local function add(a,b)
	local carry = 0
	local as,bs =
		binf(a),
		binf(b)
	local s = ""
	for n=1,#as do
		local ad,bd,o = as:sub(n,n),bs:sub(n,n)
		ad, bd = tonumber(ad), tonumber(bd)
		local ocar=carry
		o, carry = adder(ad, bd, carry)
		s = ("%s%i"):format(s,o)
	end
	local o = num.new(0,assert(a.bitwidth))
	o = binf(a:add(b,o))
	print(o.." =?\n"..s.."\n")
	assert(o == s, ("addition \n  %s\n+ %s fail\nGROUND TRUTH:\t%s\n!= RESPONSE:\t%s"):format(as,bs,s,o))
end

local function rand(bw)
	local nn = num.new(0,bw)
	local o = num.new(0,bw)
	for n=0,bw-1 do
		nn:from_lnum(math.random(0,1))
		nn:lshift(n,nn)
		o:bor(nn,o)
	end
	print("rnum: "..binf(o))
	return o
end

for bw = 8,65 do
	for n=1,16 do
		add(
			rand(bw),
			rand(bw)
		)
	end
end
