-- RaidLedger: raid roll and master-loot award ledger for WoW 3.3.5a / Lua 5.1.
-- Records who really received each item (master-loot handouts, confirmed by the
-- loot chat line), follows trades of items the master looter kept, allows manual
-- corrections and exports the ledger for the raid website (RS2;LOOT).
local addonName, ns = ...
local L = ns.L
local Ledger = CreateFrame("Frame")   -- events and timers; the window is UI.lua's
-- The window (UI.lua and the tab files) fills these in; the core only calls them.
local ui = { status = function() end, refresh = function() end, suggest = function() end,
    show = function() end, shown = function() return false end }
ns.ui = ui
local MAX_HISTORY = 250
local MAX_ACTIVE = 10
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
local syncAt            -- when to ask the group for the shared ledger (after login)
local wishAskAt         -- when to ask the group's wishlist addons for their lists
local groupSize = 0
-- Members' wishlists, shared by RaidWishlist ("W" messages). Kept for this
-- session only; the ledger asks again after a login or /reload.
local wishlists = {}    -- lower(name) -> { name, at, items = { [itemID] = { spec, enhanced, rank } } }

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

-- specCounts: a player's main- and off-spec tally in one text ("1 MS / 0 OS
-- items"); a single number confused the raid when an off-spec win said 0.
function ns.specCounts(counts, name, token)
    local entry = counts[lower(name)] or {}
    return string.format(token and L["%d MS / %d OS tokens"] or L["%d MS / %d OS items"], entry.ms or 0, entry.os or 0)
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
-- counts for its winner. Items already won in the roll list but not handed
-- out yet count for their winners too (raid of 2026-10-19: loot stayed on the
-- corpse while it was rolled, and the next roll said "0 items so far"), except
-- the entry `except` that is being decided.
local function tallies(tokens, except)
    local counts = {}
    local function add(name, spec)
        local key = lower(name)
        counts[key] = counts[key] or { ms = 0, os = 0 }
        counts[key][spec] = counts[key][spec] + 1
    end
    for _, r in ipairs(ensureDatabase().history) do
        if (r.spec == "ms" or r.spec == "os") and r.state ~= "deleted" and not NO_TALLY[r.state]
            and (r.token and true or false) == (tokens and true or false) then
            add((r.state == "held" and r.winner) or r.recipient, r.spec)
        end
    end
    for _, entry in ipairs(active) do
        if entry ~= except and not entry.free and (isToken(entry.item) and true or false) == (tokens and true or false) then
            for _, w in ipairs(entry.winners or { entry.winner }) do
                if w.kind == "ms" or w.kind == "os" then add(w.name, w.kind) end
            end
        end
    end
    -- Corrections by hand (the tally tab) on top; a tally never drops below 0.
    for key, fix in pairs(ensureDatabase().tallyAdjust or {}) do
        local ms, os = fix[tokens and "tms" or "ms"] or 0, fix[tokens and "tos" or "os"] or 0
        if ms ~= 0 or os ~= 0 then
            counts[key] = counts[key] or { ms = 0, os = 0 }
            counts[key].ms = math.max(0, counts[key].ms + ms)
            counts[key].os = math.max(0, counts[key].os + os)
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
    -- An item the master looter keeps for its roll winner goes to the winner;
    -- the raid hears who won it, not who holds it until the trade.
    local recipient = record.recipient
    if record.state == "held" and record.winner and lower(record.winner) ~= lower(record.recipient) then
        recipient = record.winner
        how = how or string.format(L["with %s until traded"], record.recipient)
    end
    local spec = record.spec and (" - " .. SPEC_NAMES[record.spec]) or ""
    announce(string.format(L["[Loot] %s goes to %s%s%s."], record.item, recipient, spec,
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
    local counts = tallies(isToken(entry.item), entry)
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
    -- A bundle's winners from before a tie-break are not in its latest rolls.
    for _, r in ipairs(entry.winners or {}) do
        if lower(r.name) == lower(name) then return r end
    end
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
    local bundled = (entry.count or 1) > 1
    -- Before this award changes the tallies; a bundle keeps the log of its
    -- decision for every copy (its earlier copies count by now).
    local log = entry.bundleLog or sortedRollLog(entry)
    if bundled then entry.bundleLog = log end
    -- A bundle copy belongs to the roller it was won by.
    if bundled and roll then winner = roll.name end
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
    if bundled then
        -- One copy of a bundle: the rest stays in the loot list for the next
        -- winner (the callers put that name in the box).
        local owner = lower(roll and roll.name or recipient)
        entry.count = entry.count - 1
        entry.awarded = entry.awarded or {}
        entry.awarded[owner] = true
        for i = table.getn(entry.winners or {}), 1, -1 do
            if lower(entry.winners[i].name) == owner then table.remove(entry.winners, i) end
        end
        entry.winner = entry.winners and entry.winners[1]
        publish(record, true)
        return record
    end
    entry.record = record
    publish(record, true)
    for index = table.getn(active), 1, -1 do
        if active[index] == entry then table.remove(active, index) end
    end
    if selected == entry then selected = nil end
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

local stateLabels = { given = L["GIVEN"], held = L["HELD BY YOU"], manual = L["MANUAL"], deleted = L["REMOVED"],
    parked = L["OPEN"], disenchanted = L["DISENCHANT"], bank = L["GUILD BANK"] }

-- The core's functions that do not fit in the main chunk's 200 locals.
local roster = {}

-- roster.denied stops a change by someone who is not an editor (Access.lua)
-- and says why, in the window and in chat.
function roster.denied()
    if not ns.mayEdit or ns.mayEdit() then return false end
    ui.status(ns.deniedText())
    say(ns.deniedText())
    return true
end

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

-- winningRoll is the top counted roll of the last round in a sorted roll log.
local function winningRoll(log)
    local best
    for _, r in ipairs(log) do
        if not r.note and (not best or r.round > best.round) then best = r end
    end
    return best
end

-- openRecords: awards still to be rolled (parked, or kept without a roll),
-- oldest first, except those whose later roll is already in the roll list.
local function openRecords()
    local rolling, list = {}, {}
    for _, entry in ipairs(active) do
        if entry.later and entry.record then rolling[entry.record] = true end
    end
    local history = ensureDatabase().history
    for i = table.getn(history), 1, -1 do
        local record = history[i]
        if isOpenAward(record) and not rolling[record] then table.insert(list, record) end
    end
    return list
end

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
    -- Identical tokens from one corpse are one bundle, rolled once (raid
    -- feedback 2026-10-19), while nothing has been rolled for it yet.
    if isToken(item) then
        for _, other in ipairs(active) do
            if other.window == windowKey and other.item == item and not other.later and not other.rollLog then
                other.count = (other.count or 1) + 1
                drops[key] = other
                lootSlots[slot] = { entry = other, link = item }
                ui.refresh()
                return
            end
        end
    end
    entry = { slot = slot, item = item, npc = windowNpc, rolls = {}, window = windowKey }
    drops[key] = entry
    lootSlots[slot] = { entry = entry, link = item }
    table.insert(active, 1, entry)
    while table.getn(active) > MAX_ACTIVE do table.remove(active) end
    -- New loot needs attention: leave the roll log of an old award.
    if not selectedEntry() then selected = entry end
    ui.refresh()
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
        ui.suggest(entry)   -- a bundle's next winner
    end
    ui.status(string.format(L["Gave #%d to %s; waiting for the loot message."], record.id, name))
    ui.refresh()
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
        -- Only the recorder confirms and announces an award: another ledger in
        -- the group gets the confirmation with the shared record (two ledgers
        -- announced every item twice in the raid of 2026-10-19).
        if not record.confirmed and record.state ~= "deleted" and record.itemID == itemID
            and lower(record.recipient) == lower(name) and lower(record.origin or playerName()) == lower(playerName()) then
            record.confirmed = true
            publish(record)
            ui.status(string.format(L["Award #%d confirmed: %s received the item."], record.id, record.recipient))
            announceAward(record)
            ui.refresh()
            return
        end
    end
end

-- roster.groupLoot records an item won with group loot (need/greed), which
-- happened by accident in the raid of 2026-10-19 and left the ledger without
-- those items. It counts for nobody until an editor sets its spec
-- (/ledger spec). One ledger in the group records it (Access.lua).
function roster.groupLoot(message)
    patterns.rollWon = patterns.rollWon or patternFromFormat(LOOT_ROLL_WON or "%s won: %s")
    patterns.rollYouWon = patterns.rollYouWon or patternFromFormat(LOOT_ROLL_YOU_WON or "You won: %s")
    local name, link
    link = string.match(message or "", patterns.rollYouWon)   -- first: "You won" also fits "%s won"
    if link then name = playerName() else name, link = string.match(message or "", patterns.rollWon) end
    if not name or not itemIDFromLink(link) then return false end
    if ns.isLootRecorder and not ns.isLootRecorder() then return true end
    local record = recordAward({ item = link, npc = lastKill and lastKill.npc, rolls = {} }, name, "given", true)
    record.state = "given"   -- a group-loot win is the winner's own, never held for a trade
    ui.status(string.format(L["Group loot: #%d %s won by %s (no spec; /ledger spec %d ms|os)."],
        record.id, record.item, record.recipient, record.id))
    ui.refresh()
    return true
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
        ui.status(string.format(L["Award #%d traded: %s has the item now."], record.id, record.recipient))
        announceAward(record, L["traded"])
    end
    if table.getn(moved) > 0 then ui.refresh() end
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
    if roster.denied() then return false end
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
    ui.status(string.format(L["Award #%d now goes to %s."], record.id, record.recipient))
    announceAward(record, L["corrected"])
    ui.refresh()
    return true
end

local function deleteRecord(id)
    if roster.denied() then return end
    local record = findRecord(id)
    if not record or record.state == "deleted" then
        say(string.format(L["no award #%s."], tostring(id)))
        return
    end
    record.state = "deleted"
    publish(record)   -- stays selected in VERGABEN, where it can be restored
    ui.status(string.format(L["Award #%d removed; the export keeps it as deleted."], record.id))
    ui.refresh()
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
    -- With an editor list, only editors' ledgers change ours.
    if ns.trusts and not ns.trusts(sender) then return end
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
    -- Not cached yet (item 50667 in the raid of 2026-10-19): ask the server;
    -- the history shows the link once it has arrived.
    if itemID and string.sub(record.item, 1, 5) == "item:" then
        scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
        scanTip:SetHyperlink("item:" .. itemID)
        scanTip:Hide()
    end
    record.recipient, record.state, record.confirmed = f[9], STATES[f[10]] and f[10] or "manual", f[11] == "1"
    record.spec = (f[12] == "ms" or f[12] == "os" or f[12] == "boe") and f[12] or nil
    record.roll, record.low, record.high = tonumber(f[13]), tonumber(f[14]), tonumber(f[15])
    record.winner = f[16] ~= "" and f[16] or nil
    record.rolls, record.token = tonumber(f[17]) or 0, f[18] == "1" or nil
    record.time = f[19] ~= "" and f[19] or date("%H:%M", at)
    -- Our own awards coming back (after a crash): never reuse their numbers.
    if lower(f[3]) == lower(playerName()) then db.nextID = math.max(db.nextID, id) end
    db.startedAt = math.min(db.startedAt or at, at)
    ui.refresh()
end

local function applyLog(f, sender)
    local id, part, total = tonumber(f[4]), tonumber(f[5]), tonumber(f[6])
    if ns.trusts and not ns.trusts(sender) then return end
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
    ui.refresh()
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
    for _, fix in pairs(ensureDatabase().tallyAdjust or {}) do queue(roster.encodeAdjust(fix)) end
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
    if ns.onMessage and ns.onMessage(f, sender) then return end   -- hellos, editors (Access.lua)
    if f[1] == "A" then
        applyRecord(f, sender)
    elseif f[1] == "L" then
        applyLog(f, sender)
    elseif f[1] == "Q" and lower(f[3] or "") == lower(sender) then
        answerSync(sender)
    elseif f[1] == "W" then
        if applyWishlist(f, sender) then ui.refresh() end
    elseif f[1] == "T" then
        roster.applyAdjust(f, sender)
    end
end

---------------------------------------------------------------------------
-- Tally corrections (UI feedback 2026-10-19): editors add or take items per
-- player on top of the awards, e.g. for loot from before the ledger ran. Four
-- counters: items main/off spec (ms, os), tokens main/off spec (tms, tos).
-- Shared as "T;session;name;ms;os;tms;tos;changedAt", reset by a new raid,
-- never in the website export.
---------------------------------------------------------------------------
local ADJUST_KEYS = { "ms", "os", "tms", "tos" }

function roster.encodeAdjust(fix)
    return table.concat({ "T", currentSession(), field(fix.name), fix.ms or 0, fix.os or 0, fix.tms or 0, fix.tos or 0,
        fix.at or 0 }, ";")
end

function roster.adjustments()
    local db = ensureDatabase()
    db.tallyAdjust = db.tallyAdjust or {}
    return db.tallyAdjust
end

-- roster.adjustTally changes one counter of `name` by `delta` (or sets all to
-- 0 with counter "reset").
function roster.adjustTally(name, counter, delta)
    if roster.denied() then return false end
    name = field(trim(name))
    if name == "" then return false end
    local all = roster.adjustments()
    local fix = all[lower(name)] or { name = name, ms = 0, os = 0, tms = 0, tos = 0 }
    if counter == "reset" then
        for _, key in ipairs(ADJUST_KEYS) do fix[key] = 0 end
    else
        fix[counter] = (fix[counter] or 0) + delta
    end
    fix.at = math.max(time(), (fix.at or 0) + 1)
    all[lower(name)] = fix
    queue(roster.encodeAdjust(fix))
    ui.refresh()
    return true
end

function roster.applyAdjust(f, sender)
    if ns.trusts and not ns.trusts(sender) then return end
    local at = tonumber(f[8])
    if not at or (f[3] or "") == "" or not acceptSession(f[2], sender) then return end
    local all = roster.adjustments()
    local key = lower(f[3])
    if all[key] and (all[key].at or 0) >= at then return end
    all[key] = { name = f[3], ms = tonumber(f[4]) or 0, os = tonumber(f[5]) or 0, tms = tonumber(f[6]) or 0,
        tos = tonumber(f[7]) or 0, at = at }
    ui.refresh()
end

function ns.resetTallyAdjustments()
    ensureDatabase().tallyAdjust = {}
end

local function setRaidID(value)
    ensureDatabase().raidID = tonumber(value)
    ui.refresh()
end

-- A new raid starts an empty ledger, so its loot is never exported under the
-- previous raid's ID. Award IDs keep counting up.
local function startNewRaid()
    local db = ensureDatabase()
    db.history = {}
    db.startedAt = nil
    db.raidID = nil
    db.session = nil   -- the next award starts a new shared ledger
    editing = nil
    ns.resetTallyAdjustments()
    say(L["new raid: the award ledger is empty."])
    ui.refresh()
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
        tally = tallyOf(tallies(isToken(entry.item), entry), name, kind) })
    table.sort(entry.rolls, ranksAbove)
    ui.refresh()
