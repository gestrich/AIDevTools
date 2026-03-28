/// Unit tests for SpecContent and SpecTask domain models
import XCTest
import Foundation
@testable import ClaudeChainService

final class TestSpecTaskFromMarkdownLine: XCTestCase {
    /// Test suite for SpecTask.fromMarkdownLine factory method
    
    func testFromMarkdownLineWithUncompletedTask() {
        /// Should parse uncompleted task from markdown
        let line = "- [ ] Implement feature X"
        let index = 1
        
        let task = SpecTask.fromMarkdownLine(line, index: index)
        
        XCTAssertNotNil(task)
        XCTAssertEqual(task?.index, 1)
        XCTAssertEqual(task?.description, "Implement feature X")
        XCTAssertEqual(task?.isCompleted, false)
        XCTAssertEqual(task?.rawLine, line)
        XCTAssertEqual(task?.taskHash, generateTaskHash("Implement feature X"))
    }
    
    func testFromMarkdownLineWithCompletedTaskLowercaseX() {
        /// Should parse completed task with lowercase [x]
        let line = "- [x] Fix bug Y"
        let index = 2
        
        let task = SpecTask.fromMarkdownLine(line, index: index)
        
        XCTAssertNotNil(task)
        XCTAssertEqual(task?.index, 2)
        XCTAssertEqual(task?.description, "Fix bug Y")
        XCTAssertEqual(task?.isCompleted, true)
        XCTAssertEqual(task?.rawLine, line)
    }
    
    func testFromMarkdownLineWithCompletedTaskUppercaseX() {
        /// Should parse completed task with uppercase [X]
        let line = "- [X] Add tests"
        let index = 3
        
        let task = SpecTask.fromMarkdownLine(line, index: index)
        
        XCTAssertNotNil(task)
        XCTAssertEqual(task?.index, 3)
        XCTAssertEqual(task?.description, "Add tests")
        XCTAssertEqual(task?.isCompleted, true)
    }
    
    func testFromMarkdownLineWithLeadingWhitespace() {
        /// Should handle task with leading whitespace
        let line = "  - [ ] Task with indent"
        let index = 1
        
        let task = SpecTask.fromMarkdownLine(line, index: index)
        
        XCTAssertNotNil(task)
        XCTAssertEqual(task?.description, "Task with indent")
        XCTAssertEqual(task?.isCompleted, false)
    }
    
    func testFromMarkdownLineWithExtraSpacesInDescription() {
        /// Should trim whitespace from description
        let line = "- [ ]   Task with extra spaces   "
        let index = 1
        
        let task = SpecTask.fromMarkdownLine(line, index: index)
        
        XCTAssertNotNil(task)
        XCTAssertEqual(task?.description, "Task with extra spaces")
    }
    
    func testFromMarkdownLineReturnsNilForInvalidFormat() {
        /// Should return nil for non-task lines
        let invalidLines = [
            "# Heading",
            "Regular paragraph text",
            "- Not a checkbox",
            "* [ ] Wrong bullet",
            "[ ] No bullet",
            "",
            "- [?] Invalid checkbox",
        ]
        
        for line in invalidLines {
            let task = SpecTask.fromMarkdownLine(line, index: 1)
            XCTAssertNil(task, "Should return nil for: \(line)")
        }
    }
    
    func testFromMarkdownLineWithEmptyDescription() {
        /// Should handle empty description gracefully
        let line = "- [ ] "
        
        let task = SpecTask.fromMarkdownLine(line, index: 1)
        
        // Swift implementation allows empty descriptions
        XCTAssertNotNil(task)
        XCTAssertEqual(task?.description, "")
        XCTAssertFalse(task!.isCompleted)
    }
    
    func testFromMarkdownLineWithComplexDescription() {
        /// Should handle complex descriptions with special characters
        let line = "- [ ] Add support for API v2.0 & webhook notifications (priority: high)"
        
        let task = SpecTask.fromMarkdownLine(line, index: 1)
        
        XCTAssertNotNil(task)
        XCTAssertEqual(task?.description, "Add support for API v2.0 & webhook notifications (priority: high)")
        XCTAssertEqual(task?.isCompleted, false)
    }
}

final class TestSpecTaskToMarkdownLine: XCTestCase {
    /// Test suite for SpecTask.toMarkdownLine method
    
    func testToMarkdownLineForUncompletedTask() {
        /// Should generate correct markdown for uncompleted task
        let task = SpecTask(
            index: 1,
            description: "Implement feature X",
            isCompleted: false,
            rawLine: "- [ ] Implement feature X",
            taskHash: "abc12345"
        )
        
        let markdown = task.toMarkdownLine()
        
        XCTAssertEqual(markdown, "- [ ] Implement feature X")
    }
    
