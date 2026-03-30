## - [ ] Code Review: Review the code changes that have been made in these tasks for the following: Find fallback values that hide failures and suppressed errors — remove or replace both with proper propagation, and make the necessary code changes

Look for:
- `?? ""`, `?? []`, `?? 0`, `?? false` on paths that should never be nil
- `guard ... else { return }` that silently exits when a failure should be reported
- `try? expr ?? defaultValue` discarding the error silently
- `catch { }` — empty catch block
- `catch { print("...") }` — logged but not propagated
- `try?` where the error is discarded and the `nil` result is not explicitly handled
- `Task { try? await ... }` — fire-and-forget that swallows failures
- `continuation.finish()` called in a catch block instead of `continuation.finish(throwing: error)`

Fix: replace fallbacks with `throws`, `guard let ... else { throw ... }`, or a `precondition`/`fatalError` with a clear message. For suppressed errors, add `throws` to the enclosing function and rethrow, or propagate via `continuation.finish(throwing: error)`. At the Apps layer, catch errors from use cases and set an `.error` state so the UI can display the failure. Only keep a fallback if the default value is semantically correct (e.g., a preference with a genuine default).

---

## - [ ] Code Review: Review the code changes that have been made in these tasks for the following: Remove backwards compatibility shims added before release — there is no backwards compatibility obligation for unreleased code, and make the necessary code changes

Look for:
- Deprecated `typealias` pointing to a new name
- `@available(*, deprecated, renamed: "...")` on types or methods in code that hasn't shipped
- Old method signatures kept alongside new ones with a `// TODO: remove` comment
- Adapter or wrapper types that exist solely to bridge an old interface to a new one within the same codebase

Fix: delete the shim entirely. Update all call sites to use the new API directly. If the call sites are in the same PR, there is no reason to keep both. Backwards compatibility only matters once an API is public and has external consumers.

---

## - [ ] Code Review: Review the code changes that have been made in these tasks for the following: Replace `String`, `[String: Any]`, and raw dictionary types in APIs with proper typed models, and make the necessary code changes

Look for method signatures that accept or return `String` where a more specific type exists (e.g., a status code, an identifier, a file path), `[String: Any]` or `[String: String]` dictionaries, `Any` parameters, and JSON-decoded results stored as dictionaries rather than `Decodable` structs.

Fix: define a `struct` or `enum` with named, typed fields. For identifiers, consider a `struct FooID: RawRepresentable` wrapper rather than a bare `String` to prevent mixing up different ID spaces. For JSON responses, define a `Decodable` model. The goal is for the compiler to catch type errors rather than discovering them at runtime.

---

## - [ ] Code Review: Review the code changes that have been made in these tasks for the following: Replace optional types with non-optional where the value must be present, and make the necessary code changes

Look for `var foo: Foo?` on properties that are always set during initialization, optional return types on methods that always return a value, and `init` parameters that are optional but are required for the type to function correctly.

Fix:
- If the value is known at init time, make it a non-optional stored property and require it in `init`
- If the value might not exist yet at init, use a failable initializer `init?` or `throws` rather than storing an optional and checking it everywhere
- If the value is required for an operation to proceed, `guard let` at the call site and throw or return an error rather than silently doing nothing when nil

Optional should mean "this value genuinely may not exist." It should not mean "I wasn't sure how to get this value at initialization time."

---

## - [ ] Code Review: Review the code changes that have been made in these tasks for the following: Remove AI-changelog-style comments and replace with concise documentation or remove entirely, and make the necessary code changes

Look for comments that describe what was changed rather than what the code does:
- `// Changed X to Y for new behavior`
- `// Added Z to support the new flow`
- `// Previously this was a class, now it's a struct`
- `// Updated to use the new API`
- `// Removed old implementation`

These comments are git log entries written in the wrong place. They become noise immediately after the PR merges and mislead future readers.

Fix: delete the comment. If something genuinely needs explanation (a non-obvious algorithm, a workaround for a known bug, a performance trade-off), replace it with a comment that explains **why** the code does what it does, not what it used to do before.

---

## - [ ] Code Review: Review the code changes that have been made in these tasks for the following: Find duplicated logic and consolidate into a single shared implementation, and make the necessary code changes

Look for:
- The same condition or predicate written in multiple places (e.g., checking whether a state is valid in three different methods)
- The same sequence of operations repeated across two use cases or services
- Identical `switch` arms or `if/else` chains in multiple files

Fix: extract the duplicated logic into a single function, computed property, or type that all sites call. For value-level duplication, a free function or extension is often sufficient. For structural duplication across use cases, consider whether shared logic belongs in a Service. Do not create an abstraction if there are only two instances and they are likely to diverge — use judgement.

---

## - [ ] Code Review: Review the code changes that have been made in these tasks for the following: Replace force unwraps with proper optional handling, and make the necessary code changes

Look for `!` used to force-unwrap optionals in any context other than tests or `IBOutlet`s. Specifically find: `foo!`, `try!`, and `as!` casts in production code paths.

Fix:
- `foo!` → `guard let foo else { throw FooError.missing }` or `guard let foo else { return }` with an appropriate error log
- `try!` → `try` with the enclosing function marked `throws`, or wrap in a `do/catch` that sets error state
- `as!` → `as?` with explicit handling of the nil case, or reconsider the type hierarchy so the cast is unnecessary

A force unwrap is a bet that a condition is impossible. When that bet is wrong it crashes in production. Replace bets with proofs (non-optional types) or recoverable errors.
