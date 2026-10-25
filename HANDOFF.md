# HANDOFF.md — RLS Career Carjacking

## Status

**Current release: v0.4.0, targeting BeamNG.drive 0.40.3 and RLS Career Overhaul 2.8.0. The user confirmed the latest build ("perfect") and explicitly authorized committing/pushing all changes and publishing 0.4.0. Automated validation passes; do not claim unreported portions of the full runtime matrix were exercised.**

### v0.4.0 release preparation

- Promote the user-confirmed 0.3.1 test build to 0.4.0; gameplay logic is unchanged during release preparation.
- Put `restoreOnFootPursuitHandoff = true` first in `cfg`, first in the README configuration table, and describe the new pursuit, police restoration and Abandon features at the top of the README.
- Copy the previous published v0.3.0 release body verbatim at the user's explicit request, including its historical headings and compatibility text. README/metadata describe current compatibility.
- Commit all current repository changes, including the user's `.commandcode/taste/taste.md`, and publish the exact seven-file 0.4.0 package through the existing GitHub release workflow. Local research, tests and preferences are excluded from the release ZIP.
- Earlier instructions below to retain 0.3.1 during testing are historical and superseded by this release request.

### On-foot pursuit and police removal lifecycle (2026-10-25)

The user added `restoreOnFootPursuitHandoff = true`; it remains enabled by default. The earlier vehicle-chase startup function is preserved unchanged. Version remains 0.3.1 until release.

Confirmed source failures:

- BeamNG 0.40 `insertTraffic` constructs a native person record but rejects it at its `isVehicle` gate. The previous handoff's insertion therefore never created a walker target. It also lost pending theft alerts/reserves when the source car disappeared.
- Native RLS can run its switch handler before the add-on. That clears old responders and queues a `pursuitChange` with no responder filter. The add-on now caches the original responders through `onPursuitModeUpdate` and replaces only that deferred retarget when necessary.
- RLS can clear an officer's target/flags while retaining `targetPursuitMode`. A stale mode without a target/busy flag must not mark an idle officer committed to another chase.
- Returned native reserves can retain disabled `pursuitEnd`/reset state. Claims now clear that native action before activation and exclude reserves still chasing another live target. Target deletion also releases the add-on's reserve and clears its stale target.
- Police theft previously skipped the exact traffic-entry replacement debt. When the stolen police car was abandoned, that native police slot was permanently lost.

Implementation:

- Register one native `gameplay/traffic/vehicle` person record for the pursued player, then pass it through native traffic registration. Preserve `isPerson=true`, `isVehicle=false`, non-AI state, and native update/removal lists. No parallel traffic manager or persistent police wrapper.
- Carry pursuit data and only the original responders between car, walker and next car. Clear inherited arrest/stuck timers at the transfer. Do not emit a new pursuit start or evade reward. Preserve native re-entry autoArrest behavior.
- Move pending alert/reserve targets synchronously during the switch, independent of the stolen inventory record, so immediately abandoning/deleting the source car cannot strand the on-foot response. A bounded retry covers incomplete player-object registration.
- Stolen police traffic now uses the same exact one-entry restoration debt as civilian traffic, only after its original object leaves the active world, in the same native pool/model/config. Never top-level spawnTraffic or a custom population catalogue.

Validation loads actual installed BeamNG traffic insertion, vehicle class, update-list registration, native position update, and RLS service/role methods. It verifies both switch-hook order cases, a moving walker, preservation of an unrelated chase, disabled reserve reuse across multiple cycles, deleted-target cleanup, and the actual add-on theft -> confirmed Abandon -> exactly one police traffic pool replacement transaction. Unit tests also cover bailing out before the reserve is ready, deleting the source, and continuing the response without its inventory binding.

In-game checks still required after the updated ZIP and a full restart:

