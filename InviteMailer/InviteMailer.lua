-- InviteMailer for WoW 3.3.5a
-- Sends one letter per "Name:Code" line while a mailbox is open.
-- /im          toggle window
-- /im reset    forget who already received a letter

local DEFAULT_SUBJECT = "Your invite code"
local DEFAULT_BODY = "Hi {name},\n\nhere is your invite code for our loot wishlist site:\n\n{code}\n\nSee you in the raid!"

local SEND_DELAY = 0.5   -- seconds between letters after a success
local TIMEOUT    = 15    -- seconds to wait for the server before counting a letter as failed
local POSTAGE    = 30    -- copper per letter

local UI = {}
local queue, idx = {}, 0
local current
local sending, waiting, mailboxOpen = false, false, false
local waitElapsed, delayLeft = 0, 0
local lastError
local sentCount, failed = 0, {}

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffInviteMailer:|r " .. msg)
end

local function Fill(template, name, code)
    local function esc(s) return (s:gsub("%%", "%%%%")) end
    template = template:gsub("{name}", esc(name))
    template = template:gsub("{code}", esc(code))
    return template
end

-- Accepts "Name:Code", "Name,Code", "Name;Code" or "Name Code", one per line.
local function Parse(text)
    local list, bad = {}, {}
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        line = strtrim(line)
        if line ~= "" then
            local name, code = line:match("^([^%s:,;]+)%s*[:,;%s]%s*(%S+)$")
            if name then
                list[#list + 1] = { name = name, code = code }
            else
                bad[#bad + 1] = line
            end
        end
    end
    return list, bad
end

local function UpdateStatus(extra)
    if not UI.status then return end
    local total = #queue
    local s = string.format("Sent %d / %d   Failed %d", sentCount, total, #failed)
    if sending then
        s = s .. "   |cff00ff00sending|r"
    end
    if not mailboxOpen then
        s = s .. "   |cffff8800open a mailbox|r"
    end
    if extra then s = s .. "\n" .. extra end
    UI.status:SetText(s)
    -- SetEnabled() doesn't exist in 3.3.5, so use Enable/Disable.
    if sending or waiting then UI.start:Disable() else UI.start:Enable() end
    if sending then UI.stop:Enable() else UI.stop:Disable() end
end

local function Stop(reason)
    sending = false
    delayLeft = 0
    if reason then Print(reason) end
    UpdateStatus()
end

local function Finish()
    sending = false
    current = nil
    Print(string.format("Done. %d sent, %d failed.", sentCount, #failed))
    if #failed > 0 then
        Print("Press \"Load failed\" to put the failed lines back in the list.")
    end
    UpdateStatus()
end

local function SendNext()
    if not sending then return end
    if not mailboxOpen then
        Stop("Mailbox closed. Paused - open a mailbox and press Start to continue.")
        return
    end
    if GetMoney() < POSTAGE then
        Stop("Not enough money for postage. Stopped.")
        return
    end

    idx = idx + 1
    current = queue[idx]
    if not current then
        Finish()
        return
    end

    local subject = Fill(UI.subject:GetText(), current.name, current.code)
    local body = Fill(UI.body:GetText(), current.name, current.code)

    lastError = nil
    waiting = true
    waitElapsed = 0
    SendMail(current.name, subject, body)
    UpdateStatus("Sending to " .. current.name .. "...")
end

local function OnResult(ok, reason)
    if not waiting or not current then return end
    waiting = false
    if ok then
        sentCount = sentCount + 1
        InviteMailerDB.sent[current.name:lower()] = current.code
        Print("Sent to " .. current.name)
    else
        failed[#failed + 1] = { name = current.name, code = current.code, reason = reason or "unknown error" }
        Print("|cffff4444Failed:|r " .. current.name .. " (" .. (reason or "unknown error") .. ")")
    end
    UpdateStatus()
    if sending then delayLeft = SEND_DELAY end
end

local function Start()
    if sending or waiting then return end
    if not mailboxOpen then
        Print("Open a mailbox first.")
        UpdateStatus()
        return
    end

    local list, bad = Parse(UI.list:GetText())
    for _, line in ipairs(bad) do
        Print("|cffff8800Skipped unreadable line:|r " .. line)
    end

    queue, idx, sentCount, failed = {}, 0, 0, {}
    local skipped = 0
    for _, entry in ipairs(list) do
        if InviteMailerDB.sent[entry.name:lower()] then
            skipped = skipped + 1
        else
            queue[#queue + 1] = entry
        end
    end
    if skipped > 0 then
        Print(skipped .. " name(s) already got a letter and were skipped. Use /im reset to allow resending.")
    end
    if #queue == 0 then
        Print("Nothing to send.")
        UpdateStatus()
        return
    end

    local sample = Fill(UI.body:GetText(), queue[1].name, queue[1].code)
    if #sample > 500 then
        Print("|cffff8800Warning:|r the letter text is over 500 characters and may be cut off or rejected.")
    end
    local cost = #queue * POSTAGE
    Print(string.format("Sending %d letter(s). Postage: %s.", #queue, GetCoinTextureString and GetCoinTextureString(cost) or (cost .. " copper")))

    sending = true
    SendNext()
end

local function LoadFailed()
    if #failed == 0 then
        Print("No failed letters to load.")
        return
    end
    local lines = {}
    for _, f in ipairs(failed) do
        lines[#lines + 1] = f.name .. ":" .. f.code
    end
    UI.list:SetText(table.concat(lines, "\n"))
    Print("Failed lines loaded. Fix the names and press Start.")
end

---------------------------------------------------------------------------
-- UI
---------------------------------------------------------------------------

local function MakeScrollEdit(parent, name, width, height)
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
    scroll:SetScrollChild(edit)

    box:EnableMouse(true)
    box:SetScript("OnMouseDown", function() edit:SetFocus() end)
    return box, edit
end

local function Label(parent, text, anchor, x, y)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", x or 0, y or -10)
    fs:SetText(text)
    return fs
end

local function BuildUI()
    local f = CreateFrame("Frame", "InviteMailerFrame", UIParent)
    f:SetWidth(440)
    f:SetHeight(500)
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
    tinsert(UISpecialFrames, "InviteMailerFrame") -- Escape closes it

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    title:SetPoint("TOP", 0, -18)
    title:SetText("InviteMailer")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)

    local anchor = CreateFrame("Frame", nil, f)
    anchor:SetWidth(1); anchor:SetHeight(1)
    anchor:SetPoint("TOPLEFT", 20, -40)

    local subjLabel = Label(f, "Subject  (use {name} and {code})", anchor, 0, 0)
    local subject = CreateFrame("EditBox", "InviteMailerSubject", f, "InputBoxTemplate")
    subject:SetWidth(392)
    subject:SetHeight(20)
    subject:SetAutoFocus(false)
    subject:SetMaxLetters(64)
    subject:SetPoint("TOPLEFT", subjLabel, "BOTTOMLEFT", 6, -4)
    subject:SetText(InviteMailerDB.subject)
    subject:SetScript("OnTextChanged", function(self) InviteMailerDB.subject = self:GetText() end)
    subject:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    UI.subject = subject

    local bodyLabel = Label(f, "Letter text", subject, -6, -10)
    local bodyBox, body = MakeScrollEdit(f, "InviteMailerBody", 400, 110)
    bodyBox:SetPoint("TOPLEFT", bodyLabel, "BOTTOMLEFT", 0, -4)
    body:SetText(InviteMailerDB.body)
    body:SetScript("OnTextChanged", function(self) InviteMailerDB.body = self:GetText() end)
    UI.body = body

    local listLabel = Label(f, "Recipients - one per line:  Name:Code", bodyBox, 0, -10)
    local listBox, list = MakeScrollEdit(f, "InviteMailerList", 400, 150)
    listBox:SetPoint("TOPLEFT", listLabel, "BOTTOMLEFT", 0, -4)
    list:SetText(InviteMailerDB.list)
    list:SetScript("OnTextChanged", function(self) InviteMailerDB.list = self:GetText() end)
    UI.list = list

    local start = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    start:SetWidth(100); start:SetHeight(22)
    start:SetPoint("TOPLEFT", listBox, "BOTTOMLEFT", 0, -10)
    start:SetText("Start")
    start:SetScript("OnClick", Start)
    UI.start = start

    local stop = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    stop:SetWidth(100); stop:SetHeight(22)
    stop:SetPoint("LEFT", start, "RIGHT", 8, 0)
    stop:SetText("Stop")
    stop:SetScript("OnClick", function() Stop("Stopped. Press Start to continue with the remaining names.") end)
    UI.stop = stop

    local loadFailed = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    loadFailed:SetWidth(110); loadFailed:SetHeight(22)
    loadFailed:SetPoint("LEFT", stop, "RIGHT", 8, 0)
    loadFailed:SetText("Load failed")
    loadFailed:SetScript("OnClick", LoadFailed)

    local status = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    status:SetPoint("TOPLEFT", start, "BOTTOMLEFT", 0, -10)
    status:SetWidth(400)
    status:SetJustifyH("LEFT")
    UI.status = status

    f:SetScript("OnShow", function() UpdateStatus() end)
    UI.frame = f
    UpdateStatus()
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("MAIL_SHOW")
events:RegisterEvent("MAIL_CLOSED")
events:RegisterEvent("MAIL_SEND_SUCCESS")
events:RegisterEvent("MAIL_FAILED")
events:RegisterEvent("UI_ERROR_MESSAGE")

events:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "InviteMailer" then
        InviteMailerDB = InviteMailerDB or {}
        InviteMailerDB.subject = InviteMailerDB.subject or DEFAULT_SUBJECT
        InviteMailerDB.body = InviteMailerDB.body or DEFAULT_BODY
        InviteMailerDB.list = InviteMailerDB.list or ""
        InviteMailerDB.sent = InviteMailerDB.sent or {}
        BuildUI()
    elseif event == "MAIL_SHOW" then
        mailboxOpen = true
        UpdateStatus()
    elseif event == "MAIL_CLOSED" then
        mailboxOpen = false
        if sending then
            -- Any letter already in flight still reports its result.
            Stop("Mailbox closed. Paused - open a mailbox and press Start to continue.")
        end
        UpdateStatus()
    elseif event == "MAIL_SEND_SUCCESS" then
        OnResult(true)
    elseif event == "MAIL_FAILED" then
        OnResult(false, lastError)
    elseif event == "UI_ERROR_MESSAGE" then
        if waiting then lastError = arg1 end
    end
end)

events:SetScript("OnUpdate", function(self, elapsed)
    if waiting then
        waitElapsed = waitElapsed + elapsed
        if waitElapsed > TIMEOUT then
            OnResult(false, "no answer from server")
        end
    elseif sending and delayLeft > 0 then
        delayLeft = delayLeft - elapsed
        if delayLeft <= 0 then
            delayLeft = 0
            SendNext()
        end
    end
end)

---------------------------------------------------------------------------
-- Slash command
---------------------------------------------------------------------------

SLASH_INVITEMAILER1 = "/im"
SLASH_INVITEMAILER2 = "/invitemailer"
SlashCmdList["INVITEMAILER"] = function(msg)
    msg = strtrim((msg or ""):lower())
    if msg == "reset" then
        InviteMailerDB.sent = {}
        Print("Sent history cleared. Every name in the list will get a letter again.")
    elseif UI.frame:IsShown() then
        UI.frame:Hide()
    else
        UI.frame:Show()
    end
end
