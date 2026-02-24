--- sf-nvim test results buffer module
-- @license MIT

local PathUtils = require("sf.core.path_utils")
local Utils = require("sf.core.utils")

local TestResultsBuffer = {}

--- Parse a stack trace line to extract class name, method name, and line number
--- @param stack_line string The stack trace line to parse
--- @return string|nil class_name The class name if found
--- @return string|nil method_name The method name if found  
--- @return number|nil line_number The line number if found
function TestResultsBuffer.parse_stack_trace_line(stack_line)
  -- Pattern for: Class.ClassName.methodName: line 77, column 1
  local class_name, method_name, line_number = stack_line:match("Class%.([^%.]+)%.([^:]+):%s*line%s*(%d+)")
  if class_name and method_name and line_number then
    return class_name, method_name, tonumber(line_number)
  end
  
  -- Pattern for: ClassName.methodName: line 77, column 1 (without "Class." prefix)
  class_name, method_name, line_number = stack_line:match("([^%.]+)%.([^:]+):%s*line%s*(%d+)")
  if class_name and method_name and line_number then
    return class_name, method_name, tonumber(line_number)
  end
  
  -- Pattern for: ClassName: line 77, column 1 (class level error)
  class_name, line_number = stack_line:match("([^:]+):%s*line%s*(%d+)")
  if class_name and line_number then
    return class_name, nil, tonumber(line_number)
  end
  
  return nil, nil, nil
end

--- Create and display test results in a dedicated buffer
--- @param test_results table The parsed test results from SF CLI
--- @param test_name string The name of the test that was executed
function TestResultsBuffer.show_results(test_results, test_name)
  if not test_results or not test_results.result then
    vim.notify("No test results to display", vim.log.levels.ERROR)
    return
  end

  local summary = test_results.result.summary
  local tests = test_results.result.tests or {}

  -- Create or reuse existing buffer
  local buf_name = "SF Test Results"
  local existing_buf = vim.fn.bufnr(buf_name)
  local buf

  if existing_buf ~= -1 then
    buf = existing_buf
  else
    buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, buf_name)
  end

  -- Set buffer options
  vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
  vim.api.nvim_buf_set_option(buf, "swapfile", false)
  vim.api.nvim_buf_set_option(buf, "modifiable", true)
  vim.api.nvim_buf_set_option(buf, "readonly", false)

  -- Generate buffer content
  local lines = {}
  local test_line_map = {} -- Maps line numbers to test information

  -- Header
  table.insert(lines, "═══════════════════════════════════════════════════════════════")
  table.insert(lines, "                        SF TEST RESULTS")
  table.insert(lines, "═══════════════════════════════════════════════════════════════")
  table.insert(lines, "")

  -- Test execution info
  table.insert(lines, "Test Execution: " .. test_name)
  if summary.testStartTime then
    table.insert(lines, "Start Time: " .. summary.testStartTime)
  end
  if summary.testExecutionTime then
    table.insert(lines, "Execution Time: " .. summary.testExecutionTime)
  end
  table.insert(lines, "")

  -- Summary section
  table.insert(lines, "SUMMARY")
  table.insert(lines, "───────────────────────────────────────────────────────────────")
  table.insert(lines, string.format("Outcome: %s", summary.outcome or "Unknown"))
  table.insert(lines, string.format("Tests Run: %d", summary.testsRan or 0))
  table.insert(lines, string.format("Passed: %d (%s)", summary.passing or 0, summary.passRate or "0%"))
  table.insert(lines, string.format("Failed: %d (%s)", summary.failing or 0, summary.failRate or "0%"))
  table.insert(lines, string.format("Skipped: %d", summary.skipped or 0))
  table.insert(lines, "")

  -- Individual test results
  if #tests > 0 then
    table.insert(lines, "TEST DETAILS")
    table.insert(lines, "───────────────────────────────────────────────────────────────")
    table.insert(lines, "")

    for i, test in ipairs(tests) do
      local line_start = #lines + 1
      local test_name_line = line_start

      -- Test header
      local status_icon = test.Outcome == "Pass" and "✓" or "✗"
      local test_full_name = test.FullName or (test.ApexClass and test.ApexClass.Name .. "." .. test.MethodName) or test.MethodName or "Unknown"
      
      table.insert(lines, string.format("%s %s", status_icon, test_full_name))
      
      -- Store test information for navigation
      test_line_map[test_name_line] = {
        class_name = test.ApexClass and test.ApexClass.Name or nil,
        method_name = test.MethodName,
        full_name = test_full_name
      }

      -- Test details
      if test.RunTime then
        table.insert(lines, string.format("   Runtime: %d ms", test.RunTime))
      end

      -- Show failure details if test failed
      if test.Outcome == "Fail" then
        if test.Message then
          table.insert(lines, "   Error Message:")
          -- Split message into multiple lines if needed
          local message_lines = vim.split(test.Message, "\n")
          for _, msg_line in ipairs(message_lines) do
            table.insert(lines, "     " .. msg_line)
          end
        end

        if test.StackTrace then
          table.insert(lines, "   Stack Trace:")
          -- Split stack trace into multiple lines
          local stack_lines = vim.split(test.StackTrace, "\n")
          for _, stack_line in ipairs(stack_lines) do
            local line_num = #lines + 1
            table.insert(lines, "     " .. stack_line)
            
            -- Check if this stack trace line contains line number information
            local class_name, method_name, line_number = TestResultsBuffer.parse_stack_trace_line(stack_line)
            if class_name and line_number then
              test_line_map[line_num] = {
                class_name = class_name,
                method_name = method_name,
                line_number = line_number,
                is_stack_trace = true
              }
            end
          end
        end
      end

      table.insert(lines, "")
    end
  end

  -- Footer
  table.insert(lines, "───────────────────────────────────────────────────────────────")
  table.insert(lines, "Press 'gf' or <Enter> on test names to open source files")
  table.insert(lines, "Press 'gf' or <Enter> on stack trace lines to jump to specific line numbers")
  table.insert(lines, "Press 'q' to close this buffer")

  -- Set buffer content
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  -- Make buffer read-only
  vim.api.nvim_buf_set_option(buf, "modifiable", false)
  vim.api.nvim_buf_set_option(buf, "readonly", true)

  -- Set up buffer-local keymaps
  TestResultsBuffer.setup_keymaps(buf, test_line_map)

  -- Open buffer in a new window
  TestResultsBuffer.open_results_window(buf)

  -- Set syntax highlighting
  TestResultsBuffer.setup_syntax(buf)
