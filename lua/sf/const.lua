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
        TARGET_ORG = "-o",
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
M.MANIFEST_THRESHOLD = 10
return M
