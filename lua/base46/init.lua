local M = {}
local g = vim.g

-- Default options
local default_opts = {
  integrations = {
    "blankline",
    "blink",
    "cmp",
    "mason",
    "tbline",
    "telescope",
  },
  excluded = {},
  theme = nil,
  theme_toggle = { 'onedark', 'one_light' },
  transparency = false,
  hl_override = {},
  hl_add = {},
  changed_themes = {},
  ui = {
    cmp = {},
    telescope = {
      style = "bordered" -- bordered | borderless
    },
    statusline = {
      -- default | minimal | vscode | vscode_colored
      theme = "default",
    }
  },
}

M.opts = vim.deepcopy(default_opts)

local function tbval_index(tb, val)
  for i, v in ipairs(tb) do
    if v == val then
      return i
    end
  end
end

-- included by default integrations
local default_integrations = {
  "defaults",
  "devicons",
  "git",
  "lsp",
  "statusline",
  "syntax",
  "treesitter",
  "whichkey",
}

local function merge_opts()
  for _, value in ipairs(default_integrations) do
    if not tbval_index(M.opts.integrations, value) then
      table.insert(M.opts.integrations, value)
    end
  end

  for _, value in ipairs(M.opts.excluded or {}) do
    local val_i = tbval_index(M.opts.integrations, value)
    if val_i then
      table.remove(M.opts.integrations, val_i)
    end
  end
end

merge_opts()

M.setup = function(opts)
  if opts then
    M.opts = M.merge_tb(vim.deepcopy(default_opts), opts)
  end

  merge_opts()

  if M.opts.theme ~= nil then
    M.apply_theme(M.opts.theme)
  end
end

M.load_all_highlights = function()
  M.apply_theme(M.opts.theme)
end

M.get_theme_tb = function(type)
  local name = M.opts.theme
  local present1, default_theme = pcall(require, "base46.themes." .. name)
  local present2, user_theme = pcall(require, "themes." .. name)

  if present1 then
    return default_theme[type]
  elseif present2 then
    return user_theme[type]
  else
    error "No such theme!"
  end
end

M.merge_tb = function(...)
  return vim.tbl_deep_extend("force", ...)
end

local lighten = require("base46.colors").change_hex_lightness
local mixcolors = require("base46.colors").mix

-- turns color var names in hl_override/hl_add to actual colors
-- hl_add = { abc = { bg = "one_bg" }} -> bg = colors.one_bg
M.turn_str_to_color = function(tb)
  local colors = vim.tbl_extend("force", M.get_theme_tb "base_30", M.get_theme_tb "base_16")
  local copy = vim.deepcopy(tb)

  for _, hlgroups in pairs(copy) do
    for opt, val in pairs(hlgroups) do
      local valtype = type(val)

      if opt == "fg" or opt == "bg" or opt == "sp" then
        -- named colors from base30
        if valtype == "string" and val:sub(1, 1) ~= "#" and val ~= "none" and val ~= "NONE" then
          hlgroups[opt] = colors[val]
        elseif valtype == "table" then
          -- transform table to color
          hlgroups[opt] = #val == 2 and lighten(colors[val[1]], val[2])
              or mixcolors(colors[val[1]], colors[val[2]], val[3])
        end
      end
    end
  end

  return copy
end

M.extend_default_hl = function(highlights, integration_name)
  local polish_hl = M.get_theme_tb "polish_hl"

  -- polish themes
  if polish_hl and polish_hl[integration_name] then
    highlights = M.merge_tb(highlights, polish_hl[integration_name])
  end

  -- transparency
  if M.opts.transparency then
    local glassy = require "base46.glassy"

    for key, value in pairs(glassy) do
      if highlights[key] then
        highlights[key] = M.merge_tb(highlights[key], value)
      end
    end
  end

  local hl_override = M.opts.hl_override
  local overriden_hl = M.turn_str_to_color(hl_override)

  for key, value in pairs(overriden_hl) do
    if highlights[key] then
      highlights[key] = M.merge_tb(highlights[key], value)
    end
  end

  return highlights
end

M.get_integration = function(name)
  require('plenary.reload').reload_module("base46.integrations." .. name)
  local highlights = require("base46.integrations." .. name)
  return M.extend_default_hl(highlights, name)
end

-- convert table into string
M.tb_2hl = function(tb)
  for hlgroupName, v in pairs(tb) do
    --- @type vim.api.keyset.highlight
    local hlopts = {}

    for optName, optVal in pairs(v) do
      hlopts[optName] = optVal
    end

    vim.api.nvim_set_hl(0, hlgroupName, hlopts)
  end
end

M.apply_theme = function(theme)
  local present1 = pcall(require, "base46.themes." .. theme)
  local present2 = pcall(require, "themes." .. theme)
  if not present1 and not present2 then
    error "No such theme!"
  end

  M.opts.theme = theme
  require("base46.term").apply()
  vim.cmd.highlight('clear')
  vim.g.colors_name = 'base46-' .. theme

  for _, name in ipairs(M.opts.integrations) do
    M.tb_2hl(M.get_integration(name))

    if name == "defaults" then
      vim.o.tgc = true
      vim.o.bg = M.get_theme_tb("type")
    end
  end
end

local base46_path = vim.fn.fnamemodify(debug.getinfo(M.merge_tb, "S").source:sub(2), ":p:h")

M.list_themes = function()
  local default_themes = vim.fn.readdir(base46_path .. "/themes")
  local custom_themes = vim.uv.fs_stat(vim.fn.stdpath "config" .. "/lua/themes")

  if custom_themes and custom_themes.type == "directory" then
    local themes_tb = vim.fn.readdir(vim.fn.stdpath "config" .. "/lua/themes")
    for _, value in ipairs(themes_tb) do
      table.insert(default_themes, value)
    end
  end

  for index, theme in ipairs(default_themes) do
    default_themes[index] = theme:match "(.+)%..+"
  end

  return default_themes
end

M.override_theme = function(default_theme, theme_name)
  local changed_themes = M.opts.changed_themes
  return M.merge_tb(default_theme, changed_themes.all or {}, changed_themes[theme_name] or {})
end

--------------------------- user functions ----------------------------------------------------------
M.toggle_theme = function()
  local themes = M.opts.theme_toggle

  if M.opts.theme ~= themes[1] and M.opts.theme ~= themes[2] then
    vim.notify "Set your current theme to one of those mentioned in the theme_toggle table (chadrc)"
    return
  end

  g.icon_toggled = not g.icon_toggled
  g.toggle_theme_icon = g.icon_toggled and "   " or "   "

  M.opts.theme = (themes[1] == M.opts.theme and themes[2]) or themes[1]

  package.loaded.chadrc = nil
  M.load_all_highlights()
end

return M
