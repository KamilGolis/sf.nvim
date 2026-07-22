--- SOQL state engine unit tests
-- Tests QueryState construction and clause factory functions.

local helpers = dofile("tests/helpers.lua")
local eq = helpers.expect.equality
local expect = helpers.expect

describe("soql/state", function()
  local State

  before_each(function()
    State = require("sf.soql.state")
  end)

  it("QueryState:new() creates with default empty collections", function()
    local state = State.QueryState:new({ sobject = "Account" })
    eq(state.sobject, "Account")
    eq(state.is_subquery, false)
    eq(state.parent_state, nil)
    eq(state.relationship_name, nil)
    eq(#state.subqueries, 0)
    eq(#state.where_clauses, 0)
    eq(#state.order_by, 0)
    eq(state.limit, nil)
    eq(state.offset, nil)
  end)

  it("QueryState:new() pre-populates system fields", function()
    local state = State.QueryState:new({ sobject = "Account" })
    eq(state.selected_fields["Id"], true)
    eq(state.selected_fields["CreatedById"], true)
    eq(state.selected_fields["CreatedDate"], true)
    eq(state.selected_fields["LastModifiedById"], true)
    eq(state.selected_fields["LastModifiedDate"], true)
  end)

  it("QueryState:new() accepts override options", function()
    local parent = State.QueryState:new({ sobject = "Account" })
    local child = State.QueryState:new({
      sobject = "Contact",
      is_subquery = true,
      parent_state = parent,
      relationship_name = "Contacts",
      limit = 10,
    })
    eq(child.is_subquery, true)
    eq(child.parent_state, parent)
    eq(child.relationship_name, "Contacts")
    eq(child.limit, 10)
  end)

  it("QueryState:new() creates independent state objects", function()
    local s1 = State.QueryState:new({ sobject = "Account" })
    local s2 = State.QueryState:new({ sobject = "Contact" })
    eq(s1.sobject, "Account")
    eq(s2.sobject, "Contact")
    -- Modifying one should not affect the other
    s1.selected_fields["CustomField__c"] = true
    eq(s2.selected_fields["CustomField__c"], nil)
  end)

  it("new_where_condition creates correct structure", function()
    local wc = State.new_where_condition("Industry", "=", "Technology")
    eq(wc.field, "Industry")
    eq(wc.op, "=")
    eq(wc.value, "Technology")
  end)

  it("new_order_by_clause creates correct structure", function()
    local ob = State.new_order_by_clause("Name", "ASC", "FIRST")
    eq(ob.field, "Name")
    eq(ob.direction, "ASC")
    eq(ob.nulls, "FIRST")
  end)

  it("new_order_by_clause accepts nil nulls", function()
    local ob = State.new_order_by_clause("Name", "DESC", nil)
    eq(ob.field, "Name")
    eq(ob.direction, "DESC")
    eq(ob.nulls, nil)
  end)

  it("merge_fields_from_string adds only missing fields (additive, never removes)", function()
    local state = State.QueryState:new({ sobject = "Account" })
    -- system fields pre-populated; add two explicit fields
    State.merge_fields_from_string(state, "Name, Custom__c")
    eq(state.selected_fields["Name"], true)
    eq(state.selected_fields["Custom__c"], true)
    eq(state.selected_fields["Id"], true) -- system field retained

    -- re-adding an existing field is a no-op
    State.merge_fields_from_string(state, "Name")
    eq(state.selected_fields["Name"], true)

    -- whitespace + newline splitting, and additive-only: removing from the
    -- string does NOT remove from the set
    State.merge_fields_from_string(state, "Foo , Bar\nBaz")
    eq(state.selected_fields["Foo"], true)
    eq(state.selected_fields["Bar"], true)
    eq(state.selected_fields["Baz"], true)
    eq(state.selected_fields["Custom__c"], true) -- still present (not removed)
  end)

  it("remove_fields drops non-system fields and keeps system fields", function()
    local state = State.QueryState:new({ sobject = "Account" })
    State.merge_fields_from_string(state, "Name, Custom__c")
    eq(state.selected_fields["Name"], true)
    eq(state.selected_fields["Id"], true)

    local n = State.remove_fields(state, { "Name", "Id", "DoesNotExist" })
    eq(n, 1) -- only Name removed
    eq(state.selected_fields["Name"], nil)
    eq(state.selected_fields["Id"], true) -- system field kept
    eq(state.selected_fields["Custom__c"], true) -- untouched
  end)
end)
