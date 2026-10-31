-- VERGABEN tab: every award of this raid on the left, the selected award on
-- the right. It only corrects (FR-RL-009): which tally it counts for (MS / OS
-- / none), its recipient, back to BEUTE (to roll or hand it out again),
-- remove, and its roll log (right-click a roll to pass or recount it).
-- EXPORT shows the website export in place of the tab.
local _, ns = ...
local L = ns.L
local core, ui = ns.core, ns.ui
local roster = core.roster
local LEFT_WIDTH = 420
local LOG_TOP = 204

local panel = CreateFrame("Frame", "RaidLedgerAwardsTab")
local awardOffset, logOffset = 0, 0
local boxRecord, boxRecipient    -- what the recipient box was last filled with

local STATE_COLORS = {
    given = {0.45, 0.85, 0.55}, held = {1.00, 0.82, 0.30},
    manual = {0.58, 0.79, 0.88}, deleted = {0.45, 0.45, 0.45}, parked = {0.85, 0.62, 1.00},
    disenchanted = {0.75, 0.55, 1.00}, bank = {0.95, 0.85, 0.45},
}

local function stateText(record)
    local text = record.state == "manual" and "" or (core.stateLabels[record.state] or string.upper(record.state or ""))
    if record.state == "held" and not ns.isPlayer(record.recipient) then text = L["HELD"] end
    if core.isOpenAward(record) then text = L["OPEN"] end
    if text ~= "" and not record.confirmed and record.state ~= "deleted" then text = text .. "?" end
    local color = core.isOpenAward(record) and STATE_COLORS.parked or STATE_COLORS[record.state] or STATE_COLORS.manual
    return text, color
end

---------------------------------------------------------------------------
-- Award list
---------------------------------------------------------------------------
local list = ns.pane(panel, 0, 0, LEFT_WIDTH, nil, "RaidLedgerHistoryPane")
local exportButton = ns.flatButton(list, L["EXPORT"], 70, "RaidLedgerExport")
exportButton:SetHeight(18)
exportButton:SetPoint("TOPRIGHT", list, "TOPRIGHT", -8, -6)
local newRaidButton = ns.flatButton(list, L["NEW RAID"], 86)
newRaidButton:SetHeight(18)
newRaidButton:SetPoint("RIGHT", exportButton, "LEFT", -6, 0)
local emptyText = ns.label(list, "GameFontNormalSmall", 11, {0.42, 0.61, 0.70})
emptyText:SetPoint("CENTER", list, "CENTER", 0, 10)
emptyText:SetText(L["No awards recorded in this ledger."])

local awardRows = ns.rowList(function(i)
    local row = ns.listRow(list, 0, { 64, 86 }, "RaidLedgerAwardLine" .. i)
    row:SetPoint("TOPLEFT", list, "TOPLEFT", 10, -28 - (i - 1) * ns.ROW_HEIGHT)
    row:SetPoint("RIGHT", list, "RIGHT", -10, 0)
    return row
end)

---------------------------------------------------------------------------
-- The selected award
---------------------------------------------------------------------------
local detail = ns.pane(panel, 0, 0, nil, nil, "RaidLedgerAwardDetail")
ns.sideBySide(list, detail, LEFT_WIDTH)
detail.heading:SetText(L["SELECTED AWARD"])
local titleButton = CreateFrame("Button", nil, detail)
titleButton:SetPoint("TOPLEFT", detail, "TOPLEFT", 12, -28)
titleButton:SetPoint("RIGHT", detail, "RIGHT", -12, 0)
titleButton:SetHeight(18)
local awardTitle = ns.label(titleButton, "GameFontHighlight", 12, {0.94, 0.97, 1.00})
awardTitle:SetAllPoints(titleButton)
awardTitle:SetJustifyH("LEFT")
awardTitle:SetWordWrap(false)
local nowLine = ns.label(detail, "GameFontNormalSmall", 10, {0.45, 0.68, 0.80})
nowLine:SetPoint("TOPLEFT", titleButton, "BOTTOMLEFT", 0, -4)
nowLine:SetPoint("RIGHT", titleButton, "RIGHT", 0, 0)
nowLine:SetHeight(14)
nowLine:SetJustifyH("LEFT")
nowLine:SetWordWrap(false)

