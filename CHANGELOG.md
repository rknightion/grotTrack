# Changelog

## [0.9.0](https://github.com/rknightion/grotTrack/compare/v0.8.0...v0.9.0) (2026-04-02)


### Features

* **ui:** increase screenshot browser default size to 1800×1100 ([a31b825](https://github.com/rknightion/grotTrack/commit/a31b8255b6f1fca10207e327b66004bb50bbc423))
* **ui:** make timeline rail full-height via GeometryReader, widen to 280pt ([ba68af4](https://github.com/rknightion/grotTrack/commit/ba68af41b92d62aa7c7cdff9471205070f9bcbc0))
* **ui:** redesign grid tab with Photos-style edge-to-edge thumbnails ([4ebe4cf](https://github.com/rknightion/grotTrack/commit/4ebe4cf06ae584b4fce3d288cb381310623b7816))
* **ui:** scrollable context panel and Up/Down/Space keyboard navigation ([ff46509](https://github.com/rknightion/grotTrack/commit/ff46509af22a18053db0ed0aa549729066cd8a37))


### Documentation

* add screenshot browser v2 enhancement design spec ([265876d](https://github.com/rknightion/grotTrack/commit/265876d67ffbe60ffee1506cd03c16c59f2f7d9f))
* add screenshot browser v2 implementation plan ([261c0c0](https://github.com/rknightion/grotTrack/commit/261c0c06da7fb73d8acca133ff2aa07072b805e9))


### Refactoring

* **ui:** extract shared entityStyle, fix lint warnings, cache DateFormatter ([c58eead](https://github.com/rknightion/grotTrack/commit/c58eeadcea32defefd6863ddf7957c5dafeb87d3))

## [0.8.0](https://github.com/rknightion/grotTrack/compare/v0.7.0...v0.8.0) (2026-04-02)


### Features

* **enrichment:** add ActivitySession SwiftData model ([9e88ae4](https://github.com/rknightion/grotTrack/commit/9e88ae4ea0fc68b4c581b19a4c93308bb19108e9))
* **enrichment:** add EntityExtractor with NSDataDetector, NLTagger, and regex ([227f64d](https://github.com/rknightion/grotTrack/commit/227f64d15f2198adf4b84c9124bae7817d2e2963))
* **enrichment:** add ExtractedEntity model with entity types ([bd9c515](https://github.com/rknightion/grotTrack/commit/bd9c515f17e51bfd27dc82fd758efab501792e03))
* **enrichment:** add OCR text, entity chips, search, and session segments to UI ([7529a83](https://github.com/rknightion/grotTrack/commit/7529a83f38410901987db33714e75c0fa6d7d68d))
* **enrichment:** add ScreenshotEnrichment SwiftData model ([21bbc18](https://github.com/rknightion/grotTrack/commit/21bbc180a428ed39b5086b5a3f9283b264a24586))
* **enrichment:** add ScreenshotEnrichmentService with Vision OCR pipeline ([c788450](https://github.com/rknightion/grotTrack/commit/c78845096f9247857680ed6ad6f233e0a90e7354))
* **enrichment:** add SessionClassifier with FoundationModels @Generable ([f3330f6](https://github.com/rknightion/grotTrack/commit/f3330f643ba99c4b3b2efd4547794856e0a889a7))
* **enrichment:** add SessionDetector with boundary detection state machine ([2a4e8c2](https://github.com/rknightion/grotTrack/commit/2a4e8c28d3c7aa8a8e84fa5f21c3c931e3b219ac))
* **enrichment:** register ScreenshotEnrichment and ActivitySession in schema ([0e6cf43](https://github.com/rknightion/grotTrack/commit/0e6cf435a531b5bacc4df91fc3296240e2cbd9e7))
* **enrichment:** wire enrichment services into AppCoordinator lifecycle ([b6213da](https://github.com/rknightion/grotTrack/commit/b6213dae2bccb114e6a540f35b974e4d2cc24081))
* **ui:** enhance screenshot capture quality and viewer ([596fc31](https://github.com/rknightion/grotTrack/commit/596fc3144521afa276f0fab0983ad5ae5ccf495e))


### Miscellaneous

* bump deployment target to macOS 26 for Vision/FoundationModels ([c40d1c7](https://github.com/rknightion/grotTrack/commit/c40d1c7e9b4fd51cb776bcab71206415b4136d6b))


### Documentation

* add screenshot enrichment pipeline design spec ([34eebaa](https://github.com/rknightion/grotTrack/commit/34eebaa6a3365f2bdb4f41478c933c194ebde4b7))
* add screenshot enrichment pipeline implementation plan ([3e9449a](https://github.com/rknightion/grotTrack/commit/3e9449ad573ba8b900b64dc394745be0953b5ebb))
* update arch.txt with enrichment pipeline architecture ([061a32a](https://github.com/rknightion/grotTrack/commit/061a32a91631c3fddd2fb199e197b429b1e84e7a))


### Tests

* **enrichment:** update screenshot browser tests for enrichment and search ([a395264](https://github.com/rknightion/grotTrack/commit/a3952646516c146c00b313ea74582cccfcc6ffbb))

## [0.7.0](https://github.com/rknightion/grotTrack/compare/v0.6.0...v0.7.0) (2026-04-02)


### Features

* **screenshots:** add ScreenshotBrowserView window shell with date/mode pickers ([cfa3738](https://github.com/rknightion/grotTrack/commit/cfa3738de739f8e3d6b9205914e77711eb088ddd))
* **screenshots:** add ScreenshotBrowserViewModel with data loading and tests ([954ee63](https://github.com/rknightion/grotTrack/commit/954ee630d9bf07521d1a0fb283eab324948b0307))
* **screenshots:** add vertical timeline rail with activity segments and screenshot markers ([e547757](https://github.com/rknightion/grotTrack/commit/e54775775d047fa1e253d1ad4f87df0d1424adf2))
* **screenshots:** implement adaptive grid view grouped by hour ([c8a209d](https://github.com/rknightion/grotTrack/commit/c8a209d12c9a5789e081c3a26a19b92206b53a07))
* **screenshots:** implement full-bleed viewer with info bar and timeline rail ([83b808c](https://github.com/rknightion/grotTrack/commit/83b808c6b0ce278531290c4b652d9b2994af6d9f))


### Bug Fixes

* resolve lint errors in screenshot browser files ([cd7b58b](https://github.com/rknightion/grotTrack/commit/cd7b58bd02c7092f39f95d7b5e9fd5eeee0117a4))
* **screenshots:** address code review findings ([50f8489](https://github.com/rknightion/grotTrack/commit/50f84893a72254e5c0cc3594a7c8f646a814b8d1))


### Documentation

* add screenshot browser design spec ([55439f0](https://github.com/rknightion/grotTrack/commit/55439f0e702d5dd59062aa6921caaaf571abca83))
* add screenshot browser implementation plan ([2c1cba9](https://github.com/rknightion/grotTrack/commit/2c1cba9eb8a4a7e84fbd0109e226967faabe07a0))
* clarify screenshot-to-activity resolution in spec ([a7d4650](https://github.com/rknightion/grotTrack/commit/a7d46509713f535cfb1f9113229ce361b753f80a))

## [0.6.0](https://github.com/rknightion/grotTrack/compare/v0.5.2...v0.6.0) (2026-04-02)


### Features

* **timeline:** add JSON/CSV export to timeline toolbar ([55c43b5](https://github.com/rknightion/grotTrack/commit/55c43b5a064ee5b1129508b5410b1d78eb3345a4))
* **trends:** add TrendScope enum and unified load/generate/navigate ([500f491](https://github.com/rknightion/grotTrack/commit/500f4911a28430cf44104981743d210c1de715ff))
* **trends:** create unified TrendsView with Week/Month picker ([cc02f3d](https://github.com/rknightion/grotTrack/commit/cc02f3daaaac3a17968c44747397b8aa8dfbdf48))
* **trends:** wire up TrendsView, remove old report windows ([a6cd331](https://github.com/rknightion/grotTrack/commit/a6cd3316bfae46c0cf01f8a9331eb84dd1858a49))


### Bug Fixes

* **timeline:** use .task instead of .onAppear for initial data load ([f8a1799](https://github.com/rknightion/grotTrack/commit/f8a179950651f04201621fa0f0276121b50de422))


### Documentation

* add implementation plan for timeline cleanup and unified trends ([f814aea](https://github.com/rknightion/grotTrack/commit/f814aea31ef6aec34a21d863acf92fc034641833))
* add timeline cleanup and unified trends design spec ([8328158](https://github.com/rknightion/grotTrack/commit/8328158e2702bb1db92ec857510a27481de714e6))
* update arch.txt for timeline cleanup and unified trends ([066471c](https://github.com/rknightion/grotTrack/commit/066471cb7c0dae16cd7e82243c25adebdeb6ec7c))


### Refactoring

* **reports:** remove DailyReport dependency from ReportGenerator ([a39c0c7](https://github.com/rknightion/grotTrack/commit/a39c0c74960dd935cb5f0691a78d83ed14bc3318))
* **reports:** remove DailyReport model and daily report views ([7145f3e](https://github.com/rknightion/grotTrack/commit/7145f3e8911de94135e4327cdb7499fff6e16af0))
* **timeline:** remove dead customer tab ([e158c97](https://github.com/rknightion/grotTrack/commit/e158c979ba13e69b08c43444cb7750f1d811a80c))

## [0.5.2](https://github.com/rknightion/grotTrack/compare/v0.5.1...v0.5.2) (2026-04-02)


### Refactoring

* **timeline:** switch to event-based live updates ([a133b83](https://github.com/rknightion/grotTrack/commit/a133b8328947987c8097da9fc430be38a09633c7))

## [0.5.1](https://github.com/rknightion/grotTrack/compare/v0.5.0...v0.5.1) (2026-04-02)


### Miscellaneous

* setup release-please for extension versioning ([fa2035e](https://github.com/rknightion/grotTrack/commit/fa2035eb5adb17bca685998edf2d642fa5f24340))


### Refactoring

* **browser:** switch to event-driven tab tracking ([ab93178](https://github.com/rknightion/grotTrack/commit/ab9317814bdf0398a14c96964cd677f139c09c7f))

## [0.5.0](https://github.com/rknightion/grotTrack/compare/v0.4.1...v0.5.0) (2026-04-02)


### Features

* add runtime interval config in settings ([f6f82c5](https://github.com/rknightion/grotTrack/commit/f6f82c56262fc0468f06a74223be95ff213a135b))
* add weekly/monthly reports and quick annotations ([7ae60bb](https://github.com/rknightion/grotTrack/commit/7ae60bb9ae095ce17c26387dc69c49eed8568253))


### Miscellaneous

* **deps:** lock file maintenance ([#15](https://github.com/rknightion/grotTrack/issues/15)) ([684e5aa](https://github.com/rknightion/grotTrack/commit/684e5aa47d965e2e6532962da8035a1a7017fe71))

## [0.4.1](https://github.com/rknightion/grotTrack/compare/v0.4.0...v0.4.1) (2026-03-25)


### Refactoring

* remove AI features for local-only app ([71ef1aa](https://github.com/rknightion/grotTrack/commit/71ef1aa156032c68d5e10ff9281b8bfb667b314b))

## [0.4.0](https://github.com/rknightion/grotTrack/compare/v0.3.0...v0.4.0) (2026-03-24)


### Features

* add Chrome extension with automated publishing and enhanced UI ([ddce222](https://github.com/rknightion/grotTrack/commit/ddce2223491518581f9115401a974b51fb2ddbba))

## [0.3.0](https://github.com/rknightion/grotTrack/compare/v0.2.2...v0.3.0) (2026-03-24)


### Features

* **permissions:** add real-time permission monitoring system ([5a7d763](https://github.com/rknightion/grotTrack/commit/5a7d763936fc4a8e794ab42a0ea84269dfa0a728))
* **permissions:** improve screen recording permission request flow ([1cd9ef4](https://github.com/rknightion/grotTrack/commit/1cd9ef44460f8a1d5916f5b6cad63c2383f8a55e))
* **tracking:** add graceful degradation for missing permissions ([541ee23](https://github.com/rknightion/grotTrack/commit/541ee233abf9d4becd9ce60b2e1fed443d5f8abd))


### Bug Fixes

* **app:** update bootstrap to use synchronous permission checks ([0d7014f](https://github.com/rknightion/grotTrack/commit/0d7014f01fb06de96e00d193c48cac25e425c535))
* **ui:** simplify permission request flows in onboarding and settings ([d184401](https://github.com/rknightion/grotTrack/commit/d184401eaaa252fc5e68de850a5041eff5f24351))


### Documentation

* **arch:** update permission handling architecture documentation ([7cd8062](https://github.com/rknightion/grotTrack/commit/7cd8062b5f61bc34082f057beb79fff845973963))


### Refactoring

* **permissions:** replace async screen recording check with synchronous API ([8e88449](https://github.com/rknightion/grotTrack/commit/8e88449b1c9517c7e4b88efeb3ea09452e2ad25f))

## [0.2.2](https://github.com/rknightion/grotTrack/compare/v0.2.1...v0.2.2) (2026-03-24)


### Miscellaneous

* **deps:** pin dependencies ([#3](https://github.com/rknightion/grotTrack/issues/3)) ([35ff7bf](https://github.com/rknightion/grotTrack/commit/35ff7bf0f756eb0d572b5a0859a9d0a31cd75f01))
* **deps:** update dependency typescript to v6 ([d87361c](https://github.com/rknightion/grotTrack/commit/d87361c330cec4b1ed88150f1b3de7293c1fe6e8))
* **deps:** update dependency typescript to v6 ([f58f558](https://github.com/rknightion/grotTrack/commit/f58f558dd994d5868d399f854385d4f3ddac1d54))

## [0.2.1](https://github.com/rknightion/grotTrack/compare/v0.2.0...v0.2.1) (2026-03-24)


### Bug Fixes

* skip export step in macOS release workflow ([0c2d676](https://github.com/rknightion/grotTrack/commit/0c2d676014ac73d365282d4dba662580fcbaa5cf))
* ts6 upgrade ([80c623a](https://github.com/rknightion/grotTrack/commit/80c623aeb71cd3101a62ad45a9ef4963b8dab1ea))


### Miscellaneous

* **deps:** update actions/upload-artifact action to v7 ([e9d32ca](https://github.com/rknightion/grotTrack/commit/e9d32ca920618b51ec6c1384757faec230d146a0))
* **deps:** update actions/upload-artifact action to v7 ([d68ccd5](https://github.com/rknightion/grotTrack/commit/d68ccd579ab94ddec86f09cb001c37f0104d1f50))
* **deps:** update dependency @types/chrome to ^0.1.0 ([dd09e5a](https://github.com/rknightion/grotTrack/commit/dd09e5acb164cf6439310da0f98a7a16a2abfb76))
* **deps:** update dependency @types/chrome to ^0.1.0 ([d42dc5f](https://github.com/rknightion/grotTrack/commit/d42dc5fd3c9eb878eb828f7ebbade035a694adbe))
* **deps:** update github actions ([f8d5cfd](https://github.com/rknightion/grotTrack/commit/f8d5cfd5116d9608d239ba2eb798bb7772b07be6))
* **deps:** update github actions (major) ([8e6c103](https://github.com/rknightion/grotTrack/commit/8e6c103dfe8585857d709447475c81491692f291))

## [0.2.0](https://github.com/rknightion/grotTrack/compare/v0.1.0...v0.2.0) (2026-03-24)


### Features

* initial release attempt ([a3fae06](https://github.com/rknightion/grotTrack/commit/a3fae066dee7161fb33c43066ea7e5659b1bed26))
