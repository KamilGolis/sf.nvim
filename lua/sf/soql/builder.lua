--- TODO: Lot of issues. Inconsistency with keybinds, no way to edit/remove WHERE, UI Inconsistency.
--- sf-nvim SOQL Query Builder — entry point, keymaps, and interaction workflow
-- @license MIT

local Compiler = require("sf.soql.compiler")
local Config = require("sf.config")
local Const = require("sf.const")
local Executor = require("sf.soql.executor")
local Log = require("sf.core.log").scoped("soql/builder")
local PathUtils = require("sf.core.path_utils")
local Render = require("sf.soql.render")
local Schema = require("sf.soql.schema")
local State = require("sf.soql.state")

local M = {}

--- Module-level cache mapping sobject name to describe data { fields, childRelationships }.
local describe_cache = {}

--- Guard: ensure Snacks.nvim is available.
local snacks_ok, Snacks = pcall(require, "snacks")
if not snacks_ok then
  Snacks = nil
end

--- Find the window displaying a given buffer.
--- @param bufnr integer
--- @return integer|nil window id
local function find_window_for_buf(bufnr)
  local wins = vim.api.nvim_list_wins()
  for _, w in ipairs(wins) do
    if vim.api.nvim_win_get_buf(w) == bufnr then
      return w
    end
  end
  return nil
end

--- Open the field multi-select picker for a QueryState.
--- Merges selected items into the current field set (does not replace).
--- @param state table QueryState
local function open_field_picker(state)
  if not Snacks then
    Log.notify(Const.SOQL.MESSAGES.SNACKS_REQUIRED_PICKER, vim.log.levels.ERROR)
    return
  end

  local describe_data = describe_cache[state.sobject]

  if not describe_data or not describe_data.fields then
    Log.notify(string.format(Const.SOQL.MESSAGES.NO_SCHEMA_DATA_FOR, state.sobject or "?"), vim.log.levels.ERROR)
    return
  end

  -- Capture window to restore focus after picker closes
  local win = find_window_for_buf(state.bufnr)

  local items = {}

  -- Add common standard fields first
  for _, f in ipairs(Const.SOQL.COMMON_STANDARD_FIELDS) do
    table.insert(items, {
      text = f,
      label = "(common -- may not be present)",
      api_name = f,
    })
  end

  -- Add described fields
  for _, f in ipairs(describe_data.fields) do
    table.insert(items, {
      text = f.name .. "  (" .. f.field_type .. ")  - " .. f.label,
      api_name = f.name,
    })
  end

  Snacks.picker({
    items = items,
    layout = { preset = "vscode" },
    multiselect = true,
    format = function(item)
      if item.label then
        return {
          { item.text, "Comment" },
          { " (" .. item.label .. ")", "Comment" },
        }
      end
      return { { item.text } }
    end,
    confirm = function(picker, _)
      local selected = picker:selected()
      picker:close()

      -- Restore focus to builder window
      if win and vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_set_current_win(win)
      end

      -- Merge: add selected items to the current set
      for _, item in ipairs(selected) do
        state.selected_fields[item.api_name] = true
      end

      Render.render(state)
    end,
  })
end

--- Open a multi-select picker listing all currently selected fields; confirming
--- removes the chosen ones (SYSTEM_FIELDS are kept by State.remove_fields).
--- @param state table QueryState
local function open_remove_picker(state)
  if not Snacks then
    Log.notify(Const.SOQL.MESSAGES.SNACKS_REQUIRED_REMOVER, vim.log.levels.ERROR)
    return
  end

  local win = find_window_for_buf(state.bufnr)
  local items = {}
  local fields = vim.tbl_keys(state.selected_fields)

  table.sort(fields)
  for _, f in ipairs(fields) do
    table.insert(items, { text = f, api_name = f })
  end

  Snacks.picker({
    items = items,
    layout = { preset = "vscode" },
    multiselect = true,
    format = function(item)
      return { { item.text } }
    end,
    confirm = function(picker, _)
      local selected = picker:selected()
      picker:close()

      if win and vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_set_current_win(win)
      end

      local to_remove = {}
      for _, item in ipairs(selected) do
        table.insert(to_remove, item.api_name)
      end

      local n = State.remove_fields(state, to_remove)
      if n == 0 then
        Log.notify(Const.SOQL.MESSAGES.REMOVED_NONE, vim.log.levels.INFO)
      else
        Log.notify(string.format(Const.SOQL.MESSAGES.REMOVED_COUNT, n), vim.log.levels.INFO)
      end

      Render.render(state)
    end,
  })
