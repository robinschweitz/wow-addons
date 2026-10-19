-- RaidLedger editors and addon users (raid feedback 2026-10-19).
-- Editors: the names that may change the ledger (start rolls, award, park,
-- correct). Set in the SETTINGS panel or with /ledger allow|deny|editors,
-- saved for the account and shared with the group, so everybody else's ledger
-- only watches and ignores awards from non-editors. An empty list keeps the
-- old rules (anyone; rolls on bag items need the master looter or the lead).
-- Addon users: every ledger says hello with its version, RaidWishlist answers
-- too, and the panel shows which raid members run which addon.
-- Messages (prefix FLLedger, ";"-separated like every RaidLedger format):
--   HQ;<name>                  who runs the addons? (after login / joining a group)
--   H;<version>;<editor 0/1>   a ledger: its version, and whether it may edit
--   HW;<version>               a wishlist
--   E;<changedAt>;<name,...>   the editor list (empty: everyone may edit)
local addonName, ns = ...
local L = ns.L
local Ledger = ns.Ledger
local VERSION = GetAddOnMetadata and GetAddOnMetadata(addonName, "Version") or "?"
local EDITOR_SLOTS = 8
local COLUMNS, ROWS = 5, 5

local users = {}        -- lower(name) -> { name, ledger = version, editor = bool, wishlist = version }
local helloAt, askAt    -- when to send our hello (and ask the group for theirs)
local groupSize = 0

local function editors()
    local db = ns.ensureDatabase()
    db.editors = db.editors or {}
    return db.editors
end

local function listed(name)
    for _, editor in ipairs(editors()) do
        if ns.lower(editor) == ns.lower(name or "") then return true end
    end
    return false
end

function ns.hasEditors() return table.getn(editors()) > 0 end
function ns.mayEdit() return not ns.hasEditors() or listed(ns.playerName()) end
function ns.trusts(sender) return not ns.hasEditors() or listed(sender) end

-- capitalize writes a typed name like the client does ("cara" -> "Cara").
-- Only the first ASCII letter changes: string.lower/upper must never touch
-- the bytes of letters like "ä" (an emulated run turned "Seelenfänger" into
-- garbage that way); names are compared case-insensitively anyway.
local function capitalize(name)
    name = ns.trim(name or "")
    local first = string.sub(name, 1, 1)
    if first == "" or string.byte(first) > 127 then return name end
    return string.upper(first) .. string.sub(name, 2)
end

local function editorText()
    return table.getn(editors()) > 0 and table.concat(editors(), ", ") or L["nobody (everyone may change the ledger)"]
end

function ns.deniedText()
    return string.format(L["Only the editors may change the ledger: %s."], editorText())
end

local function shareEditors()
    if not ns.groupChannel() then return end
    ns.queue(table.concat({ "E", tostring(ns.ensureDatabase().editorsAt or 0), table.concat(editors(), ",") }, ";"))
end

local function sayHello(ask)
    if not ns.groupChannel() then return end
    if ask then ns.queue("HQ;" .. ns.field(ns.playerName())) end
    ns.queue(table.concat({ "H", VERSION, ns.mayEdit() and "1" or "0" }, ";"))
    if ns.hasEditors() and ns.mayEdit() then shareEditors() end
end

---------------------------------------------------------------------------
-- Settings panel
---------------------------------------------------------------------------
local panel = CreateFrame("Frame", "RaidLedgerSettings")
ns.makeBackdrop(panel, 0.035, 0.070, 0.105, 0.97)
local settingsButton   -- the tab's button, once refresh exists

local heading = ns.label(panel, "GameFontNormal", 11, {1.00, 0.80, 0.32})
heading:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -11)
heading:SetText(L["SETTINGS"])


local editorHeading = ns.label(panel, "GameFontNormal", 10, {0.54, 0.88, 1.00})
editorHeading:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -38)
editorHeading:SetText(L["EDITORS: MAY START ROLLS, AWARD AND CORRECT"])

local editorHint = ns.label(panel, "GameFontNormalSmall", 9, {0.45, 0.60, 0.68})
editorHint:SetPoint("TOPLEFT", editorHeading, "BOTTOMLEFT", 0, -4)
editorHint:SetText(L["Empty: everyone may, as before. Click a name to remove it. Shared with the group."])

