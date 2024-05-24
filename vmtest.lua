local vm = require "vm"

local code=table.concat {
	vm.asms["mov imm 1 to stack sp"],"\127",
	vm.asms["mov imm 1 to stack sp"],"\8",
	vm.asms["mov imm 1 to stack sp"],"\4",
	vm.asms["add stack sp to stack sp"],
	vm.asms["add imm 1 to stack sp"],"\252",
	vm.asms["sub stack sp to reg ip"],
	"\255"
}
print((code:gsub('.',function(c)return ("%.2x"):format(string.byte(c))end)))

local obj = vm.new({
	code = code,
	--clockrate = 10
	clockrate=64*1024
})

obj.debugging = true

for k=0,255 do
	local v = vm.isadoc[k]
	if v then
		print(k,v)
	end
end

local socket = require "socket"

local i=0
local cl=socket.gettime()
local pip=obj.ip[1]
local pi=0
local dt=0

local ptime = socket.gettime()
while true do
	dt = math.min(1/10,dt)
	i=i+obj:update(dt)
	socket.sleep(0.001)
	local clc=socket.gettime()
	dt = clc - ptime
	ptime = clc
	if clc-cl > 1/10 then
		local clc=socket.gettime()
		local pipc = obj.ip[1]
		assert(({[0]=1,[true]=1})[os.execute("clear")])
		print("FPS ".. 1/dt)
		print("ip="..pipc,(i)/(clc-cl) .. " IPS\t(" .. (math.floor((i/(clc-cl)/obj.clockrate*100))/1) .. "%)")
		print(obj.debug_str)
		cl=clc pip=pipc
		i=0
	end
end
