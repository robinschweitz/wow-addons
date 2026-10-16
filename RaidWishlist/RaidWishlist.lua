-- RaidWishlist: the raid member's side of RaidLedger, for WoW 3.3.5a / Lua 5.1.
-- Imports the wishlist exported by the guild website (WL2), offers a one-click
-- roll (or rolls automatically) when the raid lead's ledger starts a roll on a
-- wishlisted item, and shows who got what this raid from the ledger's shared
-- awards (addon messages, prefix FLLedger).
local _, ns = ...
local L = ns.L
local Wishlist = CreateFrame("Frame", "RaidWishlistFrame", UIParent)
local PREFIX = "FLLedger"
local WISH_ROWS = 5
local OPEN_ROWS = 4
local RAID_ROWS = 5
local AUTO_DELAY = 1        -- seconds before an automatic roll
local SPEC_LABELS = { ms = "MS", os = "OS" }
-- Disenchanted or banked items have a holder but count for nobody.
local NO_TALLY = { disenchanted = true, bank = true }
local TOKEN_NAMES = { "Weiheabzeichen" }

local wishRows, openRows, raidRows = {}, {}, {}
local raidOffset = 0
local prompt                -- the open roll prompt { key, entry, endsAt }
local pendingRoll           -- an automatic roll waiting for its delay
local rolled = {}           -- rollKey:round -> true, so every roll happens once
local syncAt
local shareAt               -- when to send this wishlist to the group
local WISHES_PER_MESSAGE = 15

local function trim(value)
    return (value or ""):match("^%s*(.-)%s*$")
end

local function lower(value)
    return string.lower(value or "")
end

local function playerName()
    return UnitName("player") or ""
end

local function isPlayer(name)
    return lower(name) == lower(playerName())
end

local function say(text)
    DEFAULT_CHAT_FRAME:AddMessage("RaidWishlist: " .. text)
end

local function split(text)
    local fields = {}
    for value in string.gmatch(text .. ";", "([^;]*);") do table.insert(fields, value) end
    return fields
end

local function itemLink(itemID)
    return (itemID and select(2, GetItemInfo(itemID))) or ("item:" .. tostring(itemID or 0))
end

local function isToken(link)
    for _, name in ipairs(TOKEN_NAMES) do
        if string.find(link or "", name, 1, true) then return true end
    end
    return false
end

local function ensureDatabase()
    RaidWishlistDB = RaidWishlistDB or {}
    local db = RaidWishlistDB
    db.chars = db.chars or {}
    db.raid = db.raid or { awards = {} }
    db.raid.awards = db.raid.awards or {}
    local me = playerName()
    db.chars[me] = db.chars[me] or { items = {} }
    return db, db.chars[me]
end

local MAX_ENHANCED = 50     -- X = min(EP, 50), the website's rule

-- enhancedPoints is X for an enhanced main-spec roll: the EP balance from the
-- last export, minus what enhanced wins since then cost, at most 50.
local function enhancedPoints(char)
    local balance = char.balance or 0
    for _, spent in pairs(char.spent or {}) do balance = balance - spent end
    return math.max(0, math.min(balance, MAX_ENHANCED))
end

-- The roll range for a wishlist entry: main spec 1-100 (1+X..100+X when the
-- website marked it enhanced and EP are left), off spec always 1-99.
local function rollRange(entry)
    if entry.spec == "os" then return 1, 99 end
    local x = 0
    if entry.enhanced then
        local _, char = ensureDatabase()
        x = enhancedPoints(char)
    end
    return 1 + x, 100 + x
end

local function rangeLabel(entry)
    local low, high = rollRange(entry)
    if entry.spec == "os" then return "OS 1-99" end
    return low > 1 and ("MS " .. low .. "-" .. high) or "MS 1-100"
end

---------------------------------------------------------------------------
-- Wishlist import. The website exports one character's list:
--   WL2;<character>;<exported unix time>;<EP balance>
--   <itemID>;<ms|os>;<enhanced 0/1, main spec only>;<rank>;<note>
---------------------------------------------------------------------------
local function parseWishlist(text)
    local lines = {}
    for line in string.gmatch((text or "") .. "\n", "([^\n]*)\n") do
        line = trim(string.gsub(line, "\r", ""))
        if line ~= "" then table.insert(lines, line) end
    end
    if table.getn(lines) == 0 then return nil, L["Paste the wishlist export from the website first."] end
    local header = split(lines[1])
    if header[1] ~= "WL2" or not header[2] or header[2] == "" or not tonumber(header[4]) then
        return nil, L["That is not a wishlist export (it must start with WL2;). Export it again from the website."]
    end
    local items, bad = {}, {}
    for i = 2, table.getn(lines) do
        local f = split(lines[i])
        local itemID, spec, enhanced, priority = tonumber(f[1]), lower(f[2]), f[3], tonumber(f[4])
        local valid = itemID and (spec == "ms" or spec == "os") and (enhanced == "0" or enhanced == "1")
            and not (spec == "os" and enhanced == "1")
        if valid then
            table.insert(items, { itemID = itemID, spec = spec, enhanced = enhanced == "1" or nil,
                priority = priority or (table.getn(items) + 1),
                note = string.gsub(f[5] or "", "|", "") })
        else
            table.insert(bad, i)
        end
    end
    table.sort(items, function(a, b)
        if a.priority ~= b.priority then return a.priority < b.priority end
        return a.itemID < b.itemID
    end)
    return { character = header[2], exportedAt = tonumber(header[3]), balance = tonumber(header[4]), items = items },
        nil, bad
