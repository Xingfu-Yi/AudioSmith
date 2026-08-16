---
name: aigc
description: Use canonical spellings, spoken forms, and common ASR confusions to correct mixed Chinese-English AIGC dictation with full-utterance context.
---

# AIGC 专有名词读法

## 使用说明

- 将下表视为“规范写法 → 可能读法或常见误识别”的提示词典。
- 只在原始文本发音相近，并且完整上下文明确支持时改成规范写法；不要因为术语出现在表中就强行插入。
- 保留说话者原本的语言、语序、含义、数字和细节；只修正术语、同音词、大小写、空格和标点，不翻译、不总结、不扩写。
- 中英混说时保留英文术语；字母缩写按规范大小写输出，不擅自展开。

## 专有名词与读法

### Qwen、LLM 与 Transformer

| 规范写法 | 读法或常见误识别 |
|---|---|
| Qwen | 千问；千维 |
| Qwen3 | 千问三；Qwen three |
| Qwen3-ASR | 千问三 A S R；Qwen three A S R |
| Qwen-Image | 千问 Image |
| Qwen-Image-Edit | 千问 Image Edit；千维 Image Edit；千问 Image Editor；千维 Image Editor |
| Qwen-VL | 千问 V L |
| ModelScope | 魔搭；model scope |
| Hugging Face | hugging face |
| AIGC | A I G C |
| LLM | L L M |
| MLLM | M L L M |
| Transformer | transformer |
| token | 偷啃；托肯 |
| tokenizer | tokenizer；托肯奈泽 |
| embedding | embedding |
| attention | attention |
| self-attention | self attention |
| cross-attention | cross attention |
| QKV | Q K V |
| RoPE | R O P E；rope |
| KV cache | K V cache |
| FlashAttention | flash attention |
| RMSNorm | R M S norm；RMS norm |
| LayerNorm | layer norm |
| AdaLN | Ada L N；艾达 L N；At L N |
| AdaLN-Zero | Ada L N zero；adaptive layer norm zero |
| Mixture of Experts | mixture of experts |
| MoE | M O E |
| GQA | G Q A |
| MQA | M Q A |
| SwiGLU | swi glu |
| context window | context window |
| prompt engineering | prompt engineering |
| in-context learning | in context learning |

### Diffusion、Flow Matching 与 DiT

| 规范写法 | 读法或常见误识别 |
|---|---|
| diffusion models | diffusion models |
| latent diffusion | latent diffusion |
| DDPM | D D P M；G D P M |
| U-Net | U net；you net；unit |
| epsilon | 艾普西龙；epsilon |
| epsilon-prediction | 艾普西龙 prediction；epsilon prediction |
| v-prediction | V prediction；velocity prediction |
| x0-prediction | x zero prediction；x0 prediction |
| SNR | S N R |
| log-SNR | log S N R |
| Min-SNR | min S N R |
| noise scheduler | noise scheduler |
| denoiser | denoiser |
| sampler | sampler |
| score matching | score matching |
| score function | score function |
| classifier-free guidance | classifier free guidance |
| CFG | C F G |
| VAE | V A E |
| CLIP | C L I P |
| Diffusion Transformer | diffusion transformer |
| DiT | D I T |
| Flow Matching | flow matching |
| rectified flow | rectified flow |
| probability path | probability path |
| velocity field | velocity field |
| continuity equation | continuity equation |
| ODE | O D E |
| optimal transport | optimal transport |
| ControlNet | control net |
| IP-Adapter | I P adapter |

### 图像、视频与模型生态

| 规范写法 | 读法或常见误识别 |
|---|---|
| Stable Diffusion | stable diffusion |
| SDXL | S D X L |
| FLUX.1 | flux one |
| ComfyUI | Comfy U I |
| Diffusers | diffusers |
| DALL-E | DALL E |
| Midjourney | mid journey |
| Imagen | imagen |
| Sora | sora |
| Veo | V O；veo |
| Wan | 万；Wan |
| HunyuanVideo | 混元 Video；Hunyuan Video |
| Kling | 可灵；Kling |
| Runway | runway |
| text-to-image | text to image |
| image-to-image | image to image |
| text-to-video | text to video |
| image-to-video | image to video |
| video diffusion | video diffusion |
| frame interpolation | frame interpolation |
| temporal consistency | temporal consistency |

### 训练、推理与本地部署

| 规范写法 | 读法或常见误识别 |
|---|---|
| PyTorch | pie torch；Pytorch |
| TorchAO | torch A O |
| JAX | jacks |
| TensorFlow | tensor flow |
| CUDA | C U D A |
| MLX | M L X |
| Core ML | core M L |
| ONNX | on X |
| LoRA | low rank adapter；Lo R A |
| RLHF | R L H F |
| DPO | D P O |
| GRPO | G R P O |
| RAG | R A G |
| BF16 | B F sixteen |
| FP16 | F P sixteen |
| FP8 | F P eight |
| INT8 | int eight |
| quantization | quantization |
| fine-tuning | fine tuning |
| post-training | post training |
| distillation | distillation |
| safetensors | safe tensors |
| checkpoint | checkpoint |
