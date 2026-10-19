# RaidWishlist

The raid member's side of [RaidLedger](../RaidLedger) for WoW 3.3.5a
(Interface 30300). Members import their wishlist from the guild website, get a
one-click roll (or an automatic roll) when the raid lead rolls out a wishlisted
item, and see who got what this raid. The raid lead uses RaidLedger; the
two addons talk over addon messages (prefix `FLLedger`). Live acceptance plans:
`../RaidWishlist-acceptance.json` (prompt) and
`../RaidWishlist-auto-acceptance.json` (auto-roll).

Open it with `/wish` (or `/raidwish`), or with the minimap button (drag it to
move it around the minimap; `/wish minimap off` hides it). The window also
opens by itself when the raid lead starts a roll on an item from your list.

The window looks like RaidLedger's, in its own color: the color button in the
header (or `/wish color`) opens the color picker, right-click (or
`/wish color reset`) goes back to green. The color is shared by all your
characters; very dark picks are brightened so the text stays readable.

The addon speaks German in German clients (deDE) and English everywhere else
(`Locales.lua`).

## The window

Three tabs (2.0.0, after the raid feedback "you cannot scroll down the
loot"), each a full-height list that scrolls with the mouse wheel; the corner
shows which entries you see ("18-30 / 30 (mouse wheel)"), the tabs count their
entries, and the window remembers the last tab:

| Tab | What it lists |
| --- | --- |
| **WUNSCHLISTE** | Your wishlist in rank order: item, note, roll range (or `ERHALTEN`) |
| **OFFEN** | Loot still waiting to be rolled, where it is and its status |
| **DIESER RAID** | Who got what this raid (item, recipient, spec) and your items so far |

A roll on a wishlisted item opens the window on **OFFEN**. Every header button
and tab has a tooltip.

## Importing the wishlist

On the guild website, copy your wishlist export, click **IMPORT** (or
`/wish import`), paste it (Ctrl+V) and press **IMPORT WISHLIST**. An import
replaces the previous list. An export made for another character is refused,
so an alt never rolls on a main's list.

The website exports one character's list:

```text
WL2;<character>;<export time, Unix seconds>;<EP balance>
<item ID>;<ms|os>;<enhanced 0/1>;<rank>;<note>
```

```text
WL2;Thorgar;1792130000;70
50415;ms;1;1;BiS weapon
52027;ms;0;2;
50074;os;0;3;for my off spec
```

- `ms` rolls main spec (`/rnd 100`), `os` off spec (`/rnd 99`).
- `enhanced` 1 rolls main spec 1+X..100+X with X = min(EP balance, 50), the
  website's rule: with 70 EP that is 51-150, with 20 EP 21-120. Off spec
  cannot be enhanced. After an enhanced win the addon lowers its copy of the
  balance by X until the next export; the website deducts X from the raid's
  loot export.
- On the website, set spec and Enhanced per item on the character page and
  press "Für Addon exportieren".
- `rank` orders the list (1 first); the note is shown in the roll prompt.
- Lines that break these rules are skipped and counted in the import message.

## Rolling

When the raid lead's RaidLedger starts a roll on an item from your list,
a prompt appears at the top of the screen: **ROLL MS 21-120** (your wishlist's
spec and EP) or **SKIP**. It closes when the roll ends.

**AUTO-ROLL** (button, or `/wish auto on|off`) rolls for you instead, about a
second after the roll starts, for example while you are away from the keyboard.

Either way the addon rolls at most once per roll (the ledger only counts your
first roll), joins a tie-break only if you are one of the tied players, and
does not roll on items you already received this raid.

## Open items

**OFFEN** (open items) lists loot that is still waiting to be rolled: items on the
corpse, items the master looter keeps for a later roll, and items parked with
another raider (e.g. unique items), with where they are and their status:
`OPEN`, `ROLLING NOW` or `WON: <name>`. Items on your wishlist are marked
`WISHLIST`. An item parked with you is not yours yet: you still get the prompt
or auto-roll when it is rolled.

## This raid

**DIESER RAID** shows every award the raid lead's ledger shares: item,
recipient and spec, with removed awards greyed out. Your items and items on
your wishlist are highlighted; hover a row for the item tooltip. The header
shows your own tally this raid, items and tokens as separate lists (main spec
and off spec each), which decides close rolls. An item the master looter holds for you
counts as yours, and its wishlist entry shows **RECEIVED**.

After a login or `/reload` the addon asks the group for this raid's awards
(`/wish sync` asks again). A newer raid replaces the list automatically.
Disenchanted and guild-bank items show **DE** and **BANK**; they count for
nobody.

## Sharing your wishlist with the raid lead

Your wishlist (items, main or off spec, Enhanced, order) goes to the raid
lead's RaidLedger: after an import, after a login, and whenever a ledger
asks. The raid lead then sees how many raiders want a drop and who. Notes stay
private. `/wish share off` stops sharing; `/wish share on` starts it again.

## Commands

| Command | Effect |
| --- | --- |
| `/wish` | Show or hide the window |
| `/wish import` | Paste a wishlist export |
| `/wish auto on` / `off` | Roll automatically / show the roll prompt |
| `/wish sync` | Ask the raid lead's ledger for this raid's awards |
| `/wish share on` / `off` | Share your wishlist with the raid lead's ledger (on by default) |
| `/wish minimap on` / `off` | Show / hide the minimap button |
| `/wish color` / `color reset` | Pick the window color / back to the default |
