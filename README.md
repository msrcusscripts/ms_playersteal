# ms_playersteal

Player-vs-player robbery for ESX, QBCore and Qbox servers built on the Ox
ecosystem, with full wasabi_ambulance death integration.

**Author:** Marcus Scripts

## Features

- Built-in hands up toggle (default **X**, rebindable), switchable off if another script handles it
- Optional weapon requirement: only players holding a firearm can rob, verified server side
- Rob living players who have their hands up, and dead / downed players at any time
- Death and incapacitation are read from **wasabi_ambulance** (export + state bags), not from generic framework death checks — players downed or killed under Wasabi are robbable immediately
- **Multi-framework**: ESX (es_extended), QBCore (qb-core) and Qbox (qbx_core) are auto-detected at startup, no configuration needed
- ox_target interaction, ox_lib progress bar / notifications / callbacks
- Looting through **ox_inventory**: on success the victim's inventory opens for the robber and every item movement is processed server-side by ox_inventory
- One robber per victim at a time, with per-robber and per-victim cooldowns that survive reconnects (ESX identifier / QB citizenid based)
- Automatic cancellation when the robber moves too far, dies, gets ragdolled / knocked around, when the victim leaves or (optionally) lowers their hands
- Every step is validated server-side: start request, live supervision while the progress runs, and a full re-validation (timing, distance, routing bucket, death / hands-up state) at the moment of completion
- Zero idle overhead: no permanent loops, supervision threads only exist while a robbery is active
- Optional job whitelist / blacklist for who is allowed to rob

## Dependencies

