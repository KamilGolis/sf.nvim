-- Smoke test: verify test infrastructure works.
-- Must be the first test to pass before any capability spec runs.

local helpers = dofile("tests/helpers.lua")
local eq = helpers.expect.equality
local expect = helpers.expect

describe("smoke", function()
  it("tests run and assertions work", function()
    eq(true, true)
    eq(1, 1)
    expect.no_equality(1, 2)
  end)

  it("test helpers module loads", function()
    local ok, helpers = pcall(require, "tests.helpers.init")
    eq(ok, true)
    expect.no_equality(helpers, nil)
    expect.no_equality(helpers.mock_vim, nil)
    expect.no_equality(helpers.mock_snacks, nil)
    expect.no_equality(helpers.mock_notify, nil)
    expect.no_equality(helpers.fixtures, nil)
  end)

  it("mock_vim setup and restore cycles cleanly", function()
    local mock = require("tests.helpers.mock_vim")
    mock.setup({ system = true, notify = true })
    expect.no_equality(vim.system, nil)
    -- vim.system should be our mock function
    local job = vim.system("sf", { "--version" }, { on_exit = function() end })
    expect.no_equality(job, nil)
    expect.no_equality(job.start, nil)
    expect.no_equality(job.result, nil)
    mock.restore()
    -- After restore, vim.system is back to original
    expect.no_equality(vim.system, nil)
  end)

  it("mock_snacks captures picker calls", function()
    local snacks = require("tests.helpers.mock_snacks")
    snacks.setup()
    Snacks.picker({ items = { { id = "1", text = "test" } }, confirm = function() end })
    local items = snacks.get_items()
    expect.no_equality(items, nil)
    eq(1, #items)
    eq("1", items[1].id)
    snacks.restore()
  end)

  it("mock_notify captures messages", function()
    local notify = require("tests.helpers.mock_notify")
    notify.setup()
    vim.notify("hello world", vim.log.levels.INFO)
    local calls = notify.get_messages()
    eq(1, #calls)
    eq("hello world", calls[1])
    notify.restore()
  end)

  it("fixtures loader returns nil for nonexistent file", function()
    local f = require("tests.helpers.fixtures")
    local content, err = f.load_text("core-utilities", "nonexistent.json")
    eq(content, nil)
    expect.no_equality(err, nil)
  end)
end)
