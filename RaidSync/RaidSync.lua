-- RaidSync for WoW 3.3.5a
-- Exchanges copy-and-paste text with the raid website:
--   * Invite tab: paste the roster export (RS1|INV|...) and invite everyone.
--   * Loot tab:   record master-loot drops and copy the loot export (RS1|LOOT|...).
-- /rs            toggle window
-- /rs del <n>    remove recorded drop number n from the export

local FORMAT = "RS1"
local INVITE_DELAY = 0.3   -- seconds between invites
local INVITE_EXPIRY = 65   -- seconds after which an unanswered invite no longer blocks party slots

local Core = {}
RaidSyncCore = Core -- exposed for the offline tests

---------------------------------------------------------------------------
-- Pure helpers (no WoW API)
---------------------------------------------------------------------------

function Core.Trim(s)
    s = string.gsub(s or "", "^%s+", "")
    s = string.gsub(s, "%s+$", "")
    return s
end

function Core.Split(line, sep)
    local fields, start = {}, 1
    while true do
        local i = string.find(line, sep, start, true)
        if not i then
            fields[#fields + 1] = string.sub(line, start)
            return fields
        end
        fields[#fields + 1] = string.sub(line, start, i - 1)
        start = i + 1
    end
end

function Core.Lines(text)
    local lines = {}
    text = string.gsub((text or "") .. "\n", "\r", "")
    for line in string.gmatch(text, "([^\n]*)\n") do
        line = Core.Trim(line)
        if line ~= "" then lines[#lines + 1] = line end
    end
    return lines
end

-- ParseInvite reads "RS1|INV|<raidID>|<raidName>|<size>" followed by
-- "<name>|<role>|<class>|<bench 0/1>" lines.
function Core.ParseInvite(text)
    local lines = Core.Lines(text)
    if #lines == 0 then return nil, nil, "Kein Text eingefügt." end
    local header = Core.Split(lines[1], "|")
    if #header ~= 5 or header[1] ~= FORMAT or header[2] ~= "INV" or not tonumber(header[3]) then
        return nil, nil, "Das ist kein Einladungs-Export der Website."
    end
    local raid = { id = tonumber(header[3]), name = header[4], size = tonumber(header[5]) }
    local members, bad = {}, {}
    for i = 2, #lines do
        local f = Core.Split(lines[i], "|")
        if #f == 4 and f[1] ~= "" then
            members[#members + 1] = { name = f[1], role = f[2], class = f[3], bench = (f[4] == "1"), status = "offen" }
        else
            bad[#bad + 1] = lines[i]
        end
    end
    return raid, members, nil, bad
end

-- BuildLootExport renders "RS1|LOOT|<raidID>|<recorder>|<startUnix>" followed by
-- "<unixTime>|<npcID or ->|<itemID>|<recipient or ->" for every kept entry.
function Core.BuildLootExport(raidID, recorder, startedAt, entries)
    local lines = { table.concat({ FORMAT, "LOOT", tostring(raidID or 0), Core.Field(recorder), tostring(startedAt or 0) }, "|") }
    for _, e in ipairs(entries) do
        if not e.deleted then
            lines[#lines + 1] = table.concat({ tostring(e.time), e.npc and tostring(e.npc) or "-", tostring(e.item), e.recipient and Core.Field(e.recipient) or "-" }, "|")
        end
    end
    return table.concat(lines, "\n")
end

function Core.Field(s)
    s = string.gsub(s or "", "[|\r\n]", "")
    return s
end

-- PatternFromFormat turns a client format string such as ERR_DECLINE_GROUP_S
-- into a Lua pattern, so the German and English clients both work.
function Core.PatternFromFormat(fmt)
    if type(fmt) ~= "string" or fmt == "" then return nil end
    local p = string.gsub(fmt, "([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
    p = string.gsub(p, "%%%d%$s", "(.+)")
    p = string.gsub(p, "%%s", "(.+)")
    return "^" .. p .. "$"
end

-- NameFromMessage strips player links and brackets from a chat name.
function Core.NameFromMessage(name)
    if not name then return nil end
    local linked = string.match(name, "|Hplayer:([^:|]+)")
    if linked then name = linked end
    name = string.gsub(name, "[%[%]]", "")
    return Core.Trim(name)
end

-- NPCFromGUID reads the creature ID from a 3.3.5 GUID like 0xF130008F5C000123.
function Core.NPCFromGUID(guid)
    if type(guid) ~= "string" then return nil end
    local kind = string.sub(guid, 3, 5)
    if kind ~= "F13" and kind ~= "F15" then return nil end
    return tonumber(string.sub(guid, 9, 12), 16)
end

function Core.ItemIDFromLink(link)
    if type(link) ~= "string" then return nil end
    return tonumber(string.match(link, "item:(%d+)"))
end

-- GroupOrder sorts names by role (tank, heal, rest) and returns the target subgroup per name.
function Core.GroupOrder(names, roleOf)
    local priority = { TANK = 1, HEAL = 2, DD = 3 }
    local sorted = {}
    for _, name in ipairs(names) do sorted[#sorted + 1] = name end
    table.sort(sorted, function(a, b)
        local pa, pb = priority[roleOf[string.lower(a)] or ""] or 4, priority[roleOf[string.lower(b)] or ""] or 4
        if pa ~= pb then return pa < pb end
        return string.lower(a) < string.lower(b)
    end)
    local targets = {}
    for i, name in ipairs(sorted) do targets[name] = math.floor((i - 1) / 5) + 1 end
    return targets
end

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------

local db
local UI = {}
local members = {}
local queue, inviting, inviteDelay = {}, false, 0
local currentSlots = {}
local lastKill
local patterns = {}

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffRaidSync:|r " .. msg)
end

local function Lower(name) return string.lower(name or "") end

local function FindMember(name)
    local key = Lower(Core.NameFromMessage(name))
    for _, m in ipairs(members) do
        if Lower(m.name) == key then return m end
    end
end

local function GroupNames()
    local names = { [Lower(UnitName("player"))] = true }
    if GetNumRaidMembers() > 0 then
        for i = 1, GetNumRaidMembers() do
            local name = GetRaidRosterInfo(i)
            if name then names[Lower(name)] = true end
        end
    else
        for i = 1, GetNumPartyMembers() do
            local name = UnitName("party" .. i)
            if name then names[Lower(name)] = true end
        end
    end
    return names
end

-- GuildOnline only knows members the guild roster currently lists; the
-- "show offline" setting of the guild window is left alone.
local function GuildOnline()
    local online = {}
    if not IsInGuild() then return online end
    for i = 1, GetNumGuildMembers() do
        local name, _, _, _, _, _, _, _, isOnline = GetGuildRosterInfo(i)
        if name then online[Lower(name)] = isOnline and true or false end
    end
    return online
end

local function CanManageGroup()
    if GetNumRaidMembers() > 0 then return IsRaidLeader() or IsRaidOfficer() end
    if GetNumPartyMembers() > 0 then return IsPartyLeader() end
    return true
end

local function PendingInvites()
    local count, now = 0, GetTime()
    for _, m in ipairs(members) do
        if m.status == "eingeladen" then
            if now - (m.invitedAt or now) > INVITE_EXPIRY then
                m.status = "keine Antwort"
            else
                count = count + 1
            end
        end
    end
    return count
end

---------------------------------------------------------------------------
-- Display
---------------------------------------------------------------------------

local statusColors = {
    ["im Raid"] = "00ff00", ["eingeladen"] = "ffff00", ["abgelehnt"] = "ff4444",
    ["nicht gefunden"] = "ff4444", ["in anderer Gruppe"] = "ff8800", ["offline"] = "999999",
    ["keine Antwort"] = "ff8800", ["Ersatzbank"] = "999999", ["offen"] = "ffffff",
}
local roleLabels = { TANK = "Tank", HEAL = "Heal", DD = "DD" }

local function SetReadOnly(edit, text)
    edit.readOnlyText = text
    edit:SetText(text)
end

local function RefreshInvites()
    if not UI.inviteList then return end
    local lines, joined = {}, 0
    for _, m in ipairs(members) do
        if m.status == "im Raid" then joined = joined + 1 end
        lines[#lines + 1] = string.format("%s  %s  %s  |cff%s%s|r", m.name, roleLabels[m.role] or m.role or "", m.class or "", statusColors[m.status] or "ffffff", m.status)
    end
    SetReadOnly(UI.inviteList, table.concat(lines, "\n"))
    local raid = db.raid
    local head = raid and string.format("Raid #%d %s: %d / %d im Raid", raid.id, raid.name or "", joined, #members) or "Noch kein Export eingelesen."
    if inviting then head = head .. "   |cff00ff00lädt ein...|r" end
    UI.inviteStatus:SetText(head)
end

local function EntryLabel(i, e)
    local boss = e.npc and ("NPC " .. e.npc) or "Boss unbekannt"
    local who = e.recipient or "|cffff8800nicht vergeben|r"
    local line = string.format("%d. %s  %s  -> %s", i, e.link or ("Item " .. e.item), boss, who)
    if e.deleted then line = "|cff777777" .. string.gsub(line, "|c%x%x%x%x%x%x%x%x", "") .. " (entfernt)|r" end
    return line
end

local function RefreshLoot()
    if not UI.lootList then return end
    local lines, kept = {}, 0
    for i, e in ipairs(db.loot.entries) do
        lines[#lines + 1] = EntryLabel(i, e)
        if not e.deleted then kept = kept + 1 end
    end
    SetReadOnly(UI.lootList, table.concat(lines, "\n"))
    local state = db.loot.recording and "|cff00ff00Aufzeichnung läuft|r" or "Aufzeichnung gestoppt"
    UI.lootStatus:SetText(string.format("%s   %d Drops", state, kept))
    UI.recordButton:SetText(db.loot.recording and "Stoppen" or "Aufzeichnen")
end

---------------------------------------------------------------------------
-- Invites
---------------------------------------------------------------------------

local function ReadInviteText()
    local raid, list, err, bad = Core.ParseInvite(UI.inviteText:GetText())
    if err then
        Print("|cffff4444" .. err .. "|r")
        return
    end
    for _, line in ipairs(bad) do Print("|cffff8800Zeile übersprungen:|r " .. line) end
    members = list
    db.raid = raid
    db.members = list
    if not db.loot.recording and #db.loot.entries == 0 then
        db.loot.raidID = raid.id
        UI.raidIDBox:SetText(tostring(raid.id))
    end
    local inGroup = GroupNames()
    for _, m in ipairs(members) do
        if inGroup[Lower(m.name)] then m.status = "im Raid" elseif m.bench and not db.includeBench then m.status = "Ersatzbank" end
    end
    Print(string.format("%d Charaktere für Raid #%d eingelesen.", #members, raid.id))
    RefreshInvites()
end

local function StartInvites(retryMissing)
    if #members == 0 then
        Print("Zuerst den Export der Website einlesen.")
        return
    end
    if not CanManageGroup() then
        Print("|cffff4444Nur Raidleiter oder Assistenten können einladen.|r")
        return
    end
    local inGroup, online = GroupNames(), GuildOnline()
    queue = {}
    for _, m in ipairs(members) do
        local key = Lower(m.name)
        if inGroup[key] then
            m.status = "im Raid"
        elseif m.bench and not db.includeBench then
            m.status = "Ersatzbank"
        elseif online[key] == false then
            m.status = "offline"
        elseif m.status == "offen" or m.status == "Ersatzbank" or (retryMissing and m.status ~= "eingeladen") then
            queue[#queue + 1] = m
        end
    end
    if #queue == 0 then
        Print("Niemand mehr einzuladen.")
        RefreshInvites()
        return
    end
    inviting, inviteDelay = true, 0
    Print(string.format("Lade %d Charaktere ein.", #queue))
    RefreshInvites()
end

local function InviteStep()
    if GetNumRaidMembers() == 0 then
        if GetNumPartyMembers() > 0 and IsPartyLeader() then
            -- A raid is needed for more than five players; convert once someone joined.
            ConvertToRaid()
            inviteDelay = 1
            return
        end
        if GetNumPartyMembers() + PendingInvites() >= 4 then
            inviteDelay = 0.5
            return
        end
    end
    local m = table.remove(queue, 1)
    if not m then
        inviting = false
        Print("Alle Einladungen verschickt.")
        RefreshInvites()
        return
    end
    m.status, m.invitedAt = "eingeladen", GetTime()
    InviteUnit(m.name)
    inviteDelay = INVITE_DELAY
    RefreshInvites()
end

local function UpdateGroupStatus()
    local inGroup = GroupNames()
    for _, m in ipairs(members) do
        if inGroup[Lower(m.name)] then
            m.status = "im Raid"
        elseif m.status == "im Raid" then
            m.status = "offen"
        end
    end
    RefreshInvites()
end

local function SortGroups()
    if GetNumRaidMembers() == 0 or not (IsRaidLeader() or IsRaidOfficer()) then
        Print("Gruppen sortieren geht nur im Raid als Raidleiter oder Assistent.")
        return
    end
    local roleOf, names, index, group, counts = {}, {}, {}, {}, {}
    for _, m in ipairs(members) do roleOf[Lower(m.name)] = m.role end
    for i = 1, GetNumRaidMembers() do
        local name, _, subgroup = GetRaidRosterInfo(i)
        if name then
            names[#names + 1] = name
            index[name], group[name] = i, subgroup
            counts[subgroup] = (counts[subgroup] or 0) + 1
        end
    end
    local targets = Core.GroupOrder(names, roleOf)
    local moves = 0
    for _, name in ipairs(names) do
        local target = targets[name]
        if group[name] ~= target then
            local swapWith
            for _, other in ipairs(names) do
                if group[other] == target and targets[other] ~= target then swapWith = other break end
            end
            if swapWith then
                SwapRaidSubgroup(index[name], index[swapWith])
                group[name], group[swapWith] = target, group[name]
                moves = moves + 1
            elseif (counts[target] or 0) < 5 then
                counts[group[name]] = counts[group[name]] - 1
                counts[target] = (counts[target] or 0) + 1
                SetRaidSubgroup(index[name], target)
                group[name] = target
                moves = moves + 1
            end
        end
    end
    Print(moves > 0 and string.format("%d Spieler verschoben (Tanks, Heiler, Rest).", moves) or "Gruppen sind bereits sortiert.")
end

---------------------------------------------------------------------------
-- Loot
---------------------------------------------------------------------------

local function IsMasterLooter()
    local method, partyMaster, raidMaster = GetLootMethod()
    if method ~= "master" then return false end
    if raidMaster then return UnitIsUnit("raid" .. raidMaster, "player") end
    return partyMaster == 0
end

local function OnLootOpened()
    wipe(currentSlots)
    if not db.loot.recording or not IsMasterLooter() then return end
    local sourceGUID
    if UnitExists("target") and UnitIsDead("target") then sourceGUID = UnitGUID("target") end
    local npc = Core.NPCFromGUID(sourceGUID) or (lastKill and lastKill.npc)
    -- Chests have no unit; the last kill identifies them well enough to avoid doubles.
    local sourceKey = sourceGUID or ("kill:" .. tostring(lastKill and lastKill.guid or "none"))
    local threshold = GetLootThreshold()
    local added = 0
    for slot = 1, GetNumLootItems() do
        local link = GetLootSlotLink(slot)
        local _, _, _, quality = GetLootSlotInfo(slot)
        local itemID = Core.ItemIDFromLink(link)
        if itemID and quality and quality >= threshold then
            local key = sourceKey .. ":" .. slot .. ":" .. itemID
            local index = db.loot.sources[key]
            if not index then
                db.loot.entries[#db.loot.entries + 1] = { time = time(), npc = npc, item = itemID, link = link }
                index = #db.loot.entries
                db.loot.sources[key] = index
                added = added + 1
            end
            currentSlots[slot] = index
        end
    end
    if added > 0 then
        Print(string.format("%d Drop(s) aufgezeichnet.", added))
        RefreshLoot()
    end
end

local function OnMasterLootGiven(slot, candidate)
    local index = currentSlots[slot]
    if not index then return end
    local name = GetMasterLootCandidate(candidate)
    if name then
        db.loot.entries[index].recipient = name
        RefreshLoot()
    end
end

local function OnLootMessage(msg)
    if not db.loot.recording then return end
    local name, link = string.match(msg, patterns.lootOther or "^$")
    if not name then
        link = string.match(msg, patterns.lootSelf or "^$")
        name = link and UnitName("player")
    end
    local itemID = Core.ItemIDFromLink(link)
    if not itemID then return end
    name = Core.NameFromMessage(name)
    local entries = db.loot.entries
    -- Confirm a master-loot assignment, or fill in the first open drop of that item.
    for i = #entries, 1, -1 do
        local e = entries[i]
        if not e.deleted and e.item == itemID and Lower(e.recipient) == Lower(name) and not e.confirmed then
            e.confirmed = true
            return
        end
    end
    for i = 1, #entries do
        local e = entries[i]
        if not e.deleted and e.item == itemID and not e.recipient then
            e.recipient, e.confirmed = name, true
            RefreshLoot()
            return
        end
    end
end

local function ToggleRecording()
    local raidID = tonumber(UI.raidIDBox:GetText())
    if not db.loot.recording and not raidID then
        Print("Bitte zuerst eine Raid-ID eintragen oder den Einladungs-Export einlesen.")
        return
    end
    db.loot.recording = not db.loot.recording
    if db.loot.recording then
        db.loot.raidID = raidID
        db.loot.startedAt = db.loot.startedAt or time()
        if GetLootMethod() ~= "master" then Print("|cffff8800Hinweis:|r Plündermethode ist nicht Plündermeister; es wird nur als Plündermeister aufgezeichnet.") end
    end
    RefreshLoot()
end

local function ExportLoot()
    local text = Core.BuildLootExport(db.loot.raidID or tonumber(UI.raidIDBox:GetText()), UnitName("player"), db.loot.startedAt or time(), db.loot.entries)
    UI.exportBox:SetText(text)
    UI.exportBox:SetFocus()
    UI.exportBox:HighlightText()
    Print("Export markiert - mit Strg+C kopieren und auf der Raidseite unter Loot einfügen.")
end

local function RemoveEntry(n)
    local e = db.loot.entries[n]
    if not e then
        Print("Keinen Drop Nummer " .. tostring(n) .. " gefunden.")
        return
    end
    e.deleted = true
    RefreshLoot()
end

local function RemoveLast()
    for i = #db.loot.entries, 1, -1 do
        if not db.loot.entries[i].deleted then
            RemoveEntry(i)
            return
        end
    end
end

local function ClearLoot()
    db.loot = { entries = {}, sources = {}, recording = false, raidID = db.loot.raidID }
    UI.exportBox:SetText("")
    RefreshLoot()
    Print("Aufzeichnung geleert.")
end

---------------------------------------------------------------------------
-- UI
---------------------------------------------------------------------------

local function MakeScrollEdit(parent, name, width, height, readOnly)
    local box = CreateFrame("Frame", nil, parent)
    box:SetWidth(width)
    box:SetHeight(height)
    box:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    box:SetBackdropColor(0, 0, 0, 0.6)

    local scroll = CreateFrame("ScrollFrame", name .. "Scroll", box, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", -26, 6)

    local edit = CreateFrame("EditBox", name, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject(ChatFontNormal)
    edit:SetWidth(width - 36)
    edit:SetHeight(height - 12)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    if ScrollingEdit_OnCursorChanged then
        edit:SetScript("OnCursorChanged", ScrollingEdit_OnCursorChanged)
        edit:SetScript("OnUpdate", function(self, elapsed) ScrollingEdit_OnUpdate(self, elapsed, scroll) end)
    end
    if readOnly then
        edit:SetScript("OnTextChanged", function(self, userInput)
            if userInput then self:SetText(self.readOnlyText or "") end
        end)
    end
    scroll:SetScrollChild(edit)

    box:EnableMouse(true)
    box:SetScript("OnMouseDown", function() edit:SetFocus() end)
    return box, edit
end

local function Button(parent, text, width, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetWidth(width)
    b:SetHeight(22)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

local function Label(parent, text, template)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontNormal")
    fs:SetText(text)
    fs:SetJustifyH("LEFT")
    return fs
end

local function BuildInvitePanel(panel)
    local hint = Label(panel, "Website: Raid > Aufstellung > 'Einladungen für Addon' kopieren und hier einfügen.", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", 0, 0)
    hint:SetWidth(420)

    local pasteBox, paste = MakeScrollEdit(panel, "RaidSyncInviteText", 420, 80)
    pasteBox:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -6)
    paste:SetText(db.inviteText or "")
    paste:SetScript("OnTextChanged", function(self) db.inviteText = self:GetText() end)
    UI.inviteText = paste

    local read = Button(panel, "Einlesen", 90, ReadInviteText)
    read:SetPoint("TOPLEFT", pasteBox, "BOTTOMLEFT", 0, -6)
    local all = Button(panel, "Alle einladen", 105, function() StartInvites(false) end)
    all:SetPoint("LEFT", read, "RIGHT", 6, 0)
    local missing = Button(panel, "Fehlende erneut", 110, function() StartInvites(true) end)
    missing:SetPoint("LEFT", all, "RIGHT", 6, 0)
    local sort = Button(panel, "Gruppen sortieren", 105, SortGroups)
    sort:SetPoint("LEFT", missing, "RIGHT", 6, 0)

    local bench = CreateFrame("CheckButton", "RaidSyncIncludeBench", panel, "UICheckButtonTemplate")
    bench:SetPoint("TOPLEFT", read, "BOTTOMLEFT", -4, -2)
    bench:SetChecked(db.includeBench)
    bench:SetScript("OnClick", function(self) db.includeBench = self:GetChecked() and true or false end)
    _G[bench:GetName() .. "Text"]:SetText("Ersatzbank mit einladen")

    local listBox, list = MakeScrollEdit(panel, "RaidSyncInviteList", 420, 220, true)
    listBox:SetPoint("TOPLEFT", bench, "BOTTOMLEFT", 4, -2)
    UI.inviteList = list

    local status = Label(panel, "", "GameFontHighlightSmall")
    status:SetPoint("TOPLEFT", listBox, "BOTTOMLEFT", 0, -6)
    status:SetWidth(420)
    UI.inviteStatus = status
end

local function BuildLootPanel(panel)
    local idLabel = Label(panel, "Raid-ID:")
    idLabel:SetPoint("TOPLEFT", 0, -4)
    local idBox = CreateFrame("EditBox", "RaidSyncRaidID", panel, "InputBoxTemplate")
    idBox:SetWidth(70)
    idBox:SetHeight(20)
    idBox:SetAutoFocus(false)
    idBox:SetNumeric(true)
    idBox:SetPoint("LEFT", idLabel, "RIGHT", 10, 0)
    idBox:SetText(db.loot.raidID and tostring(db.loot.raidID) or "")
    idBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    UI.raidIDBox = idBox

    local record = Button(panel, "Aufzeichnen", 110, ToggleRecording)
    record:SetPoint("LEFT", idBox, "RIGHT", 10, 0)
    UI.recordButton = record

    local status = Label(panel, "", "GameFontHighlightSmall")
    status:SetPoint("LEFT", record, "RIGHT", 10, 0)
    UI.lootStatus = status

    local listBox, list = MakeScrollEdit(panel, "RaidSyncLootList", 420, 200, true)
    listBox:SetPoint("TOPLEFT", idLabel, "BOTTOMLEFT", 0, -12)
    UI.lootList = list

    local export = Button(panel, "Export", 90, ExportLoot)
    export:SetPoint("TOPLEFT", listBox, "BOTTOMLEFT", 0, -6)
    local removeLast = Button(panel, "Letzten entfernen", 120, RemoveLast)
    removeLast:SetPoint("LEFT", export, "RIGHT", 6, 0)
    local clear = Button(panel, "Leeren", 80, function() StaticPopup_Show("RAIDSYNC_CLEAR") end)
    clear:SetPoint("LEFT", removeLast, "RIGHT", 6, 0)

    local exportBox, exportEdit = MakeScrollEdit(panel, "RaidSyncLootExport", 420, 70)
    exportBox:SetPoint("TOPLEFT", export, "BOTTOMLEFT", 0, -6)
    exportEdit:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    UI.exportBox = exportEdit

    local hint = Label(panel, "Nur als Plündermeister wird aufgezeichnet. Einzelne Drops: /rs del <Nummer>", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", exportBox, "BOTTOMLEFT", 0, -4)
    hint:SetWidth(420)
end

local function ShowTab(name)
    UI.invitePanel:Hide()
    UI.lootPanel:Hide()
    UI[name .. "Panel"]:Show()
    UI.inviteTab:SetButtonState(name == "invite" and "PUSHED" or "NORMAL", name == "invite")
    UI.lootTab:SetButtonState(name == "loot" and "PUSHED" or "NORMAL", name == "loot")
end

local function BuildUI()
    local f = CreateFrame("Frame", "RaidSyncFrame", UIParent)
    f:SetWidth(460)
    f:SetHeight(520)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()
    tinsert(UISpecialFrames, "RaidSyncFrame")
    UI.frame = f

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    title:SetPoint("TOP", 0, -18)
    title:SetText("RaidSync")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)

    UI.inviteTab = Button(f, "Einladen", 100, function() ShowTab("invite") end)
    UI.inviteTab:SetPoint("TOPLEFT", 20, -40)
    UI.lootTab = Button(f, "Loot", 100, function() ShowTab("loot") end)
    UI.lootTab:SetPoint("LEFT", UI.inviteTab, "RIGHT", 6, 0)

    for _, name in ipairs({ "invite", "loot" }) do
        local panel = CreateFrame("Frame", nil, f)
        panel:SetPoint("TOPLEFT", 20, -72)
        panel:SetPoint("BOTTOMRIGHT", -20, 16)
        UI[name .. "Panel"] = panel
    end
    BuildInvitePanel(UI.invitePanel)
    BuildLootPanel(UI.lootPanel)
    f:SetScript("OnShow", function() RefreshInvites() RefreshLoot() end)
    ShowTab("invite")
end

StaticPopupDialogs["RAIDSYNC_CLEAR"] = {
    text = "Alle aufgezeichneten Drops löschen?",
    button1 = YES,
    button2 = NO,
    OnAccept = function() ClearLoot() end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
}

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local function BuildPatterns()
    local system = {
        { ERR_BAD_PLAYER_NAME_S, "nicht gefunden" },
        { ERR_ALREADY_IN_GROUP_S, "in anderer Gruppe" },
        { ERR_DECLINE_GROUP_S, "abgelehnt" },
        { ERR_JOINED_GROUP_S, "im Raid" },
        { ERR_RAID_MEMBER_ADDED_S, "im Raid" },
        { ERR_INVITE_PLAYER_S, "eingeladen" },
    }
    patterns.system = {}
    for _, entry in ipairs(system) do
        local p = Core.PatternFromFormat(entry[1])
        if p then patterns.system[#patterns.system + 1] = { pattern = p, status = entry[2] } end
    end
    patterns.lootOther = Core.PatternFromFormat(LOOT_ITEM)
    patterns.lootSelf = Core.PatternFromFormat(LOOT_ITEM_SELF)
end

local function OnSystemMessage(msg)
    for _, entry in ipairs(patterns.system) do
        local name = string.match(msg, entry.pattern)
        if name then
            local m = FindMember(name)
            if m then
                -- The invite confirmation keeps the invite time set when the invite was sent.
                if entry.status ~= "eingeladen" or m.status ~= "eingeladen" then m.status = entry.status end
                RefreshInvites()
            end
            return
        end
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("CHAT_MSG_SYSTEM")
events:RegisterEvent("CHAT_MSG_LOOT")
events:RegisterEvent("RAID_ROSTER_UPDATE")
events:RegisterEvent("PARTY_MEMBERS_CHANGED")
events:RegisterEvent("LOOT_OPENED")
events:RegisterEvent("LOOT_CLOSED")
events:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")

events:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        if ... ~= "RaidSync" then return end
        RaidSyncDB = RaidSyncDB or {}
        db = RaidSyncDB
        db.loot = db.loot or {}
        db.loot.entries = db.loot.entries or {}
        db.loot.sources = db.loot.sources or {}
        members = db.members or {}
        BuildPatterns()
        BuildUI()
        hooksecurefunc("GiveMasterLoot", OnMasterLootGiven)
    elseif not db then
        return
    elseif event == "CHAT_MSG_SYSTEM" then
        OnSystemMessage(...)
    elseif event == "CHAT_MSG_LOOT" then
        OnLootMessage(...)
    elseif event == "RAID_ROSTER_UPDATE" or event == "PARTY_MEMBERS_CHANGED" then
        UpdateGroupStatus()
    elseif event == "LOOT_OPENED" then
        OnLootOpened()
    elseif event == "LOOT_CLOSED" then
        wipe(currentSlots)
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        local _, subEvent, _, _, _, destGUID = ...
        if subEvent == "UNIT_DIED" then
            local npc = Core.NPCFromGUID(destGUID)
            if npc then lastKill = { npc = npc, guid = destGUID } end
        end
    end
end)

events:SetScript("OnUpdate", function(self, elapsed)
    if not inviting then return end
    inviteDelay = inviteDelay - elapsed
    if inviteDelay <= 0 then InviteStep() end
end)

---------------------------------------------------------------------------
-- Slash command
---------------------------------------------------------------------------

SLASH_RAIDSYNC1 = "/rs"
SLASH_RAIDSYNC2 = "/raidsync"
SlashCmdList["RAIDSYNC"] = function(msg)
    msg = Core.Trim(string.lower(msg or ""))
    local n = string.match(msg, "^del%s+(%d+)$")
    if n then
        RemoveEntry(tonumber(n))
    elseif UI.frame:IsShown() then
        UI.frame:Hide()
    else
        UI.frame:Show()
    end
end
