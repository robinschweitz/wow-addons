-- RaidLedger: raid roll and master-loot award ledger for WoW 3.3.5a / Lua 5.1.
-- Records who really received each item (master-loot handouts, confirmed by the
-- loot chat line), follows trades of items the master looter kept, allows manual
-- corrections and exports the ledger for the raid website (RS2;LOOT).
local addonName, ns = ...
local L = ns.L
local Ledger = CreateFrame("Frame", "RaidLedgerFrame", UIParent)
local MAX_HISTORY = 250
local MAX_ACTIVE = 10
local HISTORY_LINES = 4
-- Default roll and tie-break lengths; /ledger timer changes them (saved).
local ROLL_SECONDS = 30
local TIE_SECONDS = 15
local ROLL_LIMITS = { 10, 300 }
local TIE_LIMITS = { 5, 120 }
local TRADE_GRACE = 5   -- seconds a closed trade window may still report "Trade complete."
local EXPORT_FORMAT = "RS2"
-- Tokens are not counted in the item tally (matched in the item link's name).
local TOKEN_NAMES = { "Weiheabzeichen" }
-- "boe": a free roll for any character on a bind-on-equip item nobody wanted
-- for this character; it counts in no tally (the website's BOE method).
local SPEC_NAMES = { ms = L["main spec"], os = L["off spec"], boe = L["BoE"] }
-- Items nobody wants go to the disenchanter or the guild bank: they keep their
-- holder (who has the item) but count for nobody.
local NO_TALLY = { disenchanted = true, bank = true }

local active = {}
local selected          -- the selected entry table (not an index: inserts shift indices)
local editing           -- the history record whose recipient is being corrected
local lootSlots = {}    -- slot -> { entry = active entry, link = item link } of the open loot window
local drops = {}        -- source:slot:link -> entry, so reopening a corpse does not duplicate items
local windowKey, windowNpc
local windowCount = 0
local lastKill          -- { guid, npc } of the latest creature death, for chests
local trade             -- { partner, items, closedAt } of the open or just closed trade
local patterns = {}
local historyOffset = 0
local rollOffset = 0
local syncAt            -- when to ask the group for the shared ledger (after login)
local wishAskAt         -- when to ask the group's wishlist addons for their lists
local groupSize = 0
-- Members' wishlists, shared by RaidWishlist ("W" messages). Kept for this
-- session only; the ledger asks again after a login or /reload.
local wishlists = {}    -- lower(name) -> { name, at, items = { [itemID] = { spec, enhanced, rank } } }
local rows = {}

local function trim(value)
    return (value or ""):match("^%s*(.-)%s*$")
end

local function lower(value)
    return string.lower(value or "")
end

-- field strips characters that would break the export or the ledger display.
local function field(value)
    return (string.gsub(value or "", "[|;\r\n]", ""))
end

local function itemIDFromLink(link)
    if type(link) ~= "string" then return nil end
    return tonumber(string.match(link, "item:(%d+)"))
end

-- npcFromGUID reads the creature ID from a 3.3.5a GUID such as 0xF130003B6900182E.
local function npcFromGUID(guid)
    if type(guid) ~= "string" then return nil end
    local kind = string.sub(guid, 3, 5)
    if kind ~= "F13" and kind ~= "F15" then return nil end
    return tonumber(string.sub(guid, 9, 12), 16)
end

-- patternFromFormat turns a client format string (LOOT_ITEM, RANDOM_ROLL_RESULT)
-- into an anchored Lua pattern. Localized clients use positional specifiers
-- ("%1$s" on deDE); "%1" would otherwise become an invalid back-reference.
local function patternFromFormat(format)
    if type(format) ~= "string" or format == "" then return nil end
    format = format:gsub("%%%d+%$", "%%")
    format = format:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
    format = format:gsub("%%s", "(.-)")
    format = format:gsub("%%d", "(%%d+)")
    return "^" .. format .. "$"
end

local function playerName()
    return UnitName("player") or ""
end

local function isPlayer(name)
    return lower(name) == lower(playerName())
end

local function say(text)
    DEFAULT_CHAT_FRAME:AddMessage("RaidLedger: " .. text)
end

-- announce goes to raid chat in a raid, party chat in a party, else local chat.
local function announce(text)
    if GetNumRaidMembers() and GetNumRaidMembers() > 0 then
        SendChatMessage(text, "RAID")
    elseif GetNumPartyMembers() and GetNumPartyMembers() > 0 then
        SendChatMessage(text, "PARTY")
    else
        DEFAULT_CHAT_FRAME:AddMessage("RaidLedger: " .. text)
    end
end

-- Loot rules (decided by the raid): /rnd 100 is main spec, /rnd 99 off spec.
-- An enhanced main-spec roll is 1+X..100+X with X = min(EP, 50) (the guild
-- website's rule), so any X from 1 to 50 counts (2-101 up to 51-150). Main spec
-- always beats off spec; within one spec the player with the fewest items this
-- raid wins, and the roll decides between equal tallies.
local function rollKind(low, high)
    if low == 1 and high == 100 then return "ms" end
    if low == 1 and high == 99 then return "os" end
    if high == low + 99 and low >= 2 and low <= 51 then return "ms" end
end

-- isBindOnEquip reads the item's tooltip (3.3.5a has no bind type in
-- GetItemInfo). Cached per item; an item the client has not seen yet reads as
-- not BoE.
local scanTip = CreateFrame("GameTooltip", "RaidLedgerScanTip", nil, "GameTooltipTemplate")
local bindOnEquip = {}
local function isBindOnEquip(link)
    local id = tonumber(string.match(link or "", "item:(%d+)"))
    if not id or not ITEM_BIND_ON_EQUIP then return false end
    if bindOnEquip[id] == nil then
        scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
        scanTip:SetHyperlink("item:" .. id)
        local found = false
        for i = 2, math.min(scanTip:NumLines(), 6) do
            local line = _G["RaidLedgerScanTipTextLeft" .. i]
            if line and line:GetText() == ITEM_BIND_ON_EQUIP then found = true end
        end
        local seen = scanTip:NumLines() > 0
        scanTip:Hide()
        if not seen then return false end   -- not cached yet: ask again later
        bindOnEquip[id] = found
    end
    return bindOnEquip[id]
end

local function isToken(link)
    for _, name in ipairs(TOKEN_NAMES) do
        if string.find(link or "", name, 1, true) then return true end
    end
    return false
end

-- rollLabel describes a counted roll: "MS", "MS 21-120" (with points) or "OS".
local function rollLabel(r)
    if r.kind == "os" then return "OS" end
    if r.kind == "boe" then return "BoE" end
    if r.low and r.low > 1 then return "MS " .. r.low .. "-" .. r.high end
    return "MS"
end

local function itemCount(n, token)
    if token then return n == 1 and L["1 token"] or string.format(L["%d tokens"], n) end
    return n == 1 and L["1 item"] or string.format(L["%d items"], n)
end

-- ranksAbove orders counted rolls: main spec first, then the fewest items, then
-- the highest roll.
local function ranksAbove(a, b)
    if a.kind ~= b.kind then return a.kind == "ms" end
    if (a.tally or 0) ~= (b.tally or 0) then return (a.tally or 0) < (b.tally or 0) end
    return a.value > b.value
end

local function ensureDatabase()
    RaidLedgerDB = RaidLedgerDB or {}
    local db = RaidLedgerDB
    db.history = db.history or {}
    db.nextID = db.nextID or 0
    -- Records from version 1.0 have no stable ID yet; number them oldest first.
    for i = table.getn(db.history), 1, -1 do
        local record = db.history[i]
        if not record.id then
            db.nextID = db.nextID + 1
            record.id = db.nextID
            record.itemID = record.itemID or itemIDFromLink(record.item)
            record.state = record.state or "manual"
            record.confirmed = true
        end
    end
    return db
end

local function rollSeconds() return ensureDatabase().rollSeconds or ROLL_SECONDS end
local function tieSeconds() return ensureDatabase().tieSeconds or TIE_SECONDS end

-- reminders: the seconds left at which a roll of this length is announced
-- again - half and a quarter of its time, rounded to whole seconds.
local function reminders(seconds)
    return { math.floor(seconds / 2 + 0.5), math.floor(seconds / 4 + 0.5) }
end

local function findRecord(id)
    for _, record in ipairs(ensureDatabase().history) do
        if record.id == id then return record end
    end
end

-- tallies counts this raid's awards per player and spec ({ ms = n, os = n }),
-- keyed by lower-case name. Items and tokens (Weiheabzeichen) are separate
-- lists: tallies() counts items, tallies(true) tokens. Removed awards and
-- awards without a spec (handed out without a roll) do not count; a held item
-- counts for its winner.
local function tallies(tokens)
    local counts = {}
    for _, r in ipairs(ensureDatabase().history) do
        if (r.spec == "ms" or r.spec == "os") and r.state ~= "deleted" and not NO_TALLY[r.state]
            and (r.token and true or false) == (tokens and true or false) then
            local key = lower((r.state == "held" and r.winner) or r.recipient)
            counts[key] = counts[key] or { ms = 0, os = 0 }
            counts[key][r.spec] = counts[key][r.spec] + 1
        end
    end
    return counts
end

-- isOpenAward: an item handed out only to be held until it is rolled - parked
-- with a raider (unique items) or kept by the master looter without a roll.
local function isOpenAward(r)
    return r.state == "parked" or (r.state == "held" and not r.winner and not r.spec)
end

local function tallyOf(counts, name, kind)
    local entry = counts[lower(name)]
    return entry and entry[kind] or 0
end

-- applyWishlist reads "W;<exported at>;<part>;<parts>;<itemID>:<m|o>:<0|1>:<rank>,...".
-- Part 1 starts a fresh copy of the sender's list.
local function applyWishlist(f, sender)
    local at, part, parts = tonumber(f[2]) or 0, tonumber(f[3]), tonumber(f[4])
    if not part or not parts or part < 1 or part > parts or parts > 20 then return false end
    local key = lower(sender)
    local list = wishlists[key]
    if part == 1 or not list or list.at ~= at then
        list = { name = sender, at = at, items = {} }
        wishlists[key] = list
    end
    for itemID, spec, enhanced, rank in string.gmatch(f[5] or "", "(%d+):([mo]):([01]):(%d+)") do
        list.items[tonumber(itemID)] = { spec = spec == "o" and "os" or "ms", enhanced = enhanced == "1", rank = tonumber(rank) }
    end
    return true
end

-- wishersOf lists who wished for an item: main spec first, then by rank.
local function wishersOf(itemID)
    local list = {}
    if not itemID then return list end
    for _, wishlist in pairs(wishlists) do
        local wish = wishlist.items[itemID]
        if wish then
            table.insert(list, { name = wishlist.name, spec = wish.spec, enhanced = wish.enhanced, rank = wish.rank })
        end
    end
    table.sort(list, function(a, b)
        if a.spec ~= b.spec then return a.spec == "ms" end
        if a.rank ~= b.rank then return a.rank < b.rank end
        return a.name < b.name
    end)
    return list
end

local function wishOf(name, itemID)
    local wishlist = wishlists[lower(name or "")]
    return wishlist and itemID and wishlist.items[itemID]
end

local function knowsWishlists()
    return next(wishlists) ~= nil
end

local function summaryLine(name)
    local items, tokens = tallies(), tallies(true)
    return string.format(L["%s this raid: items %d MS / %d OS, tokens %d MS / %d OS"], name,
        tallyOf(items, name, "ms"), tallyOf(items, name, "os"), tallyOf(tokens, name, "ms"), tallyOf(tokens, name, "os"))
end

-- announceAward tells the raid who got an item, so nobody has to ask.
local function announceAward(record, how)
    if record.state == "parked" then
        announce(string.format(L["[Loot] %s is parked with %s until it is rolled."], record.item, record.recipient))
        return
    elseif record.state == "disenchanted" then
        announce(string.format(L["[Loot] %s will be disenchanted (%s)."], record.item, record.recipient))
        return
    elseif record.state == "bank" then
        announce(string.format(L["[Loot] %s goes to the guild bank (%s)."], record.item, record.recipient))
        return
    end
    local spec = record.spec and (" - " .. SPEC_NAMES[record.spec]) or ""
    announce(string.format(L["[Loot] %s goes to %s%s%s."], record.item, record.recipient, spec,
        how and (" (" .. how .. ")") or ""))
end

local function isActive(entry)
    for _, candidate in ipairs(active) do
        if candidate == entry then return true end
    end
    return false
end

-- sortedRollLog copies an entry's roll log for the ledger: by round (1 = the
-- roll, 2+ = tie-breaks), counted rolls in winning order (main spec, fewest
-- items, highest roll), then ignored rolls in the order they came in.
local function sortedRollLog(entry)
    if not entry.rollLog then return {} end
    local counts = tallies(isToken(entry.item))
    local log = {}
    for index, r in ipairs(entry.rollLog) do
        local copy = { name = r.name, value = r.value, round = r.round, note = r.note, order = index,
            kind = r.kind, low = r.low, high = r.high, was = r.was }
        if r.kind and not r.note then copy.tally = tallyOf(counts, r.name, r.kind) end
        table.insert(log, copy)
    end
    table.sort(log, function(a, b)
        if a.round ~= b.round then return a.round < b.round end
        if (a.note == nil) ~= (b.note == nil) then return a.note == nil end
        if a.note == nil and (a.kind ~= b.kind or a.tally ~= b.tally or a.value ~= b.value) then
            return ranksAbove(a, b)
        end
        return a.order < b.order
    end)
    for _, r in ipairs(log) do r.order = nil end
    return log
end

---------------------------------------------------------------------------
-- Shared ledger: every award change goes to the other addon users in the
-- group, so officers see the same list and a crashed master looter can get
-- the ledger back (/ledger sync).
---------------------------------------------------------------------------
local SYNC_PREFIX = "FLLedger"
local outbox = {}
local NOTE_CODES = { ["re-roll"] = "r", ["not in tie-break"] = "t", passed = "p", ["not counted"] = "n" }

local function groupChannel()
    if GetNumRaidMembers() and GetNumRaidMembers() > 0 then return "RAID" end
    if GetNumPartyMembers() and GetNumPartyMembers() > 0 then return "PARTY" end
end

local function queue(message)
    if groupChannel() then table.insert(outbox, message) end
end

local function currentSession()
    local db = ensureDatabase()
    db.session = db.session or (field(playerName()) .. "-" .. time())
    return db.session
end

local rollCount = 0

-- shareRollStart tells wishlist addons that a roll (or a tie-break among
-- `tied`) is open for an item: "S;session;origin;rollKey;itemID;seconds;round;
-- tied,names". It jumps the queue, so award backlogs cannot delay it.
local function shareRollStart(entry, seconds, tied)
    if not groupChannel() then return end
    if not entry.rollKey then
        rollCount = rollCount + 1
        entry.rollKey = field(playerName()) .. "-" .. time() .. "-" .. rollCount
    end
    local itemID = string.match(entry.item or "", "item:(%d+)")
    table.insert(outbox, 1, table.concat({ "S", currentSession(), field(playerName()), entry.rollKey,
        itemID or "", seconds, entry.round or 1, tied and table.concat(tied, ",") or "" }, ";"))
end

-- currentSession names this raid's ledger; it changes with every new raid.
local function encodeRecord(r)
    return table.concat({ "A", currentSession(), field(r.origin or playerName()), r.id, r.rev or 1, r.at or 0,
        r.itemID or "", r.npc or "", field(r.recipient), r.state or "manual", r.confirmed and 1 or 0,
        r.spec or "", r.roll or "", r.low or "", r.high or "", field(r.winner or ""), r.rolls or 0,
        r.token and 1 or "", r.time or "" }, ";")
end

-- encodeLog splits a roll log into messages of at most ~200 characters.
local function encodeLog(r)
    local entries = {}
    for _, e in ipairs(r.rollLog or {}) do
        local code = e.note and (NOTE_CODES[e.note] or "x") or ""
        table.insert(entries, table.concat({ field(e.name), e.value, e.low or 1, e.high or 100, e.round or 1,
            code, e.tally or "" }, ","))
    end
    local parts, current = {}, {}
    local length = 0
    for _, entry in ipairs(entries) do
        if length + string.len(entry) > 160 and table.getn(current) > 0 then
            table.insert(parts, current)
            current, length = {}, 0
        end
        table.insert(current, entry)
        length = length + string.len(entry) + 1
    end
    if table.getn(current) > 0 then table.insert(parts, current) end
    local messages = {}
    for index, part in ipairs(parts) do
        table.insert(messages, table.concat({ "L", currentSession(), field(r.origin or playerName()), r.id,
            index, table.getn(parts), table.concat(part, "/") }, ";"))
    end
    return messages
end

-- publish sends a changed award (with its roll log when withLog is set).
local function publish(record, withLog)
    record.origin = record.origin or playerName()
    record.rev = (record.rev or 0) + 1
    queue(encodeRecord(record))
    if withLog then
        for _, message in ipairs(encodeLog(record)) do queue(message) end
    end
end

local function findRoll(entry, name)
    for _, r in ipairs(entry.rolls or {}) do
        if lower(r.name) == lower(name) then return r end
    end
end

-- recordAward stores an award and removes the item from the active list.
-- Items the recorder gives to himself are "held" until a trade or a correction.
-- The award's spec comes from the recipient's roll, or for a held item from
-- the roll winner's (the master looter passes it on later).
local function recordAward(entry, recipient, state, confirmed)
    local db = ensureDatabase()
    local winner = entry.winner and entry.winner.name
    local roll = findRoll(entry, recipient)
    if not roll and isPlayer(recipient) and winner then roll = findRoll(entry, winner) end
    local log = sortedRollLog(entry)   -- before this award changes the tallies
    db.nextID = db.nextID + 1
    local record = {
        id = db.nextID,
        item = entry.item or L["Unknown item"],
        itemID = itemIDFromLink(entry.item),
        npc = entry.npc,
        recipient = field(recipient),
        state = ((state == "parked" or NO_TALLY[state]) and state) or (isPlayer(recipient) and "held") or state,
        confirmed = confirmed and true or false,
        rolls = table.getn(entry.rolls or {}),
        roll = roll and roll.value,
        spec = roll and roll.kind,
        low = roll and roll.low,
        high = roll and roll.high,
        winner = winner,
        token = isToken(entry.item) or nil,
        rollLog = log,
        time = date("%H:%M"),
        at = time(),
    }
    table.insert(db.history, 1, record)
    db.startedAt = db.startedAt or record.at
    while table.getn(db.history) > MAX_HISTORY do
        table.remove(db.history)
    end
    if NO_TALLY[record.state] then record.roll, record.spec, record.low, record.high, record.winner = nil, nil, nil, nil, nil end
    entry.record = record
    publish(record, true)
    for index = table.getn(active), 1, -1 do
        if active[index] == entry then table.remove(active, index) end
    end
    if selected == entry then selected = nil end
    historyOffset = 0
    return record
end

-- buildExport renders "RS2;LOOT;<raidID>;<recorder>;<startedAt>;<exportedAt>"
-- followed by "<id>;<awardedAt>;<npcID or ->;<itemID or ->;<recipient>;<state>;
-- <roll or ->;<ms|os|->;<low-high or ->;<roll winner or ->" per award, oldest
-- first. The winner tells the website who a held item goes to. The range shows
-- enhanced rolls (e.g. 21-120), whose points the website deducts. IDs never change, so the website can update lines it
-- already imported; removed awards stay in the export as "deleted" tombstones.
-- The separator is ";" because "|" starts escape sequences ("|T", "|c") in a
-- WoW EditBox, and character names cannot contain ";".
local function buildExport(raidID, recorder, startedAt, exportedAt, history)
    local lines = { table.concat({ EXPORT_FORMAT, "LOOT", tostring(raidID), field(recorder),
        tostring(startedAt or exportedAt), tostring(exportedAt) }, ";") }
    for i = table.getn(history), 1, -1 do
        local r = history[i]
        lines[table.getn(lines) + 1] = table.concat({ tostring(r.id), tostring(r.at or 0),
            r.npc and tostring(r.npc) or "-", r.itemID and tostring(r.itemID) or "-",
            field(r.recipient), r.state or "manual", r.roll and tostring(r.roll) or "-",
            r.spec or "-", r.low and (r.low .. "-" .. r.high) or "-",
            r.winner and field(r.winner) ~= "" and field(r.winner) or "-" }, ";")
    end
    return table.concat(lines, "\n")
end

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

local function label(parent, template, size, color)
    local text = parent:CreateFontString(nil, "OVERLAY", template)
    if size then text:SetFont(STANDARD_TEXT_FONT, size) end
    if color then text:SetTextColor(color[1], color[2], color[3]) end
    return text
end

local function flatButton(parent, caption, width)
    local button = CreateFrame("Button", nil, parent)
    button:SetWidth(width)
    button:SetHeight(24)
    makeBackdrop(button, 0.08, 0.25, 0.34, 0.98)
    local text = label(button, "GameFontNormal", 10, {0.70, 0.93, 1.00})
    text:SetPoint("CENTER", button, "CENTER", 0, 0)
    button:SetFontString(text)
    button:SetText(caption)
    return button
end

Ledger:SetWidth(600)
Ledger:SetHeight(410)
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
title:SetPoint("TOPLEFT", Ledger, "TOPLEFT", 18, -18)
title:SetText("RaidLedger")   -- the addon's name, not translated

local close = CreateFrame("Button", nil, Ledger)
close:SetWidth(24)
close:SetHeight(24)
close:SetPoint("TOPRIGHT", Ledger, "TOPRIGHT", -13, -14)
makeBackdrop(close, 0.10, 0.16, 0.21, 0.95)
local closeText = label(close, "GameFontNormal", 14, {0.72, 0.84, 0.90})
closeText:SetPoint("CENTER", close, "CENTER", 0, 0)
closeText:SetText("X")
close:SetScript("OnClick", function() Ledger:Hide() end)

local exportButton = flatButton(Ledger, L["EXPORT"], 70)
exportButton:SetPoint("RIGHT", close, "LEFT", -8, 0)

local rollPane = CreateFrame("Frame", "RaidLedgerRollPane", Ledger)
rollPane:SetPoint("TOPLEFT", Ledger, "TOPLEFT", 16, -48)
rollPane:SetWidth(336)
rollPane:SetHeight(228)
makeBackdrop(rollPane, 0.035, 0.070, 0.105, 0.97)
rollPane:EnableMouseWheel(true)

local rollHeading = label(rollPane, "GameFontNormal", 11, {1.00, 0.80, 0.32})
rollHeading:SetPoint("TOPLEFT", rollPane, "TOPLEFT", 12, -11)
rollHeading:SetText(L["MASTER LOOT ITEMS"])

local EMPTY_ACTIVE = L["Open the master loot window\nPlayers can then use /rnd"]
local emptyRolls = label(rollPane, "GameFontNormalSmall", 11, {0.42, 0.61, 0.70})
emptyRolls:SetPoint("CENTER", rollPane, "CENTER", 0, 10)
emptyRolls:SetText(EMPTY_ACTIVE)
emptyRolls:SetJustifyH("CENTER")

local detailPane = CreateFrame("Frame", nil, Ledger)
detailPane:SetPoint("TOPLEFT", rollPane, "TOPRIGHT", 12, 0)
detailPane:SetWidth(220)
detailPane:SetHeight(228)
makeBackdrop(detailPane, 0.035, 0.070, 0.105, 0.97)

local detailHeading = label(detailPane, "GameFontNormal", 11, {1.00, 0.80, 0.32})
detailHeading:SetPoint("TOPLEFT", detailPane, "TOPLEFT", 12, -11)
detailHeading:SetText(L["AWARD SELECTED LOOT"])

local itemDetail = label(detailPane, "GameFontHighlight", 12, {0.94, 0.97, 1.00})
itemDetail:SetPoint("TOPLEFT", detailPane, "TOPLEFT", 12, -34)
itemDetail:SetPoint("TOPRIGHT", detailPane, "TOPRIGHT", -12, -34)
itemDetail:SetHeight(26)
itemDetail:SetJustifyH("LEFT")
itemDetail:SetJustifyV("TOP")
itemDetail:SetText(L["Select an active roll"])

local rollDetail = label(detailPane, "GameFontNormalSmall", 10, {0.45, 0.68, 0.80})
rollDetail:SetPoint("TOPLEFT", itemDetail, "BOTTOMLEFT", 0, -6)
rollDetail:SetPoint("TOPRIGHT", itemDetail, "BOTTOMRIGHT", 0, -6)
rollDetail:SetJustifyH("LEFT")
rollDetail:SetWordWrap(false)
rollDetail:SetText(L["No player rolls recorded"])

local recipientBox = CreateFrame("EditBox", "RaidLedgerRecipient", detailPane, "InputBoxTemplate")
recipientBox:SetPoint("TOPLEFT", detailPane, "TOPLEFT", 14, -100)
recipientBox:SetWidth(198)
recipientBox:SetHeight(24)
recipientBox:SetAutoFocus(false)
recipientBox:SetMaxLetters(24)
recipientBox:SetTextInsets(5, 5, 0, 0)

local recipientHint = label(detailPane, "GameFontNormalSmall", 9, {0.45, 0.60, 0.68})
recipientHint:SetPoint("BOTTOMLEFT", recipientBox, "TOPLEFT", 1, 2)
recipientHint:SetText(L["RECIPIENT NAME"])

local award = CreateFrame("Button", nil, detailPane)
award:SetPoint("TOPLEFT", recipientBox, "BOTTOMLEFT", -2, -10)
award:SetWidth(136)
award:SetHeight(26)
makeBackdrop(award, 0.08, 0.25, 0.34, 0.98)
local awardText = label(award, "GameFontNormal", 10, {0.70, 0.93, 1.00})
awardText:SetPoint("CENTER", award, "CENTER", 0, 0)
awardText:SetText(L["RECORD AWARD"])

-- PARK hands an item to a raider (or keeps it) to hold until it is rolled;
-- on an open award it reads ROLL and starts that roll.
local park = CreateFrame("Button", "RaidLedgerPark", detailPane)
park:SetPoint("LEFT", award, "RIGHT", 6, 0)
park:SetWidth(54)
park:SetHeight(26)
makeBackdrop(park, 0.20, 0.12, 0.30, 0.98)
local parkText = label(park, "GameFontNormal", 10, {0.92, 0.80, 1.00})
parkText:SetPoint("CENTER", park, "CENTER", 0, 0)
parkText:SetText(L["PARK"])

local function stateButton(name, caption)
    local button = CreateFrame("Button", name, detailPane)
    button:SetHeight(16)
    makeBackdrop(button, 0.16, 0.12, 0.24, 0.98)
    local text = label(button, "GameFontNormalSmall", 9, {0.90, 0.82, 1.00})
    text:SetPoint("CENTER", button, "CENTER", 0, 0)
    button:SetFontString(text)
    button:SetText(caption)
    return button
end
local bankButton = stateButton("RaidLedgerBank", L["BANK"])
bankButton:SetWidth(44)
bankButton:SetPoint("TOPRIGHT", award, "BOTTOMLEFT", 196, -5)
local disenchantButton = stateButton("RaidLedgerDisenchant", L["DE"])
disenchantButton:SetWidth(30)
disenchantButton:SetPoint("RIGHT", bankButton, "LEFT", -4, 0)

-- ALLE opens every raid member by group; the four buttons beside it show the
-- selected item's valid rollers (winner first), then the roster.
-- The main chunk is near Lua's 200-local limit: these live in one table.
local roster = {}
roster.all = stateButton("RaidLedgerAllMembers", "")
roster.all:SetWidth(74)
roster.all:SetPoint("TOPLEFT", award, "BOTTOMLEFT", 0, -5)
makeBackdrop(roster.all, 0.06, 0.16, 0.22, 0.98)
roster.all:GetFontString():SetTextColor(0.70, 0.93, 1.00)

-- memberButton: a name (class colored) and, for a roller, the roll on the right.
function roster.button(parent, name, width)
    local button = CreateFrame("Button", name, parent)
    button:SetWidth(width)
    button:SetHeight(18)
    makeBackdrop(button, 0.045, 0.09, 0.13, 0.98)
    -- 3.3.5a Buttons have no SetTextColor; color the button's own FontString.
    local text = label(button, "GameFontNormalSmall", nil, {0.58, 0.79, 0.88})
    text:SetPoint("LEFT", button, "LEFT", 6, 0)
    text:SetPoint("RIGHT", button, "RIGHT", -6, 0)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    button:SetFontString(text)
    button.roll = label(button, "GameFontNormalSmall", 9, {1.00, 0.80, 0.32})
    button.roll:SetPoint("RIGHT", button, "RIGHT", -5, 0)
    button.roll:SetJustifyH("RIGHT")
    button:SetScript("OnClick", function(self) recipientBox:SetText(self.fullName or "") end)
    return button
end

-- showMember puts a member (or nobody) on a button; a roller's roll on the right.
function roster.show(button, member, roll)
    button.fullName, button.rollRef = member and member.name, member and roll
    if not member then button:Hide() return end
    button:SetText(member.name)
    local color = member.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[member.class]
    if color then
        button:GetFontString():SetTextColor(color.r, color.g, color.b)
    else
        button:GetFontString():SetTextColor(0.58, 0.79, 0.88)
    end
    button.roll:SetText(roll and tostring(roll.value) or "")
    button:GetFontString():SetPoint("RIGHT", button, "RIGHT", roll and -26 or -6, 0)
    if roll then
        button:SetBackdropColor(0.09, 0.17, 0.24, 0.98)
    else
        button:SetBackdropColor(0.045, 0.09, 0.13, 0.98)
    end
    button:Show()
end

local rosterButtons = {}
for i = 1, 4 do
    local button = roster.button(detailPane, "RaidLedgerMember" .. i, 96)
    button:SetPoint("TOPLEFT", roster.all, "BOTTOMLEFT", ((i - 1) % 2) * 100, -4 - math.floor((i - 1) / 2) * 21)
    rosterButtons[i] = button
end

-- The whole raid, one column per raid group: opens under the member buttons,
-- over the recent awards, so ALLE stays visible to close it again.
roster.pane = CreateFrame("Frame", "RaidLedgerMembers", Ledger)
roster.pane:SetHeight(125)
roster.pane:SetPoint("TOPLEFT", rollPane, "BOTTOMLEFT", 0, -4)
roster.pane:SetPoint("TOPRIGHT", detailPane, "BOTTOMRIGHT", 0, -4)
roster.pane:SetFrameLevel(Ledger:GetFrameLevel() + 20)
makeBackdrop(roster.pane, 0.025, 0.052, 0.078, 0.99)
roster.pane:EnableMouse(true)
roster.pane:Hide()
roster.headings, roster.groups = {}, {}
for g = 1, 5 do
    local x = 11 + (g - 1) * (106 + 4)
    local heading = label(roster.pane, "GameFontNormalSmall", 9, {1.00, 0.80, 0.32})
    heading:SetPoint("TOPLEFT", roster.pane, "TOPLEFT", x + 2, -8)
    heading:SetText(string.format(L["GROUP %d"], g))
    roster.headings[g] = heading
    roster.groups[g] = {}
    for row = 1, 5 do
        local button = roster.button(roster.pane, nil, 106)
        button:SetPoint("TOPLEFT", roster.pane, "TOPLEFT", x, -21 - (row - 1) * 20)
        button:HookScript("OnClick", function() roster.pane:Hide() end)
        roster.groups[g][row] = button
    end
end
roster.all:SetScript("OnClick", function()
    if roster.pane:IsShown() then roster.pane:Hide() else roster.pane:Show() end
end)
Ledger:HookScript("OnHide", function() roster.pane:Hide() end)

-- Right-click on a roll in the roll list: the master looter takes a pass or
-- changes how the roll counts (rules of 2026-10-17). A free BoE roll takes
-- passes only.
roster.menu = CreateFrame("Frame", "RaidLedgerRollMenu", Ledger)
roster.menu:SetWidth(132)
roster.menu:SetFrameLevel(Ledger:GetFrameLevel() + 30)
makeBackdrop(roster.menu, 0.035, 0.070, 0.105, 0.99)
roster.menu:EnableMouse(true)
roster.menu:Hide()
roster.menu.title = label(roster.menu, "GameFontNormalSmall", 10, {0.94, 0.97, 1.00})
roster.menu.title:SetPoint("TOPLEFT", roster.menu, "TOPLEFT", 10, -8)
roster.menu.title:SetPoint("TOPRIGHT", roster.menu, "TOPRIGHT", -10, -8)
roster.menu.title:SetJustifyH("LEFT")
roster.menu.title:SetWordWrap(false)
roster.menu.options = {}
for _, option in ipairs({ { "Pass", L["PASS"], "pass" }, { "MS", L["MAIN SPEC"], "ms" },
        { "Enhanced", L["ENHANCED..."], "enh" }, { "OS", L["OFF SPEC"], "os" },
        { "None", L["DOES NOT COUNT"], "none" } }) do
    local button = CreateFrame("Button", "RaidLedgerRollMenu" .. option[1], roster.menu)
    button:SetWidth(112)
    button:SetHeight(18)
    if option[3] == "pass" then makeBackdrop(button, 0.20, 0.12, 0.30, 0.98)
    else makeBackdrop(button, 0.06, 0.16, 0.22, 0.98) end
    local text = label(button, "GameFontNormalSmall", 9, option[3] == "pass" and {0.92, 0.80, 1.00} or {0.70, 0.93, 1.00})
    text:SetPoint("CENTER", button, "CENTER", 0, 0)
    button:SetFontString(text)
    button:SetText(option[2])
    button.how = option[3]
    button:SetScript("OnClick", function(self)
        local name = roster.menu.name
        roster.menu:Hide()
        if self.how == "enh" then roster.askPoints(name) else roster.apply(name, self.how) end
    end)
    table.insert(roster.menu.options, button)
end

function roster.openMenu(button)
    local menu = roster.menu
    if menu:IsShown() and menu.name == button.fullName then menu:Hide() return end
    menu.name = button.fullName
    menu.title:SetText(string.format("%s (%d)", button.fullName, button.rollRef.value))
    local free = button.rollRef.kind == "boe"
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
    -- Under the roll (right edge, by its value), or above it near the window's
    -- bottom: the menu stays inside the window.
    menu:ClearAllPoints()
    local bottom, ledgerBottom = button:GetBottom(), Ledger:GetBottom()
    if bottom and ledgerBottom and bottom - menu:GetHeight() - 2 < ledgerBottom + 8 then
        menu:SetPoint("BOTTOMRIGHT", button, "TOPRIGHT", 0, 2)
    else
        menu:SetPoint("TOPRIGHT", button, "BOTTOMRIGHT", 0, -2)
    end
    menu:Show()
end
Ledger:HookScript("OnHide", function() roster.menu:Hide() end)

local historyPane = CreateFrame("Frame", "RaidLedgerHistoryPane", Ledger)
historyPane:SetPoint("TOPLEFT", Ledger, "TOPLEFT", 16, -286)
historyPane:SetWidth(568)
historyPane:SetHeight(94)
makeBackdrop(historyPane, 0.025, 0.052, 0.078, 0.97)
historyPane:EnableMouseWheel(true)

local historyHeading = label(historyPane, "GameFontNormal", 11, {1.00, 0.80, 0.32})
historyHeading:SetPoint("TOPLEFT", historyPane, "TOPLEFT", 12, -10)
historyHeading:SetText(L["RECENT AWARDS"])

local clearButton = flatButton(historyPane, L["CLEAR"], 56)
clearButton:SetHeight(18)
clearButton:SetPoint("TOPRIGHT", historyPane, "TOPRIGHT", -8, -6)

local historySummary = label(historyPane, "GameFontNormalSmall", 9, {0.45, 0.60, 0.68})
historySummary:SetPoint("RIGHT", clearButton, "LEFT", -10, 0)
historySummary:SetJustifyH("RIGHT")

local stateLabels = { given = L["GIVEN"], held = L["HELD BY YOU"], manual = L["MANUAL"], deleted = L["REMOVED"],
    parked = L["OPEN"], disenchanted = L["DISENCHANT"], bank = L["GUILD BANK"] }
local stateColors = {
    given = {0.45, 0.85, 0.55}, held = {1.00, 0.82, 0.30},
    manual = {0.58, 0.79, 0.88}, deleted = {0.45, 0.45, 0.45}, parked = {0.85, 0.62, 1.00},
    disenchanted = {0.75, 0.55, 1.00}, bank = {0.95, 0.85, 0.45},
}

local historyLines = {}
for i = 1, HISTORY_LINES do
    local line = CreateFrame("Button", nil, historyPane)
    line:SetPoint("TOPLEFT", historyPane, "TOPLEFT", 8, -26 - (i - 1) * 15)
    line:SetPoint("TOPRIGHT", historyPane, "TOPRIGHT", -8, -26 - (i - 1) * 15)
    line:SetHeight(14)
    line:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground" })
    line:SetBackdropColor(0.10, 0.21, 0.29, 0)
    local text = label(line, "GameFontNormalSmall", 10, {0.72, 0.82, 0.88})
    text:SetPoint("LEFT", line, "LEFT", 5, 0)
    text:SetPoint("RIGHT", line, "RIGHT", -96, 0)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    line:SetFontString(text)
    line.state = label(line, "GameFontNormalSmall", 9)
    line.state:SetPoint("RIGHT", line, "RIGHT", -5, 0)
    line.state:SetJustifyH("RIGHT")
    historyLines[i] = line
end

local status = label(Ledger, "GameFontNormalSmall", 10, {0.42, 0.60, 0.68})
status:SetPoint("BOTTOMLEFT", Ledger, "BOTTOMLEFT", 18, 12)
status:SetPoint("BOTTOMRIGHT", Ledger, "BOTTOMRIGHT", -18, 12)
status:SetJustifyH("LEFT")
status:SetWordWrap(false)
status:SetText(L["CLICK AN AWARD FOR ITS ROLLS OR TO CHANGE ITS RECIPIENT  |  /ledger help"])

-- Export overlay: replaces the three panes while shown.
local exportPanel = CreateFrame("Frame", "RaidLedgerExportPanel", Ledger)
exportPanel:SetPoint("TOPLEFT", Ledger, "TOPLEFT", 16, -48)
exportPanel:SetWidth(568)
exportPanel:SetHeight(332)
makeBackdrop(exportPanel, 0.035, 0.070, 0.105, 0.97)
exportPanel:Hide()

local exportHeading = label(exportPanel, "GameFontNormal", 11, {1.00, 0.80, 0.32})
exportHeading:SetPoint("TOPLEFT", exportPanel, "TOPLEFT", 12, -11)
exportHeading:SetText(string.format(L["WEBSITE EXPORT  (%s LOOT)"], EXPORT_FORMAT))

local raidLabel = label(exportPanel, "GameFontNormalSmall", 9, {0.45, 0.60, 0.68})
raidLabel:SetPoint("TOPLEFT", exportPanel, "TOPLEFT", 12, -40)
raidLabel:SetText(L["RAID ID"])

local raidBox = CreateFrame("EditBox", nil, exportPanel, "InputBoxTemplate")
raidBox:SetPoint("LEFT", raidLabel, "RIGHT", 12, 0)
raidBox:SetWidth(80)
raidBox:SetHeight(24)
raidBox:SetAutoFocus(false)
raidBox:SetNumeric(true)
raidBox:SetMaxLetters(9)

local newRaidButton = flatButton(exportPanel, L["NEW RAID"], 90)
newRaidButton:SetPoint("TOPRIGHT", exportPanel, "TOPRIGHT", -12, -34)
local backButton = flatButton(exportPanel, L["BACK"], 70)
backButton:SetPoint("RIGHT", newRaidButton, "LEFT", -8, 0)

local exportBack = CreateFrame("Frame", nil, exportPanel)
exportBack:SetPoint("TOPLEFT", exportPanel, "TOPLEFT", 10, -66)
exportBack:SetPoint("BOTTOMRIGHT", exportPanel, "BOTTOMRIGHT", -10, 10)
makeBackdrop(exportBack, 0.01, 0.02, 0.03, 0.98)

local exportScroll = CreateFrame("ScrollFrame", nil, exportBack)
exportScroll:SetPoint("TOPLEFT", exportBack, "TOPLEFT", 8, -8)
exportScroll:SetPoint("BOTTOMRIGHT", exportBack, "BOTTOMRIGHT", -8, 8)
exportScroll:EnableMouseWheel(true)

local exportText = CreateFrame("EditBox", "RaidLedgerExportText", exportScroll)
exportText:SetMultiLine(true)
exportText:SetAutoFocus(false)
exportText:SetFontObject(ChatFontNormal)
exportText:SetWidth(532)
exportText:SetHeight(240)
exportScroll:SetScrollChild(exportText)
exportScroll:SetScript("OnMouseWheel", function(self, delta)
    local range = self:GetVerticalScrollRange() or 0
    local value = math.max(0, math.min(range, self:GetVerticalScroll() - delta * 28))
    self:SetVerticalScroll(value)
end)
exportText:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
exportText:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
-- Read-only: typing restores the generated text.
exportText:SetScript("OnTextChanged", function(self, userInput)
    if userInput then self:SetText(self.generated or "") self:HighlightText() end
end)

local function activeRollCount(entry)
    return table.getn(entry.rolls)
end

local function selectedEntry()
    if not selected then return nil end
    for _, entry in ipairs(active) do
        if entry == selected then return entry end
    end
    selected = nil
end

-- Rolls belong to the entry whose roll is running, not to whatever row the
-- master looter happens to have selected (new loot or clicks must not steal them).
local function rollingEntry()
    local latest
    for _, entry in ipairs(active) do
        if entry.endsAt and not entry.winner and (not latest or entry.startedAt > latest.startedAt) then
            latest = entry
        end
    end
    return latest
end

-- lootSlotOf returns the slot of `entry` in the open master-loot window, if any.
local function lootSlotOf(entry)
    if not entry then return nil end
    local method = GetLootMethod()
    if method ~= "master" then return nil end
    for slot, info in pairs(lootSlots) do
        if info.entry == entry and GetLootSlotLink(slot) == info.link then return slot end
    end
end

local function candidateIndex(name)
    for i = 1, 40 do
        local candidate = GetMasterLootCandidate(i)
        if candidate and lower(candidate) == lower(name) then return i end
    end
end

-- raidMembers lists the group: name, raid group and class token.
function roster.members()
    local members = {}
    local count = GetNumRaidMembers()
    if count and count > 0 then
        for i = 1, count do
            local name, _, group, _, _, class = GetRaidRosterInfo(i)
            if name then table.insert(members, { name = name, group = group or 1, class = class }) end
        end
        return members
    end
    for i = 0, GetNumPartyMembers() do
        local unit = i == 0 and "player" or ("party" .. i)
        local name = UnitName(unit)
        if name then table.insert(members, { name = name, group = 1, class = select(2, UnitClass(unit)) }) end
    end
    return members
end

-- rankedRollers: the counted rolls of the selected item (or of the award being
-- edited), best first, one per player.
function roster.rollers()
    local rolls = {}
    if editing then
        for _, r in ipairs(editing.rollLog or {}) do
            if r.kind and not r.note and r.value then table.insert(rolls, r) end
        end
        table.sort(rolls, ranksAbove)
    else
        local entry = selectedEntry()
        rolls = entry and entry.rolls or rolls
    end
    local ranked, seen = {}, {}
    for _, r in ipairs(rolls) do
        if r.name and not seen[string.lower(r.name)] then
            seen[string.lower(r.name)] = true
            table.insert(ranked, r)
        end
    end
    return ranked
end

local function updateRoster()
    local members = roster.members()
    local byName = {}
    for _, m in ipairs(members) do byName[string.lower(m.name)] = m end
    local shown, rollOf = {}, {}
    for _, r in ipairs(roster.rollers()) do
        rollOf[string.lower(r.name)] = r
        if table.getn(shown) < 4 then table.insert(shown, byName[string.lower(r.name)] or { name = r.name }) end
    end
    for _, m in ipairs(members) do
        if table.getn(shown) >= 4 then break end
        if not rollOf[string.lower(m.name)] then table.insert(shown, m) end
    end
    for i = 1, 4 do
        local m = shown[i]
        roster.show(rosterButtons[i], m, m and rollOf[string.lower(m.name)])
    end
    roster.all:SetText(string.format(L["ALL (%d)"], table.getn(members)))
    -- The popout: members in roster order within their raid group.
    local rows = { 0, 0, 0, 0, 0 }
    for g = 1, 5 do
        for row = 1, 5 do roster.groups[g][row]:Hide() end
    end
    for _, m in ipairs(members) do
        local g = math.min(math.max(tonumber(m.group) or 1, 1), 5)
        if rows[g] < 5 then
            rows[g] = rows[g] + 1
            roster.show(roster.groups[g][rows[g]], m, rollOf[string.lower(m.name)])
        end
    end
    for g = 1, 5 do
        if rows[g] > 0 then roster.headings[g]:Show() else roster.headings[g]:Hide() end
    end
end

local function updateHistory()
    local history = ensureDatabase().history
    local total, held = table.getn(history), 0
    for _, record in ipairs(history) do
        if record.state == "held" then held = held + 1 end
    end
    historyOffset = math.max(0, math.min(historyOffset, total - HISTORY_LINES))
    historyHeading:SetText(total > 0 and string.format(L["AWARDS (%d)"], total) or L["RECENT AWARDS"])
    historySummary:SetText(held > 0 and string.format(L["%d HELD BY YOU  |  SCROLL FOR MORE"], held)
        or (total > HISTORY_LINES and L["SCROLL FOR MORE"] or ""))
    for i = 1, HISTORY_LINES do
        local line = historyLines[i]
        local record = history[i + historyOffset]
        line.record = record
        if record then
            local text = string.format(L["#%d  %s  |  %s  ->  %s  (%d rolls)"], record.id, record.time or "",
                record.item, record.recipient, record.rolls or 0)
            if record.state == "deleted" then text = "|cff777777" .. string.gsub(text, "|c%x%x%x%x%x%x%x%x", "") .. "|r" end
            line:SetText(text)
            local stateText = stateLabels[record.state] or string.upper(record.state or "")
            if record.state == "held" and not isPlayer(record.recipient) then stateText = L["HELD"] end
            if isOpenAward(record) then stateText = L["OPEN"] end
            if string.sub(record.item or "", 1, 5) == "item:" then
                record.item = select(2, GetItemInfo(record.itemID or 0)) or record.item   -- now cached?
            end
            if not record.confirmed and record.state ~= "deleted" then stateText = stateText .. "?" end
            local color = isOpenAward(record) and stateColors.parked or stateColors[record.state] or stateColors.manual
            line.state:SetText(stateText)
            line.state:SetTextColor(color[1], color[2], color[3])
            line:SetBackdropColor(0.10, 0.21, 0.29, editing == record and 0.98 or 0)
            line:Show()
        else
            line:SetText(i == 1 and L["No awards recorded in this ledger."] or "")
            line.state:SetText("")
            line:SetBackdropColor(0.10, 0.21, 0.29, 0)
            if i == 1 then line:Show() else line:Hide() end
        end
    end
end

local function updateSelection()
    if editing then
        itemDetail:SetText(string.format("#%d %s", editing.id, editing.item))
        rollDetail:SetText(string.format(L["NOW: %s (%s)"], editing.recipient, stateLabels[editing.state] or editing.state or ""))
        awardText:SetText(editing.state == "deleted" and L["RESTORE + SET"] or L["CHANGE RECIPIENT"])
        parkText:SetText(isOpenAward(editing) and L["ROLL"] or L["PARK"])
        return
    end
    local entry = selectedEntry()
    awardText:SetText(lootSlotOf(entry) and L["GIVE + RECORD"] or L["RECORD AWARD"])
    parkText:SetText(L["PARK"])
    if entry then
        itemDetail:SetText(entry.item)
        if entry.winner then
            rollDetail:SetText(string.format(L["WINNER: %s (%d)"], entry.winner.name, entry.winner.value))
        elseif entry.endsAt then
            rollDetail:SetText(string.format(L["%d rolls  |  %ds remaining"], activeRollCount(entry), math.max(0, math.ceil(entry.endsAt - GetTime()))))
        else
            rollDetail:SetText(string.format(L["%d player rolls recorded"], activeRollCount(entry)))
        end
    else
        itemDetail:SetText(L["Select an active roll"])
        rollDetail:SetText(L["No player rolls recorded"])
    end
end

-- winningRoll is the top counted roll of the last round in a sorted roll log.
local function winningRoll(log)
    local best
    for _, r in ipairs(log) do
        if not r.note and (not best or r.round > best.round) then best = r end
    end
    return best
end

-- roster.lineText: a roll in the active roll list, "Name  MS 21-120".
function roster.lineText(r, won)
    local text = r.name
    if (r.round or 1) > 1 then text = text .. string.format(L["  (tie-break %d)"], r.round - 1) end
    if r.note then
        local reason = L[r.note] or r.note
        return "|cff777777" .. text .. string.format(L["  - ignored: %s"], reason) .. "|r"
    end
    if r.kind then text = text .. "  " .. rollLabel(r) end
    if r.was then text = text .. L["  (corrected)"] end
    if won then text = text .. L["  - won"] end
    return text
end

-- showRollLog fills the roll pane with the rolls of a recorded award.
local function showRollLog(record)
    local log = record.rollLog
    local count = log and table.getn(log) or 0
    rollOffset = math.max(0, math.min(rollOffset, count - MAX_ACTIVE))
    rollHeading:SetText(count > MAX_ACTIVE and string.format(L["ROLLS FOR AWARD #%d  (%d, SCROLL)"], record.id, count)
        or string.format(L["ROLLS FOR AWARD #%d"], record.id))
    local winner = log and winningRoll(log)
    for i = 1, MAX_ACTIVE do
        local row, r = rows[i], log and log[i + rollOffset]
        row.item = nil
        row.logName, row.fullName = r and r.name, r and r.name
        row.rollRef = r and r.kind and not r.note and r or nil
        if r then
            local text = r.name
            if r.round > 1 then text = text .. string.format(L["  (tie-break %d)"], r.round - 1) end
            if r.note then
                text = "|cff777777" .. text .. string.format(L["  - ignored: %s"], L[r.note]) .. "|r"
                row.count:SetTextColor(0.45, 0.45, 0.45)
            elseif r == winner then
                text = text .. L["  - won"]
                row.count:SetTextColor(0.45, 0.85, 0.55)
            else
                row.count:SetTextColor(1.00, 0.79, 0.31)
            end
            -- Spec and the tally the ranking used (logs from before 1.2 have neither).
            if r.kind and not r.note then
                text = text .. "  (" .. rollLabel(r) .. ", " .. itemCount(r.tally or 0, record.token) .. ")"
            end
            if r.was then text = text .. string.format(L["  - corrected, rolled %s"], r.was) end
            -- Rollers who listed the item show their wishlist rank.
            local wish = wishOf(r.name, record.itemID)
            if wish then text = text .. string.format(L["  [WL #%d]"], wish.rank) end
            row:SetText(text)
            row.wish:SetText("")
            row.count:SetText(tostring(r.value))
            row:SetBackdropColor(0.045, 0.09, 0.13, 0.98)
            row:Show()
        else
            row:Hide()
        end
    end
    if count == 0 then
        emptyRolls:SetText(log and L["Awarded without a /rnd roll"] or L["Rolls were not recorded\nfor this older award"])
        emptyRolls:Show()
    else
        emptyRolls:Hide()
    end
end

local function updateRows()
    if editing then
        showRollLog(editing)
        updateSelection()
        updateRoster()
        updateHistory()
        return
    end
    rollHeading:SetText(L["MASTER LOOT ITEMS"])
    emptyRolls:SetText(EMPTY_ACTIVE)
    -- Under the items: the selected item's rolls (left-click picks the
    -- recipient, right-click passes or recounts), scrolled by the mouse wheel.
    local current = selectedEntry()
    local log = current and sortedRollLog(current) or {}
    local items = math.min(table.getn(active), MAX_ACTIVE)
    local room = MAX_ACTIVE - items - 1
    local count = table.getn(log)
    if count == 0 or room < 1 then room = 0 end
    rollOffset = math.max(0, math.min(rollOffset, count - room))
    local winner = current and current.winner and winningRoll(log)
    local activeCount = 0
    for i = 1, MAX_ACTIVE do
        local entry = i <= items and active[i]
        local row = rows[i]
        row.logName, row.fullName, row.rollRef = nil, nil, nil
        row:GetFontString():SetTextColor(0.82, 0.91, 0.96)
        row:SetBackdropBorderColor(0.20, 0.63, 0.82, 0.92)
        if room > 0 and i == items + 1 then
            row.item = nil
            row:SetText(count > room and L["ROLLS (SCROLL)"] or L["ROLLS"])
            row:GetFontString():SetTextColor(1.00, 0.80, 0.32)
            row.count:SetText("")
            row.wish:SetText("")
            row:SetBackdropColor(0, 0, 0, 0)
            row:SetBackdropBorderColor(0, 0, 0, 0)
            row:Show()
        elseif room > 0 and i > items + 1 and log[i - items - 1 + rollOffset] then
            local r = log[i - items - 1 + rollOffset]
            row.item = nil
            row.logName, row.fullName = r.name, r.name
            if r.kind and not r.note then row.rollRef = r end
            row:SetText(roster.lineText(r, r == winner))
            row.count:SetText(tostring(r.value))
            if r.note then row.count:SetTextColor(0.45, 0.45, 0.45)
            elseif r == winner then row.count:SetTextColor(0.45, 0.85, 0.55)
            else row.count:SetTextColor(1.00, 0.79, 0.31) end
            row.wish:SetText("")
            row:SetBackdropColor(0.03, 0.06, 0.09, 0.98)
            row:Show()
        elseif entry then
            activeCount = activeCount + 1
            row.item = entry
            row.logName = nil
            row:SetText(string.format("%s", entry.item))
            row.count:SetText(string.format(L["%d ROLLS"], activeRollCount(entry)))
            row.count:SetTextColor(1.00, 0.79, 0.31)
            -- How many wishlists name this item; "WL 0" flags loot nobody listed.
            local wished = table.getn(wishersOf(itemIDFromLink(entry.item)))
            row.wish:SetText(knowsWishlists() and string.format(L["WL %d"], wished) or "")
            if wished > 0 then row.wish:SetTextColor(0.45, 0.85, 0.55) else row.wish:SetTextColor(0.50, 0.50, 0.50) end
            local isSelected = selected == entry
            row:SetBackdropColor(isSelected and 0.10 or 0.045, isSelected and 0.21 or 0.09, isSelected and 0.29 or 0.13, 0.98)
            row:Show()
        else
            row.item = nil
            row:Hide()
        end
    end
    if activeCount == 0 then emptyRolls:Show() else emptyRolls:Hide() end
    updateSelection()
    updateRoster()
    updateHistory()
