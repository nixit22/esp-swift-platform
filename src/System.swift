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

/// Restarts the device. Never returns.
///
/// `esp_restart()`'s C declaration (`esp_system.h`) is
/// `void esp_restart(void) __attribute__((__noreturn__))`, but this toolchain does not
/// import that attribute as a Swift `-> Never` return type — confirmed empirically, so
/// this wrapper traps in a delay loop after the call to give callers a real `Never`
/// (usable as the tail call of another `-> Never` function). The delay (rather than a
/// busy `while true {}`) avoids spinning the CPU while `esp_restart()`'s own shutdown
/// sequence (deferred via a task/timer) runs to completion.
public func restart() -> Never {
    esp_restart()
    while true { vTaskDelay(TickType_t(ms: 1_000)) }
}
