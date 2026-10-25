// Copyright (c) 2026 Nicolas Christe
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

private let log = Logger(tag: "Task")

/// Common interface for anything that wraps a FreeRTOS task handle and can be notified —
/// `Task` (a task this component created via `run()`) and `MainTask` (ESP-IDF's own "main"
/// task, which this component never creates but still needs to notify).
///
/// Only the two members below are actual requirements — each is the single point where a
/// conformer must touch its own private task handle. Every typed, public-facing overload
/// (`notify()`, the `OptionSet` overloads, `notifier()`, the typed `notifyIsrHandler` overloads)
/// is a shared default implementation in the extension below, built on top of these two.
///
public protocol TaskProtocol: AnyObject {
    /// Sets the given raw FreeRTOS notification bits on this task (OR'd in), waking it if it's
    /// blocked in `Task.waitNotification()`.
    func notify(_ events: UInt32)

    /// Registers an ISR-safe notification target for the given raw bits. See the typed
    /// `notifyIsrHandler(_:)` overloads below for the public entry points.
    func notifyIsrHandler(_ events: UInt32) -> IsrHandler
}

extension TaskProtocol {
    /// Wakes this task with an empty notification (no bits set) — a plain "wake up now" signal
    /// for callers that don't need to distinguish which event occurred.
    public func notify() {
        notify(0)
    }

    /// Wakes this task, OR-ing in the raw values of every bit in `notificationBits`.
    public func notify<NotificationBits>(_ notificationBits: [NotificationBits])
    where NotificationBits: OptionSet, NotificationBits.RawValue == UInt32 {
        notify(notificationBits.reduce(0) { $0 | $1.rawValue })
    }

    /// Variadic form of `notify(_:[NotificationBits])`.
    public func notify<NotificationBits>(_ notificationBits: NotificationBits...)
    where NotificationBits: OptionSet, NotificationBits.RawValue == UInt32 {
        notify(notificationBits)
    }

    /// Returns a callable that wakes this task with a plain "wake up now" notification (no
    /// bits) whenever it's invoked — for handing to code that shouldn't hold a full `Task`/
    /// `MainTask` reference, just permission to notify it.
    public func notifier() -> TaskNotifier {
        TaskNotifier(task: self)
    }

    /// Registers an ISR-safe notification target for a plain "wake up now" notification (no
    /// bits set). See `notifyIsrHandler(_:UInt32)` for the underlying mechanism and its
    /// lifetime caveat.
    public func notifyIsrHandler() -> IsrHandler {
        notifyIsrHandler(0)
    }

    /// Returns a callable that wakes this task with `notificationBits` set whenever it's invoked.
    public func notifier<NotificationBits>(_ notificationBits: [NotificationBits]) -> TaskEventsNotifier
    where NotificationBits: OptionSet, NotificationBits.RawValue == UInt32 {
        TaskEventsNotifier(task: self, notificationBits: notificationBits)
    }

    /// Variadic form of `notifier(_:[NotificationBits])`.
    public func notifier<NotificationBits>(_ notificationBits: NotificationBits...) -> TaskEventsNotifier
    where NotificationBits: OptionSet, NotificationBits.RawValue == UInt32 {
        notifier(notificationBits)
    }

    /// Registers an ISR-safe notification target that sets every bit in `notificationBits` when
    /// triggered from interrupt context. See `notifyIsrHandler(_:UInt32)` for the underlying
    /// mechanism and its lifetime caveat.
    public func notifyIsrHandler<NotificationBits>(_ notificationBits: [NotificationBits]) -> IsrHandler
    where NotificationBits: OptionSet, NotificationBits.RawValue == UInt32 {
        notifyIsrHandler(notificationBits.reduce(0) { $0 | $1.rawValue })
    }

    /// Variadic form of `notifyIsrHandler(_:[NotificationBits])`.
    public func notifyIsrHandler<NotificationBits>(_ notificationBits: NotificationBits...) -> IsrHandler
    where NotificationBits: OptionSet, NotificationBits.RawValue == UInt32 {
        notifyIsrHandler(notificationBits)
    }
}

/// A callable that wakes a fixed target task with a plain "wake up now" notification. Bind it
/// once via `task.notifier()` and hand it to code that shouldn't hold a full task reference.
public struct TaskNotifier {
    private let task: TaskProtocol

