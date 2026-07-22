--- SOQL compiler unit tests
-- Tests the QueryState → SOQL compilation logic.

local helpers = dofile("tests/helpers.lua")
local eq = helpers.expect.equality
local expect = helpers.expect
local has_match = helpers.expect.match

describe("soql/compiler", function()
  local State

  before_each(function()
    State = require("sf.soql.state")
  end)

  it("empty fields fallback to SELECT Id", function()
    local state = State.QueryState:new({ sobject = "Account" })
    state.selected_fields = {}
    local Compiler = require("sf.soql.compiler")
    local result = Compiler.compile(state)
    eq("SELECT Id\nFROM Account", result)
  end)

  it("single field produces SELECT and FROM", function()
    local state = State.QueryState:new({ sobject = "Account" })
    state.selected_fields = { Id = true }
    local Compiler = require("sf.soql.compiler")
    local result = Compiler.compile(state)
    has_match(result, "SELECT Id")
    has_match(result, "FROM Account")
  end)

  it("multiple fields produces comma-separated SELECT with sorted fields", function()
    local state = State.QueryState:new({ sobject = "Account" })
    state.selected_fields = { Id = true, Name = true, Industry = true }
    local Compiler = require("sf.soql.compiler")
    local result = Compiler.compile(state)
    has_match(result, "SELECT Id, Industry, Name")
    has_match(result, "FROM Account")
  end)

  it("WHERE condition quotes string values", function()
    local state = State.QueryState:new({ sobject = "Account" })
    state.selected_fields = { Id = true, Name = true }
    state.where_clauses = { State.new_where_condition("Industry", "=", "Technology") }
    local Compiler = require("sf.soql.compiler")
    local result = Compiler.compile(state)
    has_match(result, "WHERE Industry = 'Technology'")
  end)

  it("WHERE condition does not quote numeric values", function()
    local state = State.QueryState:new({ sobject = "Account" })
    state.selected_fields = { Id = true }
    state.where_clauses = { State.new_where_condition("Age", ">", "30") }
    local Compiler = require("sf.soql.compiler")
    local result = Compiler.compile(state)
    has_match(result, "WHERE Age > 30")
    eq(result:find("'30'"), nil) -- no quotes
  end)

  it("WHERE condition does not quote boolean values", function()
    local state = State.QueryState:new({ sobject = "Contact" })
    state.selected_fields = { Id = true }
    state.where_clauses = { State.new_where_condition("IsActive", "=", "true") }
    local Compiler = require("sf.soql.compiler")
    local result = Compiler.compile(state)
    has_match(result, "WHERE IsActive = true")
  end)

  it("multiple WHERE conditions joined with AND", function()
    local state = State.QueryState:new({ sobject = "Account" })
    state.selected_fields = { Id = true }
    state.where_clauses = {
      State.new_where_condition("Industry", "=", "Technology"),
      State.new_where_condition("Type", "=", "Partner"),
    }
    local Compiler = require("sf.soql.compiler")
    local result = Compiler.compile(state)
    has_match(result, "Industry = 'Technology'")
    has_match(result, "Type = 'Partner'")
    has_match(result, "AND")
  end)

  it("ORDER BY produces ORDER BY clause", function()
    local state = State.QueryState:new({ sobject = "Account" })
    state.selected_fields = { Id = true }
    state.order_by = { State.new_order_by_clause("Name", "ASC") }
    local Compiler = require("sf.soql.compiler")
    local result = Compiler.compile(state)
    has_match(result, "ORDER BY Name ASC")
  end)

  it("multiple ORDER BY clauses", function()
    local state = State.QueryState:new({ sobject = "Account" })
    state.selected_fields = { Id = true }
    state.order_by = {
      State.new_order_by_clause("Name", "ASC"),
      State.new_order_by_clause("Industry", "DESC"),
    }
    local Compiler = require("sf.soql.compiler")
    local result = Compiler.compile(state)
    has_match(result, "ORDER BY Name ASC, Industry DESC")
  end)

  it("LIMIT and OFFSET produce clauses", function()
    local state = State.QueryState:new({ sobject = "Account" })
    state.selected_fields = { Id = true }
    state.limit = 10
    state.offset = 5
    local Compiler = require("sf.soql.compiler")
    local result = Compiler.compile(state)
    has_match(result, "LIMIT 10")
    has_match(result, "OFFSET 5")
  end)

  it("subquery is inlined in parentheses under SELECT", function()
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

    local Compiler = require("sf.soql.compiler")
    local result = Compiler.compile(parent)
    has_match(result, "SELECT Id, Name, %(SELECT Email, Id")
    has_match(result, "FROM Contacts")
    has_match(result, "FROM Account")
  end)


  it("clause ordering is: SELECT FROM WHERE ORDER BY LIMIT OFFSET", function()
    local state = State.QueryState:new({ sobject = "Account" })
    state.selected_fields = { Id = true }
    state.where_clauses = { State.new_where_condition("Industry", "=", "Tech") }
    state.order_by = { State.new_order_by_clause("Name", "ASC") }
    state.limit = 10
    state.offset = 5
    local Compiler = require("sf.soql.compiler")
    local result = Compiler.compile(state)

    local select_pos = result:find("SELECT")
    local from_pos = result:find("FROM")
    local where_pos = result:find("WHERE")
    local order_pos = result:find("ORDER BY")
    local limit_pos = result:find("LIMIT")
    local offset_pos = result:find("OFFSET")

    eq(select_pos ~= nil, true)
    eq(from_pos > select_pos, true)
    eq(where_pos > from_pos, true)
    eq(order_pos > where_pos, true)
    eq(limit_pos > order_pos, true)
    eq(offset_pos > limit_pos, true)
  end)
end)
