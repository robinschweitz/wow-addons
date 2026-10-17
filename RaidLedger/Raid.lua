-- RaidLedger raid setup, taken over from RaidSync: read the raid website's
-- invite list, invite everyone (and retry the missing), sort raid groups by
-- role, and export who was really in the raid for the website's roster import.
-- Text formats, ";"-separated like every RaidLedger export (a WoW edit box
-- treats "|" as the start of an escape sequence):
--   invite list (website -> addon): RS2;INV;<raidID>;<raidName>;<size>
--                                   <name>;<TANK|HEAL|DD>;<class>;<bench 0/1>
--   attendance (addon -> website):  RS2;ROSTER;<raidID>;<recorder>;<exportUnix>
--                                   <name>;<classToken or ->;<firstSeenUnix>
local _, ns = ...
local L = ns.L
local FORMAT = "RS2"
local INVITE_DELAY = 0.3    -- seconds between invites
local INVITE_EXPIRY = 65    -- an unanswered invite stops reserving a party slot
local MEMBER_ROWS = 14

local STATUS_LABELS = {
    open = L["open"], invited = L["invited"], joined = L["in raid"], declined = L["declined"],
    notfound = L["not found"], othergroup = L["in another group"], offline = L["offline"],
    noanswer = L["no answer"], bench = L["bench"],
}
local STATUS_COLORS = {
    open = {0.85, 0.85, 0.85}, invited = {1.00, 0.85, 0.30}, joined = {0.45, 0.85, 0.55},
    declined = {1.00, 0.40, 0.40}, notfound = {1.00, 0.40, 0.40}, othergroup = {1.00, 0.60, 0.25},
    offline = {0.55, 0.55, 0.55}, noanswer = {1.00, 0.60, 0.25}, bench = {0.55, 0.55, 0.55},
}
local ROLE_LABELS = { TANK = "Tank", HEAL = "Heal", DD = "DD" }
local ROLE_ORDER = { TANK = 1, HEAL = 2, DD = 3 }

local MAX_CONVERT_TRIES = 3  -- a party below level 10 cannot become a raid
local queue, inviting, inviteDelay = {}, false, 0
local convertTries, convertFailed = 0, false
local memberOffset = 0
local patterns

local function setup()
    local db = ns.ensureDatabase()
    db.setup = db.setup or { members = {}, seen = {} }
    db.setup.members = db.setup.members or {}
    db.setup.seen = db.setup.seen or {}
    return db.setup
end

local function split(line, separator)
    local fields, start = {}, 1
    while true do
        local i = string.find(line, separator, start, true)
        if not i then
            table.insert(fields, string.sub(line, start))
            return fields
        end
        table.insert(fields, string.sub(line, start, i - 1))
        start = i + 1
    end
end

-- parseInvite reads the website's invite list.
local function parseInvite(text)
    text = text or ""
    local lines = {}
    for line in string.gmatch(string.gsub(text, "\r", "") .. "\n", "([^\n]*)\n") do
        line = ns.trim(line)
        if line ~= "" then table.insert(lines, line) end
    end
    if table.getn(lines) == 0 then return nil, L["Paste the website's invite list first."] end
    local header = split(lines[1], ";")
    if table.getn(header) ~= 5 or header[1] ~= FORMAT or header[2] ~= "INV" or not tonumber(header[3]) then
        return nil, L["That is not the website's invite list."]
    end
    local raid = { id = tonumber(header[3]), name = header[4], size = tonumber(header[5]) }
    local members, bad = {}, {}
    for i = 2, table.getn(lines) do
        local f = split(lines[i], ";")
        if table.getn(f) == 4 and f[1] ~= "" then
            table.insert(members, { name = f[1], role = f[2], class = f[3], bench = f[4] == "1", status = "open" })
        else
            table.insert(bad, lines[i])
        end
    end
    return raid, nil, members, bad
end