end

-- startSelectedRoll starts a roll for the selected item; with `free` a free
-- BoE roll for any character.
local function startSelectedRoll(free)
    if roster.denied() then return end
    local entry = selectedEntry()
    if not entry then
        ui.status(L["Select a master-loot item before starting a roll."])
        return
    end
    entry.free = free and true or nil
    entry.nobody = nil
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
        ui.status(string.format(L["%d-second free BoE roll started."], seconds))
    else
        announce(string.format(L["[Loot] %s - /rnd now! %d seconds. /rnd 100 main spec (enhanced: 1+X to 100+X, X up to 50), /rnd 99 off spec."],
            entry.item, seconds))
        shareRollStart(entry, seconds)
        ui.status(string.format(L["%d-second raid roll started."], seconds))
    end
    ui.refresh()
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
        entry.nobody = true
        announce(string.format(L["[Loot] %s - nobody wanted it."], entry.item))
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
    local counts = tallies(isToken(entry.item), entry)   -- tokens rank by the token tally
    for _, roll in ipairs(entry.rolls) do roll.tally = tallyOf(counts, roll.name, roll.kind) end
    table.sort(entry.rolls, ranksAbove)
    if (entry.count or 1) > 1 and not entry.free then return roster.finishBundle(entry) end
    local best = entry.rolls[1]
    local top = best.value
    local tied = {}
    for _, roll in ipairs(entry.rolls) do
        if roll.kind == best.kind and roll.tally == best.tally and roll.value == top then
            table.insert(tied, roll.name)
        end
    end
    if table.getn(tied) > 1 then
        roster.tieBreak(entry, tied, top)
        return
    end
    entry.winner = entry.rolls[1]
    entry.tieBreak = nil
    ui.suggest(entry)
    if entry.free then
        announce(string.format(L["[Loot] %s - free BoE roll won by %s (%d)."], entry.item, best.name, best.value))
        return
    end
    announce(string.format(L["[Loot] %s won by %s (%d) - %s%s, %s so far."], entry.item, best.name, best.value,
        SPEC_NAMES[best.kind], best.low and best.low > 1 and (" " .. best.low .. "-" .. best.high) or "",
        ns.specCounts(counts, best.name, isToken(entry.item))))
