-- BEUTE tab: the loot list on the left (this corpse's drops, then the open
-- items held until they are rolled) with the raid's disenchanter below it;
-- the selected item on the right in two steps (FR-RL-006): 1 WÜRFELN (roll,
-- free BoE roll, every roll with what the roller has so far) and 2 VERGEBEN
-- (give to a name, disenchant or guild bank). The button for the next
-- step is highlighted. Click a roll to make its player the recipient,
-- right-click it to pass or count it differently.
local _, ns = ...
local L = ns.L
local core, ui = ns.core, ns.ui
local roster = core.roster
local LEFT_WIDTH = 288
local ROLLS_TOP, ROLLS_BELOW = 128, 116   -- the roll list sits between step 1 and step 2
local RAID_BAR = 56                          -- the disenchanter bar below the loot list
local PAD, GAP = 12, 6                       -- the detail pane's inner margin and button gap

local panel = CreateFrame("Frame", "RaidLedgerLootTab")
local itemOffset, rollOffset = 0, 0
local openRecord          -- an open award picked in the loot list (it is rolled from here)
local openBundle          -- matching open token awards, selected before their shared roll

local itemPane = ns.pane(panel, 0, 0, LEFT_WIDTH, nil, "RaidLedgerRollPane")
local clearLoot = ns.flatButton(itemPane, L["EMPTY"], 64)
clearLoot:SetHeight(18)
clearLoot:SetPoint("TOPRIGHT", itemPane, "TOPRIGHT", -8, -6)
local emptyText = ns.label(itemPane, "GameFontNormalSmall", 11, {0.42, 0.61, 0.70})
emptyText:SetPoint("CENTER", itemPane, "CENTER", 0, 10)
emptyText:SetWidth(LEFT_WIDTH - 30)
emptyText:SetText(L["Open the master loot window\nPlayers can then use /rnd"])
emptyText:SetJustifyH("CENTER")

local itemRows = ns.rowList(function(i)
    local row = ns.listRow(itemPane, 0, { 66, 34 }, "RaidLedgerItemRow" .. i)
    row:SetPoint("TOPLEFT", itemPane, "TOPLEFT", 10, -28 - (i - 1) * ns.ROW_HEIGHT)
    row:SetPoint("RIGHT", itemPane, "RIGHT", -10, 0)
    return row
end)

local detail = ns.pane(panel, 0, 0, nil, nil, "RaidLedgerDetailPane")
ns.sideBySide(itemPane, detail, LEFT_WIDTH)
detail.heading:SetText(L["SELECTED ITEM"])

-- The item's name; hovering it shows the item.
local titleButton = CreateFrame("Button", nil, detail)
titleButton:SetPoint("TOPLEFT", detail, "TOPLEFT", 12, -28)
titleButton:SetPoint("RIGHT", detail, "RIGHT", -12, 0)
titleButton:SetHeight(18)
local itemTitle = ns.label(titleButton, "GameFontHighlight", 13, {0.94, 0.97, 1.00}, "RaidLedgerItem")
itemTitle:SetAllPoints(titleButton)
itemTitle:SetJustifyH("LEFT")
itemTitle:SetWordWrap(false)
local stateLine = ns.label(detail, "GameFontNormalSmall", 10, {0.45, 0.68, 0.80}, "RaidLedgerRollDetail")
stateLine:SetPoint("TOPLEFT", titleButton, "BOTTOMLEFT", 0, -4)
stateLine:SetPoint("RIGHT", titleButton, "RIGHT", 0, 0)
stateLine:SetHeight(14)
stateLine:SetJustifyH("LEFT")
stateLine:SetWordWrap(false)

-- Roll and hand-out controls share one grid, without prescribing an order.
local startButton = ns.flatButton(detail, L["ROLL"], 130, "RaidLedgerStart")
startButton:SetPoint("TOPLEFT", detail, "TOPLEFT", PAD, -68)
local freeButton = ns.flatButton(detail, L["FREE BOE ROLL"], 130, "RaidLedgerFreeRoll")
freeButton:SetPoint("LEFT", startButton, "RIGHT", GAP, 0)

local rollHeading = ns.label(detail, "GameFontNormalSmall", 9, {0.55, 0.72, 0.80})
rollHeading:SetPoint("TOPLEFT", detail, "TOPLEFT", PAD + 2, -114)
local soFarHeading = ns.label(detail, "GameFontNormalSmall", 9, {0.55, 0.72, 0.80})
soFarHeading:SetPoint("TOPRIGHT", detail, "TOPRIGHT", -54, -114)
soFarHeading:SetText(L["SO FAR"])
local rollValueHeading = ns.label(detail, "GameFontNormalSmall", 9, {0.55, 0.72, 0.80})
rollValueHeading:SetPoint("TOPRIGHT", detail, "TOPRIGHT", -16, -114)
rollValueHeading:SetText(L["RESULT"])