-- buildRoster lists everyone seen in the raid, earliest first.
local function buildRoster(raidID, recorder, exportedAt, seen)
    local list = {}
    for _, entry in pairs(seen) do table.insert(list, entry) end
    table.sort(list, function(a, b)
        if a.first ~= b.first then return a.first < b.first end
        return ns.lower(a.name) < ns.lower(b.name)
    end)
    local lines = { table.concat({ FORMAT, "ROSTER", tostring(raidID), ns.field(recorder), tostring(exportedAt) }, ";") }
    for _, entry in ipairs(list) do
        table.insert(lines, table.concat({ ns.field(entry.name), ns.field(entry.class or "-"), tostring(entry.first) }, ";"))
    end
    return table.concat(lines, "\n")
end

-- groupTargets sorts names by role (tanks, healers, the rest, then by name)
-- and returns the subgroup each should be in.
local function groupTargets(names, roleOf)
    local sorted = {}
    for _, name in ipairs(names) do table.insert(sorted, name) end
    table.sort(sorted, function(a, b)
        local pa, pb = ROLE_ORDER[roleOf[ns.lower(a)] or ""] or 4, ROLE_ORDER[roleOf[ns.lower(b)] or ""] or 4
        if pa ~= pb then return pa < pb end
        return ns.lower(a) < ns.lower(b)
    end)
    local targets = {}
    for i, name in ipairs(sorted) do targets[name] = math.floor((i - 1) / 5) + 1 end
    return targets
end

local function groupNames()
    local names = { [ns.lower(ns.playerName())] = true }
    if (GetNumRaidMembers() or 0) > 0 then
        for i = 1, GetNumRaidMembers() do
            local name = GetRaidRosterInfo(i)
            if name then names[ns.lower(name)] = true end
        end
    else
        for i = 1, GetNumPartyMembers() or 0 do
            local name = UnitName("party" .. i)
            if name then names[ns.lower(name)] = true end
        end
    end
    return names
end

-- guildOnline only knows the members the guild roster lists right now.
local function guildOnline()
    local online = {}
    if not IsInGuild() then return online end
    for i = 1, GetNumGuildMembers() or 0 do
        local name, _, _, _, _, _, _, _, isOnline = GetGuildRosterInfo(i)
        if name then online[ns.lower(name)] = isOnline and true or false end
    end
    return online
end

local function canManageGroup()
    if (GetNumRaidMembers() or 0) > 0 then return IsRaidLeader() or IsRaidOfficer() end
    if (GetNumPartyMembers() or 0) > 0 then return IsPartyLeader() end
    return true
end

local function pendingInvites()
    local count, now = 0, GetTime()
    for _, member in ipairs(setup().members) do
        if member.status == "invited" then
            if now - (member.invitedAt or now) > INVITE_EXPIRY then
                member.status = "noanswer"
            else
                count = count + 1
            end
        end
    end
    return count
end

---------------------------------------------------------------------------
-- Panel
---------------------------------------------------------------------------
local Ledger = ns.Ledger
local panel = CreateFrame("Frame", "RaidLedgerRaidPanel", Ledger)
panel:SetPoint("TOPLEFT", Ledger, "TOPLEFT", 16, -48)
panel:SetWidth(568)
panel:SetHeight(332)
ns.makeBackdrop(panel, 0.035, 0.070, 0.105, 0.97)
panel:Hide()
ns.addOverlay(panel)

local raidButton = ns.flatButton(Ledger, L["RAID"], 56)
_G.RaidLedgerRaidButton = raidButton
raidButton:SetPoint("RIGHT", ns.headerButton, "LEFT", -8, 0)

local heading = ns.label(panel, "GameFontNormal", 11, {1.00, 0.80, 0.32})
heading:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -11)
heading:SetText(L["RAID SETUP"])

local backButton = ns.flatButton(panel, L["BACK"], 70)
backButton:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -12, -6)

local hint = ns.label(panel, "GameFontNormalSmall", 9, {0.55, 0.72, 0.80})
hint:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -34)
hint:SetWidth(300)
hint:SetJustifyH("LEFT")
hint:SetText(L["Paste the website's invite list (Raid > Aufstellung > Einladungen für Addon):"])