end

-- roster.tieBreak starts a tie-break in which only the `tied` players roll.
function roster.tieBreak(entry, tied, value)
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
        entry.item, joinNames(tied), value, table.concat(tied, ", "), seconds))
    shareRollStart(entry, seconds, tied)
end

-- roster.finishBundle decides a bundle of identical tokens (entry.count
-- copies, raid feedback 2026-10-19): the best rolls win one copy each. A tie
-- matters only where it decides the last copy: the players above it keep
-- their copies (entry.fixed) while the tied players roll for the rest.
-- Players who already received a copy (entry.awarded) are left out.
function roster.finishBundle(entry)
    local function same(a, b) return a.kind == b.kind and a.tally == b.tally and a.value == b.value end
    local fixed, taken = entry.fixed or {}, {}
    for _, r in ipairs(fixed) do taken[string.lower(r.name)] = true end
    for name in pairs(entry.awarded or {}) do taken[name] = true end
    local rolls = {}
    for _, r in ipairs(entry.rolls) do
        if not taken[string.lower(r.name)] then table.insert(rolls, r) end
    end
    local need = entry.count - table.getn(fixed)
    local cut, after = rolls[need], rolls[need + 1]
    if need > 0 and cut and after and same(cut, after) then
        local tied = {}
        for _, r in ipairs(rolls) do
            if same(r, cut) then table.insert(tied, r.name)
            elseif ranksAbove(r, cut) then table.insert(fixed, r) end
        end
        entry.fixed = fixed
        roster.tieBreak(entry, tied, cut.value)
        return
    end
    local winners = {}
    for _, r in ipairs(fixed) do table.insert(winners, r) end
    for i = 1, math.min(math.max(need, 0), table.getn(rolls)) do table.insert(winners, rolls[i]) end
    entry.fixed, entry.tieBreak = nil, nil
    entry.winners, entry.winner = winners, winners[1]
    ui.suggest(entry)
    local names = {}
    for _, r in ipairs(winners) do table.insert(names, string.format("%s (%d)", r.name, r.value)) end
    announce(string.format(L["[Loot] %dx %s won by %s."], entry.count, entry.item, table.concat(names, ", ")))
    if table.getn(winners) < entry.count then
        announce(string.format(L["[Loot] %s - %d left: nobody wanted it."], entry.item, entry.count - table.getn(winners)))
    end
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
    local counts = tallies(isToken(entry.item), entry)
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
    entry.winner, entry.winners, entry.tieBreak, entry.bundleLog = nil, nil, nil, nil
    -- A bundle keeps the copies decided before a tie-break, unless their
    -- player no longer has a counted roll.
    if entry.fixed then
        for i = table.getn(entry.fixed), 1, -1 do
            if not roster.counted(entry, entry.fixed[i].name)[1] then table.remove(entry.fixed, i) end
        end
    end
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
-- award `record` (its roll log in the awards tab). Without a record, the
-- award shown in the awards tab counts when that tab is open (chat commands).
function roster.apply(name, how, points, record)
    if roster.denied() then return end
    record = record or (editing and ui.tab and ui.tab() == "awards" and editing)
    if record then return roster.applyAward(record, name, how, points) end
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
    ui.refresh()
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
        ui.status(string.format(L["Award #%d: no valid roll is left; decide who gets it (DE, BANK or another recipient)."], record.id))
    elseif second and second.kind == best.kind and second.tally == best.tally and second.value == best.value then
        ui.status(string.format(L["Award #%d: %s and %s tie; decide who gets it."], record.id, best.name, second.name))
    elseif lower(best.name) ~= lower(record.recipient or "") then
        setRecipient(record.id, best.name, best)
        return
    else
        record.winner, record.spec = best.name, best.kind
        record.roll, record.low, record.high = best.value, best.low, best.high
    end
    publish(record)
    ui.refresh()
