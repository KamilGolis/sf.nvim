local M = {}

--- Regex patterns for parsing SF CLI version information
M.UPDATE_WARNING_PATTERN = "›%s+Warning:%s+@salesforce/cli%s+update%s+available%s+from%s+([%d%.]+)%s+to%s+([%d%.]+)"
M.VERSION_INFO_PATTERN = "@salesforce/cli/([%d%.]+)%s+([%S]+)%s+(node%-v[%d%.]+)"
M.CURRENT_VERSION_PATTERN = "([%d%.]+)%s+to%s+([%d%.]+)"
M.PLATFORM_PATTERN = "%s+([%S]+)%s+"
M.NODE_VERSION_PATTERN = "(node%-v[%d%.]+)"
M.VERSION_NUMBER_PATTERN = "([%d%.]+)"

--- Font icons for UI elements
M.ICONS = {
  -- Status icons
  SUCCESS = "\u{f00c}",
  ERROR = "\u{f00d}",
  WARNING = "\u{f071}",
  INFO = "\u{f05a}",

  -- Application icons
  BROWSER = "\u{f0ac}",
  API = "\u{f1e6}",
  BATCH = "\u{f085}",
  MOBILE = "\u{f10a}",

  -- Performance icons
  FAST = "\u{f0e7}",
  MEDIUM = "\u{f252}",
  SLOW = "\u{f0e4}",

  -- Size icons
  LARGE_FILE = "\u{f0f6}",
  MEDIUM_FILE = "\u{f016}",
  SMALL_FILE = "\u{f0c5}",

  -- General icons
  LOG_ID = "\u{f2c2}",
  USER = "\u{f007}",
  TIME = "\u{f073}",
  DURATION = "\u{f017}",
  SIZE = "\u{f0ae}",
  OPERATION = "\u{f021}",
  REQUEST = "\u{f233}",
  LOCATION = "\u{f041}",
  URL = "\u{f0ac}",
  METADATA = "\u{f1c0}",
  TYPE = "\u{f02b}",
  LOG_INFO = "\u{f0f6}",
  TECHNICAL = "\u{f0ad}",
  STATE = "\u{f013}",
  FILE = "\u{f07b}",
  LINK = "\u{f0c1}",
}

--- Debug level field definitions with valid values and defaults.
--- Used by debug level new/edit commands for interactive editing.
M.DEBUG_LEVEL_FIELDS = {
  { name = "DeveloperName", label = "Log Level Name", values = nil, default = "Default", readonly_edit = true },
  {
    name = "ApexCode",
    label = "Apex Code",
    values = { "NONE", "ERROR", "WARN", "INFO", "DEBUG", "FINE", "FINER", "FINEST" },
    default = "DEBUG",
  },
  { name = "ApexProfiling", label = "Apex Profiling", values = { "NONE", "INFO", "FINE", "FINEST" }, default = "INFO" },
  { name = "Callout", label = "Callout", values = { "NONE", "ERROR", "INFO", "FINER", "FINEST" }, default = "INFO" },
  { name = "DataAccess", label = "Data Access", values = { "NONE" }, default = "NONE" },
  { name = "Database", label = "Database", values = { "NONE", "WARN", "INFO", "FINE", "FINEST" }, default = "INFO" },
  { name = "Nba", label = "NBA", values = { "NONE", "ERROR", "INFO", "FINE" }, default = "INFO" },
  { name = "System", label = "System", values = { "NONE", "INFO", "DEBUG", "FINE" }, default = "DEBUG" },
  { name = "Validation", label = "Validation", values = { "NONE", "INFO" }, default = "INFO" },
  { name = "Visualforce", label = "Visualforce", values = { "NONE", "INFO", "FINE", "FINER" }, default = "INFO" },
  { name = "Wave", label = "Wave", values = { "NONE", "ERROR", "INFO", "FINE", "FINER", "FINEST" }, default = "INFO" },
  {
    name = "Workflow",
    label = "Workflow",
    values = { "NONE", "ERROR", "WARN", "INFO", "FINE", "FINER" },
    default = "INFO",
  },
}

--- String format templates for displaying Salesforce org details
M.ORG_DETAILS_FORMAT = {
  HEADER = "Selected Org Information:",
  ALIAS = "Alias: %s",
  INSTANCE_URL = "Instance URL: %s",
  USERNAME = "Username: %s",
  ORG_ID = "Org ID: %s",
  CONNECTED_STATUS = "Connected Status: %s",
  IS_DEFAULT = "Is Default: %s",
  IS_DEVHUB = "Is DevHub: %s",
  IS_SANDBOX = "Is Sandbox: %s",
  API_VERSION = "API Version: %s",
}