end

--- Add a parent relationship dotted field (e.g. Owner.Name, MyLookup__r.Custom__c).
--- Step 1: pick a reference field from the current SObject.
--- Step 2: determine the relationship name (relationshipName, or strip "Id" from field name).
--- Step 3: pick ONE field from the target SObject's describe.
--- Step 4: construct "RelationshipName.TargetField" and add to selected_fields.
--- @param state table QueryState
local function add_related_field(state)
  local describe_data = describe_cache[state.sobject]
  if not describe_data or not describe_data.fields then
    Log.notify(Const.SOQL.MESSAGES.NO_SCHEMA_DATA, vim.log.levels.ERROR)
    return
  end

  -- Filter to only reference-type fields that have referenceTo info
  local ref_fields = {}
  for _, f in ipairs(describe_data.fields) do
    if type(f.referenceTo) == "table" and #f.referenceTo > 0 then
      table.insert(ref_fields, f)
    end
  end

  if #ref_fields == 0 then
    Log.notify(string.format(Const.SOQL.MESSAGES.NO_RELATIONSHIP_FIELDS, state.sobject or "?"), vim.log.levels.INFO)
    return
  end

  local win = find_window_for_buf(state.bufnr)

  -- Step 1: Pick the relationship field
  local items = {}
  for _, f in ipairs(ref_fields) do
    local targets = table.concat(f.referenceTo, ", ")
    table.insert(items, {
      text = f.name .. "  (" .. f.field_type .. ")  \u{2192}  " .. targets,
      field = f,
    })
  end

  if Snacks then
    Snacks.picker({
      items = items,
      layout = { preset = "vscode" },
      prompt = "Related Field",
      format = function(item)
        return { { item.text } }
      end,
      confirm = function(picker, item)
        picker:close()
        if win and vim.api.nvim_win_is_valid(win) then
          vim.api.nvim_set_current_win(win)
        end

        local ref_field = item.field
        -- Determine the relationship name to use as path prefix
        -- relationshipName is the __r suffix name; if nil, strip "Id" from the field name
        local rel_name = ref_field.relationshipName
        if not rel_name or rel_name == vim.NIL then
          rel_name = ref_field.name

          if rel_name:sub(-2) == "Id" then
            rel_name = rel_name:sub(1, -3)
          end
        end

        -- Step 2: Fetch target SObject fields
        -- referenceTo is an array; use the first target
        local target_sobject = ref_field.referenceTo[1]
        if not target_sobject then
          return
        end

        -- Ensure target SObject schema is cached
        local function pick_target_fields()
          local target_describe = describe_cache[target_sobject]

          if not target_describe or not target_describe.fields then
            Schema.fetch_describe(target_sobject, function(data)
              if data then
                describe_cache[target_sobject] = data
                pick_target_fields() -- retry after cache
              end
            end)

            return
          end

          local target_items = {}
          for _, f in ipairs(target_describe.fields) do
            table.insert(target_items, {
              text = f.name .. "  (" .. f.field_type .. ")  - " .. f.label,
              api_name = f.name,
            })
          end

          Snacks.picker({
            items = target_items,
            layout = { preset = "vscode" },
            multiselect = true,
            prompt = "Field on " .. target_sobject,
            format = function(item2)
              return { { item2.text } }
            end,
            confirm = function(picker2, _)
              local selected = picker2:selected()
              picker2:close()

              if win and vim.api.nvim_win_is_valid(win) then
                vim.api.nvim_set_current_win(win)
              end

              for _, item in ipairs(selected) do
                local dotted = rel_name .. "." .. item.api_name
                state.selected_fields[dotted] = true
              end

              Render.render(state)
            end,
          })
        end

        pick_target_fields()
      end,
    })
  end