end

function roster.askPoints(name, record)
    local entry = record or selectedEntry()
    local r = entry and roster.counted(entry, name or "")[1]
    roster.points = (r and r.kind == "ms" and r.low and r.low > 1) and (r.low - 1) or 0
    StaticPopup_Show("RAIDLEDGER_POINTS", name, nil, { name = name, record = record })
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
    OnAccept = function(self, data)
        local box = _G[self:GetName() .. "EditBox"]
        local points = tonumber(box and box:GetText() or "")
        if points and points >= 0 and points <= 50 and points == math.floor(points) then
            roster.apply(data.name, "enh", points, data.record)
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
                ui.refresh()
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
    if running and ui.shown() then ui.refresh() end
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
    selected = entry
    ui.show("loot")
    startSelectedRoll()
end

-- Rolls on items in the bags (raider feedback 2026-10-18): Alt+click a bag
-- item, or /ledger roll <item link>. The item is in the roller's bags, so it
-- is an award held by them: an open one for that item is rolled, otherwise a
-- new held award is recorded first. The roll then runs like any later roll,
-- and the winner gets the item by trade.
local function mayStartRolls()
    if ns.hasEditors and ns.hasEditors() then return ns.mayEdit() end   -- the editor list decides
    local raid, party = GetNumRaidMembers() or 0, GetNumPartyMembers() or 0
    if raid == 0 and party == 0 then return true end
    local method, partyMaster, raidMaster = GetLootMethod()
    if method == "master" then
        if raid > 0 and raidMaster and isPlayer(UnitName("raid" .. raidMaster)) then return true end
        if raid == 0 and partyMaster == 0 then return true end
    end
    if raid > 0 then return (IsRaidLeader() or IsRaidOfficer()) and true or false end
    return IsPartyLeader() and true or false
