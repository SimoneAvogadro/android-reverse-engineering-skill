# Tracker SDK Initialization & Event Patterns

Detailed code patterns for each tracker SDK — how they initialize, log events, identify users, and handle consent.

## Firebase Analytics

### Initialization
```java
// Typically in Application.onCreate() or Activity
FirebaseAnalytics mFirebaseAnalytics = FirebaseAnalytics.getInstance(this);
// Auto-initialized via google-services.json — may have no explicit init call
FirebaseApp.initializeApp(context);
```

**Where to find API key**: `google-services.json` → `project_info.firebase_url` and `client[].api_key`. After decompilation, check `res/values/strings.xml` for `google_app_id`, `firebase_database_url`, `gcm_defaultSenderId`.

### Event Logging
```java
Bundle params = new Bundle();
params.putString(FirebaseAnalytics.Param.ITEM_ID, id);
params.putString(FirebaseAnalytics.Param.ITEM_NAME, name);
mFirebaseAnalytics.logEvent(FirebaseAnalytics.Event.SELECT_CONTENT, params);
// Custom events
mFirebaseAnalytics.logEvent("custom_event_name", params);
```

**Grep**: `\.logEvent\s*\(` — captures both standard and custom events.

### User Identification
```java
mFirebaseAnalytics.setUserId("user_id_string");
mFirebaseAnalytics.setUserProperty("favorite_food", "pizza");
```

### Consent / Opt-out
```java
mFirebaseAnalytics.setAnalyticsCollectionEnabled(false); // kill switch
// Granular consent (v21.0.0+)
mFirebaseAnalytics.setConsent(Map.of(
    ConsentType.ANALYTICS_STORAGE, ConsentStatus.DENIED,
    ConsentType.AD_STORAGE, ConsentStatus.DENIED
));
```

---

## Adjust

### Initialization
```java
AdjustConfig config = new AdjustConfig(this, "APP_TOKEN", AdjustConfig.ENVIRONMENT_PRODUCTION);
config.setLogLevel(LogLevel.WARN);
config.setOnAttributionChangedListener(attribution -> { /* ... */ });
Adjust.onCreate(config);
```

**Where to find API key**: First argument to `AdjustConfig()` constructor — the app token string.

### Event Tracking
```java
AdjustEvent event = new AdjustEvent("EVENT_TOKEN");
event.setRevenue(1.0, "USD");
event.addCallbackParameter("key", "value");
Adjust.trackEvent(event);
```

### Attribution
```java
config.setOnAttributionChangedListener(attribution -> {
    attribution.trackerToken;
    attribution.trackerName;
    attribution.network;
    attribution.campaign;
});
```

### Consent
```java
Adjust.gdprForgetMe(context); // GDPR right to be forgotten
Adjust.disableThirdPartySharing(context);
Adjust.trackThirdPartySharing(thirdPartySharing);
```

---

## AppsFlyer

### Initialization
```java
AppsFlyerLib.getInstance().init("AF_DEV_KEY", conversionListener, this);
AppsFlyerLib.getInstance().start(this);
```

**Where to find API key**: First argument to `.init()` — the dev key string.

### Event Tracking
```java
Map<String, Object> eventValues = new HashMap<>();
eventValues.put(AFInAppEventParameterName.REVENUE, 1200);
eventValues.put(AFInAppEventParameterName.CURRENCY, "USD");
AppsFlyerLib.getInstance().logEvent(context, AFInAppEventType.PURCHASE, eventValues);
```

### User Identity
```java
AppsFlyerLib.getInstance().setCustomerUserId("user_id");
AppsFlyerLib.getInstance().setAdditionalData(customData);
```

### Consent
```java
AppsFlyerLib.getInstance().anonymizeUser(true);
AppsFlyerLib.getInstance().stop(true, context); // full opt-out
```

---

## Mixpanel

### Initialization
```java
MixpanelAPI mixpanel = MixpanelAPI.getInstance(context, "MIXPANEL_TOKEN");
```

**Where to find token**: First string argument to `getInstance()`.

### Event Tracking
```java
JSONObject props = new JSONObject();
props.put("source", "search");
mixpanel.track("Button Clicked", props);
mixpanel.timeEvent("Time On Page"); // starts timer
mixpanel.track("Time On Page"); // ends timer, records duration
```

### User Identity
```java
mixpanel.identify("user_id");
mixpanel.alias("new_id", "existing_id");
mixpanel.getPeople().set("$email", "user@example.com");
mixpanel.getPeople().increment("login_count", 1);
```

### Consent
```java
mixpanel.optOutTracking(); // full opt-out
mixpanel.optInTracking();  // re-enable
```