end

--- Start the WHERE condition 3-step workflow (field -> operator -> value).
--- @param state table QueryState
local function add_where_condition(state)
  local describe_data = describe_cache[state.sobject]

  if not describe_data or not describe_data.fields or #describe_data.fields == 0 then
    Log.notify(Const.SOQL.MESSAGES.NO_FIELDS_WHERE, vim.log.levels.ERROR)
    return
  end

  -- Capture window to restore focus after picker closes
  local win = find_window_for_buf(state.bufnr)

  local items = {}
  for _, f in ipairs(describe_data.fields) do
    table.insert(items, {
      text = f.name .. "  (" .. f.field_type .. ")  - " .. f.label,
      api_name = f.name,
    })
  end

  -- Step 1: Pick field
  if Snacks then
    Snacks.picker({
      items = items,
      layout = { preset = "vscode" },
      prompt = "Field",
      format = function(item)
        return { { item.text } }
      end,
      confirm = function(picker, item)
        picker:close()

        -- Restore focus to builder window
        if win and vim.api.nvim_win_is_valid(win) then
          vim.api.nvim_set_current_win(win)
        end

        local selected_field = item.api_name

        -- Step 2: Pick operator
        vim.ui.select(Const.SOQL.WHERE_OPERATORS, {
          prompt = "Operator for " .. selected_field,
        }, function(op)
          if not op then
            return
          end

          -- Step 3: Enter value
          vim.ui.input({
            prompt = "Value for " .. selected_field .. " " .. op,
          }, function(value)
            if not value or value == "" then
              return
            end

            table.insert(state.where_clauses, State.new_where_condition(selected_field, op, value))
            Render.render(state)
          end)
        end)
      end,
    })
  else
    Log.notify(Const.SOQL.MESSAGES.SNACKS_REQUIRED_FIELD_SEL, vim.log.levels.ERROR)
  end
end

--- TODO: Finish this - Start the ORDER BY 2-step workflow (field -> direction).
--- @param state table QueryState
local function add_order_by(state)
  local describe_data = describe_cache[state.sobject]

  if not describe_data or not describe_data.fields or #describe_data.fields == 0 then
    Log.notify(Const.SOQL.MESSAGES.NO_FIELDS_ORDERBY, vim.log.levels.ERROR)
    return
  end

  -- Capture window to restore focus after picker closes
  local win = find_window_for_buf(state.bufnr)

  local items = {}
  for _, f in ipairs(describe_data.fields) do
    table.insert(items, {
      text = f.name .. "  (" .. f.field_type .. ")  - " .. f.label,
      api_name = f.name,
    })
  end

  if Snacks then
    Snacks.picker({
      items = items,
      layout = { preset = "vscode" },
      prompt = "Order By Field",
      format = function(item)
        return { { item.text } }
      end,
      confirm = function(picker, item)
        picker:close()

        -- Restore focus to builder window
        if win and vim.api.nvim_win_is_valid(win) then
          vim.api.nvim_set_current_win(win)
        end

        vim.ui.select(Const.SOQL.ORDER_DIRECTIONS, {
          prompt = "Direction for " .. item.api_name,
        }, function(dir)
          if not dir then
            return
          end
          table.insert(state.order_by, State.new_order_by_clause(item.api_name, dir))
          Render.render(state)
        end)
      end,
    })
  else
    Log.notify(Const.SOQL.MESSAGES.SNACKS_REQUIRED_FIELD_SEL, vim.log.levels.ERROR)
  end
end

