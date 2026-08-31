# RLS Career Carjacking

Carjacking add-on for **BeamNG.drive + RLS Career Overhaul**.

## Features

- Steal live AI traffic using the normal **Enter/Exit Vehicle** control.
- Hotwire inspected vehicles for sale from the action wheel outside an active test drive.
- Police vehicles can be stolen and trigger maximum police heat.
- Stolen vehicles keep their configuration, damage, paint and license plate.
- Stolen vehicles are uninsured and cannot receive automated speed-camera or red-light-camera fines.
- Stolen plates become hot after a delay and can trigger a pursuit when spotted by police.
- Removing the license plate through the Parts Editor prevents future stolen-plate detection.
- Stolen vehicles have reduced market value.
- Hotwiring a dealership vehicle can apply a configurable dealer reputation penalty.
- Retrieved stolen vehicles spawn safely parked with the ignition off and parking brake applied.
- Retrieved stolen vehicles can be **stripped for parts for 5% of their value** from their garage vehicle menu.

## Installation

Leave the ZIP file intact and place it directly in your BeamNG user `mods` folder.

Keep only one copy of the mod installed, then fully restart BeamNG after replacing the file.

Enable **RLS Career Overhaul** and **RLS Career Carjacking**, then load your RLS career save.

## Using Carjacking

While on foot, walk next to an eligible AI traffic vehicle and press your normal **Enter/Exit Vehicle** control once.

The stolen vehicle is added to your career inventory and can be driven, stored, sold, modified, or stripped according to its condition and location.

## Hotwiring Sale Vehicles

Inspect a vehicle that is for sale and enter it while you are **not** in an active timed test drive.

Open the action wheel and select **Hotwire**. The vehicle is removed from the sale, added to your career inventory, and treated as a stolen vehicle with the same plate, police and value rules as a carjacked traffic vehicle.

Dealership vehicles can reduce reputation with that dealer's associated organization. RLS private marketplace sellers do not currently share a dealership organization reputation, so private-sale hotwires do not apply that reputation penalty.

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
| `plateFlagDelaySeconds` | `120` | Time in seconds after theft before the stolen license plate becomes hot. |
| `plateScanRadius` | `55.0` | Maximum distance in meters at which a police vehicle can recognize a hot stolen plate. |
| `plateScanInterval` | `0.40` | Time in seconds between stolen-plate scan checks. |
| `platePursuitLevel` | `2` | Pursuit level triggered when police recognize a hot stolen plate. |
| `stolenValueMultiplier` | `0.35` | Multiplier applied to a stolen vehicle's normal market value. `0.35` means 35% of normal value. |
| `stripPartsMultiplier` | `0.05` | Fraction of current vehicle value paid when using **Strip for Parts**. `0.05` means a 5% payout. |
| `allowPoliceVehicles` | `true` | Set to `false` to prevent police vehicles from being stolen. |
| `allowSaleVehicleHotwire` | `true` | Enables the **Hotwire** action for inspected vehicles that are for sale. |
| `allowPrivateSellerHotwire` | `true` | Allows vehicles from private marketplace sellers to be hotwired. |
| `dealerHotwireReputationPenalty` | `5000` | Reputation points deducted from a dealership's associated organization after a successful hotwire. Set to `0` to disable the reputation penalty. |
| `carjackArrestGraceSeconds` | `4.0` | Short grace period in seconds after taking control of a stolen vehicle before an existing nearby pursuit can complete an arrest. |
| `desiredPoliceResponders` | `1` | Target number of active police responders to ensure after stealing a police vehicle. |
