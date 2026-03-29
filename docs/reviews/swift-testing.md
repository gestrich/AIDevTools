## - [ ] Verify new tests use Swift Testing (`#expect`, `#require`) rather than XCTest assertions

Look for `XCTAssert`, `XCTAssertEqual`, `XCTAssertNil`, `XCTAssertNotNil`, `XCTAssertTrue`, `XCTAssertFalse`, `XCTAssertThrowsError`, and `XCTFail` in new test files. New tests should use the Swift Testing framework's `#expect` and `#require` macros instead.

Fix: replace XCTest assertions with their Swift Testing equivalents:
- `XCTAssertEqual(a, b)` → `#expect(a == b)`
- `XCTAssertNil(x)` → `#expect(x == nil)`
- `XCTAssertNotNil(x)` → `#require(x != nil)` (or `let x = try #require(optional)`)
- `XCTAssertTrue(condition)` → `#expect(condition)`
- `XCTAssertThrowsError(try foo())` → `#expect(throws: Error.self) { try foo() }`
- `XCTFail("message")` → `Issue.record("message")`

If the test file already uses `XCTestCase`, migrate the entire file to `@Suite` / `@Test` rather than mixing styles.

---

## - [ ] Verify test functions use `@Test` and descriptive names in sentence form

Look for test functions named `testFoo`, `test_foo`, or `testFooWhenBarExpectsBaz`. Swift Testing uses `@Test` with a descriptive string label instead.

Fix: rename test functions to sentence-form descriptions and add the `@Test("...")` attribute:
- `func testLoadStepsReturnsCorrectCount()` → `@Test("loadSteps returns one step per ## - [ ] heading") func loadStepsReturnsCorrectCount()`

Group related tests under a `@Suite` struct (named after the type under test) and use `@Suite("...")` for nested scenario groups.

---

## - [ ] Verify async tests use `async throws` rather than `XCTestExpectation`

Look for `XCTestExpectation`, `fulfill()`, `waitForExpectations(timeout:)`, and `wait(for:timeout:)` in test files. These are XCTest concurrency patterns; Swift Testing supports `async` natively.

Fix: convert the test function to `async throws` and `await` the result directly:

```swift
// Before
func testAsyncLoad() {
    let expectation = expectation(description: "loaded")
    service.load { result in expectation.fulfill() }
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

## - [ ] Verify tests follow Arrange-Act-Assert structure with a blank line between sections

Look for test functions that intermix setup, invocation, and assertion without clear visual separation.

Fix: organize each test into three sections separated by blank lines:
1. **Arrange** — create the subject under test and its dependencies
2. **Act** — call the one method or path being tested
3. **Assert** — verify the result with `#expect` or `#require`

If the arrange section is more than ~5 lines, extract a helper or use `@Suite` `init()` / `deinit` for shared setup.

---

## - [ ] Verify each test covers exactly one behavior and rename or split tests that cover multiple

Look for test functions that contain multiple unrelated `#expect` calls on different outcomes, or that test both the happy path and an error path in the same function.

Fix: split into separate `@Test` functions, one per behavior. A test that fails should point at one thing. Two assertions on the same result object are fine; assertions on two different code paths are not.
