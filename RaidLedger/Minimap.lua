-- RaidLedger minimap button (raider feedback 2026-10-18, like RaidWishlist's):
-- click opens or closes the ledger, drag moves the button around the minimap.
-- The position is shared by all characters; /ledger minimap on|off.
local _, ns = ...
local L = ns.L
local Ledger = ns.Ledger
local MINIMAP_RADIUS = 80
local DEFAULT_ANGLE = 160   -- RaidWishlist's sits at 200, so both fit side by side

local Button = CreateFrame("Button", "RaidLedgerMinimapButton", Minimap)
Button:SetWidth(31)
Button:SetHeight(31)
Button:SetFrameStrata("MEDIUM")
Button:SetFrameLevel(8)
Button:RegisterForClicks("LeftButtonUp")
Button:RegisterForDrag("LeftButton")
Button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
local icon = Button:CreateTexture(nil, "BACKGROUND")
icon:SetTexture("Interface\\Icons\\INV_Misc_Book_11")
icon:SetWidth(20)
icon:SetHeight(20)
icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
icon:SetPoint("TOPLEFT", Button, "TOPLEFT", 7, -5)
local border = Button:CreateTexture(nil, "OVERLAY")
border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
border:SetWidth(53)
border:SetHeight(53)
border:SetPoint("TOPLEFT", Button, "TOPLEFT", 0, 0)

local function place()
    local db = ns.ensureDatabase()
    local angle = math.rad(db.minimapAngle or DEFAULT_ANGLE)
    Button:ClearAllPoints()
    Button:SetPoint("CENTER", Minimap, "CENTER", MINIMAP_RADIUS * math.cos(angle), MINIMAP_RADIUS * math.sin(angle))
    if db.minimapHidden then Button:Hide() else Button:Show() end
end

Button:SetScript("OnClick", function()
    if Ledger:IsShown() then Ledger:Hide() else Ledger:Show() end
end)
Button:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
        local centerX, centerY = Minimap:GetCenter()
        if not centerX then return end
        local cursorX, cursorY = GetCursorPosition()
        local scale = Minimap:GetEffectiveScale()
        ns.ensureDatabase().minimapAngle = math.deg(math.atan2(cursorY / scale - centerY, cursorX / scale - centerX))
        place()
    end)
end)
Button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
Button:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("RaidLedger")
    GameTooltip:AddLine(L["Click: open or close the ledger"], 1, 1, 1)
    GameTooltip:AddLine(L["Drag: move this button"], 0.7, 0.7, 0.7)
    GameTooltip:Show()
end)
Button:SetScript("OnLeave", function() GameTooltip:Hide() end)

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
    place()
    if ForgeTestBridge and ForgeTestBridge.RegisterFrame then
        ForgeTestBridge:RegisterFrame("RaidLedgerMinimap", Button)
    end
end)

ns.commands.minimap = function(rest)
    rest = ns.lower(ns.trim(rest))
    if rest ~= "on" and rest ~= "off" then
        ns.say(L["usage: /ledger minimap on|off"])
        return
    end
    ns.ensureDatabase().minimapHidden = rest == "off" or nil
    place()
    ns.say(rest == "on" and L["minimap button shown."] or L["minimap button hidden; /ledger minimap on brings it back."])
end
table.insert(ns.help, L["/ledger minimap on|off - show or hide the minimap button"])
