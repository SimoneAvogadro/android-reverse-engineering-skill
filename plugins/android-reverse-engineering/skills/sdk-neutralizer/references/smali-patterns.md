# Smali Patterns Catalog

Complete reference of smali patterns for SDK neutralization. Each section shows the target class, methods, and the exact stub code injected.

## Ad SDK Patterns

### AdMob / Google Mobile Ads

**Class**: `Lcom/google/android/gms/ads/MobileAds;`

```smali
# Original: public static void initialize(Context, OnInitializationCompleteListener)
.method public static initialize(Landroid/content/Context;Lcom/google/android/gms/ads/initialization/OnInitializationCompleteListener;)V
    .registers 1

    return-void
.end method

# Original: public static void setRequestConfiguration(RequestConfiguration)
.method public static setRequestConfiguration(Lcom/google/android/gms/ads/RequestConfiguration;)V
    .registers 1

    return-void
.end method
```

**Class**: `Lcom/google/android/gms/ads/interstitial/InterstitialAd;`

```smali
# Original: public static void load(Context, String, AdRequest, InterstitialAdLoadCallback)
.method public static load(Landroid/content/Context;Ljava/lang/String;Lcom/google/android/gms/ads/AdRequest;Lcom/google/android/gms/ads/interstitial/InterstitialAdLoadCallback;)V
    .registers 1

    return-void
.end method
```

**Class**: `Lcom/google/android/gms/ads/rewarded/RewardedAd;`

```smali
# Original: public static void load(Context, String, AdRequest, RewardedAdLoadCallback)
.method public static load(Landroid/content/Context;Ljava/lang/String;Lcom/google/android/gms/ads/AdRequest;Lcom/google/android/gms/ads/rewarded/RewardedAdLoadCallback;)V
    .registers 1

    return-void
.end method
```

**Class**: `Lcom/google/android/gms/ads/AdView;`

```smali
# Original: public void loadAd(AdRequest)
.method public loadAd(Lcom/google/android/gms/ads/AdRequest;)V
    .registers 1

    return-void
.end method
```

### Unity Ads

**Class**: `Lcom/unity3d/ads/UnityAds;`

```smali
# Original: public static void initialize(Context, String, boolean, IUnityAdsInitializationListener)
.method public static initialize(Landroid/content/Context;Ljava/lang/String;ZLcom/unity3d/ads/IUnityAdsInitializationListener;)V
    .registers 1

    return-void
.end method

# Original: public static void load(String, IUnityAdsLoadListener)
.method public static load(Ljava/lang/String;Lcom/unity3d/ads/IUnityAdsLoadListener;)V
    .registers 1

    return-void
.end method

# Original: public static void show(Activity, String, IUnityAdsShowListener)
.method public static show(Landroid/app/Activity;Ljava/lang/String;Lcom/unity3d/ads/IUnityAdsShowListener;)V
    .registers 1

    return-void
.end method
```

### IronSource / LevelPlay

**Class**: `Lcom/ironsource/mediationsdk/IronSource;`

```smali
.method public static init(Landroid/app/Activity;Ljava/lang/String;)V
    .registers 1

    return-void
.end method

.method public static loadInterstitial()V
    .registers 1

    return-void
.end method

.method public static showInterstitial()V
    .registers 1

    return-void
.end method

.method public static showRewardedVideo()V
    .registers 1

    return-void
.end method

.method public static loadBanner(Landroid/app/Activity;Lcom/ironsource/mediationsdk/ISBannerSize;)V
    .registers 1

    return-void
.end method
```

### AppLovin / MAX

**Class**: `Lcom/applovin/sdk/AppLovinSdk;`

```smali
# Original: public static AppLovinSdk getInstance(Context) — returns null
.method public static getInstance(Landroid/content/Context;)Lcom/applovin/sdk/AppLovinSdk;
    .registers 1

    const/4 v0, 0x0

    return-object v0
.end method

# Original: public void initializeSdk()
.method public initializeSdk()V
    .registers 1

    return-void
.end method
```

