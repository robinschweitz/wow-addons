-- BEUTE tab: the loot list on the left (this corpse's drops, then the open
-- items held until they are rolled), the selected item on the right: start a
-- roll (or a free BoE roll), every roll with what the roller has so far, and
-- the hand-out buttons. Click a roll to make its player the recipient,
-- right-click it to pass or count it differently.
local _, ns = ...
local L = ns.L
local core, ui = ns.core, ns.ui
local roster = core.roster
local ITEM_ROWS, ROLL_ROWS = 19, 10
local LEFT_WIDTH = 288
local RIGHT_X = LEFT_WIDTH + 12
local RIGHT_WIDTH = ns.CONTENT_WIDTH - RIGHT_X

local panel = CreateFrame("Frame", "RaidLedgerLootTab")
local itemOffset, rollOffset = 0, 0
local openRecord          -- an open award picked in the loot list (it is rolled from here)

local itemPane = ns.pane(panel, 0, 0, LEFT_WIDTH, ns.CONTENT_HEIGHT, "RaidLedgerRollPane")
local clearLoot = ns.flatButton(itemPane, L["EMPTY"], 64)
clearLoot:SetHeight(18)
clearLoot:SetPoint("TOPRIGHT", itemPane, "TOPRIGHT", -8, -6)
local emptyText = ns.label(itemPane, "GameFontNormalSmall", 11, {0.42, 0.61, 0.70})
emptyText:SetPoint("CENTER", itemPane, "CENTER", 0, 10)
emptyText:SetWidth(LEFT_WIDTH - 30)
emptyText:SetText(L["Open the master loot window\nPlayers can then use /rnd"])
emptyText:SetJustifyH("CENTER")

local itemRows = {}
for i = 1, ITEM_ROWS do
    local row = ns.listRow(itemPane, LEFT_WIDTH - 20, { 66, 34 }, "RaidLedgerItemRow" .. i)
    row:SetPoint("TOPLEFT", itemPane, "TOPLEFT", 10, -28 - (i - 1) * ns.ROW_HEIGHT)
    itemRows[i] = row
end

local detail = ns.pane(panel, RIGHT_X, 0, RIGHT_WIDTH, ns.CONTENT_HEIGHT, "RaidLedgerDetailPane")
detail.heading:SetText(L["SELECTED ITEM"])

-- The item's name; hovering it shows the item.
local titleButton = CreateFrame("Button", nil, detail)
titleButton:SetPoint("TOPLEFT", detail, "TOPLEFT", 12, -28)
titleButton:SetWidth(RIGHT_WIDTH - 24)
titleButton:SetHeight(18)
local itemTitle = ns.label(titleButton, "GameFontHighlight", 13, {0.94, 0.97, 1.00}, "RaidLedgerItem")
itemTitle:SetAllPoints(titleButton)
itemTitle:SetJustifyH("LEFT")
itemTitle:SetWordWrap(false)
local stateLine = ns.label(detail, "GameFontNormalSmall", 10, {0.45, 0.68, 0.80}, "RaidLedgerRollDetail")
stateLine:SetPoint("TOPLEFT", titleButton, "BOTTOMLEFT", 0, -4)
stateLine:SetWidth(RIGHT_WIDTH - 24)
stateLine:SetHeight(14)
stateLine:SetJustifyH("LEFT")
stateLine:SetWordWrap(false)

local startButton = ns.flatButton(detail, L["ROLL"], 118, "RaidLedgerStart")
startButton:SetPoint("TOPLEFT", detail, "TOPLEFT", 12, -70)
local freeButton = ns.flatButton(detail, L["FREE BOE ROLL"], 118, "RaidLedgerFreeRoll")
freeButton:SetPoint("LEFT", startButton, "RIGHT", 6, 0)

local rollHeading = ns.label(detail, "GameFontNormal", 10, {1.00, 0.80, 0.32})
rollHeading:SetPoint("TOPLEFT", detail, "TOPLEFT", 12, -104)
local soFarHeading = ns.label(detail, "GameFontNormalSmall", 9, {0.55, 0.72, 0.80})
soFarHeading:SetPoint("TOPRIGHT", detail, "TOPRIGHT", -54, -106)
soFarHeading:SetText(L["SO FAR"])
local rollValueHeading = ns.label(detail, "GameFontNormalSmall", 9, {0.55, 0.72, 0.80})
rollValueHeading:SetPoint("TOPRIGHT", detail, "TOPRIGHT", -16, -106)
rollValueHeading:SetText(L["RESULT"])

