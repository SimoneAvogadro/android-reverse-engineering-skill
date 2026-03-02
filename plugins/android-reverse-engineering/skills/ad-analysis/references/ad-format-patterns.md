# Ad Format Patterns

Code patterns for each ad format across major SDKs — how to identify banner, interstitial, rewarded, native, and app-open ads in decompiled code.

## Banner Ads

Small ads displayed within the app UI, typically at top or bottom of screen.

### Lifecycle
1. Create ad view (XML layout or programmatic)
2. Set ad unit ID
3. Load ad request
4. Ad displays inline — auto-refreshes periodically

### SDK-specific patterns

**AdMob**:
```java
AdView adView = new AdView(context);
adView.setAdSize(AdSize.BANNER); // or LARGE_BANNER, MEDIUM_RECTANGLE, FULL_BANNER, LEADERBOARD
adView.setAdUnitId("ca-app-pub-XXXXX/YYYYY");
adView.loadAd(new AdRequest.Builder().build());
```

**Unity Ads**:
```java
BannerView bannerView = new BannerView(activity, "placement_id", new UnityBannerSize(320, 50));
bannerView.load();
```

**IronSource**:
```java
IronSource.loadBanner(bannerLayout, "placement_name");
// or LevelPlay:
LevelPlayBannerAdView banner = new LevelPlayBannerAdView(context, "ad_unit_id");
banner.loadAd();
```

**AppLovin MAX**:
```java
MaxAdView adView = new MaxAdView("ad_unit_id", context);
adView.loadAd();
adView.startAutoRefresh();
```

**Meta AN**:
```java
AdView adView = new AdView(context, "placement_id", AdSize.BANNER_HEIGHT_50);
adView.loadAd();
```

### Grep for all banners
```bash
grep -rn 'AdView\|BannerView\|AdSize\.\|BANNER\|loadBanner\|IronSourceBannerLayout\|MaxAdView\|MBBannerView\|PAGBannerAd\|InMobiBanner' "$SOURCE_DIR"
```

---

## Interstitial Ads

Full-screen ads shown at natural transition points (level complete, between pages).

### Lifecycle
1. Load ad in advance (preload)
2. Check if ad is ready
3. Show ad at transition point
4. Handle close callback → resume app flow

### SDK-specific patterns

**AdMob**:
```java
InterstitialAd.load(context, "ca-app-pub-XXXXX/YYYYY", adRequest,
    new InterstitialAdLoadCallback() {
        @Override public void onAdLoaded(InterstitialAd ad) { /* cache */ }
        @Override public void onAdFailedToLoad(LoadAdError error) { /* retry */ }
    });
// Show:
interstitialAd.setFullScreenContentCallback(new FullScreenContentCallback() { ... });
interstitialAd.show(activity);
```

**Unity Ads**:
```java
UnityAds.load("placement_id", new IUnityAdsLoadListener() { ... });
UnityAds.show(activity, "placement_id", new IUnityAdsShowListener() { ... });
```

**IronSource**:
```java
IronSource.loadInterstitial();
if (IronSource.isInterstitialReady()) {
    IronSource.showInterstitial("placement_name");
}
```

**AppLovin MAX**:
```java
MaxInterstitialAd interstitialAd = new MaxInterstitialAd("ad_unit_id", activity);
interstitialAd.loadAd();
interstitialAd.showAd();
```

### Grep for all interstitials
```bash
grep -rn 'InterstitialAd\|showInterstitial\|loadInterstitial\|MaxInterstitialAd\|isInterstitialReady\|FullScreenContentCallback\|TTFullScreenVideoAd\|PAGInterstitialAd' "$SOURCE_DIR"
```

---

## Rewarded Ads

Full-screen ads that give the user an in-app reward for watching.

### Lifecycle
1. Load ad in advance
2. Show ad when user opts in (e.g., "Watch ad for extra life")
3. User watches ad to completion
4. Reward callback fires → grant reward
5. Handle incomplete views (user skipped)

### SDK-specific patterns

**AdMob**:
```java
RewardedAd.load(context, "ca-app-pub-XXXXX/YYYYY", adRequest,
    new RewardedAdLoadCallback() {
        @Override public void onAdLoaded(RewardedAd ad) { /* cache */ }
    });
// Show:
rewardedAd.show(activity, new OnUserEarnedRewardListener() {
    @Override public void onUserEarnedReward(RewardItem reward) {
        int amount = reward.getAmount();
        String type = reward.getType();
    }
});
```

