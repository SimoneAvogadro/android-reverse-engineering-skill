# Recovering Original Class Names from Kotlin Metadata

When R8/ProGuard obfuscates a Kotlin app, JVM symbols are renamed but the
**Kotlin metadata strings cannot be stripped** — the Kotlin runtime depends
on them at runtime for reflection, coroutines, and `data class` features.

Two annotations leak the original fully-qualified names:

## `@DebugMetadata`

Generated for nearly every Kotlin coroutine `SuspendLambda` (i.e. almost
every `suspend` function in a modern app):

```java
@DebugMetadata(
    c  = "com.example.feature.account.AccountRepositoryImpl$fetch$1",
    f  = "AccountRepositoryImpl.kt",
    l  = {42, 51},
    m  = "invokeSuspend"
)
public final class a extends SuspendLambda implements Function2<...> { ... }
```

The `c =` field carries the original outer class FQN (with a `$` suffix
for inner / lambda scopes — strip everything after the first `$` to get the
declaring class).

## `@Metadata.d2`

Every Kotlin class carries a top-level `@Metadata` annotation. The `d2`
array lists internal class refs in JVM type-descriptor format
(`Lcom/example/Foo;`):

```java
@Metadata(d1 = {"..."},
          d2 = {"...","Lcom/example/feature/account/AccountRepositoryImpl;","..."})
public final class b implements ... { ... }
```

The first non-stdlib descriptor in `d2` is usually the file's primary
class.

## How to mine them

The skill ships two scripts:

```bash
# Build a mapping from a decompiled sources directory:
bash scripts/recover-kotlin-names.sh <output>/sources [mapping-dir]

# Outputs:
#   <mapping-dir>/mapping.tsv        obf_fqn  real_fqn  file
#   <mapping-dir>/mapping.json       same data, JSON
#   <mapping-dir>/by_package/        per-real-package index files

# Query the mapping:
bash scripts/lookup-name.sh <mapping-dir> Repository                 # search
bash scripts/lookup-name.sh <mapping-dir> -o ab.cd                   # obf -> real
bash scripts/lookup-name.sh <mapping-dir> -p com.example.feature     # list package
bash scripts/lookup-name.sh <mapping-dir> --grep '"api/' <output>/sources
   # ^ greps decompiled code and appends '// real.fqn' to each hit
```

## What you typically recover

On a real-world obfuscated Kotlin app the script recovers **30 – 50 % of
classes** — but more importantly, **almost 100 % of the classes you
actually want to read**:

| Class kind                | Recovery rate |
|---------------------------|---------------|
| `*Repository` / `*Impl`   | ~100 %        |
| `*ViewModel`              | ~100 %        |
| `*UseCase` / `*Interactor`| ~100 %        |
| Plain `data class` DTOs   | ~80 %         |
| Pure-Java helper classes  | low (no Kotlin metadata) |
| Anonymous inner classes   | sometimes recovered as the parent FQN |

## Why `jadx --deobf` is not enough

`--deobf` renames obfuscated identifiers using internal heuristics, but the
output is still synthetic (`p001a`, `C0123Foo`). It does **not** recover
the *original* names. Kotlin metadata recovery is the only reliable way to
map back to the names the developer actually wrote, and it costs essentially
nothing — just a regex pass over the decompiled sources.

Run both: `--deobf` for fields/methods that have no metadata source, plus
the recovery script for class names.

## Limitations

- **Method names and field names** are not recovered. Kotlin metadata only
  preserves class-level FQNs and a few signatures. For method names you
  still need jadx-gui's interactive rename or pattern inference.
- **Pure-Java classes** carry no `@Metadata`, so they remain obfuscated.
- **Heavily inlined classes** (`@JvmInline value class`, top-level fun
  files compiled into shared `*Kt.class` synthetic classes) sometimes show
  up under the wrong filename — treat results as a strong hint, not gospel.

## Reading flow with the mapping

1. Run `recover-kotlin-names.sh` once after decompiling.
2. Use `lookup-name.sh --grep '<pattern>' <sources>` instead of plain `grep`
   so every hit comes annotated with the real owning class.
3. When you hit an obfuscated FQN in code (e.g. `nq.e`), resolve it with
   `lookup-name.sh <mapping-dir> -o nq.e` — you will often see siblings
   (`nq.d`, `nq.f`, ...) that are the same class's split lambdas/inner
   classes, which is useful context.