1. Steal a police car, exit and run away: officers follow the player; the stopped car cannot complete the arrest.
2. Enter another car: the same chase continues with its score/timers, without stealing officers from an unrelated pursuit.
3. Steal and immediately exit/abandon before the responder is ready: the responder still pursues the walker.
4. Steal/abandon police cars repeatedly: exactly the removed police entry returns to native traffic, one fallback is reused rather than accumulating, and another police theft still dispatches a responder.
5. Verify normal evade/reward and unchanged Abandon confirmation/menu behavior. Opting out with `restoreOnFootPursuitHandoff = false` must retain native RLS behavior.

### Police overflow diagnosis (2026-10-25)

The current `beamng.log` records successful spawning/claiming of reserve 82564, followed by failure in native pursuit startup and repeated maximum-heat retries. The stack sometimes exhausts inside `utils.lua` JSON encoding, but the cause is synchronous role-change recursion, not a cyclic JSON data payload or reserve activation delay.

Installed RLS 2.8.0 source proves this sequence:

1. `integration/services/police.lua:setPursuitMode` changes the suspect action to `fleePolice`, then emits `onPursuitAction('start')` **before** writing `pursuit.mode`.
2. Career enforcement/tasklist callbacks call `career/police/playerDriving.lua:getPlayerIsCop` during that event. With mode still zero, it calls `setRole` using the inventory's `standard` role.
3. `trafficVehicle:setRole` invokes the old suspect's `onRoleEnded` before replacing the role.
4. BeamNG's native suspect `onRoleEnded` sees `flags.flee` and calls `evadeVehicle`.
5. The evade event calls `getPlayerIsCop` again, still with the old role and mode zero. This repeats until stack exhaustion. Delaying reserve activation does not change this ordering.

The new integration test loads the installed RLS service, career cop-status query, traffic role setter, marked responder role, policy registry, and BeamNG base/suspect roles. It first reproduces the recursive start/evade sequence with the unprotected native call, then verifies the add-on's protected startup, responder chase assignment, existing-chase preservation, normal evade, and cleanup after an injected error. Engine objects and event dispatch are mocked; this is not an in-game test.

### Abandon visibility correction (2026-10-25)

The user reports police chases are fixed and explicitly requests no police changes. The Lua file is byte-for-byte identical to the installed working build (SHA256 `c81ef4ed071429133203c667c838727044a3437f2a2552dcbddcf7651389aecb`).

Abandon was absent because BeamNG 0.40's `bngPopoverMenu.vue` uses `defineOptions({ inheritAttrs: false })`. The `.veh-menu` class passed by RLS's `VehicleList.vue` therefore never reaches the DOM. The decorator now finds the emitted `.bng-popover-menu` element and retains its selected-inventory-component and Lua eligibility checks. A regression fixture using the actual native class reproduces the old missing action and passes after the selector correction; the test optionally reads the selector directly from the installed BeamNG Vue file.

Only the UI JavaScript changes inside the updated 0.3.1 ZIP. No police, Lua, version, or removal-transaction changes. Abandon still requires an owned live vehicle without a garage assignment, outside the garage, and destructive confirmation. In-game menu verification remains pending.

### Current v0.3.1 test-build changes

- Use RLS's vehicle-policy `roleLocked` domain only during the synchronous pursuit-start call, only for the selected vehicle's fleeing suspect role while mode is still zero. Always withdraw the policy afterward, including on error. No global police or GUI wrappers.
- Remove `setupPursuitGameplay` from theft startup: the player is already registered in traffic; that helper recreates roles and resets existing pursuits. Call native `setPursuitMode` with selected responders and preserve a higher existing heat level.
- Activate an idle existing native pool unit before requesting a fallback; exclude units busy with another pursuit.
- Replace the add-on's override of the ambient `police` provider with its own zero-population native provider, `rlsCarjackingPolice`. Request at most one marked reserve on demand, including a valid marked fallback when the native sample is empty. RLS's ambient provider/population is unchanged.
- Keep the reserve claimed while it pursues and return it through the native API on completion or cancellation. Do not release ordinary police pool members as reserves.
- Remove Abandon from the main garage computer and remove its separate picker. Show **Abandon** only in **My Vehicles**, for owned, live vehicles in unassigned **Storage / N/A**, outside the garage. Recheck eligibility, exact vehicle and object binding at confirmation; use native inventory removal with no financial transaction.
- Button and popup use **Abandon** without financial wording; Cancel remains the default and the confirmation is destructive and single-use.
- The isolated UI decorator reads `VehicleList`'s `vehSelected` and inventory store from the owning Vue instance, then requests authoritative Lua eligibility. Inspected BeamNG 0.40's shipped renderer exposes `__vueParentComponent`; its SFC compiler uses `inlineTemplate: false`, exposing setup state. This depends on BeamNG's native `.bng-popover-menu` and RLS's setup variable names. No RLS Vue page override.
- Added optional installed-source integration checks to `tools/validate_release.py` via `--rls-source <RLS lua/ge/extensions>` and `--beamng-source <BeamNG lua>`.