--- Set LIMIT via vim.ui.input.
--- @param state table QueryState
local function set_limit(state)
  vim.ui.input({
    prompt = "Enter LIMIT (positive integer or empty to clear)",
    default = state.limit and tostring(state.limit) or "",
  }, function(val)
    if val == nil then
      return
    end

    if val == "" then
      state.limit = nil
    else
      local n = tonumber(val)
      if not n or n < 0 or n ~= math.floor(n) then
        Log.notify(Const.SOQL.MESSAGES.LIMIT_BAD, vim.log.levels.ERROR)
        return
      end

      state.limit = n
    end

    Render.render(state)
  end)
end

--- Set OFFSET via vim.ui.input.
--- @param state table QueryState
local function set_offset(state)
  vim.ui.input({
    prompt = "Enter OFFSET (positive integer or empty to clear)",
    default = state.offset and tostring(state.offset) or "",
  }, function(val)
    if val == nil then
      return
    end

    if val == "" then
      state.offset = nil
    else
      local n = tonumber(val)
      if not n or n < 0 or n ~= math.floor(n) then
        Log.notify(Const.SOQL.MESSAGES.OFFSET_BAD, vim.log.levels.ERROR)
        return
      end

      state.offset = n
    end

    Render.render(state)
  end)
end

--- Open the SObject picker to switch the current root state's target SObject.
--- @param state table QueryState
local function switch_sobject(state)
  Schema.fetch_sobjects(function(sobjects)
    if not sobjects or #sobjects == 0 then
      return
    end

    -- Capture window to restore focus after picker closes
    local win = find_window_for_buf(state.bufnr)

    local items = {}
    for _, name in ipairs(sobjects) do
      table.insert(items, { text = name, api_name = name })
    end

    if Snacks then
      Snacks.picker({
        items = items,
        layout = { preset = "vscode" },
        format = function(item)
          return { { item.text } }
        end,
        confirm = function(picker, item)
          picker:close()

          -- Restore focus to builder window
          if win and vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_set_current_win(win)
          end

          -- Reset state
          state.sobject = item.api_name
          state.selected_fields = {}
          for _, f in ipairs(Const.SOQL.SYSTEM_FIELDS) do
            state.selected_fields[f] = true
          end
          state.where_clauses = {}
          state.subqueries = {}
          state.order_by = {}
          state.limit = nil
          state.offset = nil

          -- Fetch describe for new sobject
          Schema.fetch_describe(state.sobject, function(describe_data)
            if describe_data then
              describe_cache[state.sobject] = describe_data
            end
            Render.render(state)
          end)
        end,
      })
    else
      Log.notify(Const.SOQL.MESSAGES.SNACKS_REQUIRED_SOBJECT, vim.log.levels.ERROR)
    end
  end)
end

--- Open the subquery picker (child relationships) for a root state.
--- @param state table QueryState
local function add_subquery(state)
  local describe_data = describe_cache[state.sobject]

  if not describe_data or not describe_data.childRelationships or #describe_data.childRelationships == 0 then
    Log.notify(string.format(Const.SOQL.MESSAGES.NO_CHILD_RELATIONSHIPS, state.sobject or "?"), vim.log.levels.INFO)
    return
  end

  -- Capture window to restore focus after picker closes
  local win = find_window_for_buf(state.bufnr)

  local items = {}
  for _, r in ipairs(describe_data.childRelationships) do
    table.insert(items, {
      text = r.relationshipName .. " (" .. r.childSObject .. ")",
      api_name = r.relationshipName,
      child_sobject = r.childSObject,
    })
  end

  if Snacks then
    Snacks.picker({
      items = items,
      layout = { preset = "vscode" },
      format = function(item)
        return { { item.text } }
      end,
      confirm = function(picker, item)
        picker:close()

        -- Restore focus to builder window
        if win and vim.api.nvim_win_is_valid(win) then
          vim.api.nvim_set_current_win(win)
        end

        M.create_builder_buffer(item.child_sobject, true, state, item.api_name)
      end,
    })
  else
    Log.notify(Const.SOQL.MESSAGES.SNACKS_REQUIRED_RELATIONSHIP, vim.log.levels.ERROR)
  end
end

