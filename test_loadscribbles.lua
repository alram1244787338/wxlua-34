#!/usr/bin/env lua
---------------------------------------------------------------------------
-- Regression test for LoadScribbles in scribble.wx.lua
--
-- Pure-Lua test (no wxWidgets needed). Run with:
--   lua test_loadscribbles.lua
--
-- Exit code 0 = all tests pass, non-zero = failures detected.
---------------------------------------------------------------------------

local passed, failed = 0, 0

local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
        print(string.format("  PASS  %s", name))
    else
        failed = failed + 1
        print(string.format("  FAIL  %s: %s", name, tostring(err)))
    end
end

local function assert_eq(a, b, msg)
    if a ~= b then
        error(string.format("%s (expected %s, got %s)",
              msg or "assertion failed", tostring(b), tostring(a)), 2)
    end
end

-- -----------------------------------------------------------------------
-- Minimal mock environment so we can source scribble.wx.lua's functions
-- without wxWidgets. We only need the globals that LoadScribbles and
-- SaveScribbles touch.
-- -----------------------------------------------------------------------

-- Provide a stub wx table so require("wx") doesn't blow up when we
-- source the file; we override dofile to only load the functions we need.
wx = { wxMessageBox = function() end }

-- These are the globals that LoadScribbles / SaveScribbles reference.
pointsList = {}
lastDrawn  = 0
fileName   = ""

-- -----------------------------------------------------------------------
-- Extract just the functions under test from scribble.wx.lua.
-- We read the file and eval only the function bodies we need.
-- -----------------------------------------------------------------------
local scribble_path = "wxLua/samples/scribble.wx.lua"
local src_fh = io.open(scribble_path, "r")
if not src_fh then
    -- Try from the samples directory
    scribble_path = "scribble.wx.lua"
    src_fh = io.open(scribble_path, "r")
end
if not src_fh then
    print("ERROR: cannot find scribble.wx.lua")
    os.exit(2)
end
local source = src_fh:read("*a")
src_fh:close()

-- Extract and compile LoadScribbles
local load_fn_src = source:match("(function LoadScribbles%(.-%)end)")
if not load_fn_src then
    -- multi-line match: grab from "function LoadScribbles" to matching "end"
    local start = source:find("function LoadScribbles")
    if not start then
        print("ERROR: cannot find LoadScribbles in source")
        os.exit(2)
    end
    -- naive extraction: find the line starting with "end" after the function start
    local lines = {}
    local in_func = false
    local depth = 0
    for line in source:sub(start):gmatch("[^\n]*") do
        if line:match("^function ") then in_func = true end
        if in_func then
            table.insert(lines, line)
            -- count function/if/for/while/do vs end
            for _ in line:gmatch("%bfunction") do end
            if line:match("^end") or line:match("^end[%)%s]") then
                break
            end
        end
    end
    load_fn_src = table.concat(lines, "\n")
end
assert(load(load_fn_src))()

-- Extract savevar and SaveScribbles for round-trip test
for _, fname in ipairs({"savevar", "SaveScribbles"}) do
    local fsrc = source:match("(function " .. fname .. "%(.-%)end)")
    if not fsrc then
        local start = source:find("function " .. fname)
        if start then
            local lines = {}
            local in_func = false
            for line in source:sub(start):gmatch("[^\n]*") do
                if line:match("^function ") then in_func = true end
                if in_func then
                    table.insert(lines, line)
                    if line:match("^end") or line:match("^end[%)%s]") then
                        break
                    end
                end
            end
            fsrc = table.concat(lines, "\n")
        end
    end
    if fsrc then assert(load(fsrc))() end
end

-- -----------------------------------------------------------------------
-- Helper: create a temporary file with given content, return path
-- -----------------------------------------------------------------------
local tmp_dir = os.tmpname()  -- get a unique prefix
os.remove(tmp_dir)            -- we just want the name
os.execute("mkdir -p " .. tmp_dir)

local function tmpfile(name, content)
    local path = tmp_dir .. "/" .. name
    if content then
        local fh = io.open(path, "w")
        fh:write(content)
        fh:close()
    end
    return path
end

-- Helper: create a valid scribble file
local function make_valid_scribble()
    return [[
pointsList={}
pointsList[1]={}
pointsList[1].pen={}
pointsList[1].pen.colour={}
pointsList[1].pen.colour[1]=255
pointsList[1].pen.colour[2]=0
pointsList[1].pen.colour[3]=0
pointsList[1].pen.width=3
pointsList[1].pen.style=0
pointsList[1][1]={}
pointsList[1][1].x=100
pointsList[1][1].y=200
pointsList[1][2]={}
pointsList[1][2].x=150
pointsList[1][2].y=250
]]
end

