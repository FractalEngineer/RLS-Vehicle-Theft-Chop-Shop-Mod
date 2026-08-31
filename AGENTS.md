# AGENTS.md — RLS Career Carjacking

## Project

This repository contains **RLS Career Carjacking**, a BeamNG.drive add-on for **RLS Career Overhaul**.

Published resource:
- https://www.beamng.com/resources/rls-carjacking-mechanic.39197/
- BeamNG resource/tag ID: `M3Z1BLS58`

**Known-good baseline: v0.2.14.**

Treat v0.2.14 as the reference behavior. Older handoffs/chat logs may describe bugs from v0.2.13 or earlier that are already fixed.

Primary implementation:
```text
lua/ge/extensions/career/modules/carjacking.lua
```

Expected release package:
```text
README.md
lua/ge/extensions/career/modules/carjacking.lua
mod_info/M3Z1BLS58/icon.jpg
mod_info/M3Z1BLS58/info.json
```

Do not add backup/research/temp files or directory entries to the release ZIP. Do not use `_archived` in release filenames.

---

## Source of truth

When information conflicts, use this priority:

1. Current checked-out source.
2. Known-good v0.2.14 release/README.
3. User-confirmed in-game behavior.
4. Current BeamNG/RLS source.
5. Older handoffs/chat history.

Before changing a subsystem, inspect the current implementation and diff against v0.2.14 if possible.

---

## Working style

1. Prefer **minimal, local fixes**.
2. Do **not** build a parallel traffic manager.
3. Do **not** globally wrap economy, insurance, GUI, or value-calculator functions.
4. Do not alter unrelated RLS behavior to fix a local carjacking issue.
5. For regressions, diff against v0.2.14 before inventing a new mechanism.
6. Use temporary diagnostic logging when lifecycle/order is uncertain; remove it before release.
7. Preserve stolen-vehicle save compatibility where practical.
8. Do not claim runtime success until tested in BeamNG.
9. Keep README user-facing: current features, installation, usage, configuration.

---

## Known-good v0.2.14 behavior — preserve

### Walking / carjacking priority

Carjacking uses the normal **Enter/Exit Vehicle** control while walking.

Critical rule:
```text
If BeamNG/RLS already exposes a normal enterable vehicle in front of the player,
normal Enter/Exit wins and carjacking must not intercept it.
```

Only AI traffic blocked from ordinary walking-mode entry should fall through to the carjacking path.

This is the working taxi compatibility behavior:
- ambient traffic taxis can be stolen;
- a taxi hailed by the player and waiting for pickup is entered normally;
- no taxi-state/config/vehicle-ID guessing is required.

Do not replace this with cab-state detection, taxi config blacklists, spawn interception, or active-cab ID heuristics unless a new regression proves it necessary.

### Civilian traffic replenishment

v0.2.14 traffic replenishment is intentionally narrow.

When a stolen civilian traffic vehicle later leaves the active world:
- restore **exactly that one removed traffic entry**;
- restore the same model/configuration;
- hand it directly back to BeamNG's normal traffic pool;
- then get out of the way.

There is:
- no separate taxi replenishment logic;
- no traffic-variety reserve;
- no rotating custom catalogue;
- no deliberate pool expansion;
- no map-wide traffic manager;
- no repeated top-level `gameplay_traffic.spawnTraffic()` churn.

Ambient taxis recover through the same generic traffic-entry restoration path as other stolen civilian traffic vehicles.

### Garage retrieval / safe parked state

v0.2.14 clean retrieval is known-good.

During the short RLS retrieval handoff, retrieved stolen vehicles must settle as:
- AI disabled;
- stale driver inputs cleared;
- transmission in neutral;
- parking brake applied;
- starter off;
- ignition off;
- stationary.

Physical damage must remain intact.

The working v0.2.14 implementation detects retrieval immediately and repeatedly enforces the safe controller state during the short handoff. Preserve the proven lifecycle/order rather than replacing it with an unproven reset architecture.

Do not use full `powertrain.reset()` or a destructive whole-vehicle reset unless damage persistence is explicitly proven safe.

