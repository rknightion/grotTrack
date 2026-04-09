import Foundation

// Entry point for the native messaging host process.
// Chrome launches this as a subprocess via native messaging.

let host = NativeMessageHost()
let semaphore = DispatchSemaphore(value: 0)

Task {
    await host.runMessageLoop()
    semaphore.signal()
}

semaphore.wait()