local editorButtons = {}
for i = 1, EDITOR_SLOTS do
    local button = CreateFrame("Button", "RaidLedgerEditor" .. i, panel)
    button:SetWidth(128)
    button:SetHeight(18)
    button:SetPoint("TOPLEFT", panel, "TOPLEFT", 12 + ((i - 1) % 4) * 136, -72 - math.floor((i - 1) / 4) * 22)
    ns.makeBackdrop(button, 0.06, 0.16, 0.22, 0.98)
    local text = ns.label(button, "GameFontNormalSmall", 10, {1.00, 0.86, 0.45})
    text:SetPoint("LEFT", button, "LEFT", 6, 0)
    text:SetPoint("RIGHT", button, "RIGHT", -18, 0)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    button:SetFontString(text)
    button.remove = ns.label(button, "GameFontNormalSmall", 10, {0.95, 0.45, 0.45})
    button.remove:SetPoint("RIGHT", button, "RIGHT", -6, 0)
    button.remove:SetText("x")
    editorButtons[i] = button
end

local nameBox = CreateFrame("EditBox", "RaidLedgerEditorName", panel, "InputBoxTemplate")
nameBox:SetPoint("TOPLEFT", panel, "TOPLEFT", 18, -122)
nameBox:SetWidth(140)
nameBox:SetHeight(24)
nameBox:SetAutoFocus(false)
nameBox:SetMaxLetters(24)

local addButton = ns.flatButton(panel, L["ADD"], 70)
addButton:SetPoint("LEFT", nameBox, "RIGHT", 8, 0)
local targetButton = ns.flatButton(panel, L["+ TARGET"], 80)
targetButton:SetPoint("LEFT", addButton, "RIGHT", 6, 0)

local mineText = ns.label(panel, "GameFontNormalSmall", 10, {0.45, 0.85, 0.55})
mineText:SetPoint("LEFT", targetButton, "RIGHT", 12, 0)
mineText:SetWidth(216)
mineText:SetJustifyH("LEFT")
mineText:SetHeight(14)
mineText:SetWordWrap(false)

local usersHeading = ns.label(panel, "GameFontNormal", 10, {0.54, 0.88, 1.00})
usersHeading:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -166)

local checkButton = ns.flatButton(panel, L["CHECK"], 70)
checkButton:SetHeight(18)
checkButton:SetPoint("LEFT", usersHeading, "RIGHT", 12, 0)

local cells = {}
for column = 1, COLUMNS do
    cells[column] = {}
    for row = 1, ROWS do
        local cell = ns.label(panel, "GameFontNormalSmall", 9, {0.55, 0.55, 0.55})
        cell:SetPoint("TOPLEFT", panel, "TOPLEFT", 12 + (column - 1) * 109, -188 - (row - 1) * 17)
        cell:SetWidth(104)
        cell:SetJustifyH("LEFT")
        cell:SetWordWrap(false)
        cells[column][row] = cell
    end
end

local legend = ns.label(panel, "GameFontNormalSmall", 9, {0.45, 0.60, 0.68})
legend:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 12, 12)
legend:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -12, 12)
legend:SetJustifyH("LEFT")
legend:SetText(L["Green: RaidLedger (version)  |  blue: RaidWishlist only  |  grey: no addon  |  gold: editor"])

-- Options (everything that was a chat command only): roll lengths, the
-- minimap button, the window position, a sync of the awards.
local OPTIONS_X = 574
local optionsHeading = ns.label(panel, "GameFontNormal", 10, {0.54, 0.88, 1.00})
optionsHeading:SetPoint("TOPLEFT", panel, "TOPLEFT", OPTIONS_X, -38)
optionsHeading:SetText(L["ROLLS"])

local function secondsBox(name, caption, y)
    local text = ns.label(panel, "GameFontNormalSmall", 10, {0.75, 0.85, 0.92})
    text:SetPoint("TOPLEFT", panel, "TOPLEFT", OPTIONS_X, y - 5)
    text:SetText(caption)
    local box = CreateFrame("EditBox", name, panel, "InputBoxTemplate")
    box:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -16, y)
    box:SetWidth(40)
    box:SetHeight(22)
    box:SetAutoFocus(false)
    box:SetNumeric(true)
    box:SetMaxLetters(3)
    return box
