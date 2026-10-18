# 🛡️ WoW 3.3.5a — Guild Raid Addons

Purpose-built **World of Warcraft: Wrath of the Lich King (3.3.5a)** addons for running raids together with the guild's raid website. Game and website exchange **copy-and-paste text**: no external client, API key or live website connection is needed in game.

> **Client compatibility:** These addons target the **3.3.5a / Interface 30300** client, not modern retail WoW. RaidLedger and RaidWishlist speak **German in German clients** and English everywhere else.

## ✨ At a glance

| Addon | Who uses it | What it does | Open it |
| --- | --- | --- | --- |
| **[RaidLedger](#-raidledger)** | Raid lead / master looter | Invites the website's raid list, creates the raid's calendar event, sorts groups by role, exports attendance, runs the loot rolls (main/off spec, enhanced EP rolls, fewest-items-first, passes and roll corrections, free BoE rolls, rolls on items from your bags), records awards, trades, parked, disenchanted and guild-bank items, and exports the loot for the website. | `/ledger` or the minimap button |
| **[RaidWishlist](#-raidwishlist)** | Raid members | Imports the member's wishlist from the website, prompts (or rolls automatically) when a wished item is rolled, shows open items and who got what, and shares the wishlist with the raid lead. | `/wish` or the minimap button |
| **[InviteMailer](#%EF%B8%8F-invitemailer)** | Officers | Sends personalized in-game letters containing individual invite codes. | `/im` |

**RaidLedger replaces RaidSync**, which used to live here: it does everything RaidSync did (invites, groups, attendance, loot) and more. All three addons can be installed and enabled independently. The source, offline tests and live acceptance plans of RaidLedger and RaidWishlist are in [robinschweitz/addon-forge](https://github.com/robinschweitz/addon-forge) (`examples/`).

## 📦 Installation

Guild members can download RaidLedger and RaidWishlist as ready-made zips on the guild website's **Addons** page (one folder per zip, unzip into `Interface/AddOns/`). Or get them here:

1. Download this repository using **Code → Download ZIP**, or clone it:

   ```bash
   git clone https://github.com/robinschweitz/wow-addons.git
   ```

2. Copy **the individual addon folders** into your WoW installation's `Interface/AddOns/` directory: raid leads take `RaidLedger`, raid members `RaidWishlist`, officers who mail invite codes `InviteMailer`. Do **not** copy only their `.lua` files, and don't nest an extra `wow-addons` folder around them.
3. Check that your files look like this:

   ```text
   World of Warcraft/
   └── Interface/
       └── AddOns/
           ├── RaidLedger/
           │   ├── RaidLedger.toc
           │   ├── Locales.lua
           │   ├── RaidLedger.lua
           │   ├── Raid.lua
           │   └── Minimap.lua
           ├── RaidWishlist/
           │   ├── RaidWishlist.toc
           │   ├── Locales.lua
           │   └── RaidWishlist.lua
           └── InviteMailer/
               ├── InviteMailer.toc
               └── InviteMailer.lua
   ```

4. Coming from RaidSync? Delete the old `Interface/AddOns/RaidSync` folder.
5. Restart WoW, choose **AddOns** at the character-selection screen, and enable the addon(s).

**Note:** The addons are designed for a particular guild raid website ([robinschweitz/raid-website](https://github.com/robinschweitz/raid-website)), which produces and reads the text formats below. The addons never contact a website on their own.

---

## ⚔️ RaidLedger

The raid lead's addon. Its window has three panes (loot items, the selected award, recent awards) and two buttons at the top: **RAID** (raid setup) and **EXPORT** (loot export). `/ledger` or the minimap button opens it (drag the button to move it, `/ledger minimap off` hides it). See [`RaidLedger/README.md`](RaidLedger/README.md) for every detail.

### Raid setup: invites, groups, attendance (formerly RaidSync)

1. On the website, open the raid's **Aufstellung → „Einladungen für Addon“** and copy the text.
2. In game click **RAID** (or `/ledger setup`), paste it into the box and click **READ** (**EINLESEN**). The list shows every character with role and status. Reading the list also sets the website raid ID for the loot export.
3. Click **INVITE ALL** (**ALLE EINLADEN**). Invites go out in the website's order, about 0.3 s apart; a party becomes a raid as soon as someone joined. Known offline guild members are skipped; the bench only with **BENCH: YES**. Statuses: open, invited, in raid, declined, not found, in another group, offline, no answer, bench.
4. **RETRY MISSING** (**FEHLENDE ERNEUT**) invites everyone who declined or did not answer again.
5. **SORT GROUPS** (**GRUPPEN SORTIEREN**) puts tanks, then healers, then the rest into groups of five (raid lead or assistant). It is a simple role sort, not a composition planner.
6. At the end, **EXPORT** under „Teilnahme für die Webseite“ lists everyone seen in the raid, including late additions from the world chat and players who left again. Copy it (Ctrl+C) into the website's **Aufstellung** import.
7. **CALENDAR EVENT** (**KALENDER-TERMIN**, or `/ledger calendar`) prepares a raid event in the game calendar for the list's date and start time (realm time); **CREATE EVENT** (**TERMIN ERSTELLEN**) then adds it and invites everyone on the list, the bench too. The website adds date and time to the list for raids of a raid series; lists without them are still read, only the calendar event needs them.

```text
RS2;INV;42;ICC 25 Mittwoch;25;2026-11-05;20:00
Thorgar;TANK;Krieger;0
Aelira;HEAL;Priester;0
Standby;DD;Jäger;1

RS2;ROSTER;42;Raidleader;1760007200
Thorgar;WARRIOR;1760000010
Latejoin;PALADIN;1760001200
```

### Rolls and awards

- Select an item in the master-loot window and `/ledger start`: a 30-second raid roll. `/rnd 100` is **main spec**, `/rnd 99` **off spec**, an enhanced main-spec roll is **1+X to 100+X** with X = min(EP, 50). Main spec beats off spec; within a spec the player with the **fewest items this raid** wins, then the roll. Tokens have their own tally. Ties get a 15-second tie-break.
- **GIVE + RECORD** hands the item out through master loot; items you keep for later are followed through your trades. **PARK** leaves an item with a raider until it is rolled (unique items). **DE** and **BANK** send unwanted items to the enchanter or the guild bank character; they count for nobody.
- Under the items the window lists the selected item's rolls. **Right-click a roll** to take a pass (the next-best roll wins) or to count it differently: main spec, off spec, not at all, or an enhanced roll with corrected points (110 from 21-120 with 10 instead of 20 EP becomes 100 from 11-110). This also works in a given-out award's roll log: the award then moves to the new winner.
- The four buttons under the award button show the rollers, winner first; **ALL (n)** opens the whole raid by group to pick any recipient.
- A bind-on-equip item nobody rolls on can be posted again as a **free BoE roll** for any character (`/rnd 100`, highest wins, counts for nobody).
- **Alt+click an item in your bags** (or `/ledger roll <link or ID>`) to roll it out later, e.g. after the loot window closed; the winner gets it by trade. Items that still wait for a roll stay in the master loot list, marked **OPEN** with their holder, until they are rolled.
- Every award is announced to the raid and shared with other ledger users and the members' wishlist addons. Raiders' shared wishlists show as **WL n** on each drop and `[WL #rank]` on rollers.
- Click an award to see its rolls or change the recipient; `/ledger del <#>` removes one (the export keeps it as deleted).

### Loot export

**EXPORT** builds the website's loot import (`RS2;LOOT;...`, one line per award with roll, spec, range and winner). Copy it into the raid's **Loot-Import** on the website; the preview there lets staff check boss, recipient and award method before anything is saved. **NEW RAID** (or **CLEAR**) empties the ledger for the next raid; export first.

---

## 🎯 RaidWishlist

The raid member's addon. See [`RaidWishlist/README.md`](RaidWishlist/README.md).

1. On your character page on the website, set main/second spec and Enhanced per wish and click **„Für Addon exportieren“**.
2. In game: `/wish import` (or **IMPORT**), paste, **IMPORT WISHLIST**.
3. When the raid lead rolls an item from your list, the window opens and a prompt offers **ROLL MS 21-120** (your spec and EP) or **SKIP**. **AUTO-ROLL** rolls for you, e.g. while you are away.
4. The window also lists **open items** (on the corpse, with the master looter, parked with a raider) and **this raid's awards** with your item and token tally.
5. Your wishlist is shared with the raid lead's ledger (`/wish share off` stops that). The minimap button opens the window; drag it to move it, `/wish minimap off` hides it.
6. The window looks like RaidLedger's in its own color: the color button in its header (or `/wish color`) picks any color, right-click (or `/wish color reset`) goes back to green.

---

## ✉️ InviteMailer

**InviteMailer** automates personalized **in-game mail**, particularly for distributing distinct invite codes for a guild's loot-wishlist website. It sends one letter per recipient while the **WoW mailbox is open**.

### Send a batch of codes

1. Open an **in-game mailbox**.
2. Type `/im` (or `/invitemailer`) to open InviteMailer.
3. Edit the **Subject** and **Letter text** templates.
4. Paste a recipient list, **one character and code per line**.
5. Press **Start**. Keep the mailbox open until sending finishes.
6. Watch the **Sent / Failed** status and chat messages. If necessary, click **Load failed**, fix any incorrect names, and press **Start** again.

For example, the recipient list can be:

```text
Thorgar:ABCD-1234
Aelira:EFGH-5678
Frostlin:IJKL-9012
```

The parser also accepts `Name,Code`, `Name;Code`, and `Name Code` (a single whitespace separator) instead of `Name:Code`. Blank lines are ignored and malformed lines are reported as skipped. The template supports two placeholders:

| Placeholder | Replaced with |
| --- | --- |
| `{name}` | Character name on that line |
| `{code}` | The corresponding private invite code |

Example:

**Subject:** `Your invitation, {name}`

**Body:**

```text
Hi {name},

Your loot-wishlist invite code is: {code}

See you in the raid!
```

Each recipient gets the **same template**, with only their own name and code substituted.

### Sending behavior and safety checks

- It sends letters **sequentially**, allowing about **0.5 seconds between successful/result-confirmed sends**.
- It waits for the server's mail success/failure event, with a **15-second timeout** to classify an unanswered attempt as failed.
- The addon checks for at least **30 copper postage** before attempting each letter and prints the total planned postage before starting.
- Press **Stop** to pause sending. Closing the mailbox also pauses the operation. Mail cannot be sent with the mailbox closed.
- Clicking **Load failed** replaces the recipient editor with **only this run's failed entries**, useful for correcting names and retrying.
- On a successful send, it stores the recipient's name (case-insensitively) and code in `InviteMailerDB.sent`. **Later runs skip any previously successful recipient name**, even if their code in the pasted list has changed.
- Use `/im reset` to **clear that sent history** and allow resending to those names.

**Please read before bulk sending:** There is **no per-message confirmation prompt**; pressing Start initiates mail delivery. Validate the list and template first. The addon warns when the first expanded body exceeds **500 characters**, but does not guarantee delivery of an oversized body. A timeout is treated as a failure even if the server might have delivered that mail; verify uncertain results before retrying to avoid duplicates. Sent history is a convenience safeguard, **not** a delivery audit.

---

## ⌨️ Command reference

| Command | Effect |
| --- | --- |
| `/ledger` | Show or hide the ledger |
| `/ledger setup` | Raid setup: invites, groups, attendance |
| `/ledger invite [missing]` | Invite the website's list (or retry the missing) |
| `/ledger groups` | Sort raid groups: tanks, healers, the rest |
| `/ledger attendance` | Export who was in the raid |
| `/ledger start` | Start a 30-second roll for the selected item |
| `/ledger pass <name>` · `/ledger count <name> ms\|os\|none\|enh <0-50>` | Take a pass or change how a roll counts (selected item or shown award) |
| `/ledger free` | Post the selected item again as a free BoE roll |
| `/ledger roll <link or ID>` | Roll an item from your bags (same as Alt+click on it) |
| `/ledger calendar` | Calendar raid event from the invite list, everyone invited |
| `/ledger minimap on\|off` | Show / hide the minimap button |
| `/ledger set <#> [name]` | Change the recipient of award # (without a name: your target) |
| `/ledger del <#>` | Remove award # (exported as deleted) |
| `/ledger tally` | Items per player this raid |
| `/ledger export` | Show the loot export |
| `/ledger help` | All ledger commands |
| `/wish` | Show or hide the wishlist |
| `/wish import` · `/wish auto on\|off` · `/wish share on\|off` · `/wish minimap on\|off` · `/wish color [reset]` | Wishlist import, switches and window color |
| `/im`, `/invitemailer` | Toggle InviteMailer |
| `/im reset` | Forget InviteMailer's successfully mailed recipients so they may be sent mail again |

## 💾 Saved data and privacy

All addons use standard **WoW SavedVariables**:

| SavedVariable | Contains |
| --- | --- |
| `RaidLedgerDB` | Awards with their roll logs, the raid ID, the imported invite list with statuses, the attendance seen in the raid |
| `RaidWishlistDB` | Your wishlist per character (with your EP balance from the last export), this raid's awards, switches |
| `InviteMailerDB` | Mail subject/body templates, recipient list (including invite codes), and successful-send history |

The addons **do not make network requests to the guild website**. Transfers happen through copy and paste. Members' wishlists (items, spec, Enhanced, order; not notes) are shared with the group over addon messages unless `/wish share off` is set. Treat pasted invite codes and SavedVariables backups as **sensitive**.

## 🧪 Testing and development

RaidLedger and RaidWishlist are developed in [robinschweitz/addon-forge](https://github.com/robinschweitz/addon-forge): offline specs (`examples/<Addon>/tests/*.spec.lua`, run with `forge spec`) and live acceptance plans that drive a real 3.3.5a test client on a local AzerothCore realm. Change them there and copy the addon folders here. No automated InviteMailer test suite is present in this repository.

## 🛠️ Troubleshooting

| Symptom | Check |
| --- | --- |
| The slash command does nothing | Confirm the addon folder and `.toc` are directly inside `Interface/AddOns/`; enable it at character selection; use the 3.3.5a client. |
| READ rejects the invite list | Paste the **entire** website text, starting with `RS2;INV;`. Lists from the old RaidSync website export (`RS1\|INV`) are not read; export again. |
| The ledger cannot invite | You must be party leader, raid leader or assistant. Check names, online status, free slots and **BENCH**. |
| The attendance export is empty | The ledger records raid members while it runs; it needs a raid ID from the invite list or `/ledger raid <id>`. |
| No loot is listed | Use **Master Loot**, be the master looter, check the loot threshold. |
| A wishlist is refused | Export it again on the website: the addon reads `WL2;` lists of the logged-in character. |
| InviteMailer won't start | Open a mailbox, check postage money, and check whether everyone in the list is already marked sent. |
| InviteMailer skips a changed code | It deduplicates by **recipient name**, not by code. Run `/im reset` only when deliberate resending is appropriate. |
| A mail attempt fails or times out | Review the error, correct the character name, and use **Load failed**; verify uncertain deliveries before retrying. |

## 📁 Repository layout

```text
.
├── RaidLedger/
├── RaidWishlist/
├── InviteMailer/
│   ├── InviteMailer.lua
│   └── InviteMailer.toc
└── README.md
```

---

Made for guild raid administration on **WoW 3.3.5a**. Contributions and bug reports are welcome via [GitHub Issues](https://github.com/robinschweitz/wow-addons/issues).
