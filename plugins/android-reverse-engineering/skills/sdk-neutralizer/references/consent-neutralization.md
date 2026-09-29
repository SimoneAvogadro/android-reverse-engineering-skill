# Consent Neutralization (IAB TCF / Google UMP) — code injection

This is a **distinct capability** from ordinary SDK stubbing. Ordinary neutralization
replaces a method body with a trivial no-op (`return-void`, `return 0`, `return null`).
Consent neutralization **injects real code**: it makes the app behave as if the user
opened the consent dialog and pressed **"Reject all"** — without ever showing the dialog —
by writing a reject-all IAB TCF v2.2 consent state to storage and driving the UMP callbacks.

## Why this matters

Many apps use **Google UMP** (User Messaging Platform) with the **IAB TCF v2.2** framework
(the *"…asks for your consent… / Manage options"* dialog). UMP and the CMP write the user's
choices to a small set of `IABTCF_*` keys in **SharedPreferences**. Every TCF-honoring ad and
tracker SDK **reads those keys** and self-limits accordingly (no personalized ads, no data
sharing) when consent is absent.

In the Subway Surfers 3.69.2 test app, **28 classes across 13 SDKs** read `IABTCF_*`
(AppLovin, Pangle, Fyber, Google Ads/measurement, InMobi, ironSource, Mintegral, Moloco,
Unity, Vungle, BidMachine, kpadplayer, com.sybo.ads). Highest read counts: `IABTCF_TCString`
(40), `IABTCF_gdprApplies` (36), `IABTCF_AddtlConsent` (13), `IABTCF_PurposeConsents` (12),
`IABTCF_VendorConsents` (5).

So instead of neutralizing each of those 13 SDKs' consent readers, we write a single,
authoritative **reject-all** consent state that they all honor. This **complements** — it does
not replace — SDK neutralization: SDKs that ignore TCF (Firebase Analytics, Singular, etc.)
still need their own registry entries.

## Where the consent state is really stored

Per the IAB *CMP in-app* spec, the CMP must store `IABTCF_*` in the app's **default**
SharedPreferences: `PreferenceManager.getDefaultSharedPreferences(context)` →
`<data>/shared_prefs/<package>_preferences.xml`.

Verified in the test app (UMP `user-messaging-platform@@4.0.0`):

- **Writer**: `com.google.android.gms.internal.consent_sdk.zzco` calls
  `android.preference.PreferenceManager.getDefaultSharedPreferences(Context)` (and
  `zzdw` writes `IABTCF_TCString` / `IABTCF_gdprApplies`). *(The `zzaq` helper reads
  request-info from arbitrary named files and keeps its own bookkeeping in the private file
  `__GOOGLE_FUNDING_CHOICE_SDK_INTERNAL__`; the canonical `IABTCF_*` values live in the
  default prefs.)*
- **Readers**: e.g. `com.vungle.ads.internal.privacy.PrivacyManager` and
  `com.kpadplayer.sdk.consent.ConsentUtil` both call
  `PreferenceManager.getDefaultSharedPreferences(context)`.

So the injected code writes to **`getDefaultSharedPreferences`** — byte-for-byte the store the
CMP and every reader use.

## Interception point

The reject-all prefs are written by the **injected bodies of two methods**, so the reject-all
state is written whichever UMP call pattern the app uses. **Both must be present** for the
write to happen — if neither is (see the residual limitation in Caveats), the entry is a safe
no-op and writes nothing.

- **Primary, near-universal hook**: `requestConsentInfoUpdate(Activity, ConsentRequestParameters, OnConsentInfoUpdateSuccessListener, OnConsentInfoUpdateFailureListener)` on the concrete `ConsentInformation` impl — this is the **first UMP call every integration makes**, before either the combined helper or the separate `loadConsentForm`/`ConsentForm.show` pattern. The injected body **writes the reject-all prefs** (from the Activity param, null-guarded) **then fires the success listener** (no network) so the app's consent flow continues. Because it runs first and on every pattern, it is the main place the reject-all state is written.
- **Secondary hook (combined helper)**: `com.google.android.ump.UserMessagingPlatform.loadAndShowConsentFormIfRequired(Activity, ConsentForm$OnConsentFormDismissedListener)` — a **static void** method on a stable public class. Its real body checks `canRequestAds()` and otherwise loads and shows the form. We replace the body with: **write reject-all prefs (again, identical key set) → call the dismiss listener `onConsentFormDismissed(null)` → return**. This covers apps that use the combined helper and re-asserts the state right before any form would show.
- `com.google.android.ump.ConsentForm.show(Activity, ...)` and `ConsentForm.OnConsentFormDismissedListener` are **interfaces** (abstract, no body) — they cannot be stubbed directly, and the concrete `ConsentForm` impl is obfuscated. Apps using the separate `loadConsentForm(...)` + `ConsentForm.show(...)` pattern (no combined helper) still get the reject-all state from the `requestConsentInfoUpdate` write, and `canRequestAds`/`getConsentStatus` are handled below so the form is not required.

