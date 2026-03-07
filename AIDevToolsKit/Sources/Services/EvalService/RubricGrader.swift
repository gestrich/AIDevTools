import Foundation

public struct RubricGrader: Sendable {

    public init() {}

    public func grade(
        case evalCase: EvalCase,
        rubricPayload: RubricPayload
    ) -> [String] {
        var errors: [String] = []
        guard let rubric = evalCase.rubric else { return errors }

        let requireOverallPass = rubric.requireOverallPass ?? true
        if requireOverallPass && !rubricPayload.overallPass {
            errors.append("rubric overall_pass=false")
        }

        if let minScore = rubric.minScore {
            if rubricPayload.score < minScore {
                errors.append("rubric score below threshold: \(rubricPayload.score) < \(minScore)")
            }
        }

        let checksById = Dictionary(
            rubricPayload.checks.map { ($0.id, $0) },
            uniquingKeysWith: { _, last in last }
        )

        for checkId in rubric.requiredCheckIds ?? [] {
            guard let check = checksById[checkId] else {
                errors.append("missing rubric check id: \(checkId)")
                continue
            }
            if !check.pass {
                errors.append("rubric check failed: \(checkId)")
            }
        }

        return errors
    }

    public func gradeFromJSON(
        case evalCase: EvalCase,
        rubricPayload: [String: JSONValue]
    ) -> [String] {
        var errors: [String] = []
        guard let rubric = evalCase.rubric else { return errors }

        let requireOverallPass = rubric.requireOverallPass ?? true
        let overallPass = rubricPayload["overall_pass"]?.boolValue ?? false
        if requireOverallPass && !overallPass {
            errors.append("rubric overall_pass=false")
        }

        if let minScore = rubric.minScore {
            let score = rubricPayload["score"]?.intValue
            if score == nil || score! < minScore {
                errors.append("rubric score below threshold: \(score.map(String.init) ?? "nil") < \(minScore)")
            }
        }

        guard let checksValue = rubricPayload["checks"]?.arrayValue else {
            errors.append("rubric checks is not a list")
            return errors
        }

        var checksById: [String: [String: JSONValue]] = [:]
        for checkValue in checksValue {
            guard let checkObj = checkValue.objectValue,
                  let checkId = checkObj["id"]?.stringValue else { continue }
            checksById[checkId] = checkObj
        }

        for checkId in rubric.requiredCheckIds ?? [] {
            guard let check = checksById[checkId] else {
                errors.append("missing rubric check id: \(checkId)")
                continue
            }
            let pass = check["pass"]?.boolValue ?? false
            if !pass {
                errors.append("rubric check failed: \(checkId)")
            }
        }

        return errors
    }
}