local countsLabel = ns.label(detail, "GameFontNormalSmall", 9, {0.45, 0.60, 0.68})
countsLabel:SetPoint("TOPLEFT", detail, "TOPLEFT", 14, -72)
countsLabel:SetText(L["COUNTS AS"])
local specButtons = {}
for i, spec in ipairs({ { "ms", L["MAIN SPEC"] }, { "os", L["OFF SPEC"] }, { "none", L["NOTHING"] } }) do
    local button = ns.flatButton(detail, spec[2], 84, "RaidLedgerSpec" .. spec[1])
    button:SetHeight(20)
    button:SetPoint("TOPLEFT", detail, "TOPLEFT", 12 + (i - 1) * 90, -84)
    button.spec = spec[1]
    specButtons[i] = button
end

local recipientHint = ns.label(detail, "GameFontNormalSmall", 9, {0.45, 0.60, 0.68})
recipientHint:SetPoint("TOPLEFT", detail, "TOPLEFT", 14, -112)
recipientHint:SetText(L["RECIPIENT NAME"])
local recipientBox = CreateFrame("EditBox", "RaidLedgerAwardRecipient", detail, "InputBoxTemplate")
recipientBox:SetPoint("TOPLEFT", detail, "TOPLEFT", 18, -124)
recipientBox:SetPoint("TOPRIGHT", detail, "TOP", -3, -124)
recipientBox:SetHeight(22)
recipientBox:SetAutoFocus(false)
recipientBox:SetMaxLetters(24)
local changeButton = ns.flatButton(detail, L["CHANGE"], 124, "RaidLedgerChangeRecipient")
changeButton:SetHeight(22)
changeButton:ClearAllPoints()
changeButton:SetPoint("TOPLEFT", detail, "TOP", 3, -124)
changeButton:SetPoint("TOPRIGHT", detail, "TOPRIGHT", -12, -124)

-- Back to BEUTE: the award becomes an open item with whoever holds it
-- (the live plans know it as RaidLedgerAwardPark).
local parkButton = ns.flatButton(detail, L["BACK TO LOOT"], 140, "RaidLedgerAwardPark")
parkButton:SetPoint("TOPLEFT", detail, "TOPLEFT", 12, -152)
parkButton:SetPoint("TOPRIGHT", detail, "TOP", -3, -152)
ns.makeBackdrop(parkButton, 0.20, 0.12, 0.30, 0.98)
local removeButton = ns.flatButton(detail, L["REMOVE"], 90, "RaidLedgerRemove")
removeButton:SetPoint("TOPLEFT", detail, "TOP", 3, -152)
removeButton:SetPoint("TOPRIGHT", detail, "TOPRIGHT", -12, -152)
ns.makeBackdrop(removeButton, 0.28, 0.10, 0.10, 0.98)

local logHeading = ns.label(detail, "GameFontNormal", 10, {1.00, 0.80, 0.32})
logHeading:SetPoint("TOPLEFT", detail, "TOPLEFT", 12, -188)
local logRows = ns.rowList(function(i)
    -- RaidLedgerRoll1..: the names the live test plans use for the roll log.
    local row = ns.listRow(detail, 0, { 30 }, "RaidLedgerRoll" .. i)
    row:SetPoint("TOPLEFT", detail, "TOPLEFT", 10, -LOG_TOP - (i - 1) * ns.ROW_HEIGHT)
    row:SetPoint("RIGHT", detail, "RIGHT", -10, 0)
    return row
end)
local noLog = ns.label(detail, "GameFontNormalSmall", 10, {0.42, 0.61, 0.70})
noLog:SetPoint("TOPLEFT", detail, "TOPLEFT", 16, -LOG_TOP - 4)
noLog:SetPoint("RIGHT", detail, "RIGHT", -16, 0)
noLog:SetJustifyH("LEFT")

