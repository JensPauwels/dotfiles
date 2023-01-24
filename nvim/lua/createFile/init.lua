local fzf = require("fzf")

local function version()
  -- Return the version number of the plugin.
  print("1.0.0")
  return "1.0.0"
end

local function writeToFile(fileToWriteTo, content)
  local file = io.open(fileToWriteTo, 'a');
  io.output(file)
  io.write(content);
  io.close();
end

local function createFile(filename)
  return io.open(filename, "w");
end

local function handleFolder(folder)
  -- get the name for the new file
  local newFileName = vim.fn.input("Filename: ", "", "file");

  -- Add the entry to the index file
  writeToFile(folder..'/index.js', 'export { default as '..newFileName:gsub('.js', '')..' } from \'./'..newFileName..'\';\n');

  -- add the new file
  createFile(folder..'/'..newFileName)
end

local function getDirectory()
  -- get all the directories within the current project
  local result = fzf.fzf("fd --type d --exclude node_modules")

  if result then
    -- proceeds with the result
    handleFolder(result[1]);
  end
end

local function start()
  coroutine.wrap(getDirectory)();
end

-- Export the plugin functions to the Lua state.
return {
  version = version,
  start = start
}
