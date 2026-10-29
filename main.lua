local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local Tetris = WidgetContainer:extend{
    name = "tetris",
    is_doc_only = false, -- available from the file manager too
}

function Tetris:init()
    self.ui.menu:registerToMainMenu(self)
end

function Tetris:addToMainMenu(menu_items)
    menu_items.tetris = {
        text = _("Tetris"),
        sorting_hint = "more_tools",
        callback = function()
            local TetrisScreen = require("tetris_screen")
            UIManager:show(TetrisScreen:new{})
        end,
    }
end

return Tetris