Both injected writers use the **identical key set** (a shared emitter in neutralize.sh).

### Callback-aware handling (so the app doesn't loop or stall)

The concrete `ConsentInformation` implementation (obfuscated `com.google.android.gms.internal.consent_sdk.zzj` in UMP 4.0.0) is targeted:

- `requestConsentInfoUpdate(...)` → inject **write reject-all prefs + fire the success listener** immediately (`onConsentInfoUpdateSuccess()`), no network (see above). The Activity is the first param and is `@Nullable`, so the pref-write is null-guarded; the success listener fires either way.
- `canRequestAds()` → **return true** (`return-const-1`). The app initializes ads, which then self-limit under the reject-all TCF state (and can be neutralized separately).
- `getConsentStatus()` → **return OBTAINED = 3** (`return-const-3`). The app treats consent as *completed/handled* and never re-shows the form. `ConsentStatus` values (verified): `UNKNOWN=0, NOT_REQUIRED=1, REQUIRED=2, OBTAINED=3`.

**OBTAINED vs NOT_REQUIRED**: OBTAINED is coherent with `gdprApplies=1` + a recorded reject-all
choice ("the user finished the flow and rejected"). NOT_REQUIRED would claim GDPR does not
apply, contradicting `gdprApplies=1`, and some apps then skip writing/using the TCF data. We
choose **OBTAINED**.

Protected (never stubbed): `getConsentInformation`, `getPrivacyOptionsRequirementStatus`,
`isConsentFormAvailable`, `reset`, `getApplicationContext` — object/state getters whose
`null`/altered return would NPE or desync the app.

> The concrete `zzj` class name is **obfuscated and version-specific** — and, importantly, the
> pref-write on the near-universal `requestConsentInfoUpdate` hook lives on this class. The
> stable `UserMessagingPlatform.loadAndShowConsentFormIfRequired` write only covers apps that
> use the combined helper, so do **not** treat it as self-sufficient. neutralize.sh
> **signature-guards** the injections (`SKIP_INJECT:` on mismatch), and a class that is absent
> simply matches nothing — both are harmless, but a renamed/absent `zzj` means the
> `requestConsentInfoUpdate` write does not happen. For a different UMP version, find the class
> implementing `com.google.android.ump.ConsentInformation` and update the class name in
> `registry/consent-umptcf.json`.

## The reject-all values written

To `getDefaultSharedPreferences`, via an `Editor` (`apply()`):

| Key | Type | Value | Meaning |
|---|---|---|---|
| `IABTCF_gdprApplies` | int | `1` | **Always 1** (even outside the EU) so SDKs enforce TCF |
| `IABTCF_CmpSdkID` | int | `300` | Google UMP's registered CMP id — signals "a CMP is present & values are valid" |
| `IABTCF_CmpSdkVersion` | int | `1` | CMP version |
| `IABTCF_PolicyVersion` | int | `4` | TCF v2.2 policy version |
| `IABTCF_PurposeOneTreatment` | int | `0` | No special treatment for purpose 1 |
| `IABTCF_TCString` | string | *(see below)* | Reject-all TCF v2.2 core string |
| `IABTCF_AddtlConsent` | string | `1~` | Google Additional Consent v2 — **no** additional vendors |
| `IABTCF_PurposeConsents` | string | `000000000000000000000000` | No purpose consent (all 24 zero) |
| `IABTCF_PurposeLegitimateInterests` | string | `000000000000000000000000` | **Object to all** legitimate interest |
| `IABTCF_VendorConsents` | string | `0` | No vendor consent |
| `IABTCF_VendorLegitimateInterests` | string | `0` | Object to all vendor legitimate interest |
| `IABTCF_SpecialFeaturesOptIns` | string | `000000000000` | No special-feature opt-in |
| `IABTCF_PublisherCC` | string | `AA` | Publisher country (neutral) |

**Belt and suspenders**: some SDKs decode the `IABTCF_TCString`; others read the individual
canonical keys. We write **both**, all set to reject-all.

**Crash safety of the binary-string keys**: readers index these strings by purpose/vendor id
(`charAt(id-1)`). The reader SDKs in the test app (Fyber, Mintegral, Google measurement, …)
**length-check before `charAt`**, so a short/all-zero string is treated as "no consent" for
out-of-range ids rather than throwing. Legitimate-interest objection is expressed the same way
(all-zero LI keys = the user objected to every LI purpose/vendor).