---------------------------------------------------------------------------
-- Export view (replaces both panes while shown)
---------------------------------------------------------------------------
local exportView = CreateFrame("Frame", "RaidLedgerExportPanel", panel)
exportView:SetAllPoints(panel)
ns.makeBackdrop(exportView, 0.035, 0.070, 0.105, 0.97)
exportView:SetFrameLevel(panel:GetFrameLevel() + 10)
exportView:Hide()
local exportHeading = ns.label(exportView, "GameFontNormal", 11, {1.00, 0.80, 0.32})
exportHeading:SetPoint("TOPLEFT", exportView, "TOPLEFT", 12, -11)
exportHeading:SetText(string.format(L["WEBSITE EXPORT  (%s LOOT)"], core.EXPORT_FORMAT))
local raidLabel = ns.label(exportView, "GameFontNormalSmall", 9, {0.45, 0.60, 0.68})
raidLabel:SetPoint("TOPLEFT", exportView, "TOPLEFT", 12, -40)
raidLabel:SetText(L["RAID ID"])
local raidBox = CreateFrame("EditBox", "RaidLedgerRaidID", exportView, "InputBoxTemplate")
raidBox:SetPoint("LEFT", raidLabel, "RIGHT", 12, 0)
raidBox:SetWidth(80)
raidBox:SetHeight(24)
raidBox:SetAutoFocus(false)
raidBox:SetNumeric(true)
raidBox:SetMaxLetters(9)
local backButton = ns.flatButton(exportView, L["BACK"], 70)
backButton:SetPoint("TOPRIGHT", exportView, "TOPRIGHT", -12, -34)
local exportBack = CreateFrame("Frame", nil, exportView)
exportBack:SetPoint("TOPLEFT", exportView, "TOPLEFT", 10, -66)
exportBack:SetPoint("BOTTOMRIGHT", exportView, "BOTTOMRIGHT", -10, 10)
ns.makeBackdrop(exportBack, 0.01, 0.02, 0.03, 0.98)
local exportScroll = CreateFrame("ScrollFrame", nil, exportBack)
exportScroll:SetPoint("TOPLEFT", exportBack, "TOPLEFT", 8, -8)
exportScroll:SetPoint("BOTTOMRIGHT", exportBack, "BOTTOMRIGHT", -8, 8)
exportScroll:EnableMouseWheel(true)
local exportText = CreateFrame("EditBox", "RaidLedgerExportText", exportScroll)
exportText:SetMultiLine(true)
exportText:SetAutoFocus(false)
exportText:SetFontObject(ChatFontNormal)
exportScroll:SetScrollChild(exportText)

-- A wider window keeps all selected-award actions on one shared grid.
ns.onResize(function(width, height)
    local listWidth = LEFT_WIDTH + math.floor((width - ns.CONTENT_WIDTH) * 0.4)
    local inner = width - listWidth - 12 - 24
    local each = math.floor((inner - 12) / 3)
    for index, button in ipairs(specButtons) do
        button:SetWidth(index < 3 and each or inner - each * 2 - 12)
        if index > 1 then
            button:ClearAllPoints()
            button:SetPoint("LEFT", specButtons[index - 1], "RIGHT", 6, 0)
        end
    end
    awardRows.fit(ns.rowsFit(height, 28, 24))
    logRows.fit(ns.rowsFit(height, LOG_TOP, 28))
    exportText:SetWidth(width - 36)
    exportText:SetHeight(height - 96)
end)
exportScroll:SetScript("OnMouseWheel", function(self, delta)
    local range = self:GetVerticalScrollRange() or 0
    self:SetVerticalScroll(math.max(0, math.min(range, self:GetVerticalScroll() - delta * 28)))
end)
exportText:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
exportText:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
-- Read-only: typing restores the generated text.
exportText:SetScript("OnTextChanged", function(self, userInput)
    if userInput then self:SetText(self.generated or "") self:HighlightText() end
end)

local function drawExport(focus)
    if not exportView:IsShown() then return end
    if not raidBox:HasFocus() then raidBox:SetText(ns.raidID() and tostring(ns.raidID()) or "") end
    exportText.generated = core.export() or ""
    exportText:SetText(exportText.generated)
    if exportText.generated == "" then
        ui.status(L["Enter the website's raid ID to build the export."])
    elseif focus then
        exportText:SetFocus()
        exportText:HighlightText()
        ui.status(L["Export selected: press Ctrl+C and paste it into the raid website's loot import."])
    end
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
-- awards: the history without its open items, which wait for their roll in
-- the loot tab (one place for each item, raid of 2026-10-26).
local function awards()
    local list = {}
    for _, record in ipairs(core.history()) do
        if not core.isOpenAward(record) then table.insert(list, record) end
    end
    return list
