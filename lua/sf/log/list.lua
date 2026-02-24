--- sf-nvim log list module
-- @license MIT

local Snacks = require("snacks")

local Config = require("sf.config")
local PathUtils = require("sf.core.path_utils")
local Const = require("sf.const")
local Connector = require("sf.org.connect")
local JobUtils = require("sf.core.job_utils")
local OrgUtils = require("sf.org.utils")

local LogList = {}

-- =============================================================================
-- UTILITY FUNCTIONS
-- =============================================================================

--- Get the path to store log list results
--- @return string The path to store log list JSON
local function get_log_list_path()
    local config = Config:get_options()
    return PathUtils.join(config.cache_path, "logs", "logList.json")
end

--- Process log list JSON response and convert to picker format
--- @param json_response string The JSON string from SF CLI apex list log command
--- @return boolean success True if processing was successful
--- @return table|nil logs Array of log items for picker, or nil if processing failed
--- @return string|nil error_message Error message if processing fails
local function process_log_list(json_response)
    deb("Log list JSON response:", json_response)
    
    -- Validate and parse the JSON response
    local success, parsed, error_message = JobUtils.validate_json_response(json_response, {
        status = "number",
        result = "table",
    })

    if not success then
        deb("Failed to validate log list JSON:", error_message)
        return false, nil, error_message
    end
    
    deb("Parsed log list:", parsed)

    -- Check if the parsed result has the expected structure
    if not parsed or not parsed.result or parsed.status ~= 0 then
        deb("Invalid log list structure or command failed")
        return false, nil, "Invalid log list response format or command failed"
    end

    local logs = {}
    local log_records = parsed.result

    -- Handle case where result is an array of logs
    if type(log_records) == "table" then
        for _, log in ipairs(log_records) do
            if log.Id then
                -- Format dates for better readability (handle timezone format)
                local start_time = log.StartTime or "Unknown"
                if start_time ~= "Unknown" and start_time:match("T") then
                    -- Handle both Z and +0000 timezone formats
                    start_time = start_time:gsub("T", " "):gsub("%.%d+Z", ""):gsub("%+%d%d%d%d", "")
                end

                -- Format log size
                local log_size = "Unknown"
                if log.LogLength then
                    local size_num = tonumber(log.LogLength)
                    if size_num then
                        if size_num > 1024 * 1024 then
                            log_size = string.format("%.1f MB", size_num / (1024 * 1024))
                        elseif size_num > 1024 then
                            log_size = string.format("%.1f KB", size_num / 1024)
                        else
                            log_size = string.format("%d B", size_num)
                        end
                    end
                end

                -- Format status (sanitize and truncate long error messages for table display)
                local status = log.Status or "Unknown"
                -- Sanitize status text to remove newlines and other problematic characters
                if status ~= "Unknown" then
                    status = tostring(status):gsub("[\r\n\t]", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
                end
                local status_display = status
                if #status > 15 then
                    status_display = status:sub(1, 12) .. "..."
                end

                table.insert(logs, {
                    -- Store all the data we need for display
                    id = log.Id or "Unknown",
                    user_name = (log.LogUser and log.LogUser.Name) or "Unknown",
                    start_time = start_time,
                    duration = log.DurationMilliseconds and (log.DurationMilliseconds .. " ms") or "Unknown",
                    size = log_size,
                    status = status_display,
                    status_full = status, -- Keep full status for preview
                    operation = log.Operation or "Unknown",
                    application = log.Application or "Unknown",
                    request = log.Request or "Unknown",
                    location = log.Location or "Unknown",
                    log_data = log
                })
            end
        end
    end

    deb("Processed log list entries:", { count = #logs })
    return true, logs, nil
end

--- Create log selection picker using Snacks with fallback compatibility
--- @param logs table Array of log items
--- @param callback function Callback function to handle log selection
local function create_log_selection_picker(logs, callback)
    if not logs or #logs == 0 then
        vim.notify("No debug logs found", vim.log.levels.INFO)
        return
    end

    -- Try the advanced picker format first, with fallback to simple format
    local picker_config = {
        items = logs,
        layout = {
            preset = "telescope",
            width = 0.9,
            height = 0.8,
        },
        format = function(item, _)
            -- Format with exact column specifications:
            -- ID: 18 chars + 1 for |
            -- Username: 13 chars + 2 spaces (start/end) + 1 for |
            -- Date: 19 chars + 2 spaces (start/end) + 1 for |
            -- Duration: 8 chars + 2 spaces (start/end) + 1 for |
            -- Status: 15 chars + 1 space at beginning

            local id = item.id or "Unknown"
            if #id > 18 then
                id = id:sub(1, 15) .. "..."
            end

            local username = item.user_name or "Unknown"
            if #username > 13 then
                username = username:sub(1, 10) .. "..."
            end

            local start_time = item.start_time or "Unknown"
            if #start_time > 19 then
                start_time = start_time:sub(1, 16) .. "..."
            end

            local duration = item.duration or "Unknown"
            if #duration > 8 then
                duration = duration:sub(1, 5) .. "..."
            end

            local status = item.status or "Unknown"
            if #status > 15 then
                status = status:sub(1, 12) .. "..."
            end

            return {
                { string.format("%-18s ", id), "SnacksPickerNormal" },
                { " ", "SnacksPickerComment" },
                { string.format("%-13s ", username), "SnacksPickerComment" },
                { " ", "SnacksPickerComment" },
                { string.format("%-19s ", start_time), "SnacksPickerComment" },
                { " ", "SnacksPickerComment" },
                { string.format("%-8s ", duration), "SnacksPickerComment" },
                { " ", "SnacksPickerComment" },
                { string.format("%s ", status), "SnacksPickerComment" }
            }
        end,
        confirm = function(picker, item)
            if picker and picker.close then
                picker:close()
            end
            if callback and type(callback) == "function" then
                callback(item)
            end
        end,
        preview = function(ctx)
            local item = ctx.item
            if not item then return end

            if not item then
                return { " No item selected" }
            end

            -- Handle header row
            if item.is_header then
                return {
                    Const.ICONS.LOG_INFO .. " Salesforce Debug Logs",
                    "",
                    Const.ICONS.INFO .. " This picker displays debug logs from your default Salesforce org.",
                    Const.ICONS.INFO .. " Select a log entry to view detailed information.",
                    "",
                    Const.ICONS.LOG_INFO .. " Column Layout:",
                    "  " .. Const.ICONS.LOG_ID .. " Log ID (18 chars): Salesforce debug log identifier",
                    "  " .. Const.ICONS.USER .. " User (13 chars): Name of the log owner",
                    "  " .. Const.ICONS.TIME .. " Start Time (19 chars): When the log was created",
                    "  " .. Const.ICONS.DURATION .. " Duration (8 chars): Execution time in milliseconds",
                    "  " .. Const.ICONS.SUCCESS .. " Status (15 chars): Execution status or error message",
                    "",
                    Const.ICONS.INFO .. " Long values are truncated with '...' for table display.",
                    Const.ICONS.INFO .. " Full details are shown in this preview panel when you select a log.",
                }
            end

            -- Helper function to get status icon and color
            local function get_status_info(status)
                local status_lower = (status or "unknown"):lower()
                if status_lower:match("success") then
                    return Const.ICONS.SUCCESS, "Success"
                elseif status_lower:match("error") or status_lower:match("fail") then
                    return Const.ICONS.ERROR, "Error"
                elseif status_lower:match("warning") or status_lower:match("warn") then
                    return Const.ICONS.WARNING, "Warning"
                else
                    return Const.ICONS.INFO, "Info"
                end
            end

            -- Helper function to get application icon
            local function get_app_icon(app)
                local app_lower = (app or "unknown"):lower()
                if app_lower:match("browser") then
                    return Const.ICONS.BROWSER
                elseif app_lower:match("api") then
                    return Const.ICONS.API
                elseif app_lower:match("batch") then
                    return Const.ICONS.BATCH
                else
                    return Const.ICONS.MOBILE
                end
            end

            -- Helper function to format duration with icon
            local function format_duration(duration)
                if not duration or duration == "Unknown" then
                    return Const.ICONS.MEDIUM .. " Unknown"
                end
                local num = duration:match("(%d+)")
                if num then
                    local ms = tonumber(num)
                    if ms and ms > 1000 then
                        return Const.ICONS.SLOW .. " " .. duration .. " (slow)"
                    elseif ms and ms > 500 then
                        return Const.ICONS.MEDIUM .. " " .. duration .. " (medium)"
                    else
                        return Const.ICONS.FAST .. " " .. duration .. " (fast)"
                    end
                end
                return Const.ICONS.MEDIUM .. " " .. duration
            end

            -- Helper function to format size with icon
            local function format_size(size)
                if not size or size == "Unknown" then
                    return Const.ICONS.MEDIUM_FILE .. " Unknown"
                end
                if size:match("MB") then
                    return Const.ICONS.LARGE_FILE .. " " .. size .. " (large)"
                elseif size:match("KB") then
                    return Const.ICONS.MEDIUM_FILE .. " " .. size .. " (medium)"
                else
                    return Const.ICONS.SMALL_FILE .. " " .. size .. " (small)"
                end
            end

            -- Helper function to sanitize text by removing problematic characters
            local function sanitize_text(text)
                if not text or text == "" then
                    return "Unknown"
                end

                -- Convert to string if not already
                text = tostring(text)

                -- Replace newlines, carriage returns, and tabs with spaces
                text = text:gsub("[\r\n\t]", " ")

                -- Replace multiple consecutive spaces with single space
                text = text:gsub("%s+", " ")

                -- Trim leading and trailing whitespace
                text = text:gsub("^%s+", ""):gsub("%s+$", "")

                return text
            end

            -- Helper function to wrap long text into multiple lines with proper alignment
            local function wrap_text_with_prefix(prefix, text, max_width)
                -- Sanitize the input text first
                local clean_text = sanitize_text(text)

                if not clean_text or clean_text == "" or clean_text == "Unknown" then
                    return { prefix .. "Unknown" }
                end

                local lines = {}
                local remaining_text = clean_text
                local prefix_len = vim.fn.strdisplaywidth(prefix)
                local continuation_prefix = string.rep(" ", prefix_len)

                -- First line with the original prefix
                if #remaining_text <= max_width then
                    table.insert(lines, prefix .. remaining_text)
                else
                    -- Find the best break point within max_width
                    local break_point = max_width
                    for i = max_width, 1, -1 do
                        if remaining_text:sub(i, i):match("%s") then
                            break_point = i - 1
                            break
                        end
                    end

                    table.insert(lines, prefix .. remaining_text:sub(1, break_point))
                    remaining_text = remaining_text:sub(break_point + 1):gsub("^%s+", "") -- Remove leading spaces

                    -- Continue with wrapped lines
                    while #remaining_text > 0 do
                        if #remaining_text <= max_width then
                            table.insert(lines, continuation_prefix .. remaining_text)
                            break
                        else
                            break_point = max_width
                            for i = max_width, 1, -1 do
                                if remaining_text:sub(i, i):match("%s") then
                                    break_point = i - 1
                                    break
                                end
                            end

                            table.insert(lines, continuation_prefix .. remaining_text:sub(1, break_point))
                            remaining_text = remaining_text:sub(break_point + 1):gsub("^%s+", "")
                        end
                    end
                end

                return lines
            end

            local status_icon = get_status_info(item.status_full or item.status)
            local app_icon = get_app_icon(item.application)
            local duration_formatted = format_duration(item.duration)
            local size_formatted = format_size(item.size)

            -- Format status with proper line wrapping
            local status_prefix = status_icon .. " Status:       "
            local status_lines = wrap_text_with_prefix(status_prefix, item.status_full or item.status or "Unknown", 40)

            local details = {
                "                     " .. Const.ICONS.LOG_INFO .. " Log Information",
                "===========================================================",
                "",
                Const.ICONS.LOG_ID .. " Log ID:       " .. (item.id or "Unknown"),
                Const.ICONS.USER .. " User:         " .. (item.user_name or "Unknown"),
                Const.ICONS.TIME .. " Start Time:   " .. (item.start_time or "Unknown"),
                Const.ICONS.DURATION .. " Duration:     " .. duration_formatted,
                Const.ICONS.SIZE .. " Size:         " .. size_formatted,
            }

            -- Add the wrapped status lines
            for _, line in ipairs(status_lines) do
                table.insert(details, line)
            end

            -- Continue with technical details
            vim.list_extend(details, {
                "",
                "                    " .. Const.ICONS.TECHNICAL .. " Technical Details",
                "===========================================================",
                "",
                Const.ICONS.OPERATION .. " Operation:    " .. (item.operation or "Unknown"),
                app_icon .. " Application:  " .. (item.application or "Unknown"),
                Const.ICONS.REQUEST .. " Request:      " .. (item.request or "Unknown"),
                Const.ICONS.LOCATION .. " Location:     " .. (item.location or "Unknown"),
            })

            -- Add Salesforce URL if available
            if item.log_data and item.log_data.attributes and item.log_data.attributes.url then
                table.insert(details, "")
                table.insert(details,
                    "                     " .. Const.ICONS.LINK .. " Salesforce URL")
                table.insert(details, "===========================================================")
                table.insert(details, "")
                table.insert(details, Const.ICONS.URL .. " " .. item.log_data.attributes.url)
            end

            -- Add metadata section if available
            if item.log_data then
                table.insert(details, "")
                table.insert(details,
                    "                      " .. Const.ICONS.METADATA .. " Metadata")
                table.insert(details, "===========================================================")
                table.insert(details, "")

                -- Add key metadata fields with icons
                if item.log_data.DurationMilliseconds then
                    table.insert(details,
                        Const.ICONS.MEDIUM .. " Raw Duration: " .. item.log_data.DurationMilliseconds .. " ms")
                end
                if item.log_data.LogLength then
                    table.insert(details, Const.ICONS.SIZE .. " Raw Size: " .. item.log_data.LogLength .. " bytes")
                end
                if item.log_data.attributes and item.log_data.attributes.type then
                    table.insert(details, Const.ICONS.TYPE .. " Object Type: " .. item.log_data.attributes.type)
                end
            end

            vim.bo[ctx.buf].modifiable = true
            vim.api.nvim_buf_set_lines(ctx.buf, 0, -1, false, details)

            -- Set filetype for syntax highlighting
            -- vim.bo[ctx.buf].filetype = ""

            vim.bo[ctx.buf].modifiable = false
            return true -- Return true to indicate we handled the preview
        end,
    }

    -- Call Snacks picker with error handling
    local ok, err = pcall(Snacks.picker, picker_config)
    if not ok then
        vim.notify("Failed to create picker: " .. tostring(err), vim.log.levels.ERROR)
        -- Fallback to simple notification
        local log_list = {}
        for i, log in ipairs(logs) do
            table.insert(log_list, string.format("%d. %s (%s)", i, log.id, log.status))
        end
        vim.notify("Available logs:\n" .. table.concat(log_list, "\n"), vim.log.levels.INFO)
    end
end

-- =============================================================================
-- PUBLIC API
-- =============================================================================

--- Fetch and display Salesforce debug logs
--- @param options table|nil Additional options
function LogList.list_logs(options)
    options = options or {}

    -- First check if SF CLI is installed
    Connector:check_cli(function()
        -- Check if default org is set
        local has_default_org, target_org, org_error = OrgUtils.check_default_org()
        if not has_default_org then
            vim.notify(org_error or Const.SF_CLI_MESSAGES.NO_DEFAULT_ORG, vim.log.levels.ERROR)
            return
        end

        -- Validate CLI installation
        local cli_valid, executable_path, error_msg =
            JobUtils.validate_cli_installation(Config:get_options().sf_cli_path)
        if not cli_valid or not executable_path then
            vim.notify(error_msg or Const.SF_CLI_MESSAGES.NOT_FOUND, vim.log.levels.ERROR)
            return
        end

        -- Create progress context
        local context = JobUtils.create_progress_context(
            Const.SF_CLI_MESSAGES.LOG_LIST_TITLE,
            Const.SF_CLI_MESSAGES.LOG_LIST_SUCCESS,
            Const.SF_CLI_MESSAGES.LOG_LIST_FAILED
        )

        -- Get log list file path and ensure directory exists
        local result_file = get_log_list_path()
        local result_dir = vim.fn.fnamemodify(result_file, ":h")
        vim.fn.mkdir(result_dir, "p")

        -- Build command arguments
        local args = Const.get_apex_log_list_args(target_org)

        -- Create and start the job
        local job = JobUtils.create_cli_job(executable_path, args, {
            on_success = function(job, return_val)
                deb("Log list job success", { return_val = return_val })
                
                local result = table.concat(job:result(), "\n")
                
                deb("Log list raw result:", result)

                -- Save results to file
                local file = io.open(result_file, "w")
                if file then
                    file:write(result)
                    file:close()
                end

                if result == "" then
                    JobUtils.handle_cli_error(return_val, context, Const.SF_CLI_MESSAGES.LOG_LIST_EMPTY)
                    return
                end

                -- Process log list and create picker
                local success, logs, error_message = process_log_list(result)
                if not success or not logs then
                    JobUtils.handle_cli_error(return_val, context, error_message or "Failed to process log list")
                    return
                end

                if #logs == 0 then
                    JobUtils.handle_cli_error(return_val, context, "No logs found in response")
                    return
                end

                -- Debug: Log the number of processed logs
                vim.notify(string.format("Processing %d logs for picker", #logs), vim.log.levels.INFO)

                -- Create picker for log selection with error handling
                create_log_selection_picker(logs, function(item)
                    if not item then
                        vim.notify("No item selected", vim.log.levels.WARN)
                        return
                    end

                    -- Show detailed log information
                    local notification_text = string.format(
                        "Selected log: %s\nUser: %s\nStart Time: %s\nDuration: %s\nSize: %s\nStatus: %s\nLocation: %s",
                        item.id or "Unknown",
                        item.user_name or "Unknown",
                        item.start_time or "Unknown",
                        item.duration or "Unknown",
                        item.size or "Unknown",
                        item.status_full or item.status or "Unknown",
                        item.location or "Unknown"
                    )

                    vim.notify(notification_text, vim.log.levels.INFO)
                    -- TODO: Add log retrieval functionality here
                end)

                -- Report success
                context.handle:report({ message = context.success_message, percentage = 100 })
                context.handle:finish()
            end,
            on_error = function(job, return_val)
                local stderr = job:stderr_result()
                deb("Log list job error", { return_val = return_val, stderr = stderr })
                JobUtils.handle_cli_error(return_val, context)
            end,
        })

        job:start()
    end)
end

return LogList
