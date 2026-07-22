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
end)
