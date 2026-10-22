-- StoneBlock 4 Ars Nouveau Enchanting Apparatus controller
-- EXPERIMENTAL: requires CC inventory peripheral exposure for apparatus/pedestals.
-- Connect exactly 8 pedestals, input chest, output chest and apparatus with wired modems.
-- Input must receive one complete AE2 pattern at a time (blocking mode).
-- For output, connect an AE2 Import Bus to the output chest.
local config = {
  input = 'minecraft:chest_0',
  output = 'minecraft:chest_1',
  apparatus = 'ars_nouveau:enchanting_apparatus_0',
  timeoutSeconds = 90,
}
local recipes = dofile('recipes.lua')
local function inv(name)
  local p = peripheral.wrap(name)
  assert(p and type(p.list)=='function' and type(p.pushItems)=='function', 'Missing inventory peripheral: '..name)
  return p
end
local input, output, apparatus = inv(config.input), inv(config.output), inv(config.apparatus)
local pedestals = {}
for _, name in ipairs(peripheral.getNames()) do
  if name:find('arcane_pedestal', 1, true) or name:find('arcane_platform', 1, true) then
    inv(name)
    pedestals[#pedestals+1] = name
  end
end
table.sort(pedestals)
assert(#pedestals == 8, 'Expected 8 pedestals, found '..#pedestals)
local function countItems(p)
  local counts={}
  for _, item in pairs(p.list()) do counts[item.name]=(counts[item.name] or 0)+item.count end
  return counts
end
local function slotFor(p, id)
  for slot,item in pairs(p.list()) do if item.name==id then return slot end end
end
local function push(p, dest, slot, count)
  local n=p.pushItems(dest, slot, count)
  assert(n==count, 'Moved '..tostring(n)..'/'..count..' items to '..dest)
end
local function idle()
  if next(apparatus.list()) then return false end
  for _,name in ipairs(pedestals) do if next(inv(name).list()) then return false end end
  return true
end
local function recipeForInput()
  local available=countItems(input)
  for _,recipe in ipairs(recipes) do
    local required={}
    required[recipe.reagent]=1
    for id,n in pairs(recipe.ingredients) do required[id]=(required[id] or 0)+n end
    local ok=true
    for id,n in pairs(required) do if available[id]~=n then ok=false end end
    for id in pairs(available) do if not required[id] then ok=false end end
    if ok then return recipe end
  end
end
local function craft(recipe)
  print('Crafting '..recipe.output)
  local ids={}
  for id in pairs(recipe.ingredients) do ids[#ids+1]=id end
  table.sort(ids)
  local index=1
  for _,id in ipairs(ids) do
    for _=1,recipe.ingredients[id] do
      assert(index<=#pedestals, 'Too many ingredients')
      local slot=assert(slotFor(input,id), 'Missing '..id)
      push(input,pedestals[index],slot,1)
      index=index+1
    end
  end
  sleep(0.5)
  push(input,config.apparatus,assert(slotFor(input,recipe.reagent)),1)
  local deadline=os.epoch('utc')+config.timeoutSeconds*1000
  local resultSlot
  repeat
    resultSlot=slotFor(apparatus,recipe.output)
    if resultSlot then break end
    sleep(0.25)
  until os.epoch('utc')>=deadline
  assert(resultSlot, 'Timeout: no output detected. Check Source, core, and activation.')
  push(apparatus,config.output,resultSlot,1)
  for _,name in ipairs(pedestals) do
    local p=inv(name)
    for slot,item in pairs(p.list()) do push(p,config.output,slot,item.count) end
  end
  print('Finished '..recipe.output)
end
print('Ars controller started; '..#recipes..' recipes loaded')
while true do
  if idle() then
    local recipe=recipeForInput()
    if recipe then
      local ok,err=pcall(craft,recipe)
      if not ok then printError(err); print('HALTED to prevent item loss'); break end
    end
  end
  sleep(0.5)
end