end

local function selectedRecord()
    local record = core.editing()
    if record and core.findRecord(record.id) == record and not core.isOpenAward(record) then return record end
    core.edit(nil)
end

local function drawList()
    local history = awards()
    local total = table.getn(history)
    awardOffset = math.max(0, math.min(awardOffset, total - table.getn(awardRows)))
    list.heading:SetText(total > table.getn(awardRows) and string.format(L["AWARDS (%d, SCROLL)"], total) or string.format(L["AWARDS (%d)"], total))
    local selected = selectedRecord()
    for i, row in ipairs(awardRows) do
        local record = history[i + awardOffset]
        row.record = record
        if record then
            local text = string.format("#%d  %s  %s", record.id, record.time or "", record.item)
            if record.state == "deleted" then text = "|cff777777" .. string.gsub(text, "|c%x%x%x%x%x%x%x%x", "") .. "|r" end
            row:SetText(text)
            local state, color = stateText(record)
            row.columns[1]:SetText(state)
            row.columns[1]:SetTextColor(color[1], color[2], color[3])
            row.columns[2]:SetText(record.recipient or "")
            ns.classColor(row.columns[2], record.recipient)
            ns.highlight(row, record == selected and "selected" or (record.state == "deleted" and "muted") or nil)
            row:Show()
        else
            row:Hide()
        end
    end
    if total == 0 then emptyText:Show() else emptyText:Hide() end
end

local function drawLog(record)
    local log = record and record.rollLog
    local count = log and table.getn(log) or 0
    logOffset = math.max(0, math.min(logOffset, count - table.getn(logRows)))
    logHeading:SetText(count > table.getn(logRows) and string.format(L["ROLLS (%d, SCROLL)"], count) or string.format(L["ROLLS (%d)"], count))
    local winner = log and core.winningRoll(log)
    for i, row in ipairs(logRows) do
        local r = log and log[i + logOffset]
        row.roll = r and r.kind and not r.note and r or nil
        row.playerName = r and r.name
        if r then
            -- "Name  (tie-break 1)  - won  (MS 21-120, 1 item)  - corrected, rolled 140 (41-140)  [WL #2]":
            -- the spec and the tally the ranking used.
            local text = r.name
            if (r.round or 1) > 1 then text = text .. string.format(L["  (tie-break %d)"], r.round - 1) end
            if r.note then
                text = "|cff777777" .. text .. string.format(L["  - ignored: %s"], L[r.note] or r.note) .. "|r"
            else
                if r == winner then text = text .. L["  - won"] end
                if r.kind then
                    text = text .. "  (" .. core.rollLabel(r) .. ", " .. core.itemCount(r.tally or 0, record.token) .. ")"
                end
                if r.was then text = text .. string.format(L["  - corrected, rolled %s"], r.was) end
                local wish = core.wishOf(r.name, record.itemID)
                if wish then text = text .. string.format(L["  [WL #%d]"], wish.rank) end
            end
            row:SetText(text)
            if not r.note then ns.classColor(row.text, r.name) end
            row.columns[1]:SetText(tostring(r.value))
            if r.note then row.columns[1]:SetTextColor(0.45, 0.45, 0.45)
            elseif r == winner then row.columns[1]:SetTextColor(0.45, 0.85, 0.55)
            else row.columns[1]:SetTextColor(1.00, 0.79, 0.31) end
            ns.highlight(row, r == winner and "winner" or (r.note and "muted") or nil)
            row:Show()
        else
            row:Hide()
        end
    end
    if count == 0 then
        noLog:SetText(record and (log and L["Awarded without a /rnd roll"] or L["Rolls were not recorded\nfor this older award"]) or "")
        noLog:Show()
    else
        noLog:Hide()
    end
end

