---
allowed-tools: Bash, Read, Glob, Grep, Write
description: Detect and analyze tracker/analytics SDKs in decompiled Android sources
user-invocable: true
argument-hint: <path to decompiled sources directory>
argument: path to decompiled sources directory (optional)
---

# /find-trackers

Detect and analyze analytics/tracker SDKs in a decompiled Android app.

## Instructions

You are starting the tracker analysis workflow. Follow these steps:

### Step 1: Get the source directory

If the user provided a path as an argument, use that. Otherwise, ask the user for the path to the decompiled sources directory.

If no decompiled sources exist yet, tell the user to run `/decompile` first on their APK/XAPK file.

Verify the directory exists and contains `.java` or `.kt` files:

```bash
find "$SOURCE_DIR" -name "*.java" -o -name "*.kt" | head -5
```

### Step 2: Run broad detection

Execute the tracker detection script to sweep for all known tracker SDKs:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/tracker-analysis/scripts/find-trackers.sh "$SOURCE_DIR" --all
```

Parse the output — non-empty sections indicate a detected SDK.

### Step 3: Analyze each detected SDK

For each SDK found in the sweep, perform deep analysis:

1. **Read the initialization code** — find where the SDK is set up, extract API keys/app IDs
2. **Catalog tracked events** — list all event names and their parameters
3. **Check user identification** — find setUserId/identify calls, what user data is collected
4. **Verify consent handling** — check if the app gates analytics on user consent
5. **Identify data endpoints** — known domains and any custom relay/proxy

Use the reference documents in `${CLAUDE_PLUGIN_ROOT}/skills/tracker-analysis/references/` for SDK-specific patterns.

### Step 4: Produce report

Generate a structured report with:
- **Summary table**: SDK name, init location, event count, user ID method, consent status
- **Per-SDK detail**: initialization, events, user data, consent, endpoints
- **Privacy summary**: total SDKs, consent coverage, user data shared, endpoint domains

Refer to `${CLAUDE_PLUGIN_ROOT}/skills/tracker-analysis/SKILL.md` for the full report format.

### Step 5: Offer next steps

Tell the user what they can do next:
- **Deep-dive a specific SDK**: "I can trace the full data flow for Firebase Analytics"
- **Check data exfiltration**: "I can search for proxy/relay patterns and custom endpoints"
- **Analyze ad SDKs**: "Run `/find-ads` to analyze advertising SDKs too"
- **Export report**: "I can save this report as a markdown file"