--- Messages for SF CLI connection and org operations
M.SF_CLI_MESSAGES = {
  NOT_FOUND = "SF CLI not found. Please install it.",
  VERSION_CHECK_TITLE = "Checking SF CLI version.",
  VERSION_CHECK_FAILED = "Failed to execute SF CLI command.",
  VERSION_FOUND_FORMAT = "SF CLI is installed at %s. Version: %s, Platform: %s, Node: %s.",
  VERSION_UPDATE_FORMAT = "\nUpdate available: %s.",
  VERSION_UNKNOWN = "SF CLI found, but unable to determine version.",
  ORG_LIST_TITLE = "Refreshing Salesforce org list.",
  ORG_LIST_FAILED = "Failed to fetch org list.",
  ORG_LIST_EMPTY = "orgs.json file is empty.",
  ORG_LIST_SUCCESS = "Org list fetched successfully.",
  ORG_SET_TITLE = "Setting default org.",
  ORG_SET_SUCCESS = "Default org set successfully.",
  ORG_SET_FAILED = "Failed to set default org.",
  ORG_SET_SUCCESS_FORMAT = "Default org set to: %s.",
  ORG_SET_ERROR = "Error: Failed to set default org.",
  JSON_PARSE_ERROR = "Failed to parse orgs.json or invalid format.",
  -- Log list messages
  LOG_LIST_TITLE = "Fetching Salesforce debug logs.",
  LOG_LIST_SUCCESS = "Debug logs fetched successfully.",
  LOG_LIST_FAILED = "Failed to fetch debug logs.",
  LOG_LIST_EMPTY = "No debug logs found.",
  LOG_RETRIEVE_TITLE = "Fetching Salesforce debug log.",
  LOG_RETRIEVE_SUCCESS = "Debug log retrieved successfully.",
  LOG_RETRIEVE_FAILED = "Failed to retrieve debug log.",
  LOG_NOT_IN_CACHE = "Selected log not found in cached list. Refreshing...",
  NO_DEFAULT_ORG = "No default org set. Please set a default org first using ':Sf org set'.",
  -- Schema refresh messages
  SCHEMA_REFRESH_TITLE = "Refreshing org metadata types.",
  SCHEMA_REFRESH_SUCCESS = "Metadata types fetched successfully.",
  SCHEMA_REFRESH_FAILED = "Failed to fetch metadata types.",
  -- Schema retrieve messages
  SCHEMA_RETRIEVE_TITLE = "Retrieving metadata info.",
  SCHEMA_RETRIEVE_SUCCESS = "Metadata info retrieved successfully.",
  SCHEMA_RETRIEVE_FAILED = "Failed to retrieve metadata info.",
  -- Retrieve messages
  RETRIEVE_TITLE = "Retrieving metadata from org.",
  RETRIEVE_SUCCESS = "Metadata retrieved successfully.",
  RETRIEVE_FAILED = "Failed to retrieve metadata.",
  RETRIEVE_MANIFEST_CREATED = "Generated manifest for %d items.",
  RETRIEVE_CONFLICT = "Source conflicts detected during retrieval.",
  RETRIEVE_WARNING = "Retrieval completed with warnings.",
  RETRIEVE_WITH_ISSUES = "Metadata retrieval completed with issues.",
  -- Debug level messages
  DEBUG_LEVEL_NEW_TITLE = "Creating debug level.",
  DEBUG_LEVEL_NEW_SUCCESS = "Debug level created successfully.",
  DEBUG_LEVEL_NEW_FAILED = "Failed to create debug level.",
  DEBUG_LEVEL_DELETE_TITLE = "Deleting debug level.",
  DEBUG_LEVEL_DELETE_SUCCESS = "Debug level deleted successfully.",
  DEBUG_LEVEL_DELETE_FAILED = "Failed to delete debug level.",
  DEBUG_LEVEL_EDIT_TITLE = "Updating debug level.",
  DEBUG_LEVEL_EDIT_SUCCESS = "Debug level updated successfully.",
  DEBUG_LEVEL_EDIT_FAILED = "Failed to update debug level.",
  DEBUG_LEVEL_WORKFLOW_TITLE = "Fetching org debug data.",
  DEBUG_LEVEL_WORKFLOW_SUCCESS = "Debug data fetched.",
  DEBUG_LEVEL_WORKFLOW_FAILED = "Failed to fetch debug data.",
  DEBUG_LEVEL_FETCHING_ORG = "Fetching org info.",
  DEBUG_LEVEL_FETCHING_USER = "Fetching user info.",
  DEBUG_LEVEL_FETCHING_LEVELS = "Fetching debug levels.",
  DEBUG_LEVEL_FETCHING_TRACES = "Fetching trace flags.",
  DEBUG_LEVEL_NO_FIELD_DATA = "No field data to save",
  DEBUG_LEVEL_NO_TARGET_ORG = "No target org configured for save",
  DEBUG_LEVEL_READONLY_WARN = "DeveloperName cannot be changed after creation",
  DEBUG_LEVEL_NONE_FOUND = "No debug levels found",
  DEBUG_LEVEL_NOT_FOUND_ERROR = "Could not find selected debug level",
  DEBUG_LEVEL_NO_ID = "Selected debug level has no Id",
  -- Trace flag messages
  TRACE_NEW_TITLE = "Creating trace flag.",
  TRACE_NEW_SUCCESS = "Trace flag created successfully.",
  TRACE_NEW_FAILED = "Failed to create trace flag.",
  TRACE_REFRESH_TITLE = "Refreshing trace flag.",
  TRACE_REFRESH_SUCCESS = "Trace flag refreshed successfully.",
  TRACE_REFRESH_FAILED = "Failed to refresh trace flag.",
  TRACE_NO_DEBUG_LEVEL = "No debug level selected. Select one before saving.",
  TRACE_INVALID_DATE_FORMAT = "Invalid date format. Use dd.mm.yyyy HH:MM.",
  TRACE_NO_TRACE_FLAGS = "No trace flags found for this user.",
  TRACE_NOT_FOUND_ERROR = "Could not find selected trace flag.",
  TRACE_OVERLAP_DELETING = "Removing conflicting trace flag before creating new one.",
  TRACE_OVERLAP_RETRYING = "Retrying trace flag creation after deletion.",
  TRACE_NO_STATE = "No trace state found",
  TRACE_DELETE_TITLE = "Deleting trace flag.",
  TRACE_DELETE_SUCCESS = "Trace flag deleted successfully.",
  TRACE_DELETE_FAILED = "Failed to delete trace flag.",
  TRACE_DELETE_CONFLICT_FAILED = "Failed to delete conflicting trace flag",
  DEBUG_LEVEL_SAVE_FAILED = "Failed to save debug level",
  TRACE_SAVE_IN_PROGRESS = "Trace flag save already in progress",
  TRACE_DELETE_IN_PROGRESS = "Trace flag delete already in progress",
  DEBUG_LEVEL_SAVE_IN_PROGRESS = "Debug level save already in progress",
  DEBUG_LEVEL_DELETE_IN_PROGRESS = "Debug level delete already in progress",
  -- Anonymous Apex execute messages
  APEX_EXECUTE_TITLE = "Executing Anonymous Apex.",
  APEX_EXECUTE_SUCCESS = "Anonymous Apex executed successfully.",
  APEX_EXECUTE_FAILED = "Failed to execute Anonymous Apex.",
  APEX_EXECUTE_COMPILE_ERROR = "Compilation failed.",
  APEX_EXECUTE_RUNTIME_ERROR = "Runtime exception.",
  APEX_EXECUTE_NEW_FAILED = "Failed to create scripts directory.",
  APEX_EXECUTE_CLEANUP_TITLE = "Cleaning up apex temp files.",
  APEX_EXECUTE_CLEANUP_SUCCESS = "Temp files cleaned up.",
  APEX_LIST_NO_SCRIPTS = "No Apex scripts found in scripts directory.",
  APEX_LIST_DIR_MISSING = "Scripts directory does not exist.",
}