end

--- Setup buffer-local keymaps for navigation
--- @param buf number The buffer number
--- @param test_line_map table Map of line numbers to test information
function TestResultsBuffer.setup_keymaps(buf, test_line_map)
  -- Close buffer with 'q'
  vim.api.nvim_buf_set_keymap(buf, "n", "q", ":bdelete<CR>", {
    noremap = true,
    silent = true,
    desc = "Close test results buffer"
  })

  -- Navigate to test source with 'gf' or <CR>
  local function goto_test_source()
    local line_num = vim.api.nvim_win_get_cursor(0)[1]
    local test_info = test_line_map[line_num]
    
    if test_info and test_info.class_name then
      if test_info.is_stack_trace and test_info.line_number then
        -- Navigate to specific line from stack trace
        TestResultsBuffer.open_test_source(test_info.class_name, test_info.method_name, test_info.line_number)
      else
        -- Navigate to method definition
        TestResultsBuffer.open_test_source(test_info.class_name, test_info.method_name)
      end
    end
  end

  vim.api.nvim_buf_set_keymap(buf, "n", "gf", "", {
    noremap = true,
    silent = true,
    callback = goto_test_source,
    desc = "Go to test source file"
  })

  vim.api.nvim_buf_set_keymap(buf, "n", "<CR>", "", {
    noremap = true,
    silent = true,
    callback = goto_test_source,
    desc = "Go to test source file"
  })
end

