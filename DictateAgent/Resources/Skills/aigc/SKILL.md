---
name: aigc
description: Improve mixed Chinese and English dictation about LLMs, diffusion models, image and video generation, and generative-AI training and inference.
---

# AIGC 词汇与转写

## Dictation context

The speaker discusses generative AI in mixed Chinese and English, including large language models, diffusion models, image generation, video generation, training, inference, and Apple-Silicon deployment.

## Transcription guidance

- Transcribe what was spoken; do not translate Chinese into English or English into Chinese.
- Use the complete utterance to disambiguate technical terms instead of relying on one short acoustic fragment.
- Preserve conventional capitalization, punctuation, hyphens, version numbers, model names, framework names, acronyms, and mathematical symbols.
- Preserve an English technical term when it is spoken inside a Chinese sentence.
- Prefer a vocabulary item only when it is acoustically and contextually plausible. Never insert a term merely because it appears in this Skill.
- When an acronym is spoken letter by letter, write its canonical acronym. Do not expand an acronym unless the speaker expands it.
- Keep product names distinct from similar-sounding mathematical terms. For example, use `epsilon` in a diffusion/noise-prediction context, but keep `App Store` when the speaker is discussing Apple software distribution.
- When the utterance explicitly compares two concepts using “相比于”, “区别”, `versus`, or `vs.`, do not collapse both sides into the same technical term when the audio and domain context support a known contrast.
- Add conservative punctuation at clear phrase or sentence boundaries without rewriting the speaker's meaning or style.

## Mandarin pronunciation robustness

- Use the surrounding technical sentence and selected vocabulary to tolerate common Mandarin accent confusions such as `in/ing`, `en/eng`, `l/n`, `f/h`, and retroflex/non-retroflex initials.
- Never apply a blanket phonetic substitution to ordinary Chinese. Correct a pronunciation ambiguity only when a domain term and the full sentence strongly support it.
- Treat “呃” and “嗯” as hesitation sounds rather than parts of an English term.
- If the technical wording remains uncertain, preserve the spoken wording instead of inventing a claim.

## Domain map

### LLM and Transformer

- Relate attention, QKV, RoPE, KV cache, MLP, MoE, residual connections, and normalization. Common contrasts include RMSNorm versus LayerNorm and Pre-Norm versus Post-Norm.

### Diffusion

- Keep epsilon-prediction, v-prediction, and x0-prediction distinct. Relate SNR and log-SNR to prediction targets, weighting, noise schedules, denoisers, samplers, and score functions.

### Flow Matching

- Relate Flow Matching to probability paths, velocity or vector fields, the continuity equation, ODEs, rectified flow, and optimal transport.

### DiT

- Treat DiT as a Transformer denoiser neighborhood containing patch and timestep embeddings, conditioning, cross/joint attention, MMDiT, AdaLN, and AdaLN-Zero.

## Disambiguation examples

- “扩散模型里面的艾普西龙预测” → “扩散模型里面的 epsilon 预测”
- “v prediction 和 epsilon prediction 的区别” → “v-prediction 和 epsilon-prediction 的区别”
- “R M S norm 比 layer norm” → “RMSNorm 比 LayerNorm”
- “adaptive layer norm，也就是 At L N” → “Adaptive LayerNorm，也就是 AdaLN”
- “我用 diffusion models 和 Flow Matching 做视频生成” → preserve `diffusion models` and `Flow Matching`
- “这个应用准备上架 App Store” → keep `App Store`; do not replace it with `epsilon`

## Vocabulary

### LLM and Transformer

