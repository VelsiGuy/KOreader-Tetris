--[[ Tetris UI: board renderer + full-screen widget with controls. ]]

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local DataStorage = require("datastorage")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Game = require("tetris_game")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local LuaSettings = require("luasettings")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Widget = require("ui/widget/widget")
local _ = require("gettext")
local Screen = Device.screen

local WHITE, BLACK = Blitbuffer.COLOR_WHITE, Blitbuffer.COLOR_BLACK
local LIGHT = Blitbuffer.COLOR_LIGHT_GRAY
local SHADES = {
    BLACK, Blitbuffer.COLOR_DARK_GRAY, Blitbuffer.COLOR_GRAY, LIGHT,
    Blitbuffer.COLOR_DARK_GRAY, Blitbuffer.COLOR_GRAY, BLACK,
}

-- Classic piece colours (used only when the screen is in colour mode)
local COLORS = {
    Blitbuffer.ColorRGB32(0, 190, 220, 0xFF),   -- I cyan
    Blitbuffer.ColorRGB32(245, 215, 0, 0xFF),   -- O yellow
    Blitbuffer.ColorRGB32(160, 50, 180, 0xFF),  -- T purple
    Blitbuffer.ColorRGB32(40, 180, 60, 0xFF),   -- S green
    Blitbuffer.ColorRGB32(225, 35, 35, 0xFF),   -- Z red
    Blitbuffer.ColorRGB32(40, 70, 225, 0xFF),   -- J blue
    Blitbuffer.ColorRGB32(255, 135, 0, 0xFF),   -- L orange
}

local function useColor()
    return Screen.isColorEnabled ~= nil and Screen:isColorEnabled()
end

--------------------------------------------------------------------------
-- Board + side panel
--------------------------------------------------------------------------
local TetrisView = Widget:extend{ game = nil, cell = 30, high_score = 0, message = nil }

function TetrisView:init()
    local c = self.cell
    self.bd = 3 -- board border thickness
    self.gap = math.floor(c * 0.6)
    self.board_w = c * Game.COLS + 2 * self.bd
    self.board_h = c * Game.ROWS + 2 * self.bd
    self.panel_w = c * 5
    self.dimen = Geom:new{ w = self.board_w + self.gap + self.panel_w, h = self.board_h }

    local fsize = math.max(14, math.floor(c * 0.5))
    local face = Font:getFace("cfont", fsize)
    local function tw(text, bold)
        return TextWidget:new{ text = text, face = face, bold = bold, max_width = self.panel_w }
    end
    self.t_next = tw(_("Next"), true)
    self.t_score_l, self.t_score = tw(_("Score"), true), tw("0")
    self.t_lines_l, self.t_lines = tw(_("Lines"), true), tw("0")
    self.t_level_l, self.t_level = tw(_("Level"), true), tw("1")
    self.t_best_l, self.t_best = tw(_("Best"), true), tw("0")
    self.t_msg = TextWidget:new{ text = "", face = Font:getFace("cfont", fsize + 6), bold = true,
                                 max_width = c * Game.COLS }
    self:updateTexts()
end

function TetrisView:updateTexts()
    local g = self.game
    self.t_score:setText(tostring(g.score))
    self.t_lines:setText(tostring(g.lines))
    self.t_level:setText(tostring(g.level))
    self.t_best:setText(tostring(math.max(self.high_score, g.score)))
    if self.message then self.t_msg:setText(self.message) end
end

function TetrisView:drawCell(bb, x, y, kind)
    local c = self.cell
    bb:paintRect(x, y, c, c, BLACK)
    if self.color then
        bb:paintRect(x + 1, y + 1, c - 2, c - 2, COLORS[kind])
        -- subtle highlight so blocks look like tiles
        bb:paintRect(x + 2, y + 2, c - 4, math.max(2, math.floor(c / 8)), WHITE)
        return
    end
    bb:paintRect(x + 1, y + 1, c - 2, c - 2, SHADES[kind])
    if kind >= 5 then -- extra marker so pieces differ even in similar greys
        local m = math.floor(c / 4)
        bb:paintRect(x + m + 1, y + m + 1, c - 2 * m - 2, c - 2 * m - 2, WHITE)
    end
end

function TetrisView:drawGhost(bb, x, y, kind)
    local c = self.cell
    bb:paintRect(x, y, c, c, (self.color and COLORS[kind]) or BLACK)
    bb:paintRect(x + 2, y + 2, c - 4, c - 4, WHITE)
end

