local function version()
  -- Return the version number of the plugin.
  print("1.0.0")
  return "1.0.0"
end

local function writeToFile(fileToWriteTo, content)
  local file = io.open(fileToWriteTo, 'a');
  io.output(file);
  io.write(content);
  io.close();
end

local function getCurrentFile()
  return vim.api.nvim_buf_get_name(0)
end

local function reloadCurrentBuffer()
  vim.cmd(':checktime')
end

local function generateConstructorParameters(params)
  local str = "";

  for idx, param in ipairs(params) do
    if idx ~= 1 then
      str = str.."\n\t\t"
    end

    str = str.."this."..param.." = param(data, '"..param.."');"
  end

  return str;
end

local function generateToJS(params)
  local str = "";

  for idx, param in ipairs(params) do
    if idx ~= 1 then
      str = str.."\n\t\t\t"
    end

    str = str..param..": this."..param..","
  end

  return str;
end

local function generateObservables(params)
  local str = "";

  for idx, param in ipairs(params) do
    if idx ~= 1 then
      str = str.."\n\t"
    end

    str = str..param..": observable,"
  end

  return str;
end

local function replaceValues(str, replacements)
  for k,v in pairs(replacements) do
    str = str:gsub(k, v);
  end

  return str;
end

local function buildModel(className, params)
  local baseStr = [[
import { observable, decorate } from 'mobx';
import { Param as param } from 'dpt-react';

class CLASSNAME {
  constructor(data) {
    CONSTRUCTOR_PARAMS
  }

  toJS = () => {
    return {
      TOJS
    }
  }
};

decorate(CLASSNAME, {
  OBSERVABLES
});

export default CLASSNAME;]];

  local replacements = {
    CONSTRUCTOR_PARAMS = generateConstructorParameters(params),
    OBSERVABLES = generateObservables(params),
    TOJS = generateToJS(params),
    CLASSNAME = className,
  };

  return replaceValues(baseStr, replacements);
end

local function start()
  local className = vim.fn.input("Class: ");
  local rawParams = vim.fn.input("Enter the variables comma separated: ");

  local params = {}

  for param in string.gmatch(rawParams, '([^,]+)') do
    local strippedStr = param:gsub(" ", "");
    table.insert(params, strippedStr);
  end

  writeToFile(getCurrentFile(), buildModel(className, params));
  reloadCurrentBuffer();
end

-- Export the plugin functions to the Lua state.
return {
  version = version,
  start = start
}
