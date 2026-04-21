---
description: 'Android reverse engineering with jadx and Fernflower — decompile APK/JAR/AAR, extract Retrofit/OkHttp APIs, trace call flows'
applyTo: '**/*.{apk,xapk,jar,aar}'
---

# Android Reverse Engineering

Decompile Android packages using jadx (broad coverage) or Fernflower/Vineflower (higher quality Java).

## Commands

```bash
# Check dependencies
bash plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/check-deps.sh

# Install missing dependency
bash plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/install-dep.sh <dep>

# Decompile
bash plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/decompile.sh app.apk
bash plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/decompile.sh --engine both --deobf app.apk

# Find API calls
bash plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/find-api-calls.sh output/sources/
bash plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/find-api-calls.sh output/sources/ --retrofit
bash plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/find-api-calls.sh output/sources/ --urls
```

## Workflow

1. Verify dependencies → `check-deps.sh`
2. Decompile → `decompile.sh` (jadx, fernflower, or both)
3. Analyze AndroidManifest.xml and package structure
4. Trace call flows from Activities → ViewModels → Repositories → API calls
5. Extract and document APIs → `find-api-calls.sh`

## References

See `plugins/android-reverse-engineering/skills/android-reverse-engineering/references/` for detailed guides.