end

for i = 1, MAX_ACTIVE do
    local row = CreateFrame("Button", "RaidLedgerRow" .. i, rollPane)
    row:SetPoint("TOPLEFT", rollPane, "TOPLEFT", 10, -29 - (i - 1) * 18)
    row:SetWidth(316)
    row:SetHeight(17)
    makeBackdrop(row, 0.045, 0.09, 0.13, 0.98)
    -- 3.3.5a Buttons have no SetTextColor/SetJustifyH/SetTextInsets: use a
    -- FontString anchored with the same 7px/50px insets.
    local rowText = label(row, "GameFontNormalSmall", nil, {0.82, 0.91, 0.96})
    rowText:SetPoint("LEFT", row, "LEFT", 7, 0)
    rowText:SetPoint("RIGHT", row, "RIGHT", -86, 0)
    rowText:SetJustifyH("LEFT")
    rowText:SetWordWrap(false)
    row:SetFontString(rowText)
    row.count = label(row, "GameFontNormalSmall", 9, {1.00, 0.79, 0.31})
    row.count:SetPoint("RIGHT", row, "RIGHT", -7, 0)
    row.wish = label(row, "GameFontNormalSmall", 9, {0.45, 0.85, 0.55})
    row.wish:SetPoint("RIGHT", row, "RIGHT", -52, 0)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", function(self, which)
        if which == "RightButton" then
            if self.rollRef then roster.openMenu(self) end
            return
        end
        if not self.item then   -- a roll line: its player becomes the recipient
            if self.fullName then recipientBox:SetText(self.fullName) end
            return
        end
        if selected ~= self.item then rollOffset = 0 end
        selected = self.item
        editing = nil
        recipientBox:SetText(selected and selected.winner and selected.winner.name or "")
        updateRows()
    end)
    rows[i] = row
