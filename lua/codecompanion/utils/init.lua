local api = vim.api

local M = {}

---Fire an event
---@param event string
---@param opts? table
function M.fire(event, opts)
  opts = opts or {}
  api.nvim_exec_autocmds("User", { pattern = "CodeCompanion" .. event, data = opts })
end

---Notify the user
---@param msg string
---@param level? number|string
---@return nil
function M.notify(msg, level)
  level = level or vim.log.levels.INFO
  return vim.notify(msg, level, {
    title = "CodeCompanion",
  })
end

---Get the Operating System
---@return string
function M.os()
  local os_name
  if vim.fn.has("win32") == 1 then
    os_name = "Windows"
  elseif vim.fn.has("macunix") == 1 then
    os_name = "macOS"
  elseif vim.fn.has("unix") == 1 then
    os_name = "Unix"
  else
    os_name = "Unknown"
  end
  return os_name
end

---Make the first letter uppercase
---@param str string
---@return string
M.capitalize = function(str)
  local result = str:gsub("^%l", string.upper)
  return result
end

---Check if a table is an array
---@param t table
---@return boolean
M.is_array = function(t)
  if type(t) == "table" and type(t[1]) == "table" then
    return true
  end
  return false
end

---@param table table
---@param value string
---@return boolean
M.contains = function(table, value)
  for _, v in pairs(table) do
    if v == value then
      return true
    end
  end
  return false
end

M._noop = function() end

---@param name string
---@return nil
M.set_dot_repeat = function(name)
  vim.go.operatorfunc = "v:lua.require'codecompanion.utils'._noop"
  vim.cmd.normal({ args = { "g@l" }, bang = true })
  vim.go.operatorfunc = string.format("v:lua.require'codecompanion'.%s", name)
end

---Replace any placeholders (e.g. ${placeholder}) in a string or table
---@param t table|string
---@param replacements table
---@return nil|string
function M.replace_placeholders(t, replacements)
  if type(t) == "string" then
    for placeholder, replacement in pairs(replacements) do
      t = t:gsub("%${" .. placeholder .. "}", replacement)
    end
    return t
  else
    for key, value in pairs(t) do
      if type(value) == "table" then
        M.replace_placeholders(value, replacements)
      elseif type(value) == "string" then
        for placeholder, replacement in pairs(replacements) do
          value = value:gsub("%${" .. placeholder .. "}", replacement)
        end
        t[key] = value
      end
    end
  end
end

---@param msg string
---@param vars table
---@param mapping table
---@return string
function M.replace_vars(msg, vars, mapping)
  local replacements = {}
  for _, var_name in ipairs(vars) do
    -- Check if the variable exists in the mapping
    if mapping[var_name] then
      table.insert(replacements, mapping[var_name])
    else
      error("Variable '" .. var_name .. "' not found in the mapping.")
    end
  end
  return string.format(msg, unpack(replacements))
end

---Safely get the filetype
---@param filetype string
---@return string
function M.safe_filetype(filetype)
  if filetype == "C++" then
    return "cpp"
  end
  return filetype
end

---Set an option in Neovim
---@param bufnr integer
---@param opt string
---@param value any
function M.set_option(bufnr, opt, value)
  if api.nvim_set_option_value then
    return api.nvim_set_option_value(opt, value, {
      buf = bufnr,
    })
  end
  if api.nvim_buf_set_option then
    return api.nvim_buf_set_option(bufnr, opt, value)
  end
end

function M.get_project_root()
  local project_markers = { ".git", ".svn", ".hg", "package.json", "Cargo.toml" }
  return vim.fs.root(0, project_markers)
end

---Sanitize filenames to safely store path information
---Replaces "_" with "__" to escape existing underscores, then "/" with "_"
---@param filename string Original filename/path containing possible underscores and slashes
---@return string Sanitized filename safe for flat storage
---@example
--- sanitize_filename("a/b_c.txt") -> "a_b__c.txt"
function M.sanitize_filename(filename)
  -- First escape existing underscores
  local escaped = filename:gsub("_", "__")
  -- Then replace slashes with single underscores
  local r, _ = escaped:gsub("/", "_")
  return r
end

---Reverse the sanitization process to recover original path
---First converts "_" back to "/", then restores original underscores from "__"
---@param sanitized_name string Sanitized filename from sanitize_filename()
---@return string Original path with slashes and underscores restored
---@example
--- desanitize_filename("a_b__c.txt") -> "a/b_c.txt"
function M.desanitize_filename(sanitized_name)
  -- First replace separator underscores with slashes
  local with_slashes = sanitized_name:gsub("_", "/")
  -- Then unescape original underscores
  local r, _ = with_slashes:gsub("//", "_")
  return r
end

---Get prompt content from files
---Search location: project root and cwd                                                          return M
---Filename pattern: .prompt .*.prompt
---@class CodeCompanionPromptContent
---@field prompt string
---@field adapter_prompt table<string, string>
---@return CodeCompanionPromptContent
---@example
--- { prompt: "", model_prompt: { ["deepseek-r1"] = "" } }
function M.get_prompt_content()
  local project_root = M.get_project_root()
  local cwd = vim.fn.getcwd()

  local function read_prompt_file(filepath)
    local file = io.open(filepath, "r")
    if file then
      local content = file:read("a")
      file:close()
      return content
    end
    return ""
  end

  local function process_prompt_files(dir)
    local prompt_content = { prompt = "", adapter_prompt = {} }
    local prompt_files = {}
    for entry in vim.fs.dir(dir, { depth = 1 }) do
      if entry:match("%.prompt$") then
        table.insert(prompt_files, vim.fs.joinpath(dir, entry))
      end
    end
    for _, filepath in ipairs(prompt_files) do
      local filename = vim.fs.basename(filepath)
      local content = read_prompt_file(filepath)
      if filename == ".prompt" then
        prompt_content.prompt = content
      elseif filename:match("%.prompt$") then
        local adapter_name = M.desanitize_filename(filename:gsub("%.prompt$", ""):sub(2)) -- remove .prompt and leading dot
        prompt_content.adapter_prompt[adapter_name] = content
      end
    end
    print(vim.inspect(prompt_content))
    return prompt_content
  end

  if vim.loop.fs_stat(vim.fs.joinpath(cwd, ".codecompanion")) ~= nil then
    return process_prompt_files(vim.fs.joinpath(cwd, ".codecompanion"))
  end

  if project_root and vim.loop.fs_stat(vim.fs.joinpath(project_root, ".codecompanion")) ~= nil then
    return process_prompt_files(vim.fs.joinpath(project_root, ".codecompanion"))
  end
  return { prompt = "", adapter_prompt = {} }
end

return M
