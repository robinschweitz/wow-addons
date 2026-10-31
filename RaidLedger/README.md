# RaidLedger

The raid lead's addon for WoW 3.3.5a (Interface 30300): raid setup (invites,
groups, attendance), loot rolls, awards and the website exports. It replaces
RaidSync, whose features it took over. The guild installs it from
[robinschweitz/wow-addons](https://github.com/robinschweitz/wow-addons); this
folder in [addon-forge](https://github.com/robinschweitz/addon-forge) is the
source, with offline specs in `tests/` and live plans beside the folder
(`RaidLedger-*.json`).

Open and close it with `/ledger` or the minimap button (drag it to move it
around the minimap; `/ledger minimap off` hides it).

The addon speaks German in German clients (deDE): window, raid announcements,
chat and help. Every other client gets English. Texts live in `Locales.lua`,
keyed by their English wording.

## The window

One window with five tabs (2.5.0, after the raid feedback "cleaner, easier,
everything in the UI"); each tab owns the full height, so long lists stay
readable. Every button and field has a tooltip. Chat commands still work, but
none is needed.

| Tab | What it is for |
| --- | --- |
| **BEUTE** (loot) | The loot list (this corpse's drops, then the open items held until they are rolled), the raid's **disenchanter** below it, and the selected item in two steps: **1 ROLL** (**ROLL**, free BoE roll for BoE items, every roll with what the roller has **so far**) and **2 HAND OUT** (name box, **ALL**, **GIVE TO name**, **DISENCHANT**, **GUILD BANK**). The button for the next step is green. The compact master-loot popup has **ASSIGN**, **ROLL** and **LATER ROLL**. |
| **VERGABEN** (awards) | Every award; the selected one is only corrected: **COUNTS AS** main spec / off spec / nothing, change or restore its recipient, **BACK TO LOOT**, **REMOVE**, its roll log; **EXPORT** and **NEW RAID** |
| **SPIELER** (players' tally) | Every raid member with items and tokens per spec, the numbers the fewest-items rule ranks by; - / + corrections per player, and their awards |
| **RAID** | Invites, raid groups, attendance, calendar event |
| **EINSTELLUNGEN** (settings) | Editors, who runs which addon, roll lengths, minimap button, window scale and reset, sync |

**Size and scale** (2.6.0, for high- and low-resolution clients): drag the
grip in the lower right corner to make the window larger, up to the screen's
edges (760 x 480 is the smallest). Every list then shows more rows, and the
panes share the extra width. **Scale** in EINSTELLUNGEN (- / +, 60-150%) or
`/ledger scale <percent>` makes the whole window smaller or larger. Size and
scale are saved; **RESET WINDOW** or `/ledger reset` brings back the middle of
the screen, 760 x 480 and 100%.

The source is split accordingly: `RaidLedger.lua` keeps all rules and state,
`UI.lua` the window and shared widgets, `LootTab.lua`, `AwardsTab.lua`,
`TallyTab.lua`, `Raid.lua` and `Access.lua` one tab each.

## Raid setup: invites, groups, attendance

**RAID** (or `/ledger setup`) replaces the panes with the raid setup
(`Raid.lua`):

1. Paste the website's invite list (raid page, Aufstellung, „Einladungen für
   Addon“) and click **READ**. The list fills the right side of the tab and
   shows each character's role, class and status;
   the website raid ID is also used for the loot export.
2. **INVITE ALL** invites the list in the website's order (about 0.3 s apart).
   A party turns into a raid once someone joined. Offline guild members (per the
   guild roster) are skipped, the bench only with **BENCH: YES**. Server
   messages set the status: open, invited, in raid, declined, not found, in
   another group, offline, no answer (after 65 s), bench.
3. **RETRY MISSING** invites again whoever is not in the raid, not offline and
   not still invited.
4. **SORT GROUPS** (raid lead or assistant) puts tanks, then healers, then the
   rest into groups of five, by name within a role.
5. **EXPORT** under "attendance for the website" lists everyone seen in the raid
   with class and first-seen time, also late additions and players who left.
   Paste it into the website's roster import. A list for another raid starts a
   new attendance.
6. **CALENDAR EVENT** (or `/ledger calendar`) creates a raid event in the game
   calendar for the list's date and start time and invites everyone on the
   list, the bench too (they signed up). The invites go out one at a time;
   names the server does not know are reported. Afterwards the ledger reads
   the calendar back and says whether the server confirmed the event. The
   calendar takes 100 characters per event, and only future dates.

```text
RS2;INV;<raid ID>;<raid name>;<size>;<YYYY-MM-DD>;<HH:MM>
<name>;<TANK|HEAL|DD>;<class>;<bench 0/1>

RS2;ROSTER;<raid ID>;<recorder>;<export time>
<name>;<class token or ->;<first seen>
```

Date and start time (realm time) are needed only for the calendar event; a
list without them (`RS2;INV;<raid ID>;<raid name>;<size>`) is still read.
Both are `;`-separated like the loot export. RaidSync's `RS1|INV` lists are not
read: export the list again on the website.

## Rolls

Opening a loot window lists every item at or above the group's loot threshold.
Select an item and press **ROLL** (or `/ledger start`) to start a 30-second
roll. Change the length in EINSTELLUNGEN or with
`/ledger timer <seconds> [tie-break seconds]` (roll 10-300 s, tie-break
5-120 s, default 30/15; `/ledger timer reset`), saved across `/reload` and new
raids. A running roll keeps its time. The raid is reminded when half and
a quarter of the time are left (30 s: at 15 and 8 seconds). The raid's rules:

- `/rnd 100` (1-100) is **main spec**, `/rnd 99` (1-99) is **off spec**.
- EP enhance a main-spec roll to 1+X..100+X with X = min(EP, 50), the guild
  website's rule: any range from 2-101 up to 51-150 counts. Off spec cannot be
  enhanced. The addon trusts the roll; the website deducts X from the EP
  balance (the export carries the range).
- **Main spec always beats off spec.**
- Within one spec, **the player with the fewest items this raid wins**; the
  roll decides between equal tallies. Main spec and off spec have separate
  tallies, and tokens (Weiheabzeichen) have their own: a token roll goes to
  the player with the fewest tokens.
- Only a player's first roll counts. Any other range is ignored.
- A tie (same spec, same tally, same roll) starts a 15-second tie-break among
  the tied players, and may tie again.

Announcements go to raid, then party, then local chat:
"[item] won by Bob (87) - main spec 21-120, 0 items so far." The start of a
roll and of a tie-break goes out as a **raid warning** when you are raid
leader or assistant (2.7.0), so nobody misses it; reminders and winners stay
in raid chat.

### The roll list

Beside the loot list, the selected item's rolls are listed in winning order:
name (class colored), spec (`MS`, `MS 21-120`, `OS`, `BoE`), **SO FAR** (the
roller's items of that spec this raid, the number the ranking used) and the
roll. The winner is green, ignored or passed rolls grey with the reason. The
mouse wheel scrolls a long list; the loot list stays in place.

### Picking the recipient

After a roll the winner is in the recipient box. Click any roll to make its
player the recipient, or **ALL (n)** for every raid member, one column per raid
group, in class colors.

### Passes and corrections

Only the master looter (or an editor) changes rolls. Right-click a roll in the roll list for:

- **PASS**: the player does not need the item after all. The roll is struck
  ("[item] - Bob passes."). Once a winner was announced, the next-best roll
  wins and is announced; after a tie-break the other tied player comes first,
  then the earlier rolls. With nobody left: "no valid rolls".
- **MAIN SPEC**, **OFF SPEC**, **DOES NOT COUNT**: count the roll differently.
  Main spec takes the points off an enhanced roll (110 from 21-120 counts 90).
- **ENHANCED ...**: correct the points of an enhanced roll. Someone rolled as
  with 20 EP but had 10: 110 from 21-120 becomes 100 from 11-110. 0 points is
  a plain main-spec roll.

Every change is announced ("[item] - Bob's roll counts as main spec 11-110
(100)."), and the roll log keeps what was really rolled. The same commands:
`/ledger pass <name>` and `/ledger count <name> ms|os|none|enh <0-50>`.

The same right-click works in a given-out award's roll log (VERGABEN, select
the award). If someone else now wins, the award goes to them like a recipient
change: announced with "(corrected)", the tally moves, and the old winner
trades the item over. With nobody valid left, or a tie, the award stays and
the ledger asks you to decide (DE, BANK or another recipient).

### Free BoE roll

When a roll on a bind-on-equip item ends without valid rolls, a popup offers
to post it again **NOW** as a free roll for any character (**LATER**: select
it and press **FREE BOE ROLL**, or `/ledger free`). Only `/rnd 100` counts, the highest roll wins, the
award counts in nobody's tally and is exported with spec `boe`. A free roll
takes passes, but no spec changes.

## Awards

Everything is handed out in BEUTE, step **2 HAND OUT** (2.7.0). The state line
says what happened and what comes next ("Bob won (88). Next: hand it out."),
and that step's button is green: ROLL before a roll, **GIVE TO BOB** after a
win, **DISENCHANT** when nobody wanted the item.

- **GIVE TO name** (the name in the box: a won roll fills it, click a roll or
  ALL, or type one): while the item is still in the master-loot window,
  it hands the item to the recipient with `GiveMasterLoot`. The ledger
  records the award and marks it confirmed once the server's loot message
  arrives (an unconfirmed award shows `?`).
- Handouts from the default master-loot menu are recorded the same way.
- Without the item in a master-loot window, the same button records the
  award by hand (`MANUAL`).
- An item you give to yourself after a roll is the **winner's award at once**:
  you hand it over, and trades are not tracked (2.7.0).
- Each award stores the item ID, the creature ID of the corpse (the dead target,
  the dead corpse under the mouse, or the last creature death for chests), the
  winner's roll and the time. Reopening the same corpse never lists its items
  twice, also after hand-outs or another kill in between.

Every award is announced too: "[item] goes to Bob - main spec." when the
handout is confirmed or recorded by hand, with "(corrected)" when a
correction changes the recipient. An item you keep for another player's roll
names the winner and you: "[item] goes to Bob - main spec (Tester hands it
over)." It counts in Bob's tally right away.

## Item and token tally

The tally counts this raid's awards per player, separately for main spec and
off spec, from the ledger itself: CLEAR / NEW RAID starts everyone at 0.
Items and tokens (Weiheabzeichen) are two separate lists: item rolls rank by
the item tally, token rolls by the token tally. Removed awards and awards
without a roll do not count. Items already won in the loot list but not handed out yet count for
their winners too, so a second roll on the same corpse ranks correctly. The
win announcement names both counts ("1 MS / 0 OS items so far").
`/ledger tally` lists everyone (items, then tokens), and
`/ledger spec <#> ms|os|none` moves an award to the other spec or out of
the tally. A roll nobody takes is announced as "nobody wanted it" and the row
shows NOBODY.

### Token bundles

Identical tokens from one corpse are one row ("3x [Weiheabzeichen ...]") and
one roll: the best rolls win one copy each, announced together. A tie only
matters where it decides the last copy (the players above keep theirs, the
tied ones roll again). GIVE TO hands out one copy at a time and puts the
next winner in the box; copies nobody rolled for are announced as unwanted.

### Group loot

Items won with need/greed group loot are not recorded (2.7.0): only
master-loot hand-outs and the ledger's own actions make awards.

Hover a player (a roll, the ALL list, the tally) for their items this raid, and
an award or a loot row for the item tooltip (plus the award and the
recipient's tally).

## Editors and addon users (EINSTELLUNGEN)

The settings tab holds the editor list: the names that may start rolls,
award, park and correct. Type a name and ADD (or + TARGET); adding the first
one adds you too. Click a name to remove it. The list is saved for the
account and shared with the group, so everybody else's ledger only watches:
its buttons are greyed out, and it ignores awards from players
who are not editors. An empty list keeps the old rules. In chat:
`/ledger allow <name>`, `/ledger deny <name>`, `/ledger editors`.

Below the list, every raid member shows which addon they run: green with the
RaidLedger version, blue for RaidWishlist only, grey for no addon, gold for
editors. CHECK asks the group again.

Every control has a tooltip.

## Shared ledger

Every award and change (handout, confirmation, correction, removal,
spec) goes to the other RaidLedger users in the raid or party as addon
messages, with the award's roll log. Officers therefore see the same list,
and their corrections travel back. A ledger without awards of its own follows
the master looter's raid automatically, also after a NEW RAID; one with its
own awards keeps them and warns instead of merging another raid's ledger.
Only the ledger that recorded an award confirms and announces it when the
loot line arrives, so two ledgers in a raid never announce an item twice.

Every roll start (and tie-break) is shared too, so raid members running
[RaidWishlist](../RaidWishlist) get a roll prompt, or an automatic
roll, for items on their wishlist.

After a crash the master looter's client may have lost the ledger: on login (or
with `/ledger sync`) it asks the group, and the others send their own awards
plus the asker's, which restores it. Messages are only accepted from group
members, at most four are sent per second, and the newest revision of an award
wins.

## Roll log

Every award keeps what was rolled for it, and the log is saved with the ledger.
Select an award in VERGABEN and its rolls are listed under it: counted rolls in
winning order (with spec and the tally the ranking used), then each tie-break
round, the winner marked. Rolls that did not count stay listed in grey with the
reason: `re-roll`, a wrong range such as `1-1000`, or `not in tie-break`. Long
logs scroll with the mouse wheel. Awards recorded before version 1.1 have no
roll log.

## Loot that waits: LATER ROLL

Items do not have to be rolled right away:

- **LATER ROLL** in the compact master-loot popup asks "Who keeps it until the
  roll?" and hands the selected loot to the player you click (or to you),
  straight from the corpse, to **hold until it is rolled**. Drag its title to
  move it. Use it for a unique item you already wear and cannot loot yourself.
  The raid sees "[item] is
  parked with Bob until it is rolled." Items that need no roll at all (crafting
  materials, for example) are given straight away with **GIVE TO**.
- An item you take without a roll (also from the default master-loot menu) is
  open too.
- An award can go back to the loot list: select it in VERGABEN and press
  **BACK TO LOOT**. It becomes open, held by whoever has the item, and
  leaves VERGABEN.
- An open item is handled in BEUTE like any loot: select it and press
  **ROLL** (wishlist prompts and auto-rolls included; **GIVE TO** then writes
  the result onto the same award, the winner becomes the recipient at once
  and the chat says who holds it for pickup: "pick it up from Bob"), or hand it out right
  away with GIVE TO, DISENCHANT or GUILD BANK. With an empty name box it
  stays with its holder. An open roll nobody took no longer gets stuck.
- **Items in your bags** can be rolled too: **Alt+click** the item in your bags
  (or `/ledger roll <item link or ID>`). It is recorded as held by you (or its
  open award is used) and the roll starts at once; the winner is the recipient.
  Only the master looter or the raid lead (solo: you) can start these rolls.
- Open items are listed **only in the loot list** (2.7.0), under their own
  heading after the loot ("OPEN ITEMS (2)"), with their holder ("with Bob"),
  and the list heading counts them ("LOOT (5)  |  2 OPEN"), so none is
  forgotten after the loot window closed. VERGABEN lists them once their roll
  is won. DE and guild-bank items are handed out for good and are not open.
- Open items do not count in anyone's tally. Wishlist users see them, and the
  loot still on the corpse, under **OPEN ITEMS**.

## Disenchant and guild bank

Items nobody wants go to **DISENCHANT** or **GUILD BANK** (step 2). The award counts for nobody, is announced to the raid
("... will be disenchanted (Bob)."), and appears in the export as
`disenchanted` or `bank`. A wrong award goes BACK TO LOOT first.

The disenchanter is chosen **once per raid** (2.7.0) in the bar below the
loot list ("DISENCHANTER: Bob"): **CHOOSE** picks a raid member by hand
(`/ledger de <name>`), **ROLL IT** rolls it (`/ledger deroll`). The roll starts
only while no other roll runs; everyone may `/rnd 100` (other
ranges are ignored, ties roll again), and the winner is announced as the
raid's disenchanter and shared with the other ledgers. From then on
**DISENCHANT** gives the selected item straight to the disenchanter, whatever
the box holds. NEW RAID forgets the disenchanter. Without one, DISENCHANT
gives the item to the name in the box (the enchanter), or keeps it with you
when the box is empty. **GUILD BANK** always uses the box (the bank
character), or you.

## Members' wishlists

Raiders with RaidWishlist share their wishlist with your ledger. The
ledger asks for them after a login and when the raid grows. Each drop in the
loot list then shows **WL n**: how many wishlists name it. **WL 0** marks loot
nobody listed. Hover the drop to see who wants it (main spec first, then by
rank, with Enhanced), and a roller who listed the item shows `[WL #rank]` in
the roll list. The lists are kept only until you log out or `/reload`; the
ledger then asks again.

## Clearing old loot

**NEW RAID** (in VERGABEN) and `/ledger newraid` ask first, then empty the
award ledger, the tally corrections and the raid ID. Export before clearing.
`/ledger newraid confirm` clears without asking. **EMPTY** in the loot list
only drops the loot not handed out yet (`/ledger clear`).

## Corrections

Select an award in VERGABEN: type (or click a roll for) the recipient and press
**CHANGE RECIPIENT**; **COUNTS AS** moves it between the main-spec, off-spec
and no tally; **REMOVE** asks, then marks it removed (a removed award is
restored by setting a recipient again). In SPIELER, - / + correct a player's
items or tokens per spec on top of the awards (e.g. loot from before the
ledger ran): corrections count in the ranking, are shared with the group's
ledgers, reset with a new raid and never go into the website export. The slash
commands do the same:

| Command | Effect |
| --- | --- |
| `/ledger set <#> <name>` | Change the recipient of award `#` |
| `/ledger set <#>` | Change it to your current player target |
| `/ledger del <#>` | Remove award `#` (kept in the export as `deleted`) |
| `/ledger spec <#> ms\|os\|none` | Count award `#` for main spec, off spec or no tally |
| `/ledger pass <name>` | The player passes on the selected item (or the shown award) |
| `/ledger count <name> ms\|os\|none\|enh <0-50>` | Change how that player's roll counts |
| `/ledger free` | Post the selected item again as a free BoE roll |
| `/ledger deroll` | Roll the raid's disenchanter (`/rnd 100`); DE then gives items to them |
| `/ledger de <name>` | Make `<name>` the raid's disenchanter without a roll |
| `/ledger roll <link or ID>` | Roll an item from your bags (same as Alt+click on it) |
| `/ledger calendar` | Calendar raid event from the invite list, everyone invited |
| `/ledger minimap on` / `off` | Show / hide the minimap button |
| `/ledger tally` | Items per player this raid |
| `/ledger sync` | Ask the group's ledgers for this raid's awards |

A removed award can be restored by setting a recipient again.

## Website export (RS2)

**EXPORT** in VERGABEN (or `/ledger export`) shows the export: type the
website's raid ID (or `/ledger raid <id>`) and copy the selected text with
Ctrl+C. **NEW RAID** empties the ledger and forgets the raid ID; export first.

```text
RS2;LOOT;42;Raidleader;1760000000;1760003600
1;1760000300;36612;50415;Thorgar;given;87;ms;1-100
2;1760000301;36612;52027;Raidleader;held;113;ms;21-120
3;1760000400;-;50074;Aelira;manual;-;-;-
4;1760000420;36612;50415;Frostlin;deleted;64;os;1-99
```

Header: `RS2;LOOT;<raid ID>;<recorder>;<first award time>;<export time>`.
Lines, oldest first: `<award ID>;<time>;<creature ID or ->;<item ID or ->;<recipient>;<state>;<roll or ->;<ms|os|boe|->;<roll range or ->;<roll winner or ->`.
The roll is the recipient's (or, for a held item, the winner's); a range such
as `21-120` shows an enhanced main-spec roll (X = 20). The winner tells the
website who a held item goes to. The website (raid-website, ADR 070) previews
the export: enhanced rolls default to Enhanced, held items with a winner to
the winner; parked and deleted lines are shown but never imported.
Times are Unix seconds.

States: `given` (handed out by you; an item you kept for its winner is the
winner's), `held` (kept by the recorder without a roll: open),
`parked` (held by the recipient until it is rolled), `manual` (recorded or
corrected by hand), `deleted` (removed; delete it on the website if it was
imported before), `disenchanted` and `bank` (nobody's award; the recipient
holds the item). Open `held` and `parked` lines wait for their roll.

Changes from RaidSync's `RS1|LOOT`:

- `;` replaces `|`, which starts escape sequences such as `|T` and `|c` in a
  WoW edit box.
- Removed awards stay in the export as `deleted`, so the website can remove
  lines it imported earlier.
- The header carries the export time; each line carries the roll, its spec
  and its range.
- Award IDs never change, even across `newraid`.
