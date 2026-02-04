---
name: android-reverse-engineering
description: "Decompile Android APK/XAPK/JAR/AAR files and extract/document HTTP APIs (Retrofit/OkHttp/URLs) with a repeatable workflow."
version: 1.0.0
author: "SimoneAvogadro (fork: gmh5225)"
tags: [android, reverse-engineering, jadx, fernflower, vineflower, dex2jar, okhttp, retrofit, api]
trigger: decompile APK|decompile XAPK|reverse engineer Android|extract API|analyze Android|jadx|fernflower|vineflower|follow call flow|decompile JAR|decompile AAR|Android reverse engineering|find API endpoints
---

# Android Reverse Engineering & API Extraction

This skill provides a structured workflow to:
- decompile Android artifacts (APK/XAPK/JAR/AAR)
- trace call flows from entry points to network layers
- extract and document HTTP APIs (Retrofit endpoints, OkHttp calls, hardcoded URLs, auth patterns)

## Prerequisites

- Java JDK 17+
- `jadx` (CLI)
- Optional (recommended): Vineflower/Fernflower, dex2jar

## Workflow (high-level)

1. **Decompile**
   - Use `jadx` first for a broad pass (resources + sources)
   - Use Fernflower/Vineflower for better Java output on tricky code; compare when needed
2. **Analyze structure**
   - Identify launcher Activity, Application class, and DI setup
   - Map packages: `api`, `network`, `data`, `repository`, `service`, `retrofit`, `http`
3. **Trace call flows**
   - UI entry point → ViewModel/Presenter → Repository → API service → HTTP client call
4. **Extract APIs**
   - Retrofit: interface annotations (`@GET`, `@POST`, …)
   - OkHttp: `Request.Builder`, `HttpUrl`, interceptors
   - URLs: string literals (`http://`, `https://`) and base URL builders
5. **Document endpoints**

Use this template for each endpoint you discover:

```markdown
### `METHOD /path`

- **Source**: `com.example.api.ApiService` (ApiService.java:42)
- **Base URL**: `https://api.example.com/v1`
- **Path params**: `id` (String)
- **Query params**: `page` (int), `limit` (int)
- **Headers**: `Authorization: Bearer <token>`
- **Request body**: `{ "email": "string", "password": "string" }`
- **Response**: `ApiResponse<User>`
- **Called from**: `LoginActivity → LoginViewModel → UserRepository → ApiService`
```

## Notes

This repository also ships a **Claude Code plugin** implementation (scripts, references, and the `/decompile` slash command) under:

- `plugins/android-reverse-engineering/`

