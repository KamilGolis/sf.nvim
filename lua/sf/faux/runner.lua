--- sf-nvim sObject faux class cache runner
-- Orchestrates the rebuild/clear/status workflow for the sObject faux class cache.
-- @license MIT
--
-- Flow:
--   1. `sf sobject list -s all --json` → get array of sObject names
--   2. For each name: `sf sobject describe -s <name> --json`
--   3. Pipe describe result → declgen → fauxgen → write .cls file
--   4. Output lands in .sfdx/tools/sobjects/{standardObjects,customObjects}/

local Config = require("sf.config")
local Connector = require("sf.org.connect")
local Const = require("sf.const")
local DeclGen = require("sf.faux.declgen")
local FauxGen = require("sf.faux.fauxgen")
local JobUtils = require("sf.core.job_utils")
local Log = require("sf.core.log").scoped("faux/runner")
local OrgUtils = require("sf.org.utils")
local PathUtils = require("sf.core.path_utils")

local M = {}

--- @class FauxRunner
local Runner = {}

--- Resolve the absolute path to the .sfdx/tools/sobjects directory
--- @return string
local function get_sobjects_dir()
  return PathUtils.normalize(PathUtils.join(vim.uv.cwd(), Const.SOBJECTS_DIR))
end

--- Resolve path for standard objects subdirectory
--- @return string
local function get_standard_dir()
  return PathUtils.join(get_sobjects_dir(), Const.STANDARD_DIR)
end

--- Resolve path for custom objects subdirectory
--- @return string
local function get_custom_dir()
  return PathUtils.join(get_sobjects_dir(), Const.CUSTOM_DIR)
end

--- Delete and recreate a directory
--- @param dir string Absolute path to the directory
local function reset_directory(dir)
  if vim.fn.isdirectory(dir) == 1 then
    vim.fn.delete(dir, "rf")
  end

  vim.fn.mkdir(dir, "p")
end

--- Parse JSON response from a CLI job and return the result
--- @param job table The completed CLI job
--- @return table|nil Parsed result, or nil on failure
local function parse_json_result(job)
  local stdout_lines = job:result()
  local stdout = type(stdout_lines) == "table" and table.concat(stdout_lines, "\n") or stdout_lines
  local ok, parsed = pcall(vim.json.decode, stdout)

  if not ok or not parsed then
    return nil
  end

  return parsed
end

--- Run the sequential describe loop for a list of sObject names.
--- @param sobject_names string[] Array of sObject API names to describe
--- @param mode string "all" | "standard" | "custom" | "selected" — filtering mode
--- @param target_org string Org username
--- @param executable_path string Path to sf CLI
--- @param context table Progress context handle
local function run_describe_loop(sobject_names, mode, target_org, executable_path, context)
  local standard_dir = get_standard_dir()
  local custom_dir = get_custom_dir()

  reset_directory(standard_dir)
  reset_directory(custom_dir)

  local total = #sobject_names
  local processed = 0
  local standard_count = 0
  local custom_count = 0

  local function describe_next(idx)
    if idx > total then
      local msg = string.format(Const.SF_CLI_MESSAGES.SOBJECT_REBUILD_COMPLETE_FORMAT, standard_count, custom_count)
      context.handle:report({ message = msg, percentage = 100 })
      context.handle:finish()

      Log.notify(msg, vim.log.levels.INFO)

      return
    end

    local name = sobject_names[idx]
    local describe_args = Const.get_sobject_describe_args(name, nil, target_org)
    local describe_job = JobUtils.create_cli_job(executable_path, describe_args, {
      on_success = function(job2)
        local described = parse_json_result(job2)
        if described and described.result then
          local is_custom = described.result.custom == true

          -- Filter by mode: skip objects that don't match
          local should_write = (mode == "all" or mode == "selected")
            or (mode == "standard" and not is_custom)
            or (mode == "custom" and is_custom)

          if should_write then
            local definition = DeclGen.generate_definition(described.result)
            local class_text = FauxGen.generate_faux_class_text(definition)
            local output_dir = is_custom and custom_dir or standard_dir
            local file_path = PathUtils.join(output_dir, name .. ".cls")
            local f, write_err = io.open(file_path, "w")

            if f then
              f:write(class_text)
              f:close()
              if is_custom then
                custom_count = custom_count + 1
              else
                standard_count = standard_count + 1
              end
              Log.deb("" .. name .. "..OK")
            else
              Log.notify(
                string.format(Const.SF_CLI_MESSAGES.SOBJECT_WRITE_FAILED_FORMAT, file_path, write_err or "unknown"),
                vim.log.levels.ERROR
              )
            end
          end
        else
          Log.notify(string.format(Const.SF_CLI_MESSAGES.SOBJECT_DESCRIBE_FAILED_FORMAT, name), vim.log.levels.WARN)
        end

        processed = processed + 1

        context.handle:report({
          message = string.format(Const.SF_CLI_MESSAGES.SOBJECT_DESCRIBE_PROGRESS_FORMAT, processed, total, name),
          percentage = math.max(1, math.floor(100 * processed / total)),
        })

        vim.schedule(function()
          describe_next(idx + 1)
        end)
      end,
      on_error = function(job2, return_val)
        local stderr = job2:stderr_result()

        Log.deb("" .. name .. " FAILED exit=" .. return_val)
        Log.notify(
          string.format(Const.SF_CLI_MESSAGES.SOBJECT_DESCRIBE_ERROR_FORMAT, name, return_val, stderr or ""),
          vim.log.levels.WARN
        )

        processed = processed + 1

        vim.schedule(function()
          describe_next(idx + 1)
        end)
      end,
    })
    context.handle:report({
      message = string.format("Describing: %s", name),
      percentage = math.max(0, math.floor(100 * processed / total)),
    })
    describe_job:start()
  end

  describe_next(1)