### Police theft

Preserve:
- police vehicles can be stolen;
- stolen police vehicle immediately loses police responder/registry role;
- stolen police car cannot arrest the player;
- police-car theft triggers maximum heat;
- short arrest grace during handoff;
- busy cops are not indiscriminately retargeted;
- wake existing RLS marked responders first;
- create at most one explicitly marked fallback responder if truly required;
- never generic/random police-group spam;
- stolen police vehicles cannot **Change Vehicle Identity**, and the option must not be shown.

### Pursuits

Do not disturb normal RLS pursuit lifecycle. A normal evade must still reach RLS pursuit completion/reward behavior.

Avoid global traffic-state resets or top-level traffic spawning during a pursuit.

### Hotwire

Sale vehicles can be hotwired from the action wheel while inspected and outside an active timed test drive.

Successful hotwire:
- keeps the same live vehicle/configuration;
- removes it from the sale listing;
- adds it to career inventory;
- preserves damage, paint, plate and configuration;
- releases/unfreezes it;
- starts it if necessary;
- applies stolen-vehicle police/identity/insurance/value rules.

Private marketplace hotwires are enabled by default.

Dealership penalty:
```lua
dealerHotwireReputationPenalty = 500
```
This means 500 reputation points are deducted.

### Stolen identity / insurance

A stolen civilian vehicle cannot receive normal RLS insurance until identity is changed.

The implementation uses a private negative insurance state distinct from RLS ordinary uninsured `-1`, keeping identity-locked stolen cars out of normal Add Coverage.

**Change Vehicle Identity**:
- unavailable for stolen police vehicles;
- changes the license plate;
- changes paint to a random available native paint;
- clears future stolen-vehicle identification;
- restores ordinary RLS insurance eligibility;
- keeps the stolen-value balancing penalty.

Default duration:
```lua
identityChangeDurationSeconds = 0
```
`0` = instant.

### Economy defaults

```lua
stolenValueMultiplier = 0.35
stripPartsMultiplier = 0.05
identityChangeCostMultiplier = 0.35
dealerHotwireReputationPenalty = 500
```

Never reintroduce a global sell-value wrapper.

### Names / persistence

Preserve:
- native BeamNG configuration names where available;
- configuration;
- physical damage/part condition;
- paint;
- plate;
- stolen metadata;
- intentional manual vehicle renames.

### Camera fines

Automated speed/red-light camera fines remain exempt for stolen vehicles according to the current implementation.

### Removed feature

The old **Abandon** feature is intentionally absent. Do not reintroduce it unless explicitly requested.

---

## v0.2.14 configuration defaults

```lua
local cfg = {
  interactDistance = 3.25,
  maxTargetSpeedMps = 12.0,

  immediateAlertRadius = 220.0,
  immediateAlertLevel = 2,
  policeCarjackLevel = 3,

  identityFlagDelaySeconds = 120,
  identityScanRadius = 55.0,
  identityScanInterval = 0.40,
  identityPursuitLevel = 2,

  stolenValueMultiplier = 0.35,
  stripPartsMultiplier = 0.05,
  allowPoliceVehicles = true,

  allowSaleVehicleHotwire = true,
  allowPrivateSellerHotwire = true,
  dealerHotwireReputationPenalty = 500,

  identityChangeCostMultiplier = 0.35,
  identityChangeDurationSeconds = 0,

  carjackArrestGraceSeconds = 4.0,
  desiredPoliceResponders = 1
}
```

If the checked-out v0.2.14 source differs, inspect why before "correcting" it.

---

## Dangerous historical regressions — never reintroduce