local rollRows = ns.rowList(function(i)
    local row = ns.listRow(detail, 0, { 30, 40 }, "RaidLedgerRollLine" .. i)
    row:SetPoint("TOPLEFT", detail, "TOPLEFT", PAD, -ROLLS_TOP - (i - 1) * ns.ROW_HEIGHT)
    row:SetPoint("RIGHT", detail, "RIGHT", -PAD, 0)
    return row
end)
local noRolls = ns.label(detail, "GameFontNormalSmall", 10, {0.42, 0.61, 0.70})
noRolls:SetPoint("TOPLEFT", detail, "TOPLEFT", PAD + 4, -ROLLS_TOP - 4)

-- The give button names the recipient.
local recipientHint = ns.label(detail, "GameFontNormalSmall", 9, {0.45, 0.60, 0.68})
recipientHint:SetPoint("TOPLEFT", detail, "BOTTOMLEFT", 110, 102)
recipientHint:SetPoint("RIGHT", detail, "RIGHT", -PAD, 0)
recipientHint:SetJustifyH("LEFT")
recipientHint:SetText(L["click a roll or ALL, or type a name"])
-- The edit box template draws its border 6 px left of the frame.
local recipientBox = CreateFrame("EditBox", "RaidLedgerRecipient", detail, "InputBoxTemplate")
recipientBox:SetPoint("TOPLEFT", detail, "BOTTOMLEFT", PAD + 6, 84)
recipientBox:SetWidth(132)
recipientBox:SetHeight(22)
recipientBox:SetAutoFocus(false)
recipientBox:SetMaxLetters(24)
local allButton = ns.flatButton(detail, L["ALL (%d)"], 70, "RaidLedgerAllMembers")
allButton:SetHeight(22)
allButton:SetPoint("LEFT", recipientBox, "RIGHT", 8, 0)
local giveButton = ns.flatButton(detail, L["GIVE TO ..."], 186, "RaidLedgerAward")
giveButton:SetHeight(22)
giveButton:SetPoint("LEFT", allButton, "RIGHT", GAP, 0)

local deButton = ns.flatButton(detail, L["DISENCHANT"], 130, "RaidLedgerDisenchant")
deButton:SetPoint("TOPLEFT", detail, "BOTTOMLEFT", PAD, 40)
local bankButton = ns.flatButton(detail, L["GUILD BANK"], 130, "RaidLedgerBank")
bankButton:SetPoint("LEFT", deButton, "RIGHT", GAP, 0)
for _, button in ipairs({ deButton, bankButton }) do
    ns.makeBackdrop(button, 0.16, 0.12, 0.24, 0.98)
    button.baseColor = { 0.16, 0.12, 0.24 }
end

-- layoutButtons: step 1 in one or two columns, step 2 in a row that ends at
-- the same right edge (box, ALL, give) and two equal columns below it.
local inner = 404
-- sizeStepOne: the normal roll spans the pane unless the free BoE roll appears.
local function sizeStepOne(withFree)
    if withFree then
        local each = math.floor((inner - GAP) / 2)
        startButton:SetWidth(each)
        freeButton:SetWidth(inner - each - GAP)
        freeButton:Show()
    else
        startButton:SetWidth(inner)
        freeButton:Hide()
    end
end

local function layoutButtons(width)
    -- The loot list takes 40% of any extra width (ns.sideBySide).
    local left = LEFT_WIDTH + math.floor((width - ns.CONTENT_WIDTH) * 0.4)
    inner = width - left - 12 - 2 * PAD
    sizeStepOne(freeButton:IsShown())
    local half = math.floor((inner - GAP) / 2)
    deButton:SetWidth(half)
    bankButton:SetWidth(inner - half - GAP)
    local give = math.floor(inner * 0.45)
    giveButton:SetWidth(give)
    recipientBox:SetWidth(inner - 6 - 8 - allButton:GetWidth() - GAP - give)
end

