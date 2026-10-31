-- Texts are keyed by their English wording, which is also the fallback: any
-- client that is not German shows the key itself. German clients (deDE) get the
-- table below. Keep format specifiers (%s, %d) in the same order.
local _, ns = ...
local L = setmetatable({}, { __index = function(_, key) return key end })
ns.L = L

if GetLocale() ~= "deDE" then return end

-- Window
L["EXPORT"] = "EXPORT"
L["MASTER LOOT ITEMS"] = "BEUTE DES PLÜNDERMEISTERS"
L["MASTER LOOT ITEMS  (%d OPEN)"] = "BEUTE DES PLÜNDERMEISTERS  (%d OFFEN)"
L["with %s"] = "bei %s"
L["Open the master loot window\nPlayers can then use /rnd"] = "Beutefenster als Plündermeister öffnen\nDann können alle /rnd würfeln"
L["AWARD SELECTED LOOT"] = "AUSWAHL VERGEBEN"
L["Select an active roll"] = "Einen Gegenstand auswählen"
L["No player rolls recorded"] = "Noch keine Würfe"
L["RECIPIENT NAME"] = "EMPFÄNGER"
L["RECORD AWARD"] = "ERFASSEN"
L["PARK"] = "PARKEN"
L["ROLL"] = "WÜRFELN"
L["ASSIGN"] = "ZUWEISEN"
L["START ROLL"] = "WÜRFELN STARTEN"
L["LATER ROLL AT ..."] = "SPÄTER WÜRFELN BEI ..."
L["CLOSE"] = "SCHLIESSEN"
L["ALL (%d)"] = "ALLE (%d)"
L["PASS"] = "PASST"
L["ROLLS"] = "WÜRFE"
L["ROLLS (SCROLL)"] = "WÜRFE (SCROLLEN)"
L["  (corrected)"] = "  (korrigiert)"
L["%s has no counted roll on award #%d."] = "%s hat keinen gezählten Wurf in Vergabe #%d."
L["award #%d is not with a player; change it by hand."] = "Vergabe #%d liegt bei keinem Spieler; bitte von Hand ändern."
L["Award #%d: no valid roll is left; decide who gets it (DE, BANK or another recipient)."] =
    "Vergabe #%d: kein gültiger Wurf mehr; bitte entscheiden (DE, BANK oder anderer Empfänger)."
L["Award #%d: %s and %s tie; decide who gets it."] = "Vergabe #%d: Gleichstand zwischen %s und %s; bitte entscheiden."
L["MAIN SPEC"] = "MAIN-SPEC"
L["ENHANCED..."] = "ENHANCED ..."
L["OFF SPEC"] = "SECOND-SPEC"
L["DOES NOT COUNT"] = "ZÄHLT NICHT"
L["passed"] = "gepasst"
L["not counted"] = "zählt nicht"
L["[Loot] %s - %s passes."] = "[Loot] %s - %s passt."
L["[Loot] %s - %s's roll does not count."] = "[Loot] %s - der Wurf von %s zählt nicht."
L["[Loot] %s - %s's roll counts as %s (%d)."] = "[Loot] %s - der Wurf von %s zählt als %s (%d)."
L["%s has no counted roll on the selected item."] = "%s hat keinen gezählten Wurf auf den gewählten Gegenstand."
L["a free BoE roll only takes /rnd 100; pass or none only."] = "ein freier BoE-Wurf nimmt nur /rnd 100: nur pass oder none."
L["usage: /ledger pass <name>"] = "Aufruf: /ledger pass <Name>"
L["usage: /ledger count <name> ms|os|none|enh <0-50>"] = "Aufruf: /ledger count <Name> ms|os|none|enh <0-50>"
L["Points for %s's enhanced roll (1+X to 100+X, X 0-50; 0 = plain main spec):"] =
    "Punkte für den Enhanced-Wurf von %s (1+X bis 100+X, X 0-50; 0 = normaler Main-Spec):"
L["  - corrected, rolled %s"] = "  - korrigiert, gewürfelt: %s"
L["/ledger pass <name> - the player passes: the next-best roll wins"] =
    "/ledger pass <Name> - der Spieler passt: der nächstbeste Wurf gewinnt"
L["/ledger count <name> ms|os|none|enh <0-50> - change how a roll on the selected item counts"] =
    "/ledger count <Name> ms|os|none|enh <0-50> - ändern, wie ein Wurf auf den gewählten Gegenstand zählt"