**Unity Ads**:
```java
// Same load/show as interstitial, but placement configured as rewarded on dashboard
UnityAds.load("rewarded_placement", loadListener);
UnityAds.show(activity, "rewarded_placement", showListener);
// Reward granted in onUnityAdsShowComplete with UnityAds.UnityAdsShowCompletionState.COMPLETED
```

**IronSource**:
```java
// Auto-loaded by default
if (IronSource.isRewardedVideoAvailable()) {
    IronSource.showRewardedVideo("placement_name");
}
// Reward in RewardedVideoListener.onRewardedVideoAdRewarded(Placement placement)
```

**AppLovin MAX**:
```java
MaxRewardedAd rewardedAd = MaxRewardedAd.getInstance("ad_unit_id", activity);
rewardedAd.loadAd();
rewardedAd.showAd(); // reward via MaxRewardedAdListener.onUserRewarded(MaxAd, MaxReward)
```

### Grep for all rewarded
```bash
grep -rn 'RewardedAd\|RewardedVideo\|showRewardedVideo\|OnUserEarnedRewardListener\|RewardItem\|MaxRewardedAd\|TTRewardVideoAd\|PAGRewardedAd\|MBRewardVideoHandler' "$SOURCE_DIR"
```

---

## Native Ads

Ads that match the app's look and feel, rendered with custom templates.

### Lifecycle
1. Create ad loader with ad unit ID
2. Load ad
3. Receive native ad object with assets (headline, body, image, CTA, icon)
4. Inflate custom layout and bind assets
5. Register ad view for impression/click tracking

### SDK-specific patterns

**AdMob**:
```java
AdLoader adLoader = new AdLoader.Builder(context, "ca-app-pub-XXXXX/YYYYY")
    .forNativeAd(nativeAd -> { /* bind to NativeAdView */ })
    .withNativeAdOptions(new NativeAdOptions.Builder().build())
    .build();
adLoader.loadAd(new AdRequest.Builder().build());
```

**Meta AN**:
```java
NativeAd nativeAd = new NativeAd(context, "placement_id");
nativeAd.loadAd(nativeAd.buildLoadAdConfig()
    .withAdListener(new NativeAdListener() { ... })
    .build());
```

**AppLovin MAX**:
```java
MaxNativeAdLoader nativeAdLoader = new MaxNativeAdLoader("ad_unit_id", context);
nativeAdLoader.setNativeAdListener(new MaxNativeAdListener() { ... });
nativeAdLoader.loadAd();
```

### Grep for all native
```bash
grep -rn 'NativeAd\|NativeAdView\|NativeAdLoader\|AdLoader\.Builder\|NativeBannerAd\|NativeAdLayout\|MaxNativeAdLoader\|InMobiNative\|VungleNativeAd' "$SOURCE_DIR"
```

---

## App Open Ads

Full-screen ads shown when the app is foregrounded (cold start or resume from background).

### Lifecycle
1. Preload ad during app initialization or background
2. On app foreground, check if ad is available and not expired
3. Show ad before the main content appears
4. Handle close callback → show app content

### Pattern (AdMob-specific)
```java
AppOpenAd.load(context, "ca-app-pub-XXXXX/YYYYY", adRequest,
    AppOpenAd.APP_OPEN_AD_ORIENTATION_PORTRAIT,
    new AppOpenAd.AppOpenAdLoadCallback() {
        @Override public void onAdLoaded(AppOpenAd ad) { /* cache with timestamp */ }
    });
// Show on foreground:
appOpenAd.show(activity);
```

Common implementation pattern uses `Application.ActivityLifecycleCallbacks` to detect foreground transitions:
```java
registerActivityLifecycleCallbacks(new ActivityLifecycleCallbacks() {
    @Override public void onActivityStarted(Activity activity) {
        // Show app open ad if available
    }
});
```

### Grep for app open
```bash
grep -rn 'AppOpenAd\|AppOpenAdLoadCallback\|APP_OPEN_AD\|AppOpenAdManager\|appOpenAd' "$SOURCE_DIR"
```
