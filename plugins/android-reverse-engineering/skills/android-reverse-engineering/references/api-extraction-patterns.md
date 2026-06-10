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

## Ktor (Kotlin)

Ktor is the dominant HTTP client in Kotlin Multiplatform and modern
Kotlin-only Android apps. Unlike Retrofit, Ktor does **not** use annotations
to declare endpoints — paths appear as plain string arguments to
`client.get(...)` / `client.post(...)`, often inside an extension function.

```bash
# Calls
grep -rn '\b\(client\|httpClient\|HttpClient\)\.\(get\|post\|put\|delete\|patch\|head\|request\)\s*[<(]' sources/

# Default request / base URL configuration
grep -rn 'HttpRequestBuilder\|defaultRequest\s*{\|\burl\s*(\s*"\|URLBuilder' sources/

# Auth plugin (bearer / refresh)
grep -rn '\bbearer\s*{\|BearerTokens\s*(\|loadTokens\s*{\|refreshTokens\s*{' sources/
```

Typical Ktor call (after decompile):

```java
client.get("api/v1/users/profile") {
    parameter("locale", "en-US");
}
```

The base URL is usually applied via `defaultRequest { url { host = "..." } }`
in the client builder. Search for `host =` and `URLProtocol.HTTPS` references
to pin it down.

**Note on obfuscation:** in heavily R8-shrunk apps the call site
`client.get("path")` is inlined to something like `aVar.a(dVar, "path")`
and the `client.<verb>(` regex misses it. The path string itself is **not**
obfuscated, however — fall back to the generic path-literal search
(`--paths`) for the endpoint inventory in those cases. Ktor library
internals (`BearerTokens`, `loadTokens`, `refreshTokens`, `URLProtocol`)
remain searchable because Ktor keeps these on its public API.

Ktor's authentication plugin uses the
[`Auth { bearer { loadTokens { ... }; refreshTokens { ... } } }`](https://ktor.io/docs/auth.html)
DSL — bearer access tokens with automatic refresh. After R8, the DSL
lambdas appear as `Function2`/`Function3` impls referencing
`BearerTokens(...)` calls.

## Apollo Kotlin (GraphQL)

```bash
# Client setup
grep -rn 'ApolloClient\|\.serverUrl(\|HttpNetworkTransport' sources/

# Operations (queries / mutations / subscriptions)
grep -rn '\.query(\s*[A-Z]\|\.mutation(\s*[A-Z]\|\.subscription(\s*[A-Z]' sources/
```

Apollo generates one class per operation under a generated package; once you
find the GraphQL endpoint URL via `ApolloClient.serverUrl("...")`, use the
operation classes themselves as the API documentation — each carries its
GraphQL document text in `OPERATION_DOCUMENT`.

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

## Endpoint-Shaped Path Literals (obfuscation-resistant)

When the HTTP client cannot be identified (custom abstraction, heavy
inlining, KMP shared module), or the call sites are obfuscated to
`a.b(c, "path")`, fall back to extracting the path string literals
themselves. R8 does not obfuscate string contents, so paths leak through.

```bash
# All quoted strings shaped like an API path, deduplicated
grep -rhoE '"(/[A-Za-z0-9_{}.\-]+(/[A-Za-z0-9_{}.\-]+)+/?|(api|v[0-9]+|graphql|users?|account|auth|sso|oauth|profile|cart|basket|order|product|inventory|search|category|address|location|delivery|payment|invoice|favo[u]?rites?)(/[A-Za-z0-9_{}.\-]+)+/?)"' sources/ \
    | grep -Ev '^"(image|video|audio|text|application|content)/|^"/(proc|sys|dev|tmp|etc)/' \
    | sort -u
```

The skill ships this as `find-api-calls.sh --paths`, which prints both a
deduplicated inventory and the full list of call sites. On real-world
Kotlin apps this single command typically produces 100–300 distinct
endpoint paths, which is the most useful first artifact for documentation.

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
