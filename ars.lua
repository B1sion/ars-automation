-- Unified Ars Nouveau AE2 controller for CC:Tweaked
-- One machine, one ingredient buffer and one pattern provider per network.
-- Enchanting: FIRST OCCUPIED BUFFER SLOT is the central reagent.
-- Requires inventory peripheral integration for the connected Ars blocks.

local CFG = { poll = 0.5, timeout = 120, settle = 1.0 }

local function findAll(part)
  local found = {}
  for _, name in ipairs(peripheral.getNames()) do
    if name:find(part, 1, true) then found[#found+1] = name end
  end
  table.sort(found)
  return found
end

local function exactlyOne(part, label)
  local names = findAll(part)
  assert(#names == 1, label .. ': expected exactly one, found ' .. #names)
  local p = assert(peripheral.wrap(names[1]), 'Cannot wrap ' .. names[1])
  assert(type(p.list) == 'function' and type(p.pushItems) == 'function', label .. ' lacks inventory methods')
  return names[1], p
end

local imbuements = findAll('ars_nouveau:imbuement_chamber')
local enchanting = findAll('ars_nouveau:enchanting_apparatus')
assert(#imbuements + #enchanting == 1, 'Connect exactly one Ars machine per computer network')
local mode = #imbuements == 1 and 'imbuement' or 'enchanting'
local machineName = mode == 'imbuement' and imbuements[1] or enchanting[1]
local machine = assert(peripheral.wrap(machineName))
assert(type(machine.list) == 'function' and type(machine.pushItems) == 'function', 'Machine does not expose inventory methods')
local bufferName, buffer = exactlyOne('extendedae:ingredient_buffer', 'Ingredient Buffer')
local ppName, provider = exactlyOne('pattern_provider', 'Pattern Provider')
local pedNames = findAll('ars_nouveau:arcane_pedestal')
assert(#pedNames > 0, 'No Arcane Pedestals found')
local peds = {}
for i, name in ipairs(pedNames) do
  peds[i] = assert(peripheral.wrap(name))
  assert(type(peds[i].list) == 'function' and type(peds[i].pushItems) == 'function', 'Pedestal lacks inventory methods: ' .. name)
end

local function snapshot(p) return p.list() or {} end
local function empty(p) return next(snapshot(p)) == nil end
local function sortedSlots(inv)
  local slots = {}
  for slot in pairs(inv) do slots[#slots+1] = slot end
  table.sort(slots)
  return slots
end
local function transfer(src, target, slot, qty)
  local moved = src.pushItems(target, slot, qty)
  assert(moved == qty, 'Transfer failed (' .. tostring(moved) .. '/' .. tostring(qty) .. ') to ' .. target)
end
local function unload(p)
  for _, slot in ipairs(sortedSlots(snapshot(p))) do
    local item = snapshot(p)[slot]
    if item then transfer(p, ppName, slot, item.count) end
  end
end
local function pedEmpty()
  for _, p in ipairs(peds) do if not empty(p) then return false end end
  return true
end
local function clear()
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
