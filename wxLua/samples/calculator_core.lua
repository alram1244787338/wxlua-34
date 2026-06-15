-------------------------------------------------------------------------=---
-- Name:        calculator_core.lua
-- Purpose:     Pure-Lua calculator state machine for the wxLua calculator
--              sample. Deliberately free of any wxWidgets dependency so the
--              key-handling logic can be unit tested with a plain Lua
--              interpreter (see calculator_test.lua).
-- Licence:     wxWidgets licence
-------------------------------------------------------------------------=---

local Calc = {}
Calc.__index = Calc

local MAX_LEN    = 12                       -- display length limit (as before)
local ERROR_TEXT = "Divide by zero error"   -- shown on divide-by-zero

-- ---------------------------------------------------------------------------
-- Create a new calculator in the stable initial state.
function Calc.new()
    local self = setmetatable({}, Calc)
    self:reset()
    return self
end

-- ---------------------------------------------------------------------------
-- Return every piece of internal state to a stable initial value. Used by the
-- Clear button and to recover once an error has been acknowledged. Resetting
-- only the display would leave a stale operand/operator behind for the next
-- key press, so accumulator and pending operator are wiped here too.
function Calc:reset()
    self.display        = "0"
    self.accumulator    = 0     -- pending left-hand operand
    self.pendingOp      = nil   -- operator awaiting its right-hand operand
    self.startNewNumber = true  -- next digit begins a fresh entry
    self.errored        = false -- display currently holds an error message
end

-- ---------------------------------------------------------------------------
function Calc:getDisplay()
    return self.display
end

-- ---------------------------------------------------------------------------
-- True when the display does not currently hold a fresh, user-typed operand
-- and the next digit/decimal should therefore start a new number. This mirrors
-- the original sample's reset rule exactly so decimal and leading-zero
-- behaviour is preserved.
local function needsFreshEntry(self)
    return (self.display == "0")
        or (tonumber(self.display) == nil)
        or self.startNewNumber
end

-- ---------------------------------------------------------------------------
-- Append a single digit (0-9), honouring the leading-zero rule and the 12
-- character display limit of the original sample.
function Calc:inputDigit(num)
    local s = self.display
    if needsFreshEntry(self) then
        s = ""
    end
    self.startNewNumber = false
    self.errored        = false

    if string.len(s) < MAX_LEN then
        if (num == 0) and (string.len(s) == 0) then
            -- a lone leading 0 stays "0" (and collapses on the next digit)
            s = "0"
        elseif s == "" then
            s = tostring(num)
        else
            s = s .. num
        end
        self.display = s
    end
end

-- ---------------------------------------------------------------------------
-- Append a decimal point, matching the original "leading 0." behaviour and
-- ignoring a second '.' in the same number.
function Calc:inputDecimal()
    local s = self.display
    if needsFreshEntry(self) then
        s = ""
    end
    self.startNewNumber = false
    self.errored        = false

    if string.len(s) < MAX_LEN then
        if not string.find(s, ".", 1, 1) then
            if string.len(s) == 0 then
                s = "0."
            else
                s = s .. "."
            end
            self.display = s
        end
    end
end

-- ---------------------------------------------------------------------------
-- Pure arithmetic. Returns a number, or ERROR_TEXT on divide-by-zero.
local function compute(left, right, op)
    if op == "+" then return left + right end
    if op == "-" then return left - right end
    if op == "*" then return left * right end
    if op == "/" then
        if right == 0 then return ERROR_TEXT end
        return left / right
    end
    -- unknown operator: act as identity on the right operand
    return right
end

-- ---------------------------------------------------------------------------
-- Apply an operator key: one of "+", "-", "*", "/", "=".
function Calc:inputOperator(op)
    -- An operator pressed while an error is shown returns to a clean,
    -- predictable state instead of trying to compute on the error text.
    if self.errored then
        self:reset()
        return
    end

    local current = tonumber(self.display) or 0

    -- No operator pending: this operand simply becomes the left-hand side.
    -- This also handles "press an operator right after =", where the previous
    -- result is reused as the new left operand WITHOUT recomputing it.
    if self.pendingOp == nil then
        self.accumulator    = current
        if op ~= "=" then
            self.pendingOp = op
        end
        self.startNewNumber = true
        return
    end

    -- An operator is pending but no new operand has been typed since it was
    -- set: the user pressed two operators in a row. Just swap the pending
    -- operator rather than re-applying it to the value already on screen.
    -- (This is the bug fix: "5 + -" must keep showing 5, not 10.)
    if self.startNewNumber then
        if op ~= "=" then
            self.pendingOp = op
            return
        end
        -- "=" with no fresh operand: fall through and apply the pending op
        -- using the current value as both operands (matches old behaviour).
    end

    -- A fresh operand is available: evaluate "accumulator <pendingOp> current".
    local result = compute(self.accumulator, current, self.pendingOp)

    if result == ERROR_TEXT then
        self.display        = ERROR_TEXT
        self.errored        = true
        self.accumulator    = 0
        self.pendingOp      = nil
        self.startNewNumber = true
        return
    end

    self.display     = tostring(result)
    self.accumulator = result
    if op == "=" then
        self.pendingOp = nil   -- chain stops; result waits as next left operand
    else
        self.pendingOp = op    -- keep chaining with the new operator
    end
    self.startNewNumber = true
end

return Calc
