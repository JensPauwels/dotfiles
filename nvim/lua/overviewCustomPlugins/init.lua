local fzf = require("fzf")

local function version()
  -- Return the version number of the plugin.
  print("1.0.0")
  return "1.0.0"
end

local function getOption()
  local options = {
    {
      text = "1. Create a new file - <Leader>file",
      callback = function ()
        require('createFile').start();
      end
    },
    {
      text = "2. Create a new modal - <Leader>model",
      callback = function ()
        require('modelCreator').start();
      end
    }
  }

  local textArray = {};

  for _, value in ipairs(options) do
    table.insert(textArray, value.text)
  end

  local result = fzf.fzf(textArray)

  if result then
    local selectedOption = result[1];

    for _, value in ipairs(options) do
      if (value.text == selectedOption) then
        value.callback()
      end
    end
  end
end

local function start()
  coroutine.wrap(getOption)();
end

-- Export the plugin functions to the Lua state.
return {
  version = version,
  start = start
}
