# RLS Career Carjacking

Carjacking add-on for **BeamNG.drive + RLS Career Overhaul**.

Version **0.4.0**, updated for **BeamNG.drive 0.40.3** and **RLS Career Overhaul 2.8.0**.

## New in 0.4.0

- **On-foot pursuit:** `restoreOnFootPursuitHandoff = true` makes the chase follow you when you leave a pursued vehicle and continue in the next vehicle you enter. This option is enabled by default and is the first setting in `cfg`. Set it to `false` to keep RLS's pursuit attached to your last vehicle.
- **Police traffic restoration:** storing or abandoning a stolen police traffic car restores exactly its original traffic entry. Native fallback responders can be reused for later thefts.
- **Abandon:** select an eligible vehicle under **My Vehicles → Storage / N/A**, choose **Abandon**, and confirm the popup. The action is restricted to owned vehicles left in the world without a garage assignment.

## Features

- Steal live AI traffic using the normal **Enter/Exit Vehicle** control.
- Vehicles that BeamNG/RLS exposes as normal walking-mode entry targets are never intercepted by carjacking. This keeps called passenger taxis and other legitimate service/scripted vehicles on their native Enter/Exit interaction.
- Carjacking leaves BeamNG/RLS traffic management in control. When a stolen traffic vehicle, including a police vehicle, later leaves the active world, the mod restores exactly that one removed traffic entry with the same model/configuration. If RLS has rebuilt the traffic pool in the meantime, that new population takes precedence.
- Provider-reserved traffic, including taxis dispatched by BeamNG's native traffic system, is never selected for carjacking and stays under its native lifecycle.
- Hotwire inspected vehicles for sale from the action wheel outside an active test drive; the vehicle is released and started when the hotwire completes.
- Police vehicles can be stolen and trigger maximum police heat. Exiting during a pursuit transfers it to the player on foot, then to the next vehicle entered; this can be disabled in configuration. Abandoning or storing a stolen police traffic vehicle restores its exact native traffic entry.
- Stolen vehicles keep their configuration, damage, paint and license plate when first stolen.
- Stolen street traffic receives a model-appropriate year and age-consistent mileage; hotwired dealership vehicles keep the seller's year and mileage.
- Stolen vehicles cannot be insured until their vehicle identity is changed, and do not receive automated speed-camera or red-light-camera fines.
- Eligible stolen vehicles can use **Change Vehicle Identity** from their garage vehicle menu. The service randomizes the paint and license plate, clears future stolen-vehicle identification and makes the vehicle eligible for normal RLS insurance again.
- Stolen police vehicles cannot have their identity changed.
- Stolen vehicle identity becomes known to police after a delay and can trigger a pursuit when the vehicle is recognized nearby.
- Changed identity paint and plate state is retained through garage recovery, respawning, and repair.
- Stolen vehicles have reduced market value until their identity is changed.
- Hotwiring dealership vehicles applies a configurable dealer reputation penalty.
- Retrieved stolen vehicles are detected immediately and repeatedly reset to a safe controller state during the short RLS retrieval handoff: AI disabled, driver inputs cleared, transmission in neutral, parking brake applied, starter off and ignition off. Physical vehicle damage is left intact.
- Retrieved stolen vehicles can be **stripped for parts** from their garage computer menu for a heavily reduced payout, including totaled cars. Strip for Parts has a custom icon.
- Owned vehicles left in the wild appear under **Storage / N/A** in **My Vehicles**. Their context menu offers **Abandon**, with a destructive confirmation popup.

## Installation

Leave the ZIP file intact and place it directly in your BeamNG user `mods` folder.

Keep only one copy of the mod installed, then fully restart BeamNG after replacing the file.

Enable **RLS Career Overhaul** and **RLS Career Carjacking**, then load your RLS career save.

## Using Carjacking

While on foot, walk next to an eligible AI traffic vehicle and press your normal **Enter/Exit Vehicle** control once.

The stolen vehicle is added to your career inventory and can be driven, stored, sold, modified, or stripped according to its condition and location.

## Hotwiring Sale Vehicles

Inspect a vehicle that is for sale and enter it while you are **not** in an active timed test drive.

Open the action wheel and select **Hotwire**. The vehicle is removed from the sale, added to your career inventory, released from the inspection lock and started if necessary. It then follows the same stolen-vehicle police, identity, insurance and value rules.

Dealership vehicles can reduce reputation with that dealer's associated organization. RLS private marketplace sellers do not currently share a dealership organization reputation, so private-sale hotwires do not apply that reputation penalty.

## Stripping for Parts

Retrieve a stolen vehicle to a garage, open the garage computer, select the vehicle and choose **Strip for Parts**. The menu closes while its current condition is checked, then a confirmation popup shows the vehicle name, inventory number and payout. **Cancel** is selected by default. Confirming permanently removes the entire vehicle and pays 5% of its current value by default, with a minimum payout of $1. Normally purchased vehicles cannot be stripped through this add-on.

