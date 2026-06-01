# Budget Tracker — agent entry

**Canonical rules:** [`AI_PROJECT_INSTRUCTIONS.txt`](AI_PROJECT_INSTRUCTIONS.txt)  
**Which doc when:** [`ai/DOCUMENTATION_MAP.md`](ai/DOCUMENTATION_MAP.md) ← open this if unsure

## Read order

1. `AI_PROJECT_INSTRUCTIONS.txt` — product, security, release (Update Log here)
2. `LESSONS_LEARNED.md` — resolved bugs (**read before fix**, append after)
3. `docs/PROJECT_BRIEF.md` — full spec
4. `docs/ai/writing-guide.md` — commands, TDD, `Backend/` layout
5. `ai/features/<area>.md` — **apply when** your edit matches that file’s code map
6. `docs/ai/go-bys/<topic>.md` — **apply when** implementing a similar pattern
7. `Config/SECRETS.local.md` (gitignored)

## Write routing (quick)

| You did | Update |
|---------|--------|
| Fixed a bug | `LESSONS_LEARNED.md` |
| New rule / shipped behavior | `AI_PROJECT_INSTRUCTIONS.txt` → Update Log |
| New command or convention | `docs/ai/writing-guide.md` |
| New files in a feature | `ai/features/<area>.md` |
| New copyable pattern | `docs/ai/go-bys/` + `ai/README.md` |

**Sibling (patterns only):** `../Optimized/` · **Shared CI:** `../ios-build/`

**Cursor:** Open this repo root. Rules listed in `ai/DOCUMENTATION_MAP.md` § Cursor rules.

**Before TestFlight:** Update and show `canvases/budget-tracker-preview.canvas.tsx` (see `AI_PROJECT_INSTRUCTIONS.txt` §2c).
