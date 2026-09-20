# 🛡️ Branch Protection Setup Guide

## Recommended Settings for Repository Owner Control

### Go to: GitHub Repository → Settings → Branches → Add Rule

**Rule for `main` branch**:
- Do not require the retired `Run Tests` status check. Remove it from existing branch protection or rulesets if configured; this repository now verifies changes locally.
- ✅ **Require pull request reviews before merging**
  - ✅ Required approving reviews: 1 (you)
  - ✅ Dismiss stale reviews when new commits are pushed
- ✅ **Require review from code owners** (optional)
- ✅ **Include administrators** (applies rules to you too - recommended)
- ❌ **Allow force pushes** (disabled for safety)
- ❌ **Allow deletions** (disabled for safety)

## Result
- Local build and test results are included in the pull request for code changes ✅
- YOU must manually approve ✅  
- YOU control all merges ✅
- No auto-merge capability ✅

## Optional: Create CODEOWNERS file
Create `.github/CODEOWNERS` with:
```
* @sahilsatralkar
```
This makes you the required reviewer for ALL changes.
