# SwiftPlatform

Swift wrappers for FreeRTOS and ESP-IDF primitives. Swift module name: **`Platform`**.

Depends on: `SwiftSupport`

## Source files

| C file | Swift file | Public type |
|---|---|---|
| `error.c` / `error.h` | `Error.swift` | `Error` enum, `esp_err_t.throwEspError()`, `esp_err_t.abortOnError()`, `BaseType_t.throwFreeRtosError()` |
| `log.c` / `log.h` | `Logger.swift` | `Logger(tag:)` |
| — | `TickType.swift` | `TickType_t(ms:)` — `nil` → `portMAX_DELAY` |
| `event_group.c` / `event_group.h` | `EventGroup.swift` | `EventGroup<EventBits: OptionSet>` |
| `task.c` / `task.h` | `Task.swift` | `Task` (class) |
| — | `IsrHandler.swift` | `IsrHandler` (~Copyable struct) |
| — | `System.swift` | `restart() -> Never` — typed-`Never` wrapper over `esp_restart()` |
| `platform.c` / `platform.h` | — | IntelliSense stub only — imports the umbrella header |

## Usage examples

```swift
// Logger — one instance per file, tag appears in ESP-IDF serial output
let log = Logger(tag: "my-component")
log.i("started")
log.w("retrying")
log.e("failed: \(error.name)")

// Task — run() on the Task object, waitNotification() is static (blocks the calling task)
let task = Task()
try task.run(name: "worker", stackSize: 4096, priority: 5) {
    let bits: MyEvents = Task.waitNotification()
    // handle bits
}
task.notify(MyEvents.ready)
```

## Non-obvious patterns

**`Error`** is a two-case enum: `.espError(esp_err_t)` and `.freeRtosError(Int32)`. Two patterns on `esp_err_t`: `throwEspError()` throws (for runtime failures); `abortOnError()` calls `fatalError()` (for boot-time driver inits that must not fail). Both accept an optional callback for logging before the throw/abort. `throwFreeRtosError()` is on `BaseType_t`.

**`EventGroup`** is `~Copyable` (noncopyable struct) — it owns the FreeRTOS handle and calls `vEventGroupDelete` in `deinit`. `wait()` and `set()` use `borrowing` to avoid triggering the consume checker.

**`Task`** is a `class` (reference type) and must stay one — `Unmanaged<T>` (used to smuggle `self` through `xTaskCreate`'s `void*`) requires `AnyObject`, and the entry closure needs ARC to stay alive past `run()`. The closure passed to `run()` is retained via `Unmanaged.passRetained`; `task.handle = nil` before `vTaskDelete(nil)` ensures the handle is cleared before the task stack is freed. `waitNotification()` is a `static` method — it blocks the **calling** task, not the `Task` object.

**`IsrHandler`** is a `~Copyable` struct. Its `deinit` calls `heap_caps_free(args)` to release the C-allocated args struct. Functions that only read `handler`/`args` should take it as `borrowing IsrHandler`. Never call arbitrary Swift code from the ISR — only install `handler.handler` / `handler.args` into the driver registration API.

**Logger compile-time guards** — `CMakeLists.txt` translates `CONFIG_LOG_MAXIMUM_LEVEL` into per-level `-DLOG_<LEVEL>_ENABLED` Swift flags. Guard log calls with `#if LOG_INFO_ENABLED` etc. so unused levels compile away. `@inline(__always)` on Logger methods ensures the guard is zero-cost.

**`platform.c`** exists only as an IntelliSense/Clang compilation stub. It imports the umbrella header so the IDE can resolve symbols; it contains no runtime logic.

**`restart()`** exists because `esp_restart()`'s C declaration is `__attribute__((noreturn))`, but this Embedded Swift toolchain does not import that as a Swift `-> Never` return type (confirmed empirically — code calling raw `esp_restart()` followed by unreachable statements did not get flagged/optimized as such). `restart()` calls it and then traps in a `vTaskDelay`-based loop (not a busy `while true {}`) so callers get real `Never` typing without spinning the CPU while `esp_restart()`'s own deferred shutdown sequence runs.