-- =======================================================================
print("\n=== LoadScribbles Regression Tests ===\n")
-- =======================================================================

-- Test 1: Successful load of a valid scribble file
test("valid file loads successfully", function()
    local path = tmpfile("valid.scribble", make_valid_scribble())
    local ok, errType = LoadScribbles(path)
    assert_eq(ok, true, "load should succeed")
    assert_eq(errType, nil, "no error type on success")
    assert_eq(#pointsList, 1, "should have 1 segment")
    assert_eq(pointsList[1].pen.colour[1], 255, "red channel")
    assert_eq(pointsList[1][1].x, 100, "first point x")
end)

-- Test 2: Non-existent file fails with "load" and preserves old data
test("non-existent file: fails with 'load', preserves old data", function()
    -- Set up known old state
    pointsList = {{pen = {colour = {0, 0, 0}, width = 1, style = 0}, {x = 1, y = 2}}}
    lastDrawn = 42

    local ok, errType = LoadScribbles("/no/such/file.scribble")
    assert_eq(ok, false, "load should fail")
    assert_eq(errType, "load", "error type should be 'load'")
    assert_eq(#pointsList, 1, "old pointsList preserved")
    assert_eq(pointsList[1][1].x, 1, "old point data preserved")
    assert_eq(lastDrawn, 42, "old lastDrawn preserved")
end)

-- Test 3: File with Lua syntax error fails with "run" and preserves old data
test("syntax error file: fails with 'run', preserves old data", function()
    local path = tmpfile("syntax_err.scribble", "pointsList = {{{{  -- broken syntax\n")
    pointsList = {{pen = {colour = {10, 20, 30}, width = 2, style = 0}, {x = 5, y = 6}}}
    lastDrawn = 99

    local ok, errType, errMsg = LoadScribbles(path)
    assert_eq(ok, false, "load should fail")
    assert_eq(errType, "run", "error type should be 'run'")
    assert_eq(type(errMsg), "string", "should have error message")
    assert_eq(#pointsList, 1, "old pointsList preserved")
    assert_eq(pointsList[1][1].x, 5, "old point data preserved")
    assert_eq(lastDrawn, 99, "old lastDrawn preserved")
end)

-- Test 4: File with valid Lua but no pointsList fails with "format"
test("no pointsList defined: fails with 'format'", function()
    local path = tmpfile("no_points.scribble", "x = 42\n")
    pointsList = {{pen = {colour = {1, 2, 3}, width = 1, style = 0}, {x = 9, y = 8}}}
    lastDrawn = 7

    local ok, errType = LoadScribbles(path)
    assert_eq(ok, false, "load should fail")
    assert_eq(errType, "format", "error type should be 'format'")
    assert_eq(#pointsList, 1, "old pointsList preserved")
    assert_eq(lastDrawn, 7, "old lastDrawn preserved")
end)

-- Test 5: File with pointsList but invalid segment structure fails with "format"
test("invalid segment structure: fails with 'format'", function()
    local path = tmpfile("bad_segment.scribble",
        "pointsList = { {pen = 'not_a_table', {x=1,y=2}} }\n")
    pointsList = {{pen = {colour = {5, 5, 5}, width = 1, style = 0}, {x = 3, y = 4}}}
    lastDrawn = 55

    local ok, errType = LoadScribbles(path)
    assert_eq(ok, false, "load should fail")
    assert_eq(errType, "format", "error type should be 'format'")
    assert_eq(#pointsList, 1, "old pointsList preserved")
    assert_eq(pointsList[1][1].x, 3, "old data intact")
    assert_eq(lastDrawn, 55, "old lastDrawn preserved")
end)

-- Test 6: Empty file (no pointsList set) fails with "format"
test("empty file: fails with 'format'", function()
    local path = tmpfile("empty.scribble", "-- just a comment, nothing else\n")
    pointsList = {{pen = {colour = {7, 8, 9}, width = 1, style = 0}, {x = 10, y = 20}}}
    lastDrawn = 33

    local ok, errType = LoadScribbles(path)
    assert_eq(ok, false, "load should fail")
    assert_eq(errType, "format", "error type should be 'format'")
    assert_eq(#pointsList, 1, "old pointsList preserved")
    assert_eq(lastDrawn, 33, "old lastDrawn preserved")
end)

-- Test 7: File that sets pointsList to a non-table value fails with "format"
test("pointsList set to string: fails with 'format'", function()
    local path = tmpfile("string_pl.scribble", 'pointsList = "not a table"\n')
    pointsList = {{pen = {colour = {1, 1, 1}, width = 1, style = 0}, {x = 0, y = 0}}}
    lastDrawn = 11

    local ok, errType = LoadScribbles(path)
    assert_eq(ok, false, "load should fail")
    assert_eq(errType, "format", "error type should be 'format'")
    assert_eq(type(pointsList), "table", "old pointsList preserved as table")
    assert_eq(lastDrawn, 11, "old lastDrawn preserved")
end)

-- Test 8: Successful load resets lastDrawn to 0
test("successful load resets lastDrawn to 0", function()
    lastDrawn = 123
    local path = tmpfile("valid2.scribble", make_valid_scribble())
    local ok = LoadScribbles(path)
    assert_eq(ok, true, "load should succeed")
    assert_eq(lastDrawn, 0, "lastDrawn should be reset to 0")
end)

-- Test 9: File that throws runtime error during execution
test("runtime error in file: fails with 'run', preserves old data", function()
    local path = tmpfile("runtime_err.scribble",
        "pointsList = {}\nerror('deliberate runtime error')\n")
    pointsList = {{pen = {colour = {42, 42, 42}, width = 1, style = 0}, {x = 7, y = 7}}}
    lastDrawn = 77

    local ok, errType, errMsg = LoadScribbles(path)
    assert_eq(ok, false, "load should fail")
    assert_eq(errType, "run", "error type should be 'run'")
    assert_eq(#pointsList, 1, "old pointsList preserved")
    assert_eq(lastDrawn, 77, "old lastDrawn preserved")
end)

-- Test 10: Save and reload round-trip
test("save + reload round-trip preserves data", function()
    -- Set up known data
    pointsList = {
        {pen = {colour = {100, 200, 50}, width = 5, style = 0},
         {x = 10, y = 20}, {x = 30, y = 40}},
        {pen = {colour = {0, 0, 255}, width = 2, style = 1},
         {x = 50, y = 60}, {x = 70, y = 80}},
    }
    fileName = tmpfile("roundtrip.scribble")

    -- Save (uses the global fileName)
    if SaveScribbles then
        local saved = SaveScribbles()
        assert_eq(saved, true, "save should succeed")

        -- Now load it back into fresh state
        pointsList = {}
        lastDrawn = 999
        local ok = LoadScribbles(fileName)
        assert_eq(ok, true, "reload should succeed")
        assert_eq(#pointsList, 2, "should have 2 segments")
        assert_eq(pointsList[1].pen.colour[1], 100, "segment 1 red")
        assert_eq(pointsList[2].pen.colour[3], 255, "segment 2 blue")
    else
        print("    (skipped: SaveScribbles not available)")
    end
end)

-- Test 11: After failed load, a subsequent save still writes old data correctly
test("save after failed load writes old data", function()
    -- Set up known good data
    pointsList = {
        {pen = {colour = {11, 22, 33}, width = 1, style = 0},
         {x = 1, y = 2}},
    }
    local goodFile = tmpfile("good_after_bad.scribble")
    fileName = goodFile

    if SaveScribbles then
        -- First, save the good data
        SaveScribbles()

        -- Attempt to load a bad file (this should fail but preserve old data)
        local badPath = tmpfile("bad_for_save.scribble", "garbage {{{{\n")
        local ok = LoadScribbles(badPath)
        assert_eq(ok, false, "bad load should fail")

        -- Save again — should still write the original good data
        fileName = tmpfile("resaved.scribble")
        SaveScribbles()

        -- Load the resaved file and verify
        pointsList = {}
        local ok2 = LoadScribbles(fileName)
        assert_eq(ok2, true, "resaved file should load")
        assert_eq(#pointsList, 1, "should have 1 segment")
        assert_eq(pointsList[1].pen.colour[1], 11, "data should match original")
        assert_eq(pointsList[1][1].x, 1, "point data should match")
    else
        print("    (skipped: SaveScribbles not available)")
    end
end)

-- =======================================================================
-- Summary
-- =======================================================================
print(string.format("\n=== Results: %d passed, %d failed ===\n", passed, failed))

-- Cleanup
os.execute("rm -rf " .. tmp_dir)

os.exit(failed > 0 and 1 or 0)
