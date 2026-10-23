## RLS Career Carjacking 0.3.1

**Draft only. Do not publish until RLS provides BeamNG.drive 0.40 compatibility
and the runtime test matrix passes.**

### Compatibility

- Updated for BeamNG.drive 0.40.3 and RLS Career Overhaul 2.7.2.
- BeamNG 0.40 provider-reserved and claimed traffic vehicles are never selected for carjacking, preserving native taxi dispatch and other provider lifecycles.
- Removed optional RLS modules from hard extension dependencies so load order cannot block the carjacking module.
- The Strip for Parts confirmation uses BeamNG 0.40's native cancel, confirm, and destructive button roles.

### Issue Tracker Fixes

- Simplified traffic shells are excluded from carjacking, and full-detail traffic is enabled while the add-on is active so stolen cars have real parts and normal career values.
- Hotwired dealership vehicles retain the seller's year and mileage.
- Street-stolen vehicles receive a valid model year and age-consistent mileage that survive RLS's asynchronous inventory hooks.
- Laundered paint and plates are reconciled after recovery, respawning, and repair without locking later legal repaints.

### Preserved

- Existing carjacking, hotwire, strip, retrieval, traffic restoration, police, pursuit, identity, insurance, and valuation behavior remains intact.
- BeamNG runtime regression testing remains required after installation.
