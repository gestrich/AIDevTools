---
name: ai-dev-tools-code-organization
description: >
  Checks and fixes Swift file and type organization: splits files containing multiple
  unrelated top-level types into one file per type, moves supporting enums and nested types
  below the primary type they support, and renames files whose name doesn't match their
  primary type. Use when reviewing Swift file structure, when a file feels hard to navigate,
  or when ai-dev-tools-enforce is running.
user-invocable: true
---

# Code Organization

Your job is to **fix** organization issues, not write a review. When you find a violation, make the change.

---

## One File Per Type

**Look for:** Files that contain more than one `struct`, `class`, `enum`, or `protocol` at the top level where those types are not tightly coupled. A primary type and its dedicated supporting subtype in the same file is fine; two independent feature types in the same file is not.

**Fix:** Create one file per top-level type, named after that type (e.g., `ImportConfig.swift`, `ImportResult.swift`). Update any imports or references as needed.

---

## Supporting Types Below the Primary Type

**Look for:** Files where helper `enum`s, supporting `struct`s, or protocol conformances appear *before* the primary type declaration, forcing readers to scroll past them before seeing the main type.

**Fix:** Order file contents so the primary type comes first (including its properties and methods), followed by supporting types, extensions, and conformances. A reader opening the file should immediately see the type they came to read.

---

## Nested Type Definitions Inside Methods

**Look for:** A `struct`, `class`, `actor`, or `enum` defined inside a function or method body rather than at file scope. This makes the type impossible to reference from outside the method and buries it in a long method body.

**Fix:** Move the type to a `private` declaration at file scope (above or below the containing class/struct), or nest it inside the class if it's only used by that class. File scope is preferred when the type has enough logic to be read independently.

---

## Filename Matches Primary Type

**Look for:** Files named after a type that was removed or renamed (e.g., `ProviderTypes.swift` whose sole remaining type is `SkillCheckResult`).

**Fix:** Rename the file to match the primary type it contains.
