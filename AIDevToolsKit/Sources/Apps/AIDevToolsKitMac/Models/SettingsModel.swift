import DataPathsService
import Foundation

@MainActor @Observable
final class SettingsModel {

    var dataPath: URL {
        didSet {
            ResolveDataPathUseCase().save(dataPath)
        }
    }

    init() {
        let useCase = ResolveDataPathUseCase()
        let resolved = useCase.resolve()
        self.dataPath = resolved.path
        useCase.save(resolved.path)
    }

    func updateDataPath(_ newPath: URL) {
        dataPath = newPath
    }
}
