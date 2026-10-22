
-- Ars Nouveau Enchanting Apparatus
-- AE2 + CC:Tweaked
-- StoneBlock 4 prototype
--
-- Requires inventory peripheral support.
-- One recipe per input batch.
-- Pattern Provider must use blocking mode.

local cfg = {
  input = "minecraft:chest_0",
  output = "minecraft:chest_1",
  apparatus = "ars_nouveau:enchanting_apparatus_0",
  timeout = 90
}

-- ADD YOUR RECIPES HERE
-- Each recipe identifies the central reagent,
-- pedestal ingredients, and expected output.
--
-- Item names must be registry IDs.
local recipes = {
  {
    reagent = "minecraft:diamond",
    output = "ars_nouveau:example_output",
    ingredients = {
      ["minecraft:gold_ingot"] = 2,
      ["minecraft:lapis_lazuli"] = 2
    }
  }
}

-- The example above is a placeholder.
-- Replace it with a real JEI recipe.

local function inventory(name)
  local p = peripheral.wrap(name)
  assert(p, "Missing peripheral: " .. name)
  assert(type(p.list) == "function",
    "Not an inventory: " .. name)
  return p
end

local input = inventory(cfg.input)
local output = inventory(cfg.output)
local apparatus = inventory(cfg.apparatus)

local pedestals = {}

for _, name in ipairs(peripheral.getNames()) do
  if name:find("arcane_pedestal", 1, true)
    or name:find("arcane_platform", 1, true) then
    table.insert(pedestals, name)
  end
end

table.sort(pedestals)
assert(#pedestals >= 1, "No pedestals detected")

local function counts(inv)
  local result = {}
  for _, item in pairs(inv.list()) do
    result[item.name] =
      (result[item.name] or 0) + item.count
  end
  return result
end

local function findSlot(inv, id)
  for slot, item in pairs(inv.list()) do
    if item.name == id then return slot end
  end
end

local function transfer(src, dst, slot, amount)
  local n = src.pushItems(dst, slot, amount)
  assert(n == amount,
    "Transfer failed: " .. tostring(n)
    .. "/" .. tostring(amount))
end

local function matchRecipe()
  local available = counts(input)

  for _, recipe in ipairs(recipes) do
    local needed = {}

    needed[recipe.reagent] = 1

    for id, count in pairs(recipe.ingredients) do
      needed[id] = (needed[id] or 0) + count
    end

    local matches = true

    for id, count in pairs(needed) do
      if (available[id] or 0) ~= count then
        matches = false
        break
      end
    end

    for id in pairs(available) do
      if not needed[id] then
        matches = false
        break
      end
    end

    if matches then return recipe end
  end
end

local function clearPedestals()
  for _, name in ipairs(pedestals) do
    local p = inventory(name)
    for slot, item in pairs(p.list()) do
      transfer(p, cfg.output, slot, item.count)
    end
  end
end

local function isIdle()
  if next(apparatus.list()) then return false end

  for _, name in ipairs(pedestals) do
    if next(inventory(name).list()) then
      return false
    end
  end

  return true
end

local function craft(recipe)
  print("Crafting " .. recipe.output)

  local index = 1

  -- Fill all pedestal ingredients first.
  local ids = {}
  for id in pairs(recipe.ingredients) do
    table.insert(ids, id)
  end
  table.sort(ids)

  for _, id in ipairs(ids) do
    local amount = recipe.ingredients[id]

    for i = 1, amount do
      assert(index <= #pedestals,
        "Not enough pedestals")

      local slot = findSlot(input, id)
      assert(slot, "Missing ingredient: " .. id)

      transfer(input, pedestals[index], slot, 1)
      index = index + 1
    end
  end

  sleep(0.5)

  -- Insert reagent last.
  local slot = findSlot(input, recipe.reagent)
  assert(slot, "Missing reagent")

  transfer(input, cfg.apparatus, slot, 1)

  -- Wait for expected output.
  local deadline = os.epoch("utc")
    + cfg.timeout * 1000

  local resultSlot

  while os.epoch("utc") < deadline do
    resultSlot = findSlot(apparatus, recipe.output)

    if resultSlot then break end
    sleep(0.25)
  end

  assert(resultSlot, "Craft timed out")

  -- Extract only the expected result.
  transfer(apparatus, cfg.output, resultSlot, 1)

  sleep(0.5)

  -- Recover anything left on pedestals.
  clearPedestals()

  print("Completed: " .. recipe.output)
end

print("Ars Apparatus Controller")
print("Pedestals found: " .. #pedestals)

while true do
  if isIdle() then
    local recipe = matchRecipe()

    if recipe then
      local ok, err = pcall(craft, recipe)

      if not ok then
        printError(err)
        print("Stopped to prevent item loss")
        break
      end
    end
  end

  sleep(0.5)
end