local function drawDetail()
    local record = selectedRecord()
    local mayEdit = not ns.mayEdit or ns.mayEdit()
    local controls = { changeButton, parkButton, removeButton }
    if not record then
        awardTitle:SetText(L["Select an award on the left"])
        nowLine:SetText(L["Here you change its recipient, its tally, or remove it."])
        for _, button in ipairs(controls) do ns.setEnabled(button, false) end
        for _, button in ipairs(specButtons) do ns.setEnabled(button, false) ns.highlight(button, nil) end
        drawLog(nil)
        return
    end
    -- A changed award (another award, a pass that moved it) refills the box;
    -- otherwise the name being typed stays.
    if record ~= boxRecord or record.recipient ~= boxRecipient then
        recipientBox:SetText(record.recipient or "")
        boxRecord, boxRecipient = record, record.recipient
    end
    awardTitle:SetText(string.format("#%d %s", record.id, record.item))
    local spec = record.spec and (core.SPEC_NAMES[record.spec] or record.spec) or L["no tally"]
    local state = stateText(record)
    nowLine:SetText((state ~= "" and string.format(L["NOW: %s (%s)"], record.recipient, state)
        or string.format(L["NOW: %s"], record.recipient)) .. "  |  " .. spec
        .. (record.roll and string.format(L["  |  roll %d"], record.roll) or ""))
    local deleted = record.state == "deleted"
    local countable = not deleted and not core.NO_TALLY[record.state] and record.spec ~= "boe"
    for _, button in ipairs(specButtons) do
        local current = (button.spec == "none" and not record.spec) or button.spec == record.spec
        ns.setEnabled(button, mayEdit and countable)
        button:SetBackdropColor(current and 0.12 or 0.08, current and 0.36 or 0.25, current and 0.20 or 0.34, 0.98)
        button:GetFontString():SetTextColor(current and 0.55 or 0.70, current and 1.00 or 0.93, current and 0.65 or 1.00)
    end
    changeButton:SetText(deleted and L["RESTORE + SET"] or L["CHANGE RECIPIENT"])
    ns.setEnabled(changeButton, mayEdit)
    ns.setEnabled(parkButton, mayEdit and not deleted)
    ns.setEnabled(removeButton, mayEdit and not deleted)
    drawLog(record)
end

local function refresh()
    drawList()
    drawDetail()
    drawExport()
end

local function showView(view)
    if view == "export" then
        list:Hide()
        detail:Hide()
        exportView:Show()
        drawExport(true)
    else
        exportView:Hide()
        exportText:ClearFocus()
        list:Show()
        detail:Show()
    end
end

local tab = ns.addTab("awards", function() return string.format(L["AWARDS (%d)"], table.getn(awards())) end, panel, refresh,
    "RaidLedgerTabButtonAwards")
tab.view = showView
ns.tip(tab.button, L["Every award of this raid: change recipient or tally, remove, export for the website"])

-- ns.showAward opens the awards tab on one award (from the tally tab).
function ns.showAward(record)
    core.edit(record)
    recipientBox:SetText(record and record.recipient or "")
    logOffset = 0
    for i, r in ipairs(awards()) do
        if r == record then awardOffset = math.max(0, i - math.floor(table.getn(awardRows) / 2)) end
    end
    ui.show("awards")
    showView(nil)
end