end

--- Check if curl is available for REST batch operations
local has_curl = nil
local function check_curl()
  if has_curl == nil then
    has_curl = vim.fn.executable("curl") == 1
    Log.deb("curl detected:", has_curl)
  end

  return has_curl
end

--- Get instanceUrl and accessToken for REST API calls
--- @param target_org string Org username
--- @param callback fun(instance_url: string|nil, access_token: string|nil, err: string|nil)
local function get_rest_credentials(target_org, callback)
  local exec = Config:get_options().sf_cli_path
  local org_display = vim.split(Const.REST_SF.ORG_DISPLAY.CMD, " ")
  local access_token_cmd = vim.split(Const.REST_SF.ACCESS_TOKEN.CMD, " ")
  -- Get instanceUrl
  local function do_org_display()
    local args = {}

    vim.list_extend(args, org_display)
    vim.list_extend(args, { Const.REST_SF.ORG_DISPLAY.ARGS.ORG, target_org, Const.REST_SF.ORG_DISPLAY.ARGS.JSON })

    return vim.system(
      { exec, unpack(args) },
      { text = true },
      vim.schedule_wrap(function(obj)
        if obj.code ~= 0 then
          Log.deb("get_rest_credentials failed (org display):", obj.stderr or tostring(obj.code))
          return callback(nil, nil, Const.SF_CLI_MESSAGES.REST_ORG_DISPLAY_FAILED)
        end

        local ok, parsed = pcall(vim.json.decode, obj.stdout)
        if not ok or not parsed or not parsed.result or not parsed.result.instanceUrl then
          Log.deb("get_rest_credentials failed (parse org info)")
          return callback(nil, nil, Const.SF_CLI_MESSAGES.REST_PARSE_ORG_INFO_FAILED)
        end

        local instance_url = parsed.result.instanceUrl
        -- Get access token
        local args2 = {}

        vim.list_extend(args2, access_token_cmd)
        vim.list_extend(
          args2,
          { Const.REST_SF.ACCESS_TOKEN.ARGS.ORG, target_org, Const.REST_SF.ACCESS_TOKEN.ARGS.JSON }
        )
        vim.system(
          { exec, unpack(args2) },
          { text = true },
          vim.schedule_wrap(function(obj2)
            if obj2.code ~= 0 then
              Log.deb("get_rest_credentials failed (token fetch):", obj2.stderr or tostring(obj2.code))
              return callback(nil, nil, Const.SF_CLI_MESSAGES.REST_TOKEN_FETCH_FAILED)
            end

            local ok2, parsed2 = pcall(vim.json.decode, obj2.stdout)
            if not ok2 or not parsed2 or not parsed2.result or not parsed2.result.accessToken then
              Log.deb("get_rest_credentials failed (parse token)")
              return callback(nil, nil, Const.SF_CLI_MESSAGES.REST_PARSE_TOKEN_FAILED)
            end

            Log.deb("rest credentials ok, token len:", #parsed2.result.accessToken)

            callback(instance_url, parsed2.result.accessToken, nil)
          end)
        )
      end)
    )
  end

  do_org_display()
end

--- Describe sObjects via Salesforce REST composite/batch API (25 per call)
--- @param sobject_names string[] Array of sObject API names
--- @param mode string Filtering mode
--- @param target_org string Org username
--- @param context table Progress handle
local function describe_batch_rest(sobject_names, mode, target_org, context)
  get_rest_credentials(target_org, function(instance_url, token, err)
    if err then
      context.handle:report({ message = Const.SF_CLI_MESSAGES.REST_CREDENTIALS_FAILED_PREFIX .. err, percentage = 100 })
      context.handle:finish()
      return
    end

    local api_ver = Const.REST.VERSION_PREFIX .. Config:get_options().api_version
    local endpoint = instance_url .. Const.REST.SERVICES_DATA .. "/" .. api_ver .. "/" .. Const.REST.COMPOSITE_BATCH
    local batch_size = Const.SOBJECT_BATCH_SIZE
    local total = #sobject_names
    local processed = 0
    local standard_count = 0
    local custom_count = 0
    local standard_dir = get_standard_dir()
    local custom_dir = get_custom_dir()

    reset_directory(standard_dir)
    reset_directory(custom_dir)

    local function process_batch(batch_start)
      if batch_start > total then
        local msg = string.format(Const.SF_CLI_MESSAGES.SOBJECT_REBUILD_COMPLETE_FORMAT, standard_count, custom_count)
        context.handle:report({ message = msg, percentage = 100 })
        context.handle:finish()

        Log.notify(msg, vim.log.levels.INFO)

        return
      end

      local batch_end = math.min(batch_start + batch_size - 1, total)
      local batch_names = {}

      for i = batch_start, batch_end do
        table.insert(batch_names, sobject_names[i])
      end

      local batch_requests = {}
      for _, name in ipairs(batch_names) do
        table.insert(batch_requests, {
          method = Const.REST.METHOD_GET,
          url = api_ver .. "/" .. Const.REST.SOBJECTS .. "/" .. name .. "/" .. Const.REST.DESCRIBE,
        })
      end

      local body = vim.json.encode({ [Const.REST.BATCH_REQUESTS] = batch_requests })

      local cmd = {
        Const.REST_CLI.CURL,
        Const.REST_CLI.FLAGS[1],
        Const.REST_CLI.FLAGS[2],
        Const.REST_CLI.FLAGS[3],
        "-X",
        Const.REST.METHOD_POST,
        endpoint,
        "-H",
        Const.REST.HEADER_AUTH .. token,
        "-H",
        Const.REST.HEADER_CONTENT,
        Const.REST.DATA_BINARY,
        Const.REST.STDIN,
      }

      Log.deb(
        "batch",
        math.ceil(batch_start / batch_size),
        "/",
        math.ceil(total / batch_size),
        "describing",
        #batch_names,
        "objects"
      )

      context.handle:report({
        message = string.format(
          Const.SF_CLI_MESSAGES.SOBJECT_BATCH_PROGRESS_FORMAT,
          math.ceil(batch_start / batch_size),
          math.ceil(total / batch_size),
          #batch_names
        ),
        percentage = math.max(1, math.floor(100 * processed / total)),
      })

      vim.system(
        cmd,
        { stdin = body, text = true },
        vim.schedule_wrap(function(obj)
          Log.deb("batch curl exit:", obj.code, "stdout len:", #(obj.stdout or ""))
          if obj.code ~= 0 then
            Log.notify(Const.SF_CLI_MESSAGES.REST_BATCH_DESCRIBE_FAILED .. (obj.stderr or ""), vim.log.levels.WARN)
            processed = batch_end
            process_batch(batch_end + 1)
            return
          end

          local ok, parsed = pcall(vim.json.decode, obj.stdout)
          if not ok or not parsed or not parsed.results then
            processed = batch_end
            process_batch(batch_end + 1)
            return
          end

          for _, res in ipairs(parsed.results) do
            if res.statusCode == 200 and type(res.result) == "table" then
              local describe = res.result
              local is_custom = describe.custom == true
              local should_write = (mode == "all" or mode == "selected")
                or (mode == "standard" and not is_custom)
                or (mode == "custom" and is_custom)

              if should_write then
                local definition = DeclGen.generate_definition(describe)
                local class_text = FauxGen.generate_faux_class_text(definition)
                local output_dir = is_custom and custom_dir or standard_dir
                local file_path = PathUtils.join(output_dir, describe.name .. ".cls")
                local f, write_err = io.open(file_path, "w")
                if f then
                  f:write(class_text)
                  f:close()
                  if is_custom then
                    custom_count = custom_count + 1
                  else
                    standard_count = standard_count + 1
                  end
                  Log.deb("" .. describe.name .. "..OK")
                else
                  Log.notify(
                    string.format(Const.SF_CLI_MESSAGES.SOBJECT_WRITE_FAILED_FORMAT, file_path, write_err or "unknown"),
                    vim.log.levels.ERROR
                  )
                end
              end
            end
          end

          processed = batch_end
          process_batch(batch_end + 1)
        end)
      )
    end

    process_batch(1)
  end)
end

--- List sObjects via REST describeGlobal API (includes custom flag)
--- @param target_org string Org username
--- @param callback fun(sobjects: table|nil, err: string|nil)
local function list_sobjects_rest(target_org, callback)
  get_rest_credentials(target_org, function(instance_url, token, err)
    if err then
      return callback(nil, err)
    end

    local api_ver = Const.REST.VERSION_PREFIX .. Config:get_options().api_version
    local endpoint = instance_url .. Const.REST.SERVICES_DATA .. "/" .. api_ver .. "/" .. Const.REST.SOBJECTS .. "/"
    local cmd = {
      Const.REST_CLI.CURL,
      Const.REST_CLI.FLAGS[1],
      Const.REST_CLI.FLAGS[2],
      Const.REST_CLI.FLAGS[3],
      endpoint,
      "-H",
      Const.REST.HEADER_AUTH .. token,
    }

    vim.system(
      cmd,
      { text = true },
      vim.schedule_wrap(function(obj)
        if obj.code ~= 0 then
          return callback(nil, Const.SF_CLI_MESSAGES.REST_LIST_SOBJECTS_FAILED)
        end
        local ok, parsed = pcall(vim.json.decode, obj.stdout)

        if not ok or not parsed or not parsed.sobjects then
          return callback(nil, Const.SF_CLI_MESSAGES.REST_PARSE_LIST_FAILED)
        end

        callback(parsed.sobjects, nil)
      end)
    )
  end)
end

--- Run rebuild: list all sObjects, describe each, generate & write faux classes
function Runner:rebuild()
  Connector:check_cli(function()
    local has_org, target_org, org_error = OrgUtils.check_default_org()
    if not has_org then
      Log.notify(org_error or Const.SF_CLI_MESSAGES.NO_DEFAULT_ORG, vim.log.levels.ERROR)
      return
    end

    local cli_valid, executable_path, error_msg = JobUtils.validate_cli_installation(Config:get_options().sf_cli_path)
    if not cli_valid or not executable_path then
      Log.notify(error_msg or Const.SF_CLI_MESSAGES.NOT_FOUND, vim.log.levels.ERROR)
      return
    end

    local context = JobUtils.create_progress_context(
      Const.SF_CLI_MESSAGES.SOBJECT_REBUILD_TITLE,
      Const.SF_CLI_MESSAGES.SOBJECT_REBUILD_SUCCESS,
      Const.SF_CLI_MESSAGES.SOBJECT_REBUILD_FAILED
    )

    -- Step 1: List all sObjects
    context.handle:report({ message = Const.SF_CLI_MESSAGES.SOBJECT_LISTING, percentage = 0 })

    local function on_list_complete(sobjects, err)
      if err then
        context.handle:report({ message = "List failed: " .. err, percentage = 100 })
        context.handle:finish()
        return
      end

      if #sobjects == 0 then
        context.handle:report({ message = Const.SF_CLI_MESSAGES.SOBJECT_LIST_EMPTY, percentage = 100 })
        context.handle:finish()
        return
      end

      context.handle:finish()
      local Picker = require("sf.faux.picker")

      Picker.show_sobject_picker(sobjects, function(selection)
        local describe_context = JobUtils.create_progress_context(
          Const.SF_CLI_MESSAGES.SOBJECT_REBUILD_TITLE,
          Const.SF_CLI_MESSAGES.SOBJECT_REBUILD_SUCCESS,
          Const.SF_CLI_MESSAGES.SOBJECT_REBUILD_FAILED
        )
        if check_curl() then
          Log.deb("using REST batch API for describe")
          describe_batch_rest(selection.names, selection.mode, target_org, describe_context)
        else
          Log.deb("curl not found, using sequential sf CLI")
          run_describe_loop(selection.names, selection.mode, target_org, executable_path, describe_context)
        end
      end)
    end

    if check_curl() then
      Log.deb("using REST list API")
      list_sobjects_rest(target_org, on_list_complete)
    else
      local list_args = Const.get_sobject_list_args("all", nil, target_org)

      Log.deb("list args: ", vim.inspect(list_args))

      local list_job = JobUtils.create_cli_job(executable_path, list_args, {
        on_success = function(job)
          local parsed = parse_json_result(job)

          if not parsed or not parsed.result then
            on_list_complete(nil, "parse failed")
            return
          end

          on_list_complete(parsed.result, nil)
        end,
        on_error = function(job2, code)
          on_list_complete(nil, "list failed exit=" .. code)
        end,
      })
      list_job:start()
    end
  end)
end

--- Clear all generated .cls files from the cache directories
function Runner:clear()
  local standard_dir = get_standard_dir()
  local custom_dir = get_custom_dir()

  local cleaned = 0
  local function clear_dir(dir)
    if vim.fn.isdirectory(dir) == 1 then
      local handle = vim.uv.fs_scandir(dir)

      if handle then
        while true do
          local name, type = vim.uv.fs_scandir_next(handle)
          if not name then
            break
          end

          local full_path = PathUtils.join(dir, name)
          if type == "file" and name:match("%.cls$") then
            os.remove(full_path)
            cleaned = cleaned + 1
          end
        end
      end
    end
  end

  clear_dir(standard_dir)
  clear_dir(custom_dir)

  Log.notify(
    string.format(Const.SF_CLI_MESSAGES.SOBJECT_CLEARED_FORMAT, cleaned, Const.SOBJECTS_DIR),
    vim.log.levels.INFO
  )
end

--- Count .cls files in a directory
--- @param dir string Absolute path
--- @return integer
local function count_cls_files(dir)
  if vim.fn.isdirectory(dir) ~= 1 then
    return 0
  end

  local count = 0
  local handle = vim.uv.fs_scandir(dir)

  if handle then
    while true do
      local name, type = vim.uv.fs_scandir_next(handle)
      if not name then
        break
      end
      if type == "file" and name:match("%.cls$") then
        count = count + 1
      end
    end
  end

  return count
end

--- Show cache status
function Runner:status()
  local standard_dir = get_standard_dir()
  local custom_dir = get_custom_dir()
  local sdtandard_count = count_cls_files(standard_dir)
  local custom_count = count_cls_files(custom_dir)
  local total = sdtandard_count + custom_count

  local msg = string.format(
    Const.SF_CLI_MESSAGES.SOBJECT_CACHE_STATUS_FORMAT,
    Const.SOBJECTS_DIR,
    sdtandard_count,
    custom_count,
    total
  )
end

setmetatable(M, { __index = Runner })

return M