end

for _, line in ipairs(historyLines) do
    line:SetScript("OnClick", function(self)
        if not self.record then return end
        editing = (editing ~= self.record) and self.record or nil
        selected = nil
        rollOffset = 0
        recipientBox:SetText(editing and editing.recipient or "")
        updateRows()
    end)
end

historyPane:SetScript("OnMouseWheel", function(_, delta)
    historyOffset = historyOffset - delta
    updateHistory()
end)

-- Tooltips: items show their real item tooltip; players show what they got
-- this raid, so fairness calls need no extra window.
local function showItemTooltip(owner, link)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    local itemString = type(link) == "string" and string.match(link, "item:[%-%d:]+")
    if itemString then GameTooltip:SetHyperlink(itemString) else GameTooltip:ClearLines() end
end

local function addPlayerLines(name)
    GameTooltip:AddLine(summaryLine(name), 0.45, 0.85, 1.00)
    for _, record in ipairs(ensureDatabase().history) do
        if record.state ~= "deleted" and lower(record.recipient) == lower(name) then
            GameTooltip:AddLine("  " .. record.item .. (record.spec and ("  " .. string.upper(record.spec)) or "")
                .. (record.token and L["  (token)"] or ""))
        end
    end
end

local function hideTooltip() GameTooltip:Hide() end