L["GROUP %d"] = "GRUPPE %d"
L["RECENT AWARDS"] = "LETZTE VERGABEN"
L["CLEAR"] = "LEEREN"
L["GIVEN"] = "VERGEBEN"
L["HELD BY YOU"] = "BEI DIR"
L["HELD"] = "BEIM PM"
L["MANUAL"] = "MANUELL"
L["REMOVED"] = "ENTFERNT"
L["OPEN"] = "OFFEN"
L["CLICK AN AWARD FOR ITS ROLLS OR TO CHANGE ITS RECIPIENT  |  /ledger help"] = "VERGABE ANKLICKEN: WÜRFE ANSEHEN, EMPFÄNGER ÄNDERN  |  /ledger help"
L["WEBSITE EXPORT  (%s LOOT)"] = "EXPORT FÜR DIE WEBSEITE  (%s LOOT)"
L["RAID ID"] = "RAID-ID"
L["NEW RAID"] = "NEUER RAID"
L["BACK"] = "ZURÜCK"
L["AWARDS (%d)"] = "VERGABEN (%d)"
L["%d HELD BY YOU  |  SCROLL FOR MORE"] = "%d BEI DIR  |  SCROLLEN FÜR MEHR"
L["SCROLL FOR MORE"] = "SCROLLEN FÜR MEHR"
L["#%d  %s  |  %s  ->  %s  (%d rolls)"] = "#%d  %s  |  %s  ->  %s  (%d Würfe)"
L["No awards recorded in this ledger."] = "Noch keine Vergaben erfasst."
L["NOW: %s (%s)"] = "JETZT: %s (%s)"
L["NOW: %s"] = "JETZT: %s"
L["RESTORE + SET"] = "WIEDERHERSTELLEN"
L["CHANGE RECIPIENT"] = "EMPFÄNGER ÄNDERN"
L["GIVE + RECORD"] = "GEBEN + ERFASSEN"
L["WINNER: %s (%d)"] = "GEWINNER: %s (%d)"
L["%d rolls  |  %ds remaining"] = "%d Würfe  |  noch %ds"
L["%d player rolls recorded"] = "%d Würfe erfasst"
L["ROLLS FOR AWARD #%d  (%d, SCROLL)"] = "WÜRFE ZU VERGABE #%d  (%d, SCROLLEN)"
L["ROLLS FOR AWARD #%d"] = "WÜRFE ZU VERGABE #%d"
L["  (tie-break %d)"] = "  (Stechen %d)"
L["  - ignored: %s"] = "  - ignoriert: %s"
L["  - won"] = "  - gewonnen"
L["re-roll"] = "zweiter Wurf"
L["not in tie-break"] = "nicht im Stechen"
L["Awarded without a /rnd roll"] = "Ohne /rnd-Wurf vergeben"
L["Rolls were not recorded\nfor this older award"] = "Zu dieser älteren Vergabe\nwurden keine Würfe erfasst"
L["%d ROLLS"] = "%d WÜRFE"
L["Unknown item"] = "Unbekannter Gegenstand"

-- Tooltips
L["%s this raid: items %d MS / %d OS, tokens %d MS / %d OS"] = "%s in diesem Raid: Items %d MS / %d OS, Tokens %d MS / %d OS"
L["  (token)"] = "  (Token)"
L["Award #%d: %s (%s)"] = "Vergabe #%d: %s (%s)"
L["Award #%d: %s"] = "Vergabe #%d: %s"
L["Roll %d, %s"] = "Wurf %d, %s"
L["spec unknown"] = "Spec unbekannt"

-- Raid announcements
L["main spec"] = "Main-Spec"
L["off spec"] = "Second-Spec"
L["1 item"] = "1 Item"
L["%d items"] = "%d Items"
L["1 token"] = "1 Token"
L["%d tokens"] = "%d Tokens"
L[" and "] = " und "
L["[Loot] %s - /rnd now! %d seconds. /rnd 100 main spec (enhanced: 1+X to 100+X, X up to 50), /rnd 99 off spec."] =
    "[Loot] %s - jetzt /rnd! %d Sekunden. /rnd 100 Main-Spec (Enhanced: 1+X bis 100+X, X höchstens 50), /rnd 99 Second-Spec."
L["[Loot] %s - nobody wanted it."] = "[Loot] %s - wollte niemand."
L["NOBODY"] = "NIEMAND"
L["%d MS / %d OS items"] = "%d MS / %d OS Items"
L["%d MS / %d OS tokens"] = "%d MS / %d OS Tokens"
L["[Loot] %s - tie between %s (%d)! %s: /rnd again, %d seconds."] = "[Loot] %s - Gleichstand zwischen %s (%d)! %s: nochmal /rnd, %d Sekunden."
L["[Loot] %s won by %s (%d) - %s%s, %s so far."] = "[Loot] %s gewonnen von %s (%d) - %s%s, bisher %s."
L["[Loot] %s - %d seconds left."] = "[Loot] %s - noch %d Sekunden."
L["[Loot] %s is parked with %s until it is rolled."] = "[Loot] %s wird bis zum Auswürfeln von %s verwahrt."
L["[Loot] %s goes to %s%s%s."] = "[Loot] %s geht an %s%s%s."
L["corrected"] = "korrigiert"
L["pick it up from %s"] = "bei %s abholen"

-- Status line
L["%d-second raid roll started."] = "%d-Sekunden-Wurf gestartet."
L["Select a master-loot item before starting a roll."] = "Vor dem Würfeln einen Gegenstand aus der Beute auswählen."
L["Gave #%d to %s; waiting for the loot message."] = "#%d an %s gegeben; warte auf die Beutemeldung."
L["Giving %s to %s; waiting for loot confirmation."] = "%s an %s vergeben; warte auf die Beutebestätigung."
L["Award #%d confirmed: %s received the item."] = "Vergabe #%d bestätigt: %s hat den Gegenstand erhalten."
L["Award #%d now goes to %s."] = "Vergabe #%d geht jetzt an %s."
L["Award #%d removed; the export keeps it as deleted."] = "Vergabe #%d entfernt; der Export führt sie als gelöscht."
L["Award #%d goes to %s (%s)."] = "Vergabe #%d geht an %s (%s)."
L["Restore the award before parking it."] = "Die Vergabe erst wiederherstellen, dann parken."
L["Award #%d is open, held by %s until it is rolled."] = "Vergabe #%d ist offen; %s verwahrt sie bis zum Auswürfeln."
L["Select a loot item to park."] = "Einen Gegenstand zum Parken auswählen."
L["%s cannot receive this item (not a master-loot candidate)."] = "%s kann diesen Gegenstand nicht erhalten (nicht in der Plündermeister-Liste)."
L["Enter the new recipient's name."] = "Namen des neuen Empfängers eingeben."
L["Select a loot roll before recording an award."] = "Vor dem Erfassen einen Gegenstand auswählen."
L["Choose or enter a recipient name."] = "Empfänger anklicken oder Namen eingeben."
L["Award #%d recorded for %s."] = "Vergabe #%d für %s erfasst."
L["Enter the website's raid ID to build the export."] = "Raid-ID der Webseite eingeben, dann entsteht der Export."
L["Export selected: press Ctrl+C and paste it into the raid website's loot import."] = "Export markiert: Strg+C drücken und im Loot-Import der Raid-Webseite einfügen."
L["Clear all recorded loot and start a new raid? Export it first."] = "Alle erfassten Vergaben löschen und einen neuen Raid beginnen? Vorher exportieren."

