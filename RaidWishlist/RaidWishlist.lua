-- SPDX-License-Identifier: GPL-2.0-only
-- RaidWishlist: the raid member's side of RaidLedger, for WoW 3.3.5a / Lua 5.1.
-- Imports the wishlist exported by the guild website (WL2), offers a one-click
-- roll (or rolls automatically) when the raid lead's ledger starts a roll on a
-- wishlisted item, and shows who got what this raid from the ledger's shared
-- awards (addon messages, prefix FLLedger).
local addonName, ns = ...
local L = ns.L
local Wishlist = CreateFrame("Frame", "RaidWishlistFrame", UIParent)
local PREFIX = "FLLedger"
local AUTO_DELAY = 1        -- seconds before an automatic roll
local SPEC_LABELS = { ms = "MS", os = "OS" }
local DEFAULT_REMINDER_KEYWORDS = "roll,würfel"
-- Disenchanted or banked items have a holder but count for nobody.
local NO_TALLY = { disenchanted = true, bank = true }
local TOKEN_NAMES = { "Weiheabzeichen" }

local prompt                -- the open roll prompt { key, entry, endsAt }
local pendingRoll           -- an automatic roll waiting for its delay
local rolled = {}           -- rollKey:round -> true, so every roll happens once
local syncAt
local shareAt               -- when to send this wishlist to the group
local helloAt               -- when to tell the ledgers this addon's version (HW)
local WISHES_PER_MESSAGE = 15

local function trim(value)
    return (value or ""):match("^%s*(.-)%s*$")
end

local function lower(value)
    return string.lower(value or "")
end

-- Lua 5.1 lowercases ASCII only. The catalogue needs the German letters too,
-- while still treating search text as literal text rather than a pattern.
local function catalogueLower(value)
    value = string.lower(value or "")
    value = string.gsub(value, "Ä", "ä")
    value = string.gsub(value, "Ö", "ö")
    value = string.gsub(value, "Ü", "ü")
    return string.gsub(value, "ẞ", "ß")
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

-- An item the client has never seen has no name yet: GetItemInfo answers only
-- from the client's cache and 3.3.5a has no event when an item arrives. A
-- hidden tooltip asks the server; the ticker redraws once the names are there.
local itemScan = CreateFrame("GameTooltip", "RaidWishlistItemScan", UIParent, "GameTooltipTemplate")
local askedItems = {}      -- itemID -> GetTime() of the last request, until it arrived
local function itemLink(itemID)
    local link = itemID and select(2, GetItemInfo(itemID))
    if link then return link end
    if itemID and (not askedItems[itemID] or GetTime() - askedItems[itemID] > 30) then
        askedItems[itemID] = GetTime()
        itemScan:SetOwner(UIParent, "ANCHOR_NONE")
        itemScan:SetHyperlink("item:" .. itemID)
    end
    return string.format(L["[Item %d]"], itemID or 0)
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

local function reminderKeywords(char)
    return char.reminderKeywords or DEFAULT_REMINDER_KEYWORDS
end

-- Keywords count only outside item links: "[Trollbane]" is no "roll".
local function matchingReminderKeyword(message, char)
    local text = lower((string.gsub(message, "|H.-|h.-|h", "")))
    for keyword in string.gmatch(reminderKeywords(char), "[^,]+") do
        if keyword ~= "" and string.find(text, lower(keyword), 1, true) then return true end
    end
    return false
end

local MAX_ENHANCED = 50     -- X = min(EP, 50), the website's rule

-- currentBalance is the EP balance from the last export or typed value, minus
-- what enhanced wins since then cost. enhancedPoints is X for an enhanced
-- main-spec roll: that balance, at most 50.
local function currentBalance(char)
    local balance = char.balance or 0
    for _, spent in pairs(char.spent or {}) do balance = balance - spent end
    return math.max(0, balance)
end

local function enhancedPoints(char)
    return math.min(currentBalance(char), MAX_ENHANCED)
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
    -- balanceAt, not exportedAt: editing a wish makes a new list version but
    -- not a new balance (lists saved before 2.3.0 have only exportedAt).
    if mine and low and high == low + 99 and low > 1 and award.at >= (char.balanceAt or char.exportedAt or 0) then
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
-- Theme: the window looks like RaidLedger's, but every color derives from one
-- accent the player picks (color button, /wish color). The pick is shared by
-- all characters; too dark a pick is brightened so the text stays readable.
local DEFAULT_ACCENT = { 0.40, 0.88, 0.48 }
local palette = {}
local themed = {}           -- { object, kind, key, alpha }

local function computePalette(red, green, blue)
    local top = math.max(red, green, blue)
    if top < 0.05 then red, green, blue = 1, 1, 1 else red, green, blue = red / top, green / top, blue / top end
    local function scale(k, add)
        add = add or 0
        return { red * k + add, green * k + add, blue * k + add }
    end
    local function mix(t, base)
        base = base or 1
        return { red + (base - red) * t, green + (base - green) * t, blue + (base - blue) * t }
    end
    return {
        accent = { red, green, blue }, border = scale(0.81),
        frame = scale(0.045, 0.007), pane = scale(0.085, 0.012), back = scale(0.02, 0.005),
        button = scale(0.30, 0.01), buttonOn = scale(0.50, 0.02), close = scale(0.14, 0.05),
        row = scale(0.24), rowMine = scale(0.36),
        title = mix(0.4), buttonText = mix(0.65), text = mix(0.78), soft = mix(0.5, 0.55),
        dim = mix(0.6, 0.5), faint = mix(0.68, 0.42),
    }
end

local function paint(entry)
    local object, kind, key, alpha = entry[1], entry[2], entry[3], entry[4]
    local color = palette[key]
    if kind == "backdrop" then
        object:SetBackdropColor(color[1], color[2], color[3], alpha)
        object:SetBackdropBorderColor(palette.border[1], palette.border[2], palette.border[3], 0.92)
    elseif kind == "text" then
        object:SetTextColor(color[1], color[2], color[3])
    elseif kind == "texture" then
        object:SetVertexColor(color[1], color[2], color[3], alpha or 1)
    end
end

local function themeColor(object, kind, key, alpha)
    local entry = { object, kind, key, alpha }
    table.insert(themed, entry)
    if palette[key] then paint(entry) end
end

palette = computePalette(DEFAULT_ACCENT[1], DEFAULT_ACCENT[2], DEFAULT_ACCENT[3])

local function makeBackdrop(frame, key, alpha)
    frame:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    themeColor(frame, "backdrop", key, alpha)
end

-- color is a palette key (follows the theme) or a fixed {r, g, b}.
local function label(parent, template, size, color, name)
    local text = parent:CreateFontString(name, "OVERLAY", template)
    if size then text:SetFont(STANDARD_TEXT_FONT, size) end
    if type(color) == "string" then
        themeColor(text, "text", color)
    elseif color then
        text:SetTextColor(color[1], color[2], color[3])
    end
    return text
end

-- InputBoxTemplate draws its left border 5 px left of the edit box; boxes
-- sit this far in so the border lines up with the labels above them.
local INPUT_INSET = 5

local function flatButton(parent, name, caption, width, height)
    local button = CreateFrame("Button", name, parent)
    button:SetWidth(width)
    button:SetHeight(height or 22)
    makeBackdrop(button, "button", 0.98)
    local text = label(button, "GameFontNormal", 10, "buttonText")
    text:SetPoint("CENTER", button, "CENTER", 0, 0)
    button:SetFontString(text)
    button:SetText(caption)
    return button
end

-- listRow is one line of a list: the item on the left, then `columns`
-- ({ key, width, color, justify }) on the right; row.columns[key] holds their
-- texts (named <row name><Key>, e.g. RaidWishlistRaid1Recipient).
local function listRow(parent, index, columns, name)
    local row = CreateFrame("Button", name, parent)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, -28 - (index - 1) * 17)
    row:SetPoint("RIGHT", parent, "RIGHT", -8, 0)
    row:SetHeight(16)
    row:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground" })
    row:SetBackdropColor(0, 0, 0, 0)
    row.columns = {}
    local right = -5
    for i = table.getn(columns), 1, -1 do
        local column = columns[i]
        local key = column[1]
        local text = label(row, "GameFontNormalSmall", 9, column[3] or {1.00, 0.82, 0.30},
            name .. string.upper(string.sub(key, 1, 1)) .. string.sub(key, 2))
        text:SetPoint("RIGHT", row, "RIGHT", right, 0)
        text:SetWidth(column[2])
        text:SetJustifyH(column[4] or "RIGHT")
        text:SetWordWrap(false)
        row.columns[key] = text
        right = right - column[2] - 8
    end
    local text = label(row, "GameFontNormalSmall", 10, "text")
    text:SetPoint("LEFT", row, "LEFT", 5, 0)
    text:SetPoint("RIGHT", row, "RIGHT", right, 0)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    row:SetFontString(text)
    return row
end

local RAID_NAMES = {
    NAXX = L["Naxxramas"], OS = L["Obsidian Sanctum"], EOE = L["Eye of Eternity"],
    ULD = L["Ulduar"], TOC = L["Trial of the Crusader"], ONY = L["Onyxia's Lair"],
    ICC = L["Icecrown Citadel"], RS = L["Ruby Sanctum"],
}

local function catalogueName(record)
    return GetLocale() == "deDE" and record[4] or record[3]
end

local function catalogueRaidNames(record)
    local raids = {}
    for code in string.gmatch(record[2], "[^,]+") do table.insert(raids, RAID_NAMES[code] or code) end
    return table.concat(raids, ", ")
