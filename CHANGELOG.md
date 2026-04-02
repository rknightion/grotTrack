# Changelog

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