-- Chat
L["no award #%s."] = "keine Vergabe #%s."
L["give a name or target the recipient."] = "Namen angeben oder den Empfänger anvisieren."
L["%s shares another raid's ledger; yours has its own awards, so it is not merged. Use CLEAR to follow theirs."] =
    "%s teilt das Buch eines anderen Raids; deins hat eigene Vergaben und wird nicht zusammengeführt. Mit LEEREN folgst du dem anderen."
L["new raid: the award ledger is empty."] = "neuer Raid: das Buch ist leer."
L["usage: /ledger set <#> [name]"] = "Aufruf: /ledger set <#> [Name]"
L["usage: /ledger del <#>"] = "Aufruf: /ledger del <#>"
L["usage: /ledger spec <#> ms|os|none"] = "Aufruf: /ledger spec <#> ms|os|none"
L["usage: /ledger raid <id>"] = "Aufruf: /ledger raid <ID>"
L["award #%d counts for %s."] = "Vergabe #%d zählt für %s."
L["no tally"] = "zählt nicht"
L["asked the group's ledgers for this raid's awards."] = "die Bücher der Gruppe nach den Vergaben dieses Raids gefragt."
L["not in a group: nothing to sync."] = "nicht in einer Gruppe: nichts abzugleichen."
L["tokens this raid:"] = "Tokens in diesem Raid:"
L["no items counted this raid yet."] = "in diesem Raid noch keine Items gezählt."
L["%s: %d main spec, %d off spec%s"] = "%s: %d Main-Spec, %d Second-Spec%s"
L[" (tokens)"] = " (Tokens)"
L["raid ID %s."] = "Raid-ID %s."
L["BoE"] = "BoE"
L["[Loot] %s - free BoE roll for any character! /rnd 100, %d seconds."] = "[Loot] %s - freier BoE-Wurf für jeden Charakter! /rnd 100, %d Sekunden."
L["[Loot] %s - free BoE roll won by %s (%d)."] = "[Loot] %s - freier BoE-Wurf gewonnen von %s (%d)."
L["%d-second free BoE roll started."] = "%d-Sekunden-BoE-Wurf gestartet."
L["a roll is already running for this item."] = "für diesen Gegenstand läuft bereits ein Wurf."
L["Nobody rolled on %s. Post it again now as a free BoE roll for any character? (Later: select it and /ledger free)"] =
    "Niemand hat auf %s gewürfelt. Jetzt als freien BoE-Wurf für jeden Charakter erneut posten? (Später: auswählen und /ledger free)"
L["NOW"] = "JETZT"
L["LATER"] = "SPÄTER"
L["/ledger free - post the selected item again: free BoE roll for any character (/rnd 100)"] =
    "/ledger free - gewählten Gegenstand erneut posten: freier BoE-Wurf für jeden Charakter (/rnd 100)"
L["roll timer: %d seconds, tie-break: %d seconds."] = "Wurfzeit: %d Sekunden, Gleichstand: %d Sekunden."
L["usage: /ledger timer [seconds] [tie-break seconds] (roll %d-%d, tie-break %d-%d), or /ledger timer reset"] =
    "Aufruf: /ledger timer [Sekunden] [Gleichstand-Sekunden] (Wurf %d-%d, Gleichstand %d-%d) oder /ledger timer reset"

-- /ledger help
L["/ledger - show or hide the ledger"] = "/ledger - Buch zeigen oder verbergen"
L["/ledger start - start a %d s /rnd roll for the selected item"] = "/ledger start - %d s /rnd-Wurf für den gewählten Gegenstand starten"
L["/ledger timer [seconds] [tie-break seconds] - roll lengths for new rolls; /ledger timer reset"] =
    "/ledger timer [Sekunden] [Gleichstand-Sekunden] - Wurfzeiten für neue Würfe; /ledger timer reset"
L["/ledger set <#> [name] - change the recipient of award #, or to your target"] = "/ledger set <#> [Name] - Empfänger von Vergabe # ändern (ohne Name: dein Ziel)"
L["/ledger del <#> - remove award # (exported as deleted)"] = "/ledger del <#> - Vergabe # entfernen (Export: gelöscht)"
L["/ledger spec <#> ms|os|none - set which tally award # counts for"] = "/ledger spec <#> ms|os|none - festlegen, wofür Vergabe # zählt"
L["/ledger tally - items per player this raid (main spec / off spec)"] = "/ledger tally - Items pro Spieler in diesem Raid (Main-/Second-Spec)"
L["/ledger raid <id> - set the website raid ID"] = "/ledger raid <ID> - Raid-ID der Webseite setzen"
L["/ledger export - show the website export"] = "/ledger export - Export für die Webseite zeigen"
L["/ledger sync - ask the group's other ledgers for this raid's awards"] = "/ledger sync - andere Bücher der Gruppe nach den Vergaben fragen"
L["/ledger newraid (or CLEAR) - empty the award ledger for the next raid; add confirm to skip the question"] =
    "/ledger newraid (oder LEEREN) - Buch für den nächsten Raid leeren; mit confirm ohne Rückfrage"
L["/ledger clear - drop all active rolls;  /ledger reset - the window back to the middle, normal size and scale"] =
    "/ledger clear - alle offenen Würfe verwerfen;  /ledger reset - Fenster mittig, in normaler Größe und Skalierung"

