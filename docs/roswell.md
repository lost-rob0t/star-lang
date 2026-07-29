# Roswell installation and offline cache strategy

[Roswell][roswell] installs Common Lisp implementations and loads ASDF systems
reproducibly. It is the supported local entry point for `star-lang`.

[roswell]: https://roswell.github.io

## Install SBCL via Roswell

```bash
ros install sbcl-bin
ros use sbcl-bin
```

## Load a system

```bash
ros run --eval "(ql:quickload :star-actor-protocol)" --quit
```

## Offline cache strategy

1. Pin dependencies in a lockfile generated from a clean Quicklisp dist.
2. Mirror the dist tarballs into a local `dist/` directory.
3. Configure ASDF source-registry to prefer the local cache:

   ```bash
   export CL_SOURCE_REGISTRY="$(pwd)/dist//:$(pwd)/systems//"
   ```

4. Reproducible offline load must succeed without network access. This is a
   release gate enforced by CI.