end

-- The default and smallest size; users may make it larger and scale it
-- (raider feedback 2026-10-24: high- and low-resolution clients).
local WIDTH, HEIGHT = 500, 440
Wishlist:SetWidth(WIDTH)
Wishlist:SetHeight(HEIGHT)
Wishlist:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
Wishlist:SetResizable(true)
Wishlist:SetMinResize(WIDTH, HEIGHT)
Wishlist:SetFrameStrata("DIALOG")
Wishlist:SetClampedToScreen(true)
Wishlist:EnableMouse(true)
Wishlist:SetMovable(true)
Wishlist:RegisterForDrag("LeftButton")
Wishlist:SetScript("OnDragStart", function(self) self:StartMoving() end)
Wishlist:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
makeBackdrop(Wishlist, "frame", 0.97)
-- Raise above RaidLedger (same strata) when shown or clicked, so the two
-- windows never draw through each other.
Wishlist:SetToplevel(true)
Wishlist:SetScript("OnShow", function(self) self:Raise() end)
Wishlist:Hide()

-- Header as in RaidLedger: accent line, the addon's name, buttons on the right.
local accent = Wishlist:CreateTexture(nil, "ARTWORK")
accent:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
accent:SetPoint("TOPLEFT", Wishlist, "TOPLEFT", 10, -9)
accent:SetPoint("TOPRIGHT", Wishlist, "TOPRIGHT", -10, -9)
accent:SetHeight(2)
themeColor(accent, "texture", "accent", 0.95)

local title = label(Wishlist, "GameFontNormalLarge", 17, "title")
title:SetPoint("TOPLEFT", Wishlist, "TOPLEFT", 18, -18)
title:SetText("RaidWishlist")   -- the addon's name, not translated

local close = CreateFrame("Button", "RaidWishlistClose", Wishlist)
close:SetWidth(24)
close:SetHeight(24)
close:SetPoint("TOPRIGHT", Wishlist, "TOPRIGHT", -13, -14)
makeBackdrop(close, "close", 0.95)
local closeText = label(close, "GameFontNormal", 14, "soft")
closeText:SetPoint("CENTER", close, "CENTER", 0, 0)
closeText:SetText("X")
close:SetScript("OnClick", function() Wishlist:Hide() end)

local importOpen = flatButton(Wishlist, "RaidWishlistImportOpen", L["IMPORT"], 70, 24)
importOpen:SetPoint("RIGHT", close, "LEFT", -8, 0)

local autoButton = flatButton(Wishlist, "RaidWishlistAuto", L["AUTO-ROLL: OFF"], 120, 24)
autoButton:SetPoint("RIGHT", importOpen, "LEFT", -6, 0)

-- Color button: a swatch of the current accent; opens the color picker.
local colorButton = CreateFrame("Button", "RaidWishlistColor", Wishlist)
colorButton:SetWidth(24)
colorButton:SetHeight(24)
colorButton:SetPoint("RIGHT", autoButton, "LEFT", -6, 0)
colorButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
makeBackdrop(colorButton, "close", 0.95)
local swatch = colorButton:CreateTexture(nil, "ARTWORK")
swatch:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
swatch:SetPoint("TOPLEFT", colorButton, "TOPLEFT", 6, -6)
swatch:SetPoint("BOTTOMRIGHT", colorButton, "BOTTOMRIGHT", -6, 6)
themeColor(swatch, "texture", "accent")

local editOpen = flatButton(Wishlist, "RaidWishlistEditOpen", L["EDIT"], 66, 24)
editOpen:SetPoint("RIGHT", colorButton, "LEFT", -6, 0)

---------------------------------------------------------------------------
-- Tabs (2.0, raid feedback 2026-10-20 "you cannot scroll down the loot"):
-- one full-height list per tab, each scrolling with the mouse wheel, instead
-- of three short stacked lists.
---------------------------------------------------------------------------
local tabBar = CreateFrame("Frame", nil, Wishlist)
tabBar:SetPoint("TOPLEFT", Wishlist, "TOPLEFT", 12, -44)
tabBar:SetPoint("RIGHT", Wishlist, "RIGHT", -12, 0)
tabBar:SetHeight(22)

local CONTENT_TOP, CONTENT_BOTTOM = -72, 30
local content = CreateFrame("Frame", nil, Wishlist)
content:SetPoint("TOPLEFT", Wishlist, "TOPLEFT", 12, CONTENT_TOP)
content:SetPoint("BOTTOMRIGHT", Wishlist, "BOTTOMRIGHT", -12, CONTENT_BOTTOM)

-- Each list shows as many rows (17 px) as its pane holds: 17 at the default size.
local function rowsFit(height) return math.max(1, math.floor((height - 28 - 21) / 17)) end
local lists = {}            -- id -> { pane, rows, offset, count, position, heading, empty, tab }
local listOrder = {}
local currentList

local function addList(id, name, caption, columns, emptyText)
    local pane = CreateFrame("Frame", name .. "Pane", content)
    pane:SetAllPoints(content)
    makeBackdrop(pane, "pane", 0.97)
    pane:Hide()
    local list = { id = id, pane = pane, rows = {}, pool = {}, offset = 0, count = 0, caption = caption }
    list.heading = label(pane, "GameFontNormal", 11, {1.00, 0.82, 0.32})
    list.heading:SetPoint("TOPLEFT", pane, "TOPLEFT", 12, -10)
    list.empty = label(pane, "GameFontNormalSmall", 11, "dim")
    list.empty:SetPoint("CENTER", pane, "CENTER", 0, -8)
    list.empty:SetJustifyH("CENTER")
    list.empty:SetText(emptyText)
    -- list.fit(n) makes the first n rows of the pool the list and hides the rest.
    function list.fit(count)
        for i = 1, math.max(count, table.getn(list.pool)) do
            if i <= count then
                list.pool[i] = list.pool[i] or listRow(pane, i, columns, name .. i)
                list.rows[i] = list.pool[i]
            else
                list.rows[i] = nil
                list.pool[i]:Hide()
            end
        end
    end
    list.fit(rowsFit(HEIGHT + CONTENT_TOP - CONTENT_BOTTOM))
    list.position = label(pane, "GameFontNormalSmall", 9, "faint", name .. "Position")
    list.position:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", -12, 7)
    list.position:SetJustifyH("RIGHT")
    pane:EnableMouseWheel(true)
    pane:SetScript("OnMouseWheel", function(_, delta)
        list.offset = math.max(0, math.min(list.offset - delta * 3, list.count - table.getn(list.rows)))
        if list.draw then list.draw() end
    end)
    local tab = flatButton(tabBar, "RaidWishlistTab" .. id, "", 110, 22)
    tab:SetScript("OnClick", function() lists.show(id) end)
    list.tab = tab
    lists[id] = list
    table.insert(listOrder, list)
    return list
end

local settingsOpen = flatButton(tabBar, "RaidWishlistSettingsOpen", L["SETTINGS"], 90, 22)
settingsOpen:SetPoint("TOPRIGHT", tabBar, "TOPRIGHT", 0, 0)

-- place sets how many entries a list has, clamps its offset and says which
-- of them are shown; the rows then show entries offset+1 .. offset+(rows).
local function place(list, count)
    local rows = table.getn(list.rows)
    list.count = count
    list.offset = math.max(0, math.min(list.offset, count - rows))
    if count > 0 then list.empty:Hide() else list.empty:Show() end
    if count > rows then
        list.position:SetText(string.format(L["%d-%d / %d  (mouse wheel)"], list.offset + 1,
            math.min(count, list.offset + rows), count))
    else
        list.position:SetText("")
    end
end

local function drawTabs()
    local x = 0
    for _, list in ipairs(listOrder) do
        local tab = list.tab
        tab:SetText(list.caption(list.count))
        tab:SetWidth(math.max(90, (tab:GetTextWidth() or 60) + 24))
        tab:ClearAllPoints()
        tab:SetPoint("TOPLEFT", tabBar, "TOPLEFT", x, 0)
        x = x + tab:GetWidth() + 4
        local color = list == currentList and palette.buttonOn or palette.button
        tab:SetBackdropColor(color[1], color[2], color[3], 0.98)
    end
end

function lists.show(id)
    local _, char = ensureDatabase()
    currentList = lists[id] or lists.wish
    char.tab = currentList.id
    for _, list in ipairs(listOrder) do
        if list == currentList then list.pane:Show() else list.pane:Hide() end
    end
    drawTabs()
end

local function counted(caption)
    return function(count) return count > 0 and string.format("%s (%d)", caption, count) or caption end
end

local wishList = addList("wish", "RaidWishlistWish", counted(L["WISHLIST"]),
    { { "note", 140, "dim", "LEFT" }, { "range", 70 } },
    L["No wishlist yet.\nCopy the export on the guild website, then IMPORT."])
local openList = addList("open", "RaidWishlistOpen", counted(L["OPEN"]),
    { { "where", 110, "soft", "LEFT" }, { "tag", 130 } },
    L["No loot is waiting to be rolled."])
local raidList = addList("raid", "RaidWishlistRaid", counted(L["THIS RAID"]),
    { { "recipient", 100, "text", "LEFT" }, { "tag", 70 } },
    L["Nothing handed out yet.\nAwards appear here when the raid lead uses RaidLedger."])
local wishRows, openRows, raidRows = wishList.rows, openList.rows, raidList.rows

local tallyText = label(raidList.pane, "GameFontNormalSmall", 9, "faint")
tallyText:SetPoint("TOPRIGHT", raidList.pane, "TOPRIGHT", -12, -11)
tallyText:SetJustifyH("RIGHT")