function TetrisView:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    self.color = useColor()
    local g, c, bd = self.game, self.cell, self.bd
    bb:paintRect(x, y, self.dimen.w, self.dimen.h, WHITE)

    -- board frame
    bb:paintRect(x, y, self.board_w, self.board_h, BLACK)
    local ox, oy = x + bd, y + bd
    bb:paintRect(ox, oy, c * Game.COLS, c * Game.ROWS, WHITE)

    -- grid dots
    for r = 0, Game.ROWS - 1 do
        for col = 0, Game.COLS - 1 do
            bb:paintRect(ox + col * c + math.floor(c / 2) - 1, oy + r * c + math.floor(c / 2) - 1, 2, 2, LIGHT)
        end
    end

    -- locked blocks
    for r = 1, Game.ROWS do
        for col = 1, Game.COLS do
            local k = g.grid[r][col]
            if k ~= 0 then self:drawCell(bb, ox + (col - 1) * c, oy + (r - 1) * c, k) end
        end
    end

    if not g.over then
        -- ghost
        local gy = g:ghostY()
        if gy ~= g.py then
            for _, cell in ipairs(g:cells(gy)) do
                if cell[2] >= 1 then
                    self:drawGhost(bb, ox + (cell[1] - 1) * c, oy + (cell[2] - 1) * c, g.kind)
                end
            end
        end
        -- active piece
        for _, cell in ipairs(g:cells()) do
            if cell[2] >= 1 then
                self:drawCell(bb, ox + (cell[1] - 1) * c, oy + (cell[2] - 1) * c, g.kind)
            end
        end
    end

    -- side panel
    local px = x + self.board_w + self.gap
    local cy = y
    self.t_next:paintTo(bb, px, cy)
    cy = cy + self.t_next:getSize().h + math.floor(c * 0.3)
    local cells = Game.SHAPES[g.next][1]
    local minx, maxx, miny, maxy = 9, -1, 9, -1
    for _, d in ipairs(cells) do
        minx, maxx = math.min(minx, d[1]), math.max(maxx, d[1])
        miny, maxy = math.min(miny, d[2]), math.max(maxy, d[2])
    end
    local offx = px + math.floor((4 * c - (maxx - minx + 1) * c) / 2)
    local offy = cy + math.floor((2 * c - (maxy - miny + 1) * c) / 2) + math.floor(c / 2)
    for _, d in ipairs(cells) do
        self:drawCell(bb, offx + (d[1] - minx) * c, offy + (d[2] - miny) * c, g.next)
    end
    cy = cy + 4 * c

    local function stat(label, value)
        label:paintTo(bb, px, cy)
        cy = cy + label:getSize().h
        value:paintTo(bb, px, cy)
        cy = cy + value:getSize().h + math.floor(c * 0.5)
    end
    stat(self.t_score_l, self.t_score)
    stat(self.t_lines_l, self.t_lines)
    stat(self.t_level_l, self.t_level)
    stat(self.t_best_l, self.t_best)

    -- overlay message (paused / game over)
    if self.message then
        local ts = self.t_msg:getSize()
        local pad = math.floor(c * 0.5)
        local bw, bh = ts.w + 2 * pad, ts.h + 2 * pad
        local bx = ox + math.floor((c * Game.COLS - bw) / 2)
        local by = oy + math.floor((c * Game.ROWS - bh) / 2)
        bb:paintRect(bx, by, bw, bh, BLACK)
        bb:paintRect(bx + 3, by + 3, bw - 6, bh - 6, WHITE)
        self.t_msg:paintTo(bb, bx + pad, by + pad)
    end
end

function TetrisView:free()
    for _, k in ipairs({ "t_next", "t_score_l", "t_score", "t_lines_l", "t_lines",
                         "t_level_l", "t_level", "t_best_l", "t_best", "t_msg" }) do
        if self[k] then self[k]:free() end
    end
end

--------------------------------------------------------------------------
-- Control pad: one widget, no per-button press animation (much faster on e-ink)
--------------------------------------------------------------------------
local ControlPad = Widget:extend{ rows = nil, width = 0, row_h = 0, face = nil }