--- Delete an item (subquery, WHERE condition, or ORDER BY clause) at the cursor line.
--- @param state table QueryState
local function delete_item_at_cursor(state)
  local line = vim.api.nvim_get_current_line()

  -- Check for WHERE conditions: pattern "   N. field op value"
  for i, wc in ipairs(state.where_clauses) do
    if line:match("^%s+" .. i .. "%.") then
      table.remove(state.where_clauses, i)
      Render.render(state)
      return
    end
  end

  -- Check for ORDER BY clauses: pattern "   N. field DIRECTION"
  for i, ob in ipairs(state.order_by) do
    if line:match("^%s+" .. i .. "%.") then
      table.remove(state.order_by, i)
      Render.render(state)
      return
    end
  end

  -- Check for subqueries: pattern "     N. relationshipName "
  for i, sq in ipairs(state.subqueries) do
    if line:match("^%s+" .. i .. "%.") then
      if sq.bufnr and vim.api.nvim_buf_is_valid(sq.bufnr) then
        vim.api.nvim_buf_delete(sq.bufnr, { force = true })
      end
      table.remove(state.subqueries, i)
      Render.render(state)
      return
    end
  end
end

--- Delete the field under the cursor if the cursor is on a field bullet line.
--- No-op (with a notify) when not on a field line, or when the field is a
--- protected SYSTEM_FIELD.
--- @param state table QueryState
local function delete_field_at_cursor(state)
  local line = vim.api.nvim_get_current_line()
  local field = line:match("^%s+•%s+(.+)$")

  if not field then
    Log.notify(Const.SOQL.MESSAGES.FIELD_CURSOR_HINT, vim.log.levels.INFO)
    return
  end

  if not state.selected_fields[field] then
    return
  end

  if vim.tbl_contains(Const.SOQL.SYSTEM_FIELDS, field) then
    Log.notify(Const.SOQL.MESSAGES.SYSTEM_FIELD_PROTECTED, vim.log.levels.WARN)
    return
  end

  State.remove_fields(state, { field })
  Render.render(state)
end
--- Edit a subquery — picker when multiple, direct when one.
--- @param state table QueryState
local function edit_subquery(state)
  if #state.subqueries == 0 then
    return
  end

  if #state.subqueries == 1 then
    local sq = state.subqueries[1]
    if sq.bufnr and vim.api.nvim_buf_is_valid(sq.bufnr) then
      vim.api.nvim_set_current_buf(sq.bufnr)
    else
      M.create_builder_buffer(sq.sobject, true, state, sq.relationship_name, sq)
    end

    return
  end

  if not Snacks then
    return
  end

  local items = {}
  for i, sq in ipairs(state.subqueries) do
    table.insert(items, {
      text = (sq.relationship_name or "?") .. " (" .. sq.sobject .. ")",
      index = i,
      state = sq,
    })
  end

  local win = find_window_for_buf(state.bufnr)

  Snacks.picker({
    items = items,
    layout = { preset = "vscode" },
    format = function(item)
      return { { item.text } }
    end,
    confirm = function(picker, item)
      picker:close()

      if win and vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_set_current_win(win)
      end

      local sq = item.state

      if sq.bufnr and vim.api.nvim_buf_is_valid(sq.bufnr) then
        vim.api.nvim_set_current_buf(sq.bufnr)
      else
        M.create_builder_buffer(sq.sobject, true, state, sq.relationship_name, sq)
      end
    end,
  })
end