end
local rollBox = secondsBox("RaidLedgerRollSeconds", L["Roll (s)"], -56)
local tieBox = secondsBox("RaidLedgerTieSeconds", L["Tie-break (s)"], -82)
local timerButton = ns.flatButton(panel, L["APPLY"], 136, "RaidLedgerApplyTimers")
timerButton:SetHeight(20)
timerButton:SetPoint("TOPLEFT", panel, "TOPLEFT", OPTIONS_X, -108)

local miscHeading = ns.label(panel, "GameFontNormal", 10, {0.54, 0.88, 1.00})
miscHeading:SetPoint("TOPLEFT", panel, "TOPLEFT", OPTIONS_X, -166)
miscHeading:SetText(L["WINDOW"])
local minimapButton = ns.flatButton(panel, L["MINIMAP: ON"], 136, "RaidLedgerMinimapToggle")
minimapButton:SetHeight(20)
minimapButton:SetPoint("TOPLEFT", panel, "TOPLEFT", OPTIONS_X, -184)
local centerButton = ns.flatButton(panel, L["CENTER WINDOW"], 136)
centerButton:SetHeight(20)
centerButton:SetPoint("TOPLEFT", panel, "TOPLEFT", OPTIONS_X, -208)
local syncButton = ns.flatButton(panel, L["SYNC AWARDS"], 136, "RaidLedgerSync")
syncButton:SetHeight(20)
syncButton:SetPoint("TOPLEFT", panel, "TOPLEFT", OPTIONS_X, -232)

function ns.refreshOptions()
    if not rollBox:HasFocus() then rollBox:SetText(tostring(ns.core.rollSeconds())) end
    if not tieBox:HasFocus() then tieBox:SetText(tostring(ns.core.tieSeconds())) end
    minimapButton:SetText(ns.ensureDatabase().minimapHidden and L["MINIMAP: OFF"] or L["MINIMAP: ON"])
end

timerButton:SetScript("OnClick", function()
    local roll, tie = tonumber(rollBox:GetText()), tonumber(tieBox:GetText())
    rollBox:ClearFocus()
    tieBox:ClearFocus()
    if ns.core.roster.setTimers(roll, tie) then
        ns.say(string.format(L["roll timer: %d seconds, tie-break: %d seconds."], ns.core.rollSeconds(), ns.core.tieSeconds()))
    else
        local limits, tieLimits = ns.core.ROLL_LIMITS, ns.core.TIE_LIMITS
        ns.say(string.format(L["usage: /ledger timer [seconds] [tie-break seconds] (roll %d-%d, tie-break %d-%d), or /ledger timer reset"],
            limits[1], limits[2], tieLimits[1], tieLimits[2]))
    end
    ns.refreshOptions()
end)
minimapButton:SetScript("OnClick", function()
    ns.commands.minimap(ns.ensureDatabase().minimapHidden and "on" or "off")
    ns.refreshOptions()
end)
centerButton:SetScript("OnClick", function() ns.ui.resetPosition() end)
syncButton:SetScript("OnClick", function() ns.core.sync() end)
ns.tip(rollBox, L["How long a roll runs; reminders come at half and a quarter of it"])
ns.tip(tieBox, L["How long a tie-break runs"])
ns.tip(timerButton, L["Use these lengths for the next rolls (a running roll keeps its time)"])
ns.tip(minimapButton, L["Show or hide the minimap button"])
ns.tip(centerButton, L["Move this window back to the middle of the screen"])
ns.tip(syncButton, L["Ask the group's other ledgers for this raid's awards (e.g. after a crash)"])

local function userOf(name)
    if ns.isPlayer(name) then return { name = name, ledger = VERSION, editor = ns.mayEdit() } end
    return users[ns.lower(name)]
end