end

local function findWish(itemID)
    local _, char = ensureDatabase()
    for _, entry in ipairs(char.items) do
        if entry.itemID == itemID then return entry end
    end
end

---------------------------------------------------------------------------
-- This raid's awards, from the ledger's shared "A" messages.
---------------------------------------------------------------------------
local function sessionTime(session)
    return tonumber(string.match(session or "", "%-(%d+)$")) or 0
end

-- awardOwner is who an award counts for: the recipient, or the roll winner
-- while the master looter holds the item for them.
local function awardOwner(award)
    return (award.state == "held" and award.winner) or award.recipient
end

-- An open award waits for its roll: parked with a raider, or kept by the
-- master looter without a roll yet.
local function isOpenAward(award)
    return award.state == "parked" or (award.state == "held" and not award.spec and not award.winner)
end

local function sortedAwards()
    local db = ensureDatabase()
    local list = {}
    for _, award in pairs(db.raid.awards) do table.insert(list, award) end
    table.sort(list, function(a, b)
        if (a.at or 0) ~= (b.at or 0) then return (a.at or 0) > (b.at or 0) end
        return a.key < b.key
    end)
    return list
end

-- myTally counts your awards this raid in two separate lists, like the
-- ledger: items { ms, os } and tokens { ms, os }.
local function myTally()
    local items, tokens = { ms = 0, os = 0 }, { ms = 0, os = 0 }
    for _, award in ipairs(sortedAwards()) do
        if award.state ~= "deleted" and not NO_TALLY[award.state] and (award.spec == "ms" or award.spec == "os")
            and isPlayer(awardOwner(award)) then
            local list = award.token and tokens or items
            list[award.spec] = list[award.spec] + 1
        end
    end
    return items, tokens
end

-- received marks wishlist items this player already got (or won) this raid;
-- the addon does not roll on them again.
local function refreshReceived()
    local _, char = ensureDatabase()
    for _, entry in ipairs(char.items) do entry.received = nil end
    for _, award in ipairs(sortedAwards()) do
        -- Holding an item until its roll is not receiving it.
        if award.state ~= "deleted" and not NO_TALLY[award.state] and not isOpenAward(award)
            and isPlayer(awardOwner(award)) then
            local entry = findWish(award.itemID)
            if entry then entry.received = true end
        end
    end
end

-- followSession keeps this raid's lists: a newer raid replaces them, an older
-- one (a stale ledger) is ignored.
local function followSession(session)
    local db = ensureDatabase()
    if session == "" then return false end
    if session ~= db.raid.session then
        if db.raid.session and sessionTime(session) < sessionTime(db.raid.session) then return false end
        db.raid = { session = session, awards = {}, corpse = {} }
    end
    db.raid.corpse = db.raid.corpse or {}
    return true
end

-- applyOpenItems stores a ledger's list of loot still waiting in its roll list:
-- "itemID:status:source:winner,...", status o/r/w, source c (corpse) or
-- a<award id> (an open award being rolled later).
local function applyOpenItems(f)
    if f[3] == "" or not followSession(f[2]) then return false end
    local list = {}
    for item in string.gmatch(f[4] or "", "[^,]+") do
        local itemID, itemStatus, source, winner = string.match(item, "^(%d+):(%a):(%w+):(.*)$")
        if itemID then
            table.insert(list, { itemID = tonumber(itemID), status = itemStatus, source = source,
                winner = winner ~= "" and winner or nil })
        end
    end
    ensureDatabase().raid.corpse[lower(f[3])] = list
    return true
end

local function applyAward(f)
    local id, rev = tonumber(f[4]), tonumber(f[5])
    if not id or not rev or f[3] == "" or table.getn(f) < 19 then return false end
    if not followSession(f[2]) then return false end
    local db = ensureDatabase()
    local key = lower(f[3]) .. ":" .. id
    local award = db.raid.awards[key]
    if award and award.rev >= rev then return false end
    local itemID = tonumber(f[7])
    award = award or { key = key }
    award.rev, award.at, award.itemID = rev, tonumber(f[6]) or 0, itemID
    award.item = itemLink(itemID)
    award.recipient, award.state = f[9], f[10]
    award.spec = (f[12] == "ms" or f[12] == "os") and f[12] or nil
    award.roll, award.winner = tonumber(f[13]), f[16] ~= "" and f[16] or nil
    award.token = f[18] == "1" or isToken(award.item) or nil
    db.raid.awards[key] = award
    -- An enhanced win of mine costs X until the next export brings the new balance.
    local _, char = ensureDatabase()
    local low, high = tonumber(f[14]), tonumber(f[15])
    local mine = award.state ~= "deleted" and isPlayer(award.winner or award.recipient)
    char.spent = char.spent or {}
    if mine and low and high == low + 99 and low > 1 and award.at >= (char.exportedAt or 0) then
        char.spent[key] = low - 1
    else
        char.spent[key] = nil
    end
    return true
end

-- openItems lists what is still to be rolled: corpse loot from the ledgers'
-- lists, and open awards (with their roll status from those lists).
local function openItems()
    local db = ensureDatabase()
    local list, rolling = {}, {}
    for origin, items in pairs(db.raid.corpse or {}) do
        for _, item in ipairs(items) do
            if item.source == "c" then
                table.insert(list, { itemID = item.itemID, item = itemLink(item.itemID), where = L["on the corpse"],
                    status = item.status, winner = item.winner })
            else
                rolling[origin .. ":" .. string.sub(item.source, 2)] = item
            end
        end
    end
    for _, award in ipairs(sortedAwards()) do
        if isOpenAward(award) then
            local live = rolling[award.key]
            table.insert(list, { itemID = award.itemID, item = award.item, where = string.format(L["with %s"], award.recipient),
                status = live and live.status or "o", winner = live and live.winner })
        end
    end
    return list
