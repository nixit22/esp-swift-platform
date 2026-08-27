# SwiftPlatform

Idiomatic Swift wrappers around FreeRTOS and ESP-IDF primitives (logging, tasks, event groups, error handling, ISR helpers) for Embedded Swift on ESP32 targets. Swift module name: **`Platform`**.

Depends on: `SwiftSupport`.

## Usage

```swift
import Platform

private struct AppEvents: OptionSet {
    let rawValue: UInt32
    static let booted = Self(rawValue: 1 << 0)
}

@_cdecl("app_main")
func app_main() {
    let log = Logger(tag: "app")
    log.i("booted")

    do {
        let eg = try EventGroup<AppEvents>()
        eg.set(.booted)

        if eg.wait(.booted, timeoutMs: 100).contains(.booted) {
            log.i("event received")
        }
        // No explicit cleanup — deinit calls vEventGroupDelete when `eg` goes out of scope.
    } catch let error as PlatformError {
        log.e("error: \(error.name)")
    }
}
```

See [`CLAUDE.md`](CLAUDE.md) for the full type list (`Task`, `IsrHandler`, `TickType_t.init(ms:)`) and non-obvious patterns.

## License

MIT License — Copyright (c) 2026 Nicolas Christe
