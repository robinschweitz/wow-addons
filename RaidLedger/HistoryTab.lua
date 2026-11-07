-- HISTORY tab (VERLAUF, FR-RL-023 to FR-RL-028): the finished raids this
-- ledger keeps, newest first, on the left; the selected raid on the right with
-- its tally and three actions: show its awards (in VERGABEN, where editors
-- correct them and EXPORT builds its website export), continue it as the
-- current raid, or delete it from this ledger. KEEP sets how many raids stay.
local _, ns = ...
local L = ns.L
local core, ui = ns.core, ns.ui
local LEFT_WIDTH = 420
local TALLY_TOP = 162

local panel = CreateFrame("Frame", "RaidLedgerHistoryTab")
local raidOffset, tallyOffset, selectedRaid = 0, 0, nil
local contentHeight = ns.CONTENT_HEIGHT

---------------------------------------------------------------------------
-- The list of saved raids
---------------------------------------------------------------------------
local list = ns.pane(panel, 0, 0, LEFT_WIDTH, nil, "RaidLedgerRaidList")
local keepBox = CreateFrame("EditBox", "RaidLedgerKeepRaids", list, "InputBoxTemplate")
keepBox:SetPoint("TOPRIGHT", list, "TOPRIGHT", -12, -5)
keepBox:SetWidth(44)
keepBox:SetHeight(20)
keepBox:SetAutoFocus(false)
keepBox:SetNumeric(true)
keepBox:SetMaxLetters(4)
local keepLabel = ns.label(list, "GameFontNormalSmall", 9, {0.45, 0.60, 0.68})
keepLabel:SetPoint("RIGHT", keepBox, "LEFT", -10, 0)
keepLabel:SetText(L["KEEP"])
local emptyText = ns.label(list, "GameFontNormalSmall", 11, {0.42, 0.61, 0.70})
emptyText:SetPoint("LEFT", list, "LEFT", 16, 0)
emptyText:SetPoint("RIGHT", list, "RIGHT", -16, 0)
emptyText:SetText(L["No finished raids yet. NEW RAID keeps the current raid here."])

local raidRows = ns.rowList(function(i)
    local row = ns.listRow(list, 0, { 70, 54 }, "RaidLedgerRaidRow" .. i)
    row:SetPoint("TOPLEFT", list, "TOPLEFT", 10, -30 - (i - 1) * ns.ROW_HEIGHT)
    row:SetPoint("RIGHT", list, "RIGHT", -10, 0)
    -- Named columns for the live plans and specs.
    _G["RaidLedgerRaidRow" .. i .. "Count"] = row.columns[1]
    _G["RaidLedgerRaidRow" .. i .. "Raid"] = row.columns[2]
    -- Rows are made when the tab is first drawn: register them for live plans then.
    if i <= 3 and ForgeTestBridge and ForgeTestBridge.RegisterFrame then
        ForgeTestBridge:RegisterFrame("RaidLedgerRaidRow" .. i, row)
        ForgeTestBridge:RegisterFrame("RaidLedgerRaidRow" .. i .. "Count", row.columns[1])
        ForgeTestBridge:RegisterFrame("RaidLedgerRaidRow" .. i .. "Raid", row.columns[2])
    end
    row:SetScript("OnClick", function(self)
        if not self.raid then return end
        selectedRaid, tallyOffset = self.raid, 0
        ui.refresh()
    end)
    return row
end)

---------------------------------------------------------------------------
-- The selected raid
---------------------------------------------------------------------------
local detail = ns.pane(panel, 0, 0, nil, nil, "RaidLedgerRaidDetail")
ns.sideBySide(list, detail, LEFT_WIDTH)
detail.heading:SetText(L["SELECTED RAID"])
local raidTitle = ns.label(detail, "GameFontHighlight", 12, {0.94, 0.97, 1.00})
raidTitle:SetPoint("TOPLEFT", detail, "TOPLEFT", 12, -28)
raidTitle:SetPoint("RIGHT", detail, "RIGHT", -12, 0)
raidTitle:SetHeight(16)
raidTitle:SetJustifyH("LEFT")
raidTitle:SetWordWrap(false)
local infoLine = ns.label(detail, "GameFontNormalSmall", 10, {0.45, 0.68, 0.80})
infoLine:SetPoint("TOPLEFT", raidTitle, "BOTTOMLEFT", 0, -4)
infoLine:SetPoint("RIGHT", raidTitle, "RIGHT", 0, 0)
infoLine:SetHeight(14)
infoLine:SetJustifyH("LEFT")
infoLine:SetWordWrap(false)

