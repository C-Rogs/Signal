# Local import fixtures (gitignored)

| File | Source |
|------|--------|
| `export.xml` | Apple Health export (unzipped) |
| `HevyExport.csv` | Hevy workout history |

Nothing in this folder is committed except this README.

## Run full pipeline (simulator)

```bash
./scripts/run-full-fixture-pipeline.sh
```

Mirrors the Import tab: Health XML import, then Hevy CSV, MLX embeddings, semantic retrieval checks.

Faster embeds (NL fallback, not MLX):

```bash
SIGNAL_USE_NL_EMBEDDING=1 ./scripts/run-full-fixture-pipeline.sh
```

Health-only import:

```bash
./scripts/import-health-export.sh
```