## The reject-all TCString (IAB TCF v2.2)

```
COsdsoAOsdsoAEsABAENAAEgAAAAAAAAAAAAAAAAAAAA
```

Core-string fields (Version=2 ⇒ leading `C`), all consent/LI bits zero:

- `Version=2`, `TcfPolicyVersion=4` (TCF v2.2), `CmpId=300`, `CmpVersion=1`
- `SpecialFeatureOptIns=0`, `PurposesConsent=0`, `PurposesLITransparency=0`, `PurposeOneTreatment=0`
- `MaxVendorId=0` for both the consent and legitimate-interest vendor sections (bitfield encoding, 0 vendors) ⇒ no vendor granted
- `IsServiceSpecific=1`, `ConsentLanguage="EN"`, `PublisherCC="AA"`
- `Created`/`LastUpdated` are a fixed timestamp (cosmetic; does not affect consent)

### Generation and verification

The string was generated and **decoded back** to prove every consent + legitimate-interest bit
is zero. The self-contained generator/verifier:

```python
import base64
FIELDS = [
    ("Version",6,2),("Created",36,15778368000),("LastUpdated",36,15778368000),
    ("CmpId",12,300),("CmpVersion",12,1),("ConsentScreen",6,0),
    ("ConsentLanguageChar1",6,4),("ConsentLanguageChar2",6,13),   # 'E','N'
    ("VendorListVersion",12,0),("TcfPolicyVersion",6,4),
    ("IsServiceSpecific",1,1),("UseNonStandardTexts",1,0),
    ("SpecialFeatureOptIns",12,0),("PurposesConsent",24,0),
    ("PurposesLITransparency",24,0),("PurposeOneTreatment",1,0),
    ("PublisherCCChar1",6,0),("PublisherCCChar2",6,0),            # 'A','A'
    ("MaxVendorIdConsent",16,0),("IsRangeEncodingConsent",1,0),
    ("MaxVendorIdLI",16,0),("IsRangeEncodingLI",1,0),
    ("NumPubRestrictions",12,0),
]
bits = "".join(format(v, "0{}b".format(n)) for _, n, v in FIELDS)
bits += "0" * (-len(bits) % 8)
b = bytes(int(bits[i:i+8], 2) for i in range(0, len(bits), 8))
print(base64.urlsafe_b64encode(b).decode().rstrip("="))
# -> COsdsoAOsdsoAEsABAENAAEgAAAAAAAAAAAAAAAAAAAA
```

Decoding it back yields `PurposesConsent=0`, `PurposesLITransparency=0`,
`SpecialFeatureOptIns=0`, `MaxVendorId(consent)=0`, `MaxVendorId(LI)=0`, `CmpId=300`,
`TcfPolicyVersion=4` — i.e. a valid reject-all.

## The injected smali (short)

`UserMessagingPlatform.loadAndShowConsentFormIfRequired` (static; `p0`=Activity,
`p1`=listener). `.registers 5` = 3 locals (`v0`,`v1`,`v2`) + 2 param slots (`p0`=v3, `p1`=v4),
so locals never collide with params:

```smali
    .registers 5

    invoke-virtual {p0}, Landroid/app/Activity;->getApplicationContext()Landroid/content/Context;
    move-result-object v0
    invoke-static {v0}, Landroid/preference/PreferenceManager;->getDefaultSharedPreferences(Landroid/content/Context;)Landroid/content/SharedPreferences;
    move-result-object v0
    invoke-interface {v0}, Landroid/content/SharedPreferences;->edit()Landroid/content/SharedPreferences$Editor;
    move-result-object v0

    const-string v1, "IABTCF_gdprApplies"
    const/4 v2, 0x1
    invoke-interface {v0, v1, v2}, Landroid/content/SharedPreferences$Editor;->putInt(Ljava/lang/String;I)Landroid/content/SharedPreferences$Editor;
    # ... IABTCF_CmpSdkID=300, PolicyVersion=4, PurposeOneTreatment=0 (putInt) ...
    # ... IABTCF_TCString, AddtlConsent, Purpose/Vendor/SpecialFeatures, PublisherCC (putString) ...

    invoke-interface {v0}, Landroid/content/SharedPreferences$Editor;->apply()V

    if-eqz p1, :cond_ump_done
    const/4 v1, 0x0
    invoke-interface {p1, v1}, Lcom/google/android/ump/ConsentForm$OnConsentFormDismissedListener;->onConsentFormDismissed(Lcom/google/android/ump/FormError;)V
    :cond_ump_done
    return-void
```

