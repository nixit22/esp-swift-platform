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

/// Utilities for working with RTOS tick counts.
///
/// The initializer below converts an optional millisecond value into a
/// `TickType_t` (RTOS ticks). Passing `nil` yields `portMAX_DELAY`.
extension TickType_t {
    /// The current RTOS tick count.
    ///
    /// - Note: Call from ISR context via ``nowFromISR`` instead — this wraps
    ///   `xTaskGetTickCount()`, which is not ISR-safe.
    public static var now: TickType_t {
        xTaskGetTickCount()
    }

    /// The current RTOS tick count, safe to call from ISR context.
    public static var nowFromISR: TickType_t {
        xTaskGetTickCountFromISR()
    }

    /// Create a `TickType_t` from an optional millisecond duration.
    ///
    /// - Parameter ms: Milliseconds to convert. Use `nil` for an indefinite delay.
    /// - Note: `nil` maps to `portMAX_DELAY`.
    public init(ms: UInt32?) {
        if let ms {
            // Equivalent to pdMS_TO_TICKS, done here instead of via a C shim
            // because pdMS_TO_TICKS is function-like (can't bridge into Swift)
            // while configTICK_RATE_HZ is a plain constant (can). pdMS_TO_TICKS
            // itself multiplies in TickType_t (uint32_t on this port) before
            // dividing and silently wraps for large ms.
            //
            // configTICK_RATE_HZ is fixed for the process lifetime (an IDF
            // Kconfig value baked in at build time), so this branch always
            // resolves the same way and the compiler folds it accordingly.
            let hz = UInt32(configTICK_RATE_HZ)
            if 1000 % hz == 0 {
                // Tick period is a whole number of ms: exact conversion, no
                // multiply, safe across the full UInt32 ms range.
                self = ms / (1000 / hz)
            } else {
                // hz doesn't divide 1000 evenly: this branch is compiled out
                // entirely for hz values that do (confirmed in the emitted
                // RISC-V for this project's configTICK_RATE_HZ=100), so there's
                // no cost to keeping it simple here — multiply in UInt64 and
                // saturate instead of wrapping.
                let ticks = (UInt64(ms) * UInt64(hz)) / 1000
                self = TickType_t(Swift.min(ticks, UInt64(TickType_t.max)))
            }
        } else {
            self = portMAX_DELAY
        }
    }
}
