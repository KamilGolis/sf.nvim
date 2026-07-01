--- sf-nvim retrieve picker module
-- @license MIT

local Snacks = require("snacks")

local Picker = {}

--- Create a multi-select picker for individual metadata items.
--- @param items table Array of picker items with fullName, id, type, file_name, etc.
--- @param xml_name string The metadata type xmlName (used in preview header context)
--- @param on_confirm function(items) Called with array of selected items on confirm
function Picker.create_items_picker(items, xml_name, on_confirm)
  if not items or #items == 0 then
    vim.notify("No metadata items to display.", vim.log.levels.WARN)
    return
  end

  Snacks.picker({
    items = items,
    layout = {
      preset = "telescope",
      width = 0.9,
      height = 0.8,
    },
    multiselect = true,
    format = function(item, _)
      return {
        { item.type .. ": ", "SnacksPickerComment" },
        { item.fullName .. " ", "SnacksPickerNormal" },
        { "(id:" .. item.id .. ")", "SnacksPickerComment" },
      }
    end,
    confirm = function(picker, item)
      picker:close()

      local selected = picker:selected() or {}

      if #selected == 0 and item then
        selected = { item }
      end

      if #selected == 0 then
        return
      end

      on_confirm(selected)
    end,
    preview = function(ctx)
      local item = ctx.item

      if not item then
        return
      end

      local details = {
        "                     Metadata Details",
        "===========================================================",
        "",
        " Type:       " .. (item.type or "Unknown"),
        " Full Name:  " .. (item.fullName or "Unknown"),
        " ID:         " .. (item.id or "Unknown"),
        " File:       " .. (item.file_name or "Unknown"),
        " Created by: " .. (item.created_by or "Unknown"),
        " Created:    " .. (item.created_date or "Unknown"),
        " Modified:   " .. (item.last_modified or "Unknown"),
        " State:      " .. (item.manageable_state or "Unknown"),
      }

      vim.bo[ctx.buf].modifiable = true
      vim.api.nvim_buf_set_lines(ctx.buf, 0, -1, false, details)
      vim.bo[ctx.buf].modifiable = false
    end,
  })
end

return Picker