local rollRows = {}
for i = 1, ROLL_ROWS do
    local row = ns.listRow(detail, RIGHT_WIDTH - 20, { 30, 40 }, "RaidLedgerRollLine" .. i)
    row:SetPoint("TOPLEFT", detail, "TOPLEFT", 10, -120 - (i - 1) * ns.ROW_HEIGHT)
    rollRows[i] = row
end
local noRolls = ns.label(detail, "GameFontNormalSmall", 10, {0.42, 0.61, 0.70})
noRolls:SetPoint("TOPLEFT", detail, "TOPLEFT", 16, -124)

local recipientHint = ns.label(detail, "GameFontNormalSmall", 9, {0.45, 0.60, 0.68})
recipientHint:SetPoint("TOPLEFT", detail, "TOPLEFT", 14, -306)
recipientHint:SetText(L["RECIPIENT NAME"])
local recipientBox = CreateFrame("EditBox", "RaidLedgerRecipient", detail, "InputBoxTemplate")
recipientBox:SetPoint("TOPLEFT", detail, "TOPLEFT", 18, -318)
recipientBox:SetWidth(186)
recipientBox:SetHeight(22)
recipientBox:SetAutoFocus(false)
recipientBox:SetMaxLetters(24)
local allButton = ns.flatButton(detail, L["ALL (%d)"], 90, "RaidLedgerAllMembers")
allButton:SetHeight(22)
allButton:SetPoint("LEFT", recipientBox, "RIGHT", 8, 0)

local giveButton = ns.flatButton(detail, L["GIVE + RECORD"], 150, "RaidLedgerAward")
giveButton:SetPoint("TOPLEFT", detail, "TOPLEFT", 12, -344)
local parkButton = ns.flatButton(detail, L["PARK"], 80, "RaidLedgerPark")
parkButton:SetPoint("LEFT", giveButton, "RIGHT", 6, 0)
ns.makeBackdrop(parkButton, 0.20, 0.12, 0.30, 0.98)
local deButton = ns.flatButton(detail, L["DE"], 50, "RaidLedgerDisenchant")
deButton:SetPoint("LEFT", parkButton, "RIGHT", 6, 0)
local bankButton = ns.flatButton(detail, L["BANK"], 66, "RaidLedgerBank")
bankButton:SetPoint("LEFT", deButton, "RIGHT", 6, 0)
for _, button in ipairs({ deButton, bankButton }) do ns.makeBackdrop(button, 0.16, 0.12, 0.24, 0.98) end

---------------------------------------------------------------------------
-- The whole raid by group (ALLE) and the roll menu (right-click)
---------------------------------------------------------------------------
local picker = CreateFrame("Frame", "RaidLedgerMembers", panel)
picker:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -100)
picker:SetWidth(ns.CONTENT_WIDTH)
picker:SetHeight(130)
picker:SetFrameLevel(panel:GetFrameLevel() + 20)
ns.makeBackdrop(picker, 0.025, 0.052, 0.078, 0.99)
picker:EnableMouse(true)
picker:Hide()
picker.headings, picker.cells = {}, {}
local PICKER_WIDTH = math.floor((ns.CONTENT_WIDTH - 22) / 5) - 4
for g = 1, 5 do
    local x = 11 + (g - 1) * (PICKER_WIDTH + 4)
    local heading = ns.label(picker, "GameFontNormalSmall", 9, {1.00, 0.80, 0.32})
    heading:SetPoint("TOPLEFT", picker, "TOPLEFT", x + 2, -8)
    heading:SetText(string.format(L["GROUP %d"], g))
    picker.headings[g] = heading
    picker.cells[g] = {}
    for row = 1, 5 do
        local cell = ns.listRow(picker, PICKER_WIDTH, nil)
        cell:SetPoint("TOPLEFT", picker, "TOPLEFT", x, -21 - (row - 1) * 20)
        cell:SetScript("OnClick", function(self)
            if self.fullName then recipientBox:SetText(self.fullName) end
            picker:Hide()
        end)
        picker.cells[g][row] = cell
    end
end
ns.Ledger:HookScript("OnHide", function() picker:Hide() end)