    func testToMarkdownLineForCompletedTask() {
        /// Should generate correct markdown for completed task
        let task = SpecTask(
            index: 2,
            description: "Fix bug Y",
            isCompleted: true,
            rawLine: "- [x] Fix bug Y",
            taskHash: "def67890"
        )
        
        let markdown = task.toMarkdownLine()
        
        XCTAssertEqual(markdown, "- [x] Fix bug Y")
    }
}

final class TestGenerateTaskHash: XCTestCase {
    /// Test suite for generateTaskHash function
    
    func testGenerateTaskHashConsistent() {
        /// Should generate consistent hash for same description
        let description = "Implement feature X"
        
        let hash1 = generateTaskHash(description)
        let hash2 = generateTaskHash(description)
        
        XCTAssertEqual(hash1, hash2)
        XCTAssertEqual(hash1.count, 8)
    }
    
    func testGenerateTaskHashDifferentForDifferentDescriptions() {
        /// Should generate different hashes for different descriptions
        let desc1 = "Implement feature X"
        let desc2 = "Implement feature Y"
        
        let hash1 = generateTaskHash(desc1)
        let hash2 = generateTaskHash(desc2)
        
        XCTAssertNotEqual(hash1, hash2)
    }
    
    func testGenerateTaskHashNormalizesWhitespace() {
        /// Should generate same hash after whitespace normalization
        let desc1 = "Add user authentication"
        let desc2 = "  Add user authentication  "
        let desc3 = "Add   user    authentication"
        
        let hash1 = generateTaskHash(desc1)
        let hash2 = generateTaskHash(desc2)
        let hash3 = generateTaskHash(desc3)
        
        XCTAssertEqual(hash1, hash2)
        XCTAssertEqual(hash1, hash3)
    }
    
    func testGenerateTaskHashIsLowercaseHex() {
        /// Should return lowercase hexadecimal string
        let hash = generateTaskHash("Test description")
        
        XCTAssertEqual(hash.count, 8)
        XCTAssertTrue(hash.allSatisfy { "0123456789abcdef".contains($0) })
    }
    
    func testGenerateTaskHashForEmptyString() {
        /// Should handle empty string
        let hash = generateTaskHash("")
        
        XCTAssertEqual(hash.count, 8)
    }
}

final class TestSpecContentParsing: XCTestCase {
    /// Test suite for SpecContent parsing functionality
    
    func testSpecContentInitialization() {
        /// Should initialize with project and content
        let project = Project(name: "test-project")
        let content = "# Project\n\n- [ ] Task 1\n- [x] Task 2"
        
        let spec = SpecContent(project: project, content: content)
        
        XCTAssertEqual(spec.project.name, "test-project")
        XCTAssertEqual(spec.content, content)
    }
    
    func testSpecContentParsesTasks() {
        /// Should parse all tasks from content
        let project = Project(name: "test-project")
        let content = """
# Project Specification

## Tasks

- [ ] Task 1 - First task
- [x] Task 2 - Second task (completed)
- [ ] Task 3 - Third task

## Notes

This is not a task.

- [ ] Task 4 - Fourth task
"""
        
        let spec = SpecContent(project: project, content: content)
        let tasks = spec.tasks
        
        XCTAssertEqual(tasks.count, 4)
        XCTAssertEqual(tasks[0].index, 1)
        XCTAssertEqual(tasks[0].description, "Task 1 - First task")
        XCTAssertEqual(tasks[0].isCompleted, false)
        
        XCTAssertEqual(tasks[1].index, 2)
        XCTAssertEqual(tasks[1].description, "Task 2 - Second task (completed)")
        XCTAssertEqual(tasks[1].isCompleted, true)
        
        XCTAssertEqual(tasks[2].index, 3)
        XCTAssertEqual(tasks[2].description, "Task 3 - Third task")
        XCTAssertEqual(tasks[2].isCompleted, false)
        
        XCTAssertEqual(tasks[3].index, 4)
        XCTAssertEqual(tasks[3].description, "Task 4 - Fourth task")
        XCTAssertEqual(tasks[3].isCompleted, false)
    }
    
    func testSpecContentCountMethods() {
        /// Should correctly count tasks
        let project = Project(name: "test-project")
        let content = """
- [x] Completed task 1
- [x] Completed task 2
- [ ] Pending task 1
- [ ] Pending task 2
- [ ] Pending task 3
"""
        
        let spec = SpecContent(project: project, content: content)
        
        XCTAssertEqual(spec.totalTasks, 5)
        XCTAssertEqual(spec.completedTasks, 2)
        XCTAssertEqual(spec.pendingTasks, 3)
    }
    