-- Disenchant and guild bank
L["DE"] = "DE"
L["BANK"] = "BANK"
L["DISENCHANT"] = "ENTZAUBERN"
L["DISENCHANT (%s)"] = "ENTZAUBERN (%s)"
L["GUILD BANK"] = "GILDENBANK"
L["[Loot] %s will be disenchanted (%s)."] = "[Loot] %s wird entzaubert (%s)."
L["[Loot] %s goes to the guild bank (%s)."] = "[Loot] %s geht in die Gildenbank (%s)."
L["Award #%d: %s (%s)."] = "Vergabe #%d: %s (%s)."
L["Select a loot item first."] = "Zuerst einen Gegenstand auswählen."
L["Disenchant: give it to the name in the box (or keep it); counts for nobody"] =
    "Entzaubern: an den Namen im Feld geben (sonst an dich); zählt für niemanden"
L["Guild bank: give it to the name in the box (or keep it); counts for nobody"] =
    "Gildenbank: an den Namen im Feld geben (sonst an dich); zählt für niemanden"

-- Members' wishlists
L["WL %d"] = "WL %d"
L["  [WL #%d]"] = "  [WL #%d]"
L["On %d wishlists:"] = "Auf %d Wunschlisten:"
L["  %s - %s, #%d%s"] = "  %s - %s, #%d%s"
L[", enhanced"] = ", Enhanced"
L["On nobody's wishlist."] = "Auf keiner Wunschliste."

-- Raid setup (Raid.lua, taken over from RaidSync)
L["RAID"] = "RAID"
L["RAID SETUP"] = "RAID-AUFSTELLUNG"
L["Paste the website's invite list (Raid > Aufstellung > Einladungen für Addon):"] =
    "Einladungsliste der Webseite einfügen (Raid > Aufstellung > Einladungen für Addon):"
L["READ"] = "EINLESEN"
L["INVITE ALL"] = "ALLE EINLADEN"
L["RETRY MISSING"] = "FEHLENDE ERNEUT"
L["BENCH: NO"] = "ERSATZBANK: NEIN"
L["BENCH: YES"] = "ERSATZBANK: JA"
L["SORT GROUPS"] = "GRUPPEN SORTIEREN"
L["ATTENDANCE FOR THE WEBSITE"] = "TEILNAHME FÜR DIE WEBSEITE"
L["open"] = "offen"
L["invited"] = "eingeladen"
L["in raid"] = "im Raid"
L["declined"] = "abgelehnt"
L["not found"] = "nicht gefunden"
L["in another group"] = "in anderer Gruppe"
L["offline"] = "offline"
L["no answer"] = "keine Antwort"
L["bench"] = "Ersatzbank"
L["Raid #%d %s: %d / %d in the raid"] = "Raid #%d %s: %d / %d im Raid"
L["No invite list read yet."] = "Noch keine Einladungsliste eingelesen."
L["  inviting..."] = "  lädt ein..."
L["Paste the website's invite list first."] = "Zuerst die Einladungsliste der Webseite einfügen."
L["That is not the website's invite list."] = "Das ist keine Einladungsliste der Webseite."
L["skipped line: %s"] = "Zeile übersprungen: %s"
L["%d characters read for raid #%d."] = "%d Charaktere für Raid #%d eingelesen."
L["Read the website's invite list first."] = "Zuerst die Einladungsliste der Webseite einlesen."
L["Only the raid lead or an assistant can invite."] = "Nur Raidleiter oder Assistenten können einladen."
L["Nobody left to invite."] = "Niemand mehr einzuladen."
L["Inviting %d characters."] = "Lade %d Charaktere ein."
L["All invites sent."] = "Alle Einladungen verschickt."
L["Read the invite list or set the raid ID first."] = "Zuerst die Einladungsliste einlesen oder die Raid-ID setzen."
L["Nobody seen in the raid yet."] = "Noch niemand im Raid gesehen."
L["Attendance selected: press Ctrl+C and paste it into the raid website's roster import."] =
    "Teilnahme markiert: Strg+C drücken und im Aufstellungs-Import der Raid-Webseite einfügen."
L["Sorting groups only works in a raid, as raid lead or assistant."] = "Gruppen sortieren geht nur im Raid, als Raidleiter oder Assistent."
L["%d players moved (tanks, healers, the rest)."] = "%d Spieler verschoben (Tanks, Heiler, Rest)."
L["Groups are already sorted."] = "Die Gruppen sind schon sortiert."
L["/ledger setup - invites, groups and attendance (RAID button)"] = "/ledger setup - Einladungen, Gruppen und Teilnahme (Knopf RAID)"
L["/ledger invite [missing] - invite the website's list (or retry the missing)"] =
    "/ledger invite [missing] - Liste der Webseite einladen (oder die Fehlenden erneut)"
L["/ledger groups - sort raid groups: tanks, healers, the rest"] = "/ledger groups - Raidgruppen sortieren: Tanks, Heiler, Rest"
L["/ledger attendance - export who was in the raid for the website"] = "/ledger attendance - Teilnahme für die Webseite exportieren"
L["The group did not become a raid: everyone must be level 10 or higher."] =
    "Die Gruppe wurde kein Schlachtzug: alle müssen mindestens Stufe 10 sein."

-- Minimap button
L["Click: open or close the ledger"] = "Klick: Ledger öffnen oder schließen"
L["Drag: move this button"] = "Ziehen: Knopf verschieben"
L["usage: /ledger minimap on|off"] = "Aufruf: /ledger minimap on|off"
L["minimap button shown."] = "Minimap-Knopf wird angezeigt."
L["minimap button hidden; /ledger minimap on brings it back."] = "Minimap-Knopf ausgeblendet; /ledger minimap on holt ihn zurück."
L["/ledger minimap on|off - show or hide the minimap button"] = "/ledger minimap on|off - Minimap-Knopf zeigen oder verbergen"

-- Rolls on items in the bags
L["usage: /ledger roll <item link> (or Alt+click the item in your bags)"] =
    "Aufruf: /ledger roll <Itemlink> (oder das Item in den Taschen mit Alt+Klick)"
