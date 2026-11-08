-- RaidLedger window (UI feedback 2026-10-19: "cleaner, easier, everything in
-- the UI"): one window with tabs - BEUTE (loot and rolls), VERGABEN (awards and
-- the export), SPIELER (tally and corrections), RAID (Raid.lua) and
-- EINSTELLUNGEN (Access.lua). Each tab owns its whole height, so long lists
-- stay readable. This file holds the window, the tabs and the shared widgets;
-- the tabs live in their own files. The core (RaidLedger.lua) keeps all state
-- and rules and calls ns.ui to redraw.
local _, ns = ...
local L = ns.L
local ui = ns.ui
-- The window's default and smallest size; users may make it larger and scale
-- it (raider feedback 2026-10-24: high- and low-resolution clients).
local WIDTH, HEIGHT = 760, 480
local CONTENT_TOP, CONTENT_BOTTOM = -72, 32
local SCALE_MIN, SCALE_MAX = 0.6, 1.5
ns.CONTENT_WIDTH, ns.CONTENT_HEIGHT = WIDTH - 32, HEIGHT + CONTENT_TOP - CONTENT_BOTTOM
ns.ROW_HEIGHT = 18

---------------------------------------------------------------------------
-- Shared widgets
---------------------------------------------------------------------------
local function makeBackdrop(frame, red, green, blue, alpha)
    frame:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetBackdropColor(red, green, blue, alpha)
    frame:SetBackdropBorderColor(0.20, 0.63, 0.82, 0.92)
end

local function label(parent, template, size, color, name)
    local text = parent:CreateFontString(name, "OVERLAY", template)
    if size then text:SetFont(STANDARD_TEXT_FONT, size) end
    if color then text:SetTextColor(color[1], color[2], color[3]) end
    return text
end

local function flatButton(parent, caption, width, name)
    local button = CreateFrame("Button", name, parent)
    button:SetWidth(width)
    button:SetHeight(24)
    makeBackdrop(button, 0.08, 0.25, 0.34, 0.98)
    button.baseColor = { 0.08, 0.25, 0.34 }
    local text = label(button, "GameFontNormal", 10, {0.70, 0.93, 1.00})
    text:SetPoint("CENTER", button, "CENTER", 0, 0)
    button:SetFontString(text)
    button:SetText(caption)
    return button
end

-- setEnabled greys a button out and blocks its clicks (3.3.5a Buttons have
-- Enable/Disable, but a disabled flat button would keep its colors).
local function setEnabled(button, enabled)
    if enabled then button:Enable() else button:Disable() end
    button:SetAlpha(enabled and 1 or 0.4)
end

-- setPrimary marks the button for the next step (green), or restores the
-- button's own color (`baseColor`, set where a button gets another color).
local function setPrimary(button, primary)
    local c = primary and { 0.10, 0.42, 0.20 } or button.baseColor or { 0.08, 0.25, 0.34 }
    button:SetBackdropColor(c[1], c[2], c[3], 0.98)
    if primary then button:SetBackdropBorderColor(1.00, 0.82, 0.00, 0.95)
    else button:SetBackdropBorderColor(0.20, 0.63, 0.82, 0.92) end
    button:GetFontString():SetTextColor(primary and 1.00 or 0.70, primary and 1.00 or 0.93, primary and 1.00 or 1.00)
end

-- tip gives a frame a tooltip: a text, or a function of the frame returning one.
local function tip(frame, text)
    local function show(self)
        local value = type(text) == "function" and text(self) or text
        if not value then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(value, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end
    local function hide() GameTooltip:Hide() end
    if frame:GetScript("OnEnter") then frame:HookScript("OnEnter", show) else frame:SetScript("OnEnter", show) end
    if frame:GetScript("OnLeave") then frame:HookScript("OnLeave", hide) else frame:SetScript("OnLeave", hide) end
end

-- pane: a dark box with a gold heading at its top left. Without a width it
-- reaches the parent's right edge, without a height its bottom.
local function pane(parent, x, y, width, height, name)
    local frame = CreateFrame("Frame", name, parent)
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    if width then frame:SetWidth(width) else frame:SetPoint("RIGHT", parent, "RIGHT", 0, 0) end
    if height then frame:SetHeight(height) else frame:SetPoint("BOTTOM", parent, "BOTTOM", 0, 0) end
    makeBackdrop(frame, 0.035, 0.070, 0.105, 0.97)
    frame.heading = label(frame, "GameFontNormal", 11, {1.00, 0.80, 0.32})
    frame.heading:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -10)
    return frame
