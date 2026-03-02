# Ad SDK Catalog

Quick-reference for detecting advertising SDKs in decompiled Android apps.

## AdMob / Google Mobile Ads

| Field | Value |
|---|---|
| **Package** | `com.google.android.gms.ads` |
| **Key classes** | `MobileAds`, `AdView`, `InterstitialAd`, `RewardedAd`, `NativeAd`, `AppOpenAd`, `AdRequest`, `AdLoader` |
| **Manifest markers** | `<meta-data android:name="com.google.android.gms.ads.APPLICATION_ID"/>`, `<activity android:name="com.google.android.gms.ads.AdActivity"/>` |
| **Gradle** | `com.google.android.gms:play-services-ads` |
| **Grep detection** | `MobileAds\.initialize\|com\.google\.android\.gms\.ads\|ca-app-pub-` |

## Unity Ads

| Field | Value |
|---|---|
| **Package** | `com.unity3d.ads`, `com.unity3d.services` |
| **Key classes** | `UnityAds`, `BannerView`, `IUnityAdsInitializationListener`, `IUnityAdsLoadListener`, `IUnityAdsShowListener` |
| **Manifest markers** | `<activity android:name="com.unity3d.services.ads.adunit.AdUnitActivity"/>`, `<activity android:name="com.unity3d.ads.adunit.AdUnitTransparentActivity"/>` |
| **Gradle** | `com.unity3d.ads:unity-ads` |
| **Grep detection** | `UnityAds\.initialize\|com\.unity3d\.ads\|IUnityAds` |

## IronSource / LevelPlay

| Field | Value |
|---|---|
| **Package** | `com.ironsource.mediationsdk`, `com.ironsource.sdk` |
| **Key classes** | `IronSource`, `IronSourceBannerLayout`, `InterstitialListener`, `RewardedVideoListener`, `LevelPlayBannerAdView`, `LevelPlayInterstitialAd`, `LevelPlayRewardedAd` |
| **Manifest markers** | `<activity android:name="com.ironsource.sdk.controller.ControllerActivity"/>`, `<provider android:name="com.ironsource.sdk.handlers.provider.IronSourceDataProvider"/>` |
| **Gradle** | `com.ironsource.sdk:mediationsdk` |
| **Grep detection** | `IronSource\.init\|com\.ironsource\.mediationsdk\|LevelPlay` |

## AppLovin / MAX

| Field | Value |
|---|---|
| **Package** | `com.applovin.sdk`, `com.applovin.mediation` |
| **Key classes** | `AppLovinSdk`, `MaxAdView`, `MaxInterstitialAd`, `MaxRewardedAd`, `MaxNativeAdLoader`, `MaxAdListener`, `MaxRewardedAdListener` |
| **Manifest markers** | `<meta-data android:name="applovin.sdk.key"/>`, `<activity android:name="com.applovin.adview.AppLovinFullscreenActivity"/>` |
| **Gradle** | `com.applovin:applovin-sdk` |
| **Grep detection** | `AppLovinSdk\.getInstance\|MaxAdView\|MaxInterstitialAd\|MaxRewardedAd` |

## Meta Audience Network (Facebook)

| Field | Value |
|---|---|
| **Package** | `com.facebook.ads` |
| **Key classes** | `AudienceNetworkAds`, `AdView`, `InterstitialAd`, `RewardedVideoAd`, `NativeAd`, `NativeBannerAd`, `NativeAdLayout` |
| **Manifest markers** | `<activity android:name="com.facebook.ads.AudienceNetworkActivity"/>`, `<provider android:name="com.facebook.ads.AudienceNetworkContentProvider"/>` |
| **Gradle** | `com.facebook.android:audience-network-sdk` |
| **Grep detection** | `AudienceNetworkAds\.initialize\|com\.facebook\.ads\.\|InterstitialAdListener` |

## Vungle / Liftoff

| Field | Value |
|---|---|
| **Package** | `com.vungle.warren` (legacy), `com.vungle.ads` (v7+) |
| **Key classes** | `Vungle`, `VungleBanner`, `VungleInterstitial`, `VungleRewarded`, `VungleNativeAd` |
| **Manifest markers** | `<activity android:name="com.vungle.warren.ui.VungleActivity"/>` |
| **Gradle** | `com.vungle:vungle-ads` |
| **Grep detection** | `Vungle\.init\|com\.vungle\.\|VungleBanner\|VungleInterstitial` |

## InMobi

| Field | Value |
|---|---|
| **Package** | `com.inmobi.sdk`, `com.inmobi.ads` |
| **Key classes** | `InMobiSdk`, `InMobiBanner`, `InMobiInterstitial`, `InMobiNative` |
| **Manifest markers** | `<activity android:name="com.inmobi.rendering.InMobiAdActivity"/>` |
| **Gradle** | `com.inmobi.monetization:inmobi-ads` |
| **Grep detection** | `InMobiSdk\.init\|InMobiBanner\|InMobiInterstitial` |

## Chartboost

| Field | Value |
|---|---|
| **Package** | `com.chartboost.sdk` |
| **Key classes** | `Chartboost`, `ChartboostDelegate` |
| **Manifest markers** | `<activity android:name="com.chartboost.sdk.CBImpressionActivity"/>` |
| **Gradle** | `com.chartboost:chartboost-sdk` |
| **Grep detection** | `Chartboost\.startWithAppId\|Chartboost\.showInterstitial\|com\.chartboost\.sdk` |

## Pangle / TikTok (Bytedance)

| Field | Value |
|---|---|
| **Package** | `com.bytedance.sdk.openadsdk` (legacy), `com.pgl.sys` (v5+) |
| **Key classes** | `TTAdSdk`, `TTAdConfig`, `TTAdNative`, `TTFullScreenVideoAd`, `TTRewardVideoAd`, `TTBannerAd`; v5: `PAGSdk`, `PAGBannerAd`, `PAGInterstitialAd`, `PAGRewardedAd` |
| **Manifest markers** | `<provider android:name="com.bytedance.sdk.openadsdk.multipro.TTMultiProvider"/>` |
| **Gradle** | `com.pangle.global:ads-sdk` |
| **Grep detection** | `TTAdSdk\.init\|PAGSdk\.init\|com\.bytedance\.sdk\.openadsdk` |

## Mintegral

| Field | Value |
|---|---|
| **Package** | `com.mbridge.msdk` |
| **Key classes** | `MBridgeSDKFactory`, `MBBannerView`, `MBInterstitialVideoHandler`, `MBRewardVideoHandler`, `MBNewInterstitialHandler` |
| **Manifest markers** | `<activity android:name="com.mbridge.msdk.activity.MBCommonActivity"/>` |
| **Gradle** | `com.mbridge.msdk.oversea:mbbanner`, `com.mbridge.msdk.oversea:interstitialvideo`, etc. |
| **Grep detection** | `MBridgeSDKFactory\|com\.mbridge\.msdk\|MBBannerView\|MBRewardVideoHandler` |