-- The raid's disenchanter, below the loot list: rolled once per raid, or
-- chosen by hand (FR-RL-008, FR-RL-011).
local raidBar = CreateFrame("Frame", nil, itemPane)
raidBar:SetPoint("BOTTOMLEFT", itemPane, "BOTTOMLEFT", 8, 8)
raidBar:SetPoint("BOTTOMRIGHT", itemPane, "BOTTOMRIGHT", -8, 8)
raidBar:SetHeight(RAID_BAR - 10)
ns.makeBackdrop(raidBar, 0.03, 0.06, 0.09, 0.95)
local disenchanterText = ns.label(raidBar, "GameFontNormalSmall", 10, {0.75, 0.55, 1.00}, "RaidLedgerDisenchanterName")
disenchanterText:SetPoint("TOPLEFT", raidBar, "TOPLEFT", 8, -7)
disenchanterText:SetPoint("RIGHT", raidBar, "RIGHT", -8, 0)
disenchanterText:SetJustifyH("LEFT")
disenchanterText:SetWordWrap(false)
-- Two equal buttons that grow with the loot list.
local chooseDE = ns.flatButton(raidBar, L["CHOOSE"], 100, "RaidLedgerDisenchanterChoose")
chooseDE:SetHeight(18)
chooseDE:SetPoint("BOTTOMLEFT", raidBar, "BOTTOMLEFT", 8, 6)
chooseDE:SetPoint("BOTTOMRIGHT", raidBar, "BOTTOM", -GAP / 2, 6)
local deRollButton = ns.flatButton(raidBar, L["ROLL IT"], 100, "RaidLedgerDisenchanterRoll")
deRollButton:SetHeight(18)
deRollButton:SetPoint("BOTTOMLEFT", raidBar, "BOTTOM", GAP / 2, 6)
deRollButton:SetPoint("BOTTOMRIGHT", raidBar, "BOTTOMRIGHT", -8, 6)

---------------------------------------------------------------------------
-- The whole raid by group (ALLE) and the roll menu (right-click)
---------------------------------------------------------------------------
-- It opens just above ALLE, across the whole tab.
local picker = CreateFrame("Frame", "RaidLedgerMembers", panel)
picker:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, 146)
picker:SetPoint("RIGHT", panel, "RIGHT", 0, 0)
picker:SetHeight(118)
picker:SetFrameLevel(panel:GetFrameLevel() + 20)
ns.makeBackdrop(picker, 0.025, 0.052, 0.078, 0.99)
picker:EnableMouse(true)
picker:Hide()
picker.headings, picker.cells = {}, {}
-- What a click on a name does: "recipient" (the name box) or "disenchanter".
picker.mode = "recipient"
local PICKER_CAPTIONS = { recipient = L["Who gets the item?"], disenchanter = L["Who disenchants this raid?"] }
picker.caption = ns.label(picker, "GameFontNormalSmall", 10, {0.94, 0.97, 1.00}, "RaidLedgerMembersCaption")
picker.caption:SetPoint("TOPLEFT", picker, "TOPLEFT", 13, -8)
for g = 1, 5 do
    local heading = ns.label(picker, "GameFontNormalSmall", 9, {1.00, 0.80, 0.32})
    heading:SetText(string.format(L["GROUP %d"], g))
    picker.headings[g] = heading
    picker.cells[g] = {}
    for row = 1, 5 do
        local cell = ns.listRow(picker, 100, nil, "RaidLedgerMember" .. g .. "_" .. row)
        cell:SetScript("OnClick", function(self)
            picker:Hide()
            if not self.fullName then return end
            if picker.mode == "disenchanter" then roster.setDisenchanter(self.fullName)
            else recipientBox:SetText(self.fullName) end
        end)
        picker.cells[g][row] = cell
    end
end
ns.Ledger:HookScript("OnHide", function() picker:Hide() end)

-- A larger window: more loot and roll rows, wider raid-group columns.
ns.onResize(function(width, height)
    itemRows.fit(ns.rowsFit(height, 28, RAID_BAR + 2))
    layoutButtons(width)
    rollRows.fit(ns.rowsFit(height, ROLLS_TOP, ROLLS_BELOW))
    local cellWidth = math.floor((width - 22) / 5) - 4
    for g = 1, 5 do
        local x = 11 + (g - 1) * (cellWidth + 4)
        picker.headings[g]:ClearAllPoints()
        picker.headings[g]:SetPoint("TOPLEFT", picker, "TOPLEFT", x + 2, -22)
        for row, cell in ipairs(picker.cells[g]) do
            cell:SetWidth(cellWidth)
            cell:SetHeight(15)
            cell:ClearAllPoints()
            cell:SetPoint("TOPLEFT", picker, "TOPLEFT", x, -34 - (row - 1) * 16)
        end
    end
end)

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
        local bundles = {}
        for _, record in ipairs(open) do
            local key = record.token and record.itemID
            local bundle = key and bundles[key]
            if bundle then
                table.insert(bundle.records, record)
            elseif key then
                bundle = { records = { record } }
                bundles[key] = bundle
                table.insert(lines, bundle)
            else
                table.insert(lines, { record = record })
            end
        end
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
    itemOffset = math.max(0, math.min(itemOffset, table.getn(lines) - table.getn(itemRows)))
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
            local item = line.entry and line.entry.item or line.record and line.record.item or line.records[1].item
            local itemID = core.itemIDFromLink(item)
            local count = line.entry and line.entry.count or line.records and table.getn(line.records) or 1
            row:SetText((count > 1 and (count .. "x ") or "") .. item)
            row.text:SetTextColor(0.82, 0.91, 0.96)
            local text, color
            if line.entry then text, color = entryStatus(line.entry)
            elseif line.record then text, color = string.format(L["with %s"], line.record.recipient or "?"), OPEN_COLOR
            else text, color = "", OPEN_COLOR end
            row.columns[1]:SetText(text)
            row.columns[1]:SetTextColor(color[1], color[2], color[3])
            local wished = table.getn(core.wishersOf(itemID))
            row.columns[2]:SetText(core.knowsWishlists() and string.format(L["WL %d"], wished) or "")
            if wished > 0 then row.columns[2]:SetTextColor(0.45, 0.85, 0.55) else row.columns[2]:SetTextColor(0.5, 0.5, 0.5) end
            local isSelected = (line.entry and line.entry == selected) or (line.record and line.record == openRecord)
                or (line.records and openBundle and line.records[1] == openBundle[1])
            ns.highlight(row, isSelected and "selected" or ((line.record or line.records) and "open") or nil)
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
    rollOffset = math.max(0, math.min(rollOffset, count - table.getn(rollRows)))
    rollHeading:SetText(count > table.getn(rollRows) and string.format(L["ROLLS (%d, SCROLL)"], count) or string.format(L["ROLLS (%d)"], count))
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