end

-- listRow: a clickable line with a left text and right-aligned columns
-- ({ width, ... } from the right edge). Left and right clicks reach OnClick.
local function listRow(parent, width, columns, name)
    local row = CreateFrame("Button", name, parent)
    row:SetWidth(width)
    row:SetHeight(ns.ROW_HEIGHT - 1)
    makeBackdrop(row, 0.045, 0.09, 0.13, 0.98)
    row:SetBackdropBorderColor(0, 0, 0, 0)
    local right = -6
    row.columns = {}
    for i, columnWidth in ipairs(columns or {}) do
        local column = label(row, "GameFontNormalSmall", 9, {0.75, 0.85, 0.92})
        column:SetPoint("RIGHT", row, "RIGHT", right, 0)
        column:SetWidth(columnWidth)
        column:SetJustifyH("RIGHT")
        column:SetWordWrap(false)
        row.columns[i] = column
        right = right - columnWidth - 6
    end
    local text = label(row, "GameFontNormalSmall", 10, {0.82, 0.91, 0.96})
    text:SetPoint("LEFT", row, "LEFT", 7, 0)
    text:SetPoint("RIGHT", row, "RIGHT", right, 0)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    row:SetFontString(text)
    row.text = text
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    return row
end

-- highlight colors a row: "selected", "winner", "open", "muted" or nil.
local ROW_COLORS = {
    selected = { 0.10, 0.21, 0.29 }, winner = { 0.07, 0.20, 0.12 }, open = { 0.16, 0.10, 0.22 },
    heading = { 0, 0, 0 }, muted = { 0.03, 0.05, 0.07 },
}
local function highlight(row, kind)
    local color = ROW_COLORS[kind] or { 0.045, 0.09, 0.13 }
    row:SetBackdropColor(color[1], color[2], color[3], kind == "heading" and 0 or 0.98)
end

-- classColor colors a raid member's name like the raid frames do. The class
-- of each member is read once per redraw (a 25-player raid draws dozens of
-- names; scanning the roster for each one made redraws quadratic).
local classes
local function classColor(fontString, name)
    if not classes then
        classes = {}
        for _, member in ipairs(ns.members()) do classes[ns.lower(member.name)] = member.class end
    end
    local class = classes[ns.lower(name or "")]
    local color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if color then fontString:SetTextColor(color.r, color.g, color.b)
    else fontString:SetTextColor(0.82, 0.91, 0.96) end
end

local function itemTooltip(owner, link)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    local itemString = type(link) == "string" and string.match(link, "item:[%-%d:]+")
    if itemString then GameTooltip:SetHyperlink(itemString) else GameTooltip:ClearLines() end
end

ns.makeBackdrop, ns.label, ns.flatButton, ns.tip, ns.pane = makeBackdrop, label, flatButton, tip, pane
ns.listRow, ns.highlight, ns.classColor, ns.setEnabled, ns.itemTooltip = listRow, highlight, classColor, setEnabled, itemTooltip
ns.setPrimary = setPrimary

-- ns.onResize(fn) calls fn(width, height) with the content area's size now and
-- whenever the window changes size: tabs place their panes and fit their lists.
local resizers = {}
function ns.onResize(fn)
    table.insert(resizers, fn)
    fn(ns.CONTENT_WIDTH, ns.CONTENT_HEIGHT)
end