local function textArea(name, top, height)
    local back = CreateFrame("Frame", nil, panel)
    back:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, top)
    back:SetWidth(300)
    back:SetHeight(height)
    ns.makeBackdrop(back, 0.01, 0.02, 0.03, 0.98)
    local scroll = CreateFrame("ScrollFrame", nil, back)
    scroll:SetPoint("TOPLEFT", back, "TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", back, "BOTTOMRIGHT", -6, 6)
    scroll:EnableMouseWheel(true)
    local edit = CreateFrame("EditBox", name, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject(ChatFontNormal)
    edit:SetWidth(286)
    edit:SetHeight(height - 12)
    scroll:SetScrollChild(edit)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local range = self:GetVerticalScrollRange() or 0
        self:SetVerticalScroll(math.max(0, math.min(range, self:GetVerticalScroll() - delta * 28)))
    end)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return edit
end

local inviteText = textArea("RaidLedgerInviteText", -60, 84)

local readButton = ns.flatButton(panel, L["READ"], 64)
readButton:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -152)
local inviteButton = ns.flatButton(panel, L["INVITE ALL"], 104)
inviteButton:SetPoint("LEFT", readButton, "RIGHT", 6, 0)
local retryButton = ns.flatButton(panel, L["RETRY MISSING"], 120)
retryButton:SetPoint("LEFT", inviteButton, "RIGHT", 6, 0)
local benchButton = ns.flatButton(panel, L["BENCH: NO"], 140)
benchButton:SetHeight(20)
benchButton:SetPoint("TOPLEFT", readButton, "BOTTOMLEFT", 0, -6)

local attendanceHeading = ns.label(panel, "GameFontNormal", 10, {1.00, 0.80, 0.32})
attendanceHeading:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -212)
attendanceHeading:SetText(L["ATTENDANCE FOR THE WEBSITE"])
local attendanceButton = ns.flatButton(panel, L["EXPORT"], 70)
_G.RaidLedgerAttendance = attendanceButton
attendanceButton:SetHeight(20)
attendanceButton:SetPoint("TOPRIGHT", panel, "TOPLEFT", 312, -206)
local rosterText = textArea("RaidLedgerRosterText", -234, 86)
rosterText:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
-- Read-only: typing restores the generated text.
rosterText:SetScript("OnTextChanged", function(self, userInput)
    if userInput and self.generated and self:GetText() ~= self.generated then self:SetText(self.generated) end
end)

local listBack = CreateFrame("Frame", "RaidLedgerRaidMembers", panel)
listBack:SetPoint("TOPLEFT", panel, "TOPLEFT", 324, -34)
listBack:SetWidth(232)
listBack:SetHeight(MEMBER_ROWS * 15 + 30)
ns.makeBackdrop(listBack, 0.02, 0.045, 0.07, 0.98)
listBack:EnableMouseWheel(true)

local listHeading = ns.label(listBack, "GameFontNormalSmall", 9, {0.55, 0.72, 0.80})
listHeading:SetPoint("TOPLEFT", listBack, "TOPLEFT", 8, -8)
listHeading:SetPoint("TOPRIGHT", listBack, "TOPRIGHT", -8, -8)
listHeading:SetJustifyH("LEFT")
listHeading:SetWordWrap(false)

local memberRows = {}
for i = 1, MEMBER_ROWS do
    local row = CreateFrame("Frame", "RaidLedgerRaidMember" .. i, listBack)
    row:SetPoint("TOPLEFT", listBack, "TOPLEFT", 8, -22 - (i - 1) * 15)
    row:SetPoint("TOPRIGHT", listBack, "TOPRIGHT", -8, -22 - (i - 1) * 15)
    row:SetHeight(14)
    row.text = ns.label(row, "GameFontNormalSmall", 10, {0.82, 0.91, 0.96})
    row.text:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.text:SetPoint("RIGHT", row, "RIGHT", -96, 0)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)
    row.state = ns.label(row, "GameFontNormalSmall", 9)
    row.state:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.state:SetJustifyH("RIGHT")
    memberRows[i] = row