--- SF code actions configuration
M.SF_ACTIONS = {
  -- LSP client settings
  CLIENT_NAME = "sf-actions",
  SERVER_NAME = "sf.nvim",
  AUGROUP = "sf_actions",

  -- Command identifiers
  CMD_RUN_CLASS = "sf.test.runClass",
  CMD_RUN_METHOD = "sf.test.runMethod",
  CMD_RUN_CLASS_COVERAGE = "sf.test.runClassCoverage",
  CMD_RUN_METHOD_COVERAGE = "sf.test.runMethodCoverage",

  -- Action titles
  TITLE_RUN_TEST_CLASS = "Sf: Run Test Class",
  TITLE_RUN_TEST_CLASS_COVERAGE = "Sf: Run Test Class with Coverage",
  TITLE_RUN_TEST_METHOD = "Sf: Run Test Method",
  TITLE_RUN_TEST_METHOD_COVERAGE = "Sf: Run Test Method with Coverage",

  -- Messages
  NO_ACTIONS = "No test actions available for this file",
  CLIENT_FAILED = "sf.nvim: Failed to start test actions LSP client",

  -- Picker
  PICKER_TITLE = "Test Actions",
}

--- Salesforce CLI commands and their arguments
--- Supported commands:
--- - sf --version
--- - sf project generate -n [name] -d [path] --api-version [version] -t empty
--- - sf project deploy start -d [source] --json -a [version] [--verbose] [-c]
--- - sf project deploy start -x [manifest] --json -a [version] [--verbose] [-c]
--- - sf project retrieve start -m [type:name [type:name ...]] --json -a [version] -c [-o target-org]
--- - sf project retrieve start -x [manifest] --json -a [version] -c [-o target-org]
--- - sf sgd source delta -c --from HEAD --output-dir [path]
--- - sf org list --json
--- - sf config set target-org [target-org]
--- - sf org list metadata-types --json [-o target-org]
--- - sf org list metadata -m [type] --json [-o target-org]
--- - sf apex run test -y -n [class] --json [-c]
--- - sf apex run test -y -t [method] --json [-c]
--- - sf apex list log --json [-o target-org]
--- - sf apex get log -d [dir] -i [id]
M.SF_CLI = {
  VERSION = {
    CMD = "--version",
  },
  PROJECT = {
    GENERATE = {
      CMD = "project generate",
      ARGS = {
        NAME = "-n",
        OUTPUT_DIR = "-d",
        API_VERSION = "--api-version",
        TEMPLATE = "-t",
        TEMPLATE_TYPE = "empty",
      },
    },
    DEPLOY = {
      CMD = "project deploy start",
      ARGS = {
        SOURCE_DIR = "-d",
        JSON = "--json",
        API_VERSION = "-a",
        VERBOSE = "--verbose",
        MANIFEST = "-x",
        IGNORE_CONFLICTS = "-c",
      },
    },
    RETRIEVE = {
      CMD = "project retrieve start",
      ARGS = {
        METADATA = "-m",
        MANIFEST = "-x",
        JSON = "--json",
        API_VERSION = "-a",
        IGNORE_CONFLICTS = "-c",
        TARGET_METADATA_DIR = "--target-metadata-dir",
        UNZIP = "--unzip",
        TARGET_ORG = "-o",
      },
    },
    CONVERT = {
      CMD = "project convert mdapi",
      ARGS = {
        ROOT_DIR = "--root-dir",
        OUTPUT_DIR = "--output-dir",
        JSON = "--json",
      },
    },
  },
  SGD = {
    SOURCE = {
      DELTA = {
        CMD = "sgd source delta",
        ARGS = {
          COMPARE = "-c",
          FROM = "--from",
          OUTPUT_DIR = "--output-dir",
          HEAD_REF = "HEAD",
        },
      },
    },
  },
  ORG = {
    LIST = {
      CMD = "org list",
      ARGS = {
        JSON = "--json",
      },
    },
    CONFIG = {
      SET = {
        CMD = "config set",
        ARGS = {
          TARGET_ORG = "target-org",
        },
      },
    },
    LIST_METADATA_TYPES = {
      CMD = "org list metadata-types",
      ARGS = {
        JSON = "--json",
        TARGET_ORG = "-o",
      },
    },
    LIST_METADATA = {
      CMD = "org list metadata",
      ARGS = {
        METADATA_TYPE = "-m",
        JSON = "--json",
        TARGET_ORG = "-o",
      },
    },
  },
  APEX = {
    RUN = {
      TEST = {
        CMD = "apex run test",
        ARGS = {
          SYNCHRONOUS = "-y",
          CLASS_NAMES = "-n",
          TESTS = "-t",
          COVERAGE = "-c",
          JSON = "--json",
        },
      },
    },
    LOG = {
      LIST = {
        CMD = "apex list log",
        ARGS = {
          JSON = "--json",
          TARGET_ORG = "-o",
        },
      },
      GET = {
        CMD = "apex get log",
        ARGS = {
          LOG_DIR = "-d",
          LOG_ID = "-i",
        },
      },
      ANALYZE = {
        INDENT_UNIT = "  ",
        BUF_FILETYPE = "sflog",
      },
    },
    ANONYMOUS = {
      CMD = "apex run",
      ARGS = {
        FILE = "--file",
        TARGET_ORG = "--target-org",
        API_VERSION = "--api-version",
        JSON = "--json",
      },
    },
  },
  DATA = {
    ORG_DISPLAY = {
      CMD = "org display",
      ARGS = {
        TARGET_ORG = "-o",
        JSON = "--json",
      },
    },
    RECORD_GET = {
      CMD = "data record get",
      ARGS = {
        SOBJECT = "-s",
        WHERE = "-w",
        TARGET_ORG = "-o",
        JSON = "--json",
        TOOLING = "-t",
        API_VERSION = "--api-version",
      },
    },
    QUERY = {
      CMD = "data query",
      ARGS = {
        QUERY = "-q",
        TARGET_ORG = "-o",
        TOOLING = "-t",
        JSON = "--json",
        API_VERSION = "--api-version",
      },
    },
    RECORD_CREATE = {
      CMD = "data create record",
      ARGS = {
        SOBJECT = "-s",
        VALUES = "-v",
        TOOLING = "-t",
        TARGET_ORG = "-o",
        API_VERSION = "--api-version",
        JSON = "--json",
      },
    },
    RECORD_UPDATE = {
      CMD = "data update record",
      ARGS = {
        SOBJECT = "-s",
        VALUES = "-v",
        RECORD_ID = "-i",
        TOOLING = "-t",
        TARGET_ORG = "-o",
        API_VERSION = "--api-version",
        JSON = "--json",
      },
    },
    RECORD_DELETE = {
      CMD = "data delete record",
      ARGS = {
        SOBJECT = "-s",
        RECORD_ID = "-i",
        TOOLING = "-t",
        TARGET_ORG = "-o",
        API_VERSION = "--api-version",
        JSON = "--json",
      },
    },
  },
}

--- Git commands and their arguments
M.GIT = {
  CHECK_REPO = {
    CMD = "rev-parse",
    ARGS = "--is-inside-work-tree",
  },
  STATUS = {
    CMD = "status",
    ARGS = "--porcelain",
  },
}

