# Decisions

1. **Packaging repo, not a fork.** Upstream pinned by SHA and patched with `patches/*.patch`; bumping upstream is a one-line change and our diff stays visible. Easier to undo than a fork (can always fork later).
2. **Private GitHub repo** (`jspaulsen/nanovllm-voxcpm-image`); the GHCR package inherits private visibility. Pulling needs `docker login ghcr.io`. Can be flipped public later (decision issue).
3. **Image name** `ghcr.io/jspaulsen/nanovllm-voxcpm-image`, tags: `latest` (main), `sha-<our commit>`, `upstream-<short upstream sha>`.
4. **CUDA 12.8 / torch 2.8** so one image covers sm_86 and sm_120.
