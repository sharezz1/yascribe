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

func writeCohereManifestFixture(_ store: ModelStore, crossKV: Bool = false) throws {
    guard store.model == .cohereTranscribe6bit else { return }
    var vocab = Array(repeating: "<unused>", count: 160)
    vocab[3] = "<|endoftext|>"; vocab[62] = "<|en|>"; vocab[148] = "<|pl|>"
    vocab[5] = "<|pnc|>"; vocab[8] = "<|itn|>"; vocab[17] = "mowa"
    var manifest: [String: Any] = [
        "model_id": "test", "sample_rate": 16000, "max_audio_samples": 560000,
        "max_feature_frames": 3501, "max_encoder_frames": 438, "decoder_max_len": 108,
        "default_max_new_tokens": 96, "prompt_ids": [62, 62, 5, 8], "eos_token_id": 3, "id_to_token": vocab,
        "frontend": ["package": "cohere_frontend.mlpackage", "inputs": ["audio", "length"], "outputs": ["features", "length"]],
        "encoder": ["package": "cohere_encoder.mlpackage", "inputs": ["features", "length"], "outputs": ["hidden", "length"]],
        "decoder": ["package": "cohere_decoder_fullseq_masked.mlpackage", "inputs": ["hidden", "ids", "mask", "cross"], "outputs": ["logits"]],
        "decoder_cached": ["package": "cohere_decoder_cached.mlpackage", "inputs": ["hidden", "input_id", "cache_k", "cache_v", "step", "cross_attention_mask"], "outputs": ["logits", "cache_k", "cache_v"], "logits_output": "logits", "cache_k_output": "cache_k", "cache_v_output": "cache_v", "num_layers": 1, "num_heads": 1, "head_dim": 1]
    ]
    if crossKV { manifest["cross_kv_projector"] = ["package": "optional.mlpackage", "inputs": ["hidden"], "outputs": ["k", "v"]] }
    var data = try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
    let size = Int(store.model.manifest.files["coreml_manifest.json"]!)
    data.append(Data(repeating: 32, count: size - data.count))
    try data.write(to: store.modelDirectory.appendingPathComponent("coreml_manifest.json"))
}