-- The relevant action is highlighted; the state line only reports what happened.
local function boxName() return (string.gsub(recipientBox:GetText() or "", "^%s*(.-)%s*$", "%1")) end

local function drawRaidBar(mayEdit)
    local name = roster.disenchanter()
    disenchanterText:SetText(string.format(L["DISENCHANTER: %s"], name or "-"))
    local rolling
    for _, entry in ipairs(core.active()) do
        if entry.disenchanter and entry.endsAt then rolling = true end
    end
    deRollButton:SetText(name and L["ROLL AGAIN"] or L["ROLL IT"])
    ns.setEnabled(deRollButton, mayEdit and not rolling)
    ns.setEnabled(chooseDE, mayEdit and not rolling)
end

-- drawHandOut: step 2. The give button names whoever is in the box.
local handOutEnabled, handOutPrimary = false, nil
local function drawHandOut(enabled, primary)
    handOutEnabled, handOutPrimary = enabled, primary
    local name = boxName()
    giveButton:SetText(name ~= "" and string.format(L["GIVE TO %s"], string.upper(name)) or L["GIVE TO ..."])
    ns.setEnabled(giveButton, enabled and name ~= "")
    for _, button in ipairs({ deButton, bankButton }) do ns.setEnabled(button, enabled) end
    ns.setPrimary(giveButton, enabled and primary == "give")
    ns.setPrimary(deButton, enabled and primary == "de")
end

local function drawDetail()
    local entry = core.selectedEntry()
    if entry then openRecord, openBundle = nil, nil end
    local mayEdit = (not ns.mayEdit or ns.mayEdit()) and true or false
    local rolling = entry and entry.endsAt and not entry.winner
    drawRaidBar(mayEdit)
    ns.setPrimary(startButton, false)
    sizeStepOne(false)
    if entry and entry.disenchanter then
        itemTitle:SetText(entry.item)
        stateLine:SetText(rolling and string.format(L["%d rolls  |  %ds remaining"], core.activeRollCount(entry),
            math.max(0, math.ceil(entry.endsAt - GetTime()))) or L["Not rolled yet."])
        startButton:SetText(L["ROLL"])
        ns.setEnabled(startButton, mayEdit and not rolling)
        drawHandOut(false)
        drawRolls(entry)
    elseif entry then
        local count = entry.count or 1
        itemTitle:SetText((count > 1 and (count .. "x ") or "") .. entry.item)
        local primary
        if entry.winners and entry.winners[1] then
            local names = {}
            for _, r in ipairs(entry.winners) do table.insert(names, r.name) end
            stateLine:SetText(string.format(L["WINNERS: %s"], table.concat(names, ", ")))
            primary = "give"
        elseif entry.winner then
            stateLine:SetText(string.format(L["%s won (%d)."], entry.winner.name, entry.winner.value))
            primary = "give"
        elseif rolling then
            stateLine:SetText(string.format(L["%d rolls  |  %ds remaining"], core.activeRollCount(entry),
                math.max(0, math.ceil(entry.endsAt - GetTime()))))
        elseif entry.nobody then
            stateLine:SetText(L["Nobody wanted it."])
            primary = "de"
        else
            stateLine:SetText(entry.later and L["Open item, not rolled yet."] or L["Not rolled yet."])
            primary = "roll"
        end
        startButton:SetText((entry.winner or entry.nobody) and L["ROLL AGAIN"] or L["ROLL"])
        ns.setEnabled(startButton, mayEdit and not rolling)
        ns.setPrimary(startButton, mayEdit and primary == "roll")
        -- Only a bind-on-equip item can go to any character.
        sizeStepOne(not entry.later and (entry.free or core.isBindOnEquip(entry.item)) and true or false)
        ns.setEnabled(freeButton, mayEdit and not rolling)
        drawHandOut(mayEdit and not rolling, primary)
        drawRolls(entry)
    elseif openBundle then
        local count = table.getn(openBundle)
        itemTitle:SetText((count > 1 and (count .. "x ") or "") .. openBundle[1].item)
        stateLine:SetText(L["Open item, not rolled yet."])
        startButton:SetText(L["ROLL"])
        ns.setEnabled(startButton, mayEdit)
        ns.setPrimary(startButton, mayEdit)
        drawHandOut(false)
        drawRolls(nil)
    elseif openRecord then
        itemTitle:SetText(openRecord.item)
        stateLine:SetText(string.format(L["Open: %s holds it."], openRecord.recipient or "?"))
        startButton:SetText(L["ROLL"])
        ns.setEnabled(startButton, mayEdit)
        ns.setPrimary(startButton, mayEdit)
        drawHandOut(mayEdit)
        drawRolls(nil)
    else
        itemTitle:SetText(L["Select an item on the left"])
        stateLine:SetText("")
        ns.setEnabled(startButton, false)
        drawHandOut(false)
        drawRolls(nil)
    end
    drawPicker()