Cancel an auction listing or wait for a rented/delayed vehicle to become accessible before stripping it. If the condition check fails or times out, stripping is cancelled and a message explains what happened.

## Abandoning a Vehicle

Open **My Vehicles**, select a vehicle in the **Storage / N/A** group, and choose **Abandon**. Confirm the popup to permanently remove that vehicle from your inventory. The action is available only for owned vehicles currently left in the world with no garage assignment, outside the garage. Vehicles stored at or assigned to a garage are excluded.

## Changing a Stolen Vehicle Identity

Retrieve an eligible stolen vehicle to a garage and open its vehicle menu. Select **Change Vehicle Identity**.

BeamNG/RLS does not currently expose a native VIN for career inventory vehicles, so this represents changing the vehicle's identifying markings and registration identity as a gameplay mechanic. On completion, the vehicle receives a random paint color from its model's available paints and a newly generated license plate.

Before the service is completed, the vehicle remains blocked from RLS insurance and can still be identified as stolen. After completion, it becomes a normal uninsured vehicle that can receive coverage through RLS's Insurance menu, and the stolen-value penalty is removed. Normal condition, damage and market factors still affect its value. Vehicles whose identity was changed in an older version also regain normal valuation when loaded.

Stolen police vehicles cannot use this service.

## Configuration

User-adjustable settings are at the top of `lua/ge/extensions/career/modules/carjacking.lua` inside the `cfg` table.

After changing a value, save the file and fully restart BeamNG before testing it. Keep Lua syntax intact: numbers do not use quotes, and booleans are `true` or `false`.

| Variable | Default | Description |
| --- | ---: | --- |
| `restoreOnFootPursuitHandoff` | `true` | Restores the pre-RLS-2.8 handoff where leaving a pursued vehicle moves the pursuit onto the player on foot and then to the next vehicle entered. Set to `false` to keep RLS 2.8's behavior of leaving the pursuit on the abandoned car. |
| `interactDistance` | `3.25` | Maximum distance in meters from the player to an eligible traffic vehicle for carjacking. |
| `maxTargetSpeedMps` | `12.0` | Maximum target vehicle speed in meters per second. `12.0 m/s` is about `43 km/h`. |
| `immediateAlertRadius` | `220.0` | Radius in meters in which nearby police can immediately respond to a theft, including a hotwired sale vehicle. |
| `immediateAlertLevel` | `2` | Initial pursuit level when nearby police immediately respond to a normal theft. Pursuit levels range from `1` to `3`. |
| `policeCarjackLevel` | `3` | Pursuit level triggered by stealing a police vehicle. `3` is maximum heat. |
| `identityFlagDelaySeconds` | `120` | Time in seconds after theft before the vehicle is considered reported/known stolen. |
| `identityScanRadius` | `55.0` | Maximum distance in meters at which a police vehicle can recognize a reported stolen vehicle. |
| `identityScanInterval` | `0.40` | Time in seconds between stolen-vehicle identification checks. |
| `identityPursuitLevel` | `2` | Pursuit level triggered when police recognize a reported stolen vehicle. |
| `stolenValueMultiplier` | `0.35` | Multiplier applied to a stolen vehicle's normal market value. `0.35` means 35% of normal value. |
| `stripPartsMultiplier` | `0.05` | Fraction of current vehicle value paid when using **Strip for Parts**. `0.05` means a 5% payout. |
| `allowPoliceVehicles` | `true` | Set to `false` to prevent police vehicles from being stolen. |
| `requireFullDetailTrafficVehicles` | `true` | Keeps simplified traffic shells out of career inventory and disables BeamNG's simplified-traffic option while the add-on is active. Set to `false` to accept shell vehicles with placeholder parts and values. |
| `allowSaleVehicleHotwire` | `true` | Enables the **Hotwire** action for inspected vehicles that are for sale. |
| `allowPrivateSellerHotwire` | `true` | Allows vehicles from private marketplace sellers to be hotwired. |
| `dealerHotwireReputationPenalty` | `500` | Reputation points deducted from a dealership's associated organization after a successful hotwire. Set to `0` to disable the reputation penalty. |
| `identityChangeCostMultiplier` | `0.35` | Cost of changing a stolen vehicle's identity as a fraction of its current market value. `0.35` means 35%. |
| `identityChangeDurationSeconds` | `0` | Time in real-world seconds for **Change Vehicle Identity** to complete after payment. `0` makes it instant. |
| `carjackArrestGraceSeconds` | `4.0` | Short grace period in seconds after taking control of a stolen vehicle before an existing nearby pursuit can complete an arrest. |
| `desiredPoliceResponders` | `1` | Maximum number of existing police units assigned to a stolen-police pursuit. Idle native pool units are activated first; when none are available, one marked responder is requested through a separate native provider. RLS controls the pursuit and ambient police population. |