end

local sortButton = ns.flatButton(panel, L["SORT GROUPS"], 140)
sortButton:SetPoint("TOPRIGHT", listBack, "BOTTOMRIGHT", 0, -8)

local function updatePanel()
    local data = setup()
    local members = data.members
    local joined = 0
    for _, member in ipairs(members) do
        if member.status == "joined" then joined = joined + 1 end
    end
    local head = data.raid and string.format(L["Raid #%d %s: %d / %d in the raid"], data.raid.id, data.raid.name or "",
        joined, table.getn(members)) or L["No invite list read yet."]
    if inviting then head = head .. L["  inviting..."] end
    listHeading:SetText(head)
    memberOffset = math.max(0, math.min(memberOffset, table.getn(members) - MEMBER_ROWS))
    for i = 1, MEMBER_ROWS do
        local row, member = memberRows[i], members[i + memberOffset]
        if member then
            row.text:SetText(string.format("%s  %s", member.name, ROLE_LABELS[member.role] or member.role or ""))
            row.state:SetText(STATUS_LABELS[member.status] or member.status)
            local color = STATUS_COLORS[member.status] or STATUS_COLORS.open
            row.state:SetTextColor(color[1], color[2], color[3])
            row:Show()
        else
            row:Hide()
        end
    end
    benchButton:SetText(data.includeBench and L["BENCH: YES"] or L["BENCH: NO"])
end

listBack:SetScript("OnMouseWheel", function(_, delta)
    memberOffset = memberOffset - delta
    updatePanel()
end)

---------------------------------------------------------------------------
-- Invites
---------------------------------------------------------------------------
local function readInvites()
    local raid, err, members, bad = parseInvite(inviteText:GetText())
    if not raid then
        ns.say(err)
        return
    end
    for _, line in ipairs(bad) do ns.say(string.format(L["skipped line: %s"], line)) end
    local data = setup()
    if not data.raid or data.raid.id ~= raid.id then data.seen = {} end   -- a new raid's attendance
    data.raid, data.members = raid, members
    -- The loot export uses the same raid unless awards for another raid exist.
    if not ns.raidID() or ns.historyCount() == 0 then ns.setRaidID(raid.id) end
    local inGroup = groupNames()
    for _, member in ipairs(members) do
        if inGroup[ns.lower(member.name)] then
            member.status = "joined"
        elseif member.bench and not data.includeBench then
            member.status = "bench"
        end
    end
    memberOffset = 0
    ns.say(string.format(L["%d characters read for raid #%d."], table.getn(members), raid.id))
    updatePanel()
end

local function startInvites(retryMissing)
    local data = setup()
    if table.getn(data.members) == 0 then
        ns.say(L["Read the website's invite list first."])
        return
    end
    if not canManageGroup() then
        ns.say(L["Only the raid lead or an assistant can invite."])
        return
    end
    local inGroup, online = groupNames(), guildOnline()
    queue = {}
    for _, member in ipairs(data.members) do
        local key = ns.lower(member.name)
        if inGroup[key] then
            member.status = "joined"
        elseif member.bench and not data.includeBench then
            member.status = "bench"
        elseif online[key] == false then
            member.status = "offline"
        elseif member.status == "open" or member.status == "bench"
            or (retryMissing and member.status ~= "invited") then
            table.insert(queue, member)
        end
    end
    if table.getn(queue) == 0 then
        ns.say(L["Nobody left to invite."])
        updatePanel()
        return
    end
    inviting, inviteDelay = true, 0
    convertTries, convertFailed = 0, false
    ns.say(string.format(L["Inviting %d characters."], table.getn(queue)))
    updatePanel()
end