`Editor.putInt/putString` return the `Editor`; the return is ignored and the original `v0`
reference (mutated in place) is reused for the next call — valid dalvik. `p1` is null-checked
before the interface call.

`requestConsentInfoUpdate` (instance; `p1`=Activity `@Nullable`, success listener = `p3`),
`.registers 8` = 3 locals (`v0`,`v1`,`v2` for the pref-write) + this + 4 params
(`p1`=v4, `p3`=v6). Writes the reject-all prefs (identical key set, via the shared emitter,
context from `p1`, null-guarded) then fires the success listener:

```smali
    .registers 8
    if-eqz p1, :cond_ump_nowrite
    invoke-virtual {p1}, Landroid/app/Activity;->getApplicationContext()Landroid/content/Context;
    move-result-object v0
    invoke-static {v0}, Landroid/preference/PreferenceManager;->getDefaultSharedPreferences(Landroid/content/Context;)Landroid/content/SharedPreferences;
    move-result-object v0
    invoke-interface {v0}, Landroid/content/SharedPreferences;->edit()Landroid/content/SharedPreferences$Editor;
    move-result-object v0
    # ... same IABTCF_* putInt/putString key set as consent-reject-all ...
    invoke-interface {v0}, Landroid/content/SharedPreferences$Editor;->apply()V
    :cond_ump_nowrite
    if-eqz p3, :cond_ump_ok
    invoke-interface {p3}, Lcom/google/android/ump/ConsentInformation$OnConsentInfoUpdateSuccessListener;->onConsentInfoUpdateSuccess()V
    :cond_ump_ok
    return-void
```

`canRequestAds()Z` / `getConsentStatus()I` (`return-const-1` / `return-const-3`):
`.registers = params+1`, `const/16 v0, 0x1` (or `0x3`) then `return v0`.

## How to run it

The kind travels on the target line as an optional **third** `:`-delimited field
(`<class>:<method>:<inject-kind>`). `registry-scan.py` emits it from the JSON `inject` field;
`neutralize.sh` performs the injection.

```bash
python3 registry-scan.py <decoded-dir> --registry <registry/> --depth 1 --category all --output-dir <decoded-dir>
# registry-targets.txt now contains, e.g.:
#   com/google/android/ump/UserMessagingPlatform:loadAndShowConsentFormIfRequired:consent-reject-all
bash neutralize.sh <decoded-dir> --no-builtin-targets \
  --targets-file <decoded-dir>/registry-targets.txt \
  --manifest-components-file <decoded-dir>/registry-manifest.txt
# emits PATCHED:...:consent-reject-all:... (or SKIP_INJECT:... on a signature mismatch)
```

## Caveats

- **Complements, not replaces, SDK neutralization.** Non-TCF SDKs (Firebase Analytics,
  Crashlytics, Singular, AppMetrica, …) ignore `IABTCF_*` and still need direct stubbing.
- **Reduces, does not guarantee zero, tracking.** A reject-all TCF state stops *compliant* SDKs
  from personalized ads / data sharing, but a non-compliant or non-TCF SDK may still collect
  data. Combine with per-SDK neutralization for the strongest result.
- **`gdprApplies=1` everywhere.** Setting it outside the EU is deliberate (maximum
  self-limiting). Because the form is suppressed *and* `getConsentStatus=OBTAINED` /
  `canRequestAds=true` are injected, the app cannot loop waiting for a form. If a specific app
  hard-requires the real UMP flow, drop the `canRequestAds`/`getConsentStatus` overrides (keep
  the pref-writes) and re-test.
- **Obfuscated concrete class.** The `com.google.android.gms.internal.consent_sdk.zzj` targets
  are version-specific; see the note above. Both the near-universal `requestConsentInfoUpdate`
  pref-write and the `canRequestAds`/`getConsentStatus` overrides live on this class.
- **Residual limitation — safe no-op if neither hook is present.** The pref-write is gated on
  the two injected methods being present. If a build has **neither** `requestConsentInfoUpdate`
  on a matched class (e.g. `zzj` renamed/absent in a different UMP version) **nor**
  `loadAndShowConsentFormIfRequired`, then **no** `IABTCF_*` is written — the entry is a safe
  no-op (it changes nothing). In that case re-identify the obfuscated `ConsentInformation` impl
  and update `registry/consent-umptcf.json`, or write the reject-all prefs from another hook.
  (Demonstrated: badpiggies-v2 has `loadConsentForm` but not `loadAndShowConsentFormIfRequired`,
  and its consent_sdk lacks the `zzj` targets → the whole entry correctly does nothing there.)
- **Other prefs files.** All readers checked use the default prefs. If a specific SDK reads
  `IABTCF_*` from a *non-default* named file, add a targeted write for that file.
