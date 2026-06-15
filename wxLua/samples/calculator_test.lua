#!/usr/bin/env lua
---------------------------------------------------------------------------
-- calculator_test.lua
--
-- Headless regression tests for the calculator sample's state machine.
-- Stubs out wxWidgets so the pure-Lua logic can be exercised without a
-- GUI.  Run with:  lua calculator_test.lua
--
-- Each test replays a reproducible button sequence and asserts the
-- expected display value (and, where relevant, internal state).
---------------------------------------------------------------------------

-- ---- Stub wx IDs (any unique integers work) ----
ID_0        = 100
ID_1        = 101
ID_2        = 102
ID_3        = 103
ID_4        = 104
ID_5        = 105
ID_6        = 106
ID_7        = 107
ID_8        = 108
ID_9        = 109
ID_DECIMAL  = 110
ID_EQUALS   = 120
ID_PLUS     = 121
ID_MINUS    = 122
ID_MULTIPLY = 123
ID_DIVIDE   = 124
ID_CLEAR    = 130

-- ---- Mock display ----
local displayLabel = "0"
local mockDisplay = {}
function mockDisplay:SetLabel(v) displayLabel = v end
function mockDisplay:GetLabel() return displayLabel end
txtDisplay = mockDisplay

-- ---- Copy of the calculator's global state ----
clearDisplay     = false
lastNumber       = 0
lastOperationId  = ID_PLUS
pendingNewNumber = true

-- ---- ResetCalculator (mirrors calculator.wx.lua) ----
function ResetCalculator()
    txtDisplay:SetLabel("0")
    lastNumber       = 0
    lastOperationId  = ID_PLUS
    clearDisplay     = false
    pendingNewNumber = true
end

-- ---- OnClear ----
function OnClear(event)
    ResetCalculator()
end

-- ---- OnNumber (mirrors calculator.wx.lua) ----
function OnNumber(event)
    local numberId      = event:GetId()
    local displayString = txtDisplay:GetLabel()

    if (tonumber(displayString) == nil) or (displayString == "0") or pendingNewNumber then
        displayString = ""
    end
    pendingNewNumber = false
    clearDisplay     = false

    if string.len(displayString) < 12 then
        if numberId == ID_DECIMAL then
            if not string.find(displayString, ".", 1, 1) then
                if string.len(displayString) == 0 then
                    displayString = displayString .. "0."
                else
                    displayString = displayString .. "."
                end
            end
        else
            local idTable = { [ID_0] = 0, [ID_1] = 1, [ID_2] = 2, [ID_3] = 3,
                              [ID_4] = 4, [ID_5] = 5, [ID_6] = 6, [ID_7] = 7,
                              [ID_8] = 8, [ID_9] = 9 }
            local num = idTable[numberId]

            if (num == 0) and (string.len(displayString) == 0) then
                displayString = "0"
            elseif displayString == "" then
                displayString = tostring(num)
            else
                displayString = displayString .. num
            end
        end
        txtDisplay:SetLabel(displayString)
    end
end

-- ---- DoOperation (mirrors calculator.wx.lua) ----
function DoOperation(a, b, operationId)
    local result = a
    if operationId == ID_PLUS then
        result = b + a
    elseif operationId == ID_MINUS then
        result = b - a
    elseif operationId == ID_MULTIPLY then
        result = b * a
    elseif operationId == ID_DIVIDE then
        if a == 0 then
            result = "Divide by zero error"
        else
            result = b / a
        end
    end
    return result
end

-- ---- OnOperator (mirrors calculator.wx.lua) ----
function OnOperator(event)
    local displayString = txtDisplay:GetLabel()
    local currentNumber = tonumber(displayString)
    local operationId   = event:GetId()

    if currentNumber == nil then
        ResetCalculator()
        return
    end

    if pendingNewNumber then
        if lastOperationId == ID_EQUALS then
            lastNumber      = currentNumber
            lastOperationId = operationId
        else
            lastOperationId = operationId
        end
        return
    end

    local result      = DoOperation(currentNumber, lastNumber, lastOperationId)
    local resultStr   = tostring(result)
    lastNumber        = tonumber(resultStr)
    lastOperationId   = operationId
    pendingNewNumber  = true

    txtDisplay:SetLabel(resultStr)
end

---------------------------------------------------------------------------
-- Test helpers
---------------------------------------------------------------------------
local testsPassed = 0
local testsFailed = 0

local function press(buttonId, handler)
    handler({ GetId = function() return buttonId end })
end

local function num(id)  press(id, OnNumber)   end
local function op(id)   press(id, OnOperator)  end

local function assertDisplay(expected, testName)
    local actual = txtDisplay:GetLabel()
    if actual == expected then
        testsPassed = testsPassed + 1
    else
        testsFailed = testsFailed + 1
        io.write(string.format("FAIL [%s]: expected display=%q, got %q\n",
                               testName, expected, actual))
    end
end

local function resetAndRun(name, fn)
    ResetCalculator()
    fn()
    -- assertion is done inside fn via assertDisplay
end

---------------------------------------------------------------------------
-- Test cases
---------------------------------------------------------------------------

-- T1: Basic arithmetic  5 + 3 = 8
resetAndRun("basic_add", function()
    num(ID_5); op(ID_PLUS); num(ID_3); op(ID_EQUALS)
    assertDisplay("8", "basic_add")
end)