    /// - Parameter task: The task this notifier will wake when invoked.
    public init(task: TaskProtocol) {
        self.task = task
    }

    /// Wakes the bound task.
    public func callAsFunction() {
        task.notify()
    }
}

/// A callable that wakes a fixed target task with a fixed set of notification bits. Bind it once
/// via `task.notifier(_:)` and hand it to code that shouldn't hold a full task reference.
public struct TaskEventsNotifier {
    private let task: TaskProtocol
    private let notificationBits: UInt32

    /// - Parameters:
    ///   - task: The task this notifier will wake when invoked.
    ///   - notificationBits: The bits (OR'd together) to set on every invocation.
    public init<NotificationBits>(task: TaskProtocol, notificationBits: [NotificationBits])
    where NotificationBits: OptionSet, NotificationBits.RawValue == UInt32 {
        self.task = task
        self.notificationBits = notificationBits.reduce(0) { $0 | $1.rawValue }
    }

    /// Wakes the bound task with the bound bits.
    public func callAsFunction() {
        task.notify(notificationBits)
    }
}

public final class Task: TaskProtocol {
    private var entry: (() -> Void)?

    /// The FreeRTOS task handle, set after calling `run()`
    private var handle: TaskHandle_t?

    /// Creates an unstarted task. `handle` stays nil — and every `notify`/`notifier` call a
    /// silent no-op — until `run()` succeeds.
    public init() {
    }

    /// Spawns a new FreeRTOS task running `entry`, via `xTaskCreate`. The task deletes itself
    /// (`vTaskDelete`) when `entry` returns.
    ///
    /// - Parameters:
    ///   - name: FreeRTOS task name, used in diagnostics (e.g. `uxTaskGetSystemState`) and logs.
    ///   - stackSize: Stack size in bytes.
    ///   - priority: FreeRTOS task priority.
    ///   - entry: The task's body. Runs until it returns; the task cannot be restarted afterward.
    public func run(name: String, stackSize: UInt32, priority: UInt32, entry: @escaping () -> Void) throws(PlatformError) {
        self.entry = entry
        // Not a data race despite `handle` being written here (creator thread) and
        // nil'd below (new task's thread): xTaskCreate writes `*pxCreatedTask`
        // inside prvInitialiseNewTask, which always completes *before*
        // prvAddNewTaskToReadyList runs — and that function gates task visibility
        // behind taskENTER_CRITICAL()/taskEXIT_CRITICAL() (a real SMP spinlock
        // barrier). The new task cannot be scheduled on any core, and therefore
        // cannot reach the `task.handle = nil` below, until after that barrier
        // publishes this write. Verified against FreeRTOS-Kernel-SMP/tasks.c
        // (xTaskCreate -> prvCreateTask -> prvAddNewTaskToReadyList).
        let ptr = Unmanaged.passRetained(self).toOpaque()
        try xTaskCreate(
            {
                // Convert the raw pointer to a managed Swift reference and
                // ensure it is released before deleting the FreeRTOS task.
                do {
                    let task = Unmanaged<Task>.fromOpaque($0!).takeRetainedValue()
                    task.entry?()
                    task.handle = nil
                }
                // Drop to here so `task` is released by ARC, then delete the RTOS task.
                vTaskDelete(nil)
            }, name, stackSize, ptr, priority, &handle)
            .throwFreeRtosError { rc in
                // xTaskCreate failed before the task ever started, so the entry
                // closure's takeRetainedValue() never ran to balance passRetained
                // above — release manually or `self` leaks forever.
                log.e("xTaskCreate(\(name)) failed: \(rc)")
                Unmanaged<Task>.fromOpaque(ptr).release()
            }
    }

    /// Blocks the **calling** task (not any particular `Task` object) until it has a pending
    /// notification, returning the accumulated raw bits and clearing them. `nil` blocks forever.
    ///
    /// - Parameter timeoutMs: Maximum time to wait, or `nil` to wait forever.
    /// - Returns: The raw notification value, or `0` on timeout.
    @discardableResult
    public static func waitNotification(timeoutMs: UInt32? = nil) -> UInt32 {
        ulTaskGenericNotifyTake(0, 1, TickType_t(ms: timeoutMs))
    }