    func testSpecContentGetTaskByIndex() {
        /// Should return correct task by index
        let project = Project(name: "test-project")
        let content = """
- [ ] Task 1
- [ ] Task 2
- [ ] Task 3
"""
        
        let spec = SpecContent(project: project, content: content)
        
        let task1 = spec.getTaskByIndex(1)
        XCTAssertNotNil(task1)
        XCTAssertEqual(task1?.description, "Task 1")
        XCTAssertEqual(task1?.index, 1)
        
        let task3 = spec.getTaskByIndex(3)
        XCTAssertNotNil(task3)
        XCTAssertEqual(task3?.description, "Task 3")
        XCTAssertEqual(task3?.index, 3)
        
        // Out of range
        XCTAssertNil(spec.getTaskByIndex(0))
        XCTAssertNil(spec.getTaskByIndex(4))
    }
    
    func testSpecContentGetNextAvailableTask() {
        /// Should return next uncompleted task
        let project = Project(name: "test-project")
        let content = """
- [x] Completed task 1
- [ ] Available task 1
- [ ] Available task 2
- [x] Completed task 2
"""
        
        let spec = SpecContent(project: project, content: content)
        
        let nextTask = spec.getNextAvailableTask()
        XCTAssertNotNil(nextTask)
        XCTAssertEqual(nextTask?.description, "Available task 1")
        XCTAssertEqual(nextTask?.index, 2)
    }
    
    func testSpecContentGetNextAvailableTaskWithSkipHashes() {
        /// Should skip tasks in skipHashes set
        let project = Project(name: "test-project")
        let content = """
- [ ] Task 1
- [ ] Task 2
- [ ] Task 3
"""
        
        let spec = SpecContent(project: project, content: content)
        let tasks = spec.tasks
        
        // Skip first task by hash
        let skipHashes = Set([tasks[0].taskHash])
        let nextTask = spec.getNextAvailableTask(skipHashes: skipHashes)
        
        XCTAssertNotNil(nextTask)
        XCTAssertEqual(nextTask?.description, "Task 2")
        XCTAssertEqual(nextTask?.index, 2)
    }
    
    func testSpecContentGetNextAvailableTaskAllCompleted() {
        /// Should return nil when all tasks completed
        let project = Project(name: "test-project")
        let content = """
- [x] Completed task 1
- [x] Completed task 2
- [x] Completed task 3
"""
        
        let spec = SpecContent(project: project, content: content)
        
        let nextTask = spec.getNextAvailableTask()
        XCTAssertNil(nextTask)
    }
    
    func testSpecContentGetPendingTaskIndices() {
        /// Should return indices of pending tasks
        let project = Project(name: "test-project")
        let content = """
- [x] Completed task 1
- [ ] Pending task 1
- [ ] Pending task 2
- [x] Completed task 2
- [ ] Pending task 3
"""
        
        let spec = SpecContent(project: project, content: content)
        
        let pendingIndices = spec.getPendingTaskIndices()
        XCTAssertEqual(pendingIndices, [2, 3, 5])
    }
    
    func testSpecContentToMarkdown() {
        /// Should convert tasks back to markdown
        let project = Project(name: "test-project")
        let content = """
- [ ] Task 1
- [x] Task 2
- [ ] Task 3
"""
        
        let spec = SpecContent(project: project, content: content)
        
        let markdown = spec.toMarkdown()
        let expected = """
- [ ] Task 1
- [x] Task 2
- [ ] Task 3
"""
        XCTAssertEqual(markdown, expected)
    }
    
    func testSpecContentWithNoTasks() {
        /// Should handle content with no tasks
        let project = Project(name: "test-project")
        let content = """
# Project Specification

This is a project without any tasks yet.

## Future Plans

We will add tasks later.
"""
        
        let spec = SpecContent(project: project, content: content)
        
        XCTAssertEqual(spec.totalTasks, 0)
        XCTAssertEqual(spec.completedTasks, 0)
        XCTAssertEqual(spec.pendingTasks, 0)
        XCTAssertNil(spec.getNextAvailableTask())
        XCTAssertEqual(spec.getPendingTaskIndices(), [])
        XCTAssertEqual(spec.toMarkdown(), "")
    }
    
    func testSpecContentTasksPropertyLazyLoading() {
        /// Should lazily load tasks and cache them
        let project = Project(name: "test-project")
        let content = "- [ ] Task 1\n- [ ] Task 2"
        
        let spec = SpecContent(project: project, content: content)
        
        // Access tasks multiple times - should parse only once
        let tasks1 = spec.tasks
        let tasks2 = spec.tasks
        
        XCTAssertEqual(tasks1.count, 2)
        XCTAssertEqual(tasks2.count, 2)
        // Note: Arrays are value types in Swift, so we can't test reference equality
        // This test verifies the tasks are loaded correctly
        XCTAssertEqual(tasks1[0].description, tasks2[0].description)
        XCTAssertEqual(tasks1[1].description, tasks2[1].description)
    }
}