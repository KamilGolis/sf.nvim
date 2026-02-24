--- sf-nvim test runner module
-- @license MIT

local Job = require("plenary.job")
local Snacks = require("snacks")

local Process = require("sf.core.process")
local Const = require("sf.const")
local Connector = require("sf.org.connect")
local TestResultsBuffer = require("sf.test.results_buffer")

local TestRunner = {}

--- Get the current cursor position and buffer content for treesitter analysis
--- @return table|nil The treesitter node at cursor position
local function get_node_at_cursor()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row, col = cursor[1] - 1, cursor[2]

  local parser = vim.treesitter.get_parser(bufnr, "apex")
  if not parser then
    return nil
  end

  local tree = parser:parse()[1]
  local root = tree:root()

  return root:named_descendant_for_range(row, col, row, col)
end

--- Find the class name from treesitter node
--- @param node table The treesitter node to analyze
--- @return string|nil The class name if found
local function find_class_name(node)
  while node do
    if node:type() == "class_declaration" then
      -- Look for the class name identifier
      for child in node:iter_children() do
        if child:type() == "identifier" then
          local class_name = vim.treesitter.get_node_text(child, 0)
          return class_name
        end
      end
    end
    node = node:parent()
  end
  return nil
end

--- Find the method name from treesitter node
--- @param node table The treesitter node to analyze
--- @return string|nil The method name if found
local function find_method_name(node)
  while node do
    if node:type() == "method_declaration" then
      -- Look for the method name identifier
      for child in node:iter_children() do
        if child:type() == "identifier" then
          local method_name = vim.treesitter.get_node_text(child, 0)
          return method_name
        end
      end
    end
    node = node:parent()
  end
  return nil
end

