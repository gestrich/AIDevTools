import DataPathsService
import Foundation

@MainActor @Observable
final class SettingsModel {

    private(set) var dataPath: URL
    private let resolveDataPath: ResolveDataPathUseCase

    init(resolveDataPath: ResolveDataPathUseCase = ResolveDataPathUseCase()) {
        self.resolveDataPath = resolveDataPath
        let resolved = resolveDataPath.resolve()
        self.dataPath = resolved.path
        resolveDataPath.save(resolved.path)
    }

    func updateDataPath(_ newPath: URL) {
        dataPath = newPath
        resolveDataPath.save(newPath)
    }
}
