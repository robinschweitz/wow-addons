-- SPDX-License-Identifier: GPL-2.0-only
-- Texts are keyed by their English wording, which is also the fallback: any
-- client that is not German shows the key itself. German clients (deDE) get the
-- table below. Keep format specifiers (%s, %d) in the same order.
local _, ns = ...
local L = setmetatable({}, { __index = function(_, key) return key end })
ns.L = L

if GetLocale() ~= "deDE" then return end

-- Window
L["Window color"] = "Fensterfarbe"
L["Click: pick a color"] = "Klick: Farbe wählen"
L["Right-click: back to the default"] = "Rechtsklick: zurück zur Standardfarbe"
L["window color reset."] = "Fensterfarbe zurückgesetzt."
L["/wish color [reset] - pick the window color, or go back to the default"] =
    "/wish color [reset] - Fensterfarbe wählen oder zur Standardfarbe zurück"
L["IMPORT"] = "IMPORT"
L["EDIT"] = "BEARBEITEN"
L["REMIND"] = "ERINNERN"
L["SETTINGS"] = "EINSTELLUNGEN"
L["ENHANCE POINTS"] = "ENHANCE-PUNKTE"
L["AUTO-ROLL: ON"] = "AUTO-WURF: AN"
L["AUTO-ROLL: OFF"] = "AUTO-WURF: AUS"
L["MY WISHLIST"] = "MEINE WUNSCHLISTE"
L["MY WISHLIST (%d)"] = "MEINE WUNSCHLISTE (%d)"
L["No wishlist yet.\nCopy the export on the guild website, then IMPORT."] =
    "Noch keine Wunschliste.\nExport auf der Gildenwebseite kopieren, dann IMPORT."
L["OPEN ITEMS"] = "OFFENE ITEMS"
L["OPEN ITEMS (%d)"] = "OFFENE ITEMS (%d)"
L["No loot is waiting to be rolled."] = "Keine Beute wartet aufs Auswürfeln."
L["THIS RAID"] = "DIESER RAID"
L["THIS RAID (%d)"] = "DIESER RAID (%d)"
L["YOU: ITEMS %d MS / %d OS  |  TOKENS %d MS / %d OS"] = "DU: ITEMS %d MS / %d OS  |  TOKENS %d MS / %d OS"
L["Nothing handed out yet.\nAwards appear here when the raid lead uses RaidLedger."] =
    "Noch nichts vergeben.\nHier erscheinen die Vergaben aus RaidLedger."
