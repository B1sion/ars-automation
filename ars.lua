assert(empty(machine) and pedEmpty(), 'Machine/pedestals not empty: clear manually before starting')
end
local function load()
  clear()
  local items = snapshot(buffer)
  local slots = sortedSlots(items)
  if #slots == 0 then return nil end
  local center = slots[1]
  local pi = 1
  for i = 2, #slots do
    local slot = slots[i]
    local qty = items[slot].count
    -- Imbuement follows original author: each occupied slot goes to one pedestal.
    -- Enchanting splits stacks one item per pedestal.
    if mode == 'imbuement' then
      assert(pi <= #peds, 'Not enough pedestals')
      transfer(buffer, pedNames[pi], slot, qty)
      pi = pi + 1
    else
      for j = 1, qty do
        assert(pi <= #peds, 'Not enough pedestals')
        transfer(buffer, pedNames[pi], slot, 1)
        pi = pi + 1
      end
    end
  end
  sleep(CFG.settle)
  transfer(buffer, machineName, center, items[center].count)
  return textutils.serialise(snapshot(machine))
end

print('Unified Ars Controller | ' .. mode)
print('Machine: ' .. machineName)
print('Buffer: ' .. bufferName)
print('Provider: ' .. ppName)
print('Pedestals: ' .. #peds)
print('Setup OK')

while true do
  if not empty(buffer) then
    local ok, err = pcall(function()
      local initial = load()
      if not initial then return end
      print('Crafting...')
      local deadline = os.epoch('utc') + CFG.timeout * 1000
      local changed = false
      while os.epoch('utc') < deadline do
        local now = textutils.serialise(snapshot(machine))
        if now ~= initial and not empty(machine) then
          changed = true
          break
        end
        sleep(CFG.poll)
      end
      assert(changed, 'Timed out waiting for machine inventory to change')
      sleep(CFG.settle)
      unload(machine)
      for _, p in ipairs(peds) do unload(p) end
      assert(empty(machine) and pedEmpty(), 'Output or reusable ingredients remain')
      print('Complete')
    end)
    if not ok then
      printError(err)
      error('Controller stopped; inspect inventories before restarting', 0)
    end
  end
  sleep(CFG.poll)
end
