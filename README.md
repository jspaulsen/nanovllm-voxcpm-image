# nanovllm-voxcpm-image

Lean CUDA image of the [nanovllm-voxcpm](https://github.com/a710128/nanovllm-voxcpm) FastAPI server
(`deployment/app`). Upstream is pinned by commit and patched with `patches/*.patch`. See docs/PLAN.md and
docs/DECISIONS.md.

## Build

Only needed to run something other than the published image (see Run).

```sh
VOXCPM_IMAGE=nanovllm-voxcpm-image:local docker compose build   # or: docker build -t nanovllm-voxcpm-image:local .
```

Put `VOXCPM_IMAGE=nanovllm-voxcpm-image:local` in `.env` to run that build; `docker compose up -d --build`
rebuilds and starts it. Leaving `VOXCPM_IMAGE` at the GHCR name would tag the local build with it.

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

Python dependencies are pinned by `uv.lock`, and the build fails if the lock no longer matches. After changing
`UPSTREAM_REF`, `UV_CONSTRAINTS` or `patches/`, or to pick up newer dependency releases, regenerate and commit it
(pass the same `--build-arg`s as the build):

```sh
docker build --target lock --output . .
```

## Published image

`.github/workflows/publish.yml` builds the Dockerfile and pushes `ghcr.io/jspaulsen/nanovllm-voxcpm-image` on every
push to `main` that changes more than Markdown or `docs/` (and on manual dispatch). Tags:

- `latest`: the newest `main` build.
- `upstream-<short UPSTREAM_REF>`: the newest `main` build of that upstream commit (read from the Dockerfile's
  `UPSTREAM_REF` default).
- `sha-<short commit>`: this repo's commit (also pushed by manual runs on other branches).

## Run

Compose runs `VOXCPM_IMAGE`, which defaults to `ghcr.io/jspaulsen/nanovllm-voxcpm-image:latest`. The package is
private, so log in to GHCR once:

```sh
gh auth refresh -s read:packages   # once; the default gh token lacks it
gh auth token | docker login ghcr.io -u jspaulsen --password-stdin
```

Then:

```sh
cp .env.example .env            # then edit
mkdir -p .docker-cache/huggingface
docker compose pull
docker compose up -d --no-build   # fail instead of building locally if the pull did not work
curl -fsS localhost:8090/ready
```

To pin, set `VOXCPM_IMAGE` in `.env` to a `sha-<short commit>` tag (fixed), e.g.
`ghcr.io/jspaulsen/nanovllm-voxcpm-image:sha-d41c623`, or an `upstream-<short UPSTREAM_REF>` tag such as
`...:upstream-c702631` (moves to the newest `main` build of that upstream commit), then
`docker compose pull && docker compose up -d --no-build`. `latest` only moves when you `docker compose pull` again.

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