for _, row in ipairs(rows) do
    row:SetScript("OnEnter", function(self)
        if self.item then
            showItemTooltip(self, self.item.item)
            local wishers = wishersOf(itemIDFromLink(self.item.item))
            if table.getn(wishers) > 0 then
                GameTooltip:AddLine(string.format(L["On %d wishlists:"], table.getn(wishers)), 0.45, 0.85, 1.00)
                for _, wish in ipairs(wishers) do
                    GameTooltip:AddLine(string.format(L["  %s - %s, #%d%s"], wish.name, SPEC_NAMES[wish.spec], wish.rank,
                        wish.enhanced and L[", enhanced"] or ""), 0.8, 0.8, 0.8)
                end
            elseif knowsWishlists() then
                GameTooltip:AddLine(L["On nobody's wishlist."], 0.6, 0.6, 0.6)
            end
        elseif self.logName then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.logName)
            addPlayerLines(self.logName)
        else
            return
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", hideTooltip)
end

for _, line in ipairs(historyLines) do
    line:SetScript("OnEnter", function(self)
        local record = self.record
        if not record then return end
        showItemTooltip(self, record.item)
        GameTooltip:AddLine(string.format(L["Award #%d: %s (%s)"], record.id, record.recipient,
            stateLabels[record.state] or record.state or ""), 1, 1, 1)
        if record.roll then
            GameTooltip:AddLine(string.format(L["Roll %d, %s"], record.roll, record.spec and rollLabel({
                kind = record.spec, low = record.low, high = record.high }) or L["spec unknown"]), 0.8, 0.8, 0.8)
        end
        addPlayerLines(record.recipient)
        GameTooltip:Show()
    end)
    line:SetScript("OnLeave", hideTooltip)
