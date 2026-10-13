# Skull EPGP Player (WoW 1.12)

Light addon for **raiders** of a guild using the EPGP loot system. It works together with
**[SkullEPGP_Officer](https://github.com/Duciel/SkullEPGP_Officer)**, used by the master looter / raid leader.
Nothing to configure: install it, and a small window pops up each time an item is announced.

<!-- Screenshots: put the PNG files in docs/images/ and uncomment the lines below
![Bidding window](docs/images/bidding-window.png)
![Winner announced](docs/images/winner.png)
-->

## Quick start
1. Copy the folder into `Interface/AddOns/` and `/reload` (or restart the game).
2. Join the raid: the addon silently asks the officer for your priority.
3. When an item is announced, pick **Roll**, **MIN**, **NEED** or **MAX** in the window.
4. Watch the list of bidders and the winner in the same window.

## What it does
When the officer announces an item, a window opens with:
- the **item** (hover for its tooltip) and a **countdown**,
- **your priority** (EP / (GP + base GP)),
- the **list of players who already bid or rolled**, sorted like the final ranking (MAX > NEED > MIN > roll, then priority), with their priority and roll. Your own line is highlighted,
- **four buttons**: **Roll** (plain /roll 1-100), **MIN**, **NEED**, **MAX** (the GP price is shown on each button).

Rules (same as the officer addon): one choice per announcement; the only change allowed is **NEED -> MAX**. Buttons that are not allowed any more are greyed out. MIN / NEED / MAX post the word in the raid chat, Roll does a /roll; the officer confirms your choice (the list updates) a moment later.

When the officer awards the item, the winner is shown in the window (and "You won" in your chat). The window closes by itself 20 seconds after the end.

## Installation
Copy the `SkullEPGP_Player` folder into `Interface/AddOns/`. Nothing to configure.
Your priority and the prices are sent by the officer (`/epgp publish`, or automatically when you join the group: the addon asks for them). Only messages from the raid leader / assistants / master looter are accepted. If you have no priority yet (officer import done before you connected), the addon silently asks again every 30 s while you are in a group; if you are not in the EPGP list, the window says so and stops asking.

## Commands
`/epgpp` show / hide the window - `/epgpp auto on|off` open it automatically (default on) - `/epgpp reset` reset its position - `/epgpp req` ask the officer for your priority - `/epgpp test` show a fake announcement to check the layout (nothing is sent to the raid).

The window is movable (drag it).