--- Open a floating editor showing the selected fields as a comma-separated string.
--- On save, parse by "," and add any field not already in state.selected_fields
--- (one-way, additive). The builder query is always recompiled from selected_fields,
--- so nothing here overrides it.
--- @param state table QueryState
local function edit_fields(state)
  local fields = vim.tbl_keys(state.selected_fields)
  table.sort(fields)
  local width = math.min(80, vim.o.columns - 4)
  local text_width = math.max(20, width - 4)
  local initial_lines = Render.wrap_comma_list(table.concat(fields, ", "), text_width, "")

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, initial_lines)

  local height = math.min(20, #initial_lines + 2)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "cursor",
    width = width,
    height = height,
    row = 1,
    col = 0,
    border = "single",
    style = "minimal",
  })

  local function save_and_close()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    State.merge_fields_from_string(state, table.concat(lines, "\n"))

    if win and vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end

    Render.render(state)
  end

  vim.keymap.set("n", "<C-s>", save_and_close, { buffer = buf, nowait = true, desc = "Save Fields" })
  vim.keymap.set("i", "<C-s>", save_and_close, { buffer = buf, nowait = true, desc = "Save Fields" })
  vim.keymap.set("n", "q", function()
    if win and vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end, { buffer = buf, nowait = true, desc = "Cancel edit" })
  vim.api.nvim_create_autocmd("WinClosed", {
    buffer = buf,
    once = true,
    callback = function()
      win = nil
    end,
  })
end

local function clear_fields(state)
  state.selected_fields = {}

  for _, f in ipairs(Const.SOQL.SYSTEM_FIELDS) do
    state.selected_fields[f] = true
  end
end

