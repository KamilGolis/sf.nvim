--- sf-nvim debug picker module
-- @license MIT

local Const = require("sf.const")
local DebugUtils = require("sf.debug.utils")

local Picker = {}

--- Show a Snacks picker for selecting a DebugLevel with details preview.
--- @param debug_levels table Array of DebugLevel records
--- @param on_select fun(dl: table) Called with the selected full DebugLevel record
function Picker.create_debug_level_picker(debug_levels, on_select)
  local Snacks = require("snacks")

  local items = {}
  for _, dl in ipairs(debug_levels) do
    table.insert(items, DebugUtils.debug_level_to_picker_item(dl))
  end

  Snacks.picker({
    title = "Select Debug Level",
    items = items,
    layout = { preset = "telescope", width = 0.9, height = 0.8 },
    format = function(item, _)
      local name = item.text or ""
      if #name > 30 then
        name = name:sub(1, 27) .. "..."
      end

      local id = item.id or "Unknown"
      if #id > 18 then
        id = id:sub(1, 15) .. "..."
      end

      local description = item.description or ""
      if #description > 30 then
        description = description:sub(1, 27) .. "..."
      end

      return {
        { string.format("%-30s ", name), "SnacksPickerNormal" },
        { " ", "SnacksPickerComment" },
        { string.format("%-30s ", description), "SnacksPickerComment" },
        { " ", "SnacksPickerComment" },
        { string.format("%-18s ", id), "SnacksPickerComment" },
      }
    end,
    confirm = function(picker, item)
      picker:close()

      if not item or not item.details then
        return
      end

      on_select(item.details)
    end,
    preview = function(ctx)
      local help_text = ctx.item

      if not help_text then
        return { " No item selected" }
      end

      -- Render debug level fields in preview buffer
      local dl = ctx.item.details

      if not dl then
        return { " No details available" }
      end

      local function sanitize_text(text)
        if not text or text == "" then
          return "Unknown"
        end

        text = tostring(text)
        text = text:gsub("[\r\n\t]", " ")
        text = text:gsub("%s+", " ")
        text = text:gsub("^%s+", ""):gsub("%s+$", "")

        return text
      end

      local details = {
        "                     " .. Const.ICONS.LOG_INFO .. " Debug Level Details",
        "===========================================================",
        "",
        Const.ICONS.USER .. " Developer Name:  " .. sanitize_text(dl.DeveloperName),
        Const.ICONS.INFO .. " Master Label:    " .. sanitize_text(dl.MasterLabel),
        Const.ICONS.TIME .. " Created:         " .. sanitize_text(dl.CreatedDate),
        Const.ICONS.OPERATION .. " Language:        " .. sanitize_text(dl.Language),
        Const.ICONS.LOG_ID .. " Id:              " .. sanitize_text(dl.Id),
        "",
        "                     " .. Const.ICONS.METADATA .. " Log Categories",
        "===========================================================",
        "",
        "Apex Code:       " .. sanitize_text(dl.ApexCode),
        "Apex Profiling:  " .. sanitize_text(dl.ApexProfiling),
        "Callout:         " .. sanitize_text(dl.Callout),
        "Data Access:     " .. sanitize_text(dl.DataAccess),
        "Database:        " .. sanitize_text(dl.Database),
        "NBA:             " .. sanitize_text(dl.Nba),
        "System:          " .. sanitize_text(dl.System),
        "Validation:      " .. sanitize_text(dl.Validation),
        "Visualforce:     " .. sanitize_text(dl.Visualforce),
        "Wave:            " .. sanitize_text(dl.Wave),
        "Workflow:        " .. sanitize_text(dl.Workflow),
      }

      vim.bo[ctx.buf].modifiable = true
      vim.api.nvim_buf_set_lines(ctx.buf, 0, -1, false, details)
      vim.bo[ctx.buf].modifiable = false

      return true
    end,
  })
end

--- Build a picker for valid values of a debug level field.
--- @param field_def table The field definition from Const.DEBUG_LEVEL_FIELDS
--- @param on_select fun(value: string) Called with the selected value
function Picker.create_field_value_picker(field_def, on_select)
  local values = field_def.values

  if not values or #values == 0 then
    return
  end

  local items = {}
  for _, v in ipairs(values) do
    table.insert(items, { text = v, value = v })
  end

  vim.schedule(function()
    local Snacks = require("snacks")

    Snacks.picker({
      title = "Select " .. field_def.label,
      items = items,
      layout = { preset = "vscode" },
      format = function(item)
        return { { item.text } }
      end,
      confirm = function(picker, item)
        picker:close()
        if item and item.value then
          on_select(item.value)
        end
      end,
    })
  end)
end

--- Build an input picker for the DeveloperName field.
--- @param current_value string The current value
--- @param on_confirm fun(value: string) Called with the entered name
function Picker.create_name_input(current_value, on_confirm)
  local Snacks = require("snacks")

  Snacks.input({
    prompt = "Log Level Name: ",
    default = current_value,
  }, function(value)
    if value and value ~= "" then
      on_confirm(value)
    end
  end)
end

return Picker
