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

import Platform

private struct TestEvents: OptionSet {
    let rawValue: UInt32
    static let booted = Self(rawValue: 1 << 0)
}

private let mainTask = MainTask {
    let logger = Logger(tag: "esp-swift-platform-test")
    logger.i("esp-swift-platform test app booted")

    _ = TickType_t(ms: 10)
    // Two-catch workaround: a bare `catch` inside a closure literal can't infer EventGroup's
    // typed `throws(PlatformError)` (matches the same gap documented in matter-time-test's
    // CLAUDE.md) — this do-catch used to be inside a top-level function, where it inferred fine.
    do {
        let eventGroup = try EventGroup<TestEvents>()
        eventGroup.set(.booted)
        if eventGroup.wait(.booted, timeoutMs: 1).contains(.booted) {
            logger.i("Platform: EventGroup APIs compiled and linked successfully")
        } else {
            logger.e("Platform: EventGroup wait timed out — did not see the bit it just set")
        }
    } catch let error as PlatformError {
        logger.e("Platform: EventGroup setup failed: \(error.name)")
    } catch {
        logger.e("Platform: EventGroup setup failed: unknown error")
    }

    // mainTask referencing itself is safe here: this closure only runs via run(), called from
    // app_main() after the mainTask global has already finished initializing.
    let bootedNotifier = mainTask.notifier(TestEvents.booted)
    bootedNotifier()
    let notified: TestEvents = Platform.Task.waitNotification(timeoutMs: 1)
    if notified.contains(.booted) {
        logger.i("Platform: MainTask notifier()/waitNotification APIs compiled and linked successfully")
    } else {
        logger.e("Platform: MainTask notifier() round trip timed out")
    }

    // Task itself — the component's primary type — is otherwise untested above (mainTask covers
    // MainTask/TaskProtocol only). Round-trip a real cross-task notification: spawn a worker,
    // notify it, have it notify mainTask back, and wait for that echo.
    let worker = Task()
    do {
        try worker.run(name: "worker", stackSize: 2048, priority: 5) {
            let bits: TestEvents = Task.waitNotification(timeoutMs: 1000)
            if bits.contains(.booted) {
                mainTask.notify(TestEvents.booted)
            }
        }
        worker.notify(TestEvents.booted)
        let echoed: TestEvents = Platform.Task.waitNotification(timeoutMs: 1000)
        if echoed.contains(.booted) {
            logger.i("Platform: Task.run/notify cross-task round trip succeeded")
        } else {
            logger.e("Platform: Task.run/notify cross-task round trip timed out")
        }
    } catch let error as PlatformError {
        logger.e("Platform: Task.run failed: \(error.name)")
    } catch {
        logger.e("Platform: Task.run failed: unknown error")
    }

    // Not covered above: the no-arg notify()/notifier() path, the array-form overloads, and
    // notifyIsrHandler (which needs a real ISR source to test meaningfully, not available here).
    logger.i("All selected tests finished")
}

@_cdecl("app_main")
func app_main() {
    mainTask.run()
}