function M.create_builder_buffer(sobject_name, is_subquery, parent_state, relationship_name, existing_state)
  -- Create or reuse QueryState (bufnr nil—mutated after Snacks.win creates the buffer)
  local state = existing_state
    or State.QueryState:new({
      sobject = sobject_name,
      is_subquery = is_subquery or false,
      parent_state = parent_state or nil,
      relationship_name = relationship_name or nil,
    })

  if is_subquery and parent_state then
    local exists = false
    for _, sq in ipairs(parent_state.subqueries) do
      if sq == state then
        exists = true
        break
      end
    end

    if not exists then
      table.insert(parent_state.subqueries, state)
    end
  end

  local title
  if is_subquery then
    title = " Subquery — " .. (parent_state and parent_state.sobject or "?") .. " → " .. (relationship_name or "?")
  else
    title = " SOQL Builder — " .. sobject_name
  end

  local row, col

  if is_subquery and parent_state then
    local parent_win = find_window_for_buf(parent_state.bufnr)

    if parent_win and vim.api.nvim_win_is_valid(parent_win) then
      local parent_config = vim.api.nvim_win_get_config(parent_win)
      row = (parent_config.row or 0) + 3
      col = (parent_config.col or 0) + 4
    end
  end

  if not row then
    row = math.floor((vim.o.lines - math.max(math.floor(vim.o.lines * 0.75), 30)) / 2)
  end

  if not col then
    col = 4
  end

  local win = Snacks.win({
    title = " " .. title .. " ",
    title_pos = "center",
    position = "float",
    width = math.min(120, vim.o.columns - 4),
    height = math.max(math.floor(vim.o.lines * 0.75), 30),
    row = row,
    col = col,
    border = "single",
    ft = Const.SOQL.BUF_FILETYPE,
    bo = { filetype = Const.SOQL.BUF_FILETYPE },
    enter = true,
    footer_keys = { "q", "?", "s", "A" },
    text = function()
      return Render.render_lines(state)
    end,
    keys = {
      F = {
        desc = "Select Fields",
        function()
          open_field_picker(state)
        end,
      },
      R = {
        desc = "Add Related Field",
        function()
          if not is_subquery then
            add_related_field(state)
          end
        end,
      },
      W = {
        desc = "Add WHERE",
        function()
          add_where_condition(state)
        end,
      },
      S = {
        desc = "Add Subquery",
        function()
          if not is_subquery then
            add_subquery(state)
          end
        end,
      },
      X = {
        desc = "Clear Fields",
        function()
          clear_fields(state)
        end,
      },
      x = {
        desc = "Remove Fields",
        function()
          open_remove_picker(state)
        end,
      },
      L = {
        desc = "Set LIMIT",
        function()
          set_limit(state)
        end,
      },
      O = {
        desc = "Object / OFFSET",
        function()
          if is_subquery then
            set_offset(state)
          else
            switch_sobject(state)
          end
        end,
      },
      A = {
        desc = "Run Query",
        function()
          Executor.run_query(state)
        end,
      },
      C = {
        desc = "Copy SOQL",
        function()
          local soql = Compiler.compile(state)
          vim.fn.setreg("+", soql)
          vim.notify(Const.SOQL.MESSAGES.SOQL_COPIED, vim.log.levels.INFO)
        end,
      },
      E = {
        desc = "Edit Fields",
        function()
          edit_fields(state)
        end,
      },
      s = {
        desc = "Save Query",
        function(self)
          if not is_subquery then
            M.save_query(state, self)
          end
        end,
      },
      d = {
        desc = "Delete Item",
        function()
          delete_item_at_cursor(state)
        end,
      },
      D = {
        desc = "Delete Field",
        function()
          delete_field_at_cursor(state)
        end,
      },
      q = "close",
      rf = {
        desc = "Refresh Schema",
        function()
          Schema.refresh_describe(state.sobject, function(describe_data)
            if describe_data then
              describe_cache[state.sobject] = describe_data
            end
            win:update()
          end)
        end,
      },
      { "?", "toggle_help", desc = "help" },
      e = {
        desc = "Edit Subquery",
        function()
          if not is_subquery then
            edit_subquery(state)
          end
        end,
      },
      ["<BS>"] = {
        desc = "Save & Return",
        function(self)
          if is_subquery then
            state.subquery_saved = true
            self:close()
            if parent_state and parent_state.bufnr and vim.api.nvim_buf_is_valid(parent_state.bufnr) then
              local parent_win = find_window_for_buf(parent_state.bufnr)
              if parent_win and vim.api.nvim_win_is_valid(parent_win) then
                vim.api.nvim_set_current_win(parent_win)
              end
              Render.render(parent_state)
            end
          end
        end,
      },
      ["<Esc>"] = {
        desc = "Cancel",
        function()
          if is_subquery then
            win:close()
          end
        end,
      },
    },
    on_win = function(self)
      state.bufnr = self.buf
    end,
    on_close = function()
      if is_subquery and parent_state and not state.subquery_saved then
        for i, sq in ipairs(parent_state.subqueries) do
          if sq == state then
            table.remove(parent_state.subqueries, i)
            break
          end
        end
        if parent_state.bufnr and vim.api.nvim_buf_is_valid(parent_state.bufnr) then
          Render.render(parent_state)
        end
      end
    end,
  })

  -- For root, ensure describe data is available
  if not is_subquery then
    if not describe_cache[sobject_name] then
      Schema.fetch_describe(sobject_name, function(describe_data)
        if describe_data then
          describe_cache[sobject_name] = describe_data
          win:update()
        else
          Log.notify(string.format(Const.SOQL.MESSAGES.SCHEMA_LOAD_FAILED, sobject_name), vim.log.levels.ERROR)
          win:close()
        end
      end)
    end
  else
    if not describe_cache[sobject_name] and parent_state then
      Schema.fetch_describe(sobject_name, function(describe_data)
        if describe_data then
          describe_cache[sobject_name] = describe_data
        end
      end)
    end
  end
end

--- Main entry point: open the SOQL query builder.
--- Called from :Sf soql open.
function M.open()
  -- Guard: Snacks required
  if not Snacks then
    Log.notify(Const.SOQL.MESSAGES.SNACKS_REQUIRED_BUILDER, vim.log.levels.ERROR)
    return
  end

  -- Fetch SObject list
  Schema.fetch_sobjects(function(sobjects)
    if not sobjects or #sobjects == 0 then
      return
    end

    local items = {}
    for _, name in ipairs(sobjects) do
      table.insert(items, { text = name, api_name = name })
    end

    Snacks.picker({
      items = items,
      layout = { preset = "vscode" },
      format = function(item)
        return { { item.text } }
      end,
      confirm = function(picker, item)
        picker:close()
        M.create_builder_buffer(item.api_name, false, nil, nil)
      end,
    })
  end)
end

