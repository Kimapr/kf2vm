local vm = require "vm"

local obj = vm.new({
	code = table.concat {
		vm.asms["mov imm 1 to stack sp"],"\127",
		vm.asms["mov imm 1 to stack sp"],"\8",
		vm.asms["mov imm 1 to stack sp"],"\4",
		vm.asms["add stack sp to stack sp"],
		vm.asms["add imm 1 to stack sp"],"\252",
		vm.asms["sub stack sp to reg ip"],
	}
})

for k,v in ipairs(vm.isadoc) do
	if k <256 then
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
	i=i+obj:update(dt)
	socket.sleep(0.001)
	local clc=socket.gettime()
	dt = clc - ptime
	ptime = clc
	if clc-cl > 1 then
		local clc=socket.gettime()
		local pipc = obj.ip[1]
		print("ip="..pipc,(i)/(clc-cl) .. " IPS")
		cl=clc pip=pipc
		i=0
	end
end
