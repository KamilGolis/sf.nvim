local M = {}

-- =============================================================================
-- REGEX PATTERNS
-- =============================================================================

--- Regex patterns for parsing SF CLI version information
M.UPDATE_WARNING_PATTERN =
"›%s+Warning:%s+@salesforce/cli%s+update%s+available%s+from%s+([%d%.]+)%s+to%s+([%d%.]+)"
M.VERSION_INFO_PATTERN = "@salesforce/cli/([%d%.]+)%s+([%S]+)%s+(node%-v[%d%.]+)"
M.CURRENT_VERSION_PATTERN = "([%d%.]+)%s+to%s+([%d%.]+)"
M.PLATFORM_PATTERN = "%s+([%S]+)%s+"
M.NODE_VERSION_PATTERN = "(node%-v[%d%.]+)"
M.VERSION_NUMBER_PATTERN = "([%d%.]+)"

-- =============================================================================
-- ICONS
-- =============================================================================

--- Font icons for UI elements
M.ICONS = {
  -- Status icons
  SUCCESS = "✅",
  ERROR = "❌", 
  WARNING = "⚠️ ",
  INFO = "ℹ️ ",
  
  -- Application icons
  BROWSER = "🌐",
  API = "🔌",
  BATCH = "⚙️ ",
  MOBILE = "📱",
  
  -- Performance icons
  FAST = "⚡",
  MEDIUM = "⏱️ ",
  SLOW = "🐌",
  
  -- Size icons
  LARGE_FILE = "📊",
  MEDIUM_FILE = "📄",
  SMALL_FILE = "📝",
  
  -- General icons
  LOG_ID = "🆔",
  USER = "👤",
  TIME = "📅",
  DURATION = "⏰",
  SIZE = "📏",
  OPERATION = "⚡",
  REQUEST = "📡",
  LOCATION = "📍",
  URL = "🌐",
  METADATA = "📊",
  TYPE = "🏷️ ",
  LOG_INFO = "📋",
  TECHNICAL = "🔧",
  LINK = "🔗",
}

-- =============================================================================
-- STRING FORMATS
-- =============================================================================

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

-- =============================================================================
-- SF CLI CONNECTION MESSAGES
-- =============================================================================

--- Messages for SF CLI connection and org operations
M.SF_CLI_MESSAGES = {
  NOT_FOUND = "SF CLI not found. Please install it.",
  VERSION_CHECK_TITLE = "Checking SF CLI version",
  VERSION_CHECK_FAILED = "Failed to execute SF CLI command",
  VERSION_FOUND_FORMAT = "SF CLI is installed at %s. Version: %s, Platform: %s, Node: %s",
  VERSION_UPDATE_FORMAT = "\nUpdate available: %s",
  VERSION_UNKNOWN = "SF CLI found, but unable to determine version",
  ORG_LIST_TITLE = "Refreshing Salesforce org list",
  ORG_LIST_FAILED = "Failed to fetch org list",
  ORG_LIST_EMPTY = "orgs.json file is empty",
  ORG_LIST_SUCCESS = "Org list fetched successfully",
  ORG_SET_TITLE = "Setting default org",
  ORG_SET_SUCCESS = "Default org set successfully",
  ORG_SET_FAILED = "Failed to set default org",
  ORG_SET_SUCCESS_FORMAT = "Default org set to: %s",
  ORG_SET_ERROR = "Error: Failed to set default org",
  JSON_PARSE_ERROR = "Failed to parse orgs.json or invalid format",
  -- Log list messages
  LOG_LIST_TITLE = "Fetching Salesforce debug logs",
  LOG_LIST_SUCCESS = "Debug logs fetched successfully",
  LOG_LIST_FAILED = "Failed to fetch debug logs",
  LOG_LIST_EMPTY = "No debug logs found",
  NO_DEFAULT_ORG = "No default org set. Please set a default org first using ':Sf org set'",
}

-- =============================================================================
-- COMMAND DEFINITIONS
-- =============================================================================

--- Salesforce CLI commands and their arguments
--- Supported commands:
--- - sf project generate --name [name] --output-dir [path] --api-version [version] --template empty
--- - sf project deploy start --source-dir [path] --json --api-version [version] --verbose
--- - sf sgd source delta -c --from "HEAD" --output-dir [path]
--- - sf org list --json
--- - sf config set target-org [username]
M.SF_CLI = {
  VERSION = {
    CMD = "--version",
  },
  PROJECT = {
    GENERATE = {
      CMD = "project generate",
      ARGS = {
        NAME = "--name",
        OUTPUT_DIR = "--output-dir",
        API_VERSION = "--api-version",
        TEMPLATE = "--template",
        TEMPLATE_TYPE = "empty",
      },
    },
    DEPLOY = {
      CMD = "project deploy start",
      ARGS = {
        SOURCE_DIR = "-d",
        JSON = "--json",
        API_VERSION = "--api-version",
        VERBOSE = "--verbose",
        MANIFEST = "--manifest",
        IGNORE_CONFLICTS = "--ignore-conflicts",
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
    LIST = {
      LOG = {
        CMD = "apex list log",
        ARGS = {
          JSON = "--json",
          TARGET_ORG = "-o",
        },
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

-- =============================================================================
-- UTILITY FUNCTIONS
-- =============================================================================

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

-- =============================================================================
-- COMMAND BUILDERS
-- =============================================================================

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
  vim.list_extend(args, vim.split(M.SF_CLI.PROJECT.DEPLOY.CMD, " "))

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
  vim.list_extend(args, vim.split(M.SF_CLI.PROJECT.DEPLOY.CMD, " "))

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
  local cmd_parts = split_cmd(M.SF_CLI.APEX.LIST.LOG.CMD)
  for _, part in ipairs(cmd_parts) do
    table.insert(args, part)
  end

  -- Add JSON flag
  table.insert(args, M.SF_CLI.APEX.LIST.LOG.ARGS.JSON)

  -- Add target org if provided
  if target_org then
    table.insert(args, M.SF_CLI.APEX.LIST.LOG.ARGS.TARGET_ORG)
    table.insert(args, target_org)
  end

  return args
end

return M
