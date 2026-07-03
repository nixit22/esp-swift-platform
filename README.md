# SwiftPlatform

Swift platform APIs for ESP-IDF — idiomatic wrappers around FreeRTOS and ESP-IDF C APIs for [Embedded Swift](https://github.com/apple/swift-embedded-examples) on ESP32 targets.

## Requirements

- ESP-IDF **5.5** or later
- [Embedded Swift toolchain](https://www.swift.org/download/) (`swiftc` in `PATH` or pointed to by `CMAKE_Swift_COMPILER`)
- [SwiftSupport](https://github.com/nixit22/esp-idf-swift-support.git) — pulled in automatically as a transitive dependency

## Adding SwiftPlatform as a Dependency

Clone `swift-esp` alongside your project and point `EXTRA_COMPONENT_DIRS` at the repo root in your app's `CMakeLists.txt`:

```cmake
set(EXTRA_COMPONENT_DIRS
    "${CMAKE_CURRENT_LIST_DIR}/../swift-esp"
)
```

ESP-IDF discovers all components automatically. No `idf_component.yml` entry is needed.

## CMakeLists.txt

Add `SwiftPlatform` to `REQUIRES` and `SwiftSupport` to `PRIV_REQUIRES`, then call `swift_configure()`:

```cmake
idf_component_register(
    SRCS "MyFile.swift"
    PRIV_INCLUDE_DIRS "."
    REQUIRES SwiftPlatform
    PRIV_REQUIRES SwiftSupport
)

swift_configure(MODULE_NAME MyModule)
```

`SwiftPlatform` (or any component whose Swift API a caller imports) must appear in `REQUIRES`. `SwiftSupport` only needs `PRIV_REQUIRES` — callers don't import it directly, they just need `swift_configure()` available at configure time.

## Quick Start

```swift
import Platform   // Swift module name set by swift_configure(MODULE_NAME Platform)

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
    } catch let error as Platform.Error {
        log.e("error: \(error.name)")
    }
}
```

> The module name imported in Swift (`Platform`) is determined by the `MODULE_NAME` argument passed to `swift_configure()` in the component's `CMakeLists.txt`, not the IDF component name (`SwiftPlatform`).

## API Overview

| Type | Description |
|---|---|
| `Logger` | ESP-IDF logging wrapper; per-level compile-time guards (`LOG_INFO_ENABLED`, etc.) |
| `Task` | FreeRTOS task lifecycle with typed notification bits via `OptionSet` |
| `EventGroup<EventBits>` | Generic FreeRTOS event group; wait/set typed bits, ISR handler support |
| `Error` | Unified `esp_err_t` / FreeRTOS error enum with human-readable `.name` |
| `IsrHandler` | C-callback + args bundle for ISR-safe event signalling |
| `TickType_t.init(ms:)` | Converts optional milliseconds to RTOS ticks (`nil` → `portMAX_DELAY`) |

## License

MIT License — Copyright (c) 2026 Nicolas Christe