--- Shell commands and their arguments
M.SHELL = {
  BASH = {
    CMD = "bash",
    ARGS = {
      COMMAND = "-c",
    },
  },
}

--- Generates formatted lines for org details preview
--- Generates formatted preview lines for org details display
--- @param org table The org object containing details (alias, instanceUrl, username, etc.)
--- @return table A list of formatted strings for org details display
--- @usage local lines = Const.generate_org_preview_lines(org_data)
function M.generate_org_preview_lines(org)
  return {
    M.ORG_DETAILS_FORMAT.HEADER,
    string.format(M.ORG_DETAILS_FORMAT.ALIAS, org.alias or "N/A"),
    string.format(M.ORG_DETAILS_FORMAT.INSTANCE_URL, org.instanceUrl),
    string.format(M.ORG_DETAILS_FORMAT.USERNAME, org.username),
    string.format(M.ORG_DETAILS_FORMAT.ORG_ID, org.orgId),
    string.format(M.ORG_DETAILS_FORMAT.CONNECTED_STATUS, org.connectedStatus),
    string.format(M.ORG_DETAILS_FORMAT.IS_DEFAULT, org.isDefaultUsername and "Yes" or "No"),
    string.format(M.ORG_DETAILS_FORMAT.IS_DEVHUB, org.isDevHub and "Yes" or "No"),
    string.format(M.ORG_DETAILS_FORMAT.IS_SANDBOX, org.isSandbox and "Yes" or "No"),
    string.format(M.ORG_DETAILS_FORMAT.API_VERSION, org.instanceApiVersion),
  }
end

--- Splits a command string into a table of arguments by spaces
--- @param cmd string The command string to split
--- @return table A list of command parts split by spaces
--- @usage local parts = split_cmd("sf project generate") -- returns {"sf", "project", "generate"}
local function split_cmd(cmd)
  return vim.split(cmd, " ")
end

--- Constructs arguments for SF CLI project generation command
--- @param options table Configuration options containing temp_project_name, cache_path, and api_version
--- @return table Complete argument list for sf project generate command
--- @usage local args = Const.get_project_generate_args({temp_project_name = "temp", cache_path = "/tmp"})
function M.get_project_generate_args(options)
  local args = {}

  -- Add the base command
  vim.list_extend(args, split_cmd(M.SF_CLI.PROJECT.GENERATE.CMD))

  -- Add the required arguments
  vim.list_extend(args, {
    M.SF_CLI.PROJECT.GENERATE.ARGS.NAME,
    options.temp_project_name,
    M.SF_CLI.PROJECT.GENERATE.ARGS.OUTPUT_DIR,
    options.cache_path,
    M.SF_CLI.PROJECT.GENERATE.ARGS.API_VERSION,
    options.api_version,
    M.SF_CLI.PROJECT.GENERATE.ARGS.TEMPLATE,
    M.SF_CLI.PROJECT.GENERATE.ARGS.TEMPLATE_TYPE,
  })

  return args
end

--- Constructs arguments for git repository check command
--- @return table Complete argument list for git rev-parse command
--- @usage local args = Const.get_git_check_repo_args()
function M.get_git_check_repo_args()
  return {
    M.GIT.CHECK_REPO.CMD,
    M.GIT.CHECK_REPO.ARGS,
  }
end

--- Constructs arguments for git status check command
--- @return table Complete argument list for git status command
--- @usage local args = Const.get_git_status_args()
function M.get_git_status_args()
  return {
    M.GIT.STATUS.CMD,
    M.GIT.STATUS.ARGS,
  }
end

--- Constructs arguments for SF CLI current file deployment command
--- @param current_file string The path to the current file to deploy
--- @param api_version string The Salesforce API version to use
--- @param force boolean|nil Whether to ignore conflicts (optional)
--- @return table Complete argument list for sf project deploy start command
--- @usage local args = Const.get_current_file_deploy_args("force-app/main/default/classes/Test.cls", "58.0", true)
function M.get_current_file_deploy_args(current_file, api_version, force)
  local args = {}

  -- Add the base command
  vim.list_extend(args, split_cmd(M.SF_CLI.PROJECT.DEPLOY.CMD))

  -- Add the required arguments
  vim.list_extend(args, {
    M.SF_CLI.PROJECT.DEPLOY.ARGS.SOURCE_DIR,
    current_file,
    M.SF_CLI.PROJECT.DEPLOY.ARGS.JSON,
    M.SF_CLI.PROJECT.DEPLOY.ARGS.API_VERSION,
    api_version,
  })

  -- Add ignore conflicts flag if force is enabled
  if force then
    table.insert(args, M.SF_CLI.PROJECT.DEPLOY.ARGS.IGNORE_CONFLICTS)
  end

  return args
end

--- Constructs arguments for SF CLI manifest-based deployment command
--- @param manifest_path string The path to the manifest file
--- @param api_version string The Salesforce API version to use
--- @param force boolean|nil Whether to ignore conflicts (optional)
--- @return table Complete argument list for sf project deploy start command with manifest
--- @usage local args = Const.get_manifest_deploy_args("manifest/package.xml", "58.0", true)
function M.get_manifest_deploy_args(manifest_path, api_version, force)
  local args = {}

  -- Add the base command
  vim.list_extend(args, split_cmd(M.SF_CLI.PROJECT.DEPLOY.CMD))

  -- Add the required arguments
  vim.list_extend(args, {
    M.SF_CLI.PROJECT.DEPLOY.ARGS.MANIFEST,
    manifest_path,
    M.SF_CLI.PROJECT.DEPLOY.ARGS.JSON,
    M.SF_CLI.PROJECT.DEPLOY.ARGS.API_VERSION,
    api_version,
  })

  -- Add ignore conflicts flag if force is enabled
  if force then
    table.insert(args, M.SF_CLI.PROJECT.DEPLOY.ARGS.IGNORE_CONFLICTS)
  end

  return args
end

--- Constructs complete SGD source delta command string for git diff operations
--- @param output_dir string The output directory for the delta files
--- @return string Complete command string for sf sgd source delta
--- @usage local cmd = Const.get_sgd_delta_command("/tmp/delta")
function M.get_sgd_delta_command(output_dir)
  return string.format(
    "%s %s %s %s %s %s",
    "sf",
    M.SF_CLI.SGD.SOURCE.DELTA.CMD,
    M.SF_CLI.SGD.SOURCE.DELTA.ARGS.COMPARE,
    M.SF_CLI.SGD.SOURCE.DELTA.ARGS.FROM .. ' "' .. M.SF_CLI.SGD.SOURCE.DELTA.ARGS.HEAD_REF .. '"',
    M.SF_CLI.SGD.SOURCE.DELTA.ARGS.OUTPUT_DIR,
    output_dir
  )
