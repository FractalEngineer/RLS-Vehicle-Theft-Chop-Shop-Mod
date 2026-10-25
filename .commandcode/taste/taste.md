# Taste

## Workflow

- When asking a question about behavior/regressions ("did anything change with X?"), expects a read-only investigation first with no code changes until explicitly asked. Confidence: 0.65
- When an upstream dependency (BeamNG, RLS) changes behavior the user dislikes, prefers a local opt-out/workaround in their own mod rather than only reporting it upstream. Confidence: 0.6

## Configuration & defaults

- Gameplay/behavior changes that alter expected player experience should be exposed as a named config flag (added to the `cfg` table) and documented in the README configuration table. Confidence: 0.7
- New toggles should default to "on" / the user's preferred behavior out of the box, not opt-in. Confidence: 0.65
