--- sf-nvim Apex scripts picker module
-- @license MIT

local Const = require("sf.const")
local Log = require("sf.core.log")
local Snacks = require("snacks")

local Picker = {}

--- Create scripts selection picker using Snacks with fallback compatibility
--- @param items table Array of script items with file_path, file_name, content
--- @param callback function Callback function to handle script selection
function Picker.create_scripts_picker(items, callback)
  if not items or #items == 0 then
    Log.notify("No scripts available", vim.log.levels.INFO)
    return
  end

  local picker_config = {
    title = "Apex Scripts",
    items = items,
    format = function(item)
      return { { Const.ICONS.FILE .. " " .. item.file_name } }
    end,
    preview = function(ctx)
      local item = ctx.item or ctx.items[ctx.idx]

      if not item then
        return true
      end

      local lines = vim.split(item.content, "\n")

      vim.bo[ctx.buf].modifiable = true
      vim.api.nvim_buf_set_lines(ctx.buf, 0, -1, false, lines)
      vim.bo[ctx.buf].modifiable = false

      return true
    end,
    confirm = function(picker, item)
      if picker and picker.close then
        picker:close()
      end

      if callback then
        callback(item)
      end
    end,
  }

  local ok, err = pcall(Snacks.picker, picker_config)
  if not ok then
    local script_list = {}

    for _, item in ipairs(items) do
      table.insert(script_list, item.file_name)
    end

    Log.notify("Failed to create picker: " .. tostring(err), vim.log.levels.ERROR)
    Log.notify("Available scripts:\n" .. table.concat(script_list, "\n"), vim.log.levels.INFO)
  end
end

return Picker