end

local function refresh()
    if openRecord and not core.isOpenAward(openRecord) then openRecord = nil end
    if openBundle then
        local open = false
        for _, record in ipairs(openBundle) do if core.isOpenAward(record) then open = true end end
        if not open then openBundle = nil end
    end
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
            if ui.selectMasterLoot then ui.selectMasterLoot(line.entry) end
            openRecord, openBundle = nil, nil
            recipientBox:SetText(line.entry.winner and line.entry.winner.name or "")
        elseif line.records then
            core.select(nil)
            openRecord, openBundle = nil, line.records
            recipientBox:SetText("")
        else
            core.select(nil)
            openRecord, openBundle = line.record, nil
            recipientBox:SetText("")
        end
        ui.refresh()
    end)
    row:SetScript("OnEnter", function(self)
        local line = self.line
        if not line or line.heading then return end
        local item = line.entry and line.entry.item or line.record and line.record.item or line.records[1].item
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
        elseif line.records then
            GameTooltip:AddLine(string.format(L["%d tokens"], table.getn(line.records)), 0.85, 0.62, 1.00, true)
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
    local item = entry and entry.item or (openBundle and openBundle[1].item) or (openRecord and openRecord.item)
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

-- handOut: the selected loot item, or the open item picked in the list.
local function handOut(state)
    if openRecord then
        local done = roster.handOutRecord(openRecord, state, recipientBox:GetText())
        if done then openRecord = nil end
        return done
    end
    if state == "given" then return roster.giveSelected(recipientBox:GetText()) end
    if state == "parked" then return roster.parkSelected(recipientBox:GetText()) end
    return roster.giveAwaySelected(state, recipientBox:GetText())
end

startButton:SetScript("OnClick", function()
    if openBundle then
        local records = openBundle
        openBundle = nil
        core.startLaterBundle(records)
    elseif openRecord then
        local record = openRecord
        openRecord = nil
        core.startLaterRoll(record)
    else
        core.startRoll(false)
    end
end)
freeButton:SetScript("OnClick", function() core.startRoll(true) end)
deRollButton:SetScript("OnClick", function() roster.startDisenchanterRoll() end)
giveButton:SetScript("OnClick", function() afterAction(handOut("given")) end)
deButton:SetScript("OnClick", function() afterAction(handOut("disenchanted")) end)
bankButton:SetScript("OnClick", function() afterAction(handOut("bank")) end)
local function togglePicker(mode)
    if picker:IsShown() and picker.mode == mode then picker:Hide() return end
    picker.mode = mode
    picker.caption:SetText(PICKER_CAPTIONS[mode])
    drawPicker()
    picker:Show()
end
allButton:SetScript("OnClick", function() togglePicker("recipient") end)
chooseDE:SetScript("OnClick", function()
    recipientBox:SetText("") -- The disenchanter picker must not leave a stale loot recipient behind.
    togglePicker("disenchanter")
end)
clearLoot:SetScript("OnClick", function() roster.clearActive() end)
recipientBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
recipientBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
recipientBox:SetScript("OnTextChanged", function() drawHandOut(handOutEnabled, handOutPrimary) end)

ns.tip(startButton, function()
    if openRecord or openBundle then return L["Start the roll for this open item"] end
    return string.format(L["Start a %d-second /rnd roll for this item (announced in raid chat)"], core.rollSeconds())
end)
ns.tip(freeButton, L["Post it again as a free BoE roll for any character (/rnd 100, highest wins, counts for nobody)"])
ns.tip(recipientBox, L["Who gets the item: click a name or a roll, or type one"])
ns.tip(allButton, L["The whole raid by group: click a name to pick them"])
ns.tip(giveButton, function()
    if core.lootSlotOf(core.selectedEntry()) then return L["Give the selected item to the name in the box and record it"] end
    return L["Record the selected item for the name in the box (the loot window is closed)"]
end)
ns.tip(chooseDE, L["Choose the raid's disenchanter from the raid, without a roll"])
ns.tip(deButton, function()
    local name = roster.disenchanter()
    if name then return string.format(L["Disenchant: give it to %s, this raid's disenchanter; counts for nobody"], name) end
    return L["Disenchant: give it to the name in the box (or keep it); counts for nobody"]
end)
ns.tip(bankButton, L["Guild bank: give it to the name in the box (or keep it); counts for nobody"])
ns.tip(deRollButton, L["Roll the raid's disenchanter: everyone may /rnd 100, the winner gets every DE item"])
ns.tip(clearLoot, L["Empty the loot list (the awards stay)"])

---------------------------------------------------------------------------
-- Compact master-loot assignment popup (FR-RL-014)
---------------------------------------------------------------------------
-- The corpse needs immediate actions, but the 760 px main window should not
-- cover the game every time it opens. This popup owns only the current corpse.
local MAX_MASTER_ROWS = 10
local masterLoot = CreateFrame("Frame", "RaidLedgerMasterLoot", UIParent)
masterLoot:SetWidth(460)
masterLoot:SetHeight(93)
masterLoot:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 20, -120)
masterLoot:SetFrameStrata("FULLSCREEN_DIALOG")
masterLoot:SetToplevel(true)
masterLoot:SetClampedToScreen(true)
masterLoot:EnableMouse(true)
masterLoot:SetMovable(true)
masterLoot:RegisterForDrag("LeftButton")
masterLoot:SetScript("OnDragStart", function(self) self:StartMoving() end)
masterLoot:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
ns.makeBackdrop(masterLoot, 0.018, 0.031, 0.055, 0.98)
masterLoot:Hide()