end

---------------------------------------------------------------------------
-- UI
---------------------------------------------------------------------------
local function makeBackdrop(frame, red, green, blue, alpha)
    frame:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetBackdropColor(red, green, blue, alpha)
    frame:SetBackdropBorderColor(0.36, 0.72, 0.42, 0.92)
end

local function label(parent, template, size, color)
    local text = parent:CreateFontString(nil, "OVERLAY", template)
    if size then text:SetFont(STANDARD_TEXT_FONT, size) end
    if color then text:SetTextColor(color[1], color[2], color[3]) end
    return text
end

local function flatButton(parent, name, caption, width, height)
    local button = CreateFrame("Button", name, parent)
    button:SetWidth(width)
    button:SetHeight(height or 22)
    makeBackdrop(button, 0.10, 0.26, 0.15, 0.98)
    local text = label(button, "GameFontNormal", 10, {0.78, 0.96, 0.80})
    text:SetPoint("CENTER", button, "CENTER", 0, 0)
    button:SetFontString(text)
    button:SetText(caption)
    return button
end

local function listRow(parent, index, width, top, tagWidth)
    local row = CreateFrame("Button", nil, parent)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, top - (index - 1) * 17)
    row:SetWidth(width)
    row:SetHeight(16)
    row:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground" })
    row:SetBackdropColor(0.08, 0.18, 0.11, 0)
    local text = label(row, "GameFontNormalSmall", 10, {0.80, 0.90, 0.84})
    text:SetPoint("LEFT", row, "LEFT", 5, 0)
    text:SetPoint("RIGHT", row, "RIGHT", -(tagWidth or 96), 0)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    row:SetFontString(text)
    row.right = label(row, "GameFontNormalSmall", 9, {1.00, 0.82, 0.30})
    row.right:SetPoint("RIGHT", row, "RIGHT", -5, 0)
    row.right:SetJustifyH("RIGHT")
    return row
end

Wishlist:SetWidth(470)
Wishlist:SetHeight(440)
Wishlist:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
Wishlist:SetFrameStrata("DIALOG")
Wishlist:SetClampedToScreen(true)
Wishlist:EnableMouse(true)
Wishlist:SetMovable(true)
Wishlist:RegisterForDrag("LeftButton")
Wishlist:SetScript("OnDragStart", function(self) self:StartMoving() end)
Wishlist:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
makeBackdrop(Wishlist, 0.020, 0.040, 0.030, 0.97)
-- Raise above RaidLedger (same strata) when shown or clicked, so the two
-- windows never draw through each other.
Wishlist:SetToplevel(true)
Wishlist:SetScript("OnShow", function(self) self:Raise() end)
Wishlist:Hide()

local title = label(Wishlist, "GameFontNormalLarge", 17, {0.62, 0.92, 0.66})
title:SetPoint("TOPLEFT", Wishlist, "TOPLEFT", 16, -16)
title:SetText(L["LOOT WISHLIST"])

local subtitle = label(Wishlist, "GameFontNormalSmall", 10, {0.50, 0.66, 0.54})
subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 1, -2)

local close = flatButton(Wishlist, nil, "X", 24, 24)
close:SetPoint("TOPRIGHT", Wishlist, "TOPRIGHT", -12, -12)
close:SetScript("OnClick", function() Wishlist:Hide() end)

local importOpen = flatButton(Wishlist, "RaidWishlistImportOpen", L["IMPORT"], 70, 24)
importOpen:SetPoint("RIGHT", close, "LEFT", -6, 0)

local autoButton = flatButton(Wishlist, "RaidWishlistAuto", L["AUTO-ROLL: OFF"], 120, 24)
autoButton:SetPoint("RIGHT", importOpen, "LEFT", -6, 0)

local wishPane = CreateFrame("Frame", nil, Wishlist)
wishPane:SetPoint("TOPLEFT", Wishlist, "TOPLEFT", 12, -60)
wishPane:SetWidth(446)
wishPane:SetHeight(120)
makeBackdrop(wishPane, 0.030, 0.065, 0.045, 0.97)

local wishHeading = label(wishPane, "GameFontNormal", 11, {1.00, 0.82, 0.32})
wishHeading:SetPoint("TOPLEFT", wishPane, "TOPLEFT", 12, -10)
wishHeading:SetText(L["MY WISHLIST"])

local wishEmpty = label(wishPane, "GameFontNormalSmall", 11, {0.48, 0.64, 0.52})
wishEmpty:SetPoint("CENTER", wishPane, "CENTER", 0, -8)
wishEmpty:SetJustifyH("CENTER")
wishEmpty:SetText(L["No wishlist yet.\nCopy the export on the guild website, then IMPORT."])

for i = 1, WISH_ROWS do wishRows[i] = listRow(wishPane, i, 430, -28) end

local openPane = CreateFrame("Frame", nil, Wishlist)
openPane:SetPoint("TOPLEFT", wishPane, "BOTTOMLEFT", 0, -8)
openPane:SetWidth(446)
openPane:SetHeight(103)
makeBackdrop(openPane, 0.030, 0.065, 0.045, 0.97)