end

--- Constructs arguments for bash command execution
--- @param command string The command to execute with bash
--- @return table Complete argument list for bash -c command
--- @usage local args = Const.get_bash_command_args("echo 'hello world'")
function M.get_bash_command_args(command)
  return {
    M.SHELL.BASH.ARGS.COMMAND,
    command,
  }
end

--- Constructs arguments for SF CLI Apex test execution by class name
--- @param class_name string The name of the test class to run
--- @param with_coverage boolean|nil Whether to include coverage report (optional)
--- @return table Complete argument list for sf apex run test command
--- @usage local args = Const.get_apex_test_class_args("MyTestClass", true)
function M.get_apex_test_class_args(class_name, with_coverage)
  local args = {}

  -- Add the base command
  vim.list_extend(args, split_cmd(M.SF_CLI.APEX.RUN.TEST.CMD))

  -- Add the required arguments
  vim.list_extend(args, {
    M.SF_CLI.APEX.RUN.TEST.ARGS.SYNCHRONOUS,
    M.SF_CLI.APEX.RUN.TEST.ARGS.CLASS_NAMES,
    class_name,
    M.SF_CLI.APEX.RUN.TEST.ARGS.JSON,
  })

  -- Add coverage flag if requested
  if with_coverage then
    table.insert(args, M.SF_CLI.APEX.RUN.TEST.ARGS.COVERAGE)
  end

  return args
end

--- Constructs arguments for SF CLI Apex test execution by test method
--- @param test_name string The name of the test method in format "ClassName.methodName"
--- @param with_coverage boolean|nil Whether to include coverage report (optional)
--- @return table Complete argument list for sf apex run test command
--- @usage local args = Const.get_apex_test_method_args("MyTestClass.testMethod", true)
function M.get_apex_test_method_args(test_name, with_coverage)
  local args = {}

  -- Add the base command
  vim.list_extend(args, split_cmd(M.SF_CLI.APEX.RUN.TEST.CMD))

  -- Add the required arguments
  vim.list_extend(args, {
    M.SF_CLI.APEX.RUN.TEST.ARGS.SYNCHRONOUS,
    M.SF_CLI.APEX.RUN.TEST.ARGS.TESTS,
    test_name,
    M.SF_CLI.APEX.RUN.TEST.ARGS.JSON,
  })

  -- Add coverage flag if requested
  if with_coverage then
    table.insert(args, M.SF_CLI.APEX.RUN.TEST.ARGS.COVERAGE)
  end

  return args
end

--- Constructs arguments for SF CLI Apex log list command
--- @param target_org string|nil The target org username (optional, uses default if not provided)
--- @return table Complete argument list for sf apex list log command
--- @usage local args = Const.get_apex_log_list_args("user@example.com")
function M.get_apex_log_list_args(target_org)
  local args = {}

  -- Add the base command
  local cmd_parts = split_cmd(M.SF_CLI.APEX.LOG.LIST.CMD)
  for _, part in ipairs(cmd_parts) do
    table.insert(args, part)
  end

  -- Add JSON flag
  table.insert(args, M.SF_CLI.APEX.LOG.LIST.ARGS.JSON)

  -- Add target org if provided
  if target_org then
    table.insert(args, M.SF_CLI.APEX.LOG.LIST.ARGS.TARGET_ORG)
    table.insert(args, target_org)
  end

  return args
end

--- Constructs arguments for SF CLI Apex log retrieval command
--- @param log_dir string The directory to store the downloaded log file
--- @param log_id string The ID of the log to retrieve
--- @return table Complete argument list for sf apex get log command
--- @usage local args = Const.get_apex_log_get_args("/tmp/logs", "07L9b00000M4vUTEAZ")
function M.get_apex_log_get_args(log_dir, log_id)
  local args = {}
  local cmd_parts = split_cmd(M.SF_CLI.APEX.LOG.GET.CMD)

  for _, part in ipairs(cmd_parts) do
    table.insert(args, part)
  end

  table.insert(args, M.SF_CLI.APEX.LOG.GET.ARGS.LOG_DIR)
  table.insert(args, log_dir)
  table.insert(args, M.SF_CLI.APEX.LOG.GET.ARGS.LOG_ID)
  table.insert(args, log_id)
  return args
end

--- Constructs arguments for SF CLI org list command
--- @return table Complete argument list for sf org list --json
function M.get_org_list_args()
  local args = {}
  vim.list_extend(args, split_cmd(M.SF_CLI.ORG.LIST.CMD))
  vim.list_extend(args, { M.SF_CLI.ORG.LIST.ARGS.JSON })
  return args
end

--- Constructs arguments for SF CLI config set target-org command
--- @param username string The org username to set as target
--- @return table Complete argument list for sf config set target-org [username]
function M.get_config_set_args(username)
  local args = {}
  vim.list_extend(args, split_cmd(M.SF_CLI.ORG.CONFIG.SET.CMD))
  vim.list_extend(args, { M.SF_CLI.ORG.CONFIG.SET.ARGS.TARGET_ORG, username })
  return args
end

--- Constructs arguments for SF CLI org list metadata-types command
--- @param target_org string|nil Optional target org username (uses default if nil)
function M.get_org_list_metadata_types_args(target_org)
  local args = {}
  vim.list_extend(args, split_cmd(M.SF_CLI.ORG.LIST_METADATA_TYPES.CMD))
  vim.list_extend(args, { M.SF_CLI.ORG.LIST_METADATA_TYPES.ARGS.JSON })
  if target_org then
    vim.list_extend(args, { M.SF_CLI.ORG.LIST_METADATA_TYPES.ARGS.TARGET_ORG, target_org })
  end
  return args
end

--- Constructs arguments for SF CLI org list metadata command
--- @param xml_name string The metadata type xmlName (e.g. "ApexClass")
--- @param target_org string|nil Optional target org username (uses default if nil)
--- @return table Complete argument list for sf org list metadata -m <xmlName> --json
function M.get_org_list_metadata_args(xml_name, target_org)
  local args = {}
  vim.list_extend(args, split_cmd(M.SF_CLI.ORG.LIST_METADATA.CMD))
  vim.list_extend(args, {
    M.SF_CLI.ORG.LIST_METADATA.ARGS.METADATA_TYPE,
    xml_name,
    M.SF_CLI.ORG.LIST_METADATA.ARGS.JSON,
  })
  if target_org then
    vim.list_extend(args, { M.SF_CLI.ORG.LIST_METADATA.ARGS.TARGET_ORG, target_org })
  end
  return args
