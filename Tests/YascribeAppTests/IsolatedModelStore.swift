import Foundation
@testable import YascribeLocalASR

// Każdy test ma osobny magazyn i inode blokady; produkcyjna ścieżka pozostaje stała.
func isolatedModelStore(model: LocalASRModel = .parakeetV3, directory: URL? = nil,
                        download: ModelStore.Download? = nil,
                        modelsExist: @escaping ModelStore.ModelsExist = ModelStore.fluidAudioModelsExist,
                        fileDownload: @escaping ModelStore.FileDownload = ModelStore.networkFileDownload,
                        diskSpace: @escaping ModelStore.DiskSpace = ModelDiskBudget.inspect) -> ModelStore {
    var store = ModelStore(model: model, directory: directory, download: download, modelsExist: modelsExist,
                           fileDownload: fileDownload, diskSpace: diskSpace)
    store.lockRootForTesting = directory
    return store
}
