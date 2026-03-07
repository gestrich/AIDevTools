import Testing
import EvalService

// Tests the "swift-copyright-header" skill with both positive (should pass)
// and negative (expected failure) eval cases.
//
// Positive cases: tasks within the skill's scope — should produce correct output.
// Negative cases: tasks outside the skill's scope — the skill should NOT trigger,
// and the eval framework should correctly detect the failure if it does.

enum CopyrightHeaderEvals {

    // MARK: - Positive Cases (skill CAN do this)

    static let positiveCases: [EvalCase] = [
        EvalCase(
            id: "add-header-basic",
            suite: "copyright-header",
            skillHint: "explicit",
            shouldTrigger: true,
            task: "Add the Acme Corp copyright header to this Swift file",
            input: """
            import Foundation

            struct MyModel {
                let name: String
            }
            """,
            mustInclude: ["Copyright", "Acme Corp", "import Foundation", "struct MyModel"],
            mustNotInclude: ["TODO", "FIXME", "Author"]
        ),
        EvalCase(
            id: "add-header-preserves-code",
            suite: "copyright-header",
            skillHint: "explicit",
            shouldTrigger: true,
            task: "Add the Acme Corp copyright header to this Swift file",
            input: """
            import UIKit

            class ViewController: UIViewController {
                override func viewDidLoad() {
                    super.viewDidLoad()
                }
            }
            """,
            mustInclude: ["Copyright", "Acme Corp", "import UIKit", "ViewController", "viewDidLoad"],
            mustNotInclude: ["TODO", "FIXME"]
        ),
        EvalCase(
            id: "replace-existing-header",
            suite: "copyright-header",
            skillHint: "explicit",
            shouldTrigger: true,
            task: "Add the Acme Corp copyright header to this Swift file (replace any existing header)",
            input: """
            // Created by John on 2024-01-15
            // Some old copyright notice

            import SwiftUI

            struct ContentView: View {
                var body: some View {
                    Text("Hello")
                }
            }
            """,
            mustInclude: ["Copyright", "Acme Corp", "import SwiftUI", "ContentView"],
            mustNotInclude: ["Created by John", "old copyright"]
        ),
    ]

    // MARK: - Negative Cases (skill CANNOT do this — should fail)

    static let negativeCases: [EvalCase] = [
        EvalCase(
            id: "not-swift-python",
            suite: "copyright-header",
            skillHint: "explicit",
            shouldTrigger: false,
            task: "Add the Acme Corp copyright header to this Python file",
            input: """
            import os

            def main():
                print("hello")
            """,
            mustNotInclude: ["// Copyright"]
        ),
        EvalCase(
            id: "not-swift-objc",
            suite: "copyright-header",
            skillHint: "explicit",
            shouldTrigger: false,
            task: "Convert this Objective-C code to Swift",
            input: """
            #import <Foundation/Foundation.h>

            @interface MyClass : NSObject
            @property (nonatomic, strong) NSString *name;
            @end
            """,
            mustNotInclude: ["// Copyright © Acme Corp"]
        ),
        EvalCase(
            id: "unrelated-task-write-tests",
            suite: "copyright-header",
            skillHint: "explicit",
            shouldTrigger: false,
            task: "Write unit tests for this function",
            input: """
            func add(_ a: Int, _ b: Int) -> Int {
                return a + b
            }
            """,
            mustNotInclude: ["// Copyright © Acme Corp"]
        ),
    ]

    static let allCases: [EvalCase] = positiveCases + negativeCases
}

@Suite("Copyright Header Evals — Positive", .tags(.integration), .enabled(if: IntegrationTest.isEnabled))
struct CopyrightHeaderPositiveEvalTests {

    @Test(arguments: CopyrightHeaderEvals.positiveCases)
    func evalCase(_ eval: EvalCase) async throws {
        try await runEval(eval)
    }
}

@Suite("Copyright Header Evals — Negative", .tags(.integration), .enabled(if: IntegrationTest.isEnabled))
struct CopyrightHeaderNegativeEvalTests {

    @Test(arguments: CopyrightHeaderEvals.negativeCases)
    func evalCaseExpectingFailure(_ eval: EvalCase) async throws {
        try await runEvalExpectingFailure(eval)
    }
}