L["only the master looter or the raid lead can start rolls."] = "nur der Plündermeister oder die Raidleitung kann Würfe starten."
L["%s is already being rolled."] = "Auf %s wird schon gewürfelt."
L["item %s is not in your bags."] = "Item %s ist nicht in deinen Taschen."
L["/ledger roll <item link or ID> - roll an item from your bags (or Alt+click it in your bags)"] =
    "/ledger roll <Itemlink oder ID> - auf ein Item aus deinen Taschen würfeln lassen (oder Alt+Klick in den Taschen)"

-- Calendar event from the invite list
L["CALENDAR EVENT"] = "KALENDER-TERMIN"
L["The invite list's date or time is not valid (YYYY-MM-DD;HH:MM)."] =
    "Datum oder Uhrzeit der Einladungsliste ist ungültig (JJJJ-MM-TT;HH:MM)."
L["This invite list has no date: export it again on the website."] =
    "Diese Einladungsliste hat kein Datum: bitte auf der Webseite neu exportieren."
L["The raid on %s is already over; the calendar only takes future events."] =
    "Der Raid am %s ist schon vorbei; der Kalender nimmt nur künftige Termine."
L["CREATE EVENT (%d)"] = "TERMIN ERSTELLEN (%d)"
L["%d invites ready: click CREATE EVENT (or /ledger calendar again) to add the event."] =
    "%d Einladungen bereit: TERMIN ERSTELLEN klicken (oder nochmal /ledger calendar), um den Termin anzulegen."
L["The calendar event is still being created."] = "Der Kalender-Termin wird gerade erstellt."
L["Creating the calendar event: inviting %d characters..."] = "Erstelle den Kalender-Termin: lade %d Charaktere ein..."
L["%d characters could not be invited (not found?)."] = "%d Charaktere konnten nicht eingeladen werden (nicht gefunden?)."
L["The calendar event is in the calendar: confirmed by the server."] =
    "Der Kalender-Termin steht im Kalender: vom Server bestätigt."
L["The calendar event did not show up in the calendar; check it with the calendar button."] =
    "Der Kalender-Termin ist nicht im Kalender aufgetaucht; bitte im Kalender nachsehen."
L["Raid #%d - invites from RaidLedger"] = "Raid #%d - Einladungen von RaidLedger"
L["Calendar event \"%s\" on %s created with %d invites."] = "Kalender-Termin \"%s\" am %s mit %d Einladungen erstellt."
L["%d characters not invited: the calendar takes 100 per event."] =
    "%d Charaktere nicht eingeladen: der Kalender nimmt 100 pro Termin."
L["/ledger calendar - calendar raid event from the invite list, everyone on it invited"] =
    "/ledger calendar - Kalender-Raidtermin aus der Einladungsliste, alle darauf eingeladen"

-- Raid feedback 2026-10-19: token bundles, tooltips
L["WINNERS: %s"] = "GEWINNER: %s"
L["[Loot] %dx %s won by %s."] = "[Loot] %dx %s gewonnen von %s."
L["[Loot] %s - %d left: nobody wanted it."] = "[Loot] %s - %d übrig: wollte niemand."
L["This raid's awards appear here: click one for its rolls or to change it."] =
    "Hier stehen die Vergaben dieses Raids: anklicken zeigt die Würfe oder ändert die Vergabe."
L["Close the ledger (/ledger opens it again)"] = "Schließen (/ledger öffnet es wieder)"
L["The website export of this raid's awards (RS2 LOOT)"] = "Export der Vergaben dieses Raids für die Webseite (RS2 LOOT)"
L["Who gets the item: click a name or a roll, or type one"] = "Wer das Item bekommt: Namen oder Wurf anklicken oder eintippen"
L["Give this award to the name in the box"] = "Diese Vergabe an den Namen im Feld geben"
L["Give the selected item to the name in the box and record it"] = "Das ausgewählte Item an den Namen im Feld geben und erfassen"
L["Record the selected item for the name in the box (the loot window is closed)"] =
    "Das ausgewählte Item für den Namen im Feld erfassen (das Beutefenster ist zu)"
L["Start the roll for this open item"] = "Das Würfeln für dieses offene Item starten"
L["Hand the item to the name in the box (or keep it) until it is rolled later"] =
    "Das Item dem Namen im Feld geben (oder selbst behalten), bis später darauf gewürfelt wird"
L["The whole raid by group: click a name to pick them"] = "Der ganze Raid nach Gruppen: Namen anklicken wählt ihn aus"
L["Click: recipient. Right-click: pass or count the roll differently."] =
    "Klick: Empfänger. Rechtsklick: passen oder den Wurf anders werten."
L["Click: recipient"] = "Klick: Empfänger"
L["New raid: empties the award list (export it first)"] = "Neuer Raid: leert die Vergaben (vorher exportieren)"
L["The raid's ID on the website (in its address)"] = "Die Raid-ID auf der Webseite (steht in der Adresse)"
L["Back to the loot"] = "Zurück zur Beute"
L["Ctrl+C copies the export; paste it into the website's loot import"] =
    "Strg+C kopiert den Export; auf der Webseite beim Beute-Import einfügen"
L["The player passes: the next-best roll wins"] = "Der Spieler passt: der nächstbeste Wurf gewinnt"
L["Count it as main spec (1-100)"] = "Als Main-Spec werten (1-100)"
L["Count it as enhanced main spec: asks for the points"] = "Als Enhanced Main-Spec werten: fragt nach den Punkten"
L["Count it as off spec (1-99)"] = "Als Second-Spec werten (1-99)"
L["The roll does not count"] = "Der Wurf zählt nicht"
L["Rolls on the selected item. Click: recipient. Right-click: pass or count differently."] =
    "Würfe auf das ausgewählte Item. Klick: Empfänger. Rechtsklick: passen oder anders werten."
