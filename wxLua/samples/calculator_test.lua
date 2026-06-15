-------------------------------------------------------------------------=---
-- Name:        calculator_test.lua
-- Purpose:     Regression tests for calculator_core.lua, covering the
--              operator state-machine bugs in the wxLua calculator sample.
--              Runs with a plain Lua interpreter, no wxWidgets required:
--                  lua calculator_test.lua
--              Prints "ALL TESTS PASSED" and exits 0 on success; prints the
--              failing sequences and exits 1 otherwise.
-- Licence:     wxWidgets licence
-------------------------------------------------------------------------=---

-- Make the sibling calculator_core module importable regardless of the
-- current working directory.
do
    local src = debug.getinfo(1, "S").source
    if src:sub(1, 1) == "@" then
        local dir = src:match("^@(.*[/\\])")
        if dir then
            package.path = package.path .. ";" .. dir .. "?.lua"
        end
    end
end

local Calc = require("calculator_core")

local failures = 0

-- Feed a sequence of key presses into a fresh calculator and return the
-- resulting display. Each character is a key:
--   0-9 digit, '.' decimal, '+ - * / =' operators, 'C' clear.
local function press(keys)
    local calc = Calc.new()
    for i = 1, #keys do
        local k = keys:sub(i, i)
        if k:match("%d") then
            calc:inputDigit(tonumber(k))
        elseif k == "." then
            calc:inputDecimal()
        elseif k == "C" then
            calc:reset()
        elseif k == "+" or k == "-" or k == "*" or k == "/" or k == "=" then
            calc:inputOperator(k)
        else
            error("unknown key in sequence: " .. k)
        end
    end
    return calc:getDisplay()
end

-- Assert an exact display string.
local function expect(keys, want)
    local got = press(keys)
    if got ~= want then
        failures = failures + 1
        print(string.format("FAIL  [%-10s] -> got %q, want %q", keys, got, want))
    else
        print(string.format("ok    [%-10s] -> %q", keys, got))
    end
end

-- Assert a numeric value (tolerant of int/float formatting such as 4 vs 4.0).
local function expectNum(keys, want)
    local got = press(keys)
    local n = tonumber(got)
    if n ~= want then
        failures = failures + 1
        print(string.format("FAIL  [%-10s] -> got %q (%s), want %s",
                            keys, got, tostring(n), tostring(want)))
    else
        print(string.format("ok    [%-10s] -> %s", keys, tostring(n)))
    end
end

print("-- 1. consecutive operators must not compute prematurely --")
expectNum("5+-",     5)   -- swapping + then - leaves the typed 5 untouched
expectNum("5+-3=",   2)   -- 5 - 3
expectNum("5+*2=",   10)  -- last operator wins: 5 x 2
expectNum("9-+1=",   10)  -- 9 + 1
expectNum("5++3=",   8)   -- repeated + then operand: 5 + 3

print("-- 2. normal chaining and equals --")
expectNum("5+3=",    8)
expectNum("5+3+2=",  10)
expectNum("2*3*4=",  24)
expectNum("9-4=",    5)

print("-- 3. continue after '=' reusing the result as the new operand --")
expectNum("5+3=+2=", 10)  -- (8) + 2
expectNum("5+3==",   8)   -- a trailing extra '=' stays stable
expectNum("5+3=*2=", 16)  -- (8) x 2

print("-- 4. divide-by-zero shows error, then recovers cleanly --")
expect   ("5/0=",    "Divide by zero error")
expectNum("5/0=7",   7)   -- typing a number clears the error
expectNum("5/0=+",   0)   -- an operator after error returns to a clean 0
expectNum("5/0=3+4=",7)   -- full recovery via a new calculation
expectNum("8/2=",    4)   -- ordinary division still works

print("-- 5. Clear resets internal state, not just the display --")
expectNum("5+3C",    0)   -- after Clear the display is 0
expectNum("5+3C2=",  2)   -- ...and no stale "+3"/operator is applied
expectNum("9*9C4+1=",5)   -- Clear wipes pending operator and accumulator

print("-- 6. decimal and leading-zero behaviour preserved --")
expect   ("005",     "5")    -- leading zeros collapse
expect   (".5",      "0.5")  -- a leading decimal becomes 0.5
expect   ("0.5",     "0.5")
expect   ("1..2",    "1.2")  -- a second '.' is ignored
expect   ("00.",     "0.")   -- 0 then . -> "0."
expectNum("1.5+1.5=",3)      -- decimals add correctly

if failures == 0 then
    print("\nALL TESTS PASSED")
    os.exit(0)
else
    print(string.format("\n%d TEST(S) FAILED", failures))
    os.exit(1)
end