end

for _, button in ipairs(rosterButtons) do
    button:SetScript("OnEnter", function(self)
        if not self.fullName then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.fullName)
        addPlayerLines(self.fullName)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", hideTooltip)
end

rollPane:SetScript("OnMouseWheel", function(_, delta)
    rollOffset = rollOffset - delta
    updateRows()
end)

-- The loot source identifies a corpse or chest across reopened loot windows:
-- the dead target's GUID, else the latest creature death (chests have no unit).
local function ensureWindowSource()
    if windowKey then return end
    windowCount = windowCount + 1
    local guid
    if UnitExists("target") and UnitIsDead("target") and not UnitIsPlayer("target") then guid = UnitGUID("target") end
    if guid then
        windowKey, windowNpc = guid, npcFromGUID(guid)
    elseif lastKill then
        windowKey, windowNpc = "kill:" .. lastKill.guid, lastKill.npc
    else
        windowKey, windowNpc = "window:" .. windowCount, nil
    end
end

local function addMasterLootItem(slot)
    local item = GetLootSlotLink(slot)
    if not item or item == "" then return end
    -- Only items at or above the group's loot threshold are worth a roll.
    local _, _, _, quality = GetLootSlotInfo(slot)
    local threshold = GetLootThreshold()
    if quality and threshold and quality < threshold then return end
    ensureWindowSource()
    -- Capture each source slot once, so an awarded item is not re-added by the
    -- periodic re-scan or by reopening the same corpse.
    local key = windowKey .. ":" .. slot .. ":" .. item
    local entry = drops[key]
    if entry then
        if not lootSlots[slot] then lootSlots[slot] = { entry = entry, link = item } end
        return
    end
    entry = { slot = slot, item = item, npc = windowNpc, rolls = {} }
    drops[key] = entry
    lootSlots[slot] = { entry = entry, link = item }
    table.insert(active, 1, entry)
    while table.getn(active) > MAX_ACTIVE do table.remove(active) end
    -- New loot needs attention: leave the roll log of an old award.
    if editing then
        editing = nil
        recipientBox:SetText("")
    end
    if not selectedEntry() then selected = entry end
    updateRows()
end

local function captureMasterLoot()
    local count = GetNumLootItems() or 0
    for slot = 1, count do addMasterLootItem(slot) end
end

-- onGiveMasterLoot runs after every master-loot handout, from this ledger or
-- from the default master-loot menu, and records the real recipient.
local parkSlots = {}     -- loot slot -> state ("parked", "disenchanted", "bank") of a special handout
local finishLaterRoll   -- defined with the award button

local function onGiveMasterLoot(slot, candidate)
    local name = GetMasterLootCandidate(candidate)
    local info = lootSlots[slot]
    local link = (info and info.link) or GetLootSlotLink(slot)
    if not name or not link then return end
    local mode = parkSlots[slot]
    parkSlots[slot] = nil
    local entry = info and info.entry or { item = link, npc = windowNpc, rolls = {} }
    local record = entry.record
    if record then
        -- Recorded by hand before the handout: the handout is the truth.
        record.recipient = field(name)
        record.state = mode or (isPlayer(name) and "held") or "given"
        if NO_TALLY[mode] then record.roll, record.spec, record.low, record.high, record.winner = nil, nil, nil, nil, nil end
        record.confirmed = false
        publish(record)
    else
        record = recordAward(entry, name, mode or "given", false)
    end
    status:SetText(string.format(L["Gave #%d to %s; waiting for the loot message."], record.id, name))
    updateRows()
end
hooksecurefunc("GiveMasterLoot", onGiveMasterLoot)

-- onLootMessage confirms a handout once the server's loot line arrives.
local function onLootMessage(message)
    patterns.lootOther = patterns.lootOther or patternFromFormat(LOOT_ITEM)
    patterns.lootSelf = patterns.lootSelf or patternFromFormat(LOOT_ITEM_SELF)
    local name, link
    if patterns.lootOther then name, link = string.match(message or "", patterns.lootOther) end
    if not name and patterns.lootSelf then
        link = string.match(message or "", patterns.lootSelf)
        name = link and playerName()
    end
    local itemID = itemIDFromLink(link)
    if not itemID then return end
    for _, record in ipairs(ensureDatabase().history) do
        if not record.confirmed and record.state ~= "deleted" and record.itemID == itemID
            and lower(record.recipient) == lower(name) then
            record.confirmed = true
            publish(record)
            status:SetText(string.format(L["Award #%d confirmed: %s received the item."], record.id, record.recipient))
            announceAward(record)
            updateHistory()
            return
        end
    end
end

-- Trades: items the master looter kept ("held") move to the trade partner once
-- the trade completes. Trades between other players are not visible here.
local function tradeItems()
    local items = {}
    for slot = 1, 6 do
        local itemID = itemIDFromLink(GetTradePlayerItemLink(slot))
        if itemID then table.insert(items, itemID) end
    end
    return items
end

local function snapshotTrade()
    if not trade or trade.closedAt then return end
    trade.partner = trade.partner or UnitName("NPC")
    trade.items = tradeItems()
end

-- The items offered when the player accepts are what the trade hands over: any
-- later change unaccepts the trade. On completion the slots empty (live run
-- 1445c70cd623), so the last slot snapshot alone can miss the traded item.
hooksecurefunc("AcceptTrade", function()
    if not trade or trade.closedAt then return end
    trade.partner = trade.partner or UnitName("NPC")
    trade.accepted = tradeItems()
end)

local function rememberTrade(partner, offered, result)
    ensureDatabase().lastTrade = { partner = partner or "-", offered = offered, result = result, at = time() }
end

-- applyTrade: a held item traded away goes to its roll winner ("given"); an
-- item still waiting for its roll is parked with the trade partner instead
-- (e.g. a unique item another raider holds until the roll). A copy won by the
-- partner moves first, then the oldest held copy.
local function applyTrade(partner, itemIDs)
    local history, moved, used = ensureDatabase().history, {}, {}
    local function heldCopy(itemID, wonByPartner)
        for i = table.getn(history), 1, -1 do   -- oldest first
            local record = history[i]
            if not used[i] and record.state == "held" and record.itemID == itemID and isPlayer(record.recipient)
                and (not wonByPartner or lower(record.winner) == lower(partner)) then
                return i, record
            end
        end
    end
    for _, itemID in ipairs(itemIDs) do
        local i, record = heldCopy(itemID, true)
        if not record then i, record = heldCopy(itemID, false) end
        if record then
            used[i] = true
            local open = isOpenAward(record)
            record.recipient, record.state, record.confirmed = field(partner), open and "parked" or "given", true
            publish(record)
            table.insert(moved, record)
        end
    end
    return moved
end

local function onTradeComplete()
    if not trade then
        rememberTrade(nil, 0, "no trade window seen")
        return
    end
    local items = trade.accepted or trade.items
    if not trade.partner or (trade.closedAt and GetTime() - trade.closedAt > TRADE_GRACE) then
        rememberTrade(trade.partner, table.getn(items), trade.partner and "too late" or "no partner")
        trade = nil
        return
    end
    local moved = applyTrade(trade.partner, items)
    rememberTrade(trade.partner, table.getn(items), "moved " .. table.getn(moved))
    trade = nil
    for _, record in ipairs(moved) do
        say(string.format(L["trade recorded: #%d %s -> %s"], record.id, record.item, record.recipient))
        status:SetText(string.format(L["Award #%d traded: %s has the item now."], record.id, record.recipient))
        announceAward(record, L["traded"])
    end
    if table.getn(moved) > 0 then updateRows() end
end

local function onInfoMessage(...)
    -- 3.3.5a passes only the message; later clients pass a message type first.
    local message = select(select("#", ...), ...)
    if message == ERR_TRADE_COMPLETE then
        onTradeComplete()
    elseif message == ERR_TRADE_CANCELLED then
        if trade then rememberTrade(trade.partner, table.getn(trade.items), "cancelled") end
        trade = nil
    end
end

-- setRecipient corrects an award by hand, e.g. when someone else held a unique
-- item for a moment and traded it on to the winner. Without a name the
-- current player target is used. With `roll` (a re-decided roll), that roll's
-- player becomes the award's winner.
local function setRecipient(id, name, roll)
    local record = findRecord(id)
    if not record then
        say(string.format(L["no award #%s."], tostring(id)))
        return false
    end
    name = trim(name)
    if name == "" then
        if not UnitExists("target") or not UnitIsPlayer("target") then
            say(L["give a name or target the recipient."])
            return false
        end
        name = UnitName("target")
    end
    record.recipient = field(name)
    if roll then record.winner, record.spec = roll.name, roll.kind end
    -- Given to the master looter it stays "held" only while it waits for
    -- another roll winner (the trade); otherwise it is his own award, which
    -- also closes an open (parked) award he won.
    record.state = (isPlayer(name) and record.winner and not isPlayer(record.winner)) and "held" or "manual"
    record.confirmed = true
    record.roll, record.low, record.high = roll and roll.value, roll and roll.low, roll and roll.high
    publish(record)
    status:SetText(string.format(L["Award #%d now goes to %s."], record.id, record.recipient))
    announceAward(record, L["corrected"])
    updateRows()
    return true
end

local function deleteRecord(id)
    local record = findRecord(id)
    if not record or record.state == "deleted" then
        say(string.format(L["no award #%s."], tostring(id)))
        return
    end
    record.state = "deleted"
    publish(record)
    if editing == record then editing = nil end
    status:SetText(string.format(L["Award #%d removed; the export keeps it as deleted."], record.id))
    updateRows()
end

-- Receiving the shared ledger -------------------------------------------------
local STATES = { given = true, held = true, manual = true, deleted = true, parked = true, disenchanted = true, bank = true }
local NOTE_NAMES = { r = "re-roll", t = "not in tie-break", p = "passed", n = "not counted" }
local warnedSession

local function split(text)
    local fields = {}
    for value in string.gmatch(text .. ";", "([^;]*);") do table.insert(fields, value) end
    return fields
end

local function inGroup(name)
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

local function findShared(origin, id)
    for _, record in ipairs(ensureDatabase().history) do
        if record.id == id and lower(record.origin or playerName()) == lower(origin) then return record end
    end
end

-- acceptSession decides whether a message about raid `session` belongs in
-- this ledger. A ledger without awards of its own follows the sender's raid
-- (also after a NEW RAID there); one with its own awards keeps its raid.
local function acceptSession(session, sender)
    local db = ensureDatabase()
    if session == "" then return false end
    if session == db.session then return true end
    for _, record in ipairs(db.history) do
        if lower(record.origin or playerName()) == lower(playerName()) then
            if warnedSession ~= session then
                warnedSession = session
                say(string.format(L["%s shares another raid's ledger; yours has its own awards, so it is not merged. Use CLEAR to follow theirs."], sender))
            end
            return false
        end
    end
    db.history, db.session, db.startedAt = {}, session, nil
    return true
end

local function applyRecord(f, sender)
    local id, rev = tonumber(f[4]), tonumber(f[5])
    if not id or not rev or f[3] == "" or table.getn(f) < 19 or not acceptSession(f[2], sender) then return end
    local db = ensureDatabase()
    local record = findShared(f[3], id)
    if record and (record.rev or 0) >= rev then return end
    local at = tonumber(f[6]) or 0
    if not record then
        record = { id = id, origin = f[3] }
        local position = table.getn(db.history) + 1
        for i, other in ipairs(db.history) do
            if (other.at or 0) < at then position = i break end
        end
        table.insert(db.history, position, record)
    end
    local itemID = tonumber(f[7])
    record.rev, record.at, record.itemID, record.npc = rev, at, itemID, tonumber(f[8])
    record.item = (itemID and select(2, GetItemInfo(itemID))) or record.item or ("item:" .. (itemID or 0))
    record.recipient, record.state, record.confirmed = f[9], STATES[f[10]] and f[10] or "manual", f[11] == "1"
    record.spec = (f[12] == "ms" or f[12] == "os" or f[12] == "boe") and f[12] or nil
    record.roll, record.low, record.high = tonumber(f[13]), tonumber(f[14]), tonumber(f[15])
    record.winner = f[16] ~= "" and f[16] or nil
    record.rolls, record.token = tonumber(f[17]) or 0, f[18] == "1" or nil
    record.time = f[19] ~= "" and f[19] or date("%H:%M", at)
    -- Our own awards coming back (after a crash): never reuse their numbers.
    if lower(f[3]) == lower(playerName()) then db.nextID = math.max(db.nextID, id) end
    db.startedAt = math.min(db.startedAt or at, at)
    updateRows()