end

--- Constructs arguments for SF sgd source delta command
--- @param output_dir string The output directory for delta files
--- @return table Complete argument list for sf sgd source delta
function M.get_sgd_delta_args(output_dir)
  local args = {}
  vim.list_extend(args, split_cmd(M.SF_CLI.SGD.SOURCE.DELTA.CMD))
  vim.list_extend(args, {
    M.SF_CLI.SGD.SOURCE.DELTA.ARGS.COMPARE,
    M.SF_CLI.SGD.SOURCE.DELTA.ARGS.FROM,
    M.SF_CLI.SGD.SOURCE.DELTA.ARGS.HEAD_REF,
    M.SF_CLI.SGD.SOURCE.DELTA.ARGS.OUTPUT_DIR,
    output_dir,
  })
  return args
end

--- Constructs arguments for sf project retrieve start using individual -m flags.
--- Each item is formatted as "<xmlName>:<fullName>" (e.g. "ApexClass:MyClass").
--- @param items table Array of { fullName = "...", type_name = "..." } items
--- @param api_version string The Salesforce API version (e.g. "65.0")
--- @param target_org string|nil Optional target org username
--- @return table Complete argument list
function M.get_project_retrieve_args(items, api_version, target_org)
  local args = {}
  vim.list_extend(args, split_cmd(M.SF_CLI.PROJECT.RETRIEVE.CMD))
  for _, item in ipairs(items) do
    vim.list_extend(args, { M.SF_CLI.PROJECT.RETRIEVE.ARGS.METADATA, item.type_name .. ":" .. item.fullName })
  end
  vim.list_extend(args, { M.SF_CLI.PROJECT.RETRIEVE.ARGS.JSON })
  vim.list_extend(args, { M.SF_CLI.PROJECT.RETRIEVE.ARGS.API_VERSION, api_version })
  vim.list_extend(args, { M.SF_CLI.PROJECT.RETRIEVE.ARGS.IGNORE_CONFLICTS })
  if target_org then
    vim.list_extend(args, { M.SF_CLI.PROJECT.RETRIEVE.ARGS.TARGET_ORG, target_org })
  end
  return args
end

--- Constructs arguments for sf project retrieve start using a manifest file.
--- @param manifest_path string Path to the manifest XML file
--- @param api_version string The Salesforce API version (e.g. "65.0")
--- @param target_org string|nil Optional target org username
--- @return table Complete argument list
function M.get_project_retrieve_manifest_args(manifest_path, api_version, target_org)
  local args = {}
  vim.list_extend(args, split_cmd(M.SF_CLI.PROJECT.RETRIEVE.CMD))
  vim.list_extend(args, { M.SF_CLI.PROJECT.RETRIEVE.ARGS.MANIFEST, manifest_path })
  vim.list_extend(args, { M.SF_CLI.PROJECT.RETRIEVE.ARGS.JSON })
  vim.list_extend(args, { M.SF_CLI.PROJECT.RETRIEVE.ARGS.API_VERSION, api_version })
  vim.list_extend(args, { M.SF_CLI.PROJECT.RETRIEVE.ARGS.IGNORE_CONFLICTS })
  if target_org then
    vim.list_extend(args, { M.SF_CLI.PROJECT.RETRIEVE.ARGS.TARGET_ORG, target_org })
  end
  return args
end

--- Constructs arguments for sf project retrieve start using a single metadata type.
--- Retrieves ALL items of the given type without listing individual items.
--- @param xml_name string The metadata type xmlName (e.g. "ApexClass")
--- @param api_version string The Salesforce API version (e.g. "65.0")
--- @param target_org string|nil Optional target org username
--- @return table Complete argument list
function M.get_project_retrieve_type_args(xml_name, api_version, target_org)
  local args = {}
  vim.list_extend(args, split_cmd(M.SF_CLI.PROJECT.RETRIEVE.CMD))
  vim.list_extend(args, { M.SF_CLI.PROJECT.RETRIEVE.ARGS.METADATA, xml_name })
  vim.list_extend(args, { M.SF_CLI.PROJECT.RETRIEVE.ARGS.JSON })
  vim.list_extend(args, { M.SF_CLI.PROJECT.RETRIEVE.ARGS.API_VERSION, api_version })
  vim.list_extend(args, { M.SF_CLI.PROJECT.RETRIEVE.ARGS.IGNORE_CONFLICTS })
  if target_org then
    vim.list_extend(args, { M.SF_CLI.PROJECT.RETRIEVE.ARGS.TARGET_ORG, target_org })
  end
  return args
end

--- Constructs arguments for sf project retrieve start in metadata API format.
--- Used by the diff command: retrieves to --target-metadata-dir, then project convert mdapi converts to source format.
--- @param metadata_type string The metadata type xmlName (e.g. "ApexClass")
--- @param member_name string The member name (e.g. "MyClass")
--- @param output_dir string The target metadata directory (from vim.fn.tempname())
--- @param target_org string|nil Optional target org username
--- @return table Complete argument list
function M.get_diff_retrieve_args(metadata_type, member_name, output_dir, target_org)
  local args = {}
  vim.list_extend(args, split_cmd(M.SF_CLI.PROJECT.RETRIEVE.CMD))
  vim.list_extend(args, { M.SF_CLI.PROJECT.RETRIEVE.ARGS.METADATA, metadata_type .. ":" .. member_name })
  vim.list_extend(args, { M.SF_CLI.PROJECT.RETRIEVE.ARGS.TARGET_METADATA_DIR, output_dir })
  vim.list_extend(args, { M.SF_CLI.PROJECT.RETRIEVE.ARGS.UNZIP })
  vim.list_extend(args, { M.SF_CLI.PROJECT.RETRIEVE.ARGS.JSON })
  if target_org then
    vim.list_extend(args, { M.SF_CLI.PROJECT.RETRIEVE.ARGS.TARGET_ORG, target_org })
  end
  return args
end

--- Constructs arguments for sf project convert mdapi to source format.
--- Converts the unpacked metadata format files back to source format for diffing.
--- @param root_dir string Path to unpackaged directory (from the retrieve)
--- @param output_dir string Path to write converted source files
--- @return table Complete argument list
function M.get_diff_convert_args(root_dir, output_dir)
  local args = {}
  vim.list_extend(args, split_cmd(M.SF_CLI.PROJECT.CONVERT.CMD))
  vim.list_extend(args, { M.SF_CLI.PROJECT.CONVERT.ARGS.ROOT_DIR, root_dir })
  vim.list_extend(args, { M.SF_CLI.PROJECT.CONVERT.ARGS.OUTPUT_DIR, output_dir })
  vim.list_extend(args, { M.SF_CLI.PROJECT.CONVERT.ARGS.JSON })
  return args
