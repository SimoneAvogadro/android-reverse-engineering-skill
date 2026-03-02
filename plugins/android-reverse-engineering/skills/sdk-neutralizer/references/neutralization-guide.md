# SDK Neutralization Guide

## Overview

SDK neutralization replaces the bodies of tracker/ad SDK methods with stub instructions that effectively disable them. This is the safest bytecode-level approach because:

1. **Stub > Class removal** — Removing classes causes `ClassNotFoundException` at runtime. Stubbing preserves the class structure; methods simply do nothing when called.
2. **Stub > Network blocking** — Network-level blocking (iptables, hosts file) doesn't prevent local data collection and may cause SDK retry loops that drain battery.
3. **Entry points only** — We patch only the methods called by app code (init, track, show), not internal SDK wiring. This minimizes breakage surface.

## Smali Stub Reference

### Return Type to Stub Mapping

| Return Type | Descriptor | Stub Code | Registers |
|---|---|---|---|
| void | `V` | `return-void` | 1 |
| boolean | `Z` | `const/4 v0, 0x0` + `return v0` | 1 |
| int | `I` | `const/4 v0, 0x0` + `return v0` | 1 |
| short | `S` | `const/4 v0, 0x0` + `return v0` | 1 |
| byte | `B` | `const/4 v0, 0x0` + `return v0` | 1 |
| char | `C` | `const/4 v0, 0x0` + `return v0` | 1 |
| float | `F` | `const/4 v0, 0x0` + `return v0` | 1 |
| long | `J` | `const-wide/16 v0, 0x0` + `return-wide v0` | 2 |
| double | `D` | `const-wide/16 v0, 0x0` + `return-wide v0` | 2 |
| Object (`L...;`) | `L` | `const/4 v0, 0x0` + `return-object v0` | 1 |
| Array (`[...`) | `[` | `const/4 v0, 0x0` + `return-object v0` | 1 |

### Stub Format

```smali
.method public methodName(Ljava/lang/String;)V
    .registers 1

    return-void
.end method
```

For object returns (returns null):
```smali
.method public static getInstance(Landroid/content/Context;)Lcom/example/Sdk;
    .registers 1

    const/4 v0, 0x0

    return-object v0
.end method
```

## Special Cases

### Singleton `getInstance()` returning null

When a stubbed `getInstance()` returns null, any subsequent method call on the result will throw `NullPointerException`. This is generally acceptable because:

- The NPE is caught by standard try-catch blocks in well-written app code
- If the app crashes, it indicates tight coupling that requires manual intervention
- Alternative: stub all methods on the singleton class too (neutralize.sh does this)

### Callback-dependent methods (Rewarded Ads)

Rewarded ad SDKs call back via listener when a reward is earned. Stubbing `show()` means:
- The reward callback is never invoked
- If the app gates content behind the reward, the user cannot proceed
- Mitigation: the app should handle the "ad not available" case already

### Firebase coupling

Firebase Analytics is often initialized via a `ContentProvider` that runs before `Application.onCreate()`. Stubbing `getInstance()` and `logEvent()` is sufficient — the auto-init still runs but collected data goes nowhere when `logEvent` is a no-op.

`setAnalyticsCollectionEnabled(false)` can also be called in the stub to explicitly disable collection at the API level.

### ContentProvider auto-init

Some SDKs (Firebase, Facebook, WorkManager) use `ContentProvider` for auto-initialization. Disabling the provider in the manifest (`android:enabled="false"`) prevents auto-init without removing the class.

## Manifest Patching

### `android:enabled="false"` vs Removal

- **Disable** (`android:enabled="false"`): The component remains declared but the system does not instantiate it. This preserves the XML structure and avoids manifest merge errors during rebuild.
- **Remove**: Deleting the XML element entirely. Risk of resource reference errors if other parts of the manifest or code reference the component.

**Recommendation**: Always disable, never remove.

### Component Types

| Type | Effect of Disabling |
|---|---|
| `<activity>` | Cannot be launched via Intent; ad fullscreen activities won't show |
| `<service>` | Service cannot start; background telemetry upload stops |
| `<receiver>` | Broadcast receiver does not fire; install referrer, BOOT_COMPLETED handlers disabled |
| `<provider>` | ContentProvider not initialized; auto-init SDKs disabled |

## Pitfalls

### Multidex

APKs with multidex have multiple smali directories: `smali/`, `smali_classes2/`, `smali_classes3/`, etc. The neutralization script scans all `smali*` directories to handle this.

### Native `.so` integrity checks

Some SDKs (particularly ad SDKs like AdMob, IronSource) include native libraries that perform integrity checks. These cannot be patched at the smali level. If the native code detects tampering:
- The SDK may silently disable itself (acceptable)
- The SDK may crash (rare, but requires manual `.so` removal or stubbing of the JNI bridge)

### R8/ProGuard obfuscation

If the APK was built with R8 or ProGuard, SDK class names are obfuscated (e.g., `Lcom/google/android/gms/ads/MobileAds;` becomes `La/b/c;`). In this case:
- The standard target list will not match
- Use `find-ads.sh --entrypoints` and `find-trackers.sh --entrypoints` on the decoded smali to identify obfuscated calls
- Use `--targets-file` with manually identified class:method pairs
- String constants (SDK keys, endpoint URLs) are usually not obfuscated and can help identify the SDK

### Signature invalidation

Rebuilding the APK invalidates the original signature. Consequences:
- **Play Integrity / SafetyNet**: Will fail. Apps that check integrity at runtime may refuse to run.
- **Signature-based permissions**: `android:protectionLevel="signature"` permissions will not be granted.
- **App updates**: The neutralized APK cannot update from the Play Store version (different signing key).

This is acceptable for enterprise sideloading where the modified APK is distributed via MDM.

## Legal Disclaimer

SDK neutralization for enterprise deployment is supported by:

- **EU Software Directive 2009/24/EC** Art. 5-6: Permits decompilation for interoperability and error correction
- **GDPR Art. 5(1)(c)** (data minimisation): Supports removing unnecessary data collection from enterprise-distributed apps
- **US DMCA §1201(f)**: Permits reverse engineering for interoperability

**This tool is intended for authorized enterprise use only.** The user is solely responsible for ensuring compliance with:
- Software license agreements of the modified app
- Terms of service of the SDK providers
- Applicable local and international laws
- Internal enterprise security and compliance policies

The authors provide this tool for legitimate security research, privacy compliance, and authorized enterprise deployment. Any use for piracy, circumvention of digital rights management for unauthorized purposes, or distribution of modified apps without authorization is strictly prohibited.