end

local function applyLog(f, sender)
    local id, part, total = tonumber(f[4]), tonumber(f[5]), tonumber(f[6])
    if not (id and part and total) or total > 40 or not acceptSession(f[2], sender) then return end
    local record = findShared(f[3], id)
    if not record then return end
    record.logParts = record.logParts or {}
    record.logParts[part] = f[7] or ""
    for i = 1, total do
        if not record.logParts[i] then return end
    end
    local log = {}
    for i = 1, total do
        for entry in string.gmatch(record.logParts[i], "[^/]+") do
            local name, value, low, high, round, code, tally = string.match(entry,
                "^([^,]*),(%d+),(%d+),(%d+),(%d+),(%a?),(%d*)$")
            if name then
                low, high = tonumber(low), tonumber(high)
                table.insert(log, { name = name, value = tonumber(value), low = low, high = high,
                    round = tonumber(round),
                    kind = code ~= "x" and (record.spec == "boe" and "boe" or rollKind(low, high)) or nil,
                    note = code == "x" and (low .. "-" .. high) or NOTE_NAMES[code], tally = tonumber(tally) })
            end
        end
    end
    record.rollLog, record.logParts = log, nil
    updateRows()
end

-- openSnapshot lists the items still waiting in the roll list for wishlist
-- addons: "itemID:status:source:winner" with status o (open), r (rolling) or
-- w (won, not handed out yet) and source c (corpse) or a<award id> (an open
-- award being rolled later).
local lastOpenSnapshot = ""   -- nothing to share until items appear
local function openSnapshot()
    local parts = {}
    for _, entry in ipairs(active) do
        local itemID = itemIDFromLink(entry.item)
        if itemID then
            local status = entry.winner and "w" or (entry.endsAt and "r") or "o"
            local source = entry.later and entry.record and ("a" .. entry.record.id) or "c"
            table.insert(parts, table.concat({ itemID, status, source,
                entry.winner and field(entry.winner.name) or "" }, ":"))
        end
    end
    return table.concat(parts, ",")
end

local function shareOpenItems(force)
    if not groupChannel() then return end
    local snapshot = openSnapshot()
    if snapshot == lastOpenSnapshot and not force then return end
    lastOpenSnapshot = snapshot
    queue(table.concat({ "O", currentSession(), field(playerName()), snapshot }, ";"))
end

-- answerSync sends our own awards, and the asker's (their backup), so a
-- master looter whose client crashed gets the ledger back.
local function answerSync(asker)
    shareOpenItems(true)
    for i = table.getn(ensureDatabase().history), 1, -1 do
        local record = ensureDatabase().history[i]
        local origin = lower(record.origin or playerName())
        if origin == lower(playerName()) or origin == lower(asker) then
            record.origin = record.origin or playerName()
            queue(encodeRecord(record))
            for _, message in ipairs(encodeLog(record)) do queue(message) end
        end
    end
end

local function requestSync()
    queue(table.concat({ "Q", ensureDatabase().session or "-", field(playerName()) }, ";"))
end

-- requestWishlists asks the group's RaidWishlist addons for their lists.
local function requestWishlists()
    queue("WQ;" .. field(playerName()))
end

local function onAddonMessage(prefix, message, channel, sender)
    if prefix ~= SYNC_PREFIX or type(message) ~= "string" or not sender or isPlayer(sender) then return end
    if channel ~= "RAID" and channel ~= "PARTY" or not inGroup(sender) then return end
    local f = split(message)
    if f[1] == "A" then
        applyRecord(f, sender)
    elseif f[1] == "L" then
        applyLog(f, sender)
    elseif f[1] == "Q" and lower(f[3] or "") == lower(sender) then
        answerSync(sender)
    elseif f[1] == "W" then
        if applyWishlist(f, sender) then updateRows() end
    end
end

local panes = { rollPane, detailPane, historyPane }

local function refreshExport(focus)
    local db = ensureDatabase()
    if not db.raidID then
        exportText.generated = ""
        exportText:SetText("")
        status:SetText(L["Enter the website's raid ID to build the export."])
        return
    end
    exportText.generated = buildExport(db.raidID, playerName(), db.startedAt, time(), db.history)
    exportText:SetText(exportText.generated)
    if focus then
        exportText:SetFocus()
        exportText:HighlightText()
    end
    status:SetText(L["Export selected: press Ctrl+C and paste it into the raid website's loot import."])
end