local function refresh()
    local list = editors()
    for i, button in ipairs(editorButtons) do
        local name = list[i]
        button.name = name
        if name then
            button:SetText(i == EDITOR_SLOTS and table.getn(list) > EDITOR_SLOTS
                and string.format(L["%s (+%d)"], name, table.getn(list) - EDITOR_SLOTS) or name)
            button:Show()
        else
            button:Hide()
        end
    end
    if not ns.hasEditors() then
        mineText:SetText(L["No editors: everyone may change the ledger."])
        mineText:SetTextColor(0.58, 0.79, 0.88)
    elseif ns.mayEdit() then
        mineText:SetText(L["You are an editor."])
        mineText:SetTextColor(0.45, 0.85, 0.55)
    else
        mineText:SetText(L["You only watch: not an editor."])
        mineText:SetTextColor(1.00, 0.60, 0.25)
    end
    -- The group, one column per raid group (a party is group 1).
    local members = ns.members()
    local rows, withAddon = {}, 0
    for column = 1, COLUMNS do
        rows[column] = 0
        for row = 1, ROWS do cells[column][row]:Hide() end
    end
    for _, member in ipairs(members) do
        local user = userOf(member.name)
        if user and (user.ledger or user.wishlist) then withAddon = withAddon + 1 end
        local column = math.min(math.max(tonumber(member.group) or 1, 1), COLUMNS)
        if rows[column] < ROWS then
            rows[column] = rows[column] + 1
            local cell = cells[column][rows[column]]
            if user and user.ledger then
                cell:SetText(member.name .. "  " .. user.ledger)
                if listed(member.name) then cell:SetTextColor(1.00, 0.86, 0.45)
                else cell:SetTextColor(0.45, 0.85, 0.55) end
            elseif user and user.wishlist then
                cell:SetText(member.name .. "  WL " .. user.wishlist)
                cell:SetTextColor(0.45, 0.70, 1.00)
            else
                cell:SetText(member.name .. "  -")
                cell:SetTextColor(0.50, 0.50, 0.50)
            end
            cell:Show()
        end
    end
    usersHeading:SetText(string.format(L["ADDON IN THE GROUP (%d/%d)"], withAddon, table.getn(members)))
end
ns.refreshSettings = function() if panel:IsShown() then refresh() end end
settingsButton = ns.addTab("settings", L["SETTINGS"], panel, function() refresh() ns.refreshOptions() end,
    "RaidLedgerSettingsButton").button

local function showSettings() ns.ui.show("settings") end

-- changeEditors adds or removes a name; only editors may change a list (an
-- empty one: anybody, who then becomes an editor too).
local function changeEditors(name, add)
    if not ns.mayEdit() then
        ns.say(ns.deniedText())
        return false
    end
    name = capitalize(name)
    if name == "" then
        ns.say(L["usage: /ledger allow|deny <name>"])
        return false
    end
    local list = editors()
    if add then
        if listed(name) then return false end
        table.insert(list, name)
        if not listed(ns.playerName()) then table.insert(list, ns.playerName()) end
    else
        for i = table.getn(list), 1, -1 do
            if ns.lower(list[i]) == ns.lower(name) then table.remove(list, i) end
        end
    end
    ns.ensureDatabase().editorsAt = time()
    shareEditors()
    ns.say(string.format(L["editors: %s"], editorText()))
    refresh()
    ns.ui.refresh()
    return true
end

-- acceptEditors takes a newer list from an editor of ours (or, while we have
-- none, from someone on the list they send).
local function acceptEditors(f, sender)
    local at = tonumber(f[2])
    if not at or at <= (ns.ensureDatabase().editorsAt or 0) then return end
    local names = {}
    for name in string.gmatch(f[3] or "", "[^,]+") do table.insert(names, name) end
    local fromList = false
    for _, name in ipairs(names) do
        if ns.lower(name) == ns.lower(sender) then fromList = true end
    end
    if ns.hasEditors() and not listed(sender) then return end
    if not ns.hasEditors() and not fromList then return end
    local db = ns.ensureDatabase()
    db.editors, db.editorsAt = names, at
    ns.say(string.format(L["%s shared the editors: %s"], sender, editorText()))
    refresh()
    ns.ui.refresh()
end

-- onMessage handles hellos and editor lists; true when the message is done.
function ns.onMessage(f, sender)
    local kind = f[1]
    local key = ns.lower(sender)
    if kind == "HQ" then
        helloAt = helloAt or (GetTime() + 1)
    elseif kind == "H" then
        users[key] = users[key] or { name = sender }
        users[key].ledger, users[key].editor = f[2] ~= "" and f[2] or "?", f[3] == "1"
    elseif kind == "HW" then
        users[key] = users[key] or { name = sender }
        users[key].wishlist = f[2] ~= "" and f[2] or "?"
    elseif kind == "W" then
        users[key] = users[key] or { name = sender }
        users[key].wishlist = users[key].wishlist or "?"
        ns.refreshSettings()
        return false
    elseif kind == "E" then
        acceptEditors(f, sender)
        return true
    else
        return false
    end
    ns.refreshSettings()
    return true
