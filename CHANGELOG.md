# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/) and we follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

# v3.0.0

## Changed

- `KupmiosConfig` and `KupmiosEnv` types. Ogmios cannot handle a high number of
parallel HTTP requests, so we now limit concurrency using a semaphore managed
within `KupmiosEnv`. The semaphore can be initialized with
`initOgmiosRequestSemaphore`. Additionally, users can configure
`requestSemaphoreCooldown` in `KupmiosConfig` to further throttle requests that
exceed the semaphore limit. Note that this solution is intended as a temporary
workaround, so contributions are more than welcome.

# v2.1.0

## Changed

- Reuse Ogmios types, decoders, and helper functions from [purescript-cardano-provider](https://github.com/mlabs-haskell/purescript-cardano-provider)
  ([#3](https://github.com/mlabs-haskell/purescript-cardano-kupmios-provider/pull/3))

## Removed

- `ClusterSetup` type ([#3](https://github.com/mlabs-haskell/purescript-cardano-kupmios-provider/pull/3))

# v2.0.0

## Changed

- Replaced cardano-serialization-lib (CSL) with [cardano-data-lite (CDL)](https://github.com/mlabs-haskell/purescript-cardano-data-lite)
  ([#2](https://github.com/mlabs-haskell/purescript-cardano-kupmios-provider/pull/2))