---

## Amplitude

### Initialization
```java
// v1 (legacy)
Amplitude.getInstance().initialize(context, "API_KEY").enableForegroundTracking(application);
// v2 (kotlin-first)
val amplitude = Amplitude(Configuration(apiKey = "API_KEY", context = applicationContext))
```

**Where to find API key**: Argument to `initialize()` or `Configuration()`.

### Event Tracking
```java
Amplitude.getInstance().logEvent("button_clicked");
Amplitude.getInstance().logEvent("purchase", new JSONObject().put("price", 9.99));
Amplitude.getInstance().logRevenue(new Revenue().setProductId("product").setPrice(9.99));
```

### User Identity
```java
Amplitude.getInstance().setUserId("user_id");
Identify identify = new Identify().set("plan", "premium").add("login_count", 1);
Amplitude.getInstance().identify(identify);
```

### Consent
```java
Amplitude.getInstance().setOptOut(true);
Amplitude.getInstance().enableCoppaControl(); // COPPA
```

---

## Segment

### Initialization
```java
Analytics analytics = new Analytics.Builder(context, "WRITE_KEY")
    .trackApplicationLifecycleEvents()
    .build();
Analytics.setSingletonInstance(analytics);
```

**Where to find write key**: Second argument to `Analytics.Builder()`.

### Event Tracking
```java
Analytics.with(context).track("Item Purchased",
    new Properties().putValue("item", "sword").putValue("revenue", 9.99));
Analytics.with(context).screen("Home", new Properties().putValue("tab", "feed"));
```

### User Identity
```java
Analytics.with(context).identify("user_id",
    new Traits().putName("John").putEmail("john@example.com"), null);
Analytics.with(context).alias("new_id");
```

### Consent
```java
Analytics.with(context).optOut(true);
```

---

## Braze

### Initialization
```java
BrazeConfig brazeConfig = new BrazeConfig.Builder()
    .setApiKey("API_KEY")
    .setCustomEndpoint("sdk.iad-01.braze.com")
    .build();
Braze.configure(context, brazeConfig);
```

**Where to find API key**: `.setApiKey()` and `.setCustomEndpoint()` in the config builder.

### Event & Purchase Logging
```java
Braze.getInstance(context).logCustomEvent("event_name", new BrazeProperties().addProperty("key", "value"));
Braze.getInstance(context).logPurchase("product_id", "USD", new BigDecimal("9.99"));
```

### User Identity
```java
Braze.getInstance(context).changeUser("user_id");
Braze.getInstance(context).getCurrentUser().setEmail("user@example.com");
Braze.getInstance(context).getCurrentUser().setCustomUserAttribute("attr", "value");
```

---

## CleverTap

### Initialization
```java
CleverTapAPI clevertapDefaultInstance = CleverTapAPI.getDefaultInstance(applicationContext);
// Auto-init via manifest meta-data: CLEVERTAP_ACCOUNT_ID, CLEVERTAP_TOKEN
ActivityLifecycleCallback.register(application);
```

**Where to find credentials**: Manifest `<meta-data>` tags: `CLEVERTAP_ACCOUNT_ID`, `CLEVERTAP_TOKEN`.

### Event Tracking
```java
HashMap<String, Object> props = new HashMap<>();
props.put("Product Name", "Widget");
clevertapDefaultInstance.pushEvent("Product Viewed", props);
// Charged event (purchase)
clevertapDefaultInstance.pushChargedEvent(chargeDetails, items);
```

### User Identity
```java
HashMap<String, Object> profile = new HashMap<>();
profile.put("Name", "John");
profile.put("Email", "john@example.com");
profile.put("Identity", "user_id");
clevertapDefaultInstance.onUserLogin(profile);
clevertapDefaultInstance.pushProfile(profile);
```

---

## Flurry

### Initialization
```java
new FlurryAgent.Builder()
    .withLogEnabled(true)
    .withCaptureUncaughtExceptions(true)
    .build(context, "FLURRY_API_KEY");
```

**Where to find API key**: Last argument to `.build()`.

### Event Tracking
```java
FlurryAgent.logEvent("event_name");
FlurryAgent.logEvent("event_name", params); // params is Map<String, String>
FlurryAgent.logEvent("timed_event", params, true); // timed event
FlurryAgent.endTimedEvent("timed_event");
FlurryAgent.logPayment("product", "id", 1, 9.99, "USD", "txn_id", null);
```

### User Identity
```java
FlurryAgent.setUserId("user_id");
FlurryAgent.setAge(25);
FlurryAgent.setGender(Constants.MALE);
```
