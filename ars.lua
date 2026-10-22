-- Unified Ars Nouveau controller for CC:Tweaked + Extended AE
-- Imbuement Chamber: one-at-a-time batch processing, reusable pedestals
-- Enchanting Apparatus: one recipe per batch, pedestal ingredients first
-- Assumption: FIRST OCCUPIED BUFFER SLOT = CENTER INGREDIENT.
-- AE2 pattern provider should use blocking mode.

local POLL = 0.4
local TIMEOUT_MS = 120000
local SETTLE_SECONDS = 1.0

local function findNames(fragment)
  local found = {}
  for _, name in ipairs(peripheral.getNames()) do
    if name:find(fragment, 1, true) then found[#found+1] = name end
  end
  table.sort(found)
  return found
end

local function exactlyOne(names, label)
  if #names ~= 1 then error("Expected exactly one " .. label .. ", found " .. #names) end
  return names[1], assert(peripheral.wrap(names[1]))
end

local providerName, provider = exactlyOne(findNames("pattern_provider"), "Pattern Provider")
local bufferName, buffer = exactlyOne(findNames("ingredient_buffer"), "Ingredient Buffer")
local imbuements = findNames("ars_nouveau:imbuement_chamber")
local enchantings = findNames("ars_nouveau:enchanting_apparatus")
if #imbuements + #enchantings ~= 1 then
  error("Connect exactly one Ars machine per computer (found " .. (#imbuements + #enchantings) .. ")")
end
local mode = #imbuements == 1 and "imbuement" or "enchanting"
local machineName = mode == "imbuement" and imbuements[1] or enchantings[1]
local machine = assert(peripheral.wrap(machineName))
local pedestalNames = findNames("ars_nouveau:arcane_pedestal")
local pedestals = {}
for _, name in ipairs(pedestalNames) do pedestals[#pedestals+1] = assert(peripheral.wrap(name)) end

local function inventoryOk(p, label)
  assert(type(p.list) == "function" and type(p.pushItems) == "function", label .. " does not support inventory transfer")
end
inventoryOk(buffer, "Buffer")
inventoryOk(machine, "Machine")
for i, p in ipairs(pedestals) do inventoryOk(p, "Pedestal " .. i) end

local function entries(inv)
  local result = {}
  for slot, item in pairs(inv.list() or {}) do
    result[#result+1] = {slot=slot, name=item.name, count=item.count}
  end
  table.sort(result, function(a,b) return a.slot < b.slot end)
  return result
end
local function empty(inv) return #entries(inv) == 0 end
local function now() return os.epoch("utc") end
local function fail(message) error(message, 0) end
local function transfer(src, destName, slot, amount)
  local moved = src.pushItems(destName, slot, amount)
  if moved ~= amount then fail("Transfer failed (" .. tostring(moved) .. "/" .. amount .. ") to " .. destName) end
end
local function sendAll(inv)
  for _, item in ipairs(entries(inv)) do
    transfer(inv, providerName, item.slot, item.count)
  end
end
local function snapshot(inv)
  local parts = {}
  for _, item in ipairs(entries(inv)) do
    parts[#parts+1] = item.slot .. ":" .. item.name .. ":" .. item.count
  end
  return table.concat(parts, "|")
end
local function waitForChange(before, label)
  local deadline = now() + TIMEOUT_MS
  while now() < deadline do
    if snapshot(machine) ~= before and not empty(machine) then
      sleep(SETTLE_SECONDS)
      if snapshot(machine) ~= before and not empty(machine) then return end
    end
    sleep(POLL)
  end
  fail("Timed out waiting for " .. label .. ". Items left in place for recovery")
end
local function pedestalCount()
  local total = 0
  for _, p in ipairs(pedestals) do
    for _, item in ipairs(entries(p)) do total = total + item.count end
  end
  return total
end
local function clearPedestals()
  for _, p in ipairs(pedestals) do sendAll(p) end
end
local function allPedestalsEmpty()
  for _, p in ipairs(pedestals) do if not empty(p) then return false end end
  return true
end
local function awaitBufferStable()
  local prev = snapshot(buffer)
  sleep(SETTLE_SECONDS)
  local curr = snapshot(buffer)
  if prev ~= curr then return false end
  return curr ~= ""
end

-- For Imbuement: original author's approach uses the first buffer slot as
-- center ingredient, with each other occupied slot mapped to one pedestal.
-- One center item is inserted, its output removed, then next center item.
local function runImbuement()
  if not empty(machine) or not allPedestalsEmpty() then
    fail("Machine/pedestals not empty; clear manually before starting")
  end
  local batch = entries(buffer)
  if #batch == 0 then return end
  local center = batch[1]
  if #batch-1 > #pedestals then fail("Not enough pedestals for " .. (#batch-1) .. " ingredient slots") end
  print("Imbuement: " .. center.count .. " center item(s)")
  -- Load catalysts once, one inventory slot per pedestal.
  for i=2,#batch do
    local item = batch[i]
    transfer(buffer, pedestalNames[i-1], item.slot, item.count)
  end
  for index=1,center.count do
    local current = entries(buffer)
    local centerSlot
    for _, item in ipairs(current) do
      if item.name == center.name then centerSlot = item.slot; break end
    end
    if not centerSlot then fail("Center items ran out before batch completed") end
    transfer(buffer, machineName, centerSlot, 1)
    -- Chamber should change the inserted item into the result.
    local inputSnapshot = snapshot(machine)
    waitForChange(inputSnapshot, "imbuement result " .. index)
    sendAll(machine)
    print("Completed " .. index .. "/" .. center.count)
  end
  clearPedestals()
  if not empty(machine) or not allPedestalsEmpty() then fail("Unable to clear machine/pedestals") end
end

-- For Enchanting: one center reagent per request, each pedestal gets one item.
-- Completion requires the center inventory to change from its inserted input.
local function runEnchanting()
  if not empty(machine) or not allPedestalsEmpty() then
    fail("Machine/pedestals not empty; clear manually before starting")
  end
  local batch = entries(buffer)
  if #batch == 0 then return end
  local center = batch[1]
  if center.count ~= 1 then fail("Enchanting expects one center reagent per batch") end
  local needed = 0
  for i=2,#batch do needed = needed + batch[i].count end
  if needed > #pedestals then fail("Need " .. needed .. " pedestals, found " .. #pedestals) end
  local pIndex = 1
  for i=2,#batch do
    for n=1,batch[i].count do
      transfer(buffer, pedestalNames[pIndex], batch[i].slot, 1)
      pIndex = pIndex + 1
    end
  end
  sleep(0.5)
  transfer(buffer, machineName, center.slot, 1)
  local before = snapshot(machine)
  waitForChange(before, "enchanting result")
  sendAll(machine)
  clearPedestals()
  if not empty(machine) or not allPedestalsEmpty() then fail("Unable to clear machine/pedestals") end
end

print("Unified Ars Controller | " .. mode)
print("Machine: " .. machineName)
print("Buffer: " .. bufferName)
print("Provider: " .. providerName)
print("Pedestals: " .. #pedestals)
print("Setup OK")
if #pedestals < 8 then print("WARNING: Only " .. #pedestals .. " pedestals connected") end

while true do
  if not empty(buffer) and awaitBufferStable() then
    local ok, err = pcall(function()
      if mode == "imbuement" then runImbuement() else runEnchanting() end
    end)
    if not ok then
      printError(err)
      print("Controller stopped. Inspect inventories before restarting.")
      break
    end
  end
  sleep(POLL)
end
