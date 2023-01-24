local function version()
  -- Return the version number of the plugin.
  print("1.0.0")
  return "1.0.0"
end

local function read_file(path)
    local file = io.open(path, "rb") -- r read mode and b binary mode
    if not file then return nil end
    local content = file:read "*a" -- *a or *all reads the whole file
    file:close()
    return content
end

local function getCurrentFile()
  return vim.api.nvim_buf_get_name(0)
end

local function reloadCurrentBuffer()
  vim.cmd(':checktime')
end

local function writeToFile(fileToWriteTo, content)
  local file = io.open(fileToWriteTo, 'a');
  io.output(file);
  io.write(content);
  io.close();
end

local buffer_to_string = function()
    local content =  vim.api.nvim_buf_get_lines(0, 0, vim.api.nvim_buf_line_count(0), false)
    return table.concat(content, "\n")
end

local function replaceValues(str, replacements)
  for k,v in pairs(replacements) do
    str = str:gsub(k, v);
  end

  return str;
end

local function start()
  local name = vim.api.nvim_buf_get_name(0)
  print(getCurrentFile())
  local curBuffer =  buffer_to_string()

  index = string.find(name, "/[^/]*$")
  path = string.sub(name,1,index)
  file = string.sub(name, index, #name)
  file = file:gsub("/", "")
  file = file:gsub(".go", "_test.go")

  local fileContent = read_file(path..file);

  local matches = {}
  for s in curBuffer:gmatch("[^\r\n]+") do
    for match in s:gmatch('func.*%(') do
      local strippedVal = match:gsub("[ ]", "")
      strippedVal = strippedVal:gsub("func", "")
      index = string.find(strippedVal, "%(")
      strippedVal = string.sub(strippedVal, 0, index - 1)
      table.insert(matches, strippedVal)
    end
  end

  local generatedTests = ""

  for key, val in pairs(matches) do 
    local exists = string.find(fileContent, string.format("Test%s", val:gsub("^%l", string.upper)))
    if exists == nil then
      generatedTests = generatedTests .. string.format([[
func Test%s(t *testing.T) {

}

]], val:gsub("^%l", string.upper))
    end 
  end


  writeToFile(path..file, generatedTests)
  -- writeToFile("/tmp/test.txt", fileContent)
  vim.cmd(':checktime')
end

-- Export the plugin functions to the Lua state.
return {
  version = version,
  start = start
}