-- ns.rowList(make) is a list's visible rows: rows.fit(n) makes the first n
-- rows of a pool the list (make(i) creates a missing one) and hides the rest.
function ns.rowList(make)
    local rows, pool = {}, {}
    rows.fit = function(count)
        for i = 1, math.max(count, table.getn(pool)) do
            if i <= count then
                pool[i] = pool[i] or make(i)
                rows[i] = pool[i]
            else
                rows[i] = nil
                pool[i]:Hide()
            end
        end
    end
    return rows
end

-- ns.sideBySide: the left pane keeps `leftWidth` at the default size and takes
-- 40% of any extra width; the right pane fills the rest beside it.
function ns.sideBySide(left, right, leftWidth)
    right:ClearAllPoints()
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", 12, 0)
    right:SetPoint("BOTTOMRIGHT", left:GetParent(), "BOTTOMRIGHT", 0, 0)
    ns.onResize(function(width) left:SetWidth(leftWidth + math.floor((width - ns.CONTENT_WIDTH) * 0.4)) end)
end

-- ns.rowsFit: how many list rows fit in `height` minus the space above and below.
function ns.rowsFit(height, above, below)
    return math.max(1, math.floor((height - above - below) / ns.ROW_HEIGHT))
end

-- scrollable makes a frame scroll its list with the mouse wheel: `get` and
-- `set` read and write the list's offset, `redraw` draws it again.
function ns.scrollable(frame, get, set, redraw)
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta)
        set(math.max(0, get() - delta))
        redraw()
    end)
end

---------------------------------------------------------------------------
-- The window and its tabs
---------------------------------------------------------------------------
local Ledger = CreateFrame("Frame", "RaidLedgerFrame", UIParent)
ns.Ledger = Ledger
Ledger:SetWidth(WIDTH)
Ledger:SetHeight(HEIGHT)
Ledger:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
Ledger:SetFrameStrata("DIALOG")
Ledger:SetClampedToScreen(true)
Ledger:SetToplevel(true)   -- clicking it raises it above RaidWishlist
Ledger:EnableMouse(true)
Ledger:SetMovable(true)
Ledger:RegisterForDrag("LeftButton")
Ledger:SetScript("OnDragStart", function(self) self:StartMoving() end)
Ledger:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
Ledger:SetResizable(true)
Ledger:SetMinResize(WIDTH, HEIGHT)
makeBackdrop(Ledger, 0.018, 0.031, 0.055, 0.97)

local accent = Ledger:CreateTexture(nil, "ARTWORK")
accent:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
accent:SetPoint("TOPLEFT", Ledger, "TOPLEFT", 10, -9)
accent:SetPoint("TOPRIGHT", Ledger, "TOPRIGHT", -10, -9)
accent:SetHeight(2)
accent:SetVertexColor(0.25, 0.78, 1.00, 0.95)

local title = label(Ledger, "GameFontNormalLarge", 17, {0.54, 0.88, 1.00})
title:SetPoint("TOPLEFT", Ledger, "TOPLEFT", 18, -16)
title:SetText("RaidLedger")   -- the addon's name, not translated

local close = CreateFrame("Button", nil, Ledger)
close:SetWidth(24)
close:SetHeight(24)
close:SetPoint("TOPRIGHT", Ledger, "TOPRIGHT", -13, -12)
makeBackdrop(close, 0.10, 0.16, 0.21, 0.95)
local closeText = label(close, "GameFontNormal", 14, {0.72, 0.84, 0.90})
closeText:SetPoint("CENTER", close, "CENTER", 0, 0)
closeText:SetText("X")
close:SetScript("OnClick", function() Ledger:Hide() end)
tip(close, L["Close the ledger (/ledger opens it again)"])

-- The content area every tab panel fills.
local content = CreateFrame("Frame", "RaidLedgerContent", Ledger)
content:SetPoint("TOPLEFT", Ledger, "TOPLEFT", 16, CONTENT_TOP)
content:SetPoint("BOTTOMRIGHT", Ledger, "BOTTOMRIGHT", -16, CONTENT_BOTTOM)
ns.content = content