- One framework: [es_extended](https://github.com/esx-framework/esx_core), [qb-core](https://github.com/qbcore-framework/qb-core) or [qbx_core](https://github.com/Qbox-project/qbx_core)
- [ox_lib](https://github.com/CommunityOx/ox_lib)
- [ox_target](https://github.com/CommunityOx/ox_target)
- [ox_inventory](https://github.com/CommunityOx/ox_inventory)
- wasabi_ambulance (v1 / legacy; v2 also works through its v1-compatible exports)

## Installation

1. After purchase, download the resource from your Cfx.re Portal (Granted
   Assets) and extract it as `resources/ms_playersteal`.
2. Make sure your server runs artifacts 4960 or newer (required by Asset
   Escrow) and uses a license key generated on the same Cfx.re account that
   owns the purchase.
3. Start it **after** your framework and its dependencies:

```cfg
ensure es_extended        # or qb-core / qbx_core
ensure ox_lib
ensure ox_target
ensure ox_inventory
ensure wasabi_ambulance
ensure ms_playersteal
```

4. Adjust `config.lua` to taste and put your Discord webhook URLs in
   `webhooks.lua`. No other setup is required. The console prints the
   detected framework on startup.

### Editable files (Asset Escrow)

`config.lua`, `webhooks.lua` and this README are unencrypted and safe to
edit. Every other file is protected by Cfx Asset Escrow - do not modify,
rename or remove them, and never touch the `.fxap` file that ships with
the download.

## Framework support

All framework-specific code lives in `bridge.lua`, which detects the running
framework at startup (`qbx_core` is checked before `qb-core`, so Qbox servers
running a qb compatibility bridge still use the native Qbox exports) and
wraps just three things:

- `Bridge.GetPlayer(id)` — is the player fully loaded
- `Bridge.GetJob(id)` — job name for the whitelist / blacklist
- `Bridge.GetIdentifier(id)` — persistent identifier for cooldowns
  (ESX identifier, QB / Qbox citizenid)

Support for additional frameworks can be added on request. Remember to
adjust `Config.JobBlacklist` to your server's actual job names.

## How it works

1. The robber targets a nearby player with ox_target. The option only shows on
   players who look robbable (hands up, or dead / downed according to the
   wasabi_ambulance state bags). This client check is cosmetic only.
2. The client requests permission through an ox_lib callback. The server
   verifies: both players are loaded, neither is already involved in a
   robbery, the robber is alive and job-allowed, no cooldown applies, both
   are in the same routing bucket and within `Config.MaxRobberyDistance`
   (server-side coordinates), and the target is genuinely robbable.
3. While the progress bar runs, a server-side supervision thread re-checks
   distance, connection, the robber's death status and (optionally) the
   victim's hands every 500 ms, cancelling the progress bar remotely if
   anything is off.
4. On completion the server validates that the full duration actually elapsed
   (instant-finish exploit protection) and re-runs every state check, then
   opens the victim's inventory for the robber via
   `exports.ox_inventory:forceOpenInventory`. Item transfers are handled by
   ox_inventory itself, entirely on the server.

## wasabi_ambulance integration

Death status is resolved server-side in `getDeathStatus()` (`server.lua`):

- Primary: `exports.wasabi_ambulance:isPlayerDead(serverId)`.
- Fallback: the player state bags wasabi_ambulance syncs for everyone —
  `state.dead` is `false`/`nil` while alive, `'dead'` when dead and
  `'laststand'` while downed (older builds expose `isDead` / `laststand`).

`Config.TreatLastStandAsDead` controls whether a downed (last stand) player
counts as dead for robbery purposes. The client uses the same state bags only
to decide when to *display* the target option; it never decides the outcome.

Support for other ambulance / death systems can be added on request.

## Hands up

Press **X** or type `/handsup` to raise and lower your hands; players can
rebind it under Settings > Key Bindings > FiveM. While posed you can't fire
or aim, and the pose drops on death or when entering a vehicle. Up and down
use the same blend speed (`Config.HandsUpBlendSpeed`).

Already running an emote menu that handles hands up? Set
`Config.EnableHandsUpKeybind = false` and add its animation dict/clip to
`Config.HandsUpAnims` - detection is animation based, so any resource works.

Other scripts can read or drive the pose with
`exports.ms_playersteal:IsHandsUp()` and
`exports.ms_playersteal:SetHandsUp(true)`.

A living victim's hands up state is verified **on the victim's own client**
(`lib.callback` from the server), so the robber's client can never spoof it.

## Weapon requirement

With `Config.RequireWeapon = true` the robber must be holding a firearm.
This is checked server side at the start of the robbery, every 500 ms while
it runs, and again on completion - a client can't fake it. Melee weapons and
throwables don't count (see `Config.NonFirearms`), and `Config.AllowedWeapons`
can narrow it to specific weapons. Set `Config.RequireWeapon = false` to
disable it entirely.

## Configuration overview

| Option | Description |
| --- | --- |
| `InteractionDistance` | Range of the ox_target option |
| `MaxRobberyDistance` | Hard server-side range during the whole robbery |
| `AllowRobbingDead` | Whether dead / downed players can be robbed |
| `TreatLastStandAsDead` | Whether Wasabi's last stand counts as dead |
| `RequireHandsUp` | Whether living players must have their hands up |
| `CancelIfHandsDown` | Cancel mid-robbery if the victim lowers their hands |
| `RobberyDuration` / `ProgressLabel` / `ProgressStyle` | Progress bar settings |
| `RobberCooldown` / `VictimCooldown` / `FailedCooldown` | Cooldowns in seconds (0 disables each) |
| `EnableHandsUpKeybind` / `HandsUpKey` / `HandsUpCommand` / `HandsUpBlendSpeed` | Built-in hands up toggle |
| `RequireWeapon` / `AllowedWeapons` / `NonFirearms` | Weapon requirement |
| `UseJobWhitelist` / `JobWhitelist` / `JobBlacklist` | Who may rob |
| `HandsUpAnims` / `DownedAnims` | Animation lists for detection / display |
| `Notifications` | Every message, passed straight to `lib.notify`; each entry has an `enabled` flag |
| `EnableNotifications` | Master switch for all notifications |
| `Debug` | Verbose validation logging (suspicious activity is always logged) |
| `EnableDiscordLogs` + `DiscordBotName` / `DiscordAvatar` / colors | Discord logging; webhook URLs live in `webhooks.lua` |

## File structure

```
ms_playersteal/
├── fxmanifest.lua
├── config.lua          (editable)
├── README.md           (editable)
├── client/
│   ├── handsup.lua     hands up toggle
│   └── main.lua        targeting and progress
└── server/
    ├── bridge.lua      framework detection (ESX / QBCore / Qbox)
    ├── webhooks.lua    webhook URLs (editable)
    ├── logs.lua        Discord embeds
    └── main.lua        validation, locks, cooldowns, inventory
```

## Discord logging

Set `Config.EnableDiscordLogs = true` and paste your webhook URL(s) into
`server/webhooks.lua`. Upload the included `steal_logs.png` somewhere public
and put its direct URL in `Config.DiscordAvatar` - it becomes the webhook
avatar, the embed author icon and the embed thumbnail. That file is server-only on purpose — never put webhook URLs
in shared config, because every client downloads it and a leaked URL lets
anyone spam or delete your log channel.

Each completed robbery posts a red "Steal Logs" embed with both players and
their identifiers, the location, the weapon used, how long the steal took, whether the victim was dead/downed or alive with hands up,
every item taken with quantity, the cash / black money taken, and an
estimated value when item prices are defined in ox_inventory. What was taken
is worked out server-side by snapshotting the victim's pockets at the moment
the robbery completes and diffing when the loot inventory closes (or the
robber disconnects). Bank money never appears because pocket robbery can't
touch it.

Suspicious activity (the `[SECURITY]` console entries) is posted to
`Config.DiscordSuspiciousWebhook`, or to the main webhook when that one is
empty. Every request is sent by the server; clients can neither trigger nor
see them.

Verify delivery any time by running `ms_webhook_test` in the server
console: it sends a test embed to each configured webhook, and any Discord
rejection is printed to the console with the exact reason.

## Security model

- The robber's client only ever sends two things: a start request and a
  finished/cancelled flag. Neither is trusted: the server keeps its own start
  timestamp, pairing table and state, and re-validates everything before any
  inventory access.
- Hands-up checks run on the victim's client, death checks on the server via
  wasabi_ambulance, distance checks on server-side coordinates, and inventory
  access + transfers on the server through ox_inventory.
- Spoofed or repeated `finish` events for players with no registered robbery
  are ignored, start/finish events are rate limited per player, and
  impossible timings, malformed target ids and sustained event spam are
  logged to the console as `[SECURITY]` entries.
- A robber must be alive, unrestrained (`isCuffed` / `cuffed` / `handcuffed`
  state bags) and on foot; this is enforced at start, during supervision and
  again on completion.
- While a robber is looting, the victim is locked against overlapping
  robberies until that inventory closes (with an expiry fallback), so two
  robbers can never have the same inventory open even with cooldowns
  disabled.

## Troubleshooting

- **`no supported framework found` in the console** — start es_extended,
  qbx_core or qb-core before this resource.
- **The option never appears on a player with hands up** — your hands-up
  resource probably uses a different animation; add its dict/clip to
  `Config.HandsUpAnims`.
- **Downed players can't be robbed** — confirm wasabi_ambulance is started
  before this resource and that `Config.AllowRobbingDead` (and, for last
  stand, `Config.TreatLastStandAsDead`) is enabled.
- **Discord logs don't arrive** - run `ms_webhook_test` in the server
  console and read the printed result. Common causes: `Config.EnableDiscordLogs`
  is false, the URL in `webhooks.lua` is missing/invalid, or the webhook was
  deleted in Discord (status 404).
- **Inventory doesn't open on success** — make sure you're on a current
  ox_inventory build (the `forceOpenInventory` server export is required).
