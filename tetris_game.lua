--[[ Pure game logic for Tetris (no UI code). ]]

local Game = { COLS = 10, ROWS = 20 }
Game.__index = Game

local COLS, ROWS = Game.COLS, Game.ROWS

-- 1=I 2=O 3=T 4=S 5=Z 6=J 7=L
local DEFS = {
    { "....", "XXXX", "....", "...." },
    { "XX", "XX" },
    { ".X.", "XXX", "..." },
    { ".XX", "XX.", "..." },
    { "XX.", ".XX", "..." },
    { "X..", "XXX", "..." },
    { "..X", "XXX", "..." },
}

local function parse(rows)
    local n, g = #rows, {}
    for r = 1, n do
        g[r] = {}
        for c = 1, n do g[r][c] = rows[r]:sub(c, c) == "X" end
    end
    return g, n
end

local function rotateCW(g, n)
    local o = {}
    for r = 1, n do
        o[r] = {}
        for c = 1, n do o[r][c] = g[n - c + 1][r] end
    end
    return o
end

-- SHAPES[kind] = { n = size, [rot] = { {dx,dy}, ... } } (0-based offsets)
local SHAPES = {}
for kind, rows in ipairs(DEFS) do
    local g, n = parse(rows)
    SHAPES[kind] = { n = n }
    for rot = 1, 4 do
        local cells = {}
        for r = 1, n do
            for c = 1, n do
                if g[r][c] then cells[#cells + 1] = { c - 1, r - 1 } end
            end
        end
        SHAPES[kind][rot] = cells
        g = rotateCW(g, n)
    end
end
Game.SHAPES = SHAPES

local function emptyRow()
    local row = {}
    for c = 1, COLS do row[c] = 0 end
    return row
end

function Game:new()
    math.randomseed(os.time())
    local o = setmetatable({}, self)
    o:reset()
    return o
end

function Game:reset()
    self.grid = {}
    for r = 1, ROWS do self.grid[r] = emptyRow() end
    self.score, self.lines, self.level = 0, 0, 1
    self.locks = 0
    self.over = false
    self.bag = {}
    self.next = self:draw()
    self:spawn()
end

function Game:draw()
    if #self.bag == 0 then
        for i = 1, 7 do self.bag[i] = i end
        for i = 7, 2, -1 do
            local j = math.random(i)
            self.bag[i], self.bag[j] = self.bag[j], self.bag[i]
        end
    end
    return table.remove(self.bag)
end

function Game:collides(kind, rot, px, py)
    for _, d in ipairs(SHAPES[kind][rot]) do
        local x, y = px + d[1], py + d[2]
        if x < 1 or x > COLS or y > ROWS then return true end
        if y >= 1 and self.grid[y][x] ~= 0 then return true end
    end
    return false
end

function Game:spawn()
    self.kind = self.next
    self.next = self:draw()
    self.rot = 1
    local n = SHAPES[self.kind].n
    self.px = math.floor((COLS - n) / 2) + 1
    self.py = (self.kind == 1) and 0 or 1
    if self:collides(self.kind, self.rot, self.px, self.py) then
        self.over = true
    end
end

-- Absolute grid cells of the active piece (optionally at another row).
function Game:cells(py)
    local out = {}
    py = py or self.py
    for _, d in ipairs(SHAPES[self.kind][self.rot]) do
        out[#out + 1] = { self.px + d[1], py + d[2] }
    end
    return out
end

function Game:ghostY()
    local y = self.py
    while not self:collides(self.kind, self.rot, self.px, y + 1) do y = y + 1 end
    return y
end

function Game:moveH(dx)
    if self.over then return false end
    if not self:collides(self.kind, self.rot, self.px + dx, self.py) then
        self.px = self.px + dx
        return true
    end
    return false
end

function Game:rotate(dir)
    if self.over then return false end
    dir = dir or 1
    local nrot = (self.rot - 1 + dir) % 4 + 1
    for _, dy in ipairs({ 0, -1 }) do
        for _, dx in ipairs({ 0, -1, 1, -2, 2 }) do
            if not self:collides(self.kind, nrot, self.px + dx, self.py + dy) then
                self.rot, self.px, self.py = nrot, self.px + dx, self.py + dy
                return true
            end
        end
    end
    return false
end

function Game:down()
    if not self:collides(self.kind, self.rot, self.px, self.py + 1) then
        self.py = self.py + 1
        return true
    end
    return false
end

function Game:softDrop()
    if self.over then return end
    if self:down() then
        self.score = self.score + 1
    else
        self:lock()
    end
end

function Game:hardDrop()
    if self.over then return end
    local n = 0
    while self:down() do n = n + 1 end
    self.score = self.score + 2 * n
    self:lock()
end

-- Gravity step.
function Game:step()
    if self.over then return end
    if not self:down() then self:lock() end
end

function Game:lock()
    self.locks = self.locks + 1
    for _, cell in ipairs(self:cells()) do
        local x, y = cell[1], cell[2]
        if y < 1 then
            self.over = true
            return
        end
        self.grid[y][x] = self.kind
    end
    local cleared, r = 0, ROWS
    while r >= 1 do
        local full = true
        for c = 1, COLS do
            if self.grid[r][c] == 0 then full = false break end
        end
        if full then
            table.remove(self.grid, r)
            table.insert(self.grid, 1, emptyRow())
            cleared = cleared + 1
        else
            r = r - 1
        end
    end
    if cleared > 0 then
        self.score = self.score + ({ 100, 300, 500, 800 })[cleared] * self.level
        self.lines = self.lines + cleared
        self.level = math.floor(self.lines / 10) + 1
    end
    self:spawn()
end

-- Seconds between gravity steps (kept slow-ish for e-ink refresh).
function Game:getInterval()
    return math.max(0.35, 1.0 - (self.level - 1) * 0.07)
end

return Game
