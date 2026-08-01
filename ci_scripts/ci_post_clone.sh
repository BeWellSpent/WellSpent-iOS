#!/bin/zsh
set -euo pipefail

# Xcode Cloud clones a fresh checkout with no cached state, so the generated
# proto Swift code (Packages/WellSpentAPI/Sources/WellSpentAPI/Gen/) is
# missing — it's gitignored, same policy as src/gen/ in web and gen/ in the
# backend, and normally only exists locally after running `buf generate`.
# Without this, every `Wellspent_V1_*` type fails to resolve and the whole
# app target fails to compile. This hook runs after clone, before any
# dependency resolution or build step, which is exactly where codegen needs
# to happen. `buf.build/bewellspent/wellspent` and the remote codegen
# plugins are public — confirmed this needs no BSR auth/token.
HOMEBREW_NO_AUTO_UPDATE=1 brew install bufbuild/buf/buf

cd "$CI_PRIMARY_REPOSITORY_PATH"
buf generate