-- T2: Consecutive operators  5 + - 3 = -2
--     (pressing + then - should NOT double-compute with 5)
resetAndRun("consec_ops", function()
    num(ID_5); op(ID_PLUS); op(ID_MINUS); num(ID_3); op(ID_EQUALS)
    assertDisplay("2", "consec_ops")  -- 5 - 3 = 2
end)

-- T3: Three consecutive operators  5 + * - 3
--     only the last operator (-) should take effect
resetAndRun("triple_consec", function()
    num(ID_5); op(ID_PLUS); op(ID_MULTIPLY); op(ID_MINUS)
    num(ID_3); op(ID_EQUALS)
    assertDisplay("2", "triple_consec")  -- 5 - 3 = 2
end)

-- T4: Equals then continue  5 + 3 = + 2 = 10
resetAndRun("eq_continue", function()
    num(ID_5); op(ID_PLUS); num(ID_3); op(ID_EQUALS)
    assertDisplay("8", "eq_continue_step1")
    op(ID_PLUS); num(ID_2); op(ID_EQUALS)
    assertDisplay("10", "eq_continue_step2")  -- 8 + 2 = 10
end)

-- T5: Repeated equals  5 + 3 = = should show 8, then 8 (no change)
resetAndRun("repeat_eq", function()
    num(ID_5); op(ID_PLUS); num(ID_3); op(ID_EQUALS)
    assertDisplay("8", "repeat_eq_step1")
    op(ID_EQUALS)
    assertDisplay("8", "repeat_eq_step2")
end)

-- T6: Divide by zero then recover with C
resetAndRun("div_zero_clear", function()
    num(ID_5); op(ID_DIVIDE); num(ID_0); op(ID_EQUALS)
    assertDisplay("Divide by zero error", "div_zero_display")
    -- press C to clear
    OnClear({})
    assertDisplay("0", "div_zero_after_clear")
    -- now do a normal calculation
    num(ID_8); op(ID_PLUS); num(ID_2); op(ID_EQUALS)
    assertDisplay("10", "div_zero_recover")
end)

-- T7: Divide by zero then press operator (should reset silently)
resetAndRun("div_zero_op", function()
    num(ID_5); op(ID_DIVIDE); num(ID_0); op(ID_EQUALS)
    assertDisplay("Divide by zero error", "div_zero_op_step1")
    -- pressing + should reset state silently
    op(ID_PLUS)
    assertDisplay("0", "div_zero_op_step2")
    num(ID_4); op(ID_EQUALS)
    assertDisplay("4", "div_zero_op_step3")  -- 0 + 4 = 4
end)

-- T8: Clear resets everything  5 + 3 (don't press =) then C, then 2 + 1 = 3
resetAndRun("clear_resets", function()
    num(ID_5); op(ID_PLUS); num(ID_3)
    OnClear({})
    assertDisplay("0", "clear_display")
    num(ID_2); op(ID_PLUS); num(ID_1); op(ID_EQUALS)
    assertDisplay("3", "clear_then_calc")  -- 2 + 1 = 3, not 5+3+2+1
end)

-- T9: Decimal input  0.5 + 0.5 = 1.0  (Lua tostring renders as "1.0")
resetAndRun("decimal", function()
    num(ID_DECIMAL); num(ID_5); op(ID_PLUS)
    num(ID_DECIMAL); num(ID_5); op(ID_EQUALS)
    assertDisplay("1.0", "decimal_add")
end)

-- T10: Leading zero suppressed  0 0 5 displays "5" (well, "0" then "5")
resetAndRun("leading_zero", function()
    num(ID_0); num(ID_0); num(ID_5)
    assertDisplay("5", "leading_zero")
end)

-- T11: Multiply chain  2 * 3 * 4 = 24
resetAndRun("multiply_chain", function()
    num(ID_2); op(ID_MULTIPLY); num(ID_3); op(ID_MULTIPLY)
    num(ID_4); op(ID_EQUALS)
    assertDisplay("24", "multiply_chain")
end)

-- T12: Subtract then change mind  9 - * 3 = 27
--     (user pressed - then changed to *)
resetAndRun("change_op", function()
    num(ID_9); op(ID_MINUS); op(ID_MULTIPLY)
    num(ID_3); op(ID_EQUALS)
    assertDisplay("27", "change_op")  -- 9 * 3 = 27
end)

-- T13: Operator at startup (no number entered yet)  + 5 = 5
resetAndRun("op_at_start", function()
    op(ID_PLUS); num(ID_5); op(ID_EQUALS)
    assertDisplay("5", "op_at_start")
end)

-- T14: Decimal after operator  5 + . 5 = 5.5
resetAndRun("decimal_after_op", function()
    num(ID_5); op(ID_PLUS); num(ID_DECIMAL); num(ID_5); op(ID_EQUALS)
    assertDisplay("5.5", "decimal_after_op")
end)

-- T15: Double decimal press ignored  3 . . 5 = 3.5
resetAndRun("double_decimal", function()
    num(ID_3); num(ID_DECIMAL); num(ID_DECIMAL); num(ID_5); op(ID_EQUALS)
    assertDisplay("3.5", "double_decimal")
end)

---------------------------------------------------------------------------
-- Summary
---------------------------------------------------------------------------
print(string.format("\n%d passed, %d failed out of %d tests",
                    testsPassed, testsFailed, testsPassed + testsFailed))

if testsFailed > 0 then
    os.exit(1)
end
