# HANDOFF.md — RLS Career Carjacking

## Status

**Current known-good baseline: v0.2.14**

This handoff supersedes older notes describing v0.2.13 retrieval and taxi-replenishment regressions.

At v0.2.14, the user reports those issues are fixed. Treat the relevant systems as working and regression-sensitive, not open tasks.

Published resource:
```text
https://www.beamng.com/resources/rls-carjacking-mechanic.39197/
```

BeamNG resource/tag ID:
```text
M3Z1BLS58
```

Main implementation:
```text
lua/ge/extensions/career/modules/carjacking.lua
```

Expected package:
```text
README.md
lua/ge/extensions/career/modules/carjacking.lua
mod_info/M3Z1BLS58/icon.jpg
mod_info/M3Z1BLS58/info.json
```

---

# 1. Current feature state

## Live traffic carjacking

While walking, the normal **Enter/Exit Vehicle** action can steal eligible AI traffic and convert the same live car into career inventory.

Critical compatibility priority:
```text
normal BeamNG/RLS enterable vehicle
        -> original Enter/Exit wins

no normal enterable target
        -> carjacking fallback may target eligible AI traffic
```

This is the working taxi fix:
- ambient traffic taxi can be stolen;
- a taxi hailed by the player and waiting for pickup is entered normally for the ride.

Do not add taxi-specific state/config/ID detection unless the current behavior is actually reproduced as broken.

---

## Civilian traffic restoration

v0.2.14 deliberately leaves BeamNG/RLS in charge of traffic.

When a stolen civilian traffic car later leaves the active world, the mod restores exactly the traffic entry removed by that theft:
- same model;
- same configuration;
- directly returned to BeamNG's normal traffic pool.

This applies to ambient taxis too.

There is **no separate taxi replenishment subsystem** and no traffic-variety manager.

Desired model:
```text
steal one native traffic entry
    -> player owns stolen object
    -> stolen object later leaves active world
    -> restore one equivalent traffic entry
    -> hand control back to BeamNG
```

Do not:
- expand the traffic pool;
- maintain a reserve;
- rotate a custom catalogue;
- periodically reshuffle traffic;
- repeatedly call top-level traffic spawn;
- alter configured traffic density.

---

## Sale-vehicle hotwire

While inspecting a vehicle for sale and outside an active timed test drive, the action wheel exposes **Hotwire**.

Successful hotwire:
- uses the same live vehicle;
- removes it from the sale listing;
- adds it to career inventory;
- preserves configuration/damage/paint/plate;
- releases/unfreezes it;
- starts it if needed;
- applies stolen-vehicle police/identity/insurance/value rules.

Dealer organization reputation penalty defaults to:
```text
-500
```

Configuration stores this as:
```lua
dealerHotwireReputationPenalty = 500
```
meaning 500 points are deducted.

Private marketplace vehicles can be hotwired by default and do not use the same dealer-organization penalty path.

---

## Police theft / pursuit

Police vehicles are stealable.

Preserve:
- stolen police vehicle loses responder/registry role immediately;
- stolen police car cannot arrest the player;
- police-car theft triggers maximum heat;
- arrest grace during handoff;
- already-busy cops are not indiscriminately retargeted;
- existing marked RLS responders are preferred;
- at most one marked fallback responder may be created if necessary;
- no generic police-group spam;
- stolen police vehicle cannot use **Change Vehicle Identity**.

Pursuit lifecycle should remain native to RLS. Avoid traffic operations that reset pursuit state.

---

## Change Vehicle Identity

BeamNG/RLS does not expose a native VIN field used by this mod, so **Change Vehicle Identity** is a gameplay abstraction for changing identifying markings/registration identity.

For eligible stolen civilian vehicles, successful identity change:
- generates a new plate;
- randomizes paint from native available paints;
- prevents future stolen-vehicle identification;
- restores normal RLS insurance eligibility.

Police vehicles do not show the option.

Defaults:
```lua
identityChangeDurationSeconds = 0
identityChangeCostMultiplier = 0.35
```

Duration `0` is instant.

---

## Insurance

Before identity change, a stolen civilian vehicle is kept out of RLS's normal Add Coverage flow.

