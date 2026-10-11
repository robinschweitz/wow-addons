-- Offline harness: stubs the WoW 3.3.5 API, loads RaidSync.lua and drives its events.
-- Run with Lua 5.1 from the repository root:
--   lua5.1 tests/raidsync_test.lua RaidSync/RaidSync.lua /tmp/raidsync-export.txt
-- The second argument receives the generated loot export.
local addonPath = arg[1]
local failures = 0
local function check(cond, msg)
    if cond then print("ok   " .. msg) else failures = failures + 1; print("FAIL " .. msg) end
end

-- Generic widget stub.
local frames = {}
local function newObject(name)
    local o = { scripts = {}, text = "", shown = false, name = name, events = {}, checked = false }
    local mt = { __index = function(t, k)
        return function() end
    end }
    setmetatable(o, mt)
    o.SetText = function(self, t) self.text = t or ""; if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self, false) end end
    o.GetText = function(self) return self.text end
    o.SetScript = function(self, k, f) self.scripts[k] = f end
    o.GetName = function(self) return self.name end
    o.Show = function(self) self.shown = true; if self.scripts.OnShow then self.scripts.OnShow(self) end end
    o.Hide = function(self) self.shown = false end
    o.IsShown = function(self) return self.shown end
    o.CreateFontString = function() return newObject() end
    o.GetChecked = function(self) return self.checked end
    o.SetChecked = function(self, v) self.checked = v end
    o.RegisterEvent = function(self, e) self.events[e] = true end
    if name then _G[name] = o; _G[name .. "Text"] = newObject() end
    frames[#frames + 1] = o
    return o
end
CreateFrame = function(kind, name) return newObject(name) end
UIParent, ChatFontNormal = newObject(), newObject()
UISpecialFrames, StaticPopupDialogs, SlashCmdList = {}, {}, {}
YES, NO = "Ja", "Nein"
tinsert, wipe = table.insert, function(t) for k in pairs(t) do t[k] = nil end return t end
local chat = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) chat[#chat + 1] = m end }
local hooks = {}
hooksecurefunc = function(name, f) hooks[name] = f end
StaticPopup_Show = function() end

-- German client strings (deDE 3.3.5).
ERR_INVITE_PLAYER_S = "Ihr habt %s eingeladen, Eurer Gruppe beizutreten."
ERR_BAD_PLAYER_NAME_S = "Spieler '%s' nicht gefunden."
ERR_ALREADY_IN_GROUP_S = "%s ist bereits in einer Gruppe."
ERR_DECLINE_GROUP_S = "%s lehnt Eure Gruppeneinladung ab."
ERR_JOINED_GROUP_S = "%s schließt sich der Gruppe an."
ERR_RAID_MEMBER_ADDED_S = "%s hat sich der Schlachtzugsgruppe angeschlossen."
LOOT_ITEM = "%s bekommt Beute: %s."
LOOT_ITEM_SELF = "Ihr erhaltet Beute: %s."

-- Group state.
local party, raid, isLeader = {}, {}, true
local invited = {}
local now = 1000
GetTime = function() return now end
time = function() return math.floor(1760000000 + now) end
UnitName = function(u) if u == "player" then return "Rüdiger" end local i = tonumber(string.match(u, "party(%d)")) return i and party[i] end
GetNumPartyMembers = function() return #raid > 0 and 0 or #party end
GetNumRaidMembers = function() return #raid end
GetRaidRosterInfo = function(i) local r = raid[i] if r then return r.name, 0, r.group end end
IsRaidLeader, IsRaidOfficer, IsPartyLeader = function() return isLeader end, function() return false end, function() return isLeader end
InviteUnit = function(name) invited[#invited + 1] = name end
ConvertToRaid = function()
    raid = { { name = "Rüdiger", group = 1 } }
    for _, n in ipairs(party) do raid[#raid + 1] = { name = n, group = 1 } end
end
local moves = {}
SetRaidSubgroup = function(i, g) moves[#moves + 1] = { "set", raid[i].name, g }; raid[i].group = g end
SwapRaidSubgroup = function(a, b) moves[#moves + 1] = { "swap", raid[a].name, raid[b].name }; raid[a].group, raid[b].group = raid[b].group, raid[a].group end
IsInGuild = function() return true end
local guild = { { "Shanna", true }, { "Offlinia", false } }
GetNumGuildMembers = function() return #guild end
GetGuildRosterInfo = function(i) local g = guild[i] return g[1], nil, nil, nil, nil, nil, nil, nil, g[2] end

-- Loot state.
local lootSlots, target = {}, nil
GetLootMethod = function() return "master", nil, 1 end
UnitIsUnit = function(a, b) return a == "raid1" and b == "player" end
UnitExists = function(u) return u == "target" and target ~= nil end
UnitIsDead = function() return true end
UnitGUID = function() return target end
GetLootThreshold = function() return 4 end
GetNumLootItems = function() return #lootSlots end
GetLootSlotLink = function(i) return lootSlots[i].link end
GetLootSlotInfo = function(i) return nil, "x", 1, lootSlots[i].quality end
local candidates = {}
GetMasterLootCandidate = function(i) return candidates[i] end

dofile(addonPath)
local events
for _, f in ipairs(frames) do if f.events and f.events.ADDON_LOADED then events = f end end
local function fire(event, ...) events.scripts.OnEvent(events, event, ...) end
local function tick(seconds) now = now + seconds events.scripts.OnUpdate(events, seconds) end

local Core = RaidSyncCore
-- Pure helpers.
check(Core.NPCFromGUID("0xF13000"..string.format("%04X", 36612).."000123") == 36612, "NPC id from creature GUID")
check(Core.NPCFromGUID("0x0000000000ABCDEF") == nil, "player GUID has no NPC id")
check(Core.ItemIDFromLink("|cffa335ee|Hitem:50415:0:0:0:0:0:0:0:80|h[Bryntroll]|h|r") == 50415, "item id from link")
local p = Core.PatternFromFormat(ERR_DECLINE_GROUP_S)
check(string.match("Shanna lehnt Eure Gruppeneinladung ab.", p) == "Shanna", "German decline pattern")
check(Core.NameFromMessage("|Hplayer:Shanna|h[Shanna]|h") == "Shanna", "name from player link")
local r, m, err = Core.ParseInvite("RS1|LOOT|1|x|1")
check(err ~= nil, "loot text rejected as invite")

fire("ADDON_LOADED", "RaidSync")
local slash = SlashCmdList.RAIDSYNC
slash("")
check(RaidSyncFrame:IsShown(), "/rs opens the window")

-- Invite flow.
local exportText = "RS1|INV|7|ICC25 Donnerstag|25\nShanna|HEAL|Priester|0\nThorgrim|TANK|Krieger|0\nOfflinia|DD|Magier|0\nBanko|DD|Jäger|1\nAaron|DD|Schurke|0\nBert|DD|Hexer|0\nCarla|DD|Druide|0"
RaidSyncInviteText:SetText(exportText)
-- buttons are local; drive through the same functions by finding OnClick scripts
local function clickButton(label)
    for _, f in ipairs(frames) do
        if f.text == label and f.scripts.OnClick then f.scripts.OnClick(f) return true end
    end
    error("button not found: " .. label)
end
clickButton("Einlesen")
check(string.find(RaidSyncInviteList.text, "Shanna", 1, true) ~= nil, "roster listed after reading the export")
check(RaidSyncRaidID.text == "7", "raid id carried to the loot tab")
clickButton("Alle einladen")
for _ = 1, 10 do tick(0.5) end
check(#invited == 4, "solo leader invites at most 4 before a party exists (got " .. #invited .. ")")
check(invited[1] == "Shanna" and invited[2] == "Thorgrim", "invites in roster order")
local offlineInvited, benchInvited = false, false
for _, n in ipairs(invited) do if n == "Offlinia" then offlineInvited = true end if n == "Banko" then benchInvited = true end end
check(not offlineInvited, "offline guild member skipped")
check(not benchInvited, "bench not invited by default")
fire("CHAT_MSG_SYSTEM", "Thorgrim lehnt Eure Gruppeneinladung ab.")
check(string.find(RaidSyncInviteList.text, "abgelehnt", 1, true) ~= nil, "decline shown")
party = { "Shanna" }
fire("PARTY_MEMBERS_CHANGED")
tick(0.5)
check(#raid > 0, "party converted to raid after first join")
for _ = 1, 10 do tick(1) end
check(#invited == 5, "remaining invite sent after converting (got " .. #invited .. ")")
raid[#raid + 1] = { name = "Aaron", group = 1 }
raid[#raid + 1] = { name = "Thorgrim", group = 1 }
fire("RAID_ROSTER_UPDATE")
check(string.find(RaidSyncInviteList.text, "Aaron  DD  Schurke  |cff00ff00im Raid", 1, true) ~= nil, "joined member marked im Raid")
clickButton("Gruppen sortieren")
local groupOf = {}
for _, member in ipairs(raid) do groupOf[member.name] = member.group end
check(groupOf.Thorgrim == 1 and groupOf.Shanna == 1, "tank and healer stay in group 1")

-- Loot flow.
clickButton("Aufzeichnen")
target = "0xF13000"..string.format("%04X", 36612).."000777"
lootSlots = {
    { link = "|cffa335ee|Hitem:50415:0:0:0:0:0:0:0:80|h[Bryntroll]|h|r", quality = 4 },
    { link = "|cff1eff00|Hitem:12345:0|h[Grün]|h|r", quality = 2 },
    { link = "|cffa335ee|Hitem:52027:0|h[Weiheabzeichen]|h|r", quality = 4 },
}
fire("LOOT_OPENED")
fire("LOOT_CLOSED")
fire("LOOT_OPENED")
candidates = { "Shanna", "Aaron" }
hooks.GiveMasterLoot(1, 2)
fire("CHAT_MSG_LOOT", "Aaron bekommt Beute: |cffa335ee|Hitem:50415:0:0:0:0:0:0:0:80|h[Bryntroll]|h|r.")
fire("CHAT_MSG_LOOT", "Ihr erhaltet Beute: |cffa335ee|Hitem:52027:0|h[Weiheabzeichen]|h|r.")
fire("LOOT_CLOSED")
check(#RaidSyncDB.loot.entries == 2, "two epic drops recorded once despite reopening (got " .. #RaidSyncDB.loot.entries .. ")")
-- A chest after a council kill.
target = nil
fire("COMBAT_LOG_EVENT_UNFILTERED", 0, "UNIT_DIED", nil, nil, nil, "0xF13000"..string.format("%04X", 37970).."000999")
lootSlots = { { link = "|cffa335ee|Hitem:50074:0|h[Ring]|h|r", quality = 4 } }
fire("LOOT_OPENED")
fire("LOOT_CLOSED")
slash("del 99")
clickButton("Export")
local exported = RaidSyncLootExport.text
print("---- export ----\n" .. exported .. "\n----------------")
local expected = table.concat({
    "RS1|LOOT|7|Rüdiger|" .. RaidSyncDB.loot.startedAt,
    "%d+|36612|50415|Aaron",
    "%d+|36612|52027|Rüdiger",
    "%d+|37970|50074|%-",
}, "\n")
check(string.match(exported, "^" .. expected .. "$") ~= nil, "loot export format")
clickButton("Letzten entfernen")
clickButton("Export")
check(string.find(RaidSyncLootExport.text, "50074", 1, true) == nil, "removed drop left out of the export")

local out = io.open(arg[2], "w")
out:write(exported)
out:close()
print(failures == 0 and "ALL OK" or (failures .. " FAILURES"))
os.exit(failures == 0 and 0 or 1)