end

--- Constructs arguments for SF CLI org display command
--- @param target_org string The target org username
--- @return table Complete argument list for sf org display command
function M.get_org_display_args(target_org)
  local args = {}
  vim.list_extend(args, vim.split(M.SF_CLI.DATA.ORG_DISPLAY.CMD, " "))
  vim.list_extend(args, { M.SF_CLI.DATA.ORG_DISPLAY.ARGS.TARGET_ORG, target_org })
  vim.list_extend(args, { M.SF_CLI.DATA.ORG_DISPLAY.ARGS.JSON })
  return args
end

--- Constructs arguments for SF CLI data record get command
--- @param sobject string The SObject type (e.g. "User")
--- @param where string The WHERE clause (e.g. "Username='user@example.com'")
--- @param target_org string The target org username
--- @return table Complete argument list for sf data record get command
function M.get_record_get_args(sobject, where, target_org)
  local args = {}
  vim.list_extend(args, vim.split(M.SF_CLI.DATA.RECORD_GET.CMD, " "))
  vim.list_extend(args, { M.SF_CLI.DATA.RECORD_GET.ARGS.SOBJECT, sobject })
  vim.list_extend(args, { M.SF_CLI.DATA.RECORD_GET.ARGS.WHERE, where })
  vim.list_extend(args, { M.SF_CLI.DATA.RECORD_GET.ARGS.TARGET_ORG, target_org })
  vim.list_extend(args, { M.SF_CLI.DATA.RECORD_GET.ARGS.JSON })
  return args
end

--- Constructs arguments for SF CLI data record get command using Tooling API.
--- @param sobject string The SObject type (e.g. "TraceFlag")
--- @param where string The WHERE clause
--- @param target_org string The target org username
--- @param api_version string|nil The Salesforce API version (optional)
--- @return table Complete argument list
function M.get_tooling_record_get_args(sobject, where, target_org, api_version)
  local args = {}
  vim.list_extend(args, vim.split(M.SF_CLI.DATA.RECORD_GET.CMD, " "))
  vim.list_extend(args, { M.SF_CLI.DATA.RECORD_GET.ARGS.SOBJECT, sobject })
  vim.list_extend(args, { M.SF_CLI.DATA.RECORD_GET.ARGS.WHERE, where })
  vim.list_extend(args, { M.SF_CLI.DATA.RECORD_GET.ARGS.TOOLING })
  vim.list_extend(args, { M.SF_CLI.DATA.RECORD_GET.ARGS.TARGET_ORG, target_org })
  if api_version then
    vim.list_extend(args, { M.SF_CLI.DATA.RECORD_GET.ARGS.API_VERSION, api_version })
  end
  vim.list_extend(args, { M.SF_CLI.DATA.RECORD_GET.ARGS.JSON })
  return args
end

--- Constructs arguments for SF CLI data query command
--- @param query string The SOQL query
--- @param target_org string The target org username
--- @param api_version string|nil The Salesforce API version (optional)
--- @return table Complete argument list for sf data query command with tooling API
function M.get_query_args(query, target_org, api_version)
  local args = {}
  vim.list_extend(args, vim.split(M.SF_CLI.DATA.QUERY.CMD, " "))
  vim.list_extend(args, { M.SF_CLI.DATA.QUERY.ARGS.QUERY, query })
  vim.list_extend(args, { M.SF_CLI.DATA.QUERY.ARGS.TARGET_ORG, target_org })
  vim.list_extend(args, { M.SF_CLI.DATA.QUERY.ARGS.TOOLING })
  if api_version then
    vim.list_extend(args, { M.SF_CLI.DATA.QUERY.ARGS.API_VERSION, api_version })
  end
  vim.list_extend(args, { M.SF_CLI.DATA.QUERY.ARGS.JSON })
  return args
end

--- Constructs arguments for SF CLI data create record command
--- @param target_org string The target org username
--- @param sobject string The SObject name (e.g. "DebugLevel")
--- @param values string The field=value pairs (e.g. "ApexCode=Fine DeveloperName=Test")
--- @param api_version string The Salesforce API version (e.g. "65.0")
--- @return table Complete argument list for sf data create record command
function M.get_record_create_args(target_org, sobject, values, api_version)
  local args = {}
  vim.list_extend(args, vim.split(M.SF_CLI.DATA.RECORD_CREATE.CMD, " "))
  vim.list_extend(args, { M.SF_CLI.DATA.RECORD_CREATE.ARGS.TARGET_ORG, target_org })
  vim.list_extend(args, { M.SF_CLI.DATA.RECORD_CREATE.ARGS.SOBJECT, sobject })
  vim.list_extend(args, { M.SF_CLI.DATA.RECORD_CREATE.ARGS.TOOLING })
  vim.list_extend(args, { M.SF_CLI.DATA.RECORD_CREATE.ARGS.VALUES, values })
  vim.list_extend(args, { M.SF_CLI.DATA.RECORD_CREATE.ARGS.API_VERSION, api_version })
  vim.list_extend(args, { M.SF_CLI.DATA.RECORD_CREATE.ARGS.JSON })
  return args
end

--- Constructs arguments for SF CLI data update record command
--- @param target_org string The target org username
--- @param sobject string The SObject name (e.g. "DebugLevel")
--- @param values string The field=value pairs
--- @param record_id string The record ID to update
--- @param api_version string The Salesforce API version (e.g. "65.0")
--- @return table Complete argument list for sf data update record command
function M.get_record_update_args(target_org, sobject, values, record_id, api_version)
  local args = {}
  vim.list_extend(args, vim.split(M.SF_CLI.DATA.RECORD_UPDATE.CMD, " "))
  vim.list_extend(args, { M.SF_CLI.DATA.RECORD_UPDATE.ARGS.TARGET_ORG, target_org })
  vim.list_extend(args, { M.SF_CLI.DATA.RECORD_UPDATE.ARGS.SOBJECT, sobject })
  vim.list_extend(args, { M.SF_CLI.DATA.RECORD_UPDATE.ARGS.TOOLING })
  vim.list_extend(args, { M.SF_CLI.DATA.RECORD_UPDATE.ARGS.VALUES, values })
  vim.list_extend(args, { M.SF_CLI.DATA.RECORD_UPDATE.ARGS.RECORD_ID, record_id })
  vim.list_extend(args, { M.SF_CLI.DATA.RECORD_UPDATE.ARGS.API_VERSION, api_version })
  vim.list_extend(args, { M.SF_CLI.DATA.RECORD_UPDATE.ARGS.JSON })
  return args