- `AIGC`: `A I G C`
- `LLM`: `L L M`
- `MLLM`: `M L L M`
- `large language model`
- `multimodal large language model`
- `foundation model`
- `Transformer`
- `RMSNorm`: `R M S norm`, `RMS norm`
- `LayerNorm`: `layer norm`
- `Layer Normalization`: `layer normalization`
- `LN`: `L N`
- `Adaptive LayerNorm`: `adaptive layer norm`
- `AdaLN`: `Ada L N`, `艾达 L N`, `At L N`
- `AdaLN-Zero`: `Ada L N zero`, `adaptive layer norm zero`
- `AdaLN-Single`: `Ada L N single`, `adaptive layer norm single`
- `Pre-Norm`: `pre norm`
- `Post-Norm`: `post norm`
- `GroupNorm`: `group norm`
- `BatchNorm`: `batch norm`
- `QK-Norm`: `Q K norm`, `QK norm`
- `residual connection`
- `QKV`: `Q K V`
- `RoPE`: `R O P E`
- `rotary position embedding`
- `FlashAttention`: `flash attention`
- `GQA`: `G Q A`
- `MQA`: `M Q A`
- `SwiGLU`: `swi glu`
- `self-attention`: `self attention`
- `cross-attention`: `cross attention`
- `Mixture of Experts`: `mixture of expert`
- `MoE`: `M O E`
- `tokenizer`
- `embedding`
- `context window`
- `KV cache`: `K V cache`
- `prompt engineering`
- `chain-of-thought`
- `in-context learning`
- `instruction tuning`
- `pre-training`: `pretraining`
- `post-training`: `post training`
- `fine-tuning`: `fine tuning`
- `RLHF`: `R L H F`
- `DPO`: `D P O`
- `GRPO`: `G R P O`
- `RAG`: `R A G`
- `LoRA`: `low rank adapter`
- `quantization`
- `distillation`
- `BF16`: `B F sixteen`
- `FP16`: `F P sixteen`
- `FP8`: `F P eight`
- `INT8`: `int eight`

### Diffusion and score-based models

- `Diffusion Models`: `diffusion models`
- `latent diffusion`
- `denoising diffusion probabilistic model`
- `DDPM`: `D D P M`
- `U-Net`: `U net`
- `VAE`: `V A E`
- `CLIP`: `C L I P`
- `text encoder`
- `classifier-free guidance`: `classifier free guidance`
- `CFG`: `C F G`
- `epsilon`: `艾普西龙`
- `epsilon-prediction`: `epsilon prediction`, `艾普西龙 prediction`, `艾普西龙预测`
- `v-prediction`: `v prediction`, `V prediction`, `velocity prediction`
- `x0-prediction`: `x zero prediction`, `x-zero prediction`, `x0 prediction`
- `SNR`: `S N R`
- `log-SNR`: `log S N R`
- `Min-SNR`: `min S N R`
- `SNR weighting`: `S N R weighting`
- `zero terminal SNR`: `zero terminal S N R`
- `P2 weighting`: `P two weighting`
- `noise scheduler`
- `score matching`
- `score function`
- `denoiser`
- `sigma schedule`
- `score distillation sampling`
- `SDS`: `S D S`

### Flow Matching and continuous dynamics

- `Flow Matching`: `flow matching`
- `conditional flow matching`
- `probability path`
- `velocity field`
- `vector field`
- `continuity equation`
- `ODE`: `O D E`
- `neural ODE`: `neural O D E`
- `optimal transport`
- `rectified flow`

### DiT, conditioning, and generative media

- `Diffusion Transformer`
- `DiT`: `D I T`
- `patch embedding`
- `timestep embedding`
- `MMDiT`: `M M DiT`
- `joint attention`
- `ControlNet`: `control net`
- `IP-Adapter`: `I P adapter`
- `DreamBooth`: `dream booth`
- `Stable Diffusion`
- `SDXL`: `S D X L`
- `FLUX.1`: `flux one`
- `DALL-E`: `DALL E`
- `Midjourney`: `mid journey`
- `Imagen`
- `Sora`
- `Veo`
- `Wan`
- `HunyuanVideo`: `Hunyuan Video`
- `Kling`
- `Runway`
- `ComfyUI`: `Comfy U I`
- `Hugging Face Diffusers`: `Hugging Face diffusers`
- `safetensors`: `safe tensors`
- `checkpoint`
- `sampler`
- `negative prompt`
- `seed`
- `text-to-image`: `text to image`
- `image-to-image`: `image to image`
- `text-to-video`: `text to video`
- `image-to-video`: `image to video`
- `video diffusion`
- `keyframe`
- `frame interpolation`
- `temporal consistency`
- `lip-sync`: `lip sync`

### Training, inference, and runtimes

- `PyTorch`: `pie torch`
- `JAX`: `jacks`
- `TensorFlow`: `tensor flow`
- `CUDA`: `C U D A`
- `MLX`: `M L X`
- `Core ML`: `core M L`
- `ONNX`: `on X`
- `Hugging Face`: `huggingface`
