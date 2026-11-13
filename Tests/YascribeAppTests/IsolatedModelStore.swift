import Foundation
@testable import YascribeLocalASR

// Każdy test ma osobny magazyn, więc i osobny inode blokady (`<magazyn>/.locks`, jak w produkcji).
func isolatedModelStore(model: LocalASRModel = .parakeetV3, directory: URL? = nil,
                        download: ModelStore.Download? = nil,
                        modelsExist: @escaping ModelStore.ModelsExist = ModelStore.fluidAudioModelsExist,
                        fileDownload: @escaping ModelStore.FileDownload = ModelStore.networkFileDownload,
                        diskSpace: @escaping ModelStore.DiskSpace = ModelDiskBudget.inspect) -> ModelStore {
    ModelStore(model: model, directory: directory, download: download, modelsExist: modelsExist,
               fileDownload: fileDownload, diskSpace: diskSpace)
}
