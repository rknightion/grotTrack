import Sparkle

@Observable
@MainActor
final class UpdaterService {
    let controller: SPUStandardUpdaterController

    var updater: SPUUpdater {
        controller.updater
    }

    init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        updater.checkForUpdates()
    }
}
