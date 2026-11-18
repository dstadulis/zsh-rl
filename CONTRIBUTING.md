# Contributing to `zsh-rl`

Contributions keeping `rl` small, fast, in-process, and faithful to POSIX / kernel VFS (`namei`) pathname resolution are welcome.

## Design Principles

1. **Zero external forks or subshells:** `rl` must run completely in-process inside Zsh (`PATH=""` safe) using `zsh/stat` and `zsh/system`.
2. **Strict VFS `namei` fidelity:** Never collapse `dir/..` lexically before verifying `dir` exists and is a non-symlink directory, and preserve POSIX trailing-slash directory semantics (`ENOTDIR`).
3. **Pure path-stream output:** Keep `stdout` free of decorative arrows or headers so `rl` composes cleanly in Unix pipelines; write all diagnostics to `stderr`.

## Development & Verification

1. Edit [`rl.zsh`](rl.zsh) or [`completions/_rl`](completions/_rl).
2. Add or update coverage in [`tests/`](tests/). Keep all tests hermetic (never touch real `$HOME`, `$ZSH`, or the network).
3. Run the full verification suite:
   ```sh
   make test
   ```

## License

Unless you explicitly state otherwise, any contribution intentionally submitted for inclusion in this repository shall be licensed under the [MIT License](LICENSE).