local status = label(Wishlist, "GameFontNormalSmall", 10, "faint")
status:SetPoint("BOTTOMLEFT", Wishlist, "BOTTOMLEFT", 16, 12)
status:SetJustifyH("LEFT")
status:SetWordWrap(false)
status:SetText(L["Rolls start from the raid lead's RaidLedger  |  /wish help"])

-- Import overlay: takes the place of the tabs and lists while shown.
local importPanel = CreateFrame("Frame", "RaidWishlistImportPanel", Wishlist)
importPanel:SetPoint("TOPLEFT", Wishlist, "TOPLEFT", 12, -44)
importPanel:SetPoint("BOTTOMRIGHT", Wishlist, "BOTTOMRIGHT", -12, CONTENT_BOTTOM)
makeBackdrop(importPanel, "pane", 0.99)
importPanel:SetFrameLevel(Wishlist:GetFrameLevel() + 5)
importPanel:Hide()

local importHint = label(importPanel, "GameFontNormalSmall", 10, "soft")
importHint:SetPoint("TOPLEFT", importPanel, "TOPLEFT", 12, -12)
importHint:SetText(L["Paste your wishlist export from the guild website (Ctrl+V):"])

local importBack = CreateFrame("Frame", nil, importPanel)
importBack:SetPoint("TOPLEFT", importPanel, "TOPLEFT", 10, -32)
importBack:SetPoint("BOTTOMRIGHT", importPanel, "BOTTOMRIGHT", -10, 42)
makeBackdrop(importBack, "back", 0.98)

local importScroll = CreateFrame("ScrollFrame", nil, importBack)
importScroll:SetPoint("TOPLEFT", importBack, "TOPLEFT", 8, -8)
importScroll:SetPoint("BOTTOMRIGHT", importBack, "BOTTOMRIGHT", -8, 8)

local importText = CreateFrame("EditBox", "RaidWishlistImportText", importScroll)
importText:SetMultiLine(true)
importText:SetAutoFocus(false)
importText:SetFontObject(ChatFontNormal)
importText:SetWidth(WIDTH - 60)
importText:SetHeight(HEIGHT - 200)
importScroll:SetScrollChild(importText)
importText:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
-- A multi-line edit box is only as tall as its text, so a click below the
-- last line would miss it: the whole field takes the click and focuses it.
local function focusImport()
    importText:SetFocus()
    importText:SetCursorPosition(string.len(importText:GetText() or ""))
end
importBack:EnableMouse(true)
importBack:SetScript("OnMouseDown", focusImport)
importScroll:EnableMouse(true)
importScroll:SetScript("OnMouseDown", focusImport)

local importButton = flatButton(importPanel, "RaidWishlistImportButton", L["IMPORT WISHLIST"], 130, 24)
importButton:SetPoint("BOTTOMRIGHT", importPanel, "BOTTOMRIGHT", -10, 10)
local importCancel = flatButton(importPanel, nil, L["CANCEL"], 80, 24)
importCancel:SetPoint("RIGHT", importButton, "LEFT", -6, 0)

-- Manual entries use the same stored format as website imports, so sharing,
-- rolling and raid tallies need no separate path.
local editorPanel = CreateFrame("Frame", "RaidWishlistEditorPanel", Wishlist)
editorPanel:SetPoint("TOPLEFT", Wishlist, "TOPLEFT", 12, -44)
editorPanel:SetPoint("BOTTOMRIGHT", Wishlist, "BOTTOMRIGHT", -12, CONTENT_BOTTOM)
makeBackdrop(editorPanel, "pane", 0.99)
editorPanel:SetFrameLevel(Wishlist:GetFrameLevel() + 5)
editorPanel:Hide()
local editorTitle = label(editorPanel, "GameFontNormal", 12, {1.00, 0.82, 0.32})
editorTitle:SetPoint("TOPLEFT", editorPanel, "TOPLEFT", 12, -12)
editorTitle:SetText(L["EDIT WISHLIST"])
local editorItemLabel = label(editorPanel, "GameFontNormalSmall", 10, "soft")
editorItemLabel:SetPoint("TOPLEFT", editorPanel, "TOPLEFT", 12, -206)
editorItemLabel:SetText(L["Item ID (manual fallback)"])
local editorItem = CreateFrame("EditBox", "RaidWishlistEditorItem", editorPanel, "InputBoxTemplate")
editorItem:SetAutoFocus(false)
editorItem:SetMaxLetters(8)
editorItem:SetWidth(115)
editorItem:SetHeight(22)
editorItem:SetPoint("TOPLEFT", editorPanel, "TOPLEFT", 12 + INPUT_INSET, -222)
local catalogueSearchLabel = label(editorPanel, "GameFontNormalSmall", 10, "soft")
catalogueSearchLabel:SetPoint("TOPLEFT", editorPanel, "TOPLEFT", 12, -42)
catalogueSearchLabel:SetText(L["Search item name"])
local catalogueSearch = CreateFrame("EditBox", "RaidWishlistCatalogueSearch", editorPanel, "InputBoxTemplate")
catalogueSearch:SetAutoFocus(false)
catalogueSearch:SetMaxLetters(60)
catalogueSearch:SetWidth(270)
catalogueSearch:SetHeight(22)
catalogueSearch:SetPoint("TOPLEFT", editorPanel, "TOPLEFT", 12 + INPUT_INSET, -58)
local catalogueSearchButton = flatButton(editorPanel, "RaidWishlistCatalogueGo", L["SEARCH"], 78, 22)
catalogueSearchButton:SetPoint("LEFT", catalogueSearch, "RIGHT", 6, 0)
local catalogueFilters = {
    raids = {
        { nil, L["ALL RAIDS"] }, { "NAXX", RAID_NAMES.NAXX }, { "OS", RAID_NAMES.OS }, { "EOE", RAID_NAMES.EOE },
        { "ULD", RAID_NAMES.ULD }, { "TOC", RAID_NAMES.TOC }, { "ONY", RAID_NAMES.ONY }, { "ICC", RAID_NAMES.ICC },
        { "RS", RAID_NAMES.RS },
    },
    qualities = {
        -- The catalogue holds only epic and legendary loot.
        { nil, L["ALL QUALITIES"] }, { 4, L["Epic"] }, { 5, L["Legendary"] },
    },
}
catalogueFilters.raidButton = flatButton(editorPanel, "RaidWishlistCatalogueFilter", L["ALL RAIDS"], 170, 22)
catalogueFilters.raidButton:SetPoint("TOPLEFT", editorPanel, "TOPLEFT", 12, -86)
catalogueFilters.qualityButton = flatButton(editorPanel, "RaidWishlistCatalogueQuality", L["ALL QUALITIES"], 170, 22)
catalogueFilters.qualityButton:SetPoint("LEFT", catalogueFilters.raidButton, "RIGHT", 6, 0)
local catalogueStatus = label(editorPanel, "GameFontNormalSmall", 10, "faint")
catalogueStatus:SetPoint("TOPLEFT", editorPanel, "TOPLEFT", 12, -114)
catalogueStatus:SetPoint("RIGHT", editorPanel, "RIGHT", -12, 0)
catalogueStatus:SetWordWrap(false)
local catalogueRows, catalogueResults, catalogueOffset = {}, {}, 0
for i = 1, 4 do
    local row = listRow(editorPanel, i, { { "raid", 120, "soft", "LEFT" } }, "RaidWishlistCatalogue" .. i)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", editorPanel, "TOPLEFT", 8, -131 - (i - 1) * 17)
    row:SetPoint("RIGHT", editorPanel, "RIGHT", -8, 0)
    row:Hide()
    catalogueRows[i] = row
end
local editorNoteLabel = label(editorPanel, "GameFontNormalSmall", 10, "soft")
editorNoteLabel:SetPoint("TOPLEFT", editorPanel, "TOPLEFT", 12, -252)
editorNoteLabel:SetText(L["Note (optional)"])
local editorNote = CreateFrame("EditBox", "RaidWishlistEditorNote", editorPanel, "InputBoxTemplate")
editorNote:SetAutoFocus(false)
editorNote:SetMaxLetters(120)
editorNote:SetHeight(22)
editorNote:SetPoint("TOPLEFT", editorPanel, "TOPLEFT", 12 + INPUT_INSET, -268)
editorNote:SetPoint("RIGHT", editorPanel, "RIGHT", -12, 0)
local editorMS = flatButton(editorPanel, "RaidWishlistEditorMS", L["MAIN SPEC"], 92, 24)
editorMS:SetPoint("TOPLEFT", editorPanel, "TOPLEFT", 12, -308)
local editorOS = flatButton(editorPanel, "RaidWishlistEditorOS", L["OFF SPEC"], 92, 24)
editorOS:SetPoint("LEFT", editorMS, "RIGHT", 6, 0)
local editorEnhanced = flatButton(editorPanel, "RaidWishlistEditorEnhanced", L["ENHANCED"], 96, 24)
editorEnhanced:SetPoint("LEFT", editorOS, "RIGHT", 6, 0)
local editorStatus = label(editorPanel, "GameFontNormalSmall", 10, "faint")
editorStatus:SetPoint("TOPLEFT", editorPanel, "TOPLEFT", 12, -294)
editorStatus:SetPoint("RIGHT", editorPanel, "RIGHT", -12, 0)
editorStatus:SetWordWrap(false)
local editorSave = flatButton(editorPanel, "RaidWishlistEditorSave", L["SAVE"], 104, 24)
editorSave:SetPoint("BOTTOMRIGHT", editorPanel, "BOTTOMRIGHT", -10, 10)
local editorDelete = flatButton(editorPanel, "RaidWishlistEditorDelete", L["DELETE"], 80, 24)
editorDelete:SetPoint("RIGHT", editorSave, "LEFT", -6, 0)
local editorCancel = flatButton(editorPanel, nil, L["CANCEL"], 80, 24)
editorCancel:SetPoint("RIGHT", editorDelete, "LEFT", -6, 0)
local editorSettingsOpen = flatButton(editorPanel, "RaidWishlistSettingsFromEditor", L["SETTINGS"], 100, 24)
editorSettingsOpen:SetPoint("BOTTOMLEFT", editorPanel, "BOTTOMLEFT", 10, 10)
local editorEntry, editorSpec, editorEnhancedValue