L["Rolls start from the raid lead's RaidLedger  |  /wish help"] = "Würfe startet die Raidleitung mit RaidLedger  |  /wish help"
L["Paste your wishlist export from the guild website (Ctrl+V):"] = "Wunschlisten-Export der Gildenwebseite einfügen (Strg+V):"
L["IMPORT WISHLIST"] = "IMPORTIEREN"
L["EDIT WISHLIST"] = "WUNSCHLISTE BEARBEITEN"
L["Item ID"] = "Item-ID"
L["Item ID (manual fallback)"] = "Item-ID (manuelle Eingabe)"
L["SET POINTS"] = "PUNKTE SETZEN"
L["Enter a whole number from 0 to 999999."] = "Bitte eine ganze Zahl von 0 bis 999999 eingeben."
L["Enhance points set to %d."] = "Enhance-Punkte auf %d gesetzt."
L["Search item name"] = "Itemname suchen"
L["ALL RAIDS"] = "ALLE RAIDS"
L["ALL QUALITIES"] = "ALLE QUALITÄTEN"
L["Epic"] = "Episch"
L["Legendary"] = "Legendär"
L["%d catalogue matches in %s (mouse wheel for more)."] = "%d Katalogtreffer in %s (Mausrad für mehr)."
L["Click to choose a raid filter"] = "Klick: Raidfilter auswählen"
L["Click to open the raid filter"] = "Klick: Raidfilter öffnen"
L["Click to open the item quality filter"] = "Klick: Itemqualitätsfilter öffnen"
L["SEARCH"] = "SUCHEN"
L["ADD TO WISHLIST"] = "ZUR WUNSCHLISTE"
L["Enter an item name to search the raid catalogue."] = "Bitte einen Itemnamen für den Raidkatalog eingeben."
L["Search names can be at most 60 characters."] = "Suchnamen dürfen höchstens 60 Zeichen lang sein."
L["Search text cannot contain |."] = "Suchtext darf kein | enthalten."
L["No raid loot matches that name."] = "Keine Raidbeute passt zu diesem Namen."
L["%d catalogue matches (mouse wheel for more)."] = "%d Katalogtreffer (Mausrad für mehr)."
L["Selected item ID: %d"] = "Ausgewählte Item-ID: %d"
L["Naxxramas"] = "Naxxramas"
L["Obsidian Sanctum"] = "Obsidiansanktum"
L["Eye of Eternity"] = "Auge der Ewigkeit"
L["Ulduar"] = "Ulduar"
L["Trial of the Crusader"] = "Prüfung des Kreuzfahrers"
L["Onyxia's Lair"] = "Onyxias Hort"
L["Icecrown Citadel"] = "Eiskronenzitadelle"
L["Ruby Sanctum"] = "Rubinsanktum"
L["Note (optional)"] = "Notiz (optional)"
L["MAIN SPEC"] = "HAUPTSPEC"
L["OFF SPEC"] = "ZWEITSPEC"
L["ENHANCED"] = "VERBESSERT"
L["ENHANCED: ON"] = "VERBESSERT: AN"
L["ENHANCED: OFF"] = "VERBESSERT: AUS"
L["SAVE"] = "SPEICHERN"
L["DELETE"] = "LÖSCHEN"
L["Enter a positive item ID."] = "Bitte eine positive Item-ID eingeben."
L["No wishlist item selected."] = "Kein Wunschlisten-Item ausgewählt."
L["Saved wishlist item."] = "Wunschlisten-Item gespeichert."
L["Removed wishlist item."] = "Wunschlisten-Item entfernt."
L["CHAT ROLL REMINDER"] = "CHAT-WÜRFEL-ERINNERUNG"
L["A reminder needs a wishlisted item link and a keyword."] = "Eine Erinnerung braucht einen Wunsch-Itemlink und ein Schlüsselwort."
L["Only the master looter"] = "Nur der Plündermeister"
L["All group members"] = "Alle Gruppenmitglieder"
L["Keywords (comma-separated)"] = "Schlüsselwörter (mit Komma)"
L["SAVE SETTINGS"] = "EINSTELLUNGEN SPEICHERN"
L["Enter at least one reminder keyword."] = "Bitte mindestens ein Schlüsselwort eingeben."
L["Settings saved."] = "Einstellungen gespeichert."
L["That item is already on your wishlist."] = "Dieses Item steht schon auf deiner Wunschliste."
L["RECEIVED"] = "ERHALTEN"
L["REMOVED"] = "ENTFERNT"
L["DE"] = "DE"
L["BANK"] = "BANK"
L[" TOKEN"] = " TOKEN"
L["OPEN"] = "OFFEN"
L["ROLLING NOW"] = "WIRD GEWÜRFELT"
L["WON"] = "VERGEBEN"
L["WON: %s"] = "AN: %s"
L["WISHLIST  "] = "WUNSCH  "
L["on the corpse"] = "auf der Leiche"
L["with %s"] = "bei %s"
L["WISHLIST"] = "WUNSCHLISTE"
L["CANCEL"] = "ABBRECHEN"
L["%d-%d / %d  (mouse wheel)"] = "%d-%d / %d  (Mausrad)"
L["Auto-roll: roll on wishlisted items by yourself, without the prompt (e.g. while away)."] =
    "Auto-Wurf: auf Wünsche automatisch würfeln, ohne Abfrage (z. B. wenn du kurz weg bist)."
L["Import: paste your wishlist export from the guild website."] = "Import: Wunschlisten-Export der Gildenwebseite einfügen."
L["Edit: add, change or remove wishlist items."] = "Bearbeiten: Wunschlisten-Items hinzufügen, ändern oder entfernen."
L["Catalogue search: find WotLK raid loot by English or German name."] =
    "Raidkatalog: WotLK-Raidbeute nach englischem oder deutschem Namen finden."
L["Click: select this item for your wishlist"] = "Klick: dieses Item für die Wunschliste auswählen"
L["Reminder: react to chat announcements without RaidLedger."] = "Erinnerung: auf Chat-Ansagen ohne RaidLedger reagieren."
L["Settings: set Enhance points and chat roll reminders."] =
    "Einstellungen: Enhance-Punkte und Chat-Würfel-Erinnerungen setzen."
L["Your wishlist in rank order, with the roll range you would use."] = "Deine Wunschliste nach Rang, mit deinem Würfelbereich."
L["Loot still waiting to be rolled: on the corpse, or parked with a raider."] =
    "Beute, die noch ausgewürfelt wird: auf der Leiche oder bei einem Raider geparkt."
L["Who got what this raid, and your items so far."] = "Wer in diesem Raid was bekommen hat, und deine Items bisher."

-- Roll prompt
L["ON YOUR WISHLIST"] = "AUF DEINER WUNSCHLISTE"
L["ROLL"] = "WÜRFELN"
L["ROLL %s"] = "WÜRFELN %s"
L["SKIP"] = "PASSEN"
L["Priority %d, %s%s"] = "Priorität %d, %s%s"
L["Rolled %s for %s."] = "%s gewürfelt für %s."
L["Skipped %s."] = "%s gepasst."
L["Auto-roll: %s for %s in a moment."] = "Auto-Wurf: gleich %s für %s."

-- Tooltips
L["Wishlist: %s"] = "Wunschliste: %s"
L["Waiting to be rolled, %s"] = "Wartet aufs Auswürfeln, %s"
L["no spec"] = "keine Spec"
L[", roll %d"] = ", Wurf %d"

