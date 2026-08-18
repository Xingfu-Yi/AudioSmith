#!/bin/zsh
set -euo pipefail

repo_dir=${0:A:h:h}
output_dir=${1:-"$repo_dir/artifacts/Qwen3-ASR-1.7B-8bit"}
venv_dir=${AUDIO_SMITH_QUANT_VENV:-"$repo_dir/.venv-quantize"}
python_bin=${PYTHON_BIN:-python3}
source_model='Qwen/Qwen3-ASR-1.7B'
source_revision='7278e1e70fe206f11671096ffdd38061171dd6e5'

if [[ $(uname -m) != arm64 ]]; then
  print -u2 "MLX quantization requires an Apple Silicon Mac."
  exit 1
fi

if [[ -e "$output_dir" ]]; then
  print -u2 "Refusing to overwrite existing output: $output_dir"
  exit 1
fi

"$python_bin" -m venv "$venv_dir"
"$venv_dir/bin/python" -m pip install --upgrade pip
"$venv_dir/bin/python" -m pip install 'mlx-audio==0.3.1'

"$venv_dir/bin/python" -m mlx_audio.convert \
  --hf-path "$source_model" \
  --revision "$source_revision" \
  --mlx-path "$output_dir" \
  --model-domain stt \
  --quantize \
  --q-mode affine \
  --q-bits 8 \
  --q-group-size 64

find "$output_dir" -type f -maxdepth 1 -print0 | sort -z | xargs -0 shasum -a 256