function ControlPad:init()
    self.dimen = Geom:new{ w = self.width, h = self.row_h * #self.rows }
    self.items = {}
    for ri, row in ipairs(self.rows) do
        local n = #row
        for ci, b in ipairs(row) do
            local x0 = math.floor((ci - 1) * self.width / n)
            local x1 = math.floor(ci * self.width / n)
            table.insert(self.items, {
                label = TextWidget:new{ text = b.text, face = self.face, bold = true },
                callback = b.callback,
                rx = x0, rw = x1 - x0, ry = (ri - 1) * self.row_h,
            })
        end
    end
end

function ControlPad:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    bb:paintRect(x, y, self.dimen.w, self.dimen.h, WHITE)
    for _, it in ipairs(self.items) do
        local bx, by = x + it.rx, y + it.ry
        bb:paintRect(bx + 2, by + 2, it.rw - 4, self.row_h - 4, BLACK)
        bb:paintRect(bx + 4, by + 4, it.rw - 8, self.row_h - 8, WHITE)
        local s = it.label:getSize()
        it.label:paintTo(bb, bx + math.floor((it.rw - s.w) / 2), by + math.floor((self.row_h - s.h) / 2))
    end
end

function ControlPad:hit(pos)
    local lx, ly = pos.x - self.dimen.x, pos.y - self.dimen.y
    for _, it in ipairs(self.items) do
        if lx >= it.rx and lx < it.rx + it.rw and ly >= it.ry and ly < it.ry + self.row_h then
            return it
        end
    end
end

function ControlPad:free()
    for _, it in ipairs(self.items) do it.label:free() end
end

--------------------------------------------------------------------------
-- Full-screen widget
--------------------------------------------------------------------------
local TetrisScreen = InputContainer:extend{
    name = "tetris_screen",
    covers_fullscreen = true,
}

function TetrisScreen:init()
    self.dimen = Geom:new{ w = Screen:getWidth(), h = Screen:getHeight() }
    self.settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/tetris.lua")
    self.high_score = self.settings:readSetting("high_score") or 0
    self.game = Game:new()
    self.paused = false

    self.tick_cb = function()
        self:run(function() self.game:step() end)
        self:scheduleTick()
    end

    local pad = Screen:scaleBySize(8)
    self.pad = ControlPad:new{
        width = self.dimen.w - 2 * pad,
        row_h = Screen:scaleBySize(54),
        face = Font:getFace("cfont", 22),
        rows = {
            {
                { text = _("Left"),   callback = function() self:act("moveH", -1) end },
                { text = _("Rotate"), callback = function() self:act("rotate", 1) end },
                { text = _("Right"),  callback = function() self:act("moveH", 1) end },
            },
            {
                { text = _("Down"),  callback = function() self:act("softDrop") end },
                { text = _("Drop"),  callback = function() self:act("hardDrop") end },
                { text = _("Pause"), callback = function() self:togglePause() end },
            },
            {
                { text = _("New game"), callback = function() self:newGame() end },
                { text = _("Exit"),     callback = function() self:onClose() end },
            },
        },
    }

    local avail_h = self.dimen.h - self.pad.dimen.h - 3 * pad
    local cell = math.floor(math.min(avail_h / Game.ROWS, (self.dimen.w - 2 * pad) / (Game.COLS + 0.6 + 5)))
    cell = math.max(cell, 12)

    self.view = TetrisView:new{ game = self.game, cell = cell, high_score = self.high_score }

    self[1] = FrameContainer:new{
        width = self.dimen.w,
        height = self.dimen.h,
        background = WHITE,
        bordersize = 0,
        padding = 0,
        CenterContainer:new{
            dimen = self.dimen,
            VerticalGroup:new{
                align = "center",
                self.view,
                VerticalSpan:new{ width = pad },
                self.pad,
            },
        },
    }

    self.ges_events = {
        TapBoard   = { GestureRange:new{ ges = "tap",   range = function() return self.view.dimen end } },
        SwipeBoard = { GestureRange:new{ ges = "swipe", range = function() return self.view.dimen end } },
        TapPad     = { GestureRange:new{ ges = "tap",   range = function() return self.pad.dimen end } },
    }

    if Device:hasKeys() then
        local grp = Device.input.group
        self.key_events = {
            Close     = { { grp.Back } },
            MoveLeft  = { { "Left" } },
            MoveRight = { { "Right" } },
            RotateKey = { { "Up" } },
            DownKey   = { { "Down" } },
            DropKey   = { { "Press" } },
        }
        if grp.PgFwd then self.key_events.PgFwdKey = { { grp.PgFwd }, event = "DownKey" } end
        if grp.PgBack then self.key_events.PgBackKey = { { grp.PgBack }, event = "RotateKey" } end
    end
end

function TetrisScreen:onShow()
    UIManager:setDirty(self, "full")
    self:scheduleTick()
end

function TetrisScreen:scheduleTick()
    UIManager:unschedule(self.tick_cb)
    if self.paused or self.game.over then return end
    UIManager:scheduleIn(self.game:getInterval(), self.tick_cb)
end

-- Grid-cell bounding box covering the active piece and its ghost.
function TetrisScreen:pieceBox()
    local g = self.game
    if g.over then return nil end
    local gy = g:ghostY()
    local minx, maxx, miny, maxy = 99, -1, 99, -1
    for _, d in ipairs(Game.SHAPES[g.kind][g.rot]) do
        minx, maxx = math.min(minx, g.px + d[1]), math.max(maxx, g.px + d[1])
        miny, maxy = math.min(miny, g.py + d[2]), math.max(maxy, gy + d[2])
    end
    return { minx, maxx, math.max(miny, 1), maxy }
end

-- Run a game action, then refresh only what changed.
function TetrisScreen:run(fn)
    local g = self.game
    local before, locks = self:pieceBox(), g.locks
    fn()
    self:refresh(before, locks)
end

function TetrisScreen:refresh(before, locks, full)
    local g = self.game
    local locked = (locks ~= g.locks) or g.over or full or not before
    if g.over then
        self.view.message = _("GAME OVER")
        if g.score > self.high_score then
            self.high_score = g.score
            self.view.high_score = g.score
            self.settings:saveSetting("high_score", g.score)
            self.settings:flush()
        end
    end

    local v = self.view
    if locked then
        -- board contents / score / next piece changed: refresh the whole view
        v:updateTexts()
        UIManager:setDirty(self, full and "full" or "ui", v.dimen)
        return
    end

    -- plain move: only refresh the old + new piece area, using the fast waveform
    local after = self:pieceBox()
    if not after then
        UIManager:setDirty(self, "ui", v.dimen)
        return
    end
    local x0, x1 = math.min(before[1], after[1]), math.max(before[2], after[2])
    local y0, y1 = math.min(before[3], after[3]), math.max(before[4], after[4])
    local c = v.cell
    -- the fast (A2-style) waveform drops colour on Kaleido panels, so use "ui" there
    UIManager:setDirty(self, useColor() and "ui" or "fast", Geom:new{
        x = v.dimen.x + v.bd + (x0 - 1) * c,
        y = v.dimen.y + v.bd + (y0 - 1) * c,
        w = (x1 - x0 + 1) * c,
        h = (y1 - y0 + 1) * c,
    })
end

function TetrisScreen:act(name, ...)
    if self.paused or self.game.over then return end
    local args = { ... }
    self:run(function() self.game[name](self.game, unpack(args)) end)
    if self.game.over then self:scheduleTick() end
end

function TetrisScreen:togglePause()
    if self.game.over then return end
    self.paused = not self.paused
    self.view.message = self.paused and _("PAUSED") or nil
    self:refresh(nil, nil)
    self:scheduleTick()
end

function TetrisScreen:newGame()
    self.game:reset()
    self.paused = false
    self.view.message = nil
    self:refresh(nil, nil, true)
    self:scheduleTick()
end

-- Gestures
function TetrisScreen:onTapPad(arg, ges)
    local item = self.pad:hit(ges.pos)
    if item then item.callback() end
    return true
end

function TetrisScreen:onTapBoard()
    self:act("rotate", 1)
    return true
end

function TetrisScreen:onSwipeBoard(arg, ges)
    local d = ges.direction
    if d == "west" then self:act("moveH", -1)
    elseif d == "east" then self:act("moveH", 1)
    elseif d == "south" then self:act("hardDrop")
    elseif d == "north" then self:act("rotate", 1)
    end
    return true
end

-- Keys
function TetrisScreen:onMoveLeft()  self:act("moveH", -1) return true end
function TetrisScreen:onMoveRight() self:act("moveH", 1) return true end
function TetrisScreen:onRotateKey() self:act("rotate", 1) return true end
function TetrisScreen:onDownKey()   self:act("softDrop") return true end
function TetrisScreen:onDropKey()   self:act("hardDrop") return true end

function TetrisScreen:onSuspend()
    if not self.paused and not self.game.over then self:togglePause() end
end

function TetrisScreen:onClose()
    UIManager:unschedule(self.tick_cb)
    UIManager:close(self)
    UIManager:setDirty(nil, "full")
    return true
end

function TetrisScreen:onCloseWidget()
    UIManager:unschedule(self.tick_cb)
    if self.view then self.view:free() end
    if self.pad then self.pad:free() end
end

return TetrisScreen
