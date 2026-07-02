--- sf-nvim retrieve picker module
-- @license MIT

local Snacks = require("snacks")
local Const = require("sf.const")

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
      local type_val = item.type or "Unknown"
      if #type_val > 20 then type_val = type_val:sub(1, 17) .. "..." end

      local name_val = item.fullName or "Unknown"
      if #name_val > 40 then name_val = name_val:sub(1, 37) .. "..." end

      local id_val = item.id or "Unknown"
      if #id_val > 18 then id_val = id_val:sub(1, 15) .. "..." end

      return {
        { string.format("%-20s ", type_val), "SnacksPickerComment" },
        { " ", "SnacksPickerComment" },
        { string.format("%-40s ", name_val), "SnacksPickerNormal" },
        { " ", "SnacksPickerComment" },
        { "ID:", "SnacksPickerComment" },
        { string.format("%-18s ", id_val), "SnacksPickerComment" },
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
        "                     " .. Const.ICONS.METADATA .. " Metadata Details",
        "===========================================================",
        "",
        Const.ICONS.TYPE .. " Type:          " .. (item.type or "Unknown"),
        Const.ICONS.LOG_INFO .. " Full Name:     " .. (item.fullName or "Unknown"),
        Const.ICONS.LOG_ID .. " ID:            " .. (item.id or "Unknown"),
        Const.ICONS.FILE .. " File:          " .. (item.file_name or "Unknown"),
        "",
        "                    " .. Const.ICONS.TECHNICAL .. " Audit Info",
        "===========================================================",
        "",
        Const.ICONS.USER .. " Created By:    " .. (item.created_by or "Unknown"),
        Const.ICONS.TIME .. " Created:       " .. (item.created_date or "Unknown"),
        Const.ICONS.DURATION .. " Modified:      " .. (item.last_modified or "Unknown"),
        Const.ICONS.STATE .. " State:         " .. (item.manageable_state or "Unknown"),
      }

      vim.bo[ctx.buf].modifiable = true
      vim.api.nvim_buf_set_lines(ctx.buf, 0, -1, false, details)
      vim.bo[ctx.buf].modifiable = false
    end,
  })
end

return Picker