local openHeading = label(openPane, "GameFontNormal", 11, {1.00, 0.82, 0.32})
openHeading:SetPoint("TOPLEFT", openPane, "TOPLEFT", 12, -10)
openHeading:SetText(L["OPEN ITEMS"])

local openEmpty = label(openPane, "GameFontNormalSmall", 11, {0.48, 0.64, 0.52})
openEmpty:SetPoint("CENTER", openPane, "CENTER", 0, -8)
openEmpty:SetJustifyH("CENTER")
openEmpty:SetText(L["No loot is waiting to be rolled."])

for i = 1, OPEN_ROWS do openRows[i] = listRow(openPane, i, 430, -28, 150) end

local raidPane = CreateFrame("Frame", nil, Wishlist)
raidPane:SetPoint("TOPLEFT", openPane, "BOTTOMLEFT", 0, -8)
raidPane:SetWidth(446)
raidPane:SetHeight(120)
makeBackdrop(raidPane, 0.030, 0.065, 0.045, 0.97)
raidPane:EnableMouseWheel(true)

local raidHeading = label(raidPane, "GameFontNormal", 11, {1.00, 0.82, 0.32})
raidHeading:SetPoint("TOPLEFT", raidPane, "TOPLEFT", 12, -10)
raidHeading:SetText(L["THIS RAID"])

local tallyText = label(raidPane, "GameFontNormalSmall", 9, {0.50, 0.66, 0.54})
tallyText:SetPoint("TOPRIGHT", raidPane, "TOPRIGHT", -12, -11)
tallyText:SetJustifyH("RIGHT")

local raidEmpty = label(raidPane, "GameFontNormalSmall", 11, {0.48, 0.64, 0.52})
raidEmpty:SetPoint("CENTER", raidPane, "CENTER", 0, -8)
raidEmpty:SetJustifyH("CENTER")
raidEmpty:SetText(L["Nothing handed out yet.\nAwards appear here when the raid lead uses RaidLedger."])

for i = 1, RAID_ROWS do raidRows[i] = listRow(raidPane, i, 430, -28) end

local status = label(Wishlist, "GameFontNormalSmall", 10, {0.46, 0.62, 0.50})
status:SetPoint("BOTTOMLEFT", Wishlist, "BOTTOMLEFT", 16, 12)
status:SetPoint("BOTTOMRIGHT", Wishlist, "BOTTOMRIGHT", -16, 12)
status:SetJustifyH("LEFT")
status:SetWordWrap(false)
status:SetText(L["Rolls start from the raid lead's RaidLedger  |  /wish help"])

-- Import overlay: covers the two lists while shown.
local importPanel = CreateFrame("Frame", "RaidWishlistImportPanel", Wishlist)
importPanel:SetPoint("TOPLEFT", Wishlist, "TOPLEFT", 12, -60)
importPanel:SetWidth(446)
importPanel:SetHeight(351)
makeBackdrop(importPanel, 0.030, 0.065, 0.045, 0.99)
importPanel:SetFrameLevel(Wishlist:GetFrameLevel() + 5)
importPanel:Hide()

local importHint = label(importPanel, "GameFontNormalSmall", 10, {0.62, 0.80, 0.66})
importHint:SetPoint("TOPLEFT", importPanel, "TOPLEFT", 12, -12)
importHint:SetText(L["Paste your wishlist export from the guild website (Ctrl+V):"])

local importBack = CreateFrame("Frame", nil, importPanel)
importBack:SetPoint("TOPLEFT", importPanel, "TOPLEFT", 10, -32)
importBack:SetPoint("BOTTOMRIGHT", importPanel, "BOTTOMRIGHT", -10, 42)
makeBackdrop(importBack, 0.01, 0.02, 0.015, 0.98)

local importScroll = CreateFrame("ScrollFrame", nil, importBack)
importScroll:SetPoint("TOPLEFT", importBack, "TOPLEFT", 8, -8)
importScroll:SetPoint("BOTTOMRIGHT", importBack, "BOTTOMRIGHT", -8, 8)

local importText = CreateFrame("EditBox", "RaidWishlistImportText", importScroll)
importText:SetMultiLine(true)
importText:SetAutoFocus(false)
importText:SetFontObject(ChatFontNormal)
importText:SetWidth(410)
importText:SetHeight(220)
importScroll:SetScrollChild(importText)
importText:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

local importButton = flatButton(importPanel, "RaidWishlistImportButton", L["IMPORT WISHLIST"], 130, 24)
importButton:SetPoint("BOTTOMRIGHT", importPanel, "BOTTOMRIGHT", -10, 10)
local importCancel = flatButton(importPanel, nil, "CANCEL", 70, 24)
importCancel:SetPoint("RIGHT", importButton, "LEFT", -6, 0)

-- Roll prompt: one click rolls the wishlisted spec and points.
local Prompt = CreateFrame("Frame", "RaidWishlistPrompt", UIParent)
Prompt:SetWidth(340)
Prompt:SetHeight(104)
-- At the top of the screen, above the raid lead's RaidLedger window
-- (live run 638949e7b728 showed the prompt covering its panes).
Prompt:SetPoint("TOP", UIParent, "TOP", 0, -20)
Prompt:SetFrameStrata("FULLSCREEN_DIALOG")
Prompt:SetClampedToScreen(true)
makeBackdrop(Prompt, 0.020, 0.050, 0.030, 0.98)
Prompt:Hide()

local promptTitle = label(Prompt, "GameFontNormal", 11, {1.00, 0.82, 0.32})
promptTitle:SetPoint("TOPLEFT", Prompt, "TOPLEFT", 12, -10)
promptTitle:SetText(L["ON YOUR WISHLIST"])

