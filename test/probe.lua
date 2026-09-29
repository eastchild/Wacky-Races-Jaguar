-- MAME autoboot script: snapshots + memory dumps at given frames
-- env: PROBE_FRAMES="300,600" PROBE_OUT=dir  PROBE_INPUT="frame:field:frames,..."
local out = os.getenv("PROBE_OUT") or "."
local frames = {}
for f in string.gmatch(os.getenv("PROBE_FRAMES") or "600", "%d+") do frames[tonumber(f)] = true end
local last = 0
for f, _ in pairs(frames) do if f > last then last = f end end
local inputs = {}
for fr, field, len in string.gmatch(os.getenv("PROBE_INPUT") or "", "(%d+):([^:,]+):(%d+)") do
  table.insert(inputs, {f = tonumber(fr), name = field, len = tonumber(len)})
end
local n = 0
-- optional write watch: PROBE_WATCH=hexaddr
local watch = os.getenv("PROBE_WATCH")
local taps = {}
local function install_watch()
  local wa = tonumber(watch, 16)
  local wlog = io.open(out .. "/watch.txt", "w")
  for _, tag in ipairs({":maincpu", ":gpu", ":dsp"}) do
    local dev = manager.machine.devices[tag]
    local sp = dev.spaces["program"]
    local cnt = 0
    taps[#taps + 1] = sp:install_write_tap(wa, wa + 3, "w" .. tag, function(offset, data, mask)
      cnt = cnt + 1
      if cnt < 400 then
        wlog:write(string.format("%d %s pc=%08x off=%08x data=%08x mask=%08x\n", n, tag, dev.state["PC"].value, offset, data, mask))
        wlog:flush()
      end
    end)
  end
end
local cpu = manager.machine.devices[":maincpu"]
local mem = cpu.spaces["program"]

local function dump(name, addr, len)
  local fh = io.open(out .. "/" .. name, "wb")
  for i = 0, len - 1 do fh:write(string.char(mem:read_u8(addr + i))) end
  fh:close()
end

local function find_field(name)
  for _, port in pairs(manager.machine.ioport.ports) do
    for fname, field in pairs(port.fields) do
      if fname == name then return field end
    end
  end
  return nil
end

local watch_at = tonumber(os.getenv("PROBE_WATCH_AT") or "0")
local trace_at = tonumber(os.getenv("PROBE_TRACE_AT") or "0")
local trace_len = tonumber(os.getenv("PROBE_TRACE_LEN") or "1")
local trace_cpu = os.getenv("PROBE_TRACE_CPU") or "maincpu"
local nologo_done = false
local gbtime = os.getenv("PROBE_GBTIME") == "1"
local lastg = -1
emu.register_frame_done(function()
  n = n + 1
  local prevn = n - 1
  if gbtime then
    local g = mem:read_u32(0x1024)
    if g == lastg then return end
    prevn = lastg
    if prevn < 0 then prevn = g - 1 end
    lastg = g
    n = g
  end
  local function hit(x) return prevn < x and x <= n end
  if trace_at > 0 and manager.machine.debugger then
    if n == trace_at then
      manager.machine.debugger:command("trace " .. out .. "/trace.log," .. trace_cpu .. (os.getenv("PROBE_TRACE_ACT") or ""))
    elseif n == trace_at + trace_len then
      manager.machine.debugger:command("trace off," .. trace_cpu)
    end
  end
  if watch and watch ~= "" and n == watch_at then install_watch() end
  for _, i in ipairs(inputs) do
    if hit(i.f) or hit(i.f + i.len) then
      local fld = find_field(i.name)
      if fld then fld:set_value(hit(i.f) and 1 or 0) end
    end
  end
  local fn = nil
  for f, _ in pairs(frames) do if hit(f) then fn = f end end
  if fn then
    local n = fn
    manager.machine.video:snapshot()
    dump(string.format("vars_%d.bin", n), 0x1000, 0x200)
    dump(string.format("code_%d.bin", n), 0x4700, 0x100)
    dump(string.format("hud_%d.bin", n), 0xF8000, 1536)
    dump(string.format("opl_%d.bin", n), 0x3000, 64)
    dump(string.format("flat_%d.bin", n), 0x100000, 0x10000)
    local fh = io.open(out .. string.format("/regs_%d.txt", n), "w")
    fh:write(string.format("pc=%08x\n", cpu.state["PC"].value))
    for _, r in ipairs({"D0","D1","D2","D3","D4","D5","D6","D7","A0","A1","A2","A3","A4","A5","A6","SP","SR"}) do
      fh:write(string.format("%s=%08x\n", r, cpu.state[r].value))
    end
    for _, a in ipairs({0xF03FE0, 0xF03FE4, 0xF03FE8, 0xF03FEC, 0xF03FF0, 0xF02114, 0xF02110}) do
      fh:write(string.format("%06x=%08x\n", a, mem:read_u32(a)))
    end
    local dsp = manager.machine.devices[":dsp"]
    if dsp then for name, st in pairs(dsp.state) do fh:write(string.format("dsp.%s=%08x\n", name, st.value)) end end
    local gpu = manager.machine.devices[":gpu"]
    if gpu then
      for name, st in pairs(gpu.state) do
        fh:write(string.format("gpu.%s=%08x\n", name, st.value))
      end
    end
    fh:close()
    dump(string.format("gpuram_%d.bin", n), 0xF03000, 0x1000)
    dump(string.format("dspram_%d.bin", n), 0xF1B000, 0x2000)
    dump(string.format("fb0_%d.bin", n), mem:read_u32(0xF03FE8) ~= 0 and mem:read_u32(0xF03FE8) or 0x120000, 160*144*2)
    dump(string.format("vram_%d.bin", n), 0x110000, 0x4000)
    dump(string.format("gvram_%d.bin", n), 0x11C000, 0x4000)
    if os.getenv("PROBE_PROF") then dump(string.format("prof_%d.bin", n), 0x180000, 0x20000) end
  end
  if n >= last then manager.machine:exit() end
end)











