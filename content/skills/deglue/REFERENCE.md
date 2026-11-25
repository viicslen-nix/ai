# Deglue reference

The four categories a detector looks for. Each section gives the signals that flag a candidate, the rules for keeping one, and the shape of the fix. The examples are language-agnostic; apply them in the repo's own idiom.

## Glue

A class, method, function or module whose only job is to call something else. Removing it changes no behaviour. The test is why it survives: glue is an old abstraction kept alive only so existing callers don't have to change, not every one-line delegation.

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
- It is a deliberate split: a front door that must expose the method (an adapter implementing a contract) hands each concern to its own focused helper, e.g. `EbayAdapter::createProfiles()` → `Policies::create()` beside `ListingReads` / `ListingWrites`. The one-line handoff keeps each helper's logic separate; it is not keeping old callers happy.
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

## Bugs

Leftover code that no longer does what it claims, because the migration changed something underneath it. Rank these above every cleanup row.

**Signals**
- A comparison against a value the code never produces, e.g. `$offer->status === 'Pending'` when the status reads back as enum names such as `Open` or `CounteredBuyer`. The branch is dead.
- A config key, attribute, relation or method that the migration renamed, or that was never defined. It reads as null, so the check is always empty.
- A conversion the new core already does, still done again by an old caller. For example, `$paid * 100` going into a cast that already stores minor units.
- An inverted or swapped condition next to code the migration touched. The cause may predate the migration; date it with `git log -S`.

**Prove it:** write a test that fails on the current code and passes after the fix. Then mark the row **proven**. If the test passes on the current code, the row is **disproven**; drop it. When the bug writes data, find the date it went live and count the rows written in that window (on a production read replica if there is one). Report the count. Repairing that data is a separate decision for the user.

**Not a bug when** production no longer reaches the code, for example because a related service now owns that entrypoint. Report it as an orphan under glue instead.

**Fix:** the smallest change that makes the test pass, in its own commit ahead of the cleanup.

## Row format

```
file:line | bug|glue|stringly|twin | target / literal / twin location | callers: N | introduced: <sha> | proven|disproven|unproven (bugs only) | fix|remove|inline|enum|merge|keep|report-only — reason
```