### Meta Audience Network

**Class**: `Lcom/facebook/ads/AudienceNetworkAds;`

```smali
.method public static initialize(Landroid/content/Context;)V
    .registers 1

    return-void
.end method
```

### Vungle / Liftoff

**Class**: `Lcom/vungle/warren/Vungle;`

```smali
.method public static init(Ljava/lang/String;Landroid/content/Context;Lcom/vungle/warren/InitCallback;)V
    .registers 1

    return-void
.end method

.method public static loadAd(Ljava/lang/String;Lcom/vungle/warren/LoadAdCallback;)V
    .registers 1

    return-void
.end method

.method public static playAd(Ljava/lang/String;Lcom/vungle/warren/model/AdConfig;Lcom/vungle/warren/PlayAdCallback;)V
    .registers 1

    return-void
.end method
```

### InMobi

**Class**: `Lcom/inmobi/sdk/InMobiSdk;`

```smali
.method public static init(Landroid/content/Context;Ljava/lang/String;)V
    .registers 1

    return-void
.end method
```

### Chartboost

**Class**: `Lcom/chartboost/sdk/Chartboost;`

```smali
.method public static startWithAppId(Landroid/content/Context;Ljava/lang/String;Ljava/lang/String;)V
    .registers 1

    return-void
.end method

.method public static showInterstitial(Ljava/lang/String;)V
    .registers 1

    return-void
.end method

.method public static showRewardedVideo(Ljava/lang/String;)V
    .registers 1

    return-void
.end method

.method public static cacheInterstitial(Ljava/lang/String;)V
    .registers 1

    return-void
.end method
```

### Pangle / TikTok

**Class**: `Lcom/bytedance/sdk/openadsdk/TTAdSdk;`

```smali
.method public static init(Landroid/content/Context;Lcom/bytedance/sdk/openadsdk/TTAdConfig;)V
    .registers 1

    return-void
.end method
```

**Class**: `Lcom/pgl/sys/ces/PAGSdk;`

```smali
.method public static init(Lcom/pgl/sys/ces/PAGConfig;)V
    .registers 1

    return-void
.end method
```

### Mintegral

**Class**: `Lcom/mbridge/msdk/MBridgeSDKFactory;`

```smali
# Returns null instead of SDK instance
.method public static getMBridgeSDK()Lcom/mbridge/msdk/MBridgeSDK;
    .registers 1

    const/4 v0, 0x0

    return-object v0
.end method
```

## Tracker SDK Patterns

### Firebase Analytics

**Class**: `Lcom/google/firebase/analytics/FirebaseAnalytics;`

```smali
# Returns null — callers should null-check
.method public static getInstance(Landroid/content/Context;)Lcom/google/firebase/analytics/FirebaseAnalytics;
    .registers 1

    const/4 v0, 0x0

    return-object v0
.end method

.method public logEvent(Ljava/lang/String;Landroid/os/Bundle;)V
    .registers 1

    return-void
.end method

.method public setUserId(Ljava/lang/String;)V
    .registers 1

    return-void
.end method

.method public setUserProperty(Ljava/lang/String;Ljava/lang/String;)V
    .registers 1

    return-void
.end method

.method public setAnalyticsCollectionEnabled(Z)V
    .registers 1

    return-void
.end method
```

### Adjust

**Class**: `Lcom/adjust/sdk/Adjust;`

```smali
.method public static onCreate(Lcom/adjust/sdk/AdjustConfig;)V
    .registers 1

    return-void
.end method

.method public static trackEvent(Lcom/adjust/sdk/AdjustEvent;)V
    .registers 1

    return-void
.end method

.method public static setEnabled(Z)V
    .registers 1

    return-void
.end method

.method public static addSessionCallbackParameter(Ljava/lang/String;Ljava/lang/String;)V
    .registers 1

    return-void
.end method
```

