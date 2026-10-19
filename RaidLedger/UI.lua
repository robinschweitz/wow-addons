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
local WIDTH, HEIGHT = 760, 480
local CONTENT_TOP, CONTENT_HEIGHT = -72, 376
ns.CONTENT_WIDTH, ns.CONTENT_HEIGHT = WIDTH - 32, CONTENT_HEIGHT
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

-- pane: a dark box with a gold heading at its top left.
local function pane(parent, x, y, width, height, name)
    local frame = CreateFrame("Frame", name, parent)
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    frame:SetWidth(width)
    frame:SetHeight(height)
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
content:SetWidth(ns.CONTENT_WIDTH)
content:SetHeight(CONTENT_HEIGHT)
ns.content = content

local status = label(Ledger, "GameFontNormalSmall", 10, {0.42, 0.60, 0.68})
status:SetPoint("BOTTOMLEFT", Ledger, "BOTTOMLEFT", 18, 12)
status:SetWidth(WIDTH - 36)
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

function ui.resetPosition()
    Ledger:ClearAllPoints()
    Ledger:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    ui.show()
end

-- Opening the window redraws it: shared awards of items that were not cached
-- yet show their links by now.
Ledger:HookScript("OnShow", function() ui.refresh() end)
Ledger:HookScript("OnHide", function() GameTooltip:Hide() end)

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
    ui.show(tabOrder[1] and tabOrder[1].id)
    if ForgeTestBridge and ForgeTestBridge.RegisterFrame then
        ForgeTestBridge:RegisterFrame("RaidLedgerFrame", Ledger)
        for _, tab in ipairs(tabOrder) do
            ForgeTestBridge:RegisterFrame("RaidLedgerTab" .. tab.id, tab.button)
        end
    end
end)
