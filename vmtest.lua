local vm = require "vm"

--[[local code=table.concat {
	vm.asms["mov imm 1 to stack sp"],"\127",
	vm.asms["mov imm 1 to stack sp"],"\8",
	vm.asms["mov imm 1 to stack sp"],"\4",
	vm.asms["add stack sp to stack sp"],
	vm.asms["add imm 1 to stack sp"],"\252",
	vm.asms["sub stack sp to reg ip"],
	"\255"
}]]
local asms = setmetatable({},{__index=function(s,k)return assert(vm.asms[k],k)end})
local dup = asms["fetch word imm 1 sp-rel to stack sp"].."\0"
local function call(pos)
	return
		asms["mov reg ip to stack bp"]..
		asms["add imm 1 to stack bp"].."\4"..
		asms["add imm 1 to reg ip"]..string.char(pos%256)
end
local ret = asms["mov stack bp to reg ip"]..""

local code = table.concat {
	asms["mov reg sp to stack sp"],
	asms["mov stack sp to reg bp"],
	"\0",
	asms["add imm 2 to reg bp"],"\0","\192",
	asms["mov imm 1 to stack sp"],"\12",
	"\0",
	call(6),
	asms["add imm 1 to reg sp"],"\4",
	asms["add imm 1 to reg ip"],string.char((-2-2-#call(0)-1-2)%256),
	"\0","\255", -- invalid instruction

	-- fact
	dup,
	asms["mov imm 1 to stack sp"],"\0",
	asms["if!="],asms["add imm 1 to reg ip"],string.char(#dup+1+2+#ret),
	dup,
	asms["bxor stack sp to stack sp"],
	asms["add imm 1 to stack sp"],"\1",
	ret,
	dup,
	asms["add imm 1 to stack sp"],"\255",
	call(-5 -2 -#dup -#ret -2 -1 -#dup -3 -2 -#dup),
	asms["mul stack sp"],
	ret
}

print((code:gsub('.',function(c)return ("%.2x"):format(string.byte(c))end)))

local fast = os.getenv("FAST")

local obj = vm.new({
	code = code,
	clockrate=fast and 64*1024 or 20
})

obj.debugging = not fast

for k=0,255 do
	local v = vm.isadoc[k]
	if v then
		print(k,v)
	end
end

local socket = require "socket"

local i=0
local pip=obj.ip[1]
local pi=0
local dt=0

socket.sleep(0.5)
local cl=socket.gettime()
local ptime = socket.gettime()
local ir,tr=0,0
while true do
	local ok,err=xpcall(function()
	local btr = socket.gettime()
	local _,iir=obj:update(dt)
	iir=-iir
	i=i+iir
	ir=ir+iir
	tr = tr + (socket.gettime()-btr)
	end,debug.traceback)
	if not ok then
		err = err.."\n"..(obj.debug_str or "?").."\n"
		error(err)
	end
	socket.sleep(0.001)
	local clc=socket.gettime()
	dt = clc - ptime
	ptime = clc
	if not fast or (clc-cl > 1) then
		local pipc = obj.ip[1]
		if not fast then
			assert(({[0]=1,[true]=1})[os.execute("clear")])
			print("FPS ".. 1/dt)
		end
		print("ip="..pipc,(i)/(clc-cl) .. " Hz (" .. (math.floor((i/(clc-cl)/obj.clockrate*100))/1) .. "%),\t"..(ir/tr).." Hz real")
		if not fast then
			print(obj.debug_str)
		end
		cl=clc pip=pipc
		i=0
	end
end
