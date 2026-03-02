# Tracker SDK Catalog

Quick-reference for detecting analytics/tracker SDKs in decompiled Android apps.

## Firebase Analytics

| Field | Value |
|---|---|
| **Package** | `com.google.firebase.analytics` |
| **Key classes** | `FirebaseAnalytics`, `AppMeasurement`, `AppMeasurementService` |
| **Manifest markers** | `<service android:name="com.google.android.gms.measurement.AppMeasurementService"/>`, `<receiver android:name="com.google.android.gms.measurement.AppMeasurementReceiver"/>` |
| **Gradle** | `com.google.firebase:firebase-analytics` |
| **Grep detection** | `FirebaseAnalytics\.getInstance\|AppMeasurement\|app-measurement\.com` |

## Adjust

| Field | Value |
|---|---|
| **Package** | `com.adjust.sdk` |
| **Key classes** | `Adjust`, `AdjustConfig`, `AdjustEvent`, `AdjustAttribution` |
| **Manifest markers** | `<receiver android:name="com.adjust.sdk.AdjustReferrerReceiver"/>` |
| **Gradle** | `com.adjust.sdk:adjust-android` |
| **Grep detection** | `AdjustConfig\|AdjustEvent\|Adjust\.trackEvent\|Adjust\.onCreate` |

## AppsFlyer

| Field | Value |
|---|---|
| **Package** | `com.appsflyer` |
| **Key classes** | `AppsFlyerLib`, `AppsFlyerConversionListener`, `AFInAppEventType` |
| **Manifest markers** | `<receiver android:name="com.appsflyer.SingleInstallBroadcastReceiver"/>`, `<service android:name="com.appsflyer.AppsFlyerJobIntentService"/>` |
| **Gradle** | `com.appsflyer:af-android-sdk` |
| **Grep detection** | `AppsFlyerLib\.getInstance\|AFInAppEventType\|appsflyer\.com` |

## Mixpanel

| Field | Value |
|---|---|
| **Package** | `com.mixpanel.android` |
| **Key classes** | `MixpanelAPI`, `AnalyticsMessages`, `DecideMessages` |
| **Manifest markers** | `<service android:name="com.mixpanel.android.mpmetrics.MixpanelFCMMessagingService"/>` |
| **Gradle** | `com.mixpanel.android:mixpanel-android` |
| **Grep detection** | `MixpanelAPI\.getInstance\|com\.mixpanel\.android\|api\.mixpanel\.com` |

## Amplitude

| Field | Value |
|---|---|
| **Package** | `com.amplitude.api` (v2), `com.amplitude.android` (v1) |
| **Key classes** | `Amplitude`, `AmplitudeClient`, `Revenue`, `Identify` |
| **Manifest markers** | (none specific — uses standard Android components) |
| **Gradle** | `com.amplitude:analytics-android` (v2), `com.amplitude:android-sdk` (v1) |
| **Grep detection** | `Amplitude\.getInstance\|AmplitudeClient\|api\.amplitude\.com` |

## Segment

| Field | Value |
|---|---|
| **Package** | `com.segment.analytics` |
| **Key classes** | `Analytics`, `TrackPayload`, `IdentifyPayload`, `ScreenPayload`, `Traits` |
| **Manifest markers** | (none specific) |
| **Gradle** | `com.segment.analytics.android:analytics` |
| **Grep detection** | `Analytics\.with\|com\.segment\.analytics\|api\.segment\.io` |

## Braze (formerly Appboy)

| Field | Value |
|---|---|
| **Package** | `com.braze` (v4+), `com.appboy` (legacy) |
| **Key classes** | `Braze`, `BrazeConfig`, `BrazeUser`, `BrazeProperties`; legacy: `Appboy`, `AppboyConfig` |
| **Manifest markers** | `<service android:name="com.braze.push.BrazeFirebaseMessagingService"/>`, `com.braze.BrazeActivityLifecycleCallbackListener` |
| **Gradle** | `com.braze:android-sdk-ui` |
| **Grep detection** | `Braze\.configure\|BrazeConfig\|logCustomEvent\|com\.braze\.\|com\.appboy\.` |

## CleverTap

| Field | Value |
|---|---|
| **Package** | `com.clevertap.android.sdk` |
| **Key classes** | `CleverTapAPI`, `ActivityLifecycleCallback` |
| **Manifest markers** | `<meta-data android:name="CLEVERTAP_ACCOUNT_ID"/>`, `<service android:name="com.clevertap.android.sdk.pushnotification.fcm.FcmMessageListenerService"/>` |
| **Gradle** | `com.clevertap.android:clevertap-android-sdk` |
| **Grep detection** | `CleverTapAPI\.getDefaultInstance\|pushEvent\|onUserLogin\|wzrkt\.com` |

## Flurry

| Field | Value |
|---|---|
| **Package** | `com.flurry.android` |
| **Key classes** | `FlurryAgent`, `FlurryConfig`, `FlurryPerformance` |
| **Manifest markers** | `<service android:name="com.flurry.android.agent.FlurryService"/>` |
| **Gradle** | `com.flurry.android:analytics` |
| **Grep detection** | `FlurryAgent\.logEvent\|FlurryAgent\.Builder\|data\.flurry\.com` |
