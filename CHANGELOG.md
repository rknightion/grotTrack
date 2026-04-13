# Changelog

## [0.12.6](https://github.com/rknightion/grotTrack/compare/v0.12.5...v0.12.6) (2026-04-13)


### Bug Fixes

* use marketing version for CFBundleVersion so Sparkle detects updates ([5432bd0](https://github.com/rknightion/grotTrack/commit/5432bd0d3320d0fc7fa744a231883a4f38d78e0a))

## [0.12.5](https://github.com/rknightion/grotTrack/compare/v0.12.4...v0.12.5) (2026-04-13)


### Miscellaneous

* **deps:** lock file maintenance ([#45](https://github.com/rknightion/grotTrack/issues/45)) ([4ea6616](https://github.com/rknightion/grotTrack/commit/4ea66161ddf777e80ce8ff85beaf20d816ebbbd8))
* **deps:** lock file maintenance ([#46](https://github.com/rknightion/grotTrack/issues/46)) ([3814cc0](https://github.com/rknightion/grotTrack/commit/3814cc07c8e5b8dacf45ed1fc0650014e6ccfd39))
* **deps:** update dependency wxt to v0.20.21 ([#47](https://github.com/rknightion/grotTrack/issues/47)) ([246393a](https://github.com/rknightion/grotTrack/commit/246393af6bfb851f6663d6fd222cfd8f3943181b))
* **deps:** update softprops/action-gh-release action to v3 ([#43](https://github.com/rknightion/grotTrack/issues/43)) ([27528af](https://github.com/rknightion/grotTrack/commit/27528afc27482cf4adabc6297f03e43e3b69a482))

## [0.12.4](https://github.com/rknightion/grotTrack/compare/v0.12.3...v0.12.4) (2026-04-10)


### Bug Fixes

* use AppStorage for update settings and modern GitHub Pages deployment ([61dbf16](https://github.com/rknightion/grotTrack/commit/61dbf16eec1805f39e3b1522a29b91336a348b2b))


### Miscellaneous

* **deps:** update github actions ([#42](https://github.com/rknightion/grotTrack/issues/42)) ([5f5c454](https://github.com/rknightion/grotTrack/commit/5f5c454a512e1eae684d4d710dedc49e3001dece))

## [0.12.3](https://github.com/rknightion/grotTrack/compare/v0.12.2...v0.12.3) (2026-04-09)


### Miscellaneous

* **deps:** pin actions/upload-artifact action to ea165f8 ([#37](https://github.com/rknightion/grotTrack/issues/37)) ([b292aa7](https://github.com/rknightion/grotTrack/commit/b292aa76054c03f7c2167eaa9011529d3ae7eb05))

## [0.12.2](https://github.com/rknightion/grotTrack/compare/v0.12.1...v0.12.2) (2026-04-09)


### Bug Fixes

* re-sign Sparkle framework binaries for notarization ([0d09fbd](https://github.com/rknightion/grotTrack/commit/0d09fbd9584c7b29d8997cd149671265fc7a5149))


### Miscellaneous

* add manual workflow to fetch notarization logs ([8aa8c16](https://github.com/rknightion/grotTrack/commit/8aa8c16c38b047fe50d74a59f6109e6ca5fc49aa))

## [0.12.1](https://github.com/rknightion/grotTrack/compare/v0.12.0...v0.12.1) (2026-04-09)


### Bug Fixes

* enable hardened runtime for all targets in release archive ([6a5b1c7](https://github.com/rknightion/grotTrack/commit/6a5b1c7a179ac7f45b8b15ab8c9f347a2dab449d))

## [0.12.0](https://github.com/rknightion/grotTrack/compare/v0.11.4...v0.12.0) (2026-04-09)


### Features

* add appcast generation and GitHub Pages deployment to release workflow ([bb7f59d](https://github.com/rknightion/grotTrack/commit/bb7f59d37ef24c94bfdad1f628065484828c321e))
* add appcast generation script for Sparkle updates ([c10cb06](https://github.com/rknightion/grotTrack/commit/c10cb06e6c601ae1f6366ca2d1740e5f2072f12e))
* add Check for Updates button to menu bar popover ([c64c02f](https://github.com/rknightion/grotTrack/commit/c64c02f265acc3b0069e4bc08f7bad1d333aeb15))
* add expanded detail level for 10x+ timeline zoom ([121448d](https://github.com/rknightion/grotTrack/commit/121448d6d60bbbc7d7c20ab73104e9be062845b0))
* add Sparkle appcast URL and EdDSA public key placeholder to Info.plist ([98fa720](https://github.com/rknightion/grotTrack/commit/98fa7203caa3b7319f10cd4be3da8d7d0c2be83c))
* add Sparkle auto-update integration ([2a23337](https://github.com/rknightion/grotTrack/commit/2a23337b6c822ac2b84bd26c4a97c16ed48b7397))
* add Sparkle SPM dependency for auto-update ([cc9682f](https://github.com/rknightion/grotTrack/commit/cc9682f96bbaebe27ba703e75e45a636c3d7846e))
* add UpdateSettingsView with granular update controls ([593e813](https://github.com/rknightion/grotTrack/commit/593e813da64b29f0a9dfe2f2799e9e70450669b4))
* anchor zoom to playhead position ([60b5431](https://github.com/rknightion/grotTrack/commit/60b54319e35717f84f644b677d43a13bea975df6))
* create UpdaterService and wire into AppCoordinator ([02a2581](https://github.com/rknightion/grotTrack/commit/02a258156716a74c18867cfc78fcbcce60da0d73))
* keyboard arrows scroll timeline to marker via playhead ([f23afd4](https://github.com/rknightion/grotTrack/commit/f23afd4855f2686188fa19764219fc03780e9e6f))
* playhead-centric timeline UX ([5761181](https://github.com/rknightion/grotTrack/commit/576118138dba9a6aa97466d1a89aac60d08047c5))
* replace bidirectional scroll-selection with playhead-centric model ([8a1f1aa](https://github.com/rknightion/grotTrack/commit/8a1f1aa55c31685aa532dbd4779e426e86b00695))
* show inline metadata cards at 10x+ zoom ([595bd0f](https://github.com/rknightion/grotTrack/commit/595bd0fac248129d7cd53a084cb0595097aef5e9))


### Bug Fixes

* add CI signing validation and disable frequency picker when auto-check off ([6ba449e](https://github.com/rknightion/grotTrack/commit/6ba449ef2b583134acaddc0a0beb8bafce1b8a7b))
* marker click scrolls to playhead instead of direct selection ([ef513b1](https://github.com/rknightion/grotTrack/commit/ef513b188beafa30f40a2420891a36190e91d1bb))
* resolve index space mismatch and review feedback ([ef73c2c](https://github.com/rknightion/grotTrack/commit/ef73c2c17bd19a8d87914cbf51bf31f28f9d7451))


### Miscellaneous

* set Sparkle EdDSA public key for updates ([c6a3261](https://github.com/rknightion/grotTrack/commit/c6a32610760a3e8a2b0d43d63c54b887fd37905f))


### Documentation

* add auto-update design spec ([38dd2c3](https://github.com/rknightion/grotTrack/commit/38dd2c36c651b6f814be28a09f58f8d39f57dd5c))
* add auto-update implementation plan ([fc5da32](https://github.com/rknightion/grotTrack/commit/fc5da32f53a9bc03f2480dafb42d2569e1055c54))
* add timeline playhead UX design spec ([d78de3a](https://github.com/rknightion/grotTrack/commit/d78de3a967da25831ef9ff9913fa3f3c6463b628))
* add timeline playhead UX implementation plan ([6c1b5aa](https://github.com/rknightion/grotTrack/commit/6c1b5aaf696650645ef4077eba1dc0930952abbc))


### Tests

* add tests for marker navigation index helpers ([167bb54](https://github.com/rknightion/grotTrack/commit/167bb540556468f22a7fab01344f1a6a968ea1f3))

## [0.11.4](https://github.com/rknightion/grotTrack/compare/v0.11.3...v0.11.4) (2026-04-09)


### Miscellaneous

* add version info to macOS app bundle ([c2ef7a7](https://github.com/rknightion/grotTrack/commit/c2ef7a7158c4548151132711f471aa8a8b2ba367))

## [0.11.3](https://github.com/rknightion/grotTrack/compare/v0.11.2...v0.11.3) (2026-04-09)


### Bug Fixes

* disable macOS Automatic Termination that was killing the app ([b8365aa](https://github.com/rknightion/grotTrack/commit/b8365aa27b724fa86a051f63076c8e4075a788e1))
* move startup logic to init() so tracking starts without menu bar interaction ([dd0b6cc](https://github.com/rknightion/grotTrack/commit/dd0b6cc40a359b5e44763d9aef732d55ad9baa76))


### Miscellaneous

* **deps:** update dependency @types/chrome to v0.1.40 ([#31](https://github.com/rknightion/grotTrack/issues/31)) ([89d5e9f](https://github.com/rknightion/grotTrack/commit/89d5e9ffac95c6352946ef028e29d7bc2e3213b9))

## [0.11.2](https://github.com/rknightion/grotTrack/compare/v0.11.1...v0.11.2) (2026-04-08)


### Bug Fixes

* prevent App Nap from suspending activity tracking and screenshots ([188bb39](https://github.com/rknightion/grotTrack/commit/188bb396b66f3903c014a35c9da3499d0a3e84b1))
* timeline scroll and zoom bugs ([98bf3f4](https://github.com/rknightion/grotTrack/commit/98bf3f48ee2ef34203b872d385854e5261353f78))


### Performance

* **timeline:** optimize hour lookup with dictionary ([9cca6ba](https://github.com/rknightion/grotTrack/commit/9cca6ba2ec23a48275985f7b7143a9cd294c819d))

## [0.11.1](https://github.com/rknightion/grotTrack/compare/v0.11.0...v0.11.1) (2026-04-08)


### Bug Fixes

* resolve CI build failure — [@preconcurrency](https://github.com/preconcurrency) import for ScreenCaptureKit ([85d58a0](https://github.com/rknightion/grotTrack/commit/85d58a057391062df2ebc3be6a11862481be7b16))

## [0.11.0](https://github.com/rknightion/grotTrack/compare/v0.10.1...v0.11.0) (2026-04-07)


### Features

* add display grouping by timestamp to ScreenshotBrowserViewModel ([25c01a1](https://github.com/rknightion/grotTrack/commit/25c01a15554a0ec083aad141a355a80fd288b0e3))
* add display-suffixed filename helper to ScreenshotManager ([8c6f30a](https://github.com/rknightion/grotTrack/commit/8c6f30a2db5b6fe3c9f27ad6411a57736fcad881))
* add displayID and displayIndex fields to Screenshot model ([623818d](https://github.com/rknightion/grotTrack/commit/623818d948205cc0b6c11b3f126366d4090ee4c5))
* add multi-display split pane with maximize/restore to viewer ([a8b6734](https://github.com/rknightion/grotTrack/commit/a8b6734080c7edb519f3025855ea021a696b88ff))
* add timeline zoom state, active hours range, and nearest screenshot lookup ([64c7395](https://github.com/rknightion/grotTrack/commit/64c739561af9739c1e9bb808074724b8a642a5cd))
* capture all connected displays in parallel with display metadata ([3ceb7e7](https://github.com/rknightion/grotTrack/commit/3ceb7e7a47168f1796aef069c98bafd2047b1b3e))
* rewrite TimelineRailView with ScrollView, pinch zoom, and progressive detail ([e714cd0](https://github.com/rknightion/grotTrack/commit/e714cd09e96304629417852766343cf577e8c955))
* sidebar zoom/scroll and multi-screen capture ([0a483e1](https://github.com/rknightion/grotTrack/commit/0a483e19e3d21c861a1ea112d8325a77229d85ba))
* wire scroll-to-select — scrolling timeline drives screenshot selection ([63224a0](https://github.com/rknightion/grotTrack/commit/63224a08f704e95468b2ae23a24705e50e32f19b))


### Bug Fixes

* address code review issues — feedback loop, concurrency safety, zoom math, primary-only markers ([ff215b5](https://github.com/rknightion/grotTrack/commit/ff215b564cd25e5682f27e0d0414251c12a75c2a))


### Miscellaneous

* fix lint warnings from sidebar zoom and multi-screen changes ([cf19601](https://github.com/rknightion/grotTrack/commit/cf196013861a96a965c5c1d572d2cb23dfb6279c))


### Documentation

* add design spec for sidebar zoom/scroll and multi-screen capture ([3b79031](https://github.com/rknightion/grotTrack/commit/3b790318319b4c5ce28e5ea87f02ff0217c38bf0))
* add implementation plan for sidebar zoom and multi-screen capture ([94b174a](https://github.com/rknightion/grotTrack/commit/94b174aaff75f068bfa8621b989bb3ad9b21fa61))
* rewrite README with comprehensive feature set ([9e58c55](https://github.com/rknightion/grotTrack/commit/9e58c55210476319e2bbb755fd634fedee377fc4))

## [0.10.1](https://github.com/rknightion/grotTrack/compare/v0.10.0...v0.10.1) (2026-04-06)


### Bug Fixes

* remove stale Xcode 16 selection from release workflow ([0fabfa8](https://github.com/rknightion/grotTrack/commit/0fabfa8b93047efbf380f9f43cf755f6542ec5b5))

## [0.10.0](https://github.com/rknightion/grotTrack/compare/v0.9.1...v0.10.0) (2026-04-06)


### Features

* add Cmd+[, Cmd+], Cmd+T, Cmd+E keyboard shortcuts to timeline ([1418a78](https://github.com/rknightion/grotTrack/commit/1418a78db4e9129d851e5b44268d4bc4298f610f))
* add export button to trends view ([226f7d0](https://github.com/rknightion/grotTrack/commit/226f7d037b1cd497697cde922eb63a2c66a09b51))
* add Help menu with keyboard shortcuts sheet ([fb86214](https://github.com/rknightion/grotTrack/commit/fb8621497cfa5ed4f6398d8691966460fda0f675))
* add interactive hover tooltips to stats view charts ([226dcba](https://github.com/rknightion/grotTrack/commit/226dcbaa8f73ec2e2410e99767524c93407f20bb))
* add keyboard shortcuts sheet view ([be0b558](https://github.com/rknightion/grotTrack/commit/be0b5586659909a75707bd7d4415aee3afc137db))
* add report freshness bar with regenerate button ([b5b786c](https://github.com/rknightion/grotTrack/commit/b5b786cd173e3d6115d59c6bea24c2e531c1e26f))
* add reset-to-default button for custom hotkeys ([d5e1ae2](https://github.com/rknightion/grotTrack/commit/d5e1ae2f47e7939f8228bd361d11ac72fcf0ecfd))
* add search filter and alphabetical sorting to exclusion list ([684cf91](https://github.com/rknightion/grotTrack/commit/684cf91ccf7ea8a4b38b4ac2fc34a121348d7ac9))
* add search/filter bar and sessions tab to timeline ([d8f0a67](https://github.com/rknightion/grotTrack/commit/d8f0a67a4ce54faca98a380d4f25cc634e6ea89a))
* add section labels to timeline rail segments ([ac2130b](https://github.com/rknightion/grotTrack/commit/ac2130b86687962925c6ab471882e1b59900ea26))
* add session loading, search/filter, and enrichment data to TimelineViewModel ([ac28188](https://github.com/rknightion/grotTrack/commit/ac281883e132a4d2c42f99e19d69719bbd1b3b3d))
* add sessions case to ViewMode enum ([3dab9e3](https://github.com/rknightion/grotTrack/commit/3dab9e3e5b5d8933632b5618bfe01e13baae399d))
* add Sessions view mode to timeline ([2aa83aa](https://github.com/rknightion/grotTrack/commit/2aa83aa787efec3942343f20a53a1c907c69f8c7))
* add skip-all link to onboarding welcome page ([edbe1f0](https://github.com/rknightion/grotTrack/commit/edbe1f0da4014974e2bb86abc5b92ba92cf5e9fd))
* add small/large grid icons to zoom slider endpoints ([17f4548](https://github.com/rknightion/grotTrack/commit/17f454896ac69cf7b189be21c26ac0bd2b20f8c7))
* add TaskAllocation model and JSON fields to reports ([f0ac630](https://github.com/rknightion/grotTrack/commit/f0ac630c1abd4075d61a8c4d770e433e322c59a0))
* display task-level breakdown in weekly and monthly reports ([47ef95d](https://github.com/rknightion/grotTrack/commit/47ef95d2c6c310dfe0aae035c343a18bce6adf70))
* enrich collapsed hour blocks with event count, focus pill, app %, session labels ([a1dc4d1](https://github.com/rknightion/grotTrack/commit/a1dc4d1cca1b3d129689709a9518b7b9e0e14a22))
* generate task allocations from sessions in reports ([ffe1998](https://github.com/rknightion/grotTrack/commit/ffe19981165e938f87d31c24190bc1c5d99848ea))
* include annotations and sessions in JSON/CSV exports ([f87b800](https://github.com/rknightion/grotTrack/commit/f87b8009054bef8a5e03b76e7dd79e5e5bdf1cbc))
* increase viewer context panel max height to 280px ([88d59bd](https://github.com/rknightion/grotTrack/commit/88d59bd3824a42b852394911b6d6f315aea2ead6))
* persist expand/collapse state per date across navigation ([90868e7](https://github.com/rknightion/grotTrack/commit/90868e71c6886b015f6a25607d0821b9ca4c128f))
* redesign popover with session-aware activity, focus pill, compact nav ([29a437b](https://github.com/rknightion/grotTrack/commit/29a437bbceb6f3f383d4660f374e95247f15db74))
* show confirmation banner when permissions are granted ([6c36ed0](https://github.com/rknightion/grotTrack/commit/6c36ed093ce0d826dbfa034be5b89f07e1e87e1b))
* show detailed diagnostic status for browser extension connection ([0637edd](https://github.com/rknightion/grotTrack/commit/0637eddf2253406dd26cb83e83ace593076f02da))
* update search placeholder to describe searchable fields ([bc151e1](https://github.com/rknightion/grotTrack/commit/bc151e1922214fc913cc016aa43d5b32ef8796fa))
* use specific impact-based permission descriptions in onboarding ([8d5454f](https://github.com/rknightion/grotTrack/commit/8d5454f6cc7a1a4ecfb90d9e2ce682609e53384e))


### Bug Fixes

* remove worktrees from index, add to gitignore ([9aab9a1](https://github.com/rknightion/grotTrack/commit/9aab9a1e06bb8d8476551b9e4727b43a23bffce5))
* resolve 3 swiftlint errors from UX improvement pass ([b5ee874](https://github.com/rknightion/grotTrack/commit/b5ee874a02342b0e78c06112085d97162d6c5b34))
* resolve all swiftlint warnings in app source code ([0d61e90](https://github.com/rknightion/grotTrack/commit/0d61e903082441dd3ac62d885e68f3be4fe9dcd9))
* resolve swiftlint warnings in ViewModels and Services ([71efe35](https://github.com/rknightion/grotTrack/commit/71efe353851f86b04bbab9d0cfdca1cf1a0e4621))
* resolve swiftlint warnings in Views ([bbd1af5](https://github.com/rknightion/grotTrack/commit/bbd1af50602f3600298c403efe1e3849d757b927))
* use dynamic bundle-relative path for Chrome extension folder ([5eec2f4](https://github.com/rknightion/grotTrack/commit/5eec2f404484663c25ff5916a8b4c9693b280ae3))


### Documentation

* add three implementation plans for UX improvement pass ([ef4ee02](https://github.com/rknightion/grotTrack/commit/ef4ee0210916eecf50a8e1515df8600bf106a891))
* add UX improvement pass design spec ([d3359c7](https://github.com/rknightion/grotTrack/commit/d3359c7b0fb5a87945a8b1ea666f6e86a1a5115b))

## [0.9.1](https://github.com/rknightion/grotTrack/compare/v0.9.0...v0.9.1) (2026-04-06)


### Miscellaneous

* **deps:** lock file maintenance ([#25](https://github.com/rknightion/grotTrack/issues/25)) ([8e00a90](https://github.com/rknightion/grotTrack/commit/8e00a907790aed281a7a7c48e88d89e299b35f9e))
* **deps:** update dependency @types/chrome to v0.1.39 ([#23](https://github.com/rknightion/grotTrack/issues/23)) ([dd7d72f](https://github.com/rknightion/grotTrack/commit/dd7d72fbd715abb8287f95d0974a54a5b848b401))

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