local menu = CreateFrame("Frame", "RaidLedgerRollMenu", ns.Ledger)
menu:SetWidth(132)
menu:SetFrameLevel(ns.Ledger:GetFrameLevel() + 40)
ns.makeBackdrop(menu, 0.035, 0.070, 0.105, 0.99)
menu:EnableMouse(true)
menu:Hide()
menu.title = ns.label(menu, "GameFontNormalSmall", 10, {0.94, 0.97, 1.00})
menu.title:SetPoint("TOPLEFT", menu, "TOPLEFT", 10, -8)
menu.title:SetWidth(112)
menu.title:SetJustifyH("LEFT")
menu.title:SetWordWrap(false)
menu.options = {}
local MENU_TIPS = { pass = L["The player passes: the next-best roll wins"], ms = L["Count it as main spec (1-100)"],
    enh = L["Count it as enhanced main spec: asks for the points"], os = L["Count it as off spec (1-99)"],
    none = L["The roll does not count"] }
for _, option in ipairs({ { "Pass", L["PASS"], "pass" }, { "MS", L["MAIN SPEC"], "ms" },
        { "Enhanced", L["ENHANCED..."], "enh" }, { "OS", L["OFF SPEC"], "os" },
        { "None", L["DOES NOT COUNT"], "none" } }) do
    local button = ns.flatButton(menu, option[2], 112, "RaidLedgerRollMenu" .. option[1])
    button:SetHeight(18)
    if option[3] == "pass" then ns.makeBackdrop(button, 0.20, 0.12, 0.30, 0.98) end
    button.how = option[3]
    button:SetScript("OnClick", function(self)
        menu:Hide()
        if self.how == "enh" then roster.askPoints(menu.name, menu.record)
        else roster.apply(menu.name, self.how, nil, menu.record) end
    end)
    ns.tip(button, MENU_TIPS[option[3]])
    table.insert(menu.options, button)
end
ns.Ledger:HookScript("OnHide", function() menu:Hide() end)