### AppsFlyer

**Class**: `Lcom/appsflyer/AppsFlyerLib;`

```smali
# Returns null
.method public static getInstance()Lcom/appsflyer/AppsFlyerLib;
    .registers 1

    const/4 v0, 0x0

    return-object v0
.end method

.method public init(Ljava/lang/String;Lcom/appsflyer/AppsFlyerConversionListener;Landroid/content/Context;)Lcom/appsflyer/AppsFlyerLib;
    .registers 1

    const/4 v0, 0x0

    return-object v0
.end method

.method public start(Landroid/content/Context;)V
    .registers 1

    return-void
.end method

.method public logEvent(Landroid/content/Context;Ljava/lang/String;Ljava/util/Map;)V
    .registers 1

    return-void
.end method

.method public setCustomerUserId(Ljava/lang/String;)V
    .registers 1

    return-void
.end method
```

### Mixpanel

**Class**: `Lcom/mixpanel/android/mpmetrics/MixpanelAPI;`

```smali
# Returns null
.method public static getInstance(Landroid/content/Context;Ljava/lang/String;)Lcom/mixpanel/android/mpmetrics/MixpanelAPI;
    .registers 1

    const/4 v0, 0x0

    return-object v0
.end method

.method public track(Ljava/lang/String;)V
    .registers 1

    return-void
.end method

.method public identify(Ljava/lang/String;)V
    .registers 1

    return-void
.end method

.method public timeEvent(Ljava/lang/String;)V
    .registers 1

    return-void
.end method

.method public registerSuperProperties(Lorg/json/JSONObject;)V
    .registers 1

    return-void
.end method
```

### Amplitude

**Class**: `Lcom/amplitude/api/AmplitudeClient;`

```smali
# Returns null
.method public static getInstance()Lcom/amplitude/api/AmplitudeClient;
    .registers 1

    const/4 v0, 0x0

    return-object v0
.end method

.method public initialize(Landroid/content/Context;Ljava/lang/String;)Lcom/amplitude/api/AmplitudeClient;
    .registers 1

    const/4 v0, 0x0

    return-object v0
.end method

.method public logEvent(Ljava/lang/String;)V
    .registers 1

    return-void
.end method

.method public setUserId(Ljava/lang/String;)V
    .registers 1

    return-void
.end method

.method public setUserProperties(Lorg/json/JSONObject;)V
    .registers 1

    return-void
.end method
```

### Segment

**Class**: `Lcom/segment/analytics/Analytics;`

```smali
# Returns null
.method public static with(Landroid/content/Context;)Lcom/segment/analytics/Analytics;
    .registers 1

    const/4 v0, 0x0

    return-object v0
.end method

.method public track(Ljava/lang/String;)V
    .registers 1

    return-void
.end method

.method public identify(Ljava/lang/String;)V
    .registers 1

    return-void
.end method

.method public screen(Ljava/lang/String;)V
    .registers 1

    return-void
.end method

.method public group(Ljava/lang/String;)V
    .registers 1

    return-void
.end method

.method public alias(Ljava/lang/String;)V
    .registers 1

    return-void
.end method
```

### Braze

**Class**: `Lcom/braze/Braze;`

```smali
.method public static configure(Landroid/content/Context;Lcom/braze/configuration/BrazeConfig;)Z
    .registers 1

    const/4 v0, 0x0

    return v0
.end method

.method public logCustomEvent(Ljava/lang/String;)V
    .registers 1

    return-void
.end method

.method public changeUser(Ljava/lang/String;)V
    .registers 1

    return-void
.end method

.method public logPurchase(Ljava/lang/String;Ljava/lang/String;Ljava/math/BigDecimal;)V
    .registers 1

    return-void
.end method
```

### CleverTap

**Class**: `Lcom/clevertap/android/sdk/CleverTapAPI;`

