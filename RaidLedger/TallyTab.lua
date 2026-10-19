-- SPIELER tab (the tally) (UI feedback 2026-10-19: "see and edit the tally in the UI"):
-- every raid member (and anyone with an award) with this raid's items and
-- tokens per spec - what the "fewest items wins" rule ranks by. The selected
-- player can be corrected with - / + per counter (shared with the group, not
-- exported) and lists their awards; clicking one opens it in VERGABEN, where
-- its tally (MS / OS / none) is changed.
local _, ns = ...
local L = ns.L
local core, ui = ns.core, ns.ui
local roster = core.roster
local PLAYER_ROWS, AWARD_ROWS = 17, 7
local LEFT_WIDTH = 440
local RIGHT_X = LEFT_WIDTH + 12
local RIGHT_WIDTH = ns.CONTENT_WIDTH - RIGHT_X
local COUNTERS = {
    { key = "ms", tokens = false, spec = "ms", caption = L["Items main spec"] },
    { key = "os", tokens = false, spec = "os", caption = L["Items off spec"] },
    { key = "tms", tokens = true, spec = "ms", caption = L["Tokens main spec"] },
    { key = "tos", tokens = true, spec = "os", caption = L["Tokens off spec"] },
}
local CORRECTED = { 1.00, 0.86, 0.45 }

local panel = CreateFrame("Frame", "RaidLedgerTallyTab")
local playerOffset, selectedName = 0, nil

local list = ns.pane(panel, 0, 0, LEFT_WIDTH, ns.CONTENT_HEIGHT, "RaidLedgerTallyList")
list.heading:SetText(L["TALLY THIS RAID"])
local columnHeads = {}
for i, caption in ipairs({ L["TOK. OS"], L["TOK. MS"], L["ITEMS OS"], L["ITEMS MS"] }) do
    local head = ns.label(list, "GameFontNormalSmall", 9, {0.55, 0.72, 0.80})
    head:SetPoint("TOPRIGHT", list, "TOPRIGHT", -16 - (i - 1) * 62, -32)
    head:SetWidth(56)
    head:SetJustifyH("RIGHT")
    head:SetText(caption)
    columnHeads[i] = head
end
local nameHead = ns.label(list, "GameFontNormalSmall", 9, {0.55, 0.72, 0.80})
nameHead:SetPoint("TOPLEFT", list, "TOPLEFT", 17, -32)
nameHead:SetText(L["PLAYER"])

local playerRows = {}
for i = 1, PLAYER_ROWS do
    local row = ns.listRow(list, LEFT_WIDTH - 20, { 56, 56, 56, 56 }, "RaidLedgerTallyRow" .. i)
    row:SetPoint("TOPLEFT", list, "TOPLEFT", 10, -46 - (i - 1) * ns.ROW_HEIGHT)
    playerRows[i] = row
end
local emptyText = ns.label(list, "GameFontNormalSmall", 11, {0.42, 0.61, 0.70})
emptyText:SetPoint("CENTER", list, "CENTER", 0, 10)
emptyText:SetText(L["Nobody in the group and no awards yet."])

local detail = ns.pane(panel, RIGHT_X, 0, RIGHT_WIDTH, ns.CONTENT_HEIGHT, "RaidLedgerTallyDetail")
detail.heading:SetText(L["SELECTED PLAYER"])
local playerTitle = ns.label(detail, "GameFontHighlight", 13, {0.94, 0.97, 1.00})
playerTitle:SetPoint("TOPLEFT", detail, "TOPLEFT", 12, -28)
playerTitle:SetWidth(RIGHT_WIDTH - 24)
playerTitle:SetJustifyH("LEFT")
local hint = ns.label(detail, "GameFontNormalSmall", 9, {0.45, 0.60, 0.68})
hint:SetPoint("TOPLEFT", detail, "TOPLEFT", 12, -48)
hint:SetWidth(RIGHT_WIDTH - 24)
hint:SetHeight(24)
hint:SetJustifyH("LEFT")
hint:SetJustifyV("TOP")
hint:SetWordWrap(true)
hint:SetText(L["- / + corrects a counter (e.g. loot from before the ledger). Shared, not exported."])