-- ns.openRollMenu opens the pass / recount menu for a counted roll, on the
-- selected item or on `record` (an award's roll log).
function ns.openRollMenu(row, roll, record)
    if menu:IsShown() and menu.name == roll.name then menu:Hide() return end
    if roster.denied() then return end
    menu.name, menu.record = roll.name, record
    menu.title:SetText(string.format("%s (%d)", roll.name, roll.value))
    local free = roll.kind == "boe"
    local y = -26
    for _, option in ipairs(menu.options) do
        if free and option.how ~= "pass" and option.how ~= "none" then
            option:Hide()
        else
            option:ClearAllPoints()
            option:SetPoint("TOPLEFT", menu, "TOPLEFT", 10, y)
            option:Show()
            y = y - 20
        end
    end
    menu:SetHeight(-y + 6)
    menu:ClearAllPoints()
    local bottom, ledgerBottom = row:GetBottom(), ns.Ledger:GetBottom()
    if bottom and ledgerBottom and bottom - menu:GetHeight() - 2 < ledgerBottom + 8 then
        menu:SetPoint("BOTTOMRIGHT", row, "TOPRIGHT", 0, 2)
    else
        menu:SetPoint("TOPRIGHT", row, "BOTTOMRIGHT", 0, -2)
    end
    menu:Show()
end

-- ns.rollLineText: one roll for a list, "Name  MS 21-120  [WL #2]  - won".
function ns.rollLineText(r, won, itemID)
    local text = r.name
    if (r.round or 1) > 1 then text = text .. string.format(L["  (tie-break %d)"], r.round - 1) end
    if r.note then
        return "|cff777777" .. text .. string.format(L["  - ignored: %s"], L[r.note] or r.note) .. "|r"
    end
    if r.kind then text = text .. "  " .. core.rollLabel(r) end
    if r.was then text = text .. L["  (corrected)"] end
    local wish = core.wishOf(r.name, itemID)
    if wish then text = text .. string.format(L["  [WL #%d]"], wish.rank) end
    if won then text = text .. L["  - won"] end
    return text
end

-- ns.addPlayerLines adds what a player got this raid to the tooltip.
function ns.addPlayerLines(name)
    GameTooltip:AddLine(core.summaryLine(name), 0.45, 0.85, 1.00)
    for _, record in ipairs(core.history()) do
        if record.state ~= "deleted" and ns.lower(record.recipient) == ns.lower(name) then
            GameTooltip:AddLine("  " .. record.item .. (record.spec and ("  " .. string.upper(record.spec)) or "")
                .. (record.token and L["  (token)"] or ""))
        end
    end
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
local OPEN_COLOR, NOBODY_COLOR = { 0.85, 0.62, 1.00 }, { 0.55, 0.55, 0.55 }

-- lootLines: the drops first, then a heading and the open awards.
local function lootLines()
    local lines = {}
    for _, entry in ipairs(core.active()) do table.insert(lines, { entry = entry }) end
    local open = core.openRecords()
    if table.getn(open) > 0 then
        table.insert(lines, { heading = string.format(L["OPEN ITEMS (%d)"], table.getn(open)) })
        for _, record in ipairs(open) do table.insert(lines, { record = record }) end
    end
    return lines, table.getn(open)
end

local function entryStatus(entry)
    if entry.winners and entry.winners[1] then return string.format(L["%d WINNERS"], table.getn(entry.winners)), {0.45, 0.85, 0.55} end
    if entry.winner then return entry.winner.name, {0.45, 0.85, 0.55} end
    if entry.endsAt then return string.format(L["%ds LEFT"], math.max(0, math.ceil(entry.endsAt - GetTime()))), {1.00, 0.79, 0.31} end
    if entry.nobody then return L["NOBODY"], NOBODY_COLOR end
    return string.format(L["%d ROLLS"], core.activeRollCount(entry)), {0.58, 0.72, 0.80}
end

local function drawItems()
    local lines, openCount = lootLines()
    local selected = core.selectedEntry()
    itemOffset = math.max(0, math.min(itemOffset, table.getn(lines) - ITEM_ROWS))
    itemPane.heading:SetText(openCount > 0 and string.format(L["LOOT (%d)  |  %d OPEN"], table.getn(core.active()), openCount)
        or string.format(L["LOOT (%d)"], table.getn(core.active())))
    for i, row in ipairs(itemRows) do
        local line = lines[i + itemOffset]
        row.line = line
        if not line then
            row:Hide()
        elseif line.heading then
            row:SetText(line.heading)
            row.text:SetTextColor(OPEN_COLOR[1], OPEN_COLOR[2], OPEN_COLOR[3])
            row.columns[1]:SetText("")
            row.columns[2]:SetText("")
            ns.highlight(row, "heading")
            row:Show()
        else
            local item = line.entry and line.entry.item or line.record.item
            local itemID = core.itemIDFromLink(item)
            local count = line.entry and line.entry.count or 1
            row:SetText((count > 1 and (count .. "x ") or "") .. item)
            row.text:SetTextColor(0.82, 0.91, 0.96)
            local text, color
            if line.entry then text, color = entryStatus(line.entry)
            else text, color = string.format(L["with %s"], line.record.recipient or "?"), OPEN_COLOR end
            row.columns[1]:SetText(text)
            row.columns[1]:SetTextColor(color[1], color[2], color[3])
            local wished = table.getn(core.wishersOf(itemID))
            row.columns[2]:SetText(core.knowsWishlists() and string.format(L["WL %d"], wished) or "")
            if wished > 0 then row.columns[2]:SetTextColor(0.45, 0.85, 0.55) else row.columns[2]:SetTextColor(0.5, 0.5, 0.5) end
            local isSelected = (line.entry and line.entry == selected) or (line.record and line.record == openRecord)
            ns.highlight(row, isSelected and "selected" or (line.record and "open") or nil)
            row:Show()
        end
    end
    if table.getn(lines) == 0 then emptyText:Show() else emptyText:Hide() end
end

-- wonBy: whether roll `r` of the shown log won (a bundle has one per copy).
local function wonBy(entry, log)
    local winner = entry and not entry.winners and entry.winner and core.winningRoll(log)
    local bundle = {}
    for _, w in ipairs(entry and entry.winners or {}) do bundle[ns.lower(w.name)] = w.value end
    return function(r)
        if r.note or not r.kind then return false end
        if entry and entry.winners then return bundle[ns.lower(r.name)] == r.value end
        return r == winner
    end
end

local function drawRolls(entry)
    local log = entry and core.sortedRollLog(entry) or {}
    local count = table.getn(log)
    rollOffset = math.max(0, math.min(rollOffset, count - ROLL_ROWS))
    rollHeading:SetText(count > ROLL_ROWS and string.format(L["ROLLS (%d, SCROLL)"], count) or string.format(L["ROLLS (%d)"], count))
    local won = wonBy(entry, log)
    local itemID = entry and core.itemIDFromLink(entry.item)
    for i, row in ipairs(rollRows) do
        local r = log[i + rollOffset]
        row.roll = r and r.kind and not r.note and r or nil
        row.playerName = r and r.name
        if r then
            local isWinner = won(r)
            row:SetText(ns.rollLineText(r, isWinner, itemID))
            if not r.note then ns.classColor(row.text, r.name) end
            row.columns[1]:SetText(tostring(r.value))
            row.columns[2]:SetText(r.kind and not r.note and r.kind ~= "boe" and tostring(r.tally or 0) or "")
            if r.note then row.columns[1]:SetTextColor(0.45, 0.45, 0.45)
            elseif isWinner then row.columns[1]:SetTextColor(0.45, 0.85, 0.55)
            else row.columns[1]:SetTextColor(1.00, 0.79, 0.31) end
            ns.highlight(row, isWinner and "winner" or (r.note and "muted") or nil)
            row:Show()
        else
            row:Hide()
        end
    end
    if count == 0 then
        noRolls:SetText(entry and (entry.endsAt and L["No rolls yet: players type /rnd"] or L["No player rolls recorded"]) or "")
        noRolls:Show()
    else
        noRolls:Hide()
    end
    for _, heading in ipairs({ soFarHeading, rollValueHeading }) do
        if count > 0 then heading:Show() else heading:Hide() end
    end
end

local function drawPicker()
    local members = ns.members()
    allButton:SetText(string.format(L["ALL (%d)"], table.getn(members)))
    local rows = { 0, 0, 0, 0, 0 }
    for g = 1, 5 do
        for row = 1, 5 do picker.cells[g][row]:Hide() end
    end
    for _, m in ipairs(members) do
        local g = math.min(math.max(tonumber(m.group) or 1, 1), 5)
        if rows[g] < 5 then
            rows[g] = rows[g] + 1
            local cell = picker.cells[g][rows[g]]
            cell.fullName = m.name
            cell:SetText(m.name)
            ns.classColor(cell.text, m.name)
            cell:Show()
        end
    end
    for g = 1, 5 do
        if rows[g] > 0 then picker.headings[g]:Show() else picker.headings[g]:Hide() end
    end
end

local function drawDetail()
    local entry = core.selectedEntry()
    if entry then openRecord = nil end
    local mayEdit = not ns.mayEdit or ns.mayEdit()
    local rolling = entry and entry.endsAt and not entry.winner
    if entry then
        local count = entry.count or 1
        itemTitle:SetText((count > 1 and (count .. "x ") or "") .. entry.item)
        local text = entryStatus(entry)
        if entry.winners and entry.winners[1] then
            local names = {}
            for _, r in ipairs(entry.winners) do table.insert(names, r.name) end
            stateLine:SetText(string.format(L["WINNERS: %s"], table.concat(names, ", ")))
        elseif entry.winner then
            stateLine:SetText(string.format(L["WINNER: %s (%d)"], entry.winner.name, entry.winner.value))
        elseif rolling then
            stateLine:SetText(string.format(L["%d rolls  |  %ds remaining"], core.activeRollCount(entry), math.max(0, math.ceil(entry.endsAt - GetTime()))))
        elseif entry.nobody then
            stateLine:SetText(L["Nobody wanted it: roll again, free BoE roll, DE or BANK."])
        else
            stateLine:SetText(entry.later and L["Open item: start its roll."] or L["Not rolled yet: start the roll."])
        end
        startButton:SetText((entry.winner or entry.nobody) and L["ROLL AGAIN"] or L["ROLL"])
        ns.setEnabled(startButton, mayEdit and not rolling)
        ns.setEnabled(freeButton, mayEdit and not rolling and not entry.later)
        giveButton:SetText(core.lootSlotOf(entry) and L["GIVE + RECORD"] or L["RECORD AWARD"])
        for _, button in ipairs({ giveButton, parkButton, deButton, bankButton }) do ns.setEnabled(button, mayEdit) end
        if entry.later then
            ns.setEnabled(parkButton, false)
            ns.setEnabled(deButton, false)
            ns.setEnabled(bankButton, false)
        end
        drawRolls(entry)
    elseif openRecord then
        itemTitle:SetText(openRecord.item)
        stateLine:SetText(string.format(L["Open: %s holds it until it is rolled. Click it, then ROLL."], openRecord.recipient or "?"))
        startButton:SetText(L["ROLL"])
        ns.setEnabled(startButton, mayEdit)
        ns.setEnabled(freeButton, false)
        for _, button in ipairs({ giveButton, parkButton, deButton, bankButton }) do ns.setEnabled(button, false) end
        drawRolls(nil)
    else
        itemTitle:SetText(L["Select an item on the left"])
        stateLine:SetText(L["Then ROLL starts the /rnd roll; the rolls appear below."])
        for _, button in ipairs({ startButton, freeButton, giveButton, parkButton, deButton, bankButton }) do ns.setEnabled(button, false) end
        drawRolls(nil)
    end
    drawPicker()
end

local function refresh()
    if openRecord and not core.isOpenAward(openRecord) then openRecord = nil end
    drawItems()
    drawDetail()
end

-- The box suggests the selected item's winner (after a roll, and for a
-- bundle's next copy).
function ui.suggest(entry)
    if entry and entry == core.selectedEntry() then
        recipientBox:SetText(entry.winner and entry.winner.name or "")
    end
end

local lootTab = ns.addTab("loot", function() return string.format(L["LOOT (%d)"], table.getn(core.active())) end, panel, refresh,
    "RaidLedgerTabButtonLoot")
ns.tip(lootTab.button, L["The loot to roll: start rolls, see every roll, hand items out"])

---------------------------------------------------------------------------
-- Clicks and tooltips
---------------------------------------------------------------------------
for _, row in ipairs(itemRows) do
    row:SetScript("OnClick", function(self)
        local line = self.line
        if not line or line.heading then return end
        if line.entry then
            if core.selectedEntry() ~= line.entry then rollOffset = 0 end
            core.select(line.entry)
            openRecord = nil
            recipientBox:SetText(line.entry.winner and line.entry.winner.name or "")
        else
            core.select(nil)
            openRecord = line.record
            recipientBox:SetText("")
        end
        ui.refresh()
    end)
    row:SetScript("OnEnter", function(self)
        local line = self.line
        if not line or line.heading then return end
        local item = line.entry and line.entry.item or line.record.item
        ns.itemTooltip(self, item)
        local wishers = core.wishersOf(core.itemIDFromLink(item))
        if table.getn(wishers) > 0 then
            GameTooltip:AddLine(string.format(L["On %d wishlists:"], table.getn(wishers)), 0.45, 0.85, 1.00)
            for _, wish in ipairs(wishers) do
                GameTooltip:AddLine(string.format(L["  %s - %s, #%d%s"], wish.name, core.SPEC_NAMES[wish.spec], wish.rank,
                    wish.enhanced and L[", enhanced"] or ""), 0.8, 0.8, 0.8)
            end
        elseif core.knowsWishlists() then
            GameTooltip:AddLine(L["On nobody's wishlist."], 0.6, 0.6, 0.6)
        end
        if line.record then
            GameTooltip:AddLine(string.format(L["Open: %s holds it until it is rolled. Click it, then ROLL."],
                line.record.recipient or "?"), 0.85, 0.62, 1.00, true)
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

for _, row in ipairs(rollRows) do
    row:SetScript("OnClick", function(self, which)
        if which == "RightButton" then
            if self.roll then ns.openRollMenu(self, self.roll, nil) end
            return
        end
        if self.playerName then recipientBox:SetText(self.playerName) end
    end)
    row:SetScript("OnEnter", function(self)
        if not self.playerName then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.playerName)
        ns.addPlayerLines(self.playerName)
        GameTooltip:AddLine(self.roll and L["Click: recipient. Right-click: pass or count the roll differently."]
            or L["Click: recipient"], 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

for g = 1, 5 do
    for _, cell in ipairs(picker.cells[g]) do
        cell:SetScript("OnEnter", function(self)
            if not self.fullName then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.fullName)
            ns.addPlayerLines(self.fullName)
            GameTooltip:AddLine(L["Click: recipient"], 0.6, 0.6, 0.6)
            GameTooltip:Show()
        end)
        cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
end

ns.scrollable(itemPane, function() return itemOffset end, function(v) itemOffset = v end, drawItems)
ns.scrollable(detail, function() return rollOffset end, function(v) rollOffset = v end, drawDetail)

titleButton:SetScript("OnEnter", function(self)
    local entry = core.selectedEntry()
    local item = entry and entry.item or (openRecord and openRecord.item)
    if not item then return end
    ns.itemTooltip(self, item)
    GameTooltip:Show()
end)
titleButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- After a hand-out the box is empty, or holds a bundle's next winner.
local function afterAction(done)
    if not done then return end
    local entry = core.selectedEntry()
    recipientBox:SetText(entry and entry.winner and entry.winner.name or "")
    ui.refresh()
end

startButton:SetScript("OnClick", function()
    if openRecord then
        local record = openRecord
        openRecord = nil
        core.startLaterRoll(record)
    else
        core.startRoll(false)
    end
end)
freeButton:SetScript("OnClick", function() core.startRoll(true) end)
giveButton:SetScript("OnClick", function() afterAction(roster.giveSelected(recipientBox:GetText())) end)
parkButton:SetScript("OnClick", function() afterAction(roster.parkSelected(recipientBox:GetText())) end)
deButton:SetScript("OnClick", function() afterAction(roster.giveAwaySelected("disenchanted", recipientBox:GetText())) end)
bankButton:SetScript("OnClick", function() afterAction(roster.giveAwaySelected("bank", recipientBox:GetText())) end)
allButton:SetScript("OnClick", function()
    if picker:IsShown() then picker:Hide() else drawPicker() picker:Show() end
end)
clearLoot:SetScript("OnClick", function() roster.clearActive() end)
recipientBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
recipientBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

ns.tip(startButton, function()
    if openRecord then return L["Start the roll for this open item"] end
    return string.format(L["Start a %d-second /rnd roll for this item (announced in raid chat)"], core.rollSeconds())
end)
ns.tip(freeButton, L["Post it again as a free BoE roll for any character (/rnd 100, highest wins, counts for nobody)"])
ns.tip(recipientBox, L["Who gets the item: click a name or a roll, or type one"])
ns.tip(allButton, L["The whole raid by group: click a name to pick them"])
ns.tip(giveButton, function()
    if core.lootSlotOf(core.selectedEntry()) then return L["Give the selected item to the name in the box and record it"] end
    return L["Record the selected item for the name in the box (the loot window is closed)"]
end)
ns.tip(parkButton, L["Hand the item to the name in the box (or keep it) until it is rolled later"])
ns.tip(deButton, L["Disenchant: give it to the name in the box (or keep it); counts for nobody"])
ns.tip(bankButton, L["Guild bank: give it to the name in the box (or keep it); counts for nobody"])
ns.tip(clearLoot, L["Empty the loot list (the awards stay)"])

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
    if ForgeTestBridge and ForgeTestBridge.RegisterFrame then
        ForgeTestBridge:RegisterFrame("RaidLedgerItem", itemTitle)
        ForgeTestBridge:RegisterFrame("RaidLedgerRollDetail", stateLine)
        ForgeTestBridge:RegisterFrame("RaidLedgerRollHeading", itemPane.heading)
        ForgeTestBridge:RegisterFrame("RaidLedgerAward", giveButton)
        ForgeTestBridge:RegisterFrame("RaidLedgerRecipient", recipientBox)
        ForgeTestBridge:RegisterFrame("RaidLedgerPark", parkButton)
        ForgeTestBridge:RegisterFrame("RaidLedgerStart", startButton)
        ForgeTestBridge:RegisterFrame("RaidLedgerFreeRoll", freeButton)
        ForgeTestBridge:RegisterFrame("RaidLedgerDisenchant", deButton)
        ForgeTestBridge:RegisterFrame("RaidLedgerBank", bankButton)
        ForgeTestBridge:RegisterFrame("RaidLedgerAllMembers", allButton)
        ForgeTestBridge:RegisterFrame("RaidLedgerMembers", picker)
        ForgeTestBridge:RegisterFrame("RaidLedgerPickerCell1", picker.cells[1][1])
        for i = 1, 3 do
            ForgeTestBridge:RegisterFrame("RaidLedgerItemRow" .. i, itemRows[i])
            ForgeTestBridge:RegisterFrame("RaidLedgerItemRow" .. i .. "Status", itemRows[i].columns[1])
            ForgeTestBridge:RegisterFrame("RaidLedgerRollLine" .. i, rollRows[i])
        end
    end
end)