end

-- bagLink finds an item ID's link in the bags (for /ledger roll <itemID>).
local function bagLink(itemID)
    for bag = 0, NUM_BAG_SLOTS or 4 do
        for slot = 1, GetContainerNumSlots(bag) or 0 do
            local link = GetContainerItemLink(bag, slot)
            if itemIDFromLink(link) == itemID then return link end
        end
    end
end

local function rollBagItem(link)
    link = trim(link)
    if string.match(link, "^%d+$") then
        local found = bagLink(tonumber(link))
        if not found then
            say(string.format(L["item %s is not in your bags."], link))
            return
        end
        link = found
    end
    local itemID = itemIDFromLink(link)
    if not itemID then
        say(L["usage: /ledger roll <item link> (or Alt+click the item in your bags)"])
        return
    end
    if not mayStartRolls() then
        say(ns.hasEditors and ns.hasEditors() and ns.deniedText() or L["only the master looter or the raid lead can start rolls."])
        return
    end
    ui.show("loot")
    for _, entry in ipairs(active) do
        if entry.later and entry.record and entry.record.itemID == itemID and entry.endsAt and not entry.winner then
            selected, editing = entry, nil
            ui.refresh()
            ui.status(string.format(L["%s is already being rolled."], entry.item))
            return
        end
    end
    local record
    for _, r in ipairs(ensureDatabase().history) do
        if r.itemID == itemID and isOpenAward(r) and isPlayer(r.recipient) then
            record = r
            break
        end
    end
    record = record or recordAward({ item = link, rolls = {} }, playerName(), "held", true)
    startLaterRoll(record)
