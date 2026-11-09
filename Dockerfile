# Lean image of nanovllm-voxcpm's FastAPI deployment (upstream deployment/app).
# Builder: CUDA devel + uv builds a non-editable venv from uv.lock. Runtime: plain Ubuntu (torch wheels bundle the
# CUDA libs). Regenerate uv.lock after changing UPSTREAM_REF, UV_CONSTRAINTS or patches/:
#   docker build --target lock --output . .

ARG CUDA_IMAGE=nvidia/cuda:12.8.1-devel-ubuntu22.04
ARG RUNTIME_IMAGE=ubuntu:22.04

FROM ghcr.io/astral-sh/uv:0.11.6 AS uv

FROM ${CUDA_IMAGE} AS source

ARG UPSTREAM_REPO=https://github.com/a710128/nanovllm-voxcpm
ARG UPSTREAM_REF=c702631ea33db63932f0c2288cc09a543e68a3ef
# Resolver pins (upstream commits no uv.lock). torch 2.8 is built for CUDA 12.8 (sm_86 .. sm_120).
ARG UV_CONSTRAINTS="torch==2.8.*,torchaudio==2.8.*,torchcodec==0.7.*"
# Only used if flash-attn has no prebuilt wheel for the resolved torch/python and compiles from source.
ARG TORCH_CUDA_ARCH_LIST="8.6;8.9;9.0;12.0"
ARG MAX_JOBS=4

ENV DEBIAN_FRONTEND=noninteractive \
    TORCH_CUDA_ARCH_LIST=${TORCH_CUDA_ARCH_LIST} \
    MAX_JOBS=${MAX_JOBS} \
    UV_NO_PROGRESS=1 \
    UV_PYTHON=/usr/bin/python3.10 \
    UV_PYTHON_DOWNLOADS=never \
    UV_PROJECT_ENVIRONMENT=/opt/venv \
    UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates \
      git \
      build-essential \
      ninja-build \
      python3 \
      python3-dev \
 && rm -rf /var/lib/apt/lists/*

COPY --from=uv /uv /usr/local/bin/uv

WORKDIR /src
COPY patches/ /patches/
RUN git clone "$UPSTREAM_REPO" . \
 && git checkout --detach "$UPSTREAM_REF" \
 && for p in /patches/*.patch; do git apply --verbose "$p"; done

RUN if [ -n "$UV_CONSTRAINTS" ]; then \
      deps=$(printf '%s' "$UV_CONSTRAINTS" | sed 's/[^,][^,]*/"&"/g'); \
      printf '\n[tool.uv]\nconstraint-dependencies = [%s]\n' "$deps" >> pyproject.toml; \
    fi


# Resolves from scratch (no existing uv.lock), so it also picks up newer versions allowed by the constraints.
FROM source AS locker
RUN --mount=type=cache,target=/root/.cache/uv \
    uv lock

FROM scratch AS lock
COPY --from=locker /src/uv.lock /


FROM source AS builder

# --locked fails the build if uv.lock no longer matches the patched pyproject (see the header comment).
COPY uv.lock /src/uv.lock
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --locked --all-packages --no-dev --no-editable


FROM ${RUNTIME_IMAGE}

# gcc + Python headers: Triton and TorchInductor JIT-compile host code at runtime.
# libav*: FFmpeg shared libs for torchaudio / torchcodec audio decoding.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates \
      python3 \
      python3-dev \
      gcc \
      libc6-dev \
      libavcodec58 \
      libavdevice58 \
      libavfilter7 \
      libavformat58 \
      libavutil56 \
      libswresample3 \
      libswscale5 \
 && rm -rf /var/lib/apt/lists/*

COPY --from=builder /opt/venv /opt/venv

# The container may run as any uid (compose uses the host uid), so HOME and all caches live under a
# world-writable /cache. USER is set because that uid usually has no passwd entry (getpass.getuser()).
RUN mkdir -p /cache && chmod 1777 /cache
ENV PATH=/opt/venv/bin:$PATH \
    HOME=/cache \
    USER=voxcpm \
    TRITON_CACHE_DIR=/cache/triton \
    TORCHINDUCTOR_CACHE_DIR=/cache/torchinductor \
    HF_HOME=/cache/huggingface \
    NVIDIA_VISIBLE_DEVICES=all \
    NVIDIA_DRIVER_CAPABILITIES=compute,utility

EXPOSE 8000

# Non-root by default; compose overrides this with the host uid.
USER 65534:65534

# /health (liveness) and /ready (model loaded) are available for probes.
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