-- This is an independent UIParent window, so it does not inherit Ledger's scale.
function ui.setMasterLootScale(scale) masterLoot:SetScale(scale) end

local masterTitle = ns.label(masterLoot, "GameFontNormal", 12, {1.00, 0.80, 0.32})
masterTitle:SetPoint("TOPLEFT", masterLoot, "TOPLEFT", 12, -10)
masterTitle:SetText(L["MASTER LOOT ITEMS"])
local masterClose = ns.flatButton(masterLoot, "X", 22, "RaidLedgerMasterLootClose")
masterClose:SetHeight(18)
masterClose:SetPoint("TOPRIGHT", masterLoot, "TOPRIGHT", -10, -8)
masterClose:SetScript("OnClick", function() masterLoot:Hide() end)
ns.tip(masterClose, L["Close the ledger (/ledger opens it again)"])

local masterRows = {}
for i = 1, MAX_MASTER_ROWS do
    local row = ns.listRow(masterLoot, 436, nil, "RaidLedgerMasterLootItem" .. i)
    row:SetPoint("TOPLEFT", masterLoot, "TOPLEFT", 12, -30 - (i - 1) * 19)
    row:SetPoint("RIGHT", masterLoot, "RIGHT", -12, 0)
    row:SetScript("OnClick", function(self)
        if self.entry then
            core.select(self.entry)
            ui.selectMasterLoot(self.entry)
            ui.refresh()
        end
    end)
    row:SetScript("OnEnter", function(self)
        if self.entry then ns.itemTooltip(self, self.entry.item); GameTooltip:Show() end
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    masterRows[i] = row
end

local masterRoll = ns.flatButton(masterLoot, L["ROLL"], 138, "RaidLedgerMasterLootRoll")
masterRoll:SetPoint("BOTTOMLEFT", masterLoot, "BOTTOMLEFT", 12, 12)
local masterGive = ns.flatButton(masterLoot, L["ASSIGN"], 138, "RaidLedgerMasterLootGive")
masterGive:SetPoint("LEFT", masterRoll, "RIGHT", 11, 0)
local masterLater = ns.flatButton(masterLoot, L["LATER ROLL"], 138, "RaidLedgerMasterLootLater")
masterLater:SetPoint("LEFT", masterGive, "RIGHT", 11, 0)
local masterControls = { masterTitle, masterClose, masterRoll, masterGive, masterLater }
for _, row in ipairs(masterRows) do table.insert(masterControls, row) end

local masterMembers = CreateFrame("Frame", "RaidLedgerMasterLootMembers", masterLoot)
masterMembers:SetPoint("TOPLEFT", masterLoot, "TOPLEFT", 3, -3)
masterMembers:SetPoint("BOTTOMRIGHT", masterLoot, "BOTTOMRIGHT", -3, 3)
masterMembers:SetFrameStrata("FULLSCREEN_DIALOG")
ns.makeBackdrop(masterMembers, 0.025, 0.052, 0.078, 1)
masterMembers:EnableMouse(true)
masterMembers:Hide()
local hideMasterMembers
masterMembers.caption = ns.label(masterMembers, "GameFontNormalSmall", 10, {0.94, 0.97, 1.00})
masterMembers.caption:SetPoint("TOPLEFT", masterMembers, "TOPLEFT", 12, -10)
masterMembers.cells = {}
for group = 1, 5 do
    local heading = ns.label(masterMembers, "GameFontNormalSmall", 9, {1.00, 0.80, 0.32})
    heading:SetPoint("TOPLEFT", masterMembers, "TOPLEFT", 10 + (group - 1) * 90, -30)
    heading:SetText(string.format(L["GROUP %d"], group))
    masterMembers.cells[group] = {}
    for row = 1, 5 do
        local cell = ns.listRow(masterMembers, 84, nil, "RaidLedgerMasterLootMember" .. group .. "_" .. row)
        cell:SetPoint("TOPLEFT", masterMembers, "TOPLEFT", 8 + (group - 1) * 90, -44 - (row - 1) * 18)
        cell:SetScript("OnClick", function(self)
            if not self.fullName or not masterLoot.entry then return end
            core.select(masterLoot.entry)
            hideMasterMembers()
            if masterMembers.mode == "later" then roster.parkSelected(self.fullName)
            else roster.giveSelected(self.fullName) end
        end)
        cell:SetScript("OnEnter", function(self)
            if self.fullName then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(self.fullName)
                ns.addPlayerLines(self.fullName)
                GameTooltip:Show()
            end
        end)
        cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
        masterMembers.cells[group][row] = cell
    end
end
local masterCancel = ns.flatButton(masterMembers, L["CLOSE"], 96, "RaidLedgerMasterLootMembersClose")
masterCancel:SetHeight(18)
masterCancel:SetPoint("BOTTOMRIGHT", masterMembers, "BOTTOMRIGHT", -12, 12)
hideMasterMembers = function()
    masterMembers:Hide()
    for _, control in ipairs(masterControls) do control:Show() end
    if masterLoot.normalHeight then masterLoot:SetHeight(masterLoot.normalHeight) end
end
masterCancel:SetScript("OnClick", hideMasterMembers)

local function masterEntries()
    local entries = {}
    for _, entry in ipairs(core.active()) do
        if core.lootSlotOf(entry) then table.insert(entries, entry) end
    end
    return entries
end

local function drawMasterMembers()
    local rows = { 0, 0, 0, 0, 0 }
    for group = 1, 5 do
        for row = 1, 5 do masterMembers.cells[group][row]:Hide() end
    end
    for _, member in ipairs(roster.members()) do
        local group = math.min(math.max(tonumber(member.group) or 1, 1), 5)
        if rows[group] < 5 then
            rows[group] = rows[group] + 1
            local cell = masterMembers.cells[group][rows[group]]
            cell.fullName = member.name
            cell:SetText(member.name)
            ns.classColor(cell.text, member.name)
            cell:Show()
        end
    end
end

local function drawMasterLoot()
    local entries = masterEntries()
    local found = false
    for _, entry in ipairs(entries) do if entry == masterLoot.entry then found = true end end
    if not found then
        local selected = core.selectedEntry()
        for _, entry in ipairs(entries) do
            if entry == selected then masterLoot.entry, found = entry, true end
        end
        if not found then masterLoot.entry = entries[1] end
    end
    local visible = math.min(table.getn(entries), MAX_MASTER_ROWS)
    masterLoot.normalHeight = 74 + visible * 19
    masterLoot:SetHeight(masterLoot.normalHeight)
    for index, row in ipairs(masterRows) do
        row.entry = entries[index]
        if row.entry then
            row:SetText(row.entry.item)
            ns.highlight(row, row.entry == masterLoot.entry and "selected" or nil)
            row:Show()
        else
            row:Hide()
        end
    end
    if not masterLoot.entry then
        hideMasterMembers()
        masterLoot:Hide()
        return
    end
    local mayEdit = (not ns.mayEdit or ns.mayEdit()) and true or false
    ns.setEnabled(masterRoll, mayEdit)
    ns.setEnabled(masterGive, mayEdit)
    ns.setEnabled(masterLater, mayEdit)
end

ui.selectMasterLoot = function(entry)
    if masterLoot:IsShown() then
        masterLoot.entry = entry
        drawMasterLoot()
    end
end

local function chooseMasterRecipient(mode)
    if not masterLoot.entry then return end
    masterLoot:SetHeight(math.max(masterLoot.normalHeight or 0, 158))
    masterMembers.mode = mode
    masterMembers.caption:SetText(mode == "later" and L["Who keeps it until the roll?"] or L["Who gets the item?"])
    drawMasterMembers()
    for _, control in ipairs(masterControls) do control:Hide() end
    masterMembers:Show()
end

masterRoll:SetScript("OnClick", function()
    if masterLoot.entry then core.select(masterLoot.entry); core.startRoll(false) end
end)
masterGive:SetScript("OnClick", function()
    if not masterLoot.entry then return end
    core.select(masterLoot.entry)
    if masterLoot.entry.winner then roster.giveSelected(masterLoot.entry.winner.name)
    else chooseMasterRecipient("give") end
end)
masterLater:SetScript("OnClick", function() chooseMasterRecipient("later") end)

ui.refreshMasterLoot = function()
    if masterLoot:IsShown() then drawMasterLoot() end
end
ui.showMasterLoot = function()
    if not core.isMasterLooter() then return end
    drawMasterLoot()
    if masterLoot.entry then masterLoot:Show() end
end
ui.hideMasterLoot = function()
    hideMasterMembers()
    masterLoot:Hide()
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
    if ForgeTestBridge and ForgeTestBridge.RegisterFrame then
        ForgeTestBridge:RegisterFrame("RaidLedgerMasterLoot", masterLoot)
        ForgeTestBridge:RegisterFrame("RaidLedgerMasterLootMembers", masterMembers)
        ForgeTestBridge:RegisterFrame("RaidLedgerMasterLootRoll", masterRoll)
        ForgeTestBridge:RegisterFrame("RaidLedgerMasterLootGive", masterGive)
        ForgeTestBridge:RegisterFrame("RaidLedgerMasterLootLater", masterLater)
        for row = 1, MAX_MASTER_ROWS do ForgeTestBridge:RegisterFrame("RaidLedgerMasterLootItem" .. row, masterRows[row]) end
        for row = 1, 5 do ForgeTestBridge:RegisterFrame("RaidLedgerMasterLootMember1_" .. row, masterMembers.cells[1][row]) end
        ForgeTestBridge:RegisterFrame("RaidLedgerItem", itemTitle)
        ForgeTestBridge:RegisterFrame("RaidLedgerRollDetail", stateLine)
        ForgeTestBridge:RegisterFrame("RaidLedgerRollHeading", itemPane.heading)
        ForgeTestBridge:RegisterFrame("RaidLedgerAward", giveButton)
        ForgeTestBridge:RegisterFrame("RaidLedgerRecipient", recipientBox)
        ForgeTestBridge:RegisterFrame("RaidLedgerStart", startButton)
        ForgeTestBridge:RegisterFrame("RaidLedgerFreeRoll", freeButton)
        ForgeTestBridge:RegisterFrame("RaidLedgerDisenchant", deButton)
        ForgeTestBridge:RegisterFrame("RaidLedgerDisenchanterRoll", deRollButton)
        ForgeTestBridge:RegisterFrame("RaidLedgerDisenchanterChoose", chooseDE)
        ForgeTestBridge:RegisterFrame("RaidLedgerDisenchanterName", disenchanterText)
        ForgeTestBridge:RegisterFrame("RaidLedgerBank", bankButton)
        ForgeTestBridge:RegisterFrame("RaidLedgerAllMembers", allButton)
        ForgeTestBridge:RegisterFrame("RaidLedgerMembers", picker)
        ForgeTestBridge:RegisterFrame("RaidLedgerPickerCell1", picker.cells[1][1])
        ForgeTestBridge:RegisterFrame("RaidLedgerMembersCaption", picker.caption)
        -- Group 1 only: every registered frame goes into the bridge report.
        for row = 1, 5 do ForgeTestBridge:RegisterFrame("RaidLedgerMember1_" .. row, picker.cells[1][row]) end
        for i = 1, 3 do
            ForgeTestBridge:RegisterFrame("RaidLedgerItemRow" .. i, itemRows[i])
            ForgeTestBridge:RegisterFrame("RaidLedgerItemRow" .. i .. "Status", itemRows[i].columns[1])
            ForgeTestBridge:RegisterFrame("RaidLedgerRollLine" .. i, rollRows[i])
        end
    end
end)