end
ns.rollBagItem = rollBagItem

if ContainerFrameItemButton_OnModifiedClick then
    hooksecurefunc("ContainerFrameItemButton_OnModifiedClick", function(self, button)
        if button ~= "LeftButton" or not IsAltKeyDown() or IsShiftKeyDown() or IsControlKeyDown() then return end
        rollBagItem(GetContainerItemLink(self:GetParent():GetID(), self:GetID()))
    end)
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
    ui.status(string.format(L["Award #%d goes to %s (%s)."], record.id, record.winner, how))
    ui.refresh()
end

-- Actions on loot and awards. The window passes the name from its box; every
-- action returns true when it did something, so the window can clear the box.

-- handOut gives the selected loot item to `holder` as `state` ("given",
-- "parked", "disenchanted", "bank"): through the master-loot window when the
-- item is still in it (the GiveMasterLoot hook records it), else recorded by hand.
local function handOut(holder, state)
    local entry = selectedEntry()
    if not entry or (entry.later and state ~= "given") then
        ui.status(L["Select a loot item first."])
        return false
    end
    if entry.later then
        finishLaterRoll(entry, holder)
        return true
    end
    local slot = lootSlotOf(entry)
    if slot then
        local index = candidateIndex(holder)
        if not index then
            ui.status(string.format(L["%s cannot receive this item (not a master-loot candidate)."], holder))
            return false
        end
        if state ~= "given" then parkSlots[slot] = state end
        GiveMasterLoot(slot, index)
        return true
    end
    local record = recordAward(entry, holder, state == "given" and "manual" or state, true)
    announceAward(record)
    if state == "parked" then
        ui.status(string.format(L["Award #%d is open, held by %s until it is rolled."], record.id, holder))
    elseif NO_TALLY[state] then
        ui.status(string.format(L["Award #%d: %s (%s)."], record.id, stateLabels[state], holder))
    else
        ui.status(string.format(L["Award #%d recorded for %s."], record.id, holder))
    end
    ui.suggest(entry)   -- a bundle's next winner
    ui.refresh()
    return true
end

-- roster.giveSelected: GIVE + RECORD for the selected loot item.
function roster.giveSelected(name)
    if roster.denied() then return false end
    name = trim(name)
    if not selectedEntry() then
        ui.status(L["Select a loot roll before recording an award."])
        return false
    end
    if name == "" then
        ui.status(L["Choose or enter a recipient name."])
        return false
    end
    return handOut(name, "given")
end

-- roster.parkSelected / roster.giveAwaySelected: PARK, DE and BANK for the
-- selected loot item; without a name the item stays with you.
function roster.parkSelected(name)
    if roster.denied() then return false end
    name = trim(name)
    return handOut(name ~= "" and name or playerName(), "parked")