```smali
# Returns null
.method public static getDefaultInstance(Landroid/content/Context;)Lcom/clevertap/android/sdk/CleverTapAPI;
    .registers 1

    const/4 v0, 0x0

    return-object v0
.end method

.method public pushEvent(Ljava/lang/String;)V
    .registers 1

    return-void
.end method

.method public onUserLogin(Ljava/util/Map;)V
    .registers 1

    return-void
.end method

.method public pushProfile(Ljava/util/Map;)V
    .registers 1

    return-void
.end method

.method public recordEvent(Ljava/lang/String;)V
    .registers 1

    return-void
.end method
```

### Flurry

**Class**: `Lcom/flurry/android/FlurryAgent;`

```smali
.method public static logEvent(Ljava/lang/String;)I
    .registers 1

    const/4 v0, 0x0

    return v0
.end method

.method public static setUserId(Ljava/lang/String;)V
    .registers 1

    return-void
.end method

.method public static onStartSession(Landroid/content/Context;)V
    .registers 1

    return-void
.end method

.method public static onEndSession(Landroid/content/Context;)V
    .registers 1

    return-void
.end method
```

## Manifest Disable Patterns

### Ad SDK Components

```xml
<!-- AdMob -->
<activity android:name="com.google.android.gms.ads.AdActivity" android:enabled="false" ... />
<provider android:name="com.google.android.gms.ads.MobileAdsInitProvider" android:enabled="false" ... />

<!-- Unity Ads -->
<activity android:name="com.unity3d.ads.adunit.AdUnitActivity" android:enabled="false" ... />
<activity android:name="com.unity3d.ads.adunit.AdUnitTransparentActivity" android:enabled="false" ... />

<!-- IronSource -->
<activity android:name="com.ironsource.sdk.controller.InterstitialActivity" android:enabled="false" ... />
<activity android:name="com.ironsource.sdk.controller.ControllerActivity" android:enabled="false" ... />

<!-- AppLovin -->
<activity android:name="com.applovin.adview.AppLovinFullscreenActivity" android:enabled="false" ... />

<!-- Meta AN -->
<activity android:name="com.facebook.ads.AudienceNetworkActivity" android:enabled="false" ... />

<!-- Vungle -->
<activity android:name="com.vungle.warren.ui.VungleActivity" android:enabled="false" ... />

<!-- Chartboost -->
<activity android:name="com.chartboost.sdk.CBImpressionActivity" android:enabled="false" ... />

<!-- Pangle -->
<activity android:name="com.bytedance.sdk.openadsdk.activity.TTFullScreenVideoActivity" android:enabled="false" ... />
<activity android:name="com.bytedance.sdk.openadsdk.activity.TTRewardVideoActivity" android:enabled="false" ... />
<activity android:name="com.bytedance.sdk.openadsdk.activity.TTInterstitialActivity" android:enabled="false" ... />
<activity android:name="com.bytedance.sdk.openadsdk.activity.TTAdActivity" android:enabled="false" ... />
<activity android:name="com.bytedance.sdk.openadsdk.activity.TTDelegateActivity" android:enabled="false" ... />

<!-- Vungle (new SDK) -->
<activity android:name="com.vungle.ads.internal.ui.VungleActivity" android:enabled="false" ... />

<!-- Meta AN (provider) -->
<provider android:name="com.facebook.ads.AudienceNetworkContentProvider" android:enabled="false" ... />

<!-- AppLovin (init provider) -->
<provider android:name="com.applovin.sdk.AppLovinInitProvider" android:enabled="false" ... />

<!-- BidMachine -->
<provider android:name="io.bidmachine.BidMachineInitProvider" android:enabled="false" ... />

<!-- IronSource (lifecycle) -->
<provider android:name="com.ironsource.lifecycle.IronsourceLifecycleProvider" android:enabled="false" ... />

<!-- Amazon APS -->
<activity android:name="com.amazon.device.ads.DTBAdActivity" android:enabled="false" ... />

<!-- Mintegral -->
<activity android:name="com.mbridge.msdk.activity.MBCommonActivity" android:enabled="false" ... />
<activity android:name="com.mbridge.msdk.reward.player.MBRewardVideoActivity" android:enabled="false" ... />

<!-- Smaato -->
<receiver android:name="com.smaato.sdk.core.SmaatoBroadcastReceiver" android:enabled="false" ... />
```