--- Open the test source file and navigate to the method or line number
--- @param class_name string The name of the test class
--- @param method_name string|nil The name of the test method (optional)
--- @param line_number number|nil The specific line number to navigate to (optional)
function TestResultsBuffer.open_test_source(class_name, method_name, line_number)
  if not class_name then
    vim.notify("No class name available", vim.log.levels.WARN)
    return
  end

  -- Close the results buffer first to avoid split view
  local current_buf = vim.api.nvim_get_current_buf()
  local buf_name = vim.api.nvim_buf_get_name(current_buf)
  if buf_name:match("SF Test Results") then
    vim.cmd("bdelete")
  end

  -- Try to find the class file
  local sf_root = Utils.get_sf_root()
  local possible_paths = {
    PathUtils.join(sf_root, "force-app", "main", "default", "classes", class_name .. ".cls"),
    PathUtils.join(sf_root, "src", "classes", class_name .. ".cls"),
  }

  -- Check default package path from sfdx-project.json
  local default_path = Utils.get_default_package_path()
  if default_path then
    table.insert(possible_paths, 1, PathUtils.join(sf_root .. default_path, "classes", class_name .. ".cls"))
  end

  local class_file = nil
  for _, path in ipairs(possible_paths) do
    if vim.fn.filereadable(path) == 1 then
      class_file = path
      break
    end
  end

  if not class_file then
    vim.notify("Could not find class file: " .. class_name .. ".cls", vim.log.levels.ERROR)
    return
  end

  -- Open the file
  vim.cmd("edit " .. vim.fn.fnameescape(class_file))

  -- Navigate to specific line number if provided (from stack trace)
  if line_number then
    vim.cmd("normal! " .. line_number .. "G")
    vim.cmd("normal! zz") -- Center the line
    return
  end

  -- Navigate to method if specified
  if method_name then
    -- Search for the method definition
    local method_patterns = {
      "\\v(public|private|protected|global)\\s+(static\\s+)?(testMethod\\s+)?\\w*\\s*" .. method_name .. "\\s*\\(",
      "\\v@isTest.*\\n.*" .. method_name .. "\\s*\\(",
      "\\v" .. method_name .. "\\s*\\("
    }

    for _, pattern in ipairs(method_patterns) do
      if vim.fn.search(pattern, "w") > 0 then
        vim.cmd("normal! zz") -- Center the line
        break
      end
    end
  end
end

--- Open the results buffer in an appropriate window
--- @param buf number The buffer number
function TestResultsBuffer.open_results_window(buf)
  -- Check if buffer is already visible
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == buf then
      vim.api.nvim_set_current_win(win)
      return
    end
  end

  -- Open in a new split
  vim.cmd("split")
  vim.api.nvim_win_set_buf(0, buf)
  
  -- Resize window to show content better
  local lines = vim.api.nvim_buf_line_count(buf)
  local max_height = math.floor(vim.o.lines * 0.6)
  local height = math.min(lines + 2, max_height)
  vim.api.nvim_win_set_height(0, height)
end

--- Setup syntax highlighting for the results buffer
--- @param buf number The buffer number
function TestResultsBuffer.setup_syntax(buf)
  vim.api.nvim_buf_call(buf, function()
    -- Define syntax groups
    vim.cmd([[
      syntax clear
      syntax match TestResultsHeader /^═.*═$/
      syntax match TestResultsTitle /^\s*SF TEST RESULTS\s*$/
      syntax match TestResultsSection /^[A-Z ]\+$/
      syntax match TestResultsSeparator /^───.*───$/
      syntax match TestResultsPass /^✓.*$/
      syntax match TestResultsFail /^✗.*$/
      syntax match TestResultsLabel /^\w\+:/
      syntax match TestResultsError /^\s\+Error Message:$/
      syntax match TestResultsStack /^\s\+Stack Trace:$/
      syntax match TestResultsStackLine /^\s\+.*line\s\+\d\+.*$/
      syntax match TestResultsFooter /^Press.*$/
      
      highlight link TestResultsHeader Title
      highlight link TestResultsTitle Title
      highlight link TestResultsSection Identifier
      highlight link TestResultsSeparator Comment
      highlight link TestResultsPass DiffAdd
      highlight link TestResultsFail DiffDelete
      highlight link TestResultsLabel Label
      highlight link TestResultsError ErrorMsg
      highlight link TestResultsStack WarningMsg
      highlight link TestResultsStackLine Underlined
      highlight link TestResultsFooter Comment
    ]])
  end)
end

return TestResultsBuffer