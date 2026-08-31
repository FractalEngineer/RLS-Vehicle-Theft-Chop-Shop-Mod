# RLS Career Carjacking

Carjacking add-on for **BeamNG.drive + RLS Career Overhaul**.

## Features

- Steal live AI traffic using the normal **Enter/Exit Vehicle** control.
- Taxis called through the RLS cab service are exempt from carjacking while the cab service is active, so **Enter/Exit Vehicle** enters the taxi normally.
- Stolen traffic is automatically replenished with a new normal traffic vehicle so repeated carjackings do not empty the map.
- Hotwire inspected vehicles for sale from the action wheel outside an active test drive; the vehicle is released and started when the hotwire completes.
- Police vehicles can be stolen and trigger maximum police heat.
- Stolen vehicles keep their configuration, damage, paint and license plate when first stolen.
- Stolen vehicles cannot be insured until their vehicle identity is changed, and do not receive automated speed-camera or red-light-camera fines.
- Eligible stolen vehicles can use **Change Vehicle Identity** from their garage vehicle menu. The service randomizes the paint and license plate, clears future stolen-vehicle identification and makes the vehicle eligible for normal RLS insurance again.
- Stolen police vehicles cannot have their identity changed.
- Stolen vehicle identity becomes known to police after a delay and can trigger a pursuit when the vehicle is recognized nearby.
- Stolen vehicles have reduced market value.
- Hotwiring dealership vehicles applies a configurable dealer reputation penalty.
- Retrieved stolen vehicles spawn safely parked with the ignition off and parking brake applied.
- Retrieved stolen vehicles can be **stripped for parts** from their garage vehicle menu for a heavily reduced payout.

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

## Changing a Stolen Vehicle Identity

Retrieve an eligible stolen vehicle to a garage and open its vehicle menu. Select **Change Vehicle Identity**.

BeamNG/RLS does not currently expose a native VIN for career inventory vehicles, so this represents changing the vehicle's identifying markings and registration identity as a gameplay mechanic. On completion, the vehicle receives a random paint color from its model's available paints and a newly generated license plate.

Before the service is completed, the vehicle remains blocked from RLS insurance and can still be identified as stolen. After completion, it becomes a normal uninsured vehicle that can receive coverage through RLS's Insurance menu. The stolen-value reduction remains in place for economy balance.

Stolen police vehicles cannot use this service.

## Configuration

User-adjustable settings are at the top of `lua/ge/extensions/career/modules/carjacking.lua` inside the `cfg` table.

After changing a value, save the file and fully restart BeamNG before testing it. Keep Lua syntax intact: numbers do not use quotes, and booleans are `true` or `false`.

| Variable | Default | Description |
| --- | ---: | --- |
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
| `allowSaleVehicleHotwire` | `true` | Enables the **Hotwire** action for inspected vehicles that are for sale. |
| `allowPrivateSellerHotwire` | `true` | Allows vehicles from private marketplace sellers to be hotwired. |
| `dealerHotwireReputationPenalty` | `500` | Reputation points deducted from a dealership's associated organization after a successful hotwire. Set to `0` to disable the reputation penalty. |
| `identityChangeCostMultiplier` | `0.35` | Cost of changing a stolen vehicle's identity as a fraction of its current market value. `0.35` means 35%. |
| `identityChangeDurationSeconds` | `0` | Time in real-world seconds for **Change Vehicle Identity** to complete after payment. `0` makes it instant. |
| `carjackArrestGraceSeconds` | `4.0` | Short grace period in seconds after taking control of a stolen vehicle before an existing nearby pursuit can complete an arrest. |
| `desiredPoliceResponders` | `1` | Target number of active police responders to ensure after stealing a police vehicle. |
