# Plan

## Goal
A repository we own that builds a lean CUDA Docker image of
[nanovllm-voxcpm](https://github.com/a710128/nanovllm-voxcpm)'s FastAPI deployment
(`deployment/app`) and publishes it to GitHub Container Registry (GHCR).

The image must support how it is used today:
- serving a custom local model directory (`NANOVLLM_MODEL_PATH=/abs/path`, mounted read-only at the same path)
- serving a Hugging Face repo id (`NANOVLLM_MODEL_PATH=openbmb/VoxCPM2`) through a mounted HF cache (`HF_HOME`)
- runtime LoRA registration via `POST /loras` with adapter dirs under the mounted models root
- running as the host uid/gid, writable `/cache` for Triton / TorchInductor / nanovllm caches
- GPUs: sm_86 (RTX 3090) and sm_120 (RTX PRO 4500 Blackwell); also 8.9, 9.0

## Approach
- Packaging repo, not a fork. Upstream is pinned by commit SHA (`UPSTREAM_REF` build arg),
  cloned in the builder stage; `patches/*.patch` are applied with `git apply`.
- Multi-stage Dockerfile: CUDA devel builder (uv, compiles venv) -> slim runtime stage
  containing only what is needed at runtime (python, the venv, ffmpeg/libsndfile, and a C compiler
  + python headers because Triton/TorchInductor JIT-compile at runtime).
- Torch pinned for CUDA 12.8 (Blackwell): `torch==2.8.*,torchaudio==2.8.*,torchcodec==0.7.*`.

## Carried changes from the local clone (~/repos/nanovllm-voxcpm @ c702631)
- `UV_CONSTRAINTS` build arg (resolver pins) -> becomes part of our Dockerfile.
- Triton `_lora_shrink_small_m_kernel` GEMV fix -> `patches/0001-lora-shrink-gemv-without-tl-dot.patch`.
- `docker-compose.yml` + `.env.example` -> moved here.

## Stack (one PR each, in order)
1. Lean image + compose, verified locally on the 3090 (model dir, HF repo id, LoRA register + generate).
2. GitHub Actions workflow that builds and pushes to `ghcr.io/jspaulsen/nanovllm-voxcpm-image`.
3. Compose defaults to the published GHCR image; verify a pull + run.

## Test fixtures on this machine
- Local model dirs: `~/repos/voxcpm-ft/models/VoxCPM2`, `~/repos/voxcpm-ft/models/VoxCPM2-maya_ref_proj_v2-s256`
- HF cache: `~/.cache/huggingface` contains `models--openbmb--VoxCPM2`
- LoRA: `~/repos/voxcpm-ft/runs/maya_ref_r16/checkpoints/latest/` (rank 16)
- GPU 1 = RTX 3090 (use it for tests). Old images: `nano-vllm-voxcpm-deployment:local` (28.3 GB) is the size baseline.