-- The grip in the lower right corner sizes the window.
local grip = CreateFrame("Button", "RaidLedgerResize", Ledger)
grip:SetWidth(16)
grip:SetHeight(16)
grip:SetPoint("BOTTOMRIGHT", Ledger, "BOTTOMRIGHT", -4, 4)
grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
tip(grip, L["Drag to resize the window"])

local status = label(Ledger, "GameFontNormalSmall", 10, {0.42, 0.60, 0.68})
status:SetPoint("BOTTOMLEFT", Ledger, "BOTTOMLEFT", 18, 12)
status:SetPoint("RIGHT", grip, "LEFT", -6, 0)
status:SetHeight(14)
status:SetJustifyH("LEFT")
status:SetWordWrap(false)
status:SetText(L["Pick a tab above  |  /ledger help"])

local tabs, tabOrder, current = {}, {}, nil
local TAB_X = 18

-- ns.addTab adds a tab: `panel` fills the content area, `caption` may be a
-- function returning the caption (e.g. with a count). `refresh` redraws it.
function ns.addTab(id, caption, panel, refresh, name)
    local button = CreateFrame("Button", name, Ledger)
    button:SetHeight(22)
    makeBackdrop(button, 0.05, 0.13, 0.19, 0.98)
    local text = label(button, "GameFontNormal", 10, {0.60, 0.80, 0.90})
    text:SetPoint("CENTER", button, "CENTER", 0, 0)
    button:SetFontString(text)
    button:SetPoint("TOPLEFT", Ledger, "TOPLEFT", TAB_X, -44)
    panel:SetParent(content)
    panel:ClearAllPoints()
    panel:SetAllPoints(content)
    panel:Hide()
    local tab = { id = id, caption = caption, panel = panel, refresh = refresh, button = button }
    tabs[id] = tab
    table.insert(tabOrder, tab)
    button:SetScript("OnClick", function() ui.show(id) end)
    -- Each button is as wide as its longest caption.
    button:SetText(type(caption) == "function" and caption() or caption)
    button:SetWidth(math.max(80, (button:GetTextWidth() or 60) + 28))
    TAB_X = TAB_X + button:GetWidth() + 4
    return tab
end

local function drawTabs()
    for _, tab in ipairs(tabOrder) do
        tab.button:SetText(type(tab.caption) == "function" and tab.caption() or tab.caption)
        local active = tab == current
        tab.button:SetBackdropColor(active and 0.12 or 0.05, active and 0.30 or 0.13, active and 0.42 or 0.19, 0.98)
        tab.button:GetFontString():SetTextColor(active and 1.00 or 0.60, active and 0.86 or 0.80, active and 0.45 or 0.90)
    end
end

function ui.refresh()
    classes = nil   -- the group may have changed
    ns.core.refreshLinks()
    drawTabs()
    if current and current.refresh and Ledger:IsShown() then current.refresh() end
end

function ui.status(text) status:SetText(text or "") end
function ui.shown() return Ledger:IsShown() end
function ui.tab() return current and current.id end

-- ui.show opens the window on a tab; "export" is the awards tab's export view.
function ui.show(id)
    local view
    if id == "export" then id, view = "awards", "export" end
    local tab = tabs[id or ""] or current or tabOrder[1]
    if current ~= tab then
        if current then current.panel:Hide() end
        current = tab
        tab.panel:Show()
    end
    if tab.view then tab.view(view) end
    Ledger:Show()
    ui.refresh()
end

function ui.toggle()
    if Ledger:IsShown() then Ledger:Hide() else ui.show() end
end

-- Size and scale are saved in RaidLedgerDB.window; the client keeps the place.
local function window()
    local db = ns.ensureDatabase()
    db.window = db.window or {}
    return db.window
end

-- A window may grow to the screen at its scale; a larger scale may shrink it.
local function fitScreen()
    local scale = Ledger:GetScale()
    local maxWidth = math.max(WIDTH, math.floor(UIParent:GetWidth() / scale))
    local maxHeight = math.max(HEIGHT, math.floor(UIParent:GetHeight() / scale))
    Ledger:SetMaxResize(maxWidth, maxHeight)
    Ledger:SetWidth(math.max(WIDTH, math.min(Ledger:GetWidth(), maxWidth)))
    Ledger:SetHeight(math.max(HEIGHT, math.min(Ledger:GetHeight(), maxHeight)))