end

--- Constructs arguments for SF CLI data delete record command
--- @param target_org string The target org username
--- @param sobject string The SObject name (e.g. "DebugLevel")
--- @param record_id string The record ID to delete
--- @param api_version string The Salesforce API version (e.g. "65.0")
--- @return table Complete argument list for sf data delete record command
function M.get_record_delete_args(target_org, sobject, record_id, api_version)
  local args = {}
  vim.list_extend(args, vim.split(M.SF_CLI.DATA.RECORD_DELETE.CMD, " "))
  vim.list_extend(args, { M.SF_CLI.DATA.RECORD_DELETE.ARGS.TARGET_ORG, target_org })
  vim.list_extend(args, { M.SF_CLI.DATA.RECORD_DELETE.ARGS.SOBJECT, sobject })
  vim.list_extend(args, { M.SF_CLI.DATA.RECORD_DELETE.ARGS.TOOLING })
  vim.list_extend(args, { M.SF_CLI.DATA.RECORD_DELETE.ARGS.RECORD_ID, record_id })
  vim.list_extend(args, { M.SF_CLI.DATA.RECORD_DELETE.ARGS.API_VERSION, api_version })
  vim.list_extend(args, { M.SF_CLI.DATA.RECORD_DELETE.ARGS.JSON })
  return args
end

--- Constructs arguments for SF CLI data create record command using Tooling API.
--- @param target_org string The target org username
--- @param sobject string The SObject name (e.g. "TraceFlag")
--- @param values string The field=value pairs
--- @param api_version string The Salesforce API version (e.g. "65.0")
--- @return table Complete argument list
function M.get_tooling_record_create_args(target_org, sobject, values, api_version)
  local args = {}
  vim.list_extend(args, vim.split(M.SF_CLI.DATA.RECORD_CREATE.CMD, " "))
  vim.list_extend(args, { M.SF_CLI.DATA.RECORD_CREATE.ARGS.TARGET_ORG, target_org })
  vim.list_extend(args, { M.SF_CLI.DATA.RECORD_CREATE.ARGS.SOBJECT, sobject })
  vim.list_extend(args, { M.SF_CLI.DATA.RECORD_CREATE.ARGS.TOOLING })
  vim.list_extend(args, { M.SF_CLI.DATA.RECORD_CREATE.ARGS.VALUES, values })
  vim.list_extend(args, { M.SF_CLI.DATA.RECORD_CREATE.ARGS.API_VERSION, api_version })
  vim.list_extend(args, { M.SF_CLI.DATA.RECORD_CREATE.ARGS.JSON })
  return args
end

--- Constructs arguments for SF CLI data update record command using Tooling API.
--- @param target_org string The target org username
--- @param sobject string The SObject name (e.g. "TraceFlag")
--- @param values string The field=value pairs
--- @param record_id string The record ID to update
--- @param api_version string The Salesforce API version (e.g. "65.0")
--- @return table Complete argument list
function M.get_tooling_record_update_args(target_org, sobject, values, record_id, api_version)
  local args = {}
  vim.list_extend(args, vim.split(M.SF_CLI.DATA.RECORD_UPDATE.CMD, " "))
  vim.list_extend(args, { M.SF_CLI.DATA.RECORD_UPDATE.ARGS.TARGET_ORG, target_org })
  vim.list_extend(args, { M.SF_CLI.DATA.RECORD_UPDATE.ARGS.SOBJECT, sobject })
  vim.list_extend(args, { M.SF_CLI.DATA.RECORD_UPDATE.ARGS.TOOLING })
  vim.list_extend(args, { M.SF_CLI.DATA.RECORD_UPDATE.ARGS.VALUES, values })
  vim.list_extend(args, { M.SF_CLI.DATA.RECORD_UPDATE.ARGS.RECORD_ID, record_id })
  vim.list_extend(args, { M.SF_CLI.DATA.RECORD_UPDATE.ARGS.API_VERSION, api_version })
  vim.list_extend(args, { M.SF_CLI.DATA.RECORD_UPDATE.ARGS.JSON })
  return args
end

--- Constructs arguments for SF CLI data delete record command using Tooling API.
--- @param target_org string The target org username
--- @param sobject string The SObject name (e.g. "TraceFlag")
--- @param record_id string The record ID to delete
--- @param api_version string The Salesforce API version (e.g. "65.0")
--- @return table Complete argument list
function M.get_tooling_record_delete_args(target_org, sobject, record_id, api_version)
  local args = {}
  vim.list_extend(args, vim.split(M.SF_CLI.DATA.RECORD_DELETE.CMD, " "))
  vim.list_extend(args, { M.SF_CLI.DATA.RECORD_DELETE.ARGS.TARGET_ORG, target_org })
  vim.list_extend(args, { M.SF_CLI.DATA.RECORD_DELETE.ARGS.SOBJECT, sobject })
  vim.list_extend(args, { M.SF_CLI.DATA.RECORD_DELETE.ARGS.TOOLING })
  vim.list_extend(args, { M.SF_CLI.DATA.RECORD_DELETE.ARGS.RECORD_ID, record_id })
  vim.list_extend(args, { M.SF_CLI.DATA.RECORD_DELETE.ARGS.API_VERSION, api_version })
  vim.list_extend(args, { M.SF_CLI.DATA.RECORD_DELETE.ARGS.JSON })
  return args
end

--- Constructs arguments for SF CLI Anonymous Apex execution
--- @param file_path string The path to the apex script file
--- @param api_version string The Salesforce API version to use
--- @param target_org string|nil Optional target org username (uses default if nil)
--- @return table Complete argument list for sf apex run command
--- @usage local args = Const.get_apex_run_args("/tmp/run.apex", "65.0")
function M.get_apex_run_args(file_path, api_version, target_org)
  local args = {}
  vim.list_extend(args, split_cmd(M.SF_CLI.APEX.ANONYMOUS.CMD))
  vim.list_extend(args, {
    M.SF_CLI.APEX.ANONYMOUS.ARGS.FILE,
    file_path,
    M.SF_CLI.APEX.ANONYMOUS.ARGS.API_VERSION,
    api_version,
    M.SF_CLI.APEX.ANONYMOUS.ARGS.JSON,
  })
  if target_org then
    vim.list_extend(args, { M.SF_CLI.APEX.ANONYMOUS.ARGS.TARGET_ORG, target_org })
  end
  return args
end

M.MANIFEST_THRESHOLD = 10
return M