local promptTimer = label(Prompt, "GameFontNormalSmall", 10, {0.62, 0.80, 0.66})
promptTimer:SetPoint("TOPRIGHT", Prompt, "TOPRIGHT", -12, -11)
promptTimer:SetJustifyH("RIGHT")

local promptItem = label(Prompt, "GameFontHighlight", 12, {0.94, 0.98, 0.95})
promptItem:SetPoint("TOPLEFT", Prompt, "TOPLEFT", 12, -28)
promptItem:SetPoint("TOPRIGHT", Prompt, "TOPRIGHT", -12, -28)
promptItem:SetJustifyH("LEFT")
promptItem:SetWordWrap(false)

local promptNote = label(Prompt, "GameFontNormalSmall", 10, {0.62, 0.80, 0.66})
promptNote:SetPoint("TOPLEFT", promptItem, "BOTTOMLEFT", 0, -4)
promptNote:SetPoint("TOPRIGHT", promptItem, "BOTTOMRIGHT", 0, -4)
promptNote:SetJustifyH("LEFT")
promptNote:SetWordWrap(false)

local rollButton = flatButton(Prompt, "RaidWishlistRoll", L["ROLL"], 170, 26)
rollButton:SetPoint("BOTTOMLEFT", Prompt, "BOTTOMLEFT", 12, 10)
local skipButton = flatButton(Prompt, "RaidWishlistSkip", L["SKIP"], 80, 26)
skipButton:SetPoint("LEFT", rollButton, "RIGHT", 8, 0)

---------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------
local function updateAutoButton()
    local _, char = ensureDatabase()
    autoButton:SetText(char.auto and L["AUTO-ROLL: ON"] or L["AUTO-ROLL: OFF"])
    autoButton:SetBackdropColor(char.auto and 0.16 or 0.10, char.auto and 0.42 or 0.26, char.auto and 0.20 or 0.15, 0.98)
end

local function updateWishlist()
    local _, char = ensureDatabase()
    local count = table.getn(char.items)
    wishHeading:SetText(count > 0 and string.format(L["MY WISHLIST (%d)"], count) or L["MY WISHLIST"])
    if count > 0 then wishEmpty:Hide() else wishEmpty:Show() end
    for i = 1, WISH_ROWS do
        local row, entry = wishRows[i], char.items[i]
        row.entry = entry
        if entry then
            row:SetText(string.format("%d. %s", entry.priority, itemLink(entry.itemID)))
            if entry.received then
                row.right:SetText(L["RECEIVED"])
                row.right:SetTextColor(0.45, 0.85, 0.55)
            else
                row.right:SetText(rangeLabel(entry))
                row.right:SetTextColor(1.00, 0.82, 0.30)
            end
            row:Show()
        else
            row:Hide()
        end
    end
end

local function updateRaid()
    local awards = {}
    for _, award in ipairs(sortedAwards()) do
        if not isOpenAward(award) then table.insert(awards, award) end   -- open ones are listed above
    end
    local count = table.getn(awards)
    raidOffset = math.max(0, math.min(raidOffset, count - RAID_ROWS))
    raidHeading:SetText(count > 0 and string.format(L["THIS RAID (%d)"], count) or L["THIS RAID"])
    local items, tokens = myTally()
    tallyText:SetText(string.format(L["YOU: ITEMS %d MS / %d OS  |  TOKENS %d MS / %d OS"],
        items.ms, items.os, tokens.ms, tokens.os))
    if count > 0 then raidEmpty:Hide() else raidEmpty:Show() end
    for i = 1, RAID_ROWS do
        local row, award = raidRows[i], awards[i + raidOffset]
        row.award = award
        if award then
            local text = string.format("%s  ->  %s", award.item, award.recipient)
            if award.state == "deleted" then text = "|cff777777" .. string.gsub(text, "|c%x%x%x%x%x%x%x%x", "") .. "|r" end
            row:SetText(text)
            local tag = award.state == "deleted" and L["REMOVED"] or (award.state == "disenchanted" and L["DE"])
                or (award.state == "bank" and L["BANK"]) or (SPEC_LABELS[award.spec] or "")
            if award.token and award.state ~= "deleted" then tag = tag .. L[" TOKEN"] end
            row.right:SetText(tag)
            local mine = isPlayer(awardOwner(award)) and award.state ~= "deleted"
            local wished = findWish(award.itemID) ~= nil
            row:SetBackdropColor(0.10, mine and 0.30 or 0.20, 0.14, (mine or wished) and 0.9 or 0)
            row:Show()
        else
            row:Hide()
        end
    end
end

local OPEN_STATUS = { o = L["OPEN"], r = L["ROLLING NOW"], w = L["WON"] }

local function updateOpen()
    local items = openItems()
    local count = table.getn(items)
    openHeading:SetText(count > 0 and string.format(L["OPEN ITEMS (%d)"], count) or L["OPEN ITEMS"])
    if count > 0 then openEmpty:Hide() else openEmpty:Show() end
    for i = 1, OPEN_ROWS do
        local row, item = openRows[i], items[i]
        row.open = item
        if item then
            row:SetText(string.format("%s  %s", item.item, item.where))
            local tag = OPEN_STATUS[item.status] or L["OPEN"]
            if item.status == "w" and item.winner then tag = string.format(L["WON: %s"], string.upper(item.winner)) end
            local wished = findWish(item.itemID)
            if wished and not wished.received and item.status ~= "w" then tag = L["WISHLIST  "] .. tag end
            row.right:SetText(tag)
            if item.status == "r" then
                row.right:SetTextColor(0.45, 0.85, 0.55)
            else
                row.right:SetTextColor(1.00, 0.82, 0.30)
            end
            row:SetBackdropColor(0.10, 0.20, 0.14, wished and 0.9 or 0)
            row:Show()
        else
            row:Hide()
        end
    end
