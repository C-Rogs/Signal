# M3 SPM setup

**Status:** Packages are wired in `Signal.xcodeproj` (Signal target). Agent may adjust SPM in `project.pbxproj` per `.cursor/rules/xcode-project-setup.mdc`. Open the project in Xcode once if package resolution is stale.

To add manually (only if resetting the project), use **File → Add Package Dependencies**:

| URL | Version | Products for Signal target |
|-----|---------|----------------------------|
| `https://github.com/ml-explore/mlx-swift` | Up to next minor from **0.31.3** | MLX |
| `https://github.com/ml-explore/mlx-swift-lm` | **Revision** `ee5320ddcf8cdc2765165e0350b1f9a76362a24a` (not 3.31.3 tag: `EmbeddingGemma.sanitize` crashes on device) | MLXEmbedders, MLXLMCommon |
| `https://github.com/DePasqualeOrg/swift-hf-api-mlx` | Up to next minor from **0.2.0** | MLXEmbeddersHFAPI |
| `https://github.com/DePasqualeOrg/swift-tokenizers-mlx` | Up to next minor from **0.3.0** | MLXEmbeddersTokenizers |
| `https://github.com/DePasqualeOrg/swift-tokenizers` | **Exact 0.5.0** (pins transitive dep; 0.6+ breaks mlx adapters) | (resolution only, no product link) |

Accept the Hugging Face license for `mlx-community/embeddinggemma-300m-4bit` before the first on-device embed.

Run `EmbeddingRetrievalTests` on a physical iPhone 16 Pro (simulator skips MLX integration tests).

**If build fails with missing Metal Toolchain:**

```bash
xcodebuild -downloadComponent MetalToolchain
```

**If SPM resolve fails on tokenizers artifact cache:** delete the corrupt file under `~/Library/Caches/org.swift.swiftpm/artifacts/` matching `TokenizersRust`, then **File → Packages → Reset Package Caches** in Xcode.

**If package resolve says "Package.swift was modified during the build":** run `xcodebuild -resolvePackageDependencies` again (transient race during checkout).

**When mlx-swift-lm ships a release after 3.31.3 with the `Model.update(modules:)` sanitize fix:** switch from revision pin back to up-to-next-minor from that version.
