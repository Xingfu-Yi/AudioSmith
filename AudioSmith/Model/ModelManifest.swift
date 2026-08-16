import Foundation

struct ModelFile: Codable, Equatable, Sendable {
    let path: String
    let size: Int64
    let sha256: String
}

enum ModelPurpose: String, Codable, Sendable {
    case speechRecognition
    case professionalRefinement
}

struct ModelManifest: Codable, Equatable, Sendable {
    let identifier: String
    let purpose: ModelPurpose
    let repository: String
    let revision: String
    let modelScopeRevision: String
    let environmentOverrideKey: String
    let files: [ModelFile]

    var totalBytes: Int64 { files.reduce(0) { $0 + $1.size } }

    var probeFile: ModelFile {
        files.first(where: { $0.path == "config.json" }) ?? files[0]
    }

    /// Qwen3-ASR-0.6B converted by mlx-community. ModelScope is accepted only
    /// when its files pass this same immutable content manifest.
    static let qwen3ASR06B8Bit = ModelManifest(
        identifier: "qwen3-asr-0.6b-8bit",
        purpose: .speechRecognition,
        repository: "mlx-community/Qwen3-ASR-0.6B-8bit",
        revision: "89e96d92ba34aca20b3e29fb10cc284097d1219f",
        modelScopeRevision: "master",
        // Keep ASR and text-refiner overrides purpose-specific so a path for
        // one model can never be validated against the other model's manifest.
        environmentOverrideKey: "AUDIO_SMITH_ASR_MODEL_PATH",
        files: [
            .init(path: "chat_template.json", size: 1_161, sha256: "75a8cfca24f00de72d796fbfed6858fc9614ef3dabd8696684cc3bc03a9c58ff"),
            .init(path: "config.json", size: 7_187, sha256: "5d104a945fed08728ab010f12bf3ce5ab4d0794bba276d81bff5bd83ae9d2be0"),
            .init(path: "generation_config.json", size: 142, sha256: "1da527824d81e07118facff437e03f2e24a23311e3bdeb2368973fe77e5f275c"),
            .init(path: "merges.txt", size: 1_671_853, sha256: "8831e4f1a044471340f7c0a83d7bd71306a5b867e95fd870f74d0c5308a904d5"),
            .init(path: "model.safetensors", size: 1_006_229_426, sha256: "b5bfe4abc1b4c6e58b633096682ec2b6297298add1527119936107d211adf0e8"),
            .init(path: "model.safetensors.index.json", size: 71_815, sha256: "caa32ece76c395ba241533eb4aceb0efbc72488ef3d8d2fd3c677ce068dad57d"),
            .init(path: "preprocessor_config.json", size: 330, sha256: "45e120a4eda2c20c5d7f2ea9354e63536bf35e27aa573fb7cdf78017b378770d"),
            .init(path: "tokenizer_config.json", size: 12_487, sha256: "4942d005604266809309cabc9f4e9cb89ce855d59b14681fdc0e1cc62ea26c4c"),
            .init(path: "vocab.json", size: 2_776_833, sha256: "ca10d7e9fb3ed18575dd1e277a2579c16d108e32f27439684afa0e10b1440910")
        ]
    )

    /// Official Qwen MLX 4-bit text model used only after Fn is released.
    static let qwen3Refiner17B4Bit = ModelManifest(
        identifier: "qwen3-1.7b-4bit-refiner",
        purpose: .professionalRefinement,
        repository: "Qwen/Qwen3-1.7B-MLX-4bit",
        revision: "21457c6f51ed54a7c16e988c0844db973815c137",
        modelScopeRevision: "master",
        environmentOverrideKey: "AUDIO_SMITH_REFINER_MODEL_PATH",
        files: [
            .init(path: "config.json", size: 988, sha256: "4e95bb0b083bf4847aacc08e67c5d59410f45fff6f43889d6ff400511c243fa5"),
            .init(path: "merges.txt", size: 1_671_853, sha256: "8831e4f1a044471340f7c0a83d7bd71306a5b867e95fd870f74d0c5308a904d5"),
            .init(path: "model.safetensors", size: 914_316_100, sha256: "42e688d626b3e144bf721af7517a82f3ea7e97bb5764fef1c89942bf9165072a"),
            .init(path: "model.safetensors.index.json", size: 49_731, sha256: "dae65ea418d2d8ea25e72d0b1f5b1d0a12633c1f46ca2c5ca97903bbcc3a6ce2"),
            .init(path: "tokenizer.json", size: 11_422_654, sha256: "aeb13307a71acd8fe81861d94ad54ab689df773318809eed3cbe794b4492dae4"),
            .init(path: "tokenizer_config.json", size: 8_311, sha256: "5fdfe1416aaa323832d52c5bd8624a6e9bba3e9acc6ca8104f017abc775e2368"),
            .init(path: "vocab.json", size: 2_776_833, sha256: "ca10d7e9fb3ed18575dd1e277a2579c16d108e32f27439684afa0e10b1440910")
        ]
    )
}