-- Import
L["Paste the wishlist export from the website first."] = "Zuerst den Wunschlisten-Export der Webseite einfügen."
L["That is not a wishlist export (it must start with WL2;). Export it again from the website."] =
    "Das ist kein Wunschlisten-Export (er beginnt mit WL2;). Bitte auf der Webseite neu exportieren."
L["This wishlist is for %s. Log in with %s to import it."] = "Diese Wunschliste gehört %s. Zum Importieren mit %s einloggen."
L["Imported %d wishlist items%s."] = "%d Wünsche importiert%s."
L["imported %d wishlist items%s."] = "%d Wünsche importiert%s."
L[" (%d invalid lines skipped)"] = " (%d ungültige Zeilen übersprungen)"

-- Chat
L["auto-roll is ON: wishlisted items are rolled for you."] = "Auto-Wurf ist AN: für Wünsche wird automatisch gewürfelt."
L["auto-roll is OFF: you get a roll prompt."] = "Auto-Wurf ist AUS: du bekommst eine Würfel-Abfrage."
L["asked the raid lead's ledger for this raid's awards."] = "das Buch der Raidleitung nach den Vergaben dieses Raids gefragt."
L["not in a group."] = "nicht in einer Gruppe."
L["/wish - show or hide your wishlist"] = "/wish - Wunschliste zeigen oder verbergen"
L["/wish import - paste the wishlist export from the guild website"] = "/wish import - Wunschlisten-Export der Gildenwebseite einfügen"
L["/wish edit - add a wishlist item without an export"] = "/wish edit - Wunschlisten-Item ohne Export hinzufügen"
L["/wish auto on|off - roll automatically on wishlisted items (e.g. while away)"] =
    "/wish auto on|off - automatisch auf Wünsche würfeln (z. B. wenn du kurz weg bist)"
L["/wish sync - ask the raid lead's ledger for this raid's awards"] = "/wish sync - das Buch der Raidleitung nach den Vergaben fragen"
L["/wish minimap on|off - show or hide the minimap button"] = "/wish minimap on|off - Minimap-Knopf zeigen oder verbergen"

-- Minimap button
L["Click: open or close your wishlist"] = "Klick: Wunschliste öffnen oder schließen"
L["Drag: move this button"] = "Ziehen: Knopf verschieben"
L["minimap button shown."] = "Minimap-Knopf wird angezeigt."
L["minimap button hidden; /wish minimap on brings it back."] = "Minimap-Knopf ausgeblendet; /wish minimap on holt ihn zurück."

-- Sharing the wishlist
L["/wish share on|off - show your wishlist to the raid lead's ledger (on by default)"] =
    "/wish share on|off - Wunschliste der Raidleitung zeigen (Standard: an)"
L["/wish remind all|master - chat roll reminders from all group members or only the master looter"] =
    "/wish remind all|master - Chat-Würfel-Erinnerung von allen Gruppenmitgliedern oder nur vom Plündermeister"
L["CHAT REMINDER: ON"] = "CHAT-ERINNERUNG: AN"
L["CHAT REMINDER: OFF"] = "CHAT-ERINNERUNG: AUS"
L["chat roll reminders are on."] = "Chat-Würfel-Erinnerung ist an."
L["chat roll reminders are off."] = "Chat-Würfel-Erinnerung ist aus."
L["/wish remind on|off - open the roll prompt for chat announcements (off by default)"] =
    "/wish remind on|off - Würfelabfrage bei Chat-Ansagen öffnen (Standard: aus)"
L["chat roll reminders: all group members."] = "Chat-Würfel-Erinnerung: alle Gruppenmitglieder."
L["chat roll reminders: only the master looter."] = "Chat-Würfel-Erinnerung: nur der Plündermeister."
L["your wishlist is shared with the raid lead's ledger."] = "deine Wunschliste wird mit dem Buch der Raidleitung geteilt."
L["your wishlist is no longer shared."] = "deine Wunschliste wird nicht mehr geteilt."
L["window scale: %d%%."] = "Fensterskalierung: %d%%."
L["usage: /wish scale <%d-%d> (percent)"] = "Aufruf: /wish scale <%d-%d> (Prozent)"
L["/wish scale <percent> - make the window smaller or larger; drag its lower right corner to resize it"] =
    "/wish scale <Prozent> - Fenster kleiner oder größer; die rechte untere Ecke ziehen ändert die Größe"
L["/wish reset - the window back to the middle, normal size and scale"] =
    "/wish reset - Fenster mittig, in normaler Größe und Skalierung"
L["Drag to resize the window"] = "Ziehen, um die Fenstergröße zu ändern"
L["Make the window larger (up to 150%)"] = "Das Fenster größer machen (bis 150%)"
L["Make the window smaller (down to 60%)"] = "Das Fenster kleiner machen (bis 60%)"

-- Items the client has not seen yet (the name arrives from the server)
L["[Item %d]"] = "[Gegenstand %d]"
