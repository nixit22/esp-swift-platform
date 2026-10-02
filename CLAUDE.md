# SwiftPlatform

Swift wrappers for FreeRTOS and ESP-IDF primitives. Swift module name: **`Platform`**.

Depends on: `SwiftSupport`

## Source files

| C file | Swift file | Public type |
|---|---|---|
| `error.c` / `error.h` | `PlatformError.swift` | `PlatformError` enum, `esp_err_t.throwEspError()`, `esp_err_t.abortOnError()`, `BaseType_t.throwFreeRtosError()` |
| `log.c` / `log.h` | `Logger.swift` | `Logger(tag:)` |
| — | `TickType.swift` | `TickType_t(ms:)` — `nil` → `portMAX_DELAY`; `.now` / `.nowFromISR` — current tick count |
| `event_group.c` / `event_group.h` | `EventGroup.swift` | `EventGroup<EventBits: OptionSet>` |
| `task.c` / `task.h` | `Task.swift` | `TaskProtocol`, `Task` (class), `MainTask` (class), `TaskNotifier`, `TaskEventsNotifier` |
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

// MainTask — wraps app_main's own task so it can hand out notifiers too, just like Task
private let mainTask = MainTask {
    // app body — mainTask.notifier(...) works exactly like task.notifier(...) above
}
@_cdecl("app_main")
func app_main() { mainTask.run() }
```

## Non-obvious patterns

**`PlatformError`** is a two-case enum: `.espError(esp_err_t)` and `.freeRtosError(Int32)`. Two patterns on `esp_err_t`: `throwEspError()` throws (for runtime failures); `abortOnError()` calls `fatalError()` (for boot-time driver inits that must not fail). Both accept an optional callback for logging before the throw/abort. `throwFreeRtosError()` is on `BaseType_t`.

**`EventGroup`** is `~Copyable` (noncopyable struct) — it owns the FreeRTOS handle and calls `vEventGroupDelete` in `deinit`. `wait()` and `set()` use `borrowing` to avoid triggering the consume checker.

**`TaskProtocol`** is the shared interface between `Task` (a task this component created via `run()`) and `MainTask` (ESP-IDF's own "main" task, which this component never creates but still needs to notify). It declares exactly two requirements — `notify(_ events: UInt32)` and `notifyIsrHandler(_ events: UInt32) -> IsrHandler` — the only two operations that actually need to touch a conformer's own private `TaskHandle_t?`. Every typed, public-facing overload (`notify()`, the `OptionSet`-generic `notify`/`notifier`/`notifyIsrHandler` overloads) is a single shared default implementation in a `TaskProtocol` extension, built on top of those two. This is a deliberate trade: the two raw `UInt32`-based primitives become public API (a protocol can't have a requirement more restricted than the protocol's own access level), where before `notify(_ events: UInt32)` was `private` — accepted in exchange for `Task` and `MainTask` sharing one implementation of everything else instead of duplicating it. `TaskProtocol: AnyObject` because `TaskNotifier`/`TaskEventsNotifier` store a `TaskProtocol` *existential* and need reference semantics (identity, not a value copy) for that to mean anything; it's also why the two requirements must stay non-generic — Swift cannot dispatch a generic protocol requirement through an existential value, only through a concrete type or a generic constraint.

**`Task`** is a `class` (reference type) and must stay one — `Unmanaged<T>` (used to smuggle `self` through `xTaskCreate`'s `void*`) requires `AnyObject`, and the entry closure needs ARC to stay alive past `run()`. The closure passed to `run()` is retained via `Unmanaged.passRetained`; `task.handle = nil` before `vTaskDelete(nil)` ensures the handle is cleared before the task stack is freed. `waitNotification()` is a `static` method — it blocks the **calling** task, not the `Task` object, and is not part of `TaskProtocol`: it doesn't operate on `self` (it asks FreeRTOS "what are my own pending bits," regardless of which `Task`/`MainTask` Swift object represents "me"), so code running inside either kind of task calls it the same way, directly.

**`MainTask`** exists so the ESP-IDF main task — which this component doesn't create and thus can't obtain a `Task` for via `run()` — can still hand out notifiers to other components, symmetric with any `Task.run()`-created task. It conforms to `TaskProtocol` directly (its own private `handle`, captured once via `xTaskGetCurrentTaskHandle()` in `init`) rather than composing a `Task` — there's no `Task.current()` factory; that was tried and dropped in favor of this, since a composition-based wrapper would have needed to document "never call `run()` on this" as an unenforced caller contract, whereas `MainTask` simply has no `run(name:stackSize:priority:entry:)` method to misuse. Its `handle` is `TaskHandle_t`, not `TaskHandle_t?` like `Task`'s — deliberately: `Task.handle` is legitimately nil before `run()` succeeds, so `notify()` no-op'ing on nil is correct there, but `MainTask` has no equivalent pre-ready window (it's captured unconditionally in `init`), so treating it as optional would only ever mean "silently swallow every notification forever" with no way to distinguish that from working correctly — a non-optional handle makes that failure loud (a trap at boot) instead. Usage is a single global plus a one-line `app_main()` shim:
```swift
private let mainTask = MainTask {
    // app body — may reference `mainTask` itself to build notifiers for other components
}

@_cdecl("app_main")
func app_main() { mainTask.run() }
```
`MainTask.init` captures the current task handle immediately but does not run `body` — that only happens on `run()`, so constructing `mainTask` stays a fast, non-blocking global initializer even though `body` itself may never return. This mirrors `Task`'s own `init()`/`run()` split (construction is cheap; starting is a separate, explicit call) rather than running `body` inside `init()`, which would make a top-level `let mainTask = MainTask { ... }`'s lazy-initializer block forever on first access — technically legal but a confusing shape for a type that looks like an ordinary object.

**`TickType_t.now`/`.nowFromISR`** — `.now` wraps `xTaskGetTickCount()` and is not ISR-safe; call
`.nowFromISR` (`xTaskGetTickCountFromISR()`) instead from interrupt context.

**`IsrHandler`** is a `~Copyable` struct. Its `deinit` calls `heap_caps_free(args)` to release the C-allocated args struct. Functions that only read `handler`/`args` should take it as `borrowing IsrHandler`. Never call arbitrary Swift code from the ISR — only install `handler.handler` / `handler.args` into the driver registration API.

**Logger compile-time guards** — `CMakeLists.txt` translates `CONFIG_LOG_MAXIMUM_LEVEL` into per-level `-DLOG_<LEVEL>_ENABLED` Swift flags. Guard log calls with `#if LOG_INFO_ENABLED` etc. so unused levels compile away. `@inline(__always)` on Logger methods ensures the guard is zero-cost.

**`platform.c`** exists only as an IntelliSense/Clang compilation stub. It imports the umbrella header so the IDE can resolve symbols; it contains no runtime logic.

**`restart()`** exists because `esp_restart()`'s C declaration is `__attribute__((noreturn))`, but this Embedded Swift toolchain does not import that as a Swift `-> Never` return type (confirmed empirically — code calling raw `esp_restart()` followed by unreachable statements did not get flagged/optimized as such). `restart()` calls it and then traps in a `vTaskDelay`-based loop (not a busy `while true {}`) so callers get real `Never` typing without spinning the CPU while `esp_restart()`'s own deferred shutdown sequence runs.