end

local function refresh()
    refreshReceived()
    subtitle:SetText(string.format(L["WISHLIST FOR %s  /  ROLLS  /  WHO GOT WHAT"], string.upper(playerName())))
    updateAutoButton()
    updateWishlist()
    updateOpen()
    updateRaid()
end

---------------------------------------------------------------------------
-- Rolling
---------------------------------------------------------------------------
local function doRoll(entry, key)
    if rolled[key] then return end
    rolled[key] = true
    local low, high = rollRange(entry)
    RandomRoll(low, high)
    status:SetText(string.format(L["Rolled %s for %s."], rangeLabel(entry), itemLink(entry.itemID)))
end

local function hidePrompt()
    prompt = nil
    Prompt:Hide()
end

local function showPrompt(entry, key, seconds)
    prompt = { entry = entry, key = key, endsAt = GetTime() + seconds }
    promptItem:SetText(itemLink(entry.itemID))
    local note = entry.note ~= "" and ("  -  " .. entry.note) or ""
    promptNote:SetText(string.format(L["Priority %d, %s%s"], entry.priority, rangeLabel(entry), note))
    rollButton:SetText(string.format(L["ROLL %s"], rangeLabel(entry)))
    Prompt:Show()
end

rollButton:SetScript("OnClick", function()
    if prompt then doRoll(prompt.entry, prompt.key) end
    hidePrompt()
end)
skipButton:SetScript("OnClick", function()
    if prompt then
        rolled[prompt.key] = true
        status:SetText(string.format(L["Skipped %s."], itemLink(prompt.entry.itemID)))
    end
    hidePrompt()
end)

-- onRollStart reacts to the ledger's "S;session;origin;rollKey;itemID;seconds;
-- round;tied" message: a wishlisted item (not yet received) gets a prompt or an
-- automatic roll. A tie-break only concerns the tied players.
local function onRollStart(f)
    local itemID, seconds, round = tonumber(f[5]), tonumber(f[6]), tonumber(f[7]) or 1
    if not itemID or not seconds or f[4] == "" then return end
    local entry = findWish(itemID)
    if not entry or entry.received then return end
    if round > 1 then
        local tied = false
        for name in string.gmatch(f[8] or "", "[^,]+") do
            if isPlayer(name) then tied = true end
        end
        if not tied then return end
    end
    local key = f[3] .. ":" .. f[4] .. ":" .. round
    if rolled[key] then return end
    if not Wishlist:IsShown() then
        refresh()
        Wishlist:Show()
    end
    local _, char = ensureDatabase()
    if char.auto then
        pendingRoll = { entry = entry, key = key, at = GetTime() + AUTO_DELAY }
        status:SetText(string.format(L["Auto-roll: %s for %s in a moment."], rangeLabel(entry), itemLink(entry.itemID)))
    else
        showPrompt(entry, key, seconds)
    end
end

---------------------------------------------------------------------------
-- Addon messages and sync
---------------------------------------------------------------------------
local function inGroup(name)
    if isPlayer(name) then return true end
    local key = lower(name)
    if GetNumRaidMembers() and GetNumRaidMembers() > 0 then
        for i = 1, GetNumRaidMembers() do
            if lower(GetRaidRosterInfo(i)) == key then return true end
        end
        return false
    end
    for i = 1, GetNumPartyMembers() do
        if lower(UnitName("party" .. i)) == key then return true end
    end
    return false
end

local function groupChannel()
    if GetNumRaidMembers() and GetNumRaidMembers() > 0 then return "RAID" end
    if GetNumPartyMembers() and GetNumPartyMembers() > 0 then return "PARTY" end
end

-- shareWishlist sends this character's wishlist to the group so the raid
-- lead's ledger can show who wants an item:
--   W;<exported at>;<part>;<parts>;<itemID>:<m|o>:<enhanced 0|1>:<rank>,...
-- An empty list is sent too: it clears an older copy.
local function shareWishlist()
    local channel = groupChannel()
    local _, char = ensureDatabase()
    if not channel or char.noShare then return false end
    local items = char.items
    local parts = math.max(1, math.ceil(table.getn(items) / WISHES_PER_MESSAGE))
    for part = 1, parts do
        local list = {}
        for i = (part - 1) * WISHES_PER_MESSAGE + 1, math.min(part * WISHES_PER_MESSAGE, table.getn(items)) do
            local entry = items[i]
            table.insert(list, string.format("%d:%s:%d:%d", entry.itemID, entry.spec == "os" and "o" or "m",
                entry.enhanced and 1 or 0, i))
        end
        SendAddonMessage(PREFIX, table.concat({ "W", tostring(char.exportedAt or 0), part, parts,
            table.concat(list, ",") }, ";"), channel)
    end
    return true
end

-- answerDelay spreads the answers of a whole raid over 1-5 seconds.
local function answerDelay()
    local sum = 0
    for i = 1, string.len(playerName()) do sum = sum + string.byte(playerName(), i) end
    return 1 + (sum % 40) / 10
end

