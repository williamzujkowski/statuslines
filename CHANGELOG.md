# Changelog

## [0.2.1](https://github.com/williamzujkowski/statuslines/compare/v0.2.0...v0.2.1) (2026-08-19)


### Bug Fixes

* **install:** separate runtime and development hints ([#39](https://github.com/williamzujkowski/statuslines/issues/39)) ([837ecd9](https://github.com/williamzujkowski/statuslines/commit/837ecd92d06374da9c885ce877f331582e925a95))


### Documentation

* classify git as a development dependency, not a runtime one ([#40](https://github.com/williamzujkowski/statuslines/issues/40)) ([715258e](https://github.com/williamzujkowski/statuslines/commit/715258e00a41aca86632cb4466c40ada5012027e))

## [0.2.0](https://github.com/williamzujkowski/statuslines/compare/v0.1.0...v0.2.0) (2026-08-18)


### Features

* **core:** add payload parser, color and theme primitives ([9519e59](https://github.com/williamzujkowski/statuslines/commit/9519e59d2b8a803ba18dcc0611bc26168bf6df9f))
* **render:** add segment dispatch and width fitting ([f62af58](https://github.com/williamzujkowski/statuslines/commit/f62af58c57e3e0a61e9bd339244ec07c9ba88bd3))
* **render:** search user directories for segments ([#37](https://github.com/williamzujkowski/statuslines/issues/37)) ([05fbe51](https://github.com/williamzujkowski/statuslines/commit/05fbe51d9630a65d0d5dc7982b827e1f395dd55e))
* **segments:** add the seventeen shipped segments ([6a64ac3](https://github.com/williamzujkowski/statuslines/commit/6a64ac3b0a0c943d544688a5100f7c1ed27e50f7))
* **themes:** add default, minimal, plain, dashboard and powerline themes ([53eac9b](https://github.com/williamzujkowski/statuslines/commit/53eac9bba5902911c0754a5fe2eacf9383596c6f))


### Bug Fixes

* **ci:** drop the placeholder bootstrap-sha from release-please config ([2be5f52](https://github.com/williamzujkowski/statuslines/commit/2be5f52e7b9578f7371d00386c48147e0d9fb9ca))
* **render:** show a marker when a segment is broken instead of silence ([#36](https://github.com/williamzujkowski/statuslines/issues/36)) ([7afdf94](https://github.com/williamzujkowski/statuslines/commit/7afdf94fc545e239d7c3f547c469c7cd8d6fa4ea))
* **render:** treat return 1 as nothing to show even with output ([7afdf94](https://github.com/williamzujkowski/statuslines/commit/7afdf94fc545e239d7c3f547c469c7cd8d6fa4ea))
* **themes:** strip control characters from theme values ([7afdf94](https://github.com/williamzujkowski/statuslines/commit/7afdf94fc545e239d7c3f547c469c7cd8d6fa4ea))


### Documentation

* add readme, contributing guide and reference documentation ([f3e414a](https://github.com/williamzujkowski/statuslines/commit/f3e414a950d67f4d8e821a628db6124bb7ea922f))