-- Overlays (the export, Raid.lua's raid setup) replace the three panes; only
-- one is shown at a time.
local overlays = { exportPanel }
local function showOverlay(panel)
    for _, overlay in ipairs(overlays) do
        if overlay ~= panel then overlay:Hide() end
    end
    for _, pane in ipairs(panes) do
        if panel then pane:Hide() else pane:Show() end
    end
    if panel then
        Ledger:Show()
        panel:Show()
    end
end

local function showExport(show)
    showOverlay(show and exportPanel or nil)
    if show then
        local db = ensureDatabase()
        raidBox:SetText(db.raidID and tostring(db.raidID) or "")
        refreshExport(true)
    else
        exportText:ClearFocus()
        updateRows()
    end
end

local function setRaidID(value)
    local db = ensureDatabase()
    db.raidID = tonumber(value)
    if exportPanel:IsShown() then refreshExport() end
end

raidBox:SetScript("OnTextChanged", function(self)
    local value = tonumber(self:GetText())
    if value ~= ensureDatabase().raidID then setRaidID(value) end
end)
raidBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
raidBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
exportButton:SetScript("OnClick", function() showExport(not exportPanel:IsShown()) end)
backButton:SetScript("OnClick", function() showExport(false) end)

-- A new raid starts an empty ledger, so its loot is never exported under the
-- previous raid's ID. Award IDs keep counting up.
local function startNewRaid()
    local db = ensureDatabase()
    db.history = {}
    db.startedAt = nil
    db.raidID = nil
    db.session = nil   -- the next award starts a new shared ledger
    editing = nil
    historyOffset = 0
    raidBox:SetText("")
    if exportPanel:IsShown() then refreshExport() end
    say(L["new raid: the award ledger is empty."])
    updateRows()
end

StaticPopupDialogs["RAIDLEDGER_NEW_RAID"] = {
    text = L["Clear all recorded loot and start a new raid? Export it first."],
    button1 = YES,
    button2 = NO,
    OnAccept = function() startNewRaid() end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
}
newRaidButton:SetScript("OnClick", function() StaticPopup_Show("RAIDLEDGER_NEW_RAID") end)
clearButton:SetScript("OnClick", function() StaticPopup_Show("RAIDLEDGER_NEW_RAID") end)

local function rollPattern()
    return patternFromFormat(RANDOM_ROLL_RESULT or "%s rolls %d (%d-%d)")
end

local function recordRoll(message)
    local name, roll, low, high = string.match(message or "", rollPattern())
    if not name or not roll then return end
    local entry = rollingEntry()
    if not entry then return end
    local value, lo, hi = tonumber(roll) or 0, tonumber(low), tonumber(high)
    local kind = rollKind(lo, hi)
    -- A free BoE roll takes plain /rnd 100 only.
    if entry.free then kind = (lo == 1 and hi == 100) and "boe" or nil end
    -- Ignored rolls are kept in the roll log with the reason, for disputes.
    local note
    if not kind then
        -- Only /rnd 100, /rnd 99 and enhanced main-spec ranges count (in a free
        -- roll only /rnd 100); "/rnd 1000" would otherwise win.
        note = low .. "-" .. high
    elseif entry.tieBreak and not entry.tieBreak[name] then
        -- During a tie-break only the tied players may roll.
        note = "not in tie-break"
    else
        -- The first roll counts; re-rolls are ignored.
        for _, existing in ipairs(entry.rolls) do
            if existing.name == name then note = "re-roll" end
        end
    end
    entry.rollLog = entry.rollLog or {}
    table.insert(entry.rollLog, { name = name, value = value, round = entry.round or 1, note = note,
        kind = kind, low = lo, high = hi })
    if note then return end
    table.insert(entry.rolls, { name = name, value = value, kind = kind, low = lo, high = hi,
        tally = tallyOf(tallies(isToken(entry.item)), name, kind) })
    table.sort(entry.rolls, ranksAbove)
    updateRows()
end

-- startSelectedRoll starts a roll for the selected item; with `free` a free
-- BoE roll for any character.
local function startSelectedRoll(free)
    local entry = selectedEntry()
    if not entry then
        status:SetText(L["Select a master-loot item before starting a roll."])
        return
    end
    entry.free = free and true or nil
    entry.rolls = {}
    entry.rollLog = {}
    entry.round = 1
    entry.winner = nil
    entry.tieBreak = nil
    local seconds = rollSeconds()
    entry.endsAt = GetTime() + seconds
    entry.startedAt = GetTime()
    entry.reminders = reminders(seconds)
    entry.rollKey = nil
    if free then
        -- Not shared: wishlists only prompt for main- and off-spec rolls.
        announce(string.format(L["[Loot] %s - free BoE roll for any character! /rnd 100, %d seconds."], entry.item, seconds))
        status:SetText(string.format(L["%d-second free BoE roll started."], seconds))
    else
        announce(string.format(L["[Loot] %s - /rnd now! %d seconds. /rnd 100 main spec (enhanced: 1+X to 100+X, X up to 50), /rnd 99 off spec."],
            entry.item, seconds))
        shareRollStart(entry, seconds)
        status:SetText(string.format(L["%d-second raid roll started."], seconds))
    end
    updateRows()
end

-- startFreeRoll posts an item again for any character (bind on equip): the
-- popup's entry, or the selected item for /ledger free.
local function startFreeRoll(entry)
    if entry then
        if not isActive(entry) then return end
        selected, editing = entry, nil
    end
    entry = selectedEntry()
    if entry and entry.endsAt and not entry.winner then
        say(L["a roll is already running for this item."])
        return
    end
    startSelectedRoll(true)
end

StaticPopupDialogs["RAIDLEDGER_FREE_ROLL"] = {
    text = L["Nobody rolled on %s. Post it again now as a free BoE roll for any character? (Later: select it and /ledger free)"],
    button1 = L["NOW"],
    button2 = L["LATER"],
    OnAccept = function(_, entry) startFreeRoll(entry) end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
}

local function joinNames(names)
    local count = table.getn(names)
    if count == 1 then return names[1] end
    return table.concat(names, ", ", 1, count - 1) .. L[" and "] .. names[count]
end

-- Ends a roll: a single top roll wins; a shared top roll starts a tie-break in
-- which only the tied players roll again (and which can tie again).
local function finishRoll(entry)
    entry.endsAt = nil
    if activeRollCount(entry) == 0 then
        announce(string.format(L["[Loot] %s - no valid rolls."], entry.item))
        -- Nobody needs a BoE item for this character: offer it to everyone.
        if not entry.free and isBindOnEquip(entry.item) then
            local dialog = StaticPopup_Show("RAIDLEDGER_FREE_ROLL", entry.item, nil, entry)
            -- The popup may land in any StaticPopup slot: expose this one to plans.
            if dialog and ForgeTestBridge and ForgeTestBridge.RegisterFrame then
                ForgeTestBridge:RegisterFrame("RaidLedgerFreeRollNow", _G[dialog:GetName() .. "Button1"])
                ForgeTestBridge:RegisterFrame("RaidLedgerFreeRollText", _G[dialog:GetName() .. "Text"])
            end
        end
        return
    end
    -- Tallies may have changed during the roll (other awards): rank again.
    local counts = tallies(isToken(entry.item))   -- tokens rank by the token tally
    for _, roll in ipairs(entry.rolls) do roll.tally = tallyOf(counts, roll.name, roll.kind) end
    table.sort(entry.rolls, ranksAbove)
    local best = entry.rolls[1]
    local top = best.value
    local tied = {}
    for _, roll in ipairs(entry.rolls) do
        if roll.kind == best.kind and roll.tally == best.tally and roll.value == top then
            table.insert(tied, roll.name)
        end
    end
    if table.getn(tied) > 1 then
        table.sort(tied)
        entry.tieBreak = {}
        for _, name in ipairs(tied) do entry.tieBreak[name] = true end
        entry.rolls = {}
        entry.round = (entry.round or 1) + 1
        local seconds = tieSeconds()
        entry.endsAt = GetTime() + seconds
        entry.startedAt = GetTime()
        entry.reminders = reminders(seconds)
        announce(string.format(L["[Loot] %s - tie between %s (%d)! %s: /rnd again, %d seconds."],
            entry.item, joinNames(tied), top, table.concat(tied, ", "), seconds))
        shareRollStart(entry, seconds, tied)
        return
    end
    entry.winner = entry.rolls[1]
    entry.tieBreak = nil
    if selectedEntry() == entry and not editing then recipientBox:SetText(entry.winner.name) end
    if entry.free then
        announce(string.format(L["[Loot] %s - free BoE roll won by %s (%d)."], entry.item, best.name, best.value))
        return
    end
    announce(string.format(L["[Loot] %s won by %s (%d) - %s%s, %s so far."], entry.item, best.name, best.value,
        SPEC_NAMES[best.kind], best.low and best.low > 1 and (" " .. best.low .. "-" .. best.high) or "",
        itemCount(best.tally or 0, isToken(entry.item))))
end

-- Passes and recounts work on the roll log: a struck roll gets a note, a
-- recount changes the logged roll and keeps what was rolled in `was`. Once the
-- roll has ended the winner is decided again from the latest round that still
-- has counted rolls (after a tie-break: the tied players, then the earlier rolls).
function roster.counted(entry, name)
    local found = {}
    for _, r in ipairs(entry.rollLog or {}) do
        if r.kind and not r.note and string.lower(r.name) == string.lower(name) then table.insert(found, r) end
    end
    table.sort(found, function(a, b) return (a.round or 1) > (b.round or 1) end)
    return found
end

function roster.rank(entry, round)
    local counts = tallies(isToken(entry.item))
    local rolls = {}
    for _, r in ipairs(entry.rollLog or {}) do
        if r.kind and not r.note and (r.round or 1) == round then
            table.insert(rolls, { name = r.name, value = r.value, kind = r.kind, low = r.low, high = r.high,
                tally = tallyOf(counts, r.name, r.kind) })
        end
    end
    table.sort(rolls, ranksAbove)
    return rolls
end

function roster.decide(entry)
    local round = 0
    for _, r in ipairs(entry.rollLog or {}) do
        if r.kind and not r.note and (r.round or 1) > round then round = r.round or 1 end
    end
    if entry.winner and selectedEntry() == entry and not editing and recipientBox:GetText() == entry.winner.name then
        recipientBox:SetText("")
    end
    entry.winner, entry.tieBreak = nil, nil
    entry.rolls = roster.rank(entry, round)
    finishRoll(entry)
end

-- roster.change strikes or recounts a player's logged rolls and announces it.
function roster.change(item, logs, how, points, free)
    local strike = how == "pass" or how == "none"
    if free and not strike then
        say(L["a free BoE roll only takes /rnd 100; pass or none only."])
        return false
    end
    local name = logs[1].name
    for _, r in ipairs(logs) do
        if strike then
            r.note = how == "pass" and "passed" or "not counted"
        else
            -- The roll without points; enhanced main spec adds them again.
            local base = r.value - ((r.kind == "ms" and r.low and r.low > 1) and (r.low - 1) or 0)
            r.was = r.was or string.format("%d (%d-%d)", r.value, r.low or 1, r.high or 100)
            local add = how == "enh" and points or 0
            if how == "os" then
                r.kind, r.low, r.high, r.value = "os", 1, 99, base
            else
                r.kind, r.low, r.high, r.value = "ms", 1 + add, 100 + add, base + add
            end
        end
    end
    local r = logs[1]
    if how == "pass" then
        announce(string.format(L["[Loot] %s - %s passes."], item, name))
    elseif how == "none" then
        announce(string.format(L["[Loot] %s - %s's roll does not count."], item, name))
    else
        announce(string.format(L["[Loot] %s - %s's roll counts as %s (%d)."], item, name,
            SPEC_NAMES[r.kind] .. (r.low > 1 and (" " .. r.low .. "-" .. r.high) or ""), r.value))
    end
    return true
end

-- roster.apply: how = "pass", "none" (strike the roll), "ms", "os" or "enh"
-- with `points` (0-50), for `name`'s roll on the selected item, or on the
-- award whose roll log is shown.
function roster.apply(name, how, points)
    if editing then return roster.applyAward(editing, name, how, points) end
    local entry = selectedEntry()
    local logs = entry and roster.counted(entry, name or "") or {}
    if not logs[1] then
        say(string.format(L["%s has no counted roll on the selected item."], name or "?"))
        return
    end
    if not roster.change(entry.item, logs, how, points, entry.free) then return end
    name = logs[1].name
    local strike = how == "pass" or how == "none"
    if entry.endsAt and not entry.winner then
        -- Still rolling. A tie-break with fewer than two tied players left is decided now.
        local left = 0
        if entry.tieBreak and strike then
            for tied in pairs(entry.tieBreak) do
                if string.lower(tied) == string.lower(name) then entry.tieBreak[tied] = nil end
            end
            for _ in pairs(entry.tieBreak) do left = left + 1 end
        end
        if entry.tieBreak and strike and left < 2 then
            entry.endsAt = nil
            roster.decide(entry)
        else
            entry.rolls = roster.rank(entry, entry.round or 1)
        end
    else
        roster.decide(entry)
    end
    updateRows()
end

-- roster.sortLog orders a roll log like sortedRollLog: by round, counted rolls
-- in winning order, then ignored rolls as they came in.
function roster.sortLog(log)
    local order = {}
    for i, r in ipairs(log) do order[r] = i end
    table.sort(log, function(a, b)
        if (a.round or 1) ~= (b.round or 1) then return (a.round or 1) < (b.round or 1) end
        if (a.note == nil) ~= (b.note == nil) then return a.note == nil end
        if a.note == nil and (a.kind ~= b.kind or a.tally ~= b.tally or a.value ~= b.value) then
            return ranksAbove(a, b)
        end
        return order[a] < order[b]
    end)
end

-- roster.applyAward: a pass or recount on a given-out award (rules of
-- 2026-10-17). If someone else now wins, the award goes to them like a manual
-- recipient change; with nobody valid left (or a tie) the master looter decides.
function roster.applyAward(record, name, how, points)
    local logs = roster.counted(record, name or "")
    if not logs[1] then
        say(string.format(L["%s has no counted roll on award #%d."], name or "?", record.id))
        return
    end
    if record.state ~= "given" and record.state ~= "held" and record.state ~= "manual" then
        say(string.format(L["award #%d is not with a player; change it by hand."], record.id))
        return
    end
    if not roster.change(record.item, logs, how, points, record.spec == "boe") then return end
    -- Rank again as if this award had not happened: its holder's tally without it.
    local round = 0
    for _, r in ipairs(record.rollLog) do
        if r.kind and not r.note and (r.round or 1) > round then round = r.round or 1 end
    end
    local counts = tallies(record.token)
    local holder = lower((record.state == "held" and record.winner) or record.recipient or "")
    local rolls = {}
    for _, r in ipairs(record.rollLog) do
        if r.kind and not r.note then
            r.tally = tallyOf(counts, r.name, r.kind)
            if lower(r.name) == holder and record.spec == r.kind then r.tally = math.max(r.tally - 1, 0) end
            if (r.round or 1) == round then table.insert(rolls, r) end
        end
    end
    table.sort(rolls, ranksAbove)
    roster.sortLog(record.rollLog)
    local best, second = rolls[1], rolls[2]
    if not best then
        status:SetText(string.format(L["Award #%d: no valid roll is left; decide who gets it (DE, BANK or another recipient)."], record.id))
    elseif second and second.kind == best.kind and second.tally == best.tally and second.value == best.value then
        status:SetText(string.format(L["Award #%d: %s and %s tie; decide who gets it."], record.id, best.name, second.name))
    elseif lower(best.name) ~= lower(record.recipient or "") then
        if editing == record then recipientBox:SetText(best.name) end
        setRecipient(record.id, best.name, best)
        return
    else
        record.winner, record.spec = best.name, best.kind
        record.roll, record.low, record.high = best.value, best.low, best.high
    end
    publish(record)
    updateRows()
end

function roster.askPoints(name)
    local entry = editing or selectedEntry()
    local r = entry and roster.counted(entry, name or "")[1]
    roster.points = (r and r.kind == "ms" and r.low and r.low > 1) and (r.low - 1) or 0
    StaticPopup_Show("RAIDLEDGER_POINTS", name, nil, name)
end

StaticPopupDialogs["RAIDLEDGER_POINTS"] = {
    text = L["Points for %s's enhanced roll (1+X to 100+X, X 0-50; 0 = plain main spec):"],
    button1 = OKAY,
    button2 = CANCEL,
    hasEditBox = 1,
    maxLetters = 2,
    OnShow = function(self)
        local box = _G[self:GetName() .. "EditBox"]
        if box then
            box:SetText(tostring(roster.points or 0))
            box:HighlightText()
        end
    end,
    OnAccept = function(self, name)
        local box = _G[self:GetName() .. "EditBox"]
        local points = tonumber(box and box:GetText() or "")
        if points and points >= 0 and points <= 50 and points == math.floor(points) then
            roster.apply(name, "enh", points)
        else
            say(L["usage: /ledger count <name> ms|os|none|enh <0-50>"])
        end
    end,
    EditBoxOnEnterPressed = function(self)
        local dialog = self:GetParent()
        StaticPopupDialogs["RAIDLEDGER_POINTS"].OnAccept(dialog, dialog.data)
        dialog:Hide()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
}

local function updateRollTimers()
    local running = false
    for _, entry in ipairs(active) do
        if entry.endsAt and not entry.winner then
            running = true
            local remaining = entry.endsAt - GetTime()
            if remaining <= 0 then
                finishRoll(entry)
                updateRows()
            else
                -- One message even if a slow frame passed both reminders.
                local left
                while entry.reminders and entry.reminders[1] and remaining <= entry.reminders[1] do
                    left = table.remove(entry.reminders, 1)
                end
                if left then announce(string.format(L["[Loot] %s - %d seconds left."], entry.item, left)) end
            end
        end
    end
    -- Keep the countdown in the window ticking between rolls.
    if running and Ledger:IsShown() then updateSelection() end
end

-- startLaterRoll rolls an open award (parked, or held without a roll): the
-- item joins the roll list, the roll runs as usual, and its result is written
-- onto the same award.
local function startLaterRoll(record)
    for _, entry in ipairs(active) do
        if entry.record == record and entry.later then
            selected = entry
            editing = nil
            startSelectedRoll()
            return
        end
    end
    local entry = { item = record.item, npc = record.npc, rolls = {}, record = record, later = true }
    table.insert(active, 1, entry)
    while table.getn(active) > MAX_ACTIVE do table.remove(active) end
    selected, editing = entry, nil
    recipientBox:SetText("")
    startSelectedRoll()
end

-- finishLaterRoll records the winner of a later roll. Held by the master
-- looter, the award stays "held" for the winner until the trade; parked with
-- another raider, the winner becomes the recipient (the hand-over between two
-- other players is not visible to this addon).
finishLaterRoll = function(entry, recipient)
    local record = entry.record
    local holder = record.recipient
    local roll = findRoll(entry, recipient)
    record.rollLog = sortedRollLog(entry)
    record.rolls = table.getn(entry.rolls or {})
    record.roll, record.spec = roll and roll.value, roll and roll.kind
    record.low, record.high = roll and roll.low, roll and roll.high
    record.winner = field(recipient)
    record.confirmed = true
    local how
    if isPlayer(holder) then
        record.state = "held"
        how = string.format(L["with %s until traded"], holder)
    else
        record.recipient, record.state, record.holder = field(recipient), "manual", holder
        how = string.format(L["%s hands it over"], holder)
    end
    for index = table.getn(active), 1, -1 do
        if active[index] == entry then table.remove(active, index) end
    end
    if selected == entry then selected = nil end
    publish(record, true)
    announceAward({ item = record.item, recipient = record.winner, spec = record.spec }, how)
    recipientBox:SetText("")
    status:SetText(string.format(L["Award #%d goes to %s (%s)."], record.id, record.winner, how))
    updateRows()
end

-- parkSelected hands the selected loot to a raider (or keeps it) to be rolled
-- later, or marks a recorded award as parked with its current holder.
local function parkSelected()
    local holder = trim(recipientBox:GetText())
    if editing then
        if isOpenAward(editing) then
            startLaterRoll(editing)
            return
        end
        if editing.state == "deleted" then
            status:SetText(L["Restore the award before parking it."])
            return
        end
        editing.recipient = field(holder ~= "" and holder or editing.recipient)
        editing.state, editing.winner, editing.spec, editing.roll = "parked", nil, nil, nil
        editing.low, editing.high, editing.confirmed = nil, nil, true
        publish(editing)
        announceAward(editing)
        status:SetText(string.format(L["Award #%d is open, held by %s until it is rolled."], editing.id, editing.recipient))
        editing = nil
        recipientBox:SetText("")
        updateRows()
        return
    end
    local entry = selectedEntry()
    if not entry or entry.later then
        status:SetText(L["Select a loot item to park."])
        return
    end
    if holder == "" then holder = playerName() end
    local slot = lootSlotOf(entry)
    if slot then
        local index = candidateIndex(holder)
        if not index then
            status:SetText(string.format(L["%s cannot receive this item (not a master-loot candidate)."], holder))
            return
        end
        parkSlots[slot] = "parked"
        recipientBox:SetText("")
        GiveMasterLoot(slot, index)
        return
    end
    local record = recordAward(entry, holder, "parked", true)
    announceAward(record)
    recipientBox:SetText("")
    status:SetText(string.format(L["Award #%d is open, held by %s until it is rolled."], record.id, holder))
    updateRows()
end
park:SetScript("OnClick", parkSelected)

-- giveAway hands the selected item (or marks the selected award) for
-- disenchanting or the guild bank. The holder is the name in the box, else you.
local function giveAway(state)
    local holder = trim(recipientBox:GetText())
    if editing then
        editing.recipient = field(holder ~= "" and holder or editing.recipient)
        editing.state, editing.winner, editing.confirmed = state, nil, true
        editing.roll, editing.spec, editing.low, editing.high = nil, nil, nil, nil
        publish(editing)
        announceAward(editing)
        status:SetText(string.format(L["Award #%d: %s (%s)."], editing.id, stateLabels[state], editing.recipient))
        editing = nil
        recipientBox:SetText("")
        updateRows()
        return
    end
    local entry = selectedEntry()
    if not entry or entry.later then
        status:SetText(L["Select a loot item first."])
        return
    end
    if holder == "" then holder = playerName() end
    local slot = lootSlotOf(entry)
    if slot then
        local index = candidateIndex(holder)
        if not index then
            status:SetText(string.format(L["%s cannot receive this item (not a master-loot candidate)."], holder))
            return
        end
        parkSlots[slot] = state
        recipientBox:SetText("")
        GiveMasterLoot(slot, index)
        return
    end
    local record = recordAward(entry, holder, state, true)
    announceAward(record)
    recipientBox:SetText("")
    status:SetText(string.format(L["Award #%d: %s (%s)."], record.id, stateLabels[state], holder))
    updateRows()
end
disenchantButton:SetScript("OnClick", function() giveAway("disenchanted") end)
bankButton:SetScript("OnClick", function() giveAway("bank") end)
for button, tip in pairs({ [disenchantButton] = L["Disenchant: give it to the name in the box (or keep it); counts for nobody"],
    [bankButton] = L["Guild bank: give it to the name in the box (or keep it); counts for nobody"] }) do
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(tip, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

award:SetScript("OnClick", function()
    local recipient = trim(recipientBox:GetText())
    if editing then
        if recipient == "" then
            status:SetText(L["Enter the new recipient's name."])
            return
        end
        if setRecipient(editing.id, recipient) then
            editing = nil
            recipientBox:SetText("")
            updateRows()
        end
        return
    end
    local entry = selectedEntry()
    if not entry then
        status:SetText(L["Select a loot roll before recording an award."])
        return
    end
    if recipient == "" then
        status:SetText(L["Choose or enter a recipient name."])
        return
    end
    if entry.later then
        finishLaterRoll(entry, recipient)
        return
    end
    -- With the item still in the master-loot window, hand it out for real; the
    -- GiveMasterLoot hook then records the award.
    local slot = lootSlotOf(entry)
    if slot then
        local index = candidateIndex(recipient)
        if not index then
            status:SetText(string.format(L["%s cannot receive this item (not a master-loot candidate)."], recipient))
            return
        end
        recipientBox:SetText("")
        GiveMasterLoot(slot, index)
        return
    end
    local record = recordAward(entry, recipient, "manual", true)
    announceAward(record)
    recipientBox:SetText("")
    status:SetText(string.format(L["Award #%d recorded for %s."], record.id, recipient))
    updateRows()
end)

Ledger:RegisterEvent("PLAYER_LOGIN")
Ledger:RegisterEvent("LOOT_OPENED")
Ledger:RegisterEvent("LOOT_READY")
Ledger:RegisterEvent("LOOT_CLOSED")
Ledger:RegisterEvent("CHAT_MSG_SYSTEM")
Ledger:RegisterEvent("CHAT_MSG_LOOT")
Ledger:RegisterEvent("RAID_ROSTER_UPDATE")
Ledger:RegisterEvent("PARTY_MEMBERS_CHANGED")
Ledger:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
Ledger:RegisterEvent("TRADE_SHOW")
Ledger:RegisterEvent("TRADE_PLAYER_ITEM_CHANGED")
Ledger:RegisterEvent("TRADE_ACCEPT_UPDATE")
Ledger:RegisterEvent("TRADE_CLOSED")
Ledger:RegisterEvent("UI_INFO_MESSAGE")
Ledger:RegisterEvent("CHAT_MSG_ADDON")
Ledger:SetScript("OnEvent", function(self, event, ...)
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        local _, subEvent, _, _, _, destGUID = ...
        if subEvent == "UNIT_DIED" then
            local npc = npcFromGUID(destGUID)
            if npc then lastKill = { guid = destGUID, npc = npc } end
        end
    elseif event == "PLAYER_LOGIN" then
        ensureDatabase()
        syncAt = GetTime() + 8
        updateRows()
        if ForgeTestBridge and ForgeTestBridge.RegisterFrame then
            ForgeTestBridge:RegisterFrame("RaidLedgerFrame", self)
            ForgeTestBridge:RegisterFrame("RaidLedgerItem", itemDetail)
            ForgeTestBridge:RegisterFrame("RaidLedgerAward", award)
            ForgeTestBridge:RegisterFrame("RaidLedgerRecipient", recipientBox)
            ForgeTestBridge:RegisterFrame("RaidLedgerRollDetail", rollDetail)
            ForgeTestBridge:RegisterFrame("RaidLedgerPark", park)
            ForgeTestBridge:RegisterFrame("RaidLedgerDisenchant", disenchantButton)
            ForgeTestBridge:RegisterFrame("RaidLedgerBank", bankButton)
            ForgeTestBridge:RegisterFrame("RaidLedgerHistory1", historyLines[1])
            ForgeTestBridge:RegisterFrame("RaidLedgerExportButton", exportButton)
            ForgeTestBridge:RegisterFrame("RaidLedgerExportText", exportText)
            ForgeTestBridge:RegisterFrame("RaidLedgerRollHeading", rollHeading)
            for i = 1, 3 do ForgeTestBridge:RegisterFrame("RaidLedgerRoll" .. i, rows[i]) end
            for i = 1, 4 do ForgeTestBridge:RegisterFrame("RaidLedgerMember" .. i, rosterButtons[i]) end
            ForgeTestBridge:RegisterFrame("RaidLedgerAllMembers", roster.all)
            ForgeTestBridge:RegisterFrame("RaidLedgerMembers", roster.pane)
        end
    elseif event == "LOOT_OPENED" or event == "LOOT_READY" then
        captureMasterLoot()
        updateRows()
    elseif event == "LOOT_CLOSED" then
        lootSlots = {}
        windowKey, windowNpc = nil, nil
        updateRows()
    elseif event == "CHAT_MSG_SYSTEM" then
        recordRoll(...)
    elseif event == "CHAT_MSG_LOOT" then
        onLootMessage(...)
    elseif event == "TRADE_SHOW" then
        trade = { partner = UnitName("NPC"), items = {} }
    elseif event == "TRADE_PLAYER_ITEM_CHANGED" or event == "TRADE_ACCEPT_UPDATE" then
        snapshotTrade()
    elseif event == "TRADE_CLOSED" then
        if trade and not trade.closedAt then trade.closedAt = GetTime() end
    elseif event == "UI_INFO_MESSAGE" then
        onInfoMessage(...)
    elseif event == "CHAT_MSG_ADDON" then
        onAddonMessage(...)
    else
        -- New raiders bring their wishlists; ask once the group has settled.
        local size = math.max(GetNumRaidMembers() or 0, GetNumPartyMembers() or 0)
        if size > groupSize and not syncAt then wishAskAt = GetTime() + 5 end
        groupSize = size
        updateRoster()
    end
end)
-- Timers run on a separate, always-shown frame: WoW only fires OnUpdate for
-- visible frames, so hiding the ledger must not freeze a running roll.
local ticker = CreateFrame("Frame")
local tickElapsed = 0
ticker:SetScript("OnUpdate", function(_, elapsed)
    tickElapsed = tickElapsed + elapsed
    if tickElapsed >= 0.25 then
        tickElapsed = 0
        if LootFrame and LootFrame:IsShown() then captureMasterLoot() end
        updateRollTimers()
        shareOpenItems()
        -- Shared ledger: at most four addon messages per second.
        if outbox[1] then
            local channel = groupChannel()
            if channel then SendAddonMessage(SYNC_PREFIX, table.remove(outbox, 1), channel) else outbox = {} end
        end
        if syncAt and GetTime() >= syncAt then
            syncAt = nil
            if groupChannel() then
                requestSync()
                requestWishlists()
            end
        end
        if wishAskAt and GetTime() >= wishAskAt then
            wishAskAt = nil
            if groupChannel() then requestWishlists() end
        end
    end
end)

-- Raid.lua (invites, groups, attendance; taken over from RaidSync) builds on
-- these.
ns.Ledger, ns.label, ns.flatButton, ns.makeBackdrop = Ledger, label, flatButton, makeBackdrop
ns.ensureDatabase, ns.say, ns.field, ns.trim, ns.lower = ensureDatabase, say, field, trim, lower
ns.playerName, ns.isPlayer, ns.patternFromFormat = playerName, isPlayer, patternFromFormat
ns.setStatus = function(text) status:SetText(text) end
ns.addOverlay = function(panel) table.insert(overlays, panel) end
ns.showOverlay = function(panel)
    showOverlay(panel)
    if not panel then updateRows() end
end
ns.headerButton = exportButton
ns.raidID = function() return ensureDatabase().raidID end
ns.setRaidID = function(id)
    setRaidID(id)
    raidBox:SetText(id and tostring(id) or "")
end
ns.historyCount = function() return table.getn(ensureDatabase().history) end
ns.commands = {}
ns.help = {}

local HELP = {
    L["/ledger - show or hide the ledger"],
    L["/ledger start - start a %d s /rnd roll for the selected item"],
    L["/ledger timer [seconds] [tie-break seconds] - roll lengths for new rolls; /ledger timer reset"],
    L["/ledger free - post the selected item again: free BoE roll for any character (/rnd 100)"],
    L["/ledger set <#> [name] - change the recipient of award #, or to your target"],
    L["/ledger del <#> - remove award # (exported as deleted)"],
    L["/ledger spec <#> ms|os|none - set which tally award # counts for"],
    L["/ledger pass <name> - the player passes: the next-best roll wins"],
    L["/ledger count <name> ms|os|none|enh <0-50> - change how a roll on the selected item counts"],
    L["/ledger tally - items per player this raid (main spec / off spec)"],
    L["/ledger raid <id> - set the website raid ID"],
    L["/ledger export - show the website export"],
    L["/ledger sync - ask the group's other ledgers for this raid's awards"],
    L["/ledger newraid (or CLEAR) - empty the award ledger for the next raid; add confirm to skip the question"],
    L["/ledger clear - drop all active rolls;  /ledger reset - recenter the window"],
}

SLASH_RAIDLEDGER1 = "/ledger"
SLASH_RAIDLEDGER2 = "/raidledger"
SlashCmdList["RAIDLEDGER"] = function(message)
    local command, rest = trim(message):match("^(%S*)%s*(.-)$")
    command = string.lower(command or "")
    if command == "reset" then
        Ledger:ClearAllPoints()
        Ledger:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
        Ledger:Show()
    elseif command == "clear" then
        active = {}
        selected = nil
        drops = {}
        lootSlots = {}
        updateRows()
    elseif command == "start" then
        startSelectedRoll()
    elseif command == "free" then
        startFreeRoll()
    elseif command == "pass" then
        local name = rest:match("^(%S+)$")
        if name then roster.apply(name, "pass") else say(L["usage: /ledger pass <name>"]) end
    elseif command == "count" then
        local name, how, points = rest:match("^(%S+)%s+(%a+)%s*(%d*)$")
        how, points = how and string.lower(how), tonumber(points)
        if name and (how == "ms" or how == "os" or how == "none") and not points then
            roster.apply(name, how)
        elseif name and how == "enh" and points and points <= 50 then
            roster.apply(name, "enh", points)
        else
            say(L["usage: /ledger count <name> ms|os|none|enh <0-50>"])
        end
    elseif command == "timer" then
        -- /ledger timer [roll] [tie], /ledger timer tie <s>, /ledger timer reset.
        -- Applies to rolls started afterwards; a running roll keeps its time.
        local db = ensureDatabase()
        local args = {}
        for word in string.gmatch(string.lower(rest), "%S+") do table.insert(args, word) end
        local roll, tie
        if args[1] == "reset" and not args[2] then
            db.rollSeconds, db.tieSeconds = nil, nil
        elseif args[1] == "tie" and args[2] and not args[3] then
            tie = tonumber(args[2])
            if not tie then args.bad = true end
        elseif args[1] then
            roll, tie = tonumber(args[1]), args[2] and tonumber(args[2])
            if not roll or (args[2] and not tie) or args[3] then args.bad = true end
        end
        if args.bad or (roll and (roll ~= math.floor(roll) or roll < ROLL_LIMITS[1] or roll > ROLL_LIMITS[2]))
            or (tie and (tie ~= math.floor(tie) or tie < TIE_LIMITS[1] or tie > TIE_LIMITS[2])) then
            say(string.format(L["usage: /ledger timer [seconds] [tie-break seconds] (roll %d-%d, tie-break %d-%d), or /ledger timer reset"],
                ROLL_LIMITS[1], ROLL_LIMITS[2], TIE_LIMITS[1], TIE_LIMITS[2]))
        else
            if roll then db.rollSeconds = roll ~= ROLL_SECONDS and roll or nil end
            if tie then db.tieSeconds = tie ~= TIE_SECONDS and tie or nil end
            say(string.format(L["roll timer: %d seconds, tie-break: %d seconds."], rollSeconds(), tieSeconds()))
        end
    elseif command == "set" then
        local id, name = rest:match("^#?(%d+)%s*(.-)$")
        if id then setRecipient(tonumber(id), name) else say(L["usage: /ledger set <#> [name]"]) end
    elseif command == "del" then
        local id = rest:match("^#?(%d+)$")
        if id then deleteRecord(tonumber(id)) else say(L["usage: /ledger del <#>"]) end
    elseif command == "spec" then
        local id, spec = rest:match("^#?(%d+)%s+(%a+)$")
        spec = spec and string.lower(spec)
        local record = id and findRecord(tonumber(id))
        if not record or (spec ~= "ms" and spec ~= "os" and spec ~= "none") then
            say(L["usage: /ledger spec <#> ms|os|none"])
        else
            record.spec = spec ~= "none" and spec or nil
            publish(record)
            say(string.format(L["award #%d counts for %s."], record.id, record.spec and SPEC_NAMES[record.spec] or L["no tally"]))
            updateRows()
        end
    elseif command == "sync" then
        if groupChannel() then
            requestSync()
            say(L["asked the group's ledgers for this raid's awards."])
        else
            say(L["not in a group: nothing to sync."])
        end
    elseif command == "tally" then
        -- Two separate lists: items, then tokens.
        for _, tokens in ipairs({ false, true }) do
            local names, counts = {}, tallies(tokens)
            for _, record in ipairs(ensureDatabase().history) do
                local name = (record.state == "held" and record.winner) or record.recipient
                if counts[lower(name)] and not names[lower(name)] then
                    names[lower(name)] = true
                    table.insert(names, name)
                end
            end
            table.sort(names, function(a, b) return lower(a) < lower(b) end)
            if tokens and table.getn(names) > 0 then say(L["tokens this raid:"]) end
            if not tokens and table.getn(names) == 0 then say(L["no items counted this raid yet."]) end
            for _, name in ipairs(names) do
                say(string.format(L["%s: %d main spec, %d off spec%s"], name, tallyOf(counts, name, "ms"),
                    tallyOf(counts, name, "os"), tokens and L[" (tokens)"] or ""))
            end
        end
    elseif command == "raid" then
        local id = rest:match("^(%d+)$")
        if id then
            setRaidID(id)
            raidBox:SetText(id)
            say(string.format(L["raid ID %s."], id))
        else
            say(L["usage: /ledger raid <id>"])
        end
    elseif command == "export" then
        showExport(true)
    elseif command == "newraid" then
        if string.lower(rest) == "confirm" then startNewRaid() else StaticPopup_Show("RAIDLEDGER_NEW_RAID") end
    elseif command == "" or command == "toggle" then
        if Ledger:IsShown() then Ledger:Hide() else Ledger:Show() end
    elseif ns.commands[command] then
        ns.commands[command](rest)
    else
        for _, line in ipairs(HELP) do say(string.format(line, rollSeconds())) end
        for _, line in ipairs(ns.help) do say(line) end
    end
end

Ledger:Show()
