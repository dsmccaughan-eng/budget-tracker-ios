# GitHub usage policy (iOS apps)

Applies to **Optimized** and **Budget Tracker**. Shared copy from `Desktop/ios-build/docs/`.

## GitHub is for

- Source backup (`git push`)
- History, issues, PRs
- Optional: GitHub secrets for **Codemagic signing upload** workflow (ubuntu, no macOS minutes)

## GitHub is NOT for

- TestFlight uploads — use **Codemagic** (`codemagic.yaml`)
- macOS compile/archive on Actions runners (disabled / stub workflows)

## Windows daily loop

```powershell
cd C:\Users\dsmcc\Projects\Users\m1\Desktop\<AppFolder>
git add .
git commit -m "your message"
git push origin main
```

Then: `node scripts/validate-codemagic-prereqs.mjs` and `node scripts/trigger-codemagic-build.mjs` when shipping.

**Playbook:** `docs/CODEMAGIC.md` in each repo (synced from `ios-build`).

**Optional:** Xcode Cloud — see app-specific Xcode Cloud docs if enabled.
