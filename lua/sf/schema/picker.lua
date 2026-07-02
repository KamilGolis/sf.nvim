--- sf-nvim schema picker module
-- @license MIT

local Snacks = require("snacks")

local Picker = {}

--- Create a picker for metadata types from the schema.
--- @param items table Array of { text = "...", xml_name = "...", directory_name = "..." }
--- @param on_confirm function(item) Called with the selected item on confirm
function Picker.create_type_picker(items, on_confirm)
  if not items or #items == 0 then
    vim.notify("No metadata types to display.", vim.log.levels.WARN)
    return
  end

  Snacks.picker({
    items = items,
    layout = { preset = "vscode" },
    format = function(item, _)
      return { { item.xml_name .. " (in " .. item.directory_name .. ")" } }
    end,
    confirm = function(picker, item)
      picker:close()

      if not item then
        return
      end

      on_confirm(item)
    end,
  })
end

return Picker
