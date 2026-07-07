local PathUtils = require("sf.core.path_utils")

-- These specs exercise the pure, OS-aware path helpers in sf.core.path_utils.
-- CI runs on ubuntu-latest, so os_type == "unix" and separator == "/".

describe("path_utils", function()
  describe("get_separator", function()
    it("returns / on unix hosts", function()
      assert.are.equal("/", PathUtils.get_separator())
    end)
  end)

  describe("normalize", function()
    it("collapses duplicate forward slashes", function()
      assert.are.equal("a/b", PathUtils.normalize("a//b"))
    end)

    it("converts backslashes to forward slashes on unix", function()
      assert.are.equal("a/b", PathUtils.normalize("a\\b"))
    end)

    it("passes through empty/nil input unchanged", function()
      assert.are.equal("", PathUtils.normalize(""))
      assert.are.equal(nil, PathUtils.normalize(nil))
    end)

    it("preserves a leading network path", function()
      assert.are.equal("//host/share/x", PathUtils.normalize("//host//share//x"))
    end)
  end)

  describe("join", function()
    it("joins segments with the os separator", function()
      assert.are.equal("a/b/c", PathUtils.join("a", "b", "c"))
    end)

    it("skips empty segments", function()
      assert.are.equal("a/b", PathUtils.join("a", "", "b"))
    end)

    it("returns empty string when given no segments", function()
      assert.are.equal("", PathUtils.join())
    end)
  end)

  describe("get_filename", function()
    it("extracts the trailing path component", function()
      assert.are.equal("file.txt", PathUtils.get_filename("path/to/file.txt"))
    end)

    it("returns the whole path when no separator is present", function()
      assert.are.equal("file.txt", PathUtils.get_filename("file.txt"))
    end)

    it("returns empty/nil input unchanged", function()
      assert.are.equal("", PathUtils.get_filename(""))
      assert.are.equal(nil, PathUtils.get_filename(nil))
    end)
  end)

  describe("is_absolute", function()
    it("is true for unix absolute paths", function()
      assert.is_true(PathUtils.is_absolute("/x/y"))
    end)

    it("is false for relative paths", function()
      assert.is_false(PathUtils.is_absolute("x/y"))
    end)

    it("is false for empty/nil input", function()
      assert.is_false(PathUtils.is_absolute(""))
      assert.is_false(PathUtils.is_absolute(nil))
    end)
  end)

  describe("trailing separator helpers", function()
    it("ensure_trailing_separator appends one when missing", function()
      assert.are.equal("a/", PathUtils.ensure_trailing_separator("a"))
    end)

    it("ensure_trailing_separator is idempotent", function()
      assert.are.equal("a/", PathUtils.ensure_trailing_separator("a/"))
    end)

    it("remove_trailing_separator strips a trailing separator", function()
      assert.are.equal("a", PathUtils.remove_trailing_separator("a/"))
    end)

    it("remove_trailing_separator is a no-op without one", function()
      assert.are.equal("a", PathUtils.remove_trailing_separator("a"))
    end)
  end)

  describe("to_forward_slashes", function()
    it("converts backslashes to forward slashes", function()
      assert.are.equal("a/b/c", PathUtils.to_forward_slashes("a\\b\\c"))
    end)

    it("passes through empty/nil input unchanged", function()
      assert.are.equal("", PathUtils.to_forward_slashes(""))
      assert.are.equal(nil, PathUtils.to_forward_slashes(nil))
    end)
  end)
end)