local settingsPanel = CreateFrame("Frame", "RaidWishlistSettingsPanel", Wishlist)
settingsPanel:SetPoint("TOPLEFT", Wishlist, "TOPLEFT", 12, -44)
settingsPanel:SetPoint("BOTTOMRIGHT", Wishlist, "BOTTOMRIGHT", -12, CONTENT_BOTTOM)
makeBackdrop(settingsPanel, "pane", 0.99)
settingsPanel:SetFrameLevel(Wishlist:GetFrameLevel() + 5)
settingsPanel:Hide()
local settingsTitle = label(settingsPanel, "GameFontNormal", 12, {1.00, 0.82, 0.32})
settingsTitle:SetPoint("TOPLEFT", settingsPanel, "TOPLEFT", 12, -12)
settingsTitle:SetText(L["SETTINGS"])
-- Both sections get one gold heading (raider screenshot 2026-10-26: the
-- points had a heading and a label with the same words).
local pointsTitle = label(settingsPanel, "GameFontNormal", 12, {1.00, 0.82, 0.32})
pointsTitle:SetPoint("TOPLEFT", settingsPanel, "TOPLEFT", 12, -42)
pointsTitle:SetText(L["ENHANCE POINTS"])
local editorPoints = CreateFrame("EditBox", "RaidWishlistEditorPoints", settingsPanel, "InputBoxTemplate")
editorPoints:SetAutoFocus(false)
editorPoints:SetMaxLetters(6)
editorPoints:SetWidth(72)
editorPoints:SetHeight(22)
editorPoints:SetPoint("TOPLEFT", settingsPanel, "TOPLEFT", 12 + INPUT_INSET, -64)
local editorPointsSave = flatButton(settingsPanel, "RaidWishlistEditorPointsSave", L["SET POINTS"], 112, 22)
editorPointsSave:SetPoint("LEFT", editorPoints, "RIGHT", 8, 0)
local reminderTitle = label(settingsPanel, "GameFontNormal", 12, {1.00, 0.82, 0.32})
reminderTitle:SetPoint("TOPLEFT", settingsPanel, "TOPLEFT", 12, -122)
reminderTitle:SetText(L["CHAT ROLL REMINDER"])
local reminderHint = label(settingsPanel, "GameFontNormalSmall", 10, "soft")
reminderHint:SetPoint("TOPLEFT", settingsPanel, "TOPLEFT", 12, -146)
reminderHint:SetPoint("RIGHT", settingsPanel, "RIGHT", -12, 0)
reminderHint:SetWordWrap(true)
reminderHint:SetJustifyH("LEFT")
reminderHint:SetText(L["A reminder needs a wishlisted item link and a keyword."])
-- Off by default (user decision 2026-10-26): chat only opens prompts once
-- the player switches the reminder on.
local reminderOn = flatButton(settingsPanel, "RaidWishlistReminderOn", "", 180, 24)
reminderOn:SetPoint("TOPLEFT", settingsPanel, "TOPLEFT", 12, -184)
local reminderAll = flatButton(settingsPanel, "RaidWishlistReminderAll", "", 180, 24)
reminderAll:SetPoint("LEFT", reminderOn, "RIGHT", 8, 0)
local reminderKeywordsLabel = label(settingsPanel, "GameFontNormalSmall", 10, "soft")
reminderKeywordsLabel:SetPoint("TOPLEFT", settingsPanel, "TOPLEFT", 12, -222)
reminderKeywordsLabel:SetText(L["Keywords (comma-separated)"])
local reminderKeywordsBox = CreateFrame("EditBox", "RaidWishlistReminderKeywords", settingsPanel, "InputBoxTemplate")
reminderKeywordsBox:SetAutoFocus(false)
reminderKeywordsBox:SetMaxLetters(160)
reminderKeywordsBox:SetHeight(22)
reminderKeywordsBox:SetPoint("TOPLEFT", settingsPanel, "TOPLEFT", 12 + INPUT_INSET, -238)
reminderKeywordsBox:SetPoint("RIGHT", settingsPanel, "RIGHT", -12, 0)
local settingsStatus = label(settingsPanel, "GameFontNormalSmall", 10, "faint")
settingsStatus:SetPoint("TOPLEFT", settingsPanel, "TOPLEFT", 12, -276)
settingsStatus:SetPoint("RIGHT", settingsPanel, "RIGHT", -12, 0)
settingsStatus:SetWordWrap(false)
local reminderSave = flatButton(settingsPanel, "RaidWishlistReminderSave", L["SAVE SETTINGS"], 144, 24)
reminderSave:SetPoint("BOTTOMRIGHT", settingsPanel, "BOTTOMRIGHT", -10, 10)
local reminderCancel = flatButton(settingsPanel, "RaidWishlistReminderCancel", L["CANCEL"], 80, 24)
reminderCancel:SetPoint("RIGHT", reminderSave, "LEFT", -6, 0)

---------------------------------------------------------------------------
-- Size and scale: the grip in the lower right corner sizes the window (up to
-- the screen's edges), - / + beside it scale it (60-150%). Both are saved
-- account-wide in RaidWishlistDB.window; /wish reset restores the defaults.
---------------------------------------------------------------------------
local windowSize = {}
do
    local SCALE_MIN, SCALE_MAX = 0.6, 1.5
    local grip = CreateFrame("Button", "RaidWishlistResize", Wishlist)
    grip:SetWidth(16)
    grip:SetHeight(16)
    grip:SetPoint("BOTTOMRIGHT", Wishlist, "BOTTOMRIGHT", -4, 4)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")

    local scaleUp = flatButton(Wishlist, "RaidWishlistScaleUp", "+", 20, 18)
    scaleUp:SetPoint("BOTTOMRIGHT", Wishlist, "BOTTOMRIGHT", -24, 8)
    local scaleValue = label(Wishlist, "GameFontNormalSmall", 10, "soft", "RaidWishlistScaleValue")
    scaleValue:SetPoint("RIGHT", scaleUp, "LEFT", -2, 0)
    scaleValue:SetWidth(32)
    scaleValue:SetJustifyH("CENTER")
    local scaleDown = flatButton(Wishlist, "RaidWishlistScaleDown", "-", 20, 18)
    scaleDown:SetPoint("RIGHT", scaleValue, "LEFT", -2, 0)
    status:SetPoint("RIGHT", scaleDown, "LEFT", -8, 0)

    local function saved()
        local db = ensureDatabase()
        db.window = db.window or {}
        return db.window
    end
    local function showScale() scaleValue:SetText(string.format("%d%%", math.floor(Wishlist:GetScale() * 100 + 0.5))) end

    -- A larger scale may shrink the window to keep it on the screen.
    local function fitScreen()
        local scale = Wishlist:GetScale()
        local maxWidth = math.max(WIDTH, math.floor(UIParent:GetWidth() / scale))
        local maxHeight = math.max(HEIGHT, math.floor(UIParent:GetHeight() / scale))
        Wishlist:SetWidth(math.max(WIDTH, math.min(Wishlist:GetWidth(), maxWidth)))
        Wishlist:SetHeight(math.max(HEIGHT, math.min(Wishlist:GetHeight(), maxHeight)))
    end
    local function relayout()
        local height = Wishlist:GetHeight() + CONTENT_TOP - CONTENT_BOTTOM
        for _, list in ipairs(listOrder) do list.fit(rowsFit(height)) end
        importText:SetWidth(Wishlist:GetWidth() - 60)
        importText:SetHeight(Wishlist:GetHeight() - 200)
        showScale()
        if Wishlist:IsShown() and windowSize.redraw then windowSize.redraw() end
    end
    Wishlist:SetScript("OnSizeChanged", relayout)
    local function saveSize()
        local window = saved()
        window.width, window.height = math.floor(Wishlist:GetWidth() + 0.5), math.floor(Wishlist:GetHeight() + 0.5)
    end

    -- The window grows right and down, up to the screen's edges.
    grip:SetScript("OnMouseDown", function()
        local scale = Wishlist:GetScale()
        local left, top = Wishlist:GetLeft() or 0, Wishlist:GetTop() or HEIGHT
        Wishlist:SetMaxResize(math.max(WIDTH, math.floor(UIParent:GetWidth() / scale - left)), math.max(HEIGHT, math.floor(top)))
        Wishlist:StartSizing("BOTTOMRIGHT")
    end)
    grip:SetScript("OnMouseUp", function()
        Wishlist:StopMovingOrSizing()
        saveSize()
        relayout()
    end)

    -- windowSize.setScale: 0.6-1.5, saved; false when out of range.
    function windowSize.setScale(scale)
        scale = tonumber(scale)
        if not scale or scale < SCALE_MIN - 0.001 or scale > SCALE_MAX + 0.001 then return false end
        -- Saves the rounded value: the client reads its scale back as a 32-bit float.
        scale = math.floor(scale * 10 + 0.5) / 10
        Wishlist:SetScale(scale)
        saved().scale = scale
        fitScreen()
        saveSize()
        relayout()
        return true
    end
    scaleUp:SetScript("OnClick", function() windowSize.setScale(Wishlist:GetScale() + 0.1) end)
    scaleDown:SetScript("OnClick", function() windowSize.setScale(Wishlist:GetScale() - 0.1) end)

    -- Restores the saved size and scale (at login, after the SavedVariables).
    function windowSize.restore()
        local window = saved()
        Wishlist:SetScale(window.scale or 1)
        Wishlist:SetWidth(window.width or WIDTH)
        Wishlist:SetHeight(window.height or HEIGHT)
        fitScreen()
        relayout()
    end
    function windowSize.reset()
        ensureDatabase().window = nil
        Wishlist:ClearAllPoints()
        Wishlist:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        windowSize.restore()
    end
    function windowSize.command(rest)
        local percent = tonumber(rest)
        if percent and windowSize.setScale(percent / 100) then
            say(string.format(L["window scale: %d%%."], math.floor(Wishlist:GetScale() * 100 + 0.5)))
        else
            say(string.format(L["usage: /wish scale <%d-%d> (percent)"], SCALE_MIN * 100, SCALE_MAX * 100))
        end
    end
    windowSize.grip, windowSize.up, windowSize.down = grip, scaleUp, scaleDown
    showScale()
end

-- Roll prompt: one click rolls the wishlisted spec and points.
local Prompt = CreateFrame("Frame", "RaidWishlistPrompt", UIParent)
Prompt:SetWidth(340)
Prompt:SetHeight(106)
-- At the top of the screen, above the raid lead's RaidLedger window
-- (live run 638949e7b728 showed the prompt covering its panes).
Prompt:SetPoint("TOP", UIParent, "TOP", 0, -20)
Prompt:SetFrameStrata("FULLSCREEN_DIALOG")
Prompt:SetClampedToScreen(true)
makeBackdrop(Prompt, "frame", 0.98)
Prompt:Hide()

local promptTitle = label(Prompt, "GameFontNormal", 11, {1.00, 0.82, 0.32})
promptTitle:SetPoint("TOPLEFT", Prompt, "TOPLEFT", 12, -10)
promptTitle:SetText(L["ON YOUR WISHLIST"])

local promptTimer = label(Prompt, "GameFontNormalSmall", 10, "soft")
promptTimer:SetPoint("TOPRIGHT", Prompt, "TOPRIGHT", -12, -11)
promptTimer:SetJustifyH("RIGHT")

local promptItem = label(Prompt, "GameFontHighlight", 12, {0.94, 0.98, 0.95})
promptItem:SetPoint("TOPLEFT", Prompt, "TOPLEFT", 12, -28)
promptItem:SetPoint("TOPRIGHT", Prompt, "TOPRIGHT", -12, -28)
promptItem:SetJustifyH("LEFT")
promptItem:SetWordWrap(false)

local promptNote = label(Prompt, "GameFontNormalSmall", 10, "soft")
promptNote:SetPoint("TOPLEFT", promptItem, "BOTTOMLEFT", 0, -4)
promptNote:SetPoint("TOPRIGHT", promptItem, "BOTTOMRIGHT", 0, -4)
promptNote:SetJustifyH("LEFT")
promptNote:SetWordWrap(false)

-- The buttons fill the row with the same 12 px margin on the left, right and
-- bottom (raider screenshot 2026-10-26: they sat left with empty space right).
local skipButton = flatButton(Prompt, "RaidWishlistSkip", L["SKIP"], 80, 26)
skipButton:SetPoint("BOTTOMRIGHT", Prompt, "BOTTOMRIGHT", -12, 12)
local rollButton = flatButton(Prompt, "RaidWishlistRoll", L["ROLL"], 170, 26)
rollButton:SetPoint("BOTTOMLEFT", Prompt, "BOTTOMLEFT", 12, 12)
rollButton:SetPoint("RIGHT", skipButton, "LEFT", -8, 0)

---------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------
local function updateAutoButton()
    local _, char = ensureDatabase()
    autoButton:SetText(char.auto and L["AUTO-ROLL: ON"] or L["AUTO-ROLL: OFF"])
    local color = char.auto and palette.buttonOn or palette.button
    autoButton:SetBackdropColor(color[1], color[2], color[3], 0.98)
end

local function updateWishlist()
    local _, char = ensureDatabase()
    local list = wishList
    local count = table.getn(char.items)
    list.heading:SetText(count > 0 and string.format(L["MY WISHLIST (%d)"], count) or L["MY WISHLIST"])
    place(list, count)
    for i = 1, table.getn(wishRows) do
        local row, entry = wishRows[i], char.items[i + list.offset]
        row.entry = entry
        if entry then
            row:SetText(string.format("%d. %s", entry.priority, itemLink(entry.itemID)))
            row.columns.note:SetText(entry.note or "")
            if entry.received then
                row.columns.range:SetText(L["RECEIVED"])
                row.columns.range:SetTextColor(0.45, 0.85, 0.55)
            else
                row.columns.range:SetText(rangeLabel(entry))
                row.columns.range:SetTextColor(1.00, 0.82, 0.30)
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
        if not isOpenAward(award) then table.insert(awards, award) end   -- open ones are in their own tab
    end
    local list = raidList
    local count = table.getn(awards)
    list.heading:SetText(count > 0 and string.format(L["THIS RAID (%d)"], count) or L["THIS RAID"])
    place(list, count)
    local items, tokens = myTally()
    tallyText:SetText(string.format(L["YOU: ITEMS %d MS / %d OS  |  TOKENS %d MS / %d OS"],
        items.ms, items.os, tokens.ms, tokens.os))
    for i = 1, table.getn(raidRows) do
        local row, award = raidRows[i], awards[i + list.offset]
        row.award = award
        if award then
            local removed = award.state == "deleted"
            row:SetText(removed and ("|cff777777" .. string.gsub(award.item, "|c%x%x%x%x%x%x%x%x", "") .. "|r") or award.item)
            row.columns.recipient:SetText(award.recipient)
            local tag = removed and L["REMOVED"] or (award.state == "disenchanted" and L["DE"])
                or (award.state == "bank" and L["BANK"]) or (SPEC_LABELS[award.spec] or "")
            if award.token and not removed then tag = tag .. L[" TOKEN"] end
            row.columns.tag:SetText(tag)
            local mine = isPlayer(awardOwner(award)) and not removed
            local wished = findWish(award.itemID) ~= nil
            local fill = mine and palette.rowMine or palette.row
            row:SetBackdropColor(fill[1], fill[2], fill[3], (mine or wished) and 0.9 or 0)
            row:Show()
        else
            row:Hide()
        end
    end
end

local OPEN_STATUS = { o = L["OPEN"], r = L["ROLLING NOW"], w = L["WON"] }

local function updateOpen()
    local items = openItems()
    local list = openList
    local count = table.getn(items)
    list.heading:SetText(count > 0 and string.format(L["OPEN ITEMS (%d)"], count) or L["OPEN ITEMS"])
    place(list, count)
    for i = 1, table.getn(openRows) do
        local row, item = openRows[i], items[i + list.offset]
        row.open = item
        if item then
            row:SetText(item.item)
            row.columns.where:SetText(item.where)
            local tag = OPEN_STATUS[item.status] or L["OPEN"]
            if item.status == "w" and item.winner then tag = string.format(L["WON: %s"], string.upper(item.winner)) end
            local wished = findWish(item.itemID)
            if wished and not wished.received and item.status ~= "w" then tag = L["WISHLIST  "] .. tag end
            row.columns.tag:SetText(tag)
            if item.status == "r" then
                row.columns.tag:SetTextColor(0.45, 0.85, 0.55)
            else
                row.columns.tag:SetTextColor(1.00, 0.82, 0.30)
            end
            row:SetBackdropColor(palette.row[1], palette.row[2], palette.row[3], wished and 0.9 or 0)
            row:Show()
        else
            row:Hide()
        end
    end
end

wishList.draw, openList.draw, raidList.draw = updateWishlist, updateOpen, updateRaid

local function refresh()
    refreshReceived()
    updateAutoButton()
    updateWishlist()
    updateOpen()
    updateRaid()
    if currentList then drawTabs() else lists.show(select(2, ensureDatabase()).tab) end
end
windowSize.redraw = refresh

local function closeOverlay(panel)
    panel:Hide()
    tabBar:Show()
    content:Show()
end

local function updateEditorButtons()
    local msColor = editorSpec == "ms" and palette.buttonOn or palette.button
    local osColor = editorSpec == "os" and palette.buttonOn or palette.button
    local enhancedColor = editorEnhancedValue and palette.buttonOn or palette.button
    editorMS:SetBackdropColor(msColor[1], msColor[2], msColor[3], 0.98)
    editorOS:SetBackdropColor(osColor[1], osColor[2], osColor[3], 0.98)
    editorEnhanced:SetBackdropColor(enhancedColor[1], enhancedColor[2], enhancedColor[3], 0.98)
    editorEnhanced:SetText(editorEnhancedValue and L["ENHANCED: ON"] or L["ENHANCED: OFF"])
end

local function drawCatalogueResults()
    catalogueOffset = math.max(0, math.min(catalogueOffset, table.getn(catalogueResults) - table.getn(catalogueRows)))
    for i, row in ipairs(catalogueRows) do
        local record = catalogueResults[i + catalogueOffset]
        row.record = record
        if record then
            row:SetText(catalogueName(record))
            row.columns.raid:SetText(catalogueRaidNames(record))
            row:Show()
        else
            row:Hide()
        end
    end
end

local function clearCatalogueResults()
    catalogueResults, catalogueOffset = {}, 0
    drawCatalogueResults()
end

local function updateCatalogueFilters()
    catalogueFilters.raidButton:SetText(catalogueFilters.raid and RAID_NAMES[catalogueFilters.raid] or L["ALL RAIDS"])
    for _, option in ipairs(catalogueFilters.qualities) do
        if option[1] == catalogueFilters.quality then catalogueFilters.qualityButton:SetText(option[2]) end
    end
end

local function searchCatalogue()
    local query = trim(catalogueSearch:GetText())
    if query == "" then
        catalogueStatus:SetText(L["Enter an item name to search the raid catalogue."])
        clearCatalogueResults()
        return
    end
    if string.len(query) > 60 then
        catalogueStatus:SetText(L["Search names can be at most 60 characters."])
        clearCatalogueResults()
        return
    end
    if string.find(query, "|", 1, true) then
        catalogueStatus:SetText(L["Search text cannot contain |."])
        clearCatalogueResults()
        return
    end
    query = catalogueLower(query)
    catalogueResults, catalogueOffset = {}, 0
    for _, record in ipairs(ns.catalogue or {}) do
        if string.find(catalogueLower(record[3]), query, 1, true)
            or string.find(catalogueLower(record[4]), query, 1, true) then
            if (not catalogueFilters.raid or string.find("," .. record[2] .. ",", "," .. catalogueFilters.raid .. ",", 1, true))
                and (not catalogueFilters.quality or record[5] == catalogueFilters.quality) then
                table.insert(catalogueResults, record)
            end
        end
    end
    if table.getn(catalogueResults) == 0 then
        catalogueStatus:SetText(L["No raid loot matches that name."])
    else
        catalogueStatus:SetText(string.format(L["%d catalogue matches (mouse wheel for more)."], table.getn(catalogueResults)))
    end
    drawCatalogueResults()
end

for _, row in ipairs(catalogueRows) do
    row:SetScript("OnClick", function(self)
        if self.record then
            editorItem:SetText(tostring(self.record[1]))
            editorStatus:SetText(string.format(L["Selected item ID: %d"], self.record[1]))
        end
    end)
end
editorPanel:EnableMouseWheel(true)
editorPanel:SetScript("OnMouseWheel", function(_, delta)
    if table.getn(catalogueResults) > table.getn(catalogueRows) then
        catalogueOffset = catalogueOffset - delta * 3
        drawCatalogueResults()
    end
end)

local function showEditor(entry)
    editorEntry = entry
    editorSpec = entry and entry.spec or "ms"
    editorEnhancedValue = entry and entry.enhanced or false
    editorItem:SetText(entry and tostring(entry.itemID) or "")
    editorNote:SetText(entry and entry.note or "")
    catalogueSearch:SetText("")
    catalogueStatus:SetText("")
    clearCatalogueResults()
    catalogueFilters.raidMenu:Hide()
    catalogueFilters.qualityMenu:Hide()
    updateCatalogueFilters()
    editorSave:SetText(entry and L["SAVE"] or L["ADD TO WISHLIST"])
    if entry then editorDelete:Show() else editorDelete:Hide() end
    editorStatus:SetText("")
    updateEditorButtons()
    Wishlist:Show()
    importPanel:Hide()
    settingsPanel:Hide()
    tabBar:Hide()
    content:Hide()
    editorPanel:Show()
end

-- A manual change is a newer list for the ledger, but the balance and the
-- wins it already counts stay as they were.
local function newListVersion(char)
    char.balanceAt = char.balanceAt or char.exportedAt
    char.exportedAt = time()
end

local function normalizePriorities(char)
    for i, entry in ipairs(char.items) do entry.priority = i end
end

local function saveEditor()
    local itemID = tonumber(trim(editorItem:GetText()))
    if not itemID or itemID <= 0 or itemID ~= math.floor(itemID) then
        editorStatus:SetText(L["Enter a positive item ID."])
        return
    end
    local _, char = ensureDatabase()
    -- A selected entry is changed in place, even its item ID; it never merges
    -- into another entry. A new item that is already listed updates that entry.
    local entry, listed = editorEntry, findWish(itemID)
    if entry and listed and listed ~= entry then
        editorStatus:SetText(L["That item is already on your wishlist."])
        return
    end
    entry = entry or listed
    if not entry then
        entry = { itemID = itemID, priority = table.getn(char.items) + 1 }
        table.insert(char.items, entry)
    end
    entry.itemID, entry.spec = itemID, editorSpec
    entry.enhanced = editorSpec == "ms" and editorEnhancedValue or nil
    entry.note = string.sub(string.gsub(editorNote:GetText() or "", "|", ""), 1, 120)
    newListVersion(char)
    normalizePriorities(char)
    shareAt = GetTime() + 1
    refresh()
    lists.show("wish")
    editorItem:ClearFocus()
    editorNote:ClearFocus()
    catalogueSearch:ClearFocus()
    closeOverlay(editorPanel)
    status:SetText(L["Saved wishlist item."])
end

-- The settings page edits a copy: SAVE SETTINGS stores all of it, CANCEL
-- drops all of it, the sender-mode button included. SET POINTS is a shortcut
-- that stores the points alone.
local settings = { draft = {} }

-- typedPoints reads the points field: a whole number from 0 to 999999, or nil
-- after naming the problem.
function settings.typedPoints()
    local value = trim(editorPoints:GetText())
    local points = string.match(value, "^%d+$") and tonumber(value)
    if not points or points > 999999 then
        settingsStatus:SetText(L["Enter a whole number from 0 to 999999."])
        return nil
    end
    return points
end

-- The typed value is the current balance, not an addition to past wins: the
-- wins counted so far are in it, later ones count against it.
function settings.setBalance(char, points)
    char.balance, char.spent, char.balanceAt = points, {}, time()
end

function settings.saveEnhancePoints()
    local points = settings.typedPoints()
    if not points then return end
    local _, char = ensureDatabase()
    settings.setBalance(char, points)
    settings.draft.points = tostring(points)
    editorPoints:SetText(settings.draft.points)
    editorPoints:ClearFocus()
    refresh()
    settingsStatus:SetText(string.format(L["Enhance points set to %d."], points))
end

local function deleteEditor()
    if not editorEntry then
        editorStatus:SetText(L["No wishlist item selected."])
        return
    end
    local _, char = ensureDatabase()
    for i, entry in ipairs(char.items) do
        if entry == editorEntry then table.remove(char.items, i); break end
    end
    newListVersion(char)
    normalizePriorities(char)
    shareAt = GetTime() + 1
    refresh()
    lists.show("wish")
    editorItem:ClearFocus()
    editorNote:ClearFocus()
    catalogueSearch:ClearFocus()
    closeOverlay(editorPanel)
    status:SetText(L["Removed wishlist item."])
end

function settings.updateReminderButton()
    reminderOn:SetText(settings.draft.reminderOn and L["CHAT REMINDER: ON"] or L["CHAT REMINDER: OFF"])
    local color = settings.draft.reminderOn and palette.buttonOn or palette.button
    reminderOn:SetBackdropColor(color[1], color[2], color[3], 0.98)
    reminderAll:SetText(settings.draft.reminderAll and L["All group members"] or L["Only the master looter"])
    color = settings.draft.reminderAll and palette.buttonOn or palette.button
    reminderAll:SetBackdropColor(color[1], color[2], color[3], 0.98)
end

function settings.show()
    local _, char = ensureDatabase()
    -- The real balance, not the capped roll bonus, so saving it unchanged
    -- never lowers it.
    settings.draft.points = tostring(currentBalance(char))
    settings.draft.reminderAll = char.reminderAll
    settings.draft.reminderOn = char.reminderOn
    editorPoints:SetText(settings.draft.points)
    reminderKeywordsBox:SetText(reminderKeywords(char))
    settingsStatus:SetText("")
    settings.updateReminderButton()
    Wishlist:Show()
    importPanel:Hide()
    editorPanel:Hide()
    tabBar:Hide()
    content:Hide()
    settingsPanel:Show()
end

function settings.close()
    editorPoints:ClearFocus()
    reminderKeywordsBox:ClearFocus()
    closeOverlay(settingsPanel)
end

function settings.save()
    local points = settings.typedPoints()
    if not points then return end
    local words = {}
    -- Stored as typed and lowered only to compare: lowering can mangle
    -- "ü" (playbook), so a stored "würfel" would never match again.
    local value = string.sub(string.gsub(reminderKeywordsBox:GetText() or "", "|", ""), 1, 160)
    for word in string.gmatch(value, "[^,%s]+") do
        if string.len(word) <= 32 then table.insert(words, word) end
    end
    if table.getn(words) == 0 then
        settingsStatus:SetText(L["Enter at least one reminder keyword."])
        return
    end
    local _, char = ensureDatabase()
    -- Unchanged points keep the wins counted since the last balance.
    if tostring(points) ~= settings.draft.points then settings.setBalance(char, points) end
    char.reminderAll = settings.draft.reminderAll
    char.reminderOn = settings.draft.reminderOn
    char.reminderKeywords = table.concat(words, ",")
    settings.close()
    refresh()
    status:SetText(L["Settings saved."])
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
    -- The first roll of a new raid can be its first message: switch to that
    -- raid before asking what was received (last raid's awards do not count).
    local before = ensureDatabase().raid.session
    if not followSession(f[2] or "") then return end
    if ensureDatabase().raid.session ~= before then refresh() end
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
        lists.show("open")
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

local function isMasterLooter(name)
    local method, partyMaster, raidMaster = GetLootMethod()
    if method ~= "master" then return false end
    local master
    if GetNumRaidMembers() and GetNumRaidMembers() > 0 then
        master = raidMaster and GetRaidRosterInfo(raidMaster)
    elseif partyMaster then
        master = UnitName("party" .. partyMaster)
    end
    return master and lower(master) == lower(name)
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
    elseif f[1] == "HQ" then
        -- A ledger asks who runs which addon (its SETTINGS panel lists them).
        helloAt = helloAt or (GetTime() + answerDelay())
    end
end

-- Chat from another loot addon is untrusted text. It only creates a prompt
-- after both a user-selected keyword and a wishlisted item link match.
local function onChatReminder(message, sender)
    if type(message) ~= "string" or not sender or isPlayer(sender) then return end
    -- RaidLedger starts its rolls by addon message; its "[Loot]" lines
    -- (parked items, BoE winners, counted rolls) are no roll to join.
    if string.find(message, "^%[Loot%]") then return end
    local _, char = ensureDatabase()
    if not char.reminderOn or not matchingReminderKeyword(message, char) then return end
    if not char.reminderAll and not isMasterLooter(sender) then return end
    for id in string.gmatch(message, "|Hitem:(%d+):") do
        local entry = findWish(tonumber(id))
        if entry and not entry.received then
            local key = "chat:" .. lower(sender) .. ":" .. id .. ":" .. lower(message)
            if rolled[key] then return end
            if not Wishlist:IsShown() then
                refresh()
                lists.show("wish")
                Wishlist:Show()
            end
            if char.auto then
                pendingRoll = { entry = entry, key = key, at = GetTime() + AUTO_DELAY }
                status:SetText(string.format(L["Auto-roll: %s for %s in a moment."], rangeLabel(entry), itemLink(entry.itemID)))
            else
                showPrompt(entry, key, 30)
            end
            return
        end
    end
end

---------------------------------------------------------------------------
-- Import, buttons, events
---------------------------------------------------------------------------
local function showImport(show)
    if show then
        Wishlist:Show()
        editorPanel:Hide()
        settingsPanel:Hide()
        importPanel:Show()
        tabBar:Hide()
        content:Hide()
    else
        importText:ClearFocus()
        importPanel:Hide()
        tabBar:Show()
        content:Show()
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
    char.balanceAt = list.exportedAt
    shareAt = GetTime() + 1     -- the raid lead's ledger learns the new list
    importText:SetText("")
    showImport(false)
    wishList.offset = 0
    refresh()
    lists.show("wish")
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

local function applyTheme()
    local color = ensureDatabase().color or DEFAULT_ACCENT
    palette = computePalette(color[1], color[2], color[3])
    for _, entry in ipairs(themed) do paint(entry) end
    refresh()
end

local function setColor(red, green, blue)
    ensureDatabase().color = red and { red, green, blue } or nil
    applyTheme()
end

-- Blizzard's color picker; Cancel restores the color from before.
local function pickColor()
    local db = ensureDatabase()
    local before = db.color or DEFAULT_ACCENT
    ColorPickerFrame.func, ColorPickerFrame.cancelFunc = nil, nil
    ColorPickerFrame.hasOpacity, ColorPickerFrame.opacityFunc = false, nil
    ColorPickerFrame.previousValues = { before[1], before[2], before[3], wasDefault = db.color == nil }
    ColorPickerFrame:SetColorRGB(before[1], before[2], before[3])
    ColorPickerFrame.func = function() setColor(ColorPickerFrame:GetColorRGB()) end
    ColorPickerFrame.cancelFunc = function(previous)
        if previous.wasDefault then setColor(nil) else setColor(previous[1], previous[2], previous[3]) end
    end
    ColorPickerFrame:SetFrameStrata("FULLSCREEN_DIALOG")   -- above this window
    ColorPickerFrame:Hide()
    ColorPickerFrame:Show()
end

colorButton:SetScript("OnClick", function(_, button)
    if button == "RightButton" then
        setColor(nil)
        say(L["window color reset."])
    else
        pickColor()
    end
end)
colorButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:SetText(L["Window color"])
    GameTooltip:AddLine(L["Click: pick a color"], 1, 1, 1)
    GameTooltip:AddLine(L["Right-click: back to the default"], 0.7, 0.7, 0.7)
    GameTooltip:Show()
end)
colorButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

importOpen:SetScript("OnClick", function() showImport(not importPanel:IsShown()) end)
importCancel:SetScript("OnClick", function() showImport(false) end)
importButton:SetScript("OnClick", importWishlist)
editOpen:SetScript("OnClick", function() showEditor() end)
catalogueSearchButton:SetScript("OnClick", searchCatalogue)
catalogueFilters.createMenu = function(anchor, options, prefix, selected)
    local menu = CreateFrame("Frame", nil, editorPanel)
    menu:SetWidth(170)
    menu:SetHeight(table.getn(options) * 20 + 8)
    menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    menu:SetFrameStrata("DIALOG")
    makeBackdrop(menu, "pane", 1)
    menu:Hide()
    menu.buttons = {}
    for i, option in ipairs(options) do
        local button = flatButton(menu, prefix .. i, option[2], 162, 18)
        button:SetPoint("TOPLEFT", menu, "TOPLEFT", 4, -4 - (i - 1) * 20)
        button:SetScript("OnClick", function() selected(i) end)
        menu.buttons[i] = button
    end
    return menu
end
catalogueFilters.raidMenu = catalogueFilters.createMenu(catalogueFilters.raidButton, catalogueFilters.raids,
    "RaidWishlistCatalogueR", function(i)
        catalogueFilters.raid = catalogueFilters.raids[i][1]
        catalogueFilters.raidMenu:Hide()
        updateCatalogueFilters()
        if trim(catalogueSearch:GetText()) ~= "" then searchCatalogue() end
    end)
catalogueFilters.qualityMenu = catalogueFilters.createMenu(catalogueFilters.qualityButton, catalogueFilters.qualities,
    "RaidWishlistCatalogueQ", function(i)
        catalogueFilters.quality = catalogueFilters.qualities[i][1]
        catalogueFilters.qualityMenu:Hide()
        updateCatalogueFilters()
        if trim(catalogueSearch:GetText()) ~= "" then searchCatalogue() end
    end)
catalogueFilters.raidButton:SetScript("OnClick", function()
    catalogueFilters.qualityMenu:Hide()
    if catalogueFilters.raidMenu:IsShown() then catalogueFilters.raidMenu:Hide() else catalogueFilters.raidMenu:Show() end
end)
catalogueFilters.qualityButton:SetScript("OnClick", function()
    catalogueFilters.raidMenu:Hide()
    if catalogueFilters.qualityMenu:IsShown() then catalogueFilters.qualityMenu:Hide() else catalogueFilters.qualityMenu:Show() end
end)
catalogueSearch:SetScript("OnEnterPressed", function(self)
    self:ClearFocus()
    searchCatalogue()
end)
catalogueSearch:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
editorMS:SetScript("OnClick", function() editorSpec = "ms"; updateEditorButtons() end)
editorOS:SetScript("OnClick", function() editorSpec = "os"; editorEnhancedValue = false; updateEditorButtons() end)
editorEnhanced:SetScript("OnClick", function()
    if editorSpec == "ms" then editorEnhancedValue = not editorEnhancedValue; updateEditorButtons() end
end)
editorSave:SetScript("OnClick", saveEditor)
editorPointsSave:SetScript("OnClick", settings.saveEnhancePoints)
editorDelete:SetScript("OnClick", deleteEditor)
editorCancel:SetScript("OnClick", function()
    editorItem:ClearFocus()
    editorNote:ClearFocus()
    catalogueSearch:ClearFocus()
    closeOverlay(editorPanel)
end)
settingsOpen:SetScript("OnClick", settings.show)
editorSettingsOpen:SetScript("OnClick", settings.show)
reminderOn:SetScript("OnClick", function()
    settings.draft.reminderOn = not settings.draft.reminderOn or nil
    settings.updateReminderButton()
end)
reminderAll:SetScript("OnClick", function()
    settings.draft.reminderAll = not settings.draft.reminderAll or nil
    settings.updateReminderButton()
end)
reminderSave:SetScript("OnClick", settings.save)
reminderCancel:SetScript("OnClick", settings.close)
autoButton:SetScript("OnClick", function()
    local _, char = ensureDatabase()
    setAuto(not char.auto)
end)
local function buttonTip(button, text)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(text, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
end
buttonTip(autoButton, L["Auto-roll: roll on wishlisted items by yourself, without the prompt (e.g. while away)."])
buttonTip(importOpen, L["Import: paste your wishlist export from the guild website."])
buttonTip(editOpen, L["Edit: add, change or remove wishlist items."])
buttonTip(catalogueSearchButton, L["Catalogue search: find WotLK raid loot by English or German name."])
buttonTip(catalogueFilters.raidButton, L["Click to open the raid filter"])
buttonTip(catalogueFilters.qualityButton, L["Click to open the item quality filter"])
buttonTip(settingsOpen, L["Settings: set Enhance points and chat roll reminders."])
buttonTip(editorSettingsOpen, L["Settings: set Enhance points and chat roll reminders."])
buttonTip(wishList.tab, L["Your wishlist in rank order, with the roll range you would use."])
buttonTip(openList.tab, L["Loot still waiting to be rolled: on the corpse, or parked with a raider."])
buttonTip(raidList.tab, L["Who got what this raid, and your items so far."])
buttonTip(windowSize.grip, L["Drag to resize the window"])
buttonTip(windowSize.up, L["Make the window larger (up to 150%)"])
buttonTip(windowSize.down, L["Make the window smaller (down to 60%)"])

local function showTooltip(owner, link, extra)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    local itemString = type(link) == "string" and string.match(link, "item:[%-%d:]+")
    if itemString then GameTooltip:SetHyperlink(itemString) else GameTooltip:ClearLines() end
    if extra then GameTooltip:AddLine(extra, palette.title[1], palette.title[2], palette.title[3]) end
    GameTooltip:Show()
end

for _, row in ipairs(catalogueRows) do
    row:SetScript("OnEnter", function(self)
        if self.record then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink("item:" .. self.record[1])
            GameTooltip:AddLine(catalogueRaidNames(self.record), 0.7, 0.7, 0.7)
            GameTooltip:AddLine(L["Click: select this item for your wishlist"], 1, 1, 1)
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

for _, row in ipairs(wishRows) do
    row:SetScript("OnClick", function(self) if self.entry then showEditor(self.entry) end end)
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
Wishlist:RegisterEvent("CHAT_MSG_RAID")
Wishlist:RegisterEvent("CHAT_MSG_RAID_LEADER")
Wishlist:RegisterEvent("CHAT_MSG_PARTY")
Wishlist:RegisterEvent("CHAT_MSG_PARTY_LEADER")
Wishlist:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        ensureDatabase()
        windowSize.restore()
        applyTheme()
        placeMinimapButton()
        syncAt = GetTime() + 10
        if ForgeTestBridge and ForgeTestBridge.RegisterFrame then
            ForgeTestBridge:RegisterFrame("RaidWishlistFrame", self)
            ForgeTestBridge:RegisterFrame("RaidWishlistAuto", autoButton)
            ForgeTestBridge:RegisterFrame("RaidWishlistImportOpen", importOpen)
            ForgeTestBridge:RegisterFrame("RaidWishlistImportText", importText)
            ForgeTestBridge:RegisterFrame("RaidWishlistImportButton", importButton)
            ForgeTestBridge:RegisterFrame("RaidWishlistEditOpen", editOpen)
            ForgeTestBridge:RegisterFrame("RaidWishlistSettingsOpen", settingsOpen)
            ForgeTestBridge:RegisterFrame("RaidWishlistCatalogueSearch", catalogueSearch)
            ForgeTestBridge:RegisterFrame("RaidWishlistCatalogueFilter", catalogueFilters.raidButton)
            ForgeTestBridge:RegisterFrame("RaidWishlistCatalogueQuality", catalogueFilters.qualityButton)
            ForgeTestBridge:RegisterFrame("RaidWishlistCatalogueR2", catalogueFilters.raidMenu.buttons[2])
            ForgeTestBridge:RegisterFrame("RaidWishlistCatalogueQ2", catalogueFilters.qualityMenu.buttons[2])
            ForgeTestBridge:RegisterFrame("RaidWishlistCatalogueGo", catalogueSearchButton)
            ForgeTestBridge:RegisterFrame("RaidWishlistCatalogue1", catalogueRows[1])
            ForgeTestBridge:RegisterFrame("RaidWishlistEditorItem", editorItem)
            ForgeTestBridge:RegisterFrame("RaidWishlistEditorPoints", editorPoints)
            ForgeTestBridge:RegisterFrame("RaidWishlistEditorPointsSave", editorPointsSave)
            ForgeTestBridge:RegisterFrame("RaidWishlistEditorNote", editorNote)
            ForgeTestBridge:RegisterFrame("RaidWishlistEditorMS", editorMS)
            ForgeTestBridge:RegisterFrame("RaidWishlistEditorOS", editorOS)
            ForgeTestBridge:RegisterFrame("RaidWishlistEditorSave", editorSave)
            ForgeTestBridge:RegisterFrame("RaidWishlistEditorDelete", editorDelete)
            ForgeTestBridge:RegisterFrame("RaidWishlistSettingsFromEditor", editorSettingsOpen)
            ForgeTestBridge:RegisterFrame("RaidWishlistReminderKeywords", reminderKeywordsBox)
            ForgeTestBridge:RegisterFrame("RaidWishlistReminderOn", reminderOn)
            ForgeTestBridge:RegisterFrame("RaidWishlistReminderAll", reminderAll)
            ForgeTestBridge:RegisterFrame("RaidWishlistReminderSave", reminderSave)
            ForgeTestBridge:RegisterFrame("RaidWishlistReminderCancel", reminderCancel)
            ForgeTestBridge:RegisterFrame("RaidWishlistPrompt", Prompt)
            ForgeTestBridge:RegisterFrame("RaidWishlistRoll", rollButton)
            ForgeTestBridge:RegisterFrame("RaidWishlistWish1", wishRows[1])
            ForgeTestBridge:RegisterFrame("RaidWishlistRaid1", raidRows[1])
            ForgeTestBridge:RegisterFrame("RaidWishlistOpen1", openRows[1])
            ForgeTestBridge:RegisterFrame("RaidWishlistMinimap", MinimapButton)
            ForgeTestBridge:RegisterFrame("RaidWishlistColor", colorButton)
            ForgeTestBridge:RegisterFrame("RaidWishlistResize", windowSize.grip)
            ForgeTestBridge:RegisterFrame("RaidWishlistImportField", importBack)
            ForgeTestBridge:RegisterFrame("RaidWishlistRaid1Recipient", raidRows[1].columns.recipient)
            for _, list in ipairs(listOrder) do
                ForgeTestBridge:RegisterFrame("RaidWishlistTab" .. list.id, list.tab)
            end
        end
    elseif event == "CHAT_MSG_ADDON" then
        onAddonMessage(...)
    elseif event == "CHAT_MSG_RAID" or event == "CHAT_MSG_RAID_LEADER" or event == "CHAT_MSG_PARTY" or event == "CHAT_MSG_PARTY_LEADER" then
        onChatReminder(...)
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
    -- Items asked from the server: redraw once one arrived (no event tells us).
    if next(askedItems) then
        local arrived = false
        for itemID in pairs(askedItems) do
            if GetItemInfo(itemID) then askedItems[itemID] = nil; arrived = true end
        end
        if arrived then
            refresh()
            if prompt then promptItem:SetText(itemLink(prompt.entry.itemID)) end
        end
    end
    if shareAt and now >= shareAt then
        shareAt = nil
        shareWishlist()
    end
    if helloAt and now >= helloAt then
        helloAt = nil
        local channel = groupChannel()
        if channel then SendAddonMessage(PREFIX, "HW;" .. (GetAddOnMetadata(addonName, "Version") or "?"), channel) end
    end
end)

local HELP = {
    L["/wish - show or hide your wishlist"],
    L["/wish import - paste the wishlist export from the guild website"],
    L["/wish edit - add a wishlist item without an export"],
    L["/wish auto on|off - roll automatically on wishlisted items (e.g. while away)"],
    L["/wish sync - ask the raid lead's ledger for this raid's awards"],
    L["/wish minimap on|off - show or hide the minimap button"],
    L["/wish color [reset] - pick the window color, or go back to the default"],
    L["/wish share on|off - show your wishlist to the raid lead's ledger (on by default)"],
    L["/wish remind on|off - open the roll prompt for chat announcements (off by default)"],
    L["/wish remind all|master - chat roll reminders from all group members or only the master looter"],
    L["/wish scale <percent> - make the window smaller or larger; drag its lower right corner to resize it"],
    L["/wish reset - the window back to the middle, normal size and scale"],
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
    elseif command == "edit" then
        showEditor()
    elseif command == "auto" and (rest == "on" or rest == "off") then
        setAuto(rest == "on")
    elseif command == "share" and (rest == "on" or rest == "off") then
        local _, char = ensureDatabase()
        char.noShare = rest == "off" or nil
        say(rest == "on" and L["your wishlist is shared with the raid lead's ledger."]
            or L["your wishlist is no longer shared."])
        if rest == "on" then shareAt = GetTime() + 1 end
    elseif command == "remind" and (rest == "on" or rest == "off") then
        local _, char = ensureDatabase()
        char.reminderOn = rest == "on" or nil
        say(rest == "on" and L["chat roll reminders are on."] or L["chat roll reminders are off."])
    elseif command == "remind" and (rest == "all" or rest == "master") then
        -- Sets, never toggles: a repeated command (or plan step) keeps the state.
        local _, char = ensureDatabase()
        char.reminderAll = rest == "all" or nil
        say(rest == "all" and L["chat roll reminders: all group members."]
            or L["chat roll reminders: only the master looter."])
    elseif command == "minimap" and (rest == "on" or rest == "off") then
        setMinimapButton(rest == "on")
    elseif command == "color" or command == "colour" then
        if rest == "reset" then
            setColor(nil)
            say(L["window color reset."])
        else
            Wishlist:Show()
            pickColor()
        end
    elseif command == "scale" then
        windowSize.command(rest)
    elseif command == "reset" then
        windowSize.reset()
        Wishlist:Show()
    elseif command == "sync" then
        if requestSync() then say(L["asked the raid lead's ledger for this raid's awards."]) else say(L["not in a group."]) end
    else
        for _, line in ipairs(HELP) do say(line) end
    end
end