end

function roster.giveAwaySelected(state, name)
    if roster.denied() then return false end
    name = trim(name)
    return handOut(name ~= "" and name or playerName(), state)
end

-- roster.parkRecord marks a recorded award as parked with `name` (else its
-- current holder) until it is rolled; an open award is rolled instead.
function roster.parkRecord(record, name)
    if roster.denied() then return false end
    if isOpenAward(record) then
        startLaterRoll(record)
        return true
    end
    if record.state == "deleted" then
        ui.status(L["Restore the award before parking it."])
        return false
    end
    name = trim(name)
    record.recipient = field(name ~= "" and name or record.recipient)
    record.state, record.winner, record.spec, record.roll = "parked", nil, nil, nil
    record.low, record.high, record.confirmed = nil, nil, true
    publish(record)
    announceAward(record)
    ui.status(string.format(L["Award #%d is open, held by %s until it is rolled."], record.id, record.recipient))
    ui.refresh()
    return true
end

-- roster.giveAwayRecord marks a recorded award for disenchanting or the bank.
function roster.giveAwayRecord(record, state, name)
    if roster.denied() then return false end
    name = trim(name)
    record.recipient = field(name ~= "" and name or record.recipient)
    record.state, record.winner, record.confirmed = state, nil, true
    record.roll, record.spec, record.low, record.high = nil, nil, nil, nil
    publish(record)
    announceAward(record)
    ui.status(string.format(L["Award #%d: %s (%s)."], record.id, stateLabels[state], record.recipient))
    ui.refresh()
    return true
end

-- roster.changeRecipient gives a recorded (or removed) award to `name`.
function roster.changeRecipient(record, name)
    name = trim(name)
    if name == "" then
        ui.status(L["Enter the new recipient's name."])
        return false
    end
    return setRecipient(record.id, name) and true or false
end

-- roster.setSpec moves an award to the main- or off-spec tally, or out of it.
function roster.setSpec(record, spec)
    if roster.denied() then return false end
    record.spec = (spec == "ms" or spec == "os") and spec or nil
    publish(record)
    ui.status(string.format(L["award #%d counts for %s."], record.id, record.spec and SPEC_NAMES[record.spec] or L["no tally"]))
    ui.refresh()
    return true
end

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
        ui.refresh()
    elseif event == "LOOT_OPENED" or event == "LOOT_READY" then
        captureMasterLoot()
        ui.refresh()
    elseif event == "LOOT_CLOSED" then
        lootSlots = {}
        windowKey, windowNpc = nil, nil
        ui.refresh()
    elseif event == "CHAT_MSG_SYSTEM" then
        recordRoll(...)
    elseif event == "CHAT_MSG_LOOT" then
        if not roster.groupLoot(...) then onLootMessage(...) end
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
        ui.refresh()
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

-- roster.clearActive drops every item from the loot list (not the awards).
function roster.clearActive()
    for i = table.getn(active), 1, -1 do table.remove(active, i) end
    selected = nil
    drops = {}
    lootSlots = {}
    ui.refresh()
end

-- roster.setTimers sets the roll and tie-break lengths for new rolls (nil keeps
-- one, "reset" both); false when a length is outside its limits.
function roster.setTimers(roll, tie)
    local db = ensureDatabase()
    if roll == "reset" then
        db.rollSeconds, db.tieSeconds = nil, nil
        return true
    end
    if (roll and (roll ~= math.floor(roll) or roll < ROLL_LIMITS[1] or roll > ROLL_LIMITS[2]))
        or (tie and (tie ~= math.floor(tie) or tie < TIE_LIMITS[1] or tie > TIE_LIMITS[2])) then
        return false
    end
    if roll then db.rollSeconds = roll ~= ROLL_SECONDS and roll or nil end
    if tie then db.tieSeconds = tie ~= TIE_SECONDS and tie or nil end
    return true
end

-- Shared helpers for the window (UI.lua and the tabs), Raid.lua and Access.lua.
ns.ensureDatabase, ns.say, ns.field, ns.trim, ns.lower = ensureDatabase, say, field, trim, lower
ns.playerName, ns.isPlayer, ns.patternFromFormat = playerName, isPlayer, patternFromFormat
ns.setStatus = function(text) ui.status(text) end
ns.raidID = function() return ensureDatabase().raidID end
ns.setRaidID = setRaidID
ns.historyCount = function() return table.getn(ensureDatabase().history) end
ns.queue, ns.groupChannel, ns.members = queue, groupChannel, roster.members
ns.commands = {}   -- chat commands of the other files: /ledger <name> ...
ns.help = {}