L["Open: %s holds it until it is rolled. Click it, then ROLL."] =
    "Offen: %s verwahrt es bis zum Auswürfeln. Anklicken, dann WÜRFELN."
L["Raid setup: the website's invite list, invites, raid groups and attendance"] =
    "Raid-Aufbau: Einladungsliste der Webseite, Einladungen, Raidgruppen und Anwesenheit"
L["Paste the website's invite list here (Ctrl+V), then READ"] =
    "Die Einladungsliste der Webseite hier einfügen (Strg+V), dann EINLESEN"
L["Read the pasted invite list"] = "Die eingefügte Einladungsliste einlesen"
L["Invite everyone on the list who is not in the raid yet"] = "Alle von der Liste einladen, die noch nicht im Raid sind"
L["Invite again whoever was offline, declined or did not answer"] =
    "Alle nochmal einladen, die offline waren, abgelehnt oder nicht geantwortet haben"
L["Also invite the players the website put on the bench"] = "Auch die Spieler einladen, die die Webseite auf die Bank gesetzt hat"
L["Create a calendar raid event for the list's date and time, everyone on it invited"] =
    "Einen Kalender-Raidtermin zu Datum und Uhrzeit der Liste anlegen, alle darauf eingeladen"
L["Who was in the raid, for the website's roster import"] = "Wer im Raid war, für den Roster-Import der Webseite"
L["Ctrl+C copies the attendance; paste it into the website"] = "Strg+C kopiert die Anwesenheit; auf der Webseite einfügen"
L["Sort the raid groups: tanks, healers, then the rest"] = "Raidgruppen sortieren: Tanks, Heiler, dann der Rest"

-- Editors and addon users (SETTINGS)
L["SETTINGS"] = "EINSTELLUNGEN"
L["EDITORS: MAY START ROLLS, AWARD AND CORRECT"] = "FREIGEGEBEN: DÜRFEN WÜRFELN LASSEN, VERGEBEN, KORRIGIEREN"
L["Empty: everyone may, as before. Click a name to remove it. Shared with the group."] =
    "Leer: alle dürfen, wie bisher. Klick auf einen Namen entfernt ihn. Wird mit der Gruppe geteilt."
L["ADD"] = "HINZUFÜGEN"
L["+ TARGET"] = "+ ZIEL"
L["CHECK"] = "PRÜFEN"
L["Green: RaidLedger (version)  |  blue: RaidWishlist only  |  grey: no addon  |  gold: editor"] =
    "Grün: RaidLedger (Version)  |  blau: nur RaidWishlist  |  grau: kein Addon  |  gold: freigegeben"
L["No editors: everyone may change the ledger."] = "Keine Freigabeliste: alle dürfen ändern."
L["You are an editor."] = "Du bist freigegeben."
L["You only watch: not an editor."] = "Du schaust nur zu: nicht freigegeben."
L["ADDON IN THE GROUP (%d/%d)"] = "ADDON IN DER GRUPPE (%d/%d)"
L["nobody (everyone may change the ledger)"] = "niemand (alle dürfen ändern)"
L["Only the editors may change the ledger: %s."] = "Nur Freigegebene dürfen ändern: %s."
L["usage: /ledger allow|deny <name>"] = "Aufruf: /ledger allow|deny <Name>"
L["editors: %s"] = "freigegeben: %s"
L["%s shared the editors: %s"] = "%s hat die Freigaben geteilt: %s"
L["target a player to add them."] = "einen Spieler ins Ziel nehmen, um ihn hinzuzufügen."
L["not in a group."] = "nicht in einer Gruppe."
L["Editors and who in the group runs RaidLedger or RaidWishlist"] =
    "Freigaben und wer in der Gruppe RaidLedger oder RaidWishlist nutzt"
L["Add the name in the box as an editor (the first one also adds you)"] =
    "Den Namen im Feld freigeben (beim ersten wirst du mit freigegeben)"
L["Add your target as an editor"] = "Dein Ziel freigeben"
L["Ask the group again which addons they run"] = "Die Gruppe nochmal fragen, wer welches Addon nutzt"
L["Click: no longer an editor"] = "Klick: Freigabe entfernen"
L["Name of a new editor; Enter adds it"] = "Name einer neuen Freigabe; Enter fügt ihn hinzu"
L["/ledger allow|deny <name> - add or remove an editor;  /ledger editors - list them"] =
    "/ledger allow|deny <Name> - Freigabe geben oder entfernen;  /ledger editors - Freigaben zeigen"
L["/ledger settings - editors and who runs the addons"] = "/ledger settings - Freigaben und wer die Addons nutzt"

-- Tabs (UI rework 2026-10-19)
L["Pick a tab above  |  /ledger help"] = "Oben einen Reiter wählen  |  /ledger help"
L["EMPTY"] = "LEEREN"
L["SELECTED ITEM"] = "AUSGEWÄHLTES ITEM"
L["FREE BOE ROLL"] = "FREIER BOE-WURF"
L["SO FAR"] = "BISHER"
L["OPEN ITEMS (%d)"] = "OFFENE ITEMS (%d)"
L["%d WINNERS"] = "%d GEWINNER"
L["%ds LEFT"] = "NOCH %ds"
L["LOOT (%d)  |  %d OPEN"] = "BEUTE (%d)  |  %d OFFEN"
L["LOOT (%d)"] = "BEUTE (%d)"
L["ROLLS (%d, SCROLL)"] = "WÜRFE (%d, SCROLLEN)"
L["ROLLS (%d)"] = "WÜRFE (%d)"
L["No rolls yet: players type /rnd"] = "Noch keine Würfe: alle würfeln mit /rnd"
L["Nobody wanted it: roll again, free BoE roll, DE or BANK."] = "Wollte niemand: nochmal würfeln, freier BoE-Wurf, DE oder BANK."
L["Open item: start its roll."] = "Offenes Item: Würfeln starten."
L["Not rolled yet: start the roll."] = "Noch nicht gewürfelt: Würfeln starten."
L["ROLL AGAIN"] = "NOCHMAL WÜRFELN"
L["Select an item on the left"] = "Links ein Item auswählen"
L["Then ROLL starts the /rnd roll; the rolls appear below."] = "Dann startet WÜRFELN den /rnd-Wurf; die Würfe stehen darunter."
L["Start a %d-second /rnd roll for this item (announced in raid chat)"] =
    "Einen %d-Sekunden-/rnd-Wurf für dieses Item starten (wird im Raidchat angesagt)"
