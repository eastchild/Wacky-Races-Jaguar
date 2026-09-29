local fh = io.open(os.getenv("PROBE_OUT") .. "/ports.txt", "w")
local p = manager.machine.ioport.ports[":CONFIG"]
for fname, f in pairs(p.fields) do fh:write(string.format("%s mask=%x def=%x type=%s\n", fname, f.mask, f.defvalue, tostring(f.type))) end
fh:close()
manager.machine:exit()
