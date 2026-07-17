--- sf-nvim sObject faux class cache picker
-- Multi-select picker for choosing which sObjects to rebuild
-- @license MIT

local Log = require("sf.core.log").scoped("faux/picker")
local M = {}

--- Show a multi-select picker for sObject selection with quick-select options.
--- @param sobject_names string[] Array of sObject API names from the org
--- @param callback fun(selection: { mode: string, names: string[] })
---   mode is "all", "standard", "custom", or "selected"
---   names is the full or filtered list of names to describe
function M.show_sobject_picker(sobjects, callback)
  if not sobjects or #sobjects == 0 then
    return
  end

  -- Normalize: accept both flat strings and {name,custom} objects
  local has_custom_flag = type(sobjects[1]) == "table" and sobjects[1].custom ~= nil

  local items = {
    { text = "All", predefined = "all" },
    { text = "Standard Objects", predefined = "standard" },
    { text = "Custom Objects", predefined = "custom" },
  }

  for _, obj in ipairs(sobjects) do
    table.insert(items, {
      text = type(obj) == "table" and obj.name or obj,
      custom = has_custom_flag and obj.custom or nil,
    })
  end

  Log.deb("picker: has_custom_flag=" .. tostring(has_custom_flag) .. ", total_items=" .. #items)

  Snacks.picker({
    items = items,
    layout = { preset = "vscode" },
    format = function(item, _)
      if item.predefined then
        return { { "  " .. item.text, "SnacksPickerTitle" } }
      end
      return { { item.text } }
    end,
    multiselect = true,
    confirm = function(picker, item)
      picker:close()

      local selected = picker:selected() or {}
      if #selected == 0 and item then
        selected = { item }
      end
      if #selected == 0 then
        return
      end

      -- Resolve selection
      local has_all = false
      local has_standard = false
      local has_custom = false
      local chosen_names = {}

      for _, sel in ipairs(selected) do
        if sel.predefined == "all" then
          has_all = true
        elseif sel.predefined == "standard" then
          has_standard = true
        elseif sel.predefined == "custom" then
          has_custom = true
        else
          table.insert(chosen_names, sel.text)
        end
      end

      -- Pre-filter when custom flag is available
      local function extract_names(list)
        local names = {}

        for _, obj in ipairs(list) do
          table.insert(names, type(obj) == "table" and obj.name or obj)
        end

        return names
      end

      local function filter_by_custom(list, want_custom)
        local filtered = {}

        for _, obj in ipairs(list) do
          if obj.custom == want_custom then
            table.insert(filtered, obj)
          end
        end

        return filtered
      end

      -- "All" wins, or both Standard+Custom = All
      if has_all or (has_standard and has_custom) then
        Log.deb("picker resolved: all, names=" .. #sobjects)
        callback({ mode = "all", names = extract_names(sobjects) })
      elseif has_standard then
        local filtered = has_custom_flag and filter_by_custom(sobjects, false) or sobjects
        Log.deb("picker resolved: all (filtered standard), names=" .. #filtered)
        callback({ mode = "all", names = extract_names(filtered) })
      elseif has_custom then
        local filtered = has_custom_flag and filter_by_custom(sobjects, true) or sobjects
        Log.deb("picker resolved: all (filtered custom), names=" .. #filtered)
        callback({ mode = "all", names = extract_names(filtered) })
      elseif #chosen_names > 0 then
        Log.deb("picker resolved: selected, names=" .. #chosen_names)
        callback({ mode = "selected", names = chosen_names })
      end
    end,
    preview = function(ctx)
      local item = ctx.item
      local lines = { item.text }

      if item.predefined then
        lines = { "Quick-select: " .. item.text }
      else
        lines = { "sObject: " .. item.text }
      end

      vim.api.nvim_buf_set_lines(ctx.buf, 0, -1, false, lines)
    end,
  })
end

return M