end

-- lootRecorder: of the ledgers in the group that may edit (with an empty
-- list: the leader and assistants), the first by name records group loot,
-- so two ledgers never record it twice. Without one, the first ledger does.
function ns.isLootRecorder()
    local eligible, everyone = {}, {}
    local rank = {}
    for i = 1, GetNumRaidMembers() or 0 do
        local name, memberRank = GetRaidRosterInfo(i)
        if name then rank[ns.lower(name)] = memberRank or 0 end
    end
    local party = (GetNumRaidMembers() or 0) == 0
    for _, member in ipairs(ns.members()) do
        local user = userOf(member.name)
        if user and user.ledger then
            table.insert(everyone, ns.lower(member.name))
            local may
            if ns.hasEditors() then may = listed(member.name)
            elseif party then may = ns.isPlayer(member.name) and IsPartyLeader() and true or false
            else may = (rank[ns.lower(member.name)] or 0) > 0 end
            if may then table.insert(eligible, ns.lower(member.name)) end
        end
    end
    local pool = table.getn(eligible) > 0 and eligible or everyone
    if table.getn(pool) == 0 then return true end
    table.sort(pool)
    return pool[1] == ns.lower(ns.playerName())
end

nameBox:SetScript("OnEnterPressed", function(self)
    if changeEditors(self:GetText(), true) then self:SetText("") end
    self:ClearFocus()
end)
nameBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
addButton:SetScript("OnClick", function()
    if changeEditors(nameBox:GetText(), true) then nameBox:SetText("") end
end)
targetButton:SetScript("OnClick", function()
    if UnitExists("target") and UnitIsPlayer("target") then changeEditors(UnitName("target"), true)
    else ns.say(L["target a player to add them."]) end
end)
for _, button in ipairs(editorButtons) do
    button:SetScript("OnClick", function(self) if self.name then changeEditors(self.name, false) end end)
end
checkButton:SetScript("OnClick", function()
    if ns.groupChannel() then sayHello(true) else ns.say(L["not in a group."]) end
end)

ns.tip(settingsButton, L["Editors and who in the group runs RaidLedger or RaidWishlist"])
ns.tip(addButton, L["Add the name in the box as an editor (the first one also adds you)"])
ns.tip(targetButton, L["Add your target as an editor"])
ns.tip(checkButton, L["Ask the group again which addons they run"])
for _, button in ipairs(editorButtons) do ns.tip(button, L["Click: no longer an editor"]) end
ns.tip(nameBox, L["Name of a new editor; Enter adds it"])

---------------------------------------------------------------------------
-- Events, timers, commands
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("RAID_ROSTER_UPDATE")
events:RegisterEvent("PARTY_MEMBERS_CHANGED")
events:SetScript("OnEvent", function(_, event)
    local size = math.max(GetNumRaidMembers() or 0, GetNumPartyMembers() or 0)
    if event == "PLAYER_LOGIN" then
        helloAt, askAt = GetTime() + 9, true
        if ForgeTestBridge and ForgeTestBridge.RegisterFrame then
            ForgeTestBridge:RegisterFrame("RaidLedgerSettings", panel)
            ForgeTestBridge:RegisterFrame("RaidLedgerSettingsButton", settingsButton)
        end
    elseif size > groupSize then
        -- Joining a group: ask who runs what. Someone else joining: say hello.
        helloAt = helloAt or (GetTime() + 5)
        if groupSize == 0 then askAt = true end
    end
    groupSize = size
    ns.refreshSettings()
end)
events:SetScript("OnUpdate", function()
    if helloAt and GetTime() >= helloAt then
        helloAt = nil
        sayHello(askAt)
        askAt = nil
    end
end)

ns.commands.allow = function(rest) changeEditors(rest, true) end
ns.commands.deny = function(rest) changeEditors(rest, false) end
ns.commands.editors = function() ns.say(string.format(L["editors: %s"], editorText())) end
ns.commands.settings = function() showSettings(true) end
table.insert(ns.help, L["/ledger allow|deny <name> - add or remove an editor;  /ledger editors - list them"])
table.insert(ns.help, L["/ledger settings - editors and who runs the addons"])