-- requestSync asks the raid lead's ledger for this raid's awards (after a
-- login or /reload). The ledger answers its own awards to any group member.
local function requestSync()
    local channel = groupChannel()
    if channel then
        SendAddonMessage(PREFIX, "Q;" .. (ensureDatabase().raid.session or "-") .. ";" .. playerName(), channel)
        return true
    end
    return false
end

local function onAddonMessage(prefix, message, channel, sender)
    if prefix ~= PREFIX or type(message) ~= "string" or not sender then return end
    if (channel ~= "RAID" and channel ~= "PARTY") or not inGroup(sender) then return end
    local f = split(message)
    if f[1] == "S" then
        onRollStart(f)
    elseif f[1] == "A" then
        if applyAward(f) then refresh() end
    elseif f[1] == "O" then
        if applyOpenItems(f) then refresh() end
    elseif f[1] == "WQ" then
        shareAt = shareAt or (GetTime() + answerDelay())
    end
end

---------------------------------------------------------------------------
-- Import, buttons, events
---------------------------------------------------------------------------
local function showImport(show)
    if show then
        Wishlist:Show()
        importPanel:Show()
        wishPane:Hide()
        openPane:Hide()
        raidPane:Hide()
    else
        importText:ClearFocus()
        importPanel:Hide()
        wishPane:Show()
        openPane:Show()
        raidPane:Show()
    end
end

local function importWishlist()
    local list, err, bad = parseWishlist(importText:GetText())
    if not list then
        status:SetText(err)
        return
    end
    if not isPlayer(list.character) then
        status:SetText(string.format(L["This wishlist is for %s. Log in with %s to import it."], list.character, list.character))
        return
    end
    local _, char = ensureDatabase()
    char.items, char.exportedAt, char.balance, char.spent = list.items, list.exportedAt, list.balance, {}
    shareAt = GetTime() + 1     -- the raid lead's ledger learns the new list
    importText:SetText("")
    showImport(false)
    refresh()
    local skipped = table.getn(bad) > 0 and string.format(L[" (%d invalid lines skipped)"], table.getn(bad)) or ""
    status:SetText(string.format(L["Imported %d wishlist items%s."], table.getn(list.items), skipped))
    say(string.format(L["imported %d wishlist items%s."], table.getn(list.items), skipped))
end

local function setAuto(on)
    local _, char = ensureDatabase()
    char.auto = on and true or false
    updateAutoButton()
    say(char.auto and L["auto-roll is ON: wishlisted items are rolled for you."] or L["auto-roll is OFF: you get a roll prompt."])
end

importOpen:SetScript("OnClick", function() showImport(not importPanel:IsShown()) end)
importCancel:SetScript("OnClick", function() showImport(false) end)
importButton:SetScript("OnClick", importWishlist)
autoButton:SetScript("OnClick", function()
    local _, char = ensureDatabase()
    setAuto(not char.auto)
end)
raidPane:SetScript("OnMouseWheel", function(_, delta)
    raidOffset = raidOffset - delta
    updateRaid()
end)

local function showTooltip(owner, link, extra)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    local itemString = type(link) == "string" and string.match(link, "item:[%-%d:]+")
    if itemString then GameTooltip:SetHyperlink(itemString) else GameTooltip:ClearLines() end
    if extra then GameTooltip:AddLine(extra, 0.62, 0.92, 0.66) end
    GameTooltip:Show()
end

for _, row in ipairs(wishRows) do
    row:SetScript("OnEnter", function(self)
        if self.entry then
            showTooltip(self, itemLink(self.entry.itemID), string.format(L["Wishlist: %s"], rangeLabel(self.entry))
                .. (self.entry.note ~= "" and (" - " .. self.entry.note) or ""))
        end
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
end
for _, row in ipairs(openRows) do
    row:SetScript("OnEnter", function(self)
        if self.open then showTooltip(self, self.open.item, string.format(L["Waiting to be rolled, %s"], self.open.where)) end
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
end
for _, row in ipairs(raidRows) do
    row:SetScript("OnEnter", function(self)
        if self.award then
            showTooltip(self, self.award.item, string.format("%s - %s%s", self.award.recipient,
                SPEC_LABELS[self.award.spec] or L["no spec"], self.award.roll and string.format(L[", roll %d"], self.award.roll) or ""))
        end
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

---------------------------------------------------------------------------
-- Minimap button: click opens or closes the window, drag moves the button
-- around the minimap. The position is shared by all characters.
---------------------------------------------------------------------------
local MINIMAP_RADIUS = 80
local MinimapButton = CreateFrame("Button", "RaidWishlistMinimapButton", Minimap)
MinimapButton:SetWidth(31)
MinimapButton:SetHeight(31)
MinimapButton:SetFrameStrata("MEDIUM")
MinimapButton:SetFrameLevel(8)
MinimapButton:RegisterForClicks("LeftButtonUp")
MinimapButton:RegisterForDrag("LeftButton")
MinimapButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
local minimapIcon = MinimapButton:CreateTexture(nil, "BACKGROUND")
minimapIcon:SetTexture("Interface\\Icons\\INV_Misc_Note_02")
minimapIcon:SetWidth(20)
minimapIcon:SetHeight(20)
minimapIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
minimapIcon:SetPoint("TOPLEFT", MinimapButton, "TOPLEFT", 7, -5)
local minimapBorder = MinimapButton:CreateTexture(nil, "OVERLAY")
minimapBorder:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
minimapBorder:SetWidth(53)
minimapBorder:SetHeight(53)
minimapBorder:SetPoint("TOPLEFT", MinimapButton, "TOPLEFT", 0, 0)

local function placeMinimapButton()
    local db = ensureDatabase()
    local angle = math.rad(db.minimapAngle or 200)
    MinimapButton:ClearAllPoints()
    MinimapButton:SetPoint("CENTER", Minimap, "CENTER", MINIMAP_RADIUS * math.cos(angle), MINIMAP_RADIUS * math.sin(angle))
    if db.minimapHidden then MinimapButton:Hide() else MinimapButton:Show() end
end

local function toggleWindow()
    if Wishlist:IsShown() then
        Wishlist:Hide()
    else
        refresh()
        Wishlist:Show()
    end
end

MinimapButton:SetScript("OnClick", toggleWindow)
MinimapButton:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
        local centerX, centerY = Minimap:GetCenter()
        if not centerX then return end
        local cursorX, cursorY = GetCursorPosition()
        local scale = Minimap:GetEffectiveScale()
        ensureDatabase().minimapAngle = math.deg(math.atan2(cursorY / scale - centerY, cursorX / scale - centerX))
        placeMinimapButton()
    end)
end)
MinimapButton:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
MinimapButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("RaidWishlist")
    GameTooltip:AddLine(L["Click: open or close your wishlist"], 1, 1, 1)
    GameTooltip:AddLine(L["Drag: move this button"], 0.7, 0.7, 0.7)
    GameTooltip:Show()
end)
MinimapButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