local function inviteStep()
    if (GetNumRaidMembers() or 0) == 0 then
        if (GetNumPartyMembers() or 0) > 0 and IsPartyLeader() and not convertFailed then
            -- More than five players need a raid; convert once someone joined.
            -- The server ignores it while someone is below level 10: then keep
            -- inviting into the party as long as there is room.
            convertTries = convertTries + 1
            if convertTries <= MAX_CONVERT_TRIES then
                ConvertToRaid()
                inviteDelay = 1
                return
            end
            convertFailed = true
            ns.say(L["The group did not become a raid: everyone must be level 10 or higher."])
        end
        if (GetNumPartyMembers() or 0) + pendingInvites() >= 4 then
            inviteDelay = 0.5
            return
        end
    end
    local member = table.remove(queue, 1)
    if not member then
        inviting = false
        ns.say(L["All invites sent."])
        updatePanel()
        return
    end
    member.status, member.invitedAt = "invited", GetTime()
    InviteUnit(member.name)
    inviteDelay = INVITE_DELAY
    updatePanel()
end

-- recordAttendance remembers everyone in the raid and since when, so late
-- additions (e.g. from the world chat) reach the website too.
local function recordAttendance()
    if (GetNumRaidMembers() or 0) == 0 then return end
    local seen = setup().seen
    for i = 1, GetNumRaidMembers() do
        local name, _, _, _, _, classToken = GetRaidRosterInfo(i)
        if name and not seen[ns.lower(name)] then
            seen[ns.lower(name)] = { name = name, class = classToken, first = time() }
        end
    end
end

local function exportAttendance()
    local data = setup()
    local raidID = (data.raid and data.raid.id) or ns.raidID()
    if not raidID then
        ns.say(L["Read the invite list or set the raid ID first."])
        return
    end
    recordAttendance()
    if not next(data.seen) then
        ns.say(L["Nobody seen in the raid yet."])
        return
    end
    rosterText.generated = buildRoster(raidID, ns.playerName(), time(), data.seen)
    rosterText:SetText(rosterText.generated)
    rosterText:SetFocus()
    rosterText:HighlightText()
    ns.setStatus(L["Attendance selected: press Ctrl+C and paste it into the raid website's roster import."])
end

local function updateGroupStatus()
    recordAttendance()
    local inGroup = groupNames()
    for _, member in ipairs(setup().members) do
        if inGroup[ns.lower(member.name)] then
            member.status = "joined"
        elseif member.status == "joined" then
            member.status = "open"
        end
    end
    updatePanel()
end

local function sortGroups()
    if (GetNumRaidMembers() or 0) == 0 or not (IsRaidLeader() or IsRaidOfficer()) then
        ns.say(L["Sorting groups only works in a raid, as raid lead or assistant."])
        return
    end
    local roleOf, names, index, group, counts = {}, {}, {}, {}, {}
    for _, member in ipairs(setup().members) do roleOf[ns.lower(member.name)] = member.role end
    for i = 1, GetNumRaidMembers() do
        local name, _, subgroup = GetRaidRosterInfo(i)
        if name then
            table.insert(names, name)
            index[name], group[name] = i, subgroup
            counts[subgroup] = (counts[subgroup] or 0) + 1
        end
    end
    local targets = groupTargets(names, roleOf)
    local moves = 0
    for _, name in ipairs(names) do
        local target = targets[name]
        if group[name] ~= target then
            local swapWith
            for _, other in ipairs(names) do
                if group[other] == target and targets[other] ~= target then
                    swapWith = other
                    break
                end
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
    ns.say(moves > 0 and string.format(L["%d players moved (tanks, healers, the rest)."], moves)
        or L["Groups are already sorted."])
end

---------------------------------------------------------------------------
-- Buttons, events, commands
---------------------------------------------------------------------------
local function showPanel(show)
    ns.showOverlay(show and panel or nil)
    if show then
        inviteText:SetText(setup().text or "")
        updatePanel()
    else
        inviteText:ClearFocus()
        rosterText:ClearFocus()
    end
end

