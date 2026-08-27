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

# The REST half of the API is generated from an OpenAPI contract that does not
# go through BSR — there is no OpenAPI equivalent — so it is fetched over HTTPS
# from the public WellSpent-proto repo. Only the *contract* is fetched here; the
# Swift itself is produced by the swift-openapi-generator SPM build plugin
# during the build, so there is nothing else to run.
make generate-rest

# Trust the swift-openapi-generator build plugin.
#
# An SPM *build* plugin runs arbitrary code during the build, so Xcode refuses
# to run one it has never seen approved — in the GUI that's the "Trust & Enable"
# prompt, and there is nobody to click it here. Build 44 failed exactly this
# way: "Plugin OpenAPIGenerator from package swift-openapi-generator must be
# enabled before it can be used". The approval is stored per-machine, and every
# Xcode Cloud run is a fresh ephemeral machine, so it can only ever be set here.
#
# From the CLI the equivalent is xcodebuild's -skipPackagePluginValidation, but
# Xcode Cloud owns the xcodebuild invocation and takes no extra flags — this
# default is the same switch reachable from a script. The key is spelled
# "Validatation": that double "tat" is Apple's own typo, verified against
# IDEFoundation in Xcode 26, not a mistake here. Do not "fix" it.
#
# There is no macro equivalent to set alongside it (IDESkipMacroFingerprint-
# Validation) because this project uses no Swift macros. Add it if that changes.
defaults write com.apple.dt.Xcode IDESkipPackagePluginFingerprintValidatation -bool YES
