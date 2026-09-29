local out = os.getenv("PROBE_OUT")
local fh = io.open(out .. "/joy.txt", "w")
local n = 0
local fld
for _, port in pairs(manager.machine.ioport.ports) do
  for fname, field in pairs(port.fields) do if fname == "P1 Pause" then fld = field end end
end
local mem = manager.machine.devices[":maincpu"].spaces["program"]
emu.register_frame_done(function()
  n = n + 1
  if n == 400 then fld:set_value(1) end
  if n >= 395 and n <= 410 then
    fh:write(string.format("%d raw=%08x port=%x\n", n, mem:read_u32(0x102c), fld.port:read()))
  end
  if n == 410 then fh:close(); manager.machine:exit() end
end)