---------------------------------------------------------------------------
-- Clicks and tooltips
---------------------------------------------------------------------------
for _, row in ipairs(awardRows) do
    row:SetScript("OnClick", function(self)
        if not self.record then return end
        core.edit(self.record)
        recipientBox:SetText(self.record.recipient or "")
        logOffset = 0
        ui.refresh()
    end)
    row:SetScript("OnEnter", function(self)
        local record = self.record
        if not record then return end
        ns.itemTooltip(self, record.item)
        local state = stateText(record)
        GameTooltip:AddLine(state ~= "" and string.format(L["Award #%d: %s (%s)"], record.id, record.recipient, state)
            or string.format(L["Award #%d: %s"], record.id, record.recipient), 1, 1, 1)
        if record.roll then
            GameTooltip:AddLine(string.format(L["Roll %d, %s"], record.roll, record.spec and core.rollLabel({
                kind = record.spec, low = record.low, high = record.high }) or L["spec unknown"]), 0.8, 0.8, 0.8)
        end
        ns.addPlayerLines(record.recipient)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

for _, row in ipairs(logRows) do
    row:SetScript("OnClick", function(self, which)
        if which == "RightButton" then
            if self.roll then ns.openRollMenu(self, self.roll, selectedRecord()) end
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

ns.scrollable(list, function() return awardOffset end, function(v) awardOffset = v end, drawList)
ns.scrollable(detail, function() return logOffset end, function(v) logOffset = v end, drawDetail)

titleButton:SetScript("OnEnter", function(self)
    local record = selectedRecord()
    if not record then return end
    ns.itemTooltip(self, record.item)
    GameTooltip:Show()
end)
titleButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

for _, button in ipairs(specButtons) do
    button:SetScript("OnClick", function(self)
        local record = selectedRecord()
        if record then roster.setSpec(record, self.spec) end
    end)
end
changeButton:SetScript("OnClick", function()
    local record = selectedRecord()
    if record and roster.changeRecipient(record, recipientBox:GetText()) then recipientBox:SetText(record.recipient) end
end)
parkButton:SetScript("OnClick", function()
    local record = selectedRecord()
    if record and roster.parkRecord(record, "") then ui.show("loot") end
end)
removeButton:SetScript("OnClick", function()
    local record = selectedRecord()
    if record then StaticPopup_Show("RAIDLEDGER_REMOVE_AWARD", string.format("#%d %s", record.id, record.item), nil, record) end
end)
StaticPopupDialogs["RAIDLEDGER_REMOVE_AWARD"] = {
    text = L["Remove award %s? The export keeps it as removed; CHANGE RECIPIENT restores it."],
    button1 = YES,
    button2 = NO,
    OnAccept = function(_, record) core.deleteRecord(record.id) end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
}
newRaidButton:SetScript("OnClick", function() StaticPopup_Show("RAIDLEDGER_NEW_RAID") end)
exportButton:SetScript("OnClick", function() ui.show(exportView:IsShown() and "awards" or "export") end)
backButton:SetScript("OnClick", function() ui.show("awards") end)
raidBox:SetScript("OnTextChanged", function(self)
    local value = tonumber(self:GetText())
    if value ~= ns.raidID() then
        ns.setRaidID(value)
        drawExport(false)
    end
end)
raidBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() drawExport(true) end)
raidBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
recipientBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
recipientBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

ns.tip(exportButton, L["The website export of this raid's awards (RS2 LOOT)"])
ns.tip(newRaidButton, L["New raid: empties the award list (export it first)"])
ns.tip(specButtons[1], L["The award counts in the winner's main-spec tally"])
ns.tip(specButtons[2], L["The award counts in the winner's off-spec tally"])
ns.tip(specButtons[3], L["The award counts in no tally"])
ns.tip(recipientBox, L["The award's new recipient; click a roll below to pick its player"])
ns.tip(changeButton, function()
    local record = selectedRecord()
    return record and record.state == "deleted" and L["Restore the award for the name in the box"] or L["Give this award to the name in the box"]
end)
ns.tip(parkButton, L["Back to BEUTE as an open item with whoever holds it: roll it again or hand it out there"])
ns.tip(removeButton, L["Remove the award (the export keeps it as removed)"])
ns.tip(raidBox, L["The raid's ID on the website (in its address)"])
ns.tip(backButton, L["Back to the awards"])
ns.tip(exportText, L["Ctrl+C copies the export; paste it into the website's loot import"])

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
    if ForgeTestBridge and ForgeTestBridge.RegisterFrame then
        ForgeTestBridge:RegisterFrame("RaidLedgerHistory1", awardRows[1])
        ForgeTestBridge:RegisterFrame("RaidLedgerExportButton", exportButton)
        ForgeTestBridge:RegisterFrame("RaidLedgerExportText", exportText)
        ForgeTestBridge:RegisterFrame("RaidLedgerAwardRecipient", recipientBox)
        ForgeTestBridge:RegisterFrame("RaidLedgerChangeRecipient", changeButton)
        ForgeTestBridge:RegisterFrame("RaidLedgerHistory1Recipient", awardRows[1].columns[2])
        ForgeTestBridge:RegisterFrame("RaidLedgerAwardPark", parkButton)
        ForgeTestBridge:RegisterFrame("RaidLedgerRemove", removeButton)
        ForgeTestBridge:RegisterFrame("RaidLedgerAwardLogHeading", logHeading)
        for _, button in ipairs(specButtons) do ForgeTestBridge:RegisterFrame("RaidLedgerSpec" .. button.spec, button) end
        for i = 1, 3 do ForgeTestBridge:RegisterFrame("RaidLedgerRoll" .. i, logRows[i]) end
    end
end)
