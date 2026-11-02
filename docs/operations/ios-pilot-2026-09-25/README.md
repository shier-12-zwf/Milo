# MILO iOS pilot evidence

The [complete cloud run](https://github.com/horton2048/milo/actions/runs/36159042524) passed on commit `e650fef889ae2569a563886d25e489afa6ff2a1b`. These files are historical evidence copied after the successful gate, not a replacement gate or a resumable local state.

- `verification-summary.json`: tested source, environment, counts, image labels and scope.
- `runner/`: original final state, report and check logs; build/UI were not rerun after the independent receipt arrived.
- `transport-receipt.json`: independently supplied run/head/source/image-bound review.
- `visual-review.json`: that review mapped to the actual cloud paths by the receipt receiver.
- `screenshots/`: six original, unmodified screenshots and their manifest. `home-standard-text-Dark.png` is an identical-byte convenience copy.

The `.xcresult` bundles are too large to commit. The original workflow artifacts have 14-day retention; a complete local archive is kept in `apps/ios/evidence/cloud-36159042524` (ignored by Git). Earlier failed evidence is also kept under `apps/ios/evidence/cloud-<run-id>`. Absolute paths in the copied runner state and receipts intentionally remain the original cloud paths; do not relabel this state as a local pass.

See [the pilot assessment](../specdrive-ios-pilot-2026-09-25.md) for the failure history and remaining scope.