Important implementation concept:
- RLS uses `insuranceId == -1` for ordinary uninsured vehicles;
- the mod uses a distinct internal negative state while identity-locked;
- after identity change the vehicle can return to ordinary uninsured state and receive normal coverage.

Do not replace this with broad insurance wrappers or direct insurance JSON editing.

---

## Economy

Current defaults:
```lua
stolenValueMultiplier = 0.35
stripPartsMultiplier = 0.05
identityChangeCostMultiplier = 0.35
dealerHotwireReputationPenalty = 500
```

Never install a global value-calculator wrapper.

---

## Clean garage retrieval

This was a major historical debugging area and is considered fixed in v0.2.14.

When a stolen vehicle is retrieved, the mod detects the RLS retrieval handoff and repeatedly enforces a safe controller state for that short handoff window:
```text
AI disabled
stale throttle/brake/clutch cleared
neutral
parking brake on
starter off
ignition off
stationary
```

Physical damage remains intact.

This is a known-good behavior. Do not replace it with a destructive vehicle reset, broad persistence changes, or a new retrieval architecture without first reproducing a regression and diffing against v0.2.14.

---

# 2. User-facing configuration

Current v0.2.14 defaults:

| Setting | Default |
| --- | ---: |
| `interactDistance` | `3.25` |
| `maxTargetSpeedMps` | `12.0` |
| `immediateAlertRadius` | `220.0` |
| `immediateAlertLevel` | `2` |
| `policeCarjackLevel` | `3` |
| `identityFlagDelaySeconds` | `120` |
| `identityScanRadius` | `55.0` |
| `identityScanInterval` | `0.40` |
| `identityPursuitLevel` | `2` |
| `stolenValueMultiplier` | `0.35` |
| `stripPartsMultiplier` | `0.05` |
| `allowPoliceVehicles` | `true` |
| `allowSaleVehicleHotwire` | `true` |
| `allowPrivateSellerHotwire` | `true` |
| `dealerHotwireReputationPenalty` | `500` |
| `identityChangeCostMultiplier` | `0.35` |
| `identityChangeDurationSeconds` | `0` |
| `carjackArrestGraceSeconds` | `4.0` |
| `desiredPoliceResponders` | `1` |

If current source differs, inspect why before changing it.

---

# 3. Hard-won compatibility rules

## A. Normal Enter/Exit beats carjacking

This is the taxi fix.

Do not reintroduce:
- `cabState` gating;
- taxi config blacklists;
- active-cab ID probing;
- taxi spawn monkey-patching.

Those historical approaches were less reliable than respecting BeamNG's normal enterable target.

## B. Traffic belongs to BeamNG/RLS

The mod may repair the exact hole it creates, but should not become a traffic manager.

## C. Police logic is separate

Police responder safety exists because stealing a police unit can remove a pursuit responder. Do not generalize police spawning logic into civilian/taxi population management.

## D. Retrieval must preserve damage

"Reset the driving state" does not mean "repair the car." Safe controller state and physical damage persistence are both required.

## E. Prefer local hooks

Avoid persistent global monkey-patches where a scoped/local integration is possible.

---

# 4. Historical failures to remember

These are **not current bugs**; they explain forbidden approaches.

### Economy
Global sell-value wrapping caused unrelated vehicles to have incorrect/$0 values.

### Insurance
Broad insurance wrappers and direct insurance JSON editing caused failures.

### GUI
Persistent `guihooks.trigger` wrapping caused fatal menu errors.

### Police
A stolen police vehicle once remained registered as police and could arrest the player.

Generic fallback police spawning created too many/unmarked units.

### Traffic
Global/top-level traffic spawning around carjacking disturbed pursuit state.

Custom traffic variety reserves/catalogues became unnecessarily invasive.

### Taxi compatibility
Multiple taxi-specific heuristics failed historically:
- cab state;
- config name;
- exact ID recovery;
- spawn interception.

The working solution is native enterable-target priority.

### Retrieval
Several speculative reset approaches failed in older builds. v0.2.14 is the known-good reference; diff its exact lifecycle before revisiting this area.

### Plate system
Old physical-license-plate-removal detection was intentionally replaced by **Change Vehicle Identity**.

### Removed feature
**Abandon** is intentionally removed.