Static validation: LuaJIT loadfile, transaction/identity/retrieval/traffic regression suite, actual-source police integration, JavaScript menu/icon tests, metadata, 96x96 RGB icon and exact seven-entry ZIP integrity. The v0.2.14 baseline tag already exists and was preserved.

Targeted in-game checks after replacing the old add-on ZIP and fully restarting BeamNG:

1. Steal the last police car: maximum heat, one marked responder actually chases, stolen car cannot arrest you, no stack overflow.
2. Steal a police car during a chase: preserve the pursuit, do not retarget unrelated busy cops.
3. Evade: verify normal RLS completion/reward and responder return to native traffic.
4. My Vehicles: Abandon only on an owned, live Storage / N/A vehicle; no main garage tile, assigned-garage action or stored-car action. Cancel/Escape preserve the car; confirm removes it once. Reassignment/retrieval while the popup is open must cancel removal.
5. Run the full walking/taxi, retrieval, identity/insurance, hotwire and traffic matrix below before publication.

### Previous compatibility work retained

- RLS 2.8 module resolution prefers `overhaul_*`, with legacy 2.7 fallbacks and explicit deferred `modScript.lua` loading.
- Native `onOverhaul*` hooks and the RLS walking patch chain remain in use.
- BeamNG 0.40 traffic uses `autoTraffic`; civilian restoration remains exact one-for-one, without top-level spawning during pursuit.

Per user instruction, retain version 0.3.1 throughout testing; increment only for release. The older v0.3.1 notes below are history, not the current diagnosis or implementation.

v0.3.1 issue-tracker work:
- Re-audited installed RLS 2.7.2 after the latest user update.
- Excluded `simple_traffic` shells and applied full-detail traffic while the add-on is active. RLS 2.7.2 does not solve the shell-into-inventory valuation problem itself.
- Preserved dealership year/mileage during hotwire and generated a valid year plus age-consistent mileage for street traffic.
- Persisted and reconciled laundered paint/plate state across recovery, respawn, part-condition refresh, and garage repair.
- Kept RLS 2.7.2's intentional low-weight `joesjunkcar` traffic behavior instead of restoring the 2.7.1 workaround.
- Issue #3 (post-sale `parkingSpot` stale object route) still needs the reporter's game log and reproduction; the current report does not identify a carjacking-owned object or call path.
- Issue #4 contains no version, log, or reproduction details and cannot be diagnosed yet.
- User runtime testing with BeamNG.drive 0.40.3 and RLS 2.7.2 was unsuccessful. No further mechanism should be guessed until the updated RLS integration is available for inspection.

v0.3.1 compatibility changes:
- Inspected BeamNG.drive 0.40.3 build 290897 and installed RLS 2.7.1.
- Excluded 0.40 provider-reserved and claimed traffic from carjacking. Native taxis use the new reserved traffic lifecycle and must not be consumed by this add-on.
- Removed `career_modules_inspectVehicle`, `career_modules_vehicleShopping`, and `career_modules_payment` from hard dependencies. They are optional at load and already accessed defensively at runtime, avoiding 0.40/RLS load-order blocking.
- Used 0.40's native cancel, confirm, and destructive roles on the Strip for Parts confirmation buttons.
- Confirmed the remaining native contracts used by the module still exist in 0.40.3: walking blacklist/entry hooks, traffic insertion/removal, active vehicle pooling, career inventory/save callbacks, garage teleport hook, speed-trap hooks, and confirmation dialogs.