-- Two rows: look at it (SHOW AWARDS, SHARE), change it (CONTINUE, DELETE).
local showButton = ns.flatButton(detail, L["SHOW AWARDS"], 100, "RaidLedgerRaidShow")
showButton:SetPoint("TOPLEFT", detail, "TOPLEFT", 12, -72)
local shareButton = ns.flatButton(detail, L["SHARE"], 100, "RaidLedgerRaidShare")
shareButton:SetPoint("LEFT", showButton, "RIGHT", 6, 0)
local reopenButton = ns.flatButton(detail, L["CONTINUE"], 100, "RaidLedgerRaidReopen")
reopenButton:SetPoint("TOPLEFT", showButton, "BOTTOMLEFT", 0, -6)
local deleteButton = ns.flatButton(detail, L["DELETE"], 80, "RaidLedgerRaidDelete")
deleteButton:SetPoint("LEFT", reopenButton, "RIGHT", 6, 0)
ns.makeBackdrop(deleteButton, 0.28, 0.10, 0.10, 0.98)

local tallyHeading = ns.label(detail, "GameFontNormal", 10, {1.00, 0.80, 0.32})
tallyHeading:SetPoint("TOPLEFT", detail, "TOPLEFT", 12, -140)
local tallyRows = ns.rowList(function(i)
    local row = ns.listRow(detail, 0, { 64, 92 }, "RaidLedgerRaidTally" .. i)
    row:SetPoint("TOPLEFT", detail, "TOPLEFT", 10, -TALLY_TOP - (i - 1) * ns.ROW_HEIGHT)
    row:SetPoint("RIGHT", detail, "RIGHT", -10, 0)
    return row
end)

-- Each row shares the detail pane's width.
ns.onResize(function(width, height)
    local listWidth = LEFT_WIDTH + math.floor((width - ns.CONTENT_WIDTH) * 0.4)
    local inner = width - listWidth - 12 - 24
    local half = math.floor((inner - 6) / 2)
    showButton:SetWidth(half)
    shareButton:SetWidth(inner - half - 6)
    reopenButton:SetWidth(half)
    deleteButton:SetWidth(inner - half - 6)
    contentHeight = height
end)

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
local function awardCount(raid)
    local n = 0
    for _, record in ipairs(raid.history) do
        if record.state ~= "deleted" and not core.isOpenAward(record) then n = n + 1 end
    end
    return n
end

local function isSaved(raid)
    for _, other in ipairs(core.raids()) do
        if other == raid then return true end
    end
end

-- tallyLines: everyone with items or tokens in that raid, by name.
local function tallyLines(raid)
    local items, tokens = core.tallies(false, nil, raid), core.tallies(true, nil, raid)
    local names, seen = {}, {}
    local function add(name)
        if name and name ~= "" and not seen[ns.lower(name)] then
            seen[ns.lower(name)] = true
            table.insert(names, name)
        end
    end
    for _, record in ipairs(raid.history) do add((record.state == "held" and record.winner) or record.recipient) end
    for _, fix in pairs(raid.tallyAdjust or {}) do add(fix.name) end
    local lines = {}
    for _, name in ipairs(names) do
        local ms, os = core.tallyOf(items, name, "ms"), core.tallyOf(items, name, "os")
        local tms, tos = core.tallyOf(tokens, name, "ms"), core.tallyOf(tokens, name, "os")
        if ms + os + tms + tos > 0 then table.insert(lines, { name = name, ms = ms, os = os, tms = tms, tos = tos }) end
    end
    table.sort(lines, function(a, b) return ns.lower(a.name) < ns.lower(b.name) end)
    return lines
end

local function drawList()
    local raids = core.raids()
    local total = table.getn(raids)
    raidOffset = math.max(0, math.min(raidOffset, total - table.getn(raidRows)))
    list.heading:SetText(total > table.getn(raidRows) and string.format(L["FINISHED RAIDS (%d, SCROLL)"], total)
        or string.format(L["FINISHED RAIDS (%d)"], total))
    if not keepBox:HasFocus() then keepBox:SetText(tostring(core.keepRaids())) end
    if selectedRaid and not isSaved(selectedRaid) then selectedRaid = nil end
    for i, row in ipairs(raidRows) do
        local raid = raids[i + raidOffset]
        row.raid = raid
        if raid then
            row:SetText(core.raidLabel(raid))
            local n = awardCount(raid)
            row.columns[1]:SetText(n == 1 and L["1 award"] or string.format(L["%d awards"], n))
            row.columns[2]:SetText(raid.raidID and ("#" .. raid.raidID) or "")
            ns.highlight(row, raid == selectedRaid and "selected" or nil)
            row:Show()
        else
            row:Hide()
        end
    end
    if total == 0 then emptyText:Show() else emptyText:Hide() end
end