--- Check if current file is an Apex test class
--- @return boolean True if current file is a test class
local function is_test_class()
  local bufnr = vim.api.nvim_get_current_buf()
  local parser = vim.treesitter.get_parser(bufnr, "apex")
  if not parser then
    return false
  end

  local tree = parser:parse()[1]
  local root = tree:root()

  -- Look for @isTest annotation or testMethod keyword
  local query = vim.treesitter.query.parse(
    "apex",
    [[
    (annotation
      name: (identifier) @annotation_name
      (#eq? @annotation_name "isTest"))

    (annotation
      name: (identifier) @annotation_name
      (#eq? @annotation_name "IsTest"))

    (modifiers
      (modifier) @modifier
      (#eq? @modifier "testMethod"))
  ]]
  )

  for _, _ in query:iter_captures(root, bufnr) do
    return true
  end

  return false
end

--- Create test result file path
--- @return string The path to store test results
local function get_test_result_path()
  local config = require("sf.config")
  return config:get_options().test_results_file
end

--- @return string The path to store coverage results
local function get_coverage_result_path()
  local config = require("sf.config")
  return config:get_options().coverage_results_file
end

--- Parse and display test results from JSON output
--- @param json_output string The JSON output from SF CLI
--- @param test_name string The name of the test being executed
--- @return boolean True if tests passed, false if failed
local function process_test_results(json_output, test_name)
  deb("Test results JSON output:", json_output)
  
  local ok, result = pcall(vim.json.decode, json_output)

  if not ok then
    deb("Failed to parse test results JSON")
    vim.notify("Failed to parse test results", vim.log.levels.ERROR)
    return false
  end
  
  deb("Test Results parsed:", result)

  if not result or not result.result then
    deb("Failed to parse test results: invalid result structure")
    vim.notify("Failed to parse test results", vim.log.levels.ERROR)
    return false
  end

  local summary = result.result.summary
  if not summary then
    vim.notify("No test summary found in results", vim.log.levels.ERROR)
    deb("No test summary found in results")
    return false
  end

  -- Show results in dedicated buffer instead of notifications
  TestResultsBuffer.show_results(result, test_name)

  -- Return whether tests passed
  return summary.failing == nil or summary.failing == 0
end

--- Run Apex tests for a specific class
--- @param class_name string The name of the test class to run
--- @param options table|nil Additional options
function TestRunner.run_class_tests(class_name, options)
  Connector:check_cli(function()
    options = options or {}

    if not class_name then
      vim.notify("No test class name provided", vim.log.levels.ERROR)
      return
    end

    local handle = Process.create_progress_handle({ title = "Running tests for " .. class_name })
    handle:report({ message = "Starting test execution...", percentage = 0 })

    local sf_cli_path = options.sf_cli_path or "sf"
    local result_file = get_test_result_path()

    -- Ensure the directory exists
    local result_dir = vim.fn.fnamemodify(result_file, ":h")
    vim.fn.mkdir(result_dir, "p")

    local args = Const.get_apex_test_class_args(class_name)

    local job = Job:new({
      command = sf_cli_path,
      args = args,
      on_start = function()
        handle:report({ message = "Executing tests...", percentage = 50 })
      end,
      on_exit = function(j, return_val)
        vim.schedule(function()
          local stdout = j:result()
          local json_output = table.concat(stdout, "\n")

          deb("Test Results Job output JSON", json_output)

          -- Always write results to file, regardless of return code
          local file = io.open(result_file, "w")
          if file then
            file:write(json_output)
            file:close()
          end

          if (return_val == 0 or return_val == 100) and json_output and json_output ~= "" then
            -- SF CLI executed successfully (0 = passing tests, 100 = failing tests)
            handle:report({ message = "Processing test results...", percentage = 90 })

            local tests_passed = process_test_results(json_output, class_name)
            local final_message = tests_passed and "Tests completed successfully" or "Tests completed with failures"

            handle:report({ message = final_message, percentage = 100 })
            vim.notify("Test execution completed for class: " .. class_name, vim.log.levels.INFO)
          else
            -- SF CLI execution failed (actual CLI error, not test failure)
            handle:report({ message = "Test execution failed", percentage = 100 })
            vim.notify("Failed to execute tests for class: " .. class_name, vim.log.levels.ERROR)

            local stderr = j:stderr_result()
            deb("Test execution error", { stderr = stderr, return_val = return_val, stdout = stdout })
            
            if options.debug then
              if stderr and #stderr > 0 then
                deb("Test execution stderr (debug mode)", { stderr = stderr, return_val = return_val })
              end
            end
          end
          handle:finish()
        end)
      end,
    })

    job:start()
  end)
end

--- Run Apex test for a specific method
--- @param class_name string The name of the test class
--- @param method_name string The name of the test method
--- @param options table|nil Additional options
function TestRunner.run_method_test(class_name, method_name, options)
  Connector:check_cli(function()
    options = options or {}

    if not class_name or not method_name then
      vim.notify("Class name and method name are required", vim.log.levels.ERROR)
      return
    end

    local test_name = class_name .. "." .. method_name
    local handle = Process.create_progress_handle({ title = "Running test: " .. test_name })
    handle:report({ message = "Starting test execution...", percentage = 0 })

    local sf_cli_path = options.sf_cli_path or "sf"
    local result_file = get_test_result_path()

    -- Ensure the directory exists
    local result_dir = vim.fn.fnamemodify(result_file, ":h")
    vim.fn.mkdir(result_dir, "p")

    local args = Const.get_apex_test_method_args(test_name)

    local job = Job:new({
      command = sf_cli_path,
      args = args,
      on_start = function()
        handle:report({ message = "Executing test method...", percentage = 50 })
      end,
      on_exit = function(j, return_val)
        vim.schedule(function()
          local stdout = j:result()
          local json_output = table.concat(stdout, "\n")

          deb("Test Results Job output JSON", json_output)

          -- Always write results to file, regardless of return code
          local file = io.open(result_file, "w")
          if file then
            file:write(json_output)
            file:close()
          end

          if (return_val == 0 or return_val == 100) and json_output and json_output ~= "" then
            -- SF CLI executed successfully (0 = passing tests, 100 = failing tests)
            handle:report({ message = "Processing test results...", percentage = 90 })

            local tests_passed = process_test_results(json_output, test_name)
            local final_message = tests_passed and "Test completed successfully" or "Test completed with failures"

            handle:report({ message = final_message, percentage = 100 })
            vim.notify("Test execution completed: " .. test_name, vim.log.levels.INFO)
          else
            -- SF CLI execution failed (actual CLI error, not test failure)
            handle:report({ message = "Test execution failed", percentage = 100 })
            vim.notify("Failed to execute test: " .. test_name, vim.log.levels.ERROR)

            local stderr = j:stderr_result()
            deb("Test execution error", { stderr = stderr, return_val = return_val, stdout = stdout })
            
            if options.debug then
              if stderr and #stderr > 0 then
                deb("Test execution stderr (debug mode)", { stderr = stderr, return_val = return_val })
              end
            end
          end
          handle:finish()
        end)
      end,
    })

    job:start()
  end)
end

--- Display the last executed test results from saved file
--- @param options table|nil Additional options
function TestRunner.show_last_results(options)
  deb("Starting Show Latest Results function...")
  options = options or {}

  local result_file = get_test_result_path()

  -- Check if results file exists
  if vim.fn.filereadable(result_file) ~= 1 then
    vim.notify(
      "No tests have been executed yet. Run tests first with ':Sf test class' or ':Sf test method' to generate results.",
      vim.log.levels.INFO)
    return
  end

  -- Read and parse the results file
  local file_content = vim.fn.readfile(result_file)
  if not file_content or #file_content == 0 then
    vim.notify("Test results file is empty", vim.log.levels.ERROR)
    return
  end

  local json_string = table.concat(file_content, "\n")
  deb("Last test results file content:", json_string)
  
  local ok, result = pcall(vim.json.decode, json_string)

  if not ok then
    deb("Failed to parse test results JSON from file")
    vim.notify("Failed to parse test results file", vim.log.levels.ERROR)
    return
  end
  
  deb("Test Results Job output JSON", result)

  if not ok or not result or not result.result then
    vim.notify("Failed to parse test results file", vim.log.levels.ERROR)
    return
  end

  -- Determine test name from results
  local test_name = "Last Test Results"
  if result.result.tests and #result.result.tests > 0 then
    local first_test = result.result.tests[1]
    if first_test.ApexClass and first_test.ApexClass.Name then
      test_name = first_test.ApexClass.Name
      -- If all tests are from the same class, use class name
      local all_same_class = true
      for _, test in ipairs(result.result.tests) do
        if not test.ApexClass or test.ApexClass.Name ~= first_test.ApexClass.Name then
          all_same_class = false
          break
        end
      end
      if not all_same_class then
        test_name = "Multiple Classes"
      end
    end
  end

  -- Display results using the results buffer
  TestResultsBuffer.show_results(result, test_name)
end

--- Run tests based on current cursor position
--- @param test_type string Either "class" or "method"
--- @param options table|nil Additional options
function TestRunner.run_current_tests(test_type, options)
  deb("Starting Run Current Tests function...")

  Connector:check_cli(function()
    options = options or {}

    -- Check if current file is a test class
    if not is_test_class() then
      vim.notify("Current file is not a test class", vim.log.levels.WARN)
      return
    end

    local node = get_node_at_cursor()
    if not node then
      vim.notify("Could not analyze current position", vim.log.levels.ERROR)
      return
    end

    local class_name = find_class_name(node)
    if not class_name then
      vim.notify("Could not find class name", vim.log.levels.ERROR)
      return
    end

    if test_type == "class" then
      TestRunner.run_class_tests(class_name, options)
    elseif test_type == "method" then
      local method_name = find_method_name(node)
      if not method_name then
        vim.notify("Could not find method name at cursor position", vim.log.levels.ERROR)
        return
      end
      TestRunner.run_method_test(class_name, method_name, options)
    else
      vim.notify("Invalid test type: " .. test_type, vim.log.levels.ERROR)
    end
  end)
end

--- Run tests for a specific class with coverage report
--- @param class_name string The name of the test class to run
--- @param options table|nil Additional options
function TestRunner.run_class_coverage(class_name, options)
  Connector:check_cli(function()
    options = options or {}

    if not class_name then
      vim.notify("No test class name provided", vim.log.levels.ERROR)
      return
    end

    local handle = Process.create_progress_handle({ title = "Running coverage for " .. class_name })
    handle:report({ message = "Starting test execution with coverage...", percentage = 0 })

    local sf_cli_path = options.sf_cli_path or "sf"
    local result_file = get_coverage_result_path()

    -- Ensure the directory exists
    local result_dir = vim.fn.fnamemodify(result_file, ":h")
    vim.fn.mkdir(result_dir, "p")

    local args = Const.get_apex_test_class_args(class_name, true) -- true for coverage

    local job = Job:new({
      command = sf_cli_path,
      args = args,
      on_start = function()
        handle:report({ message = "Executing tests with coverage...", percentage = 50 })
      end,
      on_exit = function(j, return_val)
        vim.schedule(function()
          local stdout = j:result()
          local json_output = table.concat(stdout, "\n")

          -- Always write results to file, regardless of return code
          local file = io.open(result_file, "w")
          if file then
            file:write(json_output)
            file:close()
          end

          if (return_val == 0 or return_val == 100) and json_output and json_output ~= "" then
            -- SF CLI executed successfully (0 = passing tests, 100 = failing tests)
            handle:report({ message = "Processing coverage results...", percentage = 90 })

            local tests_passed = process_test_results(json_output, class_name)
            local final_message = tests_passed and "Coverage completed successfully" or "Coverage completed with test failures"

            handle:report({ message = final_message, percentage = 100 })
            vim.notify("Coverage execution completed for class: " .. class_name, vim.log.levels.INFO)
          else
            -- SF CLI execution failed (actual CLI error, not test failure)
            handle:report({ message = "Coverage execution failed", percentage = 100 })
            vim.notify("Failed to execute coverage for class: " .. class_name, vim.log.levels.ERROR)

            local stderr = j:stderr_result()
            deb("Coverage execution error", { stderr = stderr, return_val = return_val, stdout = stdout })
            
            if options.debug then
              if stderr and #stderr > 0 then
                deb("Coverage execution stderr (debug mode)", { stderr = stderr, return_val = return_val })
              end
            end
          end
          handle:finish()
        end)
      end,
    })

    job:start()
  end)
end

--- Run tests for a specific method with coverage report
--- @param class_name string The name of the test class
--- @param method_name string The name of the test method
--- @param options table|nil Additional options
function TestRunner.run_method_coverage(class_name, method_name, options)
  Connector:check_cli(function()
    options = options or {}

    if not class_name or not method_name then
      vim.notify("Class name and method name are required", vim.log.levels.ERROR)
      return
    end

    local test_name = class_name .. "." .. method_name
    local handle = Process.create_progress_handle({ title = "Running coverage for " .. test_name })
    handle:report({ message = "Starting test execution with coverage...", percentage = 0 })

    local sf_cli_path = options.sf_cli_path or "sf"
    local result_file = get_coverage_result_path()

    -- Ensure the directory exists
    local result_dir = vim.fn.fnamemodify(result_file, ":h")
    vim.fn.mkdir(result_dir, "p")

    local args = Const.get_apex_test_method_args(test_name, true) -- true for coverage

    local job = Job:new({
      command = sf_cli_path,
      args = args,
      on_start = function()
        handle:report({ message = "Executing test method with coverage...", percentage = 50 })
      end,
      on_exit = function(j, return_val)
        vim.schedule(function()
          local stdout = j:result()
          local json_output = table.concat(stdout, "\n")

          -- Always write results to file, regardless of return code
          local file = io.open(result_file, "w")
          if file then
            file:write(json_output)
            file:close()
          end

          if (return_val == 0 or return_val == 100) and json_output and json_output ~= "" then
            -- SF CLI executed successfully (0 = passing tests, 100 = failing tests)
            handle:report({ message = "Processing coverage results...", percentage = 90 })

            local tests_passed = process_test_results(json_output, test_name)
            local final_message = tests_passed and "Coverage completed successfully" or "Coverage completed with test failures"

            handle:report({ message = final_message, percentage = 100 })
            vim.notify("Coverage execution completed: " .. test_name, vim.log.levels.INFO)
          else
            -- SF CLI execution failed (actual CLI error, not test failure)
            handle:report({ message = "Coverage execution failed", percentage = 100 })
            vim.notify("Failed to execute coverage: " .. test_name, vim.log.levels.ERROR)

            local stderr = j:stderr_result()
            deb("Coverage execution error", { stderr = stderr, return_val = return_val, stdout = stdout })
            
            if options.debug then
              if stderr and #stderr > 0 then
                deb("Coverage execution stderr (debug mode)", { stderr = stderr, return_val = return_val })
              end
            end
          end
          handle:finish()
        end)
      end,
    })

    job:start()
  end)
end

--- Run coverage tests based on cursor position (class or method)
--- @param test_type string Either "class" or "method"
--- @param options table|nil Additional options
function TestRunner.run_coverage_at_cursor(test_type, options)
  options = options or {}

  -- Check if current file is a test class
  if not is_test_class() then
    vim.notify("Current file is not a test class", vim.log.levels.WARN)
    return
  end

  local node = get_node_at_cursor()
  if not node then
    vim.notify("Could not analyze current position", vim.log.levels.ERROR)
    return
  end

  local class_name = find_class_name(node)
  if not class_name then
    vim.notify("Could not find class name", vim.log.levels.ERROR)
    return
  end

  if test_type == "class" then
    TestRunner.run_class_coverage(class_name, options)
  elseif test_type == "method" then
    local method_name = find_method_name(node)
    if not method_name then
      vim.notify("Could not find method name at cursor position", vim.log.levels.ERROR)
      return
    end
    TestRunner.run_method_coverage(class_name, method_name, options)
  else
    vim.notify("Invalid coverage type: " .. test_type, vim.log.levels.ERROR)
  end
end

--- Display the last executed coverage results from saved file
--- @param options table|nil Additional options
function TestRunner.show_last_coverage_results(options)
  options = options or {}

  local result_file = get_coverage_result_path()

  -- Check if results file exists
  if vim.fn.filereadable(result_file) ~= 1 then
    vim.notify(
      "No coverage has been executed yet. Run coverage first with ':Sf coverage class' or ':Sf coverage method' to generate results.",
      vim.log.levels.INFO)
    return
  end

  -- Read and parse the results file
  local file_content = vim.fn.readfile(result_file)
  if not file_content or #file_content == 0 then
    vim.notify("Coverage results file is empty", vim.log.levels.ERROR)
    return
  end

  local json_string = table.concat(file_content, "\n")
  deb("Last coverage results file content:", json_string)
  
  local ok, result = pcall(vim.json.decode, json_string)

  if not ok then
    deb("Failed to parse coverage results JSON from file")
    vim.notify("Failed to parse coverage results file", vim.log.levels.ERROR)
    return
  end
  
  deb("Coverage Results parsed:", result)

  if not result or not result.result then
    deb("Coverage result missing expected structure")
    vim.notify("Failed to parse coverage results file", vim.log.levels.ERROR)
    return
  end

  -- Display results using the same buffer system
  TestResultsBuffer.show_results(result, "Last Coverage Results")
end

return TestRunner