- Global `career_modules_valueCalculator.getInventoryVehicleSellValue` wrapper made unrelated cars worth $0.
- Broad insurance wrappers/direct insurance JSON mutation caused breakage.
- Persistent `guihooks.trigger` wrapper caused fatal menu errors.
- Stolen police vehicle once remained registered as police and could arrest the player.
- Generic police fallback spawned too many/unmarked police vehicles.
- Paint was previously lost during theft/retrieval.
- Top-level traffic spawning interfered with pursuit state.
- Traffic variety reserves/custom pool management were too invasive.
- Taxi-specific state/config/ID heuristics repeatedly failed; normal-enterable-vehicle priority is the working solution.
- Old physical license-plate-removal detection was replaced by **Change Vehicle Identity**.
- `walkerDistanceToVehicle()` was accidentally removed in one historical build and caused a fatal police-car theft error.
- **Abandon** must stay removed.

---

## Development rules

1. Inspect the exact current BeamNG/RLS API before wrapping/calling it.
2. Prefer native lifecycle hooks over polling.
3. Avoid per-frame scans of the entire career inventory.
4. Avoid persistent monkey-patches where a local/scoped hook works.
5. Do not assume object enumeration is synchronous immediately after a spawn.
6. Preserve pursuit state and traffic ownership boundaries.
7. If lifecycle order is unclear, temporarily log inventory ID, vehicle ID, traffic role, pursuit mode, walking target and callback order.
8. Remove diagnostics before packaging.

---

## Regression test matrix

Before release, test at minimum:

### Walking / taxi
- steal ordinary civilian traffic;
- steal ambient taxi;
- hail taxi, wait for pickup, press Enter/Exit -> normal taxi ride, not theft;
- steal police vehicle;
- steal police vehicle during an existing chase.

### Traffic
- repeatedly steal/store/sell/strip civilian cars;
- confirm traffic population remains healthy;
- steal/store/sell/strip an ambient taxi;
- continue driving and confirm taxis reappear naturally;
- ensure no custom variety system has been introduced.

### Pursuit
- steal civilian near police;
- sustain pursuit;
- evade normally;
- verify normal RLS pursuit completion/reward behavior;
- verify traffic restoration does not cancel pursuit.

### Retrieval
Store stolen cars deliberately in bad states:
- engine running;
- automatic in D;
- manual in gear;
- parking brake off.

Retrieve without entering.

Expected:
```text
engine off
starter off
neutral
parking brake on
stationary
damage preserved
paint/plate preserved
```

Repeat with damaged/undamaged cars and EV if available.

### Identity / insurance
- stolen civilian cannot receive normal insurance before identity change;
- Change Vehicle Identity changes paint + plate;
- identity-changed vehicle becomes normally insurable;
- stolen police vehicle never shows Change Vehicle Identity.

### Hotwire
- dealership vehicle;
- private-sale vehicle;
- running vehicle;
- non-running vehicle;
- dealer reputation deduction defaults to 500.

---

## Release validation

Before packaging:

1. Lua syntax check with `texlua` / `loadfile`.
2. Parse `mod_info/M3Z1BLS58/info.json`.
3. Verify icon is 96x96 RGB.
4. Verify `tagid` remains `M3Z1BLS58`.
5. Verify metadata version and ZIP filename match.
6. Do not invent numeric BeamNG `resource_id` or `resource_version_id`.
7. Verify no `_archived` filename.
8. Verify no Abandon references.
9. ZIP must contain exactly:
   ```text
   README.md
   lua/ge/extensions/career/modules/carjacking.lua
   mod_info/M3Z1BLS58/icon.jpg
   mod_info/M3Z1BLS58/info.json
   ```
10. `zipfile.testzip()` must return `None`.
11. Fully restart BeamNG after replacing a test/release ZIP.

BeamNG runtime is the final authority. Static validation alone is not enough.

---

## Versioning

Current known-good baseline:
```text
v0.2.14
```

For the next release, increment from 0.2.14 according to scope. Do not silently reuse 0.2.14 for materially changed code.

---

## Codex first action

1. Read this `AGENTS.md`.
2. Read `HANDOFF.md`.
3. Inspect current `carjacking.lua` and `info.json`.
4. Confirm the working tree corresponds to v0.2.14 or understand why it differs.
5. Commit/tag the known-good v0.2.14 baseline before feature work.
6. Do **not** begin by fixing old v0.2.13 taxi/retrieval bugs; they are already fixed in v0.2.14.
