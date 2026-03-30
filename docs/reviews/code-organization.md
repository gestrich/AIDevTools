## - [ ] Code Review: Review the code changes that have been made in these tasks for the following: Split files that define multiple unrelated types into one file per type, and make the necessary code changes

Look for files that contain more than one `struct`, `class`, `enum`, or `protocol` at the top level where those types are not tightly coupled (e.g., a primary type and its dedicated subtype is fine; two independent feature types in the same file is not).

Fix: create one file per top-level type, named after that type (e.g., `ImportConfig.swift`, `ImportResult.swift`). Update any imports or references as needed. This makes it easier to navigate the codebase, reduces merge conflicts, and makes the file's purpose unambiguous.

---

## - [ ] Code Review: Review the code changes that have been made in these tasks for the following: Move supporting enums and nested types below their primary type, not above it, and make the necessary code changes

Look for files where helper `enum`s, supporting `struct`s, or protocol conformances appear before the primary type declaration, forcing readers to scroll past them before seeing the main type.

Fix: order file contents so the primary type comes first (including its properties and methods), followed by supporting types, extensions, and conformances. A reader opening the file should immediately see the type they came to read.