    /// Typed form of `waitNotification(timeoutMs:)` — blocks the calling task until it has a
    /// pending notification, returning it decoded as `NotificationBits` and clearing all bits.
    ///
    /// - Parameter timeoutMs: Maximum time to wait, or `nil` to wait forever.
    /// - Returns: The notification bits set since the last wait, or an empty set on timeout.
    @discardableResult
    public static func waitNotification<NotificationBits>(timeoutMs: UInt32? = nil) -> NotificationBits
    where NotificationBits: OptionSet, NotificationBits.RawValue == UInt32 {
        var notifyValue: UInt32 = 0
        xTaskGenericNotifyWait(0, 0, 0xFFFF_FFFF, &notifyValue, TickType_t(ms: timeoutMs))
        return NotificationBits(rawValue: notifyValue)
    }

    /// `TaskProtocol` witness — see its doc comment. No-ops if `run()` hasn't succeeded yet.
    public func notify(_ events: UInt32) {
        guard let handle else { return }
        xTaskGenericNotify(handle, 0, events, eSetBits, nil)
    }

    /// - Important: The returned `IsrHandler` captures the raw FreeRTOS task handle, not a reference
    ///   to `self`. The caller must ensure this `Task` outlives both the `IsrHandler` and the ISR
    ///   registration that installs it — the handler does not keep the task alive.
    public func notifyIsrHandler(_ events: UInt32) -> IsrHandler {
        guard let handle else {
            fatalError("Task must be run before calling notifyIsrHandler")
        }
        guard let args = taskNotifyIsrArgsAllocate(handle, events, eSetBits) else {
            fatalError("Task notify ISR args allocation failed: out of memory")
        }
        return IsrHandler(handler: taskNotifyIsrHandler, args: args)
    }
}

/// Wraps ESP-IDF's own "main" task — the one that calls `app_main()` — as a `TaskProtocol`, so
/// the app body can hand out notifiers targeting it to other components, the same way any task
/// created via `Task.run()` can.
///
/// Intended usage is a single global, with `app_main()` reduced to a one-line shim:
/// ```swift
/// private let mainTask = MainTask {
///     // app body — may reference `mainTask` itself to build notifiers for other components
/// }
///
/// @_cdecl("app_main")
/// func app_main() { mainTask.run() }
/// ```
public final class MainTask: TaskProtocol {
    /// Non-optional, unlike `Task.handle`: this is captured once, unconditionally, in `init` —
    /// there's no equivalent of `Task`'s pre-`run()` window where a nil handle is a valid,
    /// silently-ignorable state. If `xTaskGetCurrentTaskHandle()` ever failed, silently
    /// swallowing every future `notify()` would be the worst failure shape for the type meant to
    /// wake the app's own loop — better to trap loudly at boot.
    private let handle: TaskHandle_t
    private let body: () -> Void

    /// - Parameter body: The app's entry-point logic. Not run until `run()` is called — this
    ///   keeps a top-level `let mainTask = MainTask { ... }`'s lazy global initializer fast and
    ///   non-blocking, even though `body` itself is expected to never return.
    public init(_ body: @escaping () -> Void) {
        self.handle = xTaskGetCurrentTaskHandle()
        self.body = body
    }

    /// Runs the app body. Must be called from the same task that constructed this `MainTask` —
    /// `handle` was captured via `xTaskGetCurrentTaskHandle()` in `init`, which snapshots
    /// whichever task calls it.
    public func run() {
        body()
    }

    /// `TaskProtocol` witness — see its doc comment. Unlike `Task.notify(_:)`, there's no nil
    /// handle to guard against: `handle` is always set by the time this can be called.
    public func notify(_ events: UInt32) {
        xTaskGenericNotify(handle, 0, events, eSetBits, nil)
    }

    /// `TaskProtocol` witness — see its doc comment, and `Task.notifyIsrHandler(_:)`'s note about
    /// the returned handler capturing the raw task handle, not `self`.
    public func notifyIsrHandler(_ events: UInt32) -> IsrHandler {
        guard let args = taskNotifyIsrArgsAllocate(handle, events, eSetBits) else {
            fatalError("Task notify ISR args allocation failed: out of memory")
        }
        return IsrHandler(handler: taskNotifyIsrHandler, args: args)
    }
}
