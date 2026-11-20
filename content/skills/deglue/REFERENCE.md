# Deglue reference

The three categories a detector looks for. Each section gives the signals that flag a candidate, the rules for keeping one, and the shape of the fix. The examples are language-agnostic; apply them in the repo's own idiom.

## Glue

A class, method, function or module whose only job is to call something else. Removing it changes no behaviour.

**Signals**
- The body is one call to another unit, plus argument reshaping (rename, reorder, wrap into or unwrap from a DTO, fill a default), and it passes the result straight back.
- Its name mirrors the target, e.g. `GetFoo::handle()` → `$client->foo()`, or `FooService::bar()` → `Package::bar()`.
- It is a manager, facade, adapter or bridge over exactly one implementation, or an interface with one implementation that tests never fake.
- It is a DTO round trip: A → B → A, or a mapper that copies fields one-to-one under the same names.
- It is a compatibility shim: an old config key that reads the new key, an alias class, a re-export, a method marked `@deprecated` that forwards.
- It is an **orphan**: the migration left it with zero callers. Delete it.

**Keep it when** it does any one of these:
- It has more than one entrypoint: it also runs as a queued job, controller, listener, command or scheduled task.
- It holds logic: locking, transactions, retries, authorization, caching, logging, tenancy or scope setup, error translation, or validation at a trust boundary.
- Its name is an **external contract**: an external service calls it by name; its class name is serialized into queue payloads, database rows (polymorphic types, stored job names) or cache keys; it is a route or webhook another system calls; or it is a package's public API.
- It is a seam that hides a third-party boundary, such as an HTTP client or SDK, and tests substitute it. A pass-through that tests only mock (`shouldRun`, `mock(Wrapper)`) is still glue: fake the dependency underneath instead.

**Fix:** point every caller at the target, then delete the wrapper and its binding, alias and tests. For a queued job class still in flight, keep a stub that forwards to the new code for one release, and say so in the report.

## Stringly-typed

A string literal that stands for one member of a closed set.

**Signals**
- A literal in a `match`/`switch` arm, a `===` comparison, `in_array`, a validation `in:` rule or `Rule::in([...])`, a default parameter value, a select-option list, or a constant array of allowed values.
- An enum or constant set for that value already exists, in the app or in the new core. Search the new core first: migrations often replace an old SDK's `*Type::C_*` constants with raw strings.
- The same literal appears in three or more files.
- A value goes through `->value` early and then travels several layers as a plain `string`.
- No enum exists yet, but the set is closed and appears in two or more places. Propose one, in the repo's enum style.

**Keep the string when** the set is open (free text, or IDs from a third party that grow without notice), or when the literal appears once at a boundary that only accepts a string.

**Fix:** type the parameters, properties and return types with the enum. Convert at the boundary: request validation (`Rule::enum`), a model attribute cast, or payload parsing. Unwrap to a string only where an API needs one. Before switching a persisted column, compare its distinct stored values against the enum's backing values; any value outside the enum needs a data fix or a tolerant parse.

## Twins

The same logic in two or more places, often an old copy beside a new one.

**Signals**
- Old and new code paths both still exist, and both are reachable.
- The same field mapping, query builder, validation rules, constant set or formatting helper appears in more than one file.
- Two helpers with different names return the same thing for the same input.
- Request rules repeat in an action, or a model scope repeats inline in a controller or job.

**Keep both when** the copies differ on purpose (different invariants, or different consumers that will evolve separately), or when merging them would need an abstraction neither copy wants. Two short literal copies are cheaper than a forced helper.

**Fix:** pick the newer or better-tested copy as the single source of truth, redirect the other copy's callers to it, then delete the other copy. If a shared helper is genuinely needed, put it next to its strongest consumer, in the repo's existing style for helpers, scopes and value objects.

## Row format

```
file:line | glue|stringly|twin | target / literal / twin location | callers: N | introduced: <sha> | remove|inline|enum|merge|keep|report-only — reason
```
