# Tahap 4 Completion Implementation Plan

Goal: implement all approved Tahap 1 requirements for synthetic local coursework and verify the eight Tahap 4 outputs. User authorized autonomous execution and focused parallel agents.

Architecture: retain the current Flutter repository API while hardening the local backend and adding independent nutrition, growth, dashboard and security modules. Integrate in one local branch with ownership boundaries; preserve existing dirty work. No external runtime services or freeRASP telemetry. Actual Android results remain pending user execution.

Spec: ../../../../../Pertemuan 6/Tahap 1 Penentuan Topik dan Analisis Kebutuhan.txt and ../../../../../Pertemuan 8/Pelacakan_Kebutuhan_Tahap_4.md.

## Work ownership and verification

- [ ] sync_backend: server_local, repository, session, full-sync/transports and focused tests; pagination, retries, conflicts, migration, role/session validation and government aggregate-only access.
- [ ] nutrition_kms: new nutrition/KMS modules, primary official sources, age boundaries, PMT triage and growth/reference curves with accessible tables. No claim of clinical validation.
- [ ] dashboard_export: government-only aggregate adapter, interactive charts/map/priority table, PDF/Excel and save/share verification.
- [ ] root: SQLite/encryption migration, native offline security/share, main UI integration, regression and independent review.
- [ ] root: browser workflow tests with isolated profiles and synthetic data, export/render checks, performance/load tests, candidate APK build/signature/dedup.
- [ ] root: update scenarios/results/bugs/fixes/user-testing status and checkpoint; report any remaining genuine blockers before claiming completeness.

## Constraints

Dummy data only. Keep services on loopback. No external telemetry. New installation requires prior user approval; user approved existing Flutter/export/security/notification dependencies and Chromium, then sqflite/sembast_sqflite and verified migration. Do not delete historical proofs, reset dirty changes or push GitHub. Report build overwrite/dedup. Android runtime validation cannot be invented.

## Review focus

Lost ACK and concurrent changes must not lose local state. Government exports must not leak identities. Corrections must not double-count growth or aggregation. Corrupted encryption or missing keys must fail without resetting data. PMT/AKG must use cited official age-specific guidance and distinguish references from treatment. No native-security bypass should be presented as production hardening.