local counterRows = {}
for i, counter in ipairs(COUNTERS) do
    local y = -80 - (i - 1) * 26
    local caption = ns.label(detail, "GameFontNormalSmall", 10, {0.75, 0.85, 0.92})
    caption:SetPoint("TOPLEFT", detail, "TOPLEFT", 14, y - 5)
    caption:SetText(counter.caption)
    local value = ns.label(detail, "GameFontNormal", 11, {0.94, 0.97, 1.00})
    value:SetPoint("TOPRIGHT", detail, "TOPRIGHT", -78, y - 4)
    value:SetWidth(60)
    value:SetJustifyH("RIGHT")
    local minus = ns.flatButton(detail, "-", 24, "RaidLedgerTallyMinus" .. counter.key)
    minus:SetHeight(20)
    minus:SetPoint("TOPRIGHT", detail, "TOPRIGHT", -42, y)
    local plus = ns.flatButton(detail, "+", 24, "RaidLedgerTallyPlus" .. counter.key)
    plus:SetHeight(20)
    plus:SetPoint("TOPRIGHT", detail, "TOPRIGHT", -12, y)
    minus.counter, plus.counter = counter.key, counter.key
    counterRows[i] = { value = value, minus = minus, plus = plus }
end
local resetButton = ns.flatButton(detail, L["RESET CORRECTIONS"], 150, "RaidLedgerTallyReset")
resetButton:SetHeight(20)
resetButton:SetPoint("TOPLEFT", detail, "TOPLEFT", 12, -186)

local awardsHeading = ns.label(detail, "GameFontNormal", 10, {1.00, 0.80, 0.32})
awardsHeading:SetPoint("TOPLEFT", detail, "TOPLEFT", 12, -218)
local awardRows = {}
for i = 1, AWARD_ROWS do
    local row = ns.listRow(detail, RIGHT_WIDTH - 20, { 34 }, "RaidLedgerTallyAward" .. i)
    row:SetPoint("TOPLEFT", detail, "TOPLEFT", 10, -234 - (i - 1) * ns.ROW_HEIGHT)
    awardRows[i] = row
end

---------------------------------------------------------------------------
-- Data and drawing
---------------------------------------------------------------------------
-- players: the group, then anyone else with an award or a correction, by name.
local function players()
    local list, seen = {}, {}
    local function add(name)
        if name and name ~= "" and not seen[ns.lower(name)] then
            seen[ns.lower(name)] = true
            table.insert(list, name)
        end
    end
    for _, member in ipairs(ns.members()) do add(member.name) end
    for _, record in ipairs(core.history()) do
        if record.state ~= "deleted" and not core.NO_TALLY[record.state] then
            add((record.state == "held" and record.winner) or record.recipient)
        end
    end
    for _, fix in pairs(roster.adjustments()) do add(fix.name) end
    table.sort(list, function(a, b) return ns.lower(a) < ns.lower(b) end)
    return list
end

local function counts(name)
    local items, tokens = core.tallies(), core.tallies(true)
    local fix = roster.adjustments()[ns.lower(name)] or {}
    local out = {}
    for _, counter in ipairs(COUNTERS) do
        out[counter.key] = { total = core.tallyOf(counter.tokens and tokens or items, name, counter.spec), fix = fix[counter.key] or 0 }
    end
    return out
end

local function drawList()
    local names = players()
    playerOffset = math.max(0, math.min(playerOffset, table.getn(names) - PLAYER_ROWS))
    for i, row in ipairs(playerRows) do
        local name = names[i + playerOffset]
        row.playerName = name
        if name then
            row:SetText(name)
            ns.classColor(row.text, name)
            local c = counts(name)
            for column, key in ipairs({ "tos", "tms", "os", "ms" }) do
                local cell = row.columns[column]
                cell:SetText(tostring(c[key].total) .. (c[key].fix ~= 0 and "*" or ""))
                if c[key].fix ~= 0 then cell:SetTextColor(CORRECTED[1], CORRECTED[2], CORRECTED[3])
                elseif c[key].total > 0 then cell:SetTextColor(0.94, 0.97, 1.00)
                else cell:SetTextColor(0.45, 0.55, 0.62) end
            end
            ns.highlight(row, ns.lower(name) == ns.lower(selectedName or "") and "selected" or nil)
            row:Show()
        else
            row:Hide()
        end
    end
    if table.getn(names) == 0 then emptyText:Show() else emptyText:Hide() end