--- Save the current query to disk and close the builder.
--- Only works from the root query (not a subquery).
--- @param state table QueryState
--- @param win snacks.win
function M.save_query(state, win)
  if state.is_subquery then
    return
  end

  if not state.sobject or state.sobject == "" then
    Log.notify(Const.SOQL.MESSAGES.SAVE_NO_SOBJECT, vim.log.levels.ERROR)
    return
  end

  local config = Config:get_options()
  local saved_dir = PathUtils.join(config.cache_path, "soql", "saved")

  vim.fn.mkdir(saved_dir, "p")

  local soql = Compiler.compile(state)

  -- Generate filename with dedup suffix
  local base = PathUtils.join(saved_dir, state.sobject)
  local filepath = base .. ".soql"
  local counter = 1

  while vim.fn.filereadable(filepath) == 1 do
    counter = counter + 1
    local suffix = string.format("_%02d", counter)
    filepath = base .. suffix .. ".soql"
  end

  -- Write file (raw SOQL text for human readability)
  local f = io.open(filepath, "w")
  if not f then
    Log.notify(string.format("Failed to save query to %s", filepath), vim.log.levels.ERROR)
    return
  end

  f:write(soql)
  f:close()

  Log.notify(string.format(Const.SOQL.MESSAGES.SAVE_SUCCESS, vim.fn.fnamemodify(filepath, ":~:.")), vim.log.levels.INFO)
  win:close()
end

--- List saved .soql files and open a picker to resume one.
--- Reads the selected file and invokes the SOQL parser to reconstruct
--- a QueryState before opening the builder.
function M.resume()
  if not Snacks then
    Log.notify(Const.SOQL.MESSAGES.SNACKS_REQUIRED_BUILDER, vim.log.levels.ERROR)
    return
  end

  local config = Config:get_options()
  local saved_dir = PathUtils.join(config.cache_path, "soql", "saved")

  if vim.fn.isdirectory(saved_dir) == 0 then
    Log.notify(Const.SOQL.MESSAGES.NO_SAVED_QUERIES, vim.log.levels.INFO)
    return
  end

  -- Scan for *.soql files
  local files = vim.fn.glob(PathUtils.join(saved_dir, "*.soql"), false, true)
  if #files == 0 then
    Log.notify(Const.SOQL.MESSAGES.NO_SAVED_QUERIES, vim.log.levels.INFO)
    return
  end

  table.sort(files)

  local items = {}
  for _, fp in ipairs(files) do
    local basename = vim.fn.fnamemodify(fp, ":t")
    table.insert(items, { text = basename, path = fp })
  end

  Snacks.picker({
    items = items,
    layout = { preset = "vscode" },
    format = function(item)
      return { { item.text } }
    end,
    confirm = function(picker, item)
      picker:close()

      -- Read the saved query file
      local f = io.open(item.path, "r")
      if not f then
        Log.notify(Const.SOQL.MESSAGES.RESUME_PARSE_FAILED, vim.log.levels.ERROR)
        return
      end

      local raw = f:read("*a")
      f:close()

      local Parser = require("sf.soql.parser")
      local parsed = Parser.parse(raw)

      if not parsed or not parsed.sobject or parsed.sobject == "" then
        Log.notify(Const.SOQL.MESSAGES.RESUME_PARSE_FAILED, vim.log.levels.ERROR)
        return
      end

      -- Build a QueryState from parsed data
      local state = State.QueryState:new({ sobject = parsed.sobject })

      -- Merge parsed fields (keep SYSTEM_FIELDS from :new)
      for field, _ in pairs(parsed.selected_fields) do
        state.selected_fields[field] = true
      end

      state.where_clauses = parsed.where_clauses
      state.order_by = parsed.order_by
      state.limit = parsed.limit
      state.offset = parsed.offset

      -- Link subqueries to parent
      for _, sq in ipairs(parsed.subqueries) do
        sq.parent_state = state
        table.insert(state.subqueries, sq)
      end

      -- Open builder with the restored state
      M.create_builder_buffer(parsed.sobject, false, nil, nil, state)
    end,
  })
end

return M
