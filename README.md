# Budget Tracker (iOS)

Personal budget app: Plaid sync, Supabase backend, Gemini categorization.

**Agent entry point:** [`AGENTS.md`](AGENTS.md) · **Which doc when:** [`ai/DOCUMENTATION_MAP.md`](ai/DOCUMENTATION_MAP.md)

1. [`AI_PROJECT_INSTRUCTIONS.txt`](AI_PROJECT_INSTRUCTIONS.txt) — living rules and update log  
2. [`LESSONS_LEARNED.md`](LESSONS_LEARNED.md) — resolved bugs (append after each fix)  
3. [`docs/PROJECT_BRIEF.md`](docs/PROJECT_BRIEF.md) — full spec and build phases  
4. [`docs/ai/writing-guide.md`](docs/ai/writing-guide.md) — commands, layout, TDD  
5. [`ai/features/`](ai/features/) — per-feature instructions  
6. [`docs/ai/go-bys/`](docs/ai/go-bys/) — implementation examples  
7. [`Config/SECRETS.local.md`](Config/SECRETS.local.md) (gitignored) — credentials  

**Cursor:** `.cursor/rules/` (auto-loaded scoped rules)

**Sibling reference app:** `../Optimized/` (fitness) — reuse patterns, not Supabase project or bundle IDs.

## Quick start (Windows)

1. Copy `Config/LocalAPIKeys.plist.example` → `Config/LocalAPIKeys.plist` and fill Supabase + Gemini keys for Simulator.
2. Install Supabase CLI (see project brief), then:
   ```powershell
   supabase login --token <YOUR_PAT>
   supabase link --project-ref dldbcbituquxedlkeefu
   .\scripts\deploy-backend.ps1
   .\scripts\test-plaid-sandbox.ps1
   ```
3. Push to GitHub and run **Verify compile** workflow (`workflow_dispatch`).

## Backend layout

- `supabase/migrations/` — additional tables + Plaid Vault helpers
- `supabase/functions/` — four Plaid Edge Functions (no secrets on iOS)
- `scripts/test-plaid-sandbox.ps1` — Sandbox smoke test

## iOS layout

- `project.yml` — XcodeGen source of truth
- `BudgetTracker/Backend/` — auth, Supabase, finance logic
- `BudgetTracker/Views/` — SwiftUI tabs and feature shells

