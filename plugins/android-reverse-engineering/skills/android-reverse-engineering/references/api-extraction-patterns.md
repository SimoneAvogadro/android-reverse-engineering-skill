# API Extraction Patterns

Patterns and grep commands for finding HTTP API calls in decompiled Android source code.

## Retrofit

Retrofit is the most common HTTP client in Android apps. API endpoints are declared as annotated interface methods.

### Annotations to search for

```bash
# HTTP method annotations
grep -rn '@GET\|@POST\|@PUT\|@DELETE\|@PATCH\|@HEAD' sources/

# Parameter annotations
grep -rn '@Query\|@QueryMap\|@Path\|@Body\|@Field\|@FieldMap\|@Part\|@Header\|@HeaderMap' sources/

# Headers annotation (static headers)
grep -rn '@Headers' sources/

# Base URL configuration
grep -rn 'baseUrl\|\.baseUrl(' sources/
```

### Typical Retrofit interface

```java
public interface ApiService {
    @GET("users/{id}")
    Call<User> getUser(@Path("id") String userId);

    @POST("auth/login")
    @Headers({"Content-Type: application/json"})
    Call<LoginResponse> login(@Body LoginRequest request);
}
```

When documenting, capture: HTTP method, path, path parameters, query parameters, request body type, response type, and any static headers.

## OkHttp

OkHttp is often used directly or as the transport layer for Retrofit.

```bash
# Request building
grep -rn 'Request\.Builder\|Request.Builder\|\.url(\|\.post(\|\.put(\|\.delete(\|\.patch(' sources/

# URL construction
grep -rn 'HttpUrl\|\.addQueryParameter\|\.addPathSegment' sources/

# Interceptors (often add auth headers)
grep -rn 'Interceptor\|addInterceptor\|addNetworkInterceptor\|intercept(' sources/

# Response handling
grep -rn '\.execute()\|\.enqueue(' sources/
```

## Volley

```bash
grep -rn 'StringRequest\|JsonObjectRequest\|JsonArrayRequest\|Volley\.newRequestQueue\|RequestQueue' sources/
```

Volley requests typically pass the URL as a constructor argument and override `getHeaders()` or `getParams()` for custom headers/parameters.

## HttpURLConnection (legacy)

```bash
grep -rn 'HttpURLConnection\|HttpsURLConnection\|openConnection\|setRequestMethod\|setRequestProperty' sources/
```

## WebView

```bash
grep -rn 'loadUrl\|evaluateJavascript\|addJavascriptInterface\|WebViewClient\|shouldOverrideUrlLoading' sources/
```

WebView-based apps may load API endpoints via JavaScript bridges. Look for `@JavascriptInterface` annotated methods.

## Hardcoded URLs and Secrets

```bash
# HTTP/HTTPS URLs
grep -rn '"https\?://[^"]*"' sources/

# API keys and tokens
grep -rni 'api[_-]\?key\|api[_-]\?secret\|auth[_-]\?token\|bearer\|access[_-]\?token\|client[_-]\?secret' sources/

# Base URL constants
grep -rni 'BASE_URL\|API_URL\|SERVER_URL\|ENDPOINT\|API_BASE' sources/
```

## Documentation Template

For each discovered API endpoint, document it using this template:

```markdown
### `METHOD /path/to/endpoint`

- **Source**: `com.example.app.api.ApiService` (file:line)
- **Base URL**: `https://api.example.com/v1`
- **Full URL**: `https://api.example.com/v1/path/to/endpoint`
- **Path parameters**: `id` (String)
- **Query parameters**: `page` (int), `limit` (int)
- **Headers**:
  - `Authorization: Bearer <token>`
  - `Content-Type: application/json`
- **Request body**: `LoginRequest { email: String, password: String }`
- **Response type**: `ApiResponse<User>`
- **Notes**: Called from `LoginActivity.onLoginClicked()`
```

## Search Strategy

1. Start with **base URL constants** — find where the API root is configured
2. Search for **Retrofit interfaces** — they give the clearest picture of all endpoints
3. Check **interceptors** — they reveal auth schemes and common headers
4. Search for **hardcoded URLs** — catch any one-off API calls outside the main client
5. Look for **WebView URLs** — some apps use hybrid web/native approaches