L["Post it again as a free BoE roll for any character (/rnd 100, highest wins, counts for nobody)"] =
    "Als freien BoE-Wurf für jeden Charakter neu posten (/rnd 100, der Höchste gewinnt, zählt für niemanden)"
L["Empty the loot list (the awards stay)"] = "Die Beuteliste leeren (die Vergaben bleiben)"
L["SELECTED AWARD"] = "AUSGEWÄHLTE VERGABE"
L["COUNTS AS"] = "ZÄHLT ALS"
L["NOTHING"] = "NICHTS"
L["CHANGE"] = "ÄNDERN"
L["REMOVE"] = "ENTFERNEN"
L["AWARDS (%d, SCROLL)"] = "VERGABEN (%d, SCROLLEN)"
L["Select an award on the left"] = "Links eine Vergabe auswählen"
L["Here you change its recipient, its tally, or remove it."] = "Hier änderst du Empfänger und MS/OS oder entfernst sie."
L["  |  roll %d"] = "  |  Wurf %d"
L["Remove award %s? The export keeps it as removed; CHANGE RECIPIENT restores it."] =
    "Vergabe %s entfernen? Der Export behält sie als entfernt; EMPFÄNGER ÄNDERN stellt sie wieder her."
L["The award counts in the winner's main-spec tally"] = "Die Vergabe zählt als Main-Spec-Item des Gewinners"
L["The award counts in the winner's off-spec tally"] = "Die Vergabe zählt als Second-Spec-Item des Gewinners"
L["The award counts in no tally"] = "Die Vergabe zählt nirgends"
L["The award's new recipient; click a roll below to pick its player"] = "Neuer Empfänger; ein Klick auf einen Wurf unten übernimmt den Spieler"
L["Restore the award for the name in the box"] = "Die Vergabe für den Namen im Feld wiederherstellen"
L["Park it with the name in the box (or its holder) until it is rolled"] =
    "Beim Namen im Feld (oder beim jetzigen Besitzer) verwahren, bis verlost wird"
L["Remove the award (the export keeps it as removed)"] = "Die Vergabe entfernen (der Export behält sie als entfernt)"
L["Back to the awards"] = "Zurück zu den Vergaben"
L["Items main spec"] = "Items Main-Spec"
L["Items off spec"] = "Items Second-Spec"
L["Tokens main spec"] = "Tokens Main-Spec"
L["Tokens off spec"] = "Tokens Second-Spec"
L["TALLY THIS RAID"] = "ITEMS PRO SPIELER"
L["TOK. OS"] = "TOK. OS"
L["TOK. MS"] = "TOK. MS"
L["ITEMS OS"] = "ITEMS OS"
L["ITEMS MS"] = "ITEMS MS"
L["PLAYER"] = "SPIELER"
L["Nobody in the group and no awards yet."] = "Niemand in der Gruppe und noch keine Vergaben."
L["SELECTED PLAYER"] = "AUSGEWÄHLTER SPIELER"
L["- / + corrects a counter (e.g. loot from before the ledger). Shared, not exported."] =
    "- / + korrigiert eine Zahl (z. B. Beute von vor dem Addon). Wird geteilt, nicht exportiert."
L["RESET CORRECTIONS"] = "KORREKTUR ZURÜCKSETZEN"
L["Select a player on the left"] = "Links einen Spieler auswählen"
L["TALLY"] = "SPIELER"
L["Click: open this award (change its tally there)"] = "Klick: diese Vergabe öffnen (dort MS/OS ändern)"
L["One less (a correction; the awards stay)"] = "Einen weniger (Korrektur; die Vergaben bleiben)"
L["One more (a correction; the awards stay)"] = "Einen mehr (Korrektur; die Vergaben bleiben)"
L["Remove this player's corrections: the tally comes from the awards only"] =
    "Korrekturen dieses Spielers entfernen: es zählen nur noch die Vergaben"
L["Roll (s)"] = "Wurf (s)"
L["Tie-break (s)"] = "Gleichstand (s)"
L["APPLY"] = "ÜBERNEHMEN"
L["WINDOW"] = "FENSTER"
L["MINIMAP: ON"] = "MINIMAP: AN"
L["MINIMAP: OFF"] = "MINIMAP: AUS"
L["RESET WINDOW"] = "FENSTER ZURÜCKSETZEN"
L["Scale"] = "Skalierung"
L["SYNC AWARDS"] = "VERGABEN ABGLEICHEN"
L["How long a roll runs; reminders come at half and a quarter of it"] =
    "Wie lange ein Wurf läuft; Erinnerungen kommen nach der Hälfte und einem Viertel"
L["How long a tie-break runs"] = "Wie lange ein Gleichstand-Wurf läuft"
L["Use these lengths for the next rolls (a running roll keeps its time)"] =
    "Diese Längen für die nächsten Würfe nehmen (ein laufender Wurf behält seine Zeit)"
L["Show or hide the minimap button"] = "Den Minimap-Knopf zeigen oder verstecken"
L["Move this window back to the middle of the screen, at its normal size and scale"] =
    "Dieses Fenster wieder in die Bildschirmmitte setzen, in normaler Größe und Skalierung"