end

-- relayout passes the content area's size to every tab, then redraws.
local function relayout()
    local width, height = Ledger:GetWidth() - 32, Ledger:GetHeight() + CONTENT_TOP - CONTENT_BOTTOM
    for _, fn in ipairs(resizers) do fn(width, height) end
    if Ledger:IsShown() then ui.refresh() end
end
Ledger:SetScript("OnSizeChanged", relayout)

local function saveSize()
    local saved = window()
    saved.width, saved.height = math.floor(Ledger:GetWidth() + 0.5), math.floor(Ledger:GetHeight() + 0.5)
end
-- The window grows right and down, up to the screen's edges.
grip:SetScript("OnMouseDown", function()
    local scale = Ledger:GetScale()
    local left, top = Ledger:GetLeft() or 0, Ledger:GetTop() or HEIGHT
    Ledger:SetMaxResize(math.max(WIDTH, math.floor(UIParent:GetWidth() / scale - left)), math.max(HEIGHT, math.floor(top)))
    Ledger:StartSizing("BOTTOMRIGHT")
end)
grip:SetScript("OnMouseUp", function()
    Ledger:StopMovingOrSizing()
    saveSize()
    relayout()
end)

function ui.scale() return Ledger:GetScale() end

-- ui.setScale sets the window's scale (0.6-1.5) and saves it; false when out of range.
function ui.setScale(scale)
    scale = tonumber(scale)
    if not scale or scale < SCALE_MIN - 0.001 or scale > SCALE_MAX + 0.001 then return false end
    scale = math.floor(scale * 10 + 0.5) / 10
    Ledger:SetScale(scale)
    if ui.setMasterLootScale then ui.setMasterLootScale(scale) end
    window().scale = scale
    fitScreen()
    saveSize()
    relayout()
    return true
end

-- Restores the saved size and scale (at login, after the SavedVariables).
local function restoreWindow()
    local saved = window()
    local scale = saved.scale or 1
    Ledger:SetScale(scale)
    if ui.setMasterLootScale then ui.setMasterLootScale(scale) end
    Ledger:SetWidth(saved.width or WIDTH)
    Ledger:SetHeight(saved.height or HEIGHT)
    fitScreen()
    relayout()
end

function ui.resetPosition()
    local db = ns.ensureDatabase()
    db.window = nil
    Ledger:ClearAllPoints()
    Ledger:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    restoreWindow()
    ui.show()
end

ns.commands.scale = function(rest)
    local percent = tonumber(rest)
    if percent and ui.setScale(percent / 100) then
        ns.say(string.format(L["window scale: %d%%."], math.floor(ui.scale() * 100 + 0.5)))
    else
        ns.say(string.format(L["usage: /ledger scale <%d-%d> (percent)"], SCALE_MIN * 100, SCALE_MAX * 100))
    end
    if ns.refreshOptions then ns.refreshOptions() end
end
table.insert(ns.help, L["/ledger scale <percent> - make the window smaller or larger; drag its lower right corner to resize it"])

-- Opening the window redraws it: shared awards of items that were not cached
-- yet show their links by now.
Ledger:HookScript("OnShow", function() ui.refresh() end)
Ledger:HookScript("OnHide", function() GameTooltip:Hide() end)

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
    restoreWindow()
    ui.show(tabOrder[1] and tabOrder[1].id)
    if ForgeTestBridge and ForgeTestBridge.RegisterFrame then
        ForgeTestBridge:RegisterFrame("RaidLedgerFrame", Ledger)
        for _, tab in ipairs(tabOrder) do
            ForgeTestBridge:RegisterFrame("RaidLedgerTab" .. tab.id, tab.button)
        end
        ForgeTestBridge:RegisterFrame("RaidLedgerResize", grip)
    end
end)
