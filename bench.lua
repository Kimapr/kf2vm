local lib = {}

local num = require "num"
lib.num = num

for i=1,2 do
--for i=1,1 do
local a = num.new(0,16)
local b = num.new(1,16)
local steps = 2^16;
	print("== pass "..i.." ==")
	local tt = i==2 and 0.3 or 0.1
for _,p in ipairs{
	{noop = function()for n=1,steps do end end},
	{bnot = function()for n=1,steps do a:bnot(a) end end},
	{band = function()for n=1,steps do a:band(b,a) end end},
	{bor = function()for n=1,steps do a:bor(b,a) end end},
	{bxor = function()for n=1,steps do a:bxor(b,a) end end},
	{add = function()for n=1,steps do a:add(b,a) end end},
	{neg = function()for n=1,steps do a:negate(a) end end},
	{sub = function()for n=1,steps do a:sub(b,a) end end},
	{lshift = function()for n=1,steps do a:lshift(b,a) end end},
	{rshift = function()for n=1,steps do a:rshift(b,a) end end},
	{arshift = function()for n=1,steps do a:arshift(b,a) end end},
	{from_lnum = function()for n=1,steps do a:from_lnum(0) end end},
	{sign = function()for n=1,steps do a:sign() end end},

	{bnot0 = function()setmetatable(a,num);setmetatable(b,num);for n=1,steps do num.bnot(a,a) end end},
	{band0 = function()for n=1,steps do num.band(a,b,a) end end},
	{bor0 = function()for n=1,steps do num.bor(a,b,a) end end},
	{bxor0 = function()for n=1,steps do num.bxor(a,b,a) end end},
	{add0 = function()for n=1,steps do num.add(a,b,a) end end},
	{neg0 = function()for n=1,steps do num.negate(a,a) end end},
	{sub0 = function()for n=1,steps do num.sub(a,b,a) end end},
	{lshift0 = function()for n=1,steps do num.lshift(a,b,a) end end},
	{rshift0 = function()for n=1,steps do num.rshift(a,b,a) end end},
	{arshift0 = function()for n=1,steps do num.arshift(a,b,a) end end},
	{from_lnum0 = function()for n=1,steps do num.from_lnum(a,0) end end},
	{sign0 = function()for n=1,steps do num.sign(a) end end},
} do local k,f = next(p) local c=os.clock()local n=0 repeat f() n=n+1 until os.clock()-c>tt local _=(i==2 or i==1) and print(k,steps*n / (os.clock()-c) / 1000000 .. " MIPS") end
end

return lib