raidButton:SetScript("OnClick", function() showPanel(not panel:IsShown()) end)
backButton:SetScript("OnClick", function() showPanel(false) end)
inviteText:SetScript("OnTextChanged", function(self) setup().text = self:GetText() end)
readButton:SetScript("OnClick", readInvites)
inviteButton:SetScript("OnClick", function() startInvites(false) end)
retryButton:SetScript("OnClick", function() startInvites(true) end)
benchButton:SetScript("OnClick", function()
    local data = setup()
    data.includeBench = not data.includeBench or nil
    for _, member in ipairs(data.members) do
        if member.bench and member.status == "bench" and data.includeBench then member.status = "open" end
        if member.bench and member.status == "open" and not data.includeBench then member.status = "bench" end
    end
    updatePanel()
end)
attendanceButton:SetScript("OnClick", exportAttendance)
sortButton:SetScript("OnClick", sortGroups)

-- System messages tell what became of an invite.
local function buildPatterns()
    patterns = {}
    for _, entry in ipairs({
        { ERR_BAD_PLAYER_NAME_S, "notfound" }, { ERR_ALREADY_IN_GROUP_S, "othergroup" },
        { ERR_DECLINE_GROUP_S, "declined" }, { ERR_JOINED_GROUP_S, "joined" },
        { ERR_RAID_MEMBER_ADDED_S, "joined" }, { ERR_INVITE_PLAYER_S, "invited" },
    }) do
        local pattern = ns.patternFromFormat(entry[1])
        if pattern then table.insert(patterns, { pattern = pattern, status = entry[2] }) end
    end
end

local function onSystemMessage(message)
    if not patterns then buildPatterns() end
    for _, entry in ipairs(patterns) do
        local name = string.match(message or "", entry.pattern)
        if name then
            name = string.match(name, "|Hplayer:([^:|]+)") or name   -- linked names
            for _, member in ipairs(setup().members) do
                if ns.lower(member.name) == ns.lower(name) then
                    -- The invite confirmation keeps the time the invite was sent.
                    if entry.status ~= "invited" or member.status ~= "invited" then member.status = entry.status end
                    updatePanel()
                end
            end
            return
        end
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("CHAT_MSG_SYSTEM")
events:RegisterEvent("RAID_ROSTER_UPDATE")
events:RegisterEvent("PARTY_MEMBERS_CHANGED")
events:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        setup()
        updatePanel()
        if ForgeTestBridge and ForgeTestBridge.RegisterFrame then
            ForgeTestBridge:RegisterFrame("RaidLedgerRaidButton", raidButton)
            ForgeTestBridge:RegisterFrame("RaidLedgerRaidPanel", panel)
            ForgeTestBridge:RegisterFrame("RaidLedgerInviteText", inviteText)
            ForgeTestBridge:RegisterFrame("RaidLedgerRead", readButton)
            ForgeTestBridge:RegisterFrame("RaidLedgerInviteAll", inviteButton)
            ForgeTestBridge:RegisterFrame("RaidLedgerAttendance", attendanceButton)
            ForgeTestBridge:RegisterFrame("RaidLedgerRosterText", rosterText)
            ForgeTestBridge:RegisterFrame("RaidLedgerRaidStatus", listHeading)
            ForgeTestBridge:RegisterFrame("RaidLedgerRaidMember1", memberRows[1].state)
        end
    elseif event == "CHAT_MSG_SYSTEM" then
        onSystemMessage(...)
    else
        updateGroupStatus()
    end
end)
events:SetScript("OnUpdate", function(_, elapsed)
    if not inviting then return end
    inviteDelay = inviteDelay - elapsed
    if inviteDelay <= 0 then inviteStep() end
end)

ns.commands.setup = function() showPanel(true) end
ns.commands.invite = function(rest) startInvites(ns.lower(rest) == "missing") end
ns.commands.groups = sortGroups
ns.commands.attendance = function()
    showPanel(true)
    exportAttendance()
end
table.insert(ns.help, L["/ledger setup - invites, groups and attendance (RAID button)"])
table.insert(ns.help, L["/ledger invite [missing] - invite the website's list (or retry the missing)"])
table.insert(ns.help, L["/ledger groups - sort raid groups: tanks, healers, the rest"])
table.insert(ns.help, L["/ledger attendance - export who was in the raid for the website"])