---

# 5. Recommended Codex repository setup

```text
RLS-Carjacking/
├── AGENTS.md
├── HANDOFF.md
├── README.md
├── lua/
│   └── ge/
│       └── extensions/
│           └── career/
│               └── modules/
│                   └── carjacking.lua
├── mod_info/
│   └── M3Z1BLS58/
│       ├── icon.jpg
│       └── info.json
└── reference/
    ├── rls-career-overhaul/   # optional
    ├── beamng-lua/            # optional matching source reference
    └── historical/            # old ZIPs, excluded from release
```

If using git, commit/tag the exact known-good v0.2.14 baseline before feature work.

Suggested commit:
```text
baseline: RLS Career Carjacking v0.2.14 known-good
```

---

# 6. First Codex session

Do not begin with a rewrite.

1. Read `AGENTS.md`.
2. Read this file.
3. Inspect current `carjacking.lua`.
4. Inspect `info.json`.
5. Confirm the repository corresponds to v0.2.14.
6. Run static validation.
7. Commit/tag the known-good baseline.
8. Only then start the next requested feature/fix.

---

# 7. Static validation

Lua syntax checker:
```lua
local f, err = loadfile(arg[1])
if not f then
  io.stderr:write(err .. "\n")
  os.exit(1)
end
print("LUA_SYNTAX_OK")
```

Validate:
- `carjacking.lua` loads syntactically;
- `info.json` parses;
- icon is 96x96 RGB;
- resource tag is `M3Z1BLS58`;
- metadata version matches package filename;
- no `_archived`;
- no Abandon references;
- no backup/temp files in package;
- ZIP integrity passes.

Expected ZIP entries:
```text
README.md
lua/ge/extensions/career/modules/carjacking.lua
mod_info/M3Z1BLS58/icon.jpg
mod_info/M3Z1BLS58/info.json
```

Do not invent numeric BeamNG `resource_id` or `resource_version_id` fields.

---

# 8. Runtime regression suite

Run after any meaningful change.

## Walking / taxi
```text
ambient taxi -> F -> stolen
hail taxi -> wait for pickup -> F -> normal taxi entry
```

## Civilian traffic
```text
steal ordinary traffic -> store/sell/strip
continue driving -> traffic remains healthy
```

## Taxi traffic
```text
steal ambient taxi -> store/sell/strip
continue driving -> ambient taxis appear again
```

## Retrieval
```text
steal car
leave engine running
leave automatic in D or manual in gear
store
retrieve without entering

EXPECTED:
engine off
neutral
parking brake on
stationary
physical damage preserved
```

## Police
```text
steal police car
EXPECTED: max heat, stolen unit no longer acts as police

steal police car during active pursuit
EXPECTED: no Lua error, pursuit remains sane
```

## Pursuit completion
```text
steal civilian near police
evade normally
EXPECTED: normal RLS pursuit completion/reward behavior
```

## Identity / insurance
```text
stolen civilian before identity change
EXPECTED: cannot add normal insurance

change identity
EXPECTED: paint changes, plate changes, normal insurance eligibility returns

stolen police vehicle
EXPECTED: no Change Vehicle Identity option
```

## Hotwire
```text
inspect sale vehicle
Hotwire
EXPECTED: same vehicle becomes stolen inventory, released and starts if needed
```

---

# 9. Packaging / versioning

v0.2.14 is the known-good baseline.

For a future release, update:
```json
{
  "tagid": "M3Z1BLS58",
  "path": "rls_carjacking",
  "filename": "rls_carjacking_vX.Y.Z.zip",
  "title": "RLS Career Carjacking",
  "version_string": "X.Y.Z"
}
```

Do not overwrite/relabel v0.2.14 with changed code. Increment the version.

---

# 10. Communication / testing

The user tests the mod directly in BeamNG.

When handing back a build:
- state exactly what changed;
- state what was deliberately left untouched;
- distinguish confirmed source findings from hypotheses;
- give a short targeted runtime test;
- do not call something fixed until the user confirms it in game;
- avoid incidental changes to unrelated systems.

Current handoff priority: **preserve the stable v0.2.14 baseline and move future development cleanly into Codex**, not reopen solved historical bugs.
