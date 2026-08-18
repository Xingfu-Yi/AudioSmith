import Foundation

struct ModelFile: Codable, Equatable, Sendable {
    let path: String
    let size: Int64
    let sha256: String
}

struct ModelManifest: Codable, Equatable, Sendable {
    let identifier: String
    let repository: String
    let revision: String
    let modelScopeRevision: String
    let environmentOverrideKey: String
    let files: [ModelFile]

    var totalBytes: Int64 { files.reduce(0) { $0 + $1.size } }

    var probeFile: ModelFile {
        files.first(where: { $0.path == "config.json" }) ?? files[0]
    }

    /// Qwen3-ASR-1.7B converted by mlx-community. ModelScope is accepted only
    /// when its files pass this same immutable content manifest.
    static let qwen3ASR17B8Bit = ModelManifest(
        identifier: "qwen3-asr-1.7b-8bit",
        repository: "mlx-community/Qwen3-ASR-1.7B-8bit",
        revision: "a8379a2e2f9e313c9292cdf1af4055ab56d50d55",
        modelScopeRevision: "master",
        environmentOverrideKey: "AUDIO_SMITH_ASR_MODEL_PATH",
        files: [
            .init(path: "chat_template.json", size: 1_161, sha256: "75a8cfca24f00de72d796fbfed6858fc9614ef3dabd8696684cc3bc03a9c58ff"),
            .init(path: "config.json", size: 7_188, sha256: "1b76b3b6c655fc54595da025f7a96474ad9fa86363303fbdd61a7d8483ccfaf7"),
            .init(path: "generation_config.json", size: 142, sha256: "1da527824d81e07118facff437e03f2e24a23311e3bdeb2368973fe77e5f275c"),
            .init(path: "merges.txt", size: 1_671_853, sha256: "8831e4f1a044471340f7c0a83d7bd71306a5b867e95fd870f74d0c5308a904d5"),
            .init(path: "model.safetensors", size: 2_463_307_541, sha256: "bf304b009cc7eca79283056f787b44c952d24ac22cec787b39732bba3c23c13c"),
            .init(path: "model.safetensors.index.json", size: 78_968, sha256: "0a5d0ec11188602242ff81a9969883d0fdeb98cd5d85cd1413089d897c201af5"),
            .init(path: "preprocessor_config.json", size: 330, sha256: "45e120a4eda2c20c5d7f2ea9354e63536bf35e27aa573fb7cdf78017b378770d"),
            .init(path: "tokenizer_config.json", size: 12_487, sha256: "4942d005604266809309cabc9f4e9cb89ce855d59b14681fdc0e1cc62ea26c4c"),
            .init(path: "vocab.json", size: 2_776_833, sha256: "ca10d7e9fb3ed18575dd1e277a2579c16d108e32f27439684afa0e10b1440910")
        ]
    )
}