L["Make the window larger (up to 150%)"] = "Das Fenster größer machen (bis 150%)"
L["Make the window smaller (down to 60%)"] = "Das Fenster kleiner machen (bis 60%)"
L["Drag to resize the window"] = "Ziehen, um die Fenstergröße zu ändern"
L["window scale: %d%%."] = "Fensterskalierung: %d%%."
L["usage: /ledger scale <%d-%d> (percent)"] = "Aufruf: /ledger scale <%d-%d> (Prozent)"
L["/ledger scale <percent> - make the window smaller or larger; drag its lower right corner to resize it"] =
    "/ledger scale <Prozent> - Fenster kleiner oder größer; die rechte untere Ecke ziehen ändert die Größe"
L["Ask the group's other ledgers for this raid's awards (e.g. after a crash)"] =
    "Die anderen Ledger der Gruppe nach den Vergaben dieses Raids fragen (z. B. nach einem Absturz)"
L["RESULT"] = "WURF"
L["%d HELD BY YOU"] = "%d BEI DIR"
L["The loot to roll: start rolls, see every roll, hand items out"] = "Die Beute zum Verlosen: Würfeln starten, alle Würfe sehen, Items vergeben"
L["Every award of this raid: change recipient or tally, remove, export for the website"] =
    "Alle Vergaben dieses Raids: Empfänger oder MS/OS ändern, entfernen, für die Webseite exportieren"
L["Items and tokens per player this raid (what the fewest-items rule ranks by), with corrections"] =
    "Items und Tokens pro Spieler in diesem Raid (danach wird bei gleicher Spec gereiht), mit Korrekturen"

-- Raid feedback 2026-10-26: disenchanter roll
L["Disenchanter roll"] = "Entzauberer-Wurf"
L["[Loot] Disenchanter roll: /rnd 100 now, %d seconds. The winner disenchants this raid's unwanted items."] =
    "[Loot] Entzauberer-Wurf: jetzt /rnd 100, %d Sekunden. Der Gewinner entzaubert die ungewollten Items dieses Raids."
L["%d-second disenchanter roll started."] = "%d-Sekunden-Entzauberer-Wurf gestartet."
L["[Loot] %s is the disenchanter for this raid (%d)."] = "[Loot] %s ist der Entzauberer dieses Raids (%d)."
L["[Loot] Nobody rolled to disenchant; DE gives items to the name in the box."] =
    "[Loot] Niemand hat fürs Entzaubern gewürfelt; DE gibt Items an den Namen im Feld."
L["%s disenchants this raid: DE gives items to them."] = "%s entzaubert in diesem Raid: DE gibt die Items an sie/ihn."
L["a disenchanter roll is already running."] = "ein Entzauberer-Wurf läuft schon."
L["finish the running roll first."] = "erst den laufenden Wurf beenden."
L["Disenchant: give it to %s, this raid's disenchanter; counts for nobody"] =
    "Entzaubern: an %s geben, den Entzauberer dieses Raids; zählt für niemanden"
L["Roll the raid's disenchanter: everyone may /rnd 100, the winner gets every DE item"] =
    "Den Entzauberer des Raids auswürfeln: alle dürfen /rnd 100, der Gewinner bekommt jedes DE-Item"
L["/ledger deroll - roll the raid's disenchanter (/rnd 100); DE then gives items to them"] =
    "/ledger deroll - den Entzauberer des Raids auswürfeln (/rnd 100); DE gibt Items dann an ihn"

-- Window feedback 2026-10-26: BEUTE in two steps, VERGABEN only corrects
L["click a roll or ALL, or type a name"] = "Wurf oder ALLE anklicken, oder Namen tippen"
L["GIVE TO ..."] = "VERGEBEN AN ..."
L["GIVE TO %s"] = "VERGEBEN AN %s"
L["ROLL IT"] = "AUSWÜRFELN"
L["DISENCHANTER: %s"] = "ENTZAUBERER: %s"
L["%s won (%d)."] = "%s hat gewonnen (%d)."
L["Nobody wanted it."] = "Wollte niemand."
L["Open item, not rolled yet."] = "Offenes Item, noch nicht gewürfelt."
L["Not rolled yet."] = "Noch nicht gewürfelt."
L["Open: %s holds it."] = "Offen: %s hat es."
L["BACK TO LOOT"] = "ZURÜCK IN BEUTE"
L["Back to BEUTE as an open item with whoever holds it: roll it again or hand it out there"] =
    "Zurück in BEUTE als offenes Item bei dem, der es hat: dort neu würfeln oder anders vergeben"

-- Raid feedback 2026-10-26, second pass: later roll, chosen disenchanter
L["LATER ROLL"] = "SPÄTER WÜRFELN"
L["CHOOSE"] = "WÄHLEN"
L["Choose the raid's disenchanter from the raid, without a roll"] = "Den Entzauberer des Raids aus dem Raid wählen, ohne Wurf"
L["[Loot] %s is the disenchanter for this raid."] = "[Loot] %s ist der Entzauberer dieses Raids."
L["usage: /ledger de <name>"] = "Aufruf: /ledger de <Name>"
L["/ledger de <name> - make <name> the raid's disenchanter without a roll"] =
    "/ledger de <Name> - <Name> ohne Wurf zum Entzauberer des Raids machen"
L["Who gets the item?"] = "Wer bekommt das Item?"
L["Who keeps it until the roll?"] = "Wer behält es bis zum Würfeln?"
L["Who disenchants this raid?"] = "Wer entzaubert in diesem Raid?"
L["Roll it later: pick who keeps it until then. A unique item you already have goes straight from the corpse to them."] =
    "Später würfeln: wählen, wer es bis dahin behält. Ein Unique-Item, das du schon hast, geht direkt aus der Leiche an diese Person."
