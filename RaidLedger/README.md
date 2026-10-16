# RaidLedger

The raid lead's addon for WoW 3.3.5a (Interface 30300): raid setup (invites,
groups, attendance), loot rolls, awards and the website exports. It replaces
RaidSync, whose features it took over. The guild installs it from
[robinschweitz/wow-addons](https://github.com/robinschweitz/wow-addons); this
folder in [addon-forge](https://github.com/robinschweitz/addon-forge) is the
source, with offline specs in `tests/` and live plans beside the folder
(`RaidLedger-*.json`).

The addon speaks German in German clients (deDE): window, raid announcements,
chat and help. Every other client gets English. Texts live in `Locales.lua`,
keyed by their English wording.

## Raid setup: invites, groups, attendance

**RAID** (or `/ledger setup`) replaces the panes with the raid setup
(`Raid.lua`):

1. Paste the website's invite list (raid page, Aufstellung, „Einladungen für
   Addon“) and click **READ**. The list shows each character's role and status;
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

```text
RS2;INV;<raid ID>;<raid name>;<size>
<name>;<TANK|HEAL|DD>;<class>;<bench 0/1>

RS2;ROSTER;<raid ID>;<recorder>;<export time>
<name>;<class token or ->;<first seen>
```

Both are `;`-separated like the loot export. RaidSync's `RS1|INV` lists are not
read: export the list again on the website.

## Rolls

Opening a loot window lists every item at or above the group's loot threshold.
Select an item and type `/ledger start` to start a 30-second roll. The raid's
rules:

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
"[item] won by Bob (87) - main spec 21-120, 0 items so far."

## Awards

- **GIVE + RECORD**: while the item is still in the master-loot window,
  the award button hands it to the recipient with `GiveMasterLoot`. The ledger
  records the award and marks it confirmed once the server's loot message
  arrives (an unconfirmed award shows `?`).
- Handouts from the default master-loot menu are recorded the same way.
- **RECORD AWARD**: without the item in a master-loot window, the award is
  recorded by hand (`MANUAL`).
- Items you give to yourself after a roll are `HELD BY YOU` for the winner.
  When you trade one away and the trade completes, the copy the partner won
  (else the oldest held copy) moves to that player. Trades between other
  players are not visible to the addon.
- Each award stores the item ID, the creature ID of the corpse (the dead target,
  or the last creature death for chests), the winner's roll and the time.
  Reopening the same corpse does not list its items twice.

Every award is announced too: "[item] goes to Bob - main spec." when the
handout is confirmed or recorded by hand, with "(traded)" or "(corrected)"
when a trade or a correction changes the recipient.

## Item and token tally

The tally counts this raid's awards per player, separately for main spec and
off spec, from the ledger itself: CLEAR / NEW RAID starts everyone at 0.
Items and tokens (Weiheabzeichen) are two separate lists: item rolls rank by
the item tally, token rolls by the token tally. Removed awards and awards
without a roll do not count; an item you hold for the winner counts for the
winner. `/ledger tally` lists everyone (items, then tokens), and
`/ledger spec <#> ms|os|none` moves an award to the other spec or out of
the tally.

Hover a group member for their items this raid, hover an award or a loot row
for the item tooltip (plus the award and the recipient's tally), and hover a
roll-log line for that roller's items.

## Shared ledger

Every award and change (handout, confirmation, trade, correction, removal,
spec) goes to the other RaidLedger users in the raid or party as addon
messages, with the award's roll log. Officers therefore see the same list,
and their corrections travel back. A ledger without awards of its own follows
the master looter's raid automatically, also after a NEW RAID; one with its
own awards keeps them and warns instead of merging another raid's ledger.

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
Click an award in the list (scroll it with the mouse wheel) and the left pane
shows its rolls instead of the loot items. It lists counted rolls in winning
order (with spec and the tally the ranking used), then each tie-break round,
and marks the winner. Rolls that did not count stay
listed in grey with the reason: `re-roll`, a wrong range such as `1-1000`, or
`not in tie-break`. Long logs scroll with the mouse wheel. Click the award
again, or open new loot, to get the loot items back. Awards recorded before
version 1.1 have no roll log.

## Loot that waits: PARK and roll later

Items do not have to be rolled right away:

- **PARK** (next to the award button) hands the selected loot to the player in
  the recipient box, or to you when it is empty, to **hold until it is rolled**.
  Use it for unique items you cannot hold twice. The award shows `OPEN` and
  the raid sees "[item] is parked with Bob until it is rolled."
- An item you take without a roll (also from the default master-loot menu) is
  open too, and trading it away parks it with the trade partner.
- An award recorded otherwise can be parked afterwards: click it, put the
  holder in the recipient box, press **PARK**.
- To roll an open item later, click its award: the button reads **ROLL**. The
  item joins the roll list and the roll runs as usual (wishlist prompts and
  auto-rolls included). **RECORD AWARD** then writes the result onto the same
  award: held by you, it waits for your trade to the winner; held by another
  raider, the winner becomes the recipient ("Bob hands it over"), since trades
  between other players are not visible.
- Open items do not count in anyone's tally. Wishlist users see them, and the
  loot still on the corpse, under **OPEN ITEMS**.

## Disenchant and guild bank

Items nobody wants go to **DE** (disenchant) or **BANK** (guild bank), the
small buttons next to "click a group member". The item goes to the name in the
recipient box (the enchanter or the bank character), or stays with you when
the box is empty. The award counts for nobody, is announced to the raid
("... will be disenchanted (Bob)."), and appears in the export as
`disenchanted` or `bank`. On a selected award the buttons change it the same
way.

## Members' wishlists

Raiders with RaidWishlist share their wishlist with your ledger. The
ledger asks for them after a login and when the raid grows. Each drop in the
loot list then shows **WL n**: how many wishlists name it. **WL 0** marks loot
nobody listed. Hover the drop to see who wants it (main spec first, then by
rank, with Enhanced), and a roller who listed the item shows `[WL #rank]` in
the roll list. The lists are kept only until you log out or `/reload`; the
ledger then asks again.

## Clearing old loot

**CLEAR** (on the award list), **NEW RAID** (in the export) and
`/ledger newraid` ask first, then empty the award ledger and forget the raid
ID. Export before clearing. `/ledger newraid confirm` clears without asking.

## Corrections

Click an award in the list, pick or type the recipient and press
**CHANGE RECIPIENT**. Or use the slash commands:

| Command | Effect |
| --- | --- |
| `/ledger set <#> <name>` | Change the recipient of award `#` |
| `/ledger set <#>` | Change it to your current player target |
| `/ledger del <#>` | Remove award `#` (kept in the export as `deleted`) |
| `/ledger spec <#> ms\|os\|none` | Count award `#` for main spec, off spec or no tally |
| `/ledger tally` | Items per player this raid |
| `/ledger sync` | Ask the group's ledgers for this raid's awards |

A removed award can be restored by setting a recipient again.

## Website export (RS2)

`/ledger raid <id>` sets the website's raid ID, and **EXPORT** (or
`/ledger export`) shows the selected text to copy with Ctrl+C.
`/ledger newraid` (or CLEAR) empties the ledger and forgets the raid ID; export first.

```text
RS2;LOOT;42;Raidleader;1760000000;1760003600
1;1760000300;36612;50415;Thorgar;given;87;ms;1-100
2;1760000301;36612;52027;Raidleader;held;113;ms;21-120
3;1760000400;-;50074;Aelira;manual;-;-;-
4;1760000420;36612;50415;Frostlin;deleted;64;os;1-99
```

Header: `RS2;LOOT;<raid ID>;<recorder>;<first award time>;<export time>`.
Lines, oldest first: `<award ID>;<time>;<creature ID or ->;<item ID or ->;<recipient>;<state>;<roll or ->;<ms|os|->;<roll range or ->;<roll winner or ->`.
The roll is the recipient's (or, for a held item, the winner's); a range such
as `21-120` shows an enhanced main-spec roll (X = 20). The winner tells the
website who a held item goes to. The website (raid-website, ADR 070) previews
the export: enhanced rolls default to Enhanced, held items with a winner to
the winner; parked and deleted lines are shown but never imported.
Times are Unix seconds.

States: `given` (handed out or traded by you), `held` (with the recorder),
`parked` (held by the recipient until it is rolled), `manual` (recorded or
corrected by hand), `deleted` (removed; delete it on the website if it was
imported before), `disenchanted` and `bank` (nobody's award; the recipient
holds the item). A `held` line without a roll is still open.

Changes from RaidSync's `RS1|LOOT`:

- `;` replaces `|`, which starts escape sequences such as `|T` and `|c` in a
  WoW edit box.
- Removed awards stay in the export as `deleted`, so the website can remove
  lines it imported earlier.
- The header carries the export time; each line carries the roll, its spec
  and its range.
- Award IDs never change, even across `newraid`.