-- ns.core: what the window reads and does. State stays here; the window only
-- draws it and passes names typed or clicked.
ns.core = {
    roster = roster, L = L, SPEC_NAMES = SPEC_NAMES, stateLabels = stateLabels, NO_TALLY = NO_TALLY,
    ROLL_LIMITS = ROLL_LIMITS, TIE_LIMITS = TIE_LIMITS, MAX_ACTIVE = MAX_ACTIVE, EXPORT_FORMAT = EXPORT_FORMAT,
    active = function() return active end,
    history = function() return ensureDatabase().history end,
    selectedEntry = selectedEntry,
    editing = function() return editing end,
    select = function(entry) selected = entry end,
    edit = function(record) editing = record end,
    openRecords = openRecords, lootSlotOf = lootSlotOf, activeRollCount = activeRollCount,
    sortedRollLog = sortedRollLog, tallies = tallies, tallyOf = tallyOf, isToken = isToken,
    rollLabel = rollLabel, itemCount = itemCount, ranksAbove = ranksAbove, winningRoll = winningRoll,
    wishersOf = wishersOf, wishOf = wishOf, knowsWishlists = knowsWishlists, summaryLine = summaryLine,
    isOpenAward = isOpenAward, itemIDFromLink = itemIDFromLink, findRecord = findRecord, isActive = isActive,
    rollSeconds = rollSeconds, tieSeconds = tieSeconds,
    startRoll = function(free) if free then startFreeRoll() else startSelectedRoll() end end,
    startLaterRoll = function(record) if not roster.denied() then startLaterRoll(record) end end,
    deleteRecord = deleteRecord,
    newRaid = startNewRaid,
    -- Shared awards of items this client had not cached yet (item 50667 in the
    -- raid of 2026-10-19) get their link once the item is known.
    refreshLinks = function()
        for _, record in ipairs(ensureDatabase().history) do
            if string.sub(record.item or "", 1, 5) == "item:" then
                record.item = select(2, GetItemInfo(record.itemID or 0)) or record.item
            end
        end
    end,
    sync = function()
        if not groupChannel() then
            say(L["not in a group: nothing to sync."])
            return
        end
        requestSync()
        say(L["asked the group's ledgers for this raid's awards."])
    end,
    export = function()
        local db = ensureDatabase()
        if not db.raidID then return nil end
        return buildExport(db.raidID, playerName(), db.startedAt, time(), db.history)
    end,
}
local HELP = {
    L["/ledger - show or hide the ledger"],
    L["/ledger start - start a %d s /rnd roll for the selected item"],
    L["/ledger timer [seconds] [tie-break seconds] - roll lengths for new rolls; /ledger timer reset"],
    L["/ledger free - post the selected item again: free BoE roll for any character (/rnd 100)"],
    L["/ledger roll <item link or ID> - roll an item from your bags (or Alt+click it in your bags)"],
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
        ui.resetPosition()
    elseif command == "clear" then
        roster.clearActive()
    elseif command == "start" then
        startSelectedRoll()
    elseif command == "roll" then
        rollBagItem(rest)
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
        if roster.denied() then return end
        local id, spec = rest:match("^#?(%d+)%s+(%a+)$")
        spec = spec and string.lower(spec)
        local record = id and findRecord(tonumber(id))
        if not record or (spec ~= "ms" and spec ~= "os" and spec ~= "none") then
            say(L["usage: /ledger spec <#> ms|os|none"])
        else
            record.spec = spec ~= "none" and spec or nil
            publish(record)
            say(string.format(L["award #%d counts for %s."], record.id, record.spec and SPEC_NAMES[record.spec] or L["no tally"]))
            ui.refresh()
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
            local known = {}
            for _, record in ipairs(ensureDatabase().history) do
                table.insert(known, (record.state == "held" and record.winner) or record.recipient)
            end
            for _, fix in pairs(roster.adjustments()) do table.insert(known, fix.name) end   -- corrected only
            for _, name in ipairs(known) do
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
            say(string.format(L["raid ID %s."], id))
        else
            say(L["usage: /ledger raid <id>"])
        end
    elseif command == "export" then
        ui.show("export")
    elseif command == "newraid" then
        if string.lower(rest) == "confirm" then startNewRaid() else StaticPopup_Show("RAIDLEDGER_NEW_RAID") end
    elseif command == "" or command == "toggle" then
        ui.toggle()
    elseif ns.commands[command] then
        ns.commands[command](rest)
    else
        for _, line in ipairs(HELP) do say(string.format(line, rollSeconds())) end
        for _, line in ipairs(ns.help) do say(line) end
    end
end

