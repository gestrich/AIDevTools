---
name: ai-dev-tools-swift-testing
description: >
  Checks and fixes Swift test files for conformance to Swift Testing conventions: replaces
  XCTest assertions with #expect/#require, adds @Test with descriptive sentence-form names,
  converts XCTestExpectation-based async tests to async throws, enforces Arrange-Act-Assert
  structure with blank-line separation, and splits tests covering multiple behaviors into
  separate @Test functions. Use when writing or reviewing Swift test files, when adding new
  tests to this project, or when ai-dev-tools-enforce is running.
user-invocable: true
---

# Swift Testing Conventions

Your job is to **fix** test convention violations, not write a review. When you find a violation, make the change. This applies to new test files and any test files modified in the current diff.

---

## XCTest Assertions → Swift Testing

New tests use `#expect` and `#require` from Swift Testing, not `XCTAssert*`. If the test file already uses `XCTestCase`, migrate the entire file to `@Suite`/`@Test` rather than mixing styles.

**Replacements:**

| XCTest | Swift Testing |
|--------|--------------|
| `XCTAssertEqual(a, b)` | `#expect(a == b)` |
| `XCTAssertNil(x)` | `#expect(x == nil)` |
| `XCTAssertNotNil(x)` | `#require(x != nil)` or `let x = try #require(optional)` |
| `XCTAssertTrue(condition)` | `#expect(condition)` |
| `XCTAssertFalse(condition)` | `#expect(!condition)` |
| `XCTAssertThrowsError(try foo())` | `#expect(throws: Error.self) { try foo() }` |
| `XCTFail("message")` | `Issue.record("message")` |

---

## `@Test` with Descriptive Names

**Look for:** Test functions named `testFoo`, `test_foo`, or `testFooWhenBarExpectsBaz`.

**Fix:** Rename to sentence-form and add `@Test("...")`:

```swift
// Before
func testLoadStepsReturnsCorrectCount() { ... }

// After
@Test("loadSteps returns one step per ## heading")
func loadStepsReturnsCorrectCount() { ... }
```

Group related tests under a `@Suite` struct named after the type under test. Use `@Suite("...")` for nested scenario groups.

---

## Async Tests → `async throws`

**Look for:** `XCTestExpectation`, `fulfill()`, `waitForExpectations(timeout:)`, `wait(for:timeout:)`.

**Fix:** Convert to `async throws` and `await` the result directly:

```swift
// Before
func testAsyncLoad() {
    let expectation = expectation(description: "loaded")
    service.load { _ in expectation.fulfill() }
    waitForExpectations(timeout: 1)
}

// After
@Test("load completes with expected result")
func asyncLoad() async throws {
    let result = try await service.load()
    #expect(result.count == 3)
}
```

---

## Arrange-Act-Assert Structure

**Look for:** Test functions that intermix setup, invocation, and assertion without clear visual separation.

**Fix:** Three sections separated by blank lines:
1. **Arrange** — create the subject under test and its dependencies
2. **Act** — call the one method or path being tested
3. **Assert** — verify with `#expect` or `#require` only

If Arrange is more than ~5 lines, extract a helper or use `@Suite init()` / `deinit` for shared setup.

---

## One Behavior Per Test

**Look for:** Test functions with multiple unrelated `#expect` calls on different outcomes, or tests that cover both the happy path and an error path in the same function.

**Fix:** Split into separate `@Test` functions, one per behavior. Two assertions on the same result object are fine; assertions on two different code paths are not. A failing test should point at exactly one thing.
