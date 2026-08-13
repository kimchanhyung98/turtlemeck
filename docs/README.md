# turtlemeck Documentation

This directory documents turtlemeck's current features and behavior.
The product guides describe the app as implemented, and the adopted technical documents record the design and research used by the current code.
Any difference between the app and these documents is a bug.

The Korean product name is 목바로.
The technical identifier `turtlemeck` remains in repository paths, the app bundle, executable names, and system-facing identifiers.

## Current Product Documentation

### App

- [Menu bar](menu-bar.md) — Status icon, popover, quick actions, and today's summary
- [Baseline calibration and posture checks](posture-checks.md) — First launch, calibration, scheduled and immediate checks, and state transitions
- [Settings](settings.md) — Every user setting and the behavior it changes
- [Notifications](notifications.md) — Banners and sounds, repeat limits, and the 20-minute snooze
- [Privacy and local data](privacy.md) — Camera and notification permissions, stored data, and debug and local-mode exceptions

### For Developers

- [Architecture](architecture.md) — App structure, composition root, analysis flow, stores, and platform integrations
- [Debugging](debugging.md) — Local builds and runs, the debug window, environment variables, and build artifacts

## Adopted Technical Documentation

- [Posture analysis workflow](workflow.md) — Korean specification for the product flow and decision rules implemented by the current code
- [Posture analysis implementation decisions](posture-analysis/README.md) — Korean record of module boundaries, tuning values, and device validation reflected in the implementation
- [Adopted algorithm research](algorithm/README.md) — Korean analysis supporting the selected PoseNet, Vision 2D, ROI, and baseline approach
- [Adopted depth-estimation research](depth-estimation/README.md) — Korean analysis supporting Depth Anything V2 and the relative-depth feature

These documents describe the adopted path or its supporting evidence.
When detailed research and the workflow disagree, the workflow specification takes precedence.

## Research Archive (Korean Only)

- [Research archive](research/) — Investigations, unselected alternatives, and historical reviews that are not part of the current product contract

Archived research can explain why an alternative was considered or rejected, but it does not define current behavior.
