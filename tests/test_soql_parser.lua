--- SOQL parser unit tests
-- Tests the compiled-SOQL → QueryState reconstruction logic.

local helpers = dofile("tests/helpers.lua")
local eq = helpers.expect.equality
local expect = helpers.expect
local has_match = helpers.expect.match

describe("soql/parser", function()
  local State
  local Compiler
  local Parser

  before_each(function()
    State = require("sf.soql.state")
    Compiler = require("sf.soql.compiler")
    Parser = require("sf.soql.parser")
  end)

  it("parses SELECT and FROM from simple query", function()
    local parsed = Parser.parse("SELECT Id\nFROM Account")

    eq(parsed ~= nil, true)
    eq(parsed.sobject, "Account")
    eq(parsed.selected_fields["Id"], true)
  end)

  it("parses multiple fields", function()
    local parsed = Parser.parse("SELECT Id, Name, Industry\nFROM Account")

    eq(parsed.selected_fields["Id"], true)
    eq(parsed.selected_fields["Name"], true)
    eq(parsed.selected_fields["Industry"], true)
  end)

  it("parses WHERE conditions", function()
    local parsed = Parser.parse("SELECT Id\nFROM Account\nWHERE Industry = 'Technology'")

    eq(#parsed.where_clauses, 1)
    eq(parsed.where_clauses[1].field, "Industry")
    eq(parsed.where_clauses[1].op, "=")
    eq(parsed.where_clauses[1].value, "Technology")
  end)

  it("parses ORDER BY with direction", function()
    local parsed = Parser.parse("SELECT Id\nFROM Account\nORDER BY Name ASC")

    eq(#parsed.order_by, 1)
    eq(parsed.order_by[1].field, "Name")
    eq(parsed.order_by[1].direction, "ASC")
  end)

  it("parses LIMIT and OFFSET", function()
    local parsed = Parser.parse("SELECT Id\nFROM Account\nLIMIT 10\nOFFSET 5")

    eq(parsed.limit, 10)
    eq(parsed.offset, 5)
  end)

  it("round-trips a complete QueryState", function()
    local state = State.QueryState:new({ sobject = "Account" })
    state.selected_fields = { Id = true, Name = true, Industry = true }
    state.where_clauses = { State.new_where_condition("Industry", "=", "Technology") }
    state.order_by = { State.new_order_by_clause("Name", "ASC") }
    state.limit = 10
    state.offset = 5

    local soql = Compiler.compile(state)
    local parsed = Parser.parse(soql)

    eq(parsed.sobject, "Account")
    eq(parsed.selected_fields["Id"], true)
    eq(parsed.selected_fields["Name"], true)
    eq(parsed.selected_fields["Industry"], true)
    eq(#parsed.where_clauses, 1)
    eq(parsed.where_clauses[1].field, "Industry")
    eq(parsed.where_clauses[1].op, "=")
    eq(parsed.where_clauses[1].value, "Technology")
    eq(#parsed.order_by, 1)
    eq(parsed.order_by[1].field, "Name")
    eq(parsed.order_by[1].direction, "ASC")
    eq(parsed.limit, 10)
    eq(parsed.offset, 5)
  end)

  it("round-trips subqueries (regression guard: in_subquery flag)", function()
    local parent = State.QueryState:new({ sobject = "Account" })
    parent.selected_fields = { Id = true, Name = true }

    local child = State.QueryState:new({
      sobject = "Contact",
      is_subquery = true,
      parent_state = parent,
      relationship_name = "Contacts",
    })
    child.selected_fields = { Id = true, Email = true }
    child.where_clauses = { State.new_where_condition("IsActive", "=", "true") }
    child.limit = 10
    parent.subqueries = { child }

    local soql = Compiler.compile(parent)
    local parsed = Parser.parse(soql)

    eq(#parsed.subqueries, 1)
    -- The compiler uses relationship_name in FROM for subqueries,
    -- so the parser recovers it as sobject.
    eq(parsed.subqueries[1].sobject, "Contacts")
    eq(parsed.subqueries[1].is_subquery, true)
    eq(parsed.subqueries[1].selected_fields["Id"], true)
    eq(parsed.subqueries[1].selected_fields["Email"], true)
    eq(#parsed.subqueries[1].where_clauses, 1)
    eq(parsed.subqueries[1].where_clauses[1].value, "true")
    eq(parsed.subqueries[1].limit, 10)
  end)

  it("parses single-line query via normalize_multiline", function()
    local parsed = Parser.parse("SELECT Id FROM Account WHERE Name = 'Test'")

    eq(parsed.sobject, "Account")
    eq(parsed.selected_fields["Id"], true)
    eq(#parsed.where_clauses, 1)
    eq(parsed.where_clauses[1].field, "Name")
    eq(parsed.where_clauses[1].value, "Test")
  end)

  it("parses single-line query with ORDER BY and LIMIT", function()
    local parsed = Parser.parse("SELECT Id, Name FROM Account ORDER BY Name ASC LIMIT 10")

    eq(parsed.sobject, "Account")
    eq(#parsed.order_by, 1)
    eq(parsed.order_by[1].field, "Name")
    eq(parsed.order_by[1].direction, "ASC")
    eq(parsed.limit, 10)
  end)

  it("returns nil for empty input", function()
    eq(Parser.parse(""), nil)
    eq(Parser.parse(nil), nil)
  end)
end)
