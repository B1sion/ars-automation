-- Change USERNAME and REPOSITORY to your public GitHub repo.
local base='https://raw.githubusercontent.com/B1sion/ars-automation/main/'
for _,name in ipairs({'ars.lua','recipes.lua','update.lua'}) do
  local response,err=http.get(base..name)
  if not response then error('Download failed: '..name..': '..tostring(err)) end
  local content=response.readAll()
  response.close()
  local file=assert(fs.open(name..'.new','w'))
  file.write(content)
  file.close()
  if fs.exists(name) then fs.delete(name) end
  fs.move(name..'.new',name)
  print('Updated '..name)
end
