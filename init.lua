local lib = {}
local bignum = require "Math.BigNum"

local num = {__index={}}
lib.num = num

local function memoize(f,n)
	n = n or 1
	local cache = {}
	return function(...)
		local v = select(n,...)
		if cache[v] then
			return (unpack or table.unpack)(cache[v])
		end
		cache[v] = {f(...)}
		return (unpack or table.unpack)(cache[v])
	end
end

local newn = (function(grad)
	return function(n,w)
		return bignum.new(n,grad(w))
	end
end)(memoize(function(w)
	return math.ceil((w*2) / 24)
end))

local mnum = memoize(function(w)
	return memoize(function(n)
		return newn(n,w)
	end)
end)
local signoffs = (function(sig,unsig)
	return function(w,signes)
		if signes then
			return sig(w)
		else
			return unsig(w)
		end
	end
end)(memoize(function(w)
	return
		newn(2,w)^newn(w-1,w),
		newn(2,w)^newn(w,w)
end),memoize(function(w)
	return
		newn(0,w),
		newn(2,w)^newn(w,w)
end))

local ncc=0
function num.new(v,w,s)
	ncc=ncc+1
	local n
	local off, div = signoffs(w,s)
	v = getmetatable(v) == num and v.n or v
	v = newn(v,w)
	while v < mnum(w)(0) do
		local mul = (-v/div+(-v%div>mnum(w)(0) and mnum(w)(1) or mnum(w)(0)))
		v = div*mul + v
	end
	v = v % div
	if s and v >= off then
		v = -(div - v)
	end
	return setmetatable({
		n = v,
		w = w,
		s = s
	},num)
end

function num.__tostring(n)
	return tostring(n.n)
end

local cc=0
function num.__add(a,b)
	cc=cc+1
	return num.new(a.n + b.n, a.w, a.s)
end

function num.__mul(a,b)
	return num.new(a.n * b.n, a.w, a.s)
end

local function newint_t(w,s)
	return function(n)
		return num.new(n,w,s)
	end
end

local int32 = newint_t(32, true)
local uint32 = newint_t(32, false)
local int64 = newint_t(64, true)
local uint64 = newint_t(64, false)

local function test()
	local fname = "./bignumtest" --..math.random(1000000,9999999)
	local f = io.open(fname..".c","w")
	f:write("#include <stdio.h>\nint main(){int ret=0;\n")
	math.randomseed(os.time())
	local function randn(w,s)
		local n = num.new(0,w,false)
		local mul = num.new(256,w,false)
		for _=1,w/8 do
			n = n * mul + num.new(math.random(0,255),w,false)
		end
		return num.new(n,w,s)
	end
	local function system(cmd)
		print("$ "..cmd)
		local out = os.execute(cmd)
		if type(out)=="number" then
			return out==0
		end
		return out
	end
	local o=os.clock()
	cc=0;ncc=0
	local nn=2
	for __=1,2 do
		local s = __==2;
		local w = 32
		local tin,tout =
			"unsigned int",
			"int"
		if not s then
			tout = tin
		end
		for n=1,64 do
			nn=nn+1
			local a = randn(w,s)
			local b = randn(w,s)
			local c = a+b
			f:write('if((',tout,')((',tin,')(',tostring(a),') + (',tin,')(',tostring(b),')) != ',tostring(c),
			'){printf("err in #',nn,': %lli != %lli\\n",',
			'(long long)((',tout,')((',tin,')(',tostring(a),')+(',tin,')(',tostring(b),'))),(long long)(',tostring(c),'));ret=1;} // #',nn,'\n')
		end
	end
	print(os.clock()-o, cc.." additions",ncc.." numnews")
	f:write("return ret;}\n")
	f:close()
	assert(system("gcc -o "..fname.." "..fname..".c"))
	assert(system(fname))
	--system("rm "..fname.." "..fname..".c")
end

test()

return lib
