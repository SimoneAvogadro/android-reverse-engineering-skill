# Data Exfiltration Patterns

How tracker SDKs send data out of the device — known endpoints, custom configurations, proxy patterns, and batch upload mechanisms.

## Known Endpoints by SDK

### Firebase Analytics / Google Analytics
| Endpoint | Purpose |
|---|---|
| `app-measurement.com` | Primary event collection |
| `firebase-settings.crashlytics.com` | Crashlytics config |
| `firebaselogging-pa.googleapis.com` | Event logging |
| `google-analytics.com/collect` | Legacy GA hits |
| `www.googletagmanager.com` | GTM container |

### Adjust
| Endpoint | Purpose |
|---|---|
| `app.adjust.com` | Event tracking, attribution |
| `app.adjust.io` | Alternative domain |
| `app.adjust.world` | Regional alternative |
| `cdn.adjust.com` | SDK config |
| `gdpr.adjust.com` | GDPR forget-me requests |

### AppsFlyer
| Endpoint | Purpose |
|---|---|
| `launches.appsflyer.com` | App launch events |
| `events.appsflyer.com` | In-app events |
| `register.appsflyer.com` | Install attribution |
| `inapps.appsflyer.com` | In-app purchase validation |
| `gcdsdk.appsflyer.com` | SDK config |

### Mixpanel
| Endpoint | Purpose |
|---|---|
| `api.mixpanel.com/track` | Event tracking |
| `api.mixpanel.com/engage` | People profiles |
| `api.mixpanel.com/decide` | Feature flags, A/B tests |
| `api-js.mixpanel.com` | Alternative endpoint |

### Amplitude
| Endpoint | Purpose |
|---|---|
| `api.amplitude.com/2/httpapi` | Event upload (v2) |
| `api2.amplitude.com/2/httpapi` | Batch event upload |
| `cdn.amplitude.com` | SDK config |
| `regionconfig.amplitude.com` | Region routing |

### Segment
| Endpoint | Purpose |
|---|---|
| `api.segment.io/v1/t` | Track events |
| `api.segment.io/v1/i` | Identify calls |
| `api.segment.io/v1/batch` | Batch upload |
| `cdn-settings.segment.com` | Workspace settings |

### Braze
| Endpoint | Purpose |
|---|---|
| `sdk.iad-01.braze.com` | US-01 SDK endpoint (varies per cluster) |
| `sdk.iad-02.braze.com` | US-02 SDK endpoint |
| `sdk.fra-01.braze.eu` | EU-01 SDK endpoint |
| `rest.iad-01.braze.com` | REST API |

Braze uses cluster-specific endpoints: `sdk.iad-NN.braze.com`, `sdk.fra-NN.braze.eu`. Look for `.setCustomEndpoint()` in `BrazeConfig.Builder`.

### CleverTap
| Endpoint | Purpose |
|---|---|
| `wzrkt.com` | Primary analytics/events |
| `in.clevertap.com` | India region |
| `eu1.clevertap.com` | EU region |
| `sg1.clevertap.com` | Singapore region |
| `clevertap-prod.com` | Legacy |

### Flurry
| Endpoint | Purpose |
|---|---|
| `data.flurry.com` | Event data upload |
| `adlog.flurry.com` | Ad analytics |
| `cfg.flurry.com` | SDK configuration |

## Custom Endpoint Configuration

Some SDKs allow custom endpoint configuration — important for identifying proxy/relay setups.

### Grep for custom endpoints
```bash
# Braze custom endpoint
grep -rn 'setCustomEndpoint\|setEndpoint\|setApiUrl' "$SOURCE_DIR"

# Segment custom host
grep -rn 'connectionFactory\|apiHost\|cdnHost' "$SOURCE_DIR"

# Mixpanel custom server
grep -rn 'setServerURL\|setDecideUrl\|setEventsUrl' "$SOURCE_DIR"

# Amplitude custom server
grep -rn 'setServerUrl\|setUseDynamicConfig' "$SOURCE_DIR"

# Generic proxy patterns
grep -rn 'proxyUrl\|proxyHost\|relayEndpoint\|analyticsProxy\|trackingProxy' "$SOURCE_DIR"
```

## Proxy & Relay Patterns

Apps may route analytics through their own servers to avoid ad blockers or aggregate data.

### Detection patterns
```bash
# Look for OkHttp interceptors that rewrite analytics URLs
grep -rn 'Interceptor.*analytics\|Interceptor.*tracking\|rewriteUrl.*analytics' "$SOURCE_DIR"

# Server-side relay: app sends events to its own API, which forwards to tracker
grep -rn '/api/analytics\|/api/events\|/api/tracking\|/v1/collect\|/v1/events' "$SOURCE_DIR"

# Custom transport layer
grep -rn 'AnalyticsTransport\|EventTransport\|TrackingTransport\|EventDispatcher' "$SOURCE_DIR"
```

## Batch Upload Patterns

Most SDKs batch events and upload periodically or on app backgrounding.

### Common batch patterns
```bash
# Database/file storage for batched events
grep -rn 'EventDatabase\|event_queue\|analytics_db\|pending_events\|EventStore' "$SOURCE_DIR"

# Flush triggers
grep -rn '\.flush\(\)\|flushEvents\|flushQueue\|uploadEvents\|sendBatch\|dispatchEvents' "$SOURCE_DIR"

# Batch size / interval config
grep -rn 'flushInterval\|batchSize\|maxQueueSize\|uploadInterval\|flushAt\|setFlushInterval' "$SOURCE_DIR"
```

## Finding the Underlying HTTP Calls

Tracker SDKs ultimately use standard HTTP mechanisms. To see the actual network calls:

```bash
# OkHttp client creation inside SDK packages
grep -rn --include="*.java" 'OkHttpClient\|HttpURLConnection' "$SOURCE_DIR"/com/google/firebase/
grep -rn --include="*.java" 'OkHttpClient\|HttpURLConnection' "$SOURCE_DIR"/com/adjust/
grep -rn --include="*.java" 'OkHttpClient\|HttpURLConnection' "$SOURCE_DIR"/com/appsflyer/

# POST bodies — look for JSON construction near known SDK packages
grep -rn 'toJson\|JSONObject\|JsonWriter\|Gson\|Moshi' "$SOURCE_DIR"/com/mixpanel/
```
