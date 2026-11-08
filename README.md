# nanovllm-voxcpm-image

Lean CUDA image of the [nanovllm-voxcpm](https://github.com/a710128/nanovllm-voxcpm) FastAPI server
(`deployment/app`). Upstream is pinned by commit and patched with `patches/*.patch`. See docs/PLAN.md and
docs/DECISIONS.md.

## Build

```sh
docker compose build            # or: docker build -t nanovllm-voxcpm-image:local .
```

Build args:

| Arg | Default | Purpose |
| --- | --- | --- |
| `UPSTREAM_REF` | `c702631ea33db63932f0c2288cc09a543e68a3ef` | Upstream commit to build. |
| `UPSTREAM_REPO` | `https://github.com/a710128/nanovllm-voxcpm` | Upstream git URL. |
| `CUDA_IMAGE` | `nvidia/cuda:12.8.1-devel-ubuntu22.04` | Builder base. |
| `RUNTIME_IMAGE` | `ubuntu:22.04` | Runtime base (must ship Python 3.10 to match the builder venv). |
| `UV_CONSTRAINTS` | `torch==2.8.*,torchaudio==2.8.*,torchcodec==0.7.*` | Comma-separated resolver pins. |
| `TORCH_CUDA_ARCH_LIST` | `8.6;8.9;9.0;12.0` | Archs if flash-attn must compile from source. |
| `MAX_JOBS` | `4` | Parallel compile jobs for that source build. |

## Run

```sh
cp .env.example .env            # then edit
mkdir -p .docker-cache/huggingface
docker compose up -d
curl -fsS localhost:8090/ready
```

The container listens on port 8000 and serves `/health`, `/ready`, `/info`, `/generate`, `/encode_latents`,
`/loras` and `/metrics` (interactive docs at `/docs`).

Mounts:

- **Models root** (`VOXCPM_MODELS_ROOT`), read-only at the same absolute path, so absolute symlinks inside
  model directories resolve. Local models and LoRA checkpoints must live under it.
- **`/cache`** (`VOXCPM_CACHE_DIR`): `HOME`, plus the Triton and TorchInductor caches.
- **`/cache/huggingface`** (`VOXCPM_HF_HOME`): `HF_HOME`, used when `VOXCPM_MODEL` is a Hub repo id.

The container runs as `VOXCPM_UID:VOXCPM_GID` so it can read owner-only model files. All settings are
documented in `.env.example`; the `NANOVLLM_*` variables they map to are upstream's
(`deployment/app/core/config.py`).

### Hugging Face model

In `.env`:

```sh
VOXCPM_MODEL=openbmb/VoxCPM2
VOXCPM_HF_HOME=/home/me/.cache/huggingface
```

The model is downloaded on first start if missing. Set `VOXCPM_HF_HUB_OFFLINE=1` to use only the cache.

### LoRA

Set `VOXCPM_LORA_ENABLED=true` and size the slots (`VOXCPM_LORA_MAX_LORA_RANK`, `VOXCPM_LORA_TARGET_MODULES`)
to fit your adapters, then:

```sh
curl -fsS -X POST localhost:8090/loras -H 'content-type: application/json' \
  -d '{"name": "my-lora", "path": "/path/to/models/my-lora/checkpoints/latest"}'
curl -fsS -X POST localhost:8090/generate -H 'content-type: application/json' \
  -d '{"target_text": "Hello there.", "lora_name": "my-lora"}' -o out.mp3
```