v0.2.16 adds native Strip for Parts confirmation after the condition refresh, with vehicle name/ID, an exact quote, Cancel as default, and one-use request tokens. Confirmation rechecks ownership, availability, vehicle identity and quote. Ordinary purchased vehicles remain excluded. Successful identity changes now remove the synthetic meet-reputation discount immediately; older identity-changed saves are migrated once by the normal stolen-state enforcement pass. Later native meet-reputation changes are left alone. This supersedes the original requirement to retain the value penalty after identity change.

Additional runtime checks: cancel stripping with both Cancel and Back/Escape, confirm the correct car/payout, verify ordinary purchased cars have no Strip option; change identity and confirm normal value; reload a previously identity-changed car and confirm its penalty stays removed.

The v0.2.14 baseline is already committed and tagged (`6edbfc3`). The September 2026 user report supersedes the old retrieval/stripping status below for RLS 2.7.1.

v0.2.15 changes:
- Garage retrieval restarts the existing bounded safe-state guard on native `onTeleportedToGarage`, including same-object retrieval. Retries count simulation time, so paused menus cannot exhaust them. BeamNG's velocity-only cluster operation clears motion; queued vehicle commands skip vehicles the player has entered. The redundant separate ignition bridge request is removed.
- Stripping accepts a valid zero valuation, normalizes numeric inventory IDs, checks availability, closes the menu for the live condition request, prevents duplicate/late transactions, and reports errors/timeouts. The reported no-op has not been reproduced in BeamNG; these address confirmed failure paths and make remaining failures observable.
- Exact civilian replacement remains necessary: 2.7.1 still removes stolen entries without automatic one-for-one replenishment. Replacement debts are discarded when their native pool changes. Insertion no longer forces the native pool-wide activation pass.
- An isolated UI mod decorates the Strip for Parts computer tile because RLS 2.7.1 ignores Lua icon fields. Hotwire uses the radial menu's native `lockOpened` icon. No RLS/Vue files are overridden. The decorator depends on RLS's `.computer-function-tile`, `.label`, `.icon` markup and this add-on's English strip label.

Source inspected: installed `rls_career_overhaul_2.7.1.zip` and the current BeamNG Lua/UI files. Reference extraction and Lua test dependencies are under Windows TEMP, excluded from the release. `tools/validate_release.py --lua-deps <temporary-lupa-install> --package` runs loadfile/regression checks and builds the explicit six-file manifest. `tests/test_icons.cjs` checks the scoped UI decorator.

Runtime tests still required: stripping damaged/undamaged/totaled vehicles; store in D/manual gear with engine running and retrieve without entry (also retrieve an already-live car); verify neutral, engine/starter off, brake on, no movement, damage/paint/plate retained; verify the Strip for Parts icon and Hotwire's native open-lock icon; repeated theft/store/sell/strip and a mission transition; normal taxi entry, police theft, pursuit completion, hotwire and identity/insurance matrix below.

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
scripts/rls_carjacking/modScript.lua
ui/modModules/rlsCarjacking/rlsCarjacking.js
ui/modModules/rlsCarjacking/icons/strip_for_parts.svg
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

### Abandon
**Abandon** is available only in the My Vehicles context menu for unassigned, live Storage / N/A vehicles outside the garage, behind a destructive confirmation. Stored and garage-assigned vehicles are excluded. Use native removal without a financial transaction.

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
- Abandon is free and confirmation-bound;
- no backup/temp files in package;
- ZIP integrity passes.

Expected ZIP entries:
```text
README.md
lua/ge/extensions/career/modules/carjacking.lua
mod_info/M3Z1BLS58/icon.jpg
mod_info/M3Z1BLS58/info.json
ui/modModules/rlsCarjacking/rlsCarjacking.js
ui/modModules/rlsCarjacking/icons/strip_for_parts.svg
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