### Tracker SDK Components

```xml
<!-- Firebase Analytics -->
<service android:name="com.google.android.gms.measurement.AppMeasurementService" android:enabled="false" ... />
<receiver android:name="com.google.android.gms.measurement.AppMeasurementReceiver" android:enabled="false" ... />
<provider android:name="com.google.android.gms.measurement.AppMeasurementContentProvider" android:enabled="false" ... />
<receiver android:name="com.google.android.gms.measurement.AppMeasurementInstallReferrerReceiver" android:enabled="false" ... />
<service android:name="com.google.android.gms.measurement.AppMeasurementJobService" android:enabled="false" ... />

<!-- Adjust -->
<receiver android:name="com.adjust.sdk.AdjustReferrerReceiver" android:enabled="false" ... />

<!-- AppsFlyer -->
<receiver android:name="com.appsflyer.SingleInstallBroadcastReceiver" android:enabled="false" ... />
<receiver android:name="com.appsflyer.MultipleInstallBroadcastReceiver" android:enabled="false" ... />

<!-- Braze -->
<service android:name="com.braze.push.BrazeFirebaseMessagingService" android:enabled="false" ... />

<!-- CleverTap -->
<receiver android:name="com.clevertap.android.sdk.pushnotification.CTPushNotificationReceiver" android:enabled="false" ... />
<service android:name="com.clevertap.android.sdk.pushnotification.CTNotificationIntentService" android:enabled="false" ... />

<!-- AppsFlyer (internal receiver) -->
<receiver android:name="com.appsflyer.internal.AFSingleInstallBroadcastReceiver" android:enabled="false" ... />
```

## Grep Patterns for Smali Files

Use these patterns with `grep -rn` on smali directories to find SDK methods:

```bash
# AdMob initialization
grep -rn 'Lcom/google/android/gms/ads/MobileAds;->initialize' smali/

# Firebase Analytics event logging
grep -rn 'Lcom/google/firebase/analytics/FirebaseAnalytics;->logEvent' smali/

# All tracker init methods
grep -rn -E '(FirebaseAnalytics;->getInstance|Adjust;->onCreate|AppsFlyerLib;->getInstance|MixpanelAPI;->getInstance|AmplitudeClient;->getInstance|Analytics;->with|Braze;->configure|CleverTapAPI;->getDefaultInstance|FlurryAgent;->onStartSession)' smali/

# All ad SDK init methods
grep -rn -E '(MobileAds;->initialize|UnityAds;->initialize|IronSource;->init|AppLovinSdk;->getInstance|AudienceNetworkAds;->initialize|Vungle;->init|InMobiSdk;->init|Chartboost;->startWithAppId|TTAdSdk;->init|PAGSdk;->init|MBridgeSDKFactory;->getMBridgeSDK)' smali/

# Find invoke-static and invoke-virtual calls to SDK methods
grep -rn 'invoke-\(static\|virtual\).*Lcom/google/android/gms/ads/' smali/
grep -rn 'invoke-\(static\|virtual\).*Lcom/google/firebase/analytics/' smali/
```

## Custom Target File Format

For `--targets-file`, use one entry per line:

```
# Comment lines start with #
# Format: smali_class_path:method_name

# Custom tracker
com/example/analytics/CustomTracker:init
com/example/analytics/CustomTracker:track
com/example/analytics/CustomTracker:setUser

# Obfuscated class (identified via string analysis)
a/b/c:a
a/b/c:b
```