local function setMinimapButton(show)
    ensureDatabase().minimapHidden = not show or nil
    placeMinimapButton()
    say(show and L["minimap button shown."] or L["minimap button hidden; /wish minimap on brings it back."])
end

Wishlist:RegisterEvent("PLAYER_LOGIN")
Wishlist:RegisterEvent("CHAT_MSG_ADDON")
Wishlist:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        ensureDatabase()
        refresh()
        placeMinimapButton()
        syncAt = GetTime() + 10
        if ForgeTestBridge and ForgeTestBridge.RegisterFrame then
            ForgeTestBridge:RegisterFrame("RaidWishlistFrame", self)
            ForgeTestBridge:RegisterFrame("RaidWishlistAuto", autoButton)
            ForgeTestBridge:RegisterFrame("RaidWishlistImportOpen", importOpen)
            ForgeTestBridge:RegisterFrame("RaidWishlistImportText", importText)
            ForgeTestBridge:RegisterFrame("RaidWishlistImportButton", importButton)
            ForgeTestBridge:RegisterFrame("RaidWishlistPrompt", Prompt)
            ForgeTestBridge:RegisterFrame("RaidWishlistRoll", rollButton)
            ForgeTestBridge:RegisterFrame("RaidWishlistWish1", wishRows[1])
            ForgeTestBridge:RegisterFrame("RaidWishlistRaid1", raidRows[1])
            ForgeTestBridge:RegisterFrame("RaidWishlistOpen1", openRows[1])
            ForgeTestBridge:RegisterFrame("RaidWishlistMinimap", MinimapButton)
        end
    elseif event == "CHAT_MSG_ADDON" then
        onAddonMessage(...)
    end
end)

-- Timers run on an always-shown frame (OnUpdate only fires for visible frames).
local ticker = CreateFrame("Frame")
local tickElapsed = 0
ticker:SetScript("OnUpdate", function(_, elapsed)
    tickElapsed = tickElapsed + elapsed
    if tickElapsed < 0.2 then return end
    tickElapsed = 0
    local now = GetTime()
    if pendingRoll and now >= pendingRoll.at then
        local roll = pendingRoll
        pendingRoll = nil
        doRoll(roll.entry, roll.key)
    end
    if prompt then
        local left = prompt.endsAt - now
        if left <= 0 then hidePrompt() else promptTimer:SetText(math.ceil(left) .. "s") end
    end
    if syncAt and now >= syncAt then
        syncAt = nil
        requestSync()
        shareWishlist()
    end
    if shareAt and now >= shareAt then
        shareAt = nil
        shareWishlist()
    end
end)

local HELP = {
    L["/wish - show or hide your wishlist"],
    L["/wish import - paste the wishlist export from the guild website"],
    L["/wish auto on|off - roll automatically on wishlisted items (e.g. while away)"],
    L["/wish sync - ask the raid lead's ledger for this raid's awards"],
    L["/wish minimap on|off - show or hide the minimap button"],
    L["/wish share on|off - show your wishlist to the raid lead's ledger (on by default)"],
}

SLASH_RAIDWISHLIST1 = "/wish"
SLASH_RAIDWISHLIST2 = "/raidwish"
SlashCmdList["RAIDWISHLIST"] = function(message)
    local command, rest = trim(message):match("^(%S*)%s*(.-)$")
    command, rest = string.lower(command or ""), string.lower(rest or "")
    if command == "" or command == "toggle" then
        toggleWindow()
    elseif command == "import" then
        showImport(true)
    elseif command == "auto" and (rest == "on" or rest == "off") then
        setAuto(rest == "on")
    elseif command == "share" and (rest == "on" or rest == "off") then
        local _, char = ensureDatabase()
        char.noShare = rest == "off" or nil
        say(rest == "on" and L["your wishlist is shared with the raid lead's ledger."]
            or L["your wishlist is no longer shared."])
        if rest == "on" then shareAt = GetTime() + 1 end
    elseif command == "minimap" and (rest == "on" or rest == "off") then
        setMinimapButton(rest == "on")
    elseif command == "sync" then
        if requestSync() then say(L["asked the raid lead's ledger for this raid's awards."]) else say(L["not in a group."]) end
    else
        for _, line in ipairs(HELP) do say(line) end
    end
end