local function drawDetail()
    local raid = selectedRaid
    local mayEdit = not ns.mayEdit or ns.mayEdit()
    ns.setEnabled(showButton, raid ~= nil)
    ns.setEnabled(shareButton, raid ~= nil)
    ns.setEnabled(reopenButton, raid ~= nil and mayEdit)
    ns.setEnabled(deleteButton, raid ~= nil)
    if not raid then
        raidTitle:SetText(L["Select a raid on the left"])
        infoLine:SetText(L["Show its awards and export, continue it, or delete it."])
        tallyHeading:SetText("")
        for _, row in ipairs(tallyRows) do row:Hide() end
        return
    end
    raidTitle:SetText(core.raidLabel(raid))
    infoLine:SetText(string.format(L["recorded by %s  |  %d awards  |  raid ID %s"], raid.recorder or "?",
        awardCount(raid), raid.raidID and tostring(raid.raidID) or "-"))
    local lines = tallyLines(raid)
    tallyOffset = math.max(0, math.min(tallyOffset, table.getn(lines) - table.getn(tallyRows)))
    tallyHeading:SetText(string.format(L["TALLY OF THIS RAID (%d)"], table.getn(lines)))
    for i, row in ipairs(tallyRows) do
        local line = lines[i + tallyOffset]
        if line then
            row:SetText(line.name)
            ns.classColor(row.text, line.name)
            row.columns[1]:SetText(string.format(L["MS %d  OS %d"], line.ms, line.os))
            row.columns[2]:SetText(line.tms + line.tos > 0 and string.format(L["tokens MS %d  OS %d"], line.tms, line.tos) or "")
            ns.highlight(row, nil)
            row:Show()
        else
            row:Hide()
        end
    end
end

-- The rows are made when the tab is first drawn, not while it stays hidden.
local function refresh()
    raidRows.fit(ns.rowsFit(contentHeight, 30, 16))
    tallyRows.fit(ns.rowsFit(contentHeight, TALLY_TOP, 16))
    drawList()
    drawDetail()
end

local tab = ns.addTab("history", L["HISTORY"], panel, refresh, "RaidLedgerTabButtonHistory")
ns.tip(tab.button, L["Finished raids: their awards, tallies and exports; continue or delete one"])

---------------------------------------------------------------------------
-- Clicks and tooltips
---------------------------------------------------------------------------
ns.scrollable(list, function() return raidOffset end, function(v) raidOffset = v end, drawList)
ns.scrollable(detail, function() return tallyOffset end, function(v) tallyOffset = v end, drawDetail)

showButton:SetScript("OnClick", function()
    if not selectedRaid then return end
    core.showRaid(selectedRaid)
    ui.show("awards")
end)
reopenButton:SetScript("OnClick", function() if selectedRaid then core.askReopen(selectedRaid) end end)
deleteButton:SetScript("OnClick", function() if selectedRaid then core.askDelete(selectedRaid) end end)
shareButton:SetScript("OnClick", function() if selectedRaid then core.shareRaid(selectedRaid) end end)

local function saveKeep(self)
    if not core.setKeepRaids(self:GetText()) then
        ui.status(L["Keep at least 1 raid."])
    else
        ui.status(string.format(L["HISTORY keeps the last %d raids."], core.keepRaids()))
    end
    self:SetText(tostring(core.keepRaids()))
    self:ClearFocus()
end
keepBox:SetScript("OnEnterPressed", saveKeep)
keepBox:SetScript("OnEscapePressed", function(self) self:SetText(tostring(core.keepRaids())) self:ClearFocus() end)

ns.tip(keepBox, L["How many finished raids are kept; the oldest go first. Press Enter to save."])
ns.tip(showButton, L["Open this raid's awards in AWARDS: correct them there or build its export"])
ns.tip(reopenButton, L["Continue this raid (e.g. on a second evening): it becomes the current raid, the current one is kept here"])
ns.tip(deleteButton, L["Delete this raid from your ledger only; other players keep theirs"])
ns.tip(shareButton, L["Send this raid's awards to the group: their ledgers and wishlists keep it under their history"])

-- Closing the window goes back to the current raid's awards.
ns.Ledger:HookScript("OnHide", function() core.showRaid(nil) end)

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
    if ForgeTestBridge and ForgeTestBridge.RegisterFrame then
        ForgeTestBridge:RegisterFrame("RaidLedgerRaidShow", showButton)
        ForgeTestBridge:RegisterFrame("RaidLedgerRaidShare", shareButton)
        ForgeTestBridge:RegisterFrame("RaidLedgerRaidReopen", reopenButton)
        ForgeTestBridge:RegisterFrame("RaidLedgerRaidDelete", deleteButton)
        ForgeTestBridge:RegisterFrame("RaidLedgerKeepRaids", keepBox)
    end
end)