end

local function playerAwards(name)
    local found = {}
    for _, record in ipairs(core.history()) do
        local holder = (record.state == "held" and record.winner) or record.recipient
        if record.state ~= "deleted" and ns.lower(holder) == ns.lower(name) then table.insert(found, record) end
    end
    return found
end

local function drawDetail()
    local mayEdit = not ns.mayEdit or ns.mayEdit()
    if not selectedName then
        playerTitle:SetText(L["Select a player on the left"])
        playerTitle:SetTextColor(0.94, 0.97, 1.00)
        for _, row in ipairs(counterRows) do
            row.value:SetText("")
            ns.setEnabled(row.minus, false)
            ns.setEnabled(row.plus, false)
        end
        ns.setEnabled(resetButton, false)
        awardsHeading:SetText("")
        for _, row in ipairs(awardRows) do row:Hide() end
        return
    end
    playerTitle:SetText(selectedName)
    ns.classColor(playerTitle, selectedName)
    local c = counts(selectedName)
    local anyFix = false
    for i, counter in ipairs(COUNTERS) do
        local row, value = counterRows[i], c[counter.key]
        row.value:SetText(value.fix ~= 0 and string.format("%d (%+d)", value.total, value.fix) or tostring(value.total))
        if value.fix ~= 0 then
            anyFix = true
            row.value:SetTextColor(CORRECTED[1], CORRECTED[2], CORRECTED[3])
        else
            row.value:SetTextColor(0.94, 0.97, 1.00)
        end
        ns.setEnabled(row.minus, mayEdit and value.total > 0)
        ns.setEnabled(row.plus, mayEdit)
    end
    ns.setEnabled(resetButton, mayEdit and anyFix)
    local awards = playerAwards(selectedName)
    awardsHeading:SetText(string.format(L["AWARDS (%d)"], table.getn(awards)))
    for i, row in ipairs(awardRows) do
        local record = awards[i]
        row.record = record
        if record then
            row:SetText(string.format("#%d  %s", record.id, record.item))
            row.columns[1]:SetText(record.spec and string.upper(record.spec) or "-")
            row:Show()
        else
            row:Hide()
        end
    end
end

local function refresh()
    drawList()
    drawDetail()
end

local tallyTab = ns.addTab("tally", L["TALLY"], panel, refresh, "RaidLedgerTabButtonTally")
ns.tip(tallyTab.button, L["Items and tokens per player this raid (what the fewest-items rule ranks by), with corrections"])

for _, row in ipairs(playerRows) do
    row:SetScript("OnClick", function(self)
        if not self.playerName then return end
        selectedName = self.playerName
        ui.refresh()
    end)
    row:SetScript("OnEnter", function(self)
        if not self.playerName then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.playerName)
        ns.addPlayerLines(self.playerName)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
end
for _, row in ipairs(awardRows) do
    row:SetScript("OnClick", function(self) if self.record then ns.showAward(self.record) end end)
    row:SetScript("OnEnter", function(self)
        if not self.record then return end
        ns.itemTooltip(self, self.record.item)
        GameTooltip:AddLine(L["Click: open this award (change its tally there)"], 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
end
for _, row in ipairs(counterRows) do
    row.minus:SetScript("OnClick", function(self) if selectedName then roster.adjustTally(selectedName, self.counter, -1) end end)
    row.plus:SetScript("OnClick", function(self) if selectedName then roster.adjustTally(selectedName, self.counter, 1) end end)
    ns.tip(row.minus, L["One less (a correction; the awards stay)"])
    ns.tip(row.plus, L["One more (a correction; the awards stay)"])
end
resetButton:SetScript("OnClick", function() if selectedName then roster.adjustTally(selectedName, "reset") end end)
ns.tip(resetButton, L["Remove this player's corrections: the tally comes from the awards only"])
ns.scrollable(list, function() return playerOffset end, function(v) playerOffset = v end, drawList)

-- ns.showTally opens the tally on one player (e.g. from a roll's tooltip).
function ns.showTally(name)
    selectedName = name
    ui.show("tally")
end
