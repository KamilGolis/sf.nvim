--- SOQL render helper unit tests
-- Tests wrap_comma_list and display_width logic.

local helpers = dofile("tests/helpers.lua")
local eq = helpers.expect.equality

describe("soql/render", function()
  local Render

  before_each(function()
    Render = require("sf.soql.render")
  end)

  it("wrap_comma_list keeps each line within width and round-trips", function()
    local text = "Name, Id, CustomField__c, OwnerId, CreatedDate"
    local out = Render.wrap_comma_list(text, 12, "")
    -- no output line exceeds the budget (single items longer than budget are allowed)
    for _, l in ipairs(out) do
      if l:find(", ") then
        -- composite line (has comma) must fit
        eq(#l <= 12 or false, true, "line [" .. l .. "] exceeds " .. 12)
      end
    end
    -- rejoining with ", " reproduces the original (proves save-time parsing is intact)
    eq(table.concat(out, ", "), text)
  end)

  it("wrap_comma_list indents continuation lines and preserves SELECT", function()
    local out = Render.wrap_comma_list("SELECT Alpha, Bravo, Charlie", 14, "  ")
    eq(out[1]:find("^SELECT Alpha"), 1, "first line keeps SELECT + first field")
    local found = false
    for _, l in ipairs(out) do
      if l:find("^  Bravo") or l:find("^  Charlie") then
        found = true
      end
    end
    eq(found, true, "at least one field is on an indented continuation")
  end)

  it("render_lines ORDER BY lines carry N. prefix", function()
    local State = require("sf.soql.state")
    local state = State.QueryState:new({ sobject = "Account" })
    state.bufnr = 9999 -- no window, falls back to display_width default
    state.order_by = {
      State.new_order_by_clause("Name", "ASC"),
      State.new_order_by_clause("Industry", "DESC"),
    }
    local lines = Render.render_lines(state)
    local found_idx = false
    local found_ob = false
    for _, l in ipairs(lines) do
      if l:match("^%s+1%.%s+Name ASC") then found_idx = true end
      if l:match("^%s+2%.%s+Industry DESC") then found_ob = true end
    end
    eq(found_idx, true, "first ORDER BY must have 1. prefix")
    eq(found_ob, true, "second ORDER BY must have 2. prefix")
  end)

  it("render_lines shows subqueries as numbered compiled strings", function()
    local State = require("sf.soql.state")
    local Compiler = require("sf.soql.compiler")
    local state = State.QueryState:new({ sobject = "Account" })
    state.bufnr = 9999
    state.selected_fields = { Id = true, Name = true }
    local child = State.QueryState:new({
      sobject = "Contact",
      is_subquery = true,
      parent_state = state,
      relationship_name = "Contacts",
    })
    child.selected_fields = { Id = true, Email = true }
    state.subqueries = { child }
    local lines = Render.render_lines(state)
    local found = false
    for _, l in ipairs(lines) do
      if l:match("^%s+1%.%s+%(") and l:find("FROM Contacts") then
        found = true
      end
    end
    eq(found, true, "subquery line must be '1. (SELECT ... FROM Contacts)'")
  end)

  it("render_lines includes keybind hints for fields, where, and order by", function()
    local State = require("sf.soql.state")
    local state = State.QueryState:new({ sobject = "Account" })
    state.bufnr = 9999
    state.selected_fields = { Id = true }
    local lines = Render.render_lines(state)
    local has_f = false
    local has_w = false
    local has_b = false
    for _, l in ipairs(lines) do
      if l:find("%[F%] Select Fields") then has_f = true end
      if l:find("%[W%] Add WHERE") then has_w = true end
      if l:find("%[B%] Add ORDER BY") then has_b = true end
    end
    eq(has_f, true, "[F] Select Fields hint missing")
    eq(has_w, true, "[W] Add WHERE hint missing")
    eq(has_b, true, "[B] Add Order By hint missing")
  end)
end)
