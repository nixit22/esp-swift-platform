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

import ESP_Platform

/// A Swift wrapper around FreeRTOS event groups.
///
/// This struct provides a type-safe interface to FreeRTOS event groups, allowing you to wait for and set event bits
/// using Swift `OptionSet` types. Event groups are useful for synchronizing tasks and handling asynchronous events.
///
/// `EventGroup` is noncopyable (`~Copyable`): the underlying handle is owned by exactly one value,
/// and the FreeRTOS event group is deleted automatically when the value goes out of scope.
///
/// Example usage:
/// ```swift
/// struct MyEvents: OptionSet {
///     let rawValue: UInt32
///     static let event1 = Self(rawValue: 1 << 0)
///     static let event2 = Self(rawValue: 1 << 1)
/// }
///
/// let eg = try EventGroup<MyEvents>()
/// eg.set(.event1)
/// let bits = eg.wait(.event1, timeoutMs: 1000)
/// ```
public struct EventGroup<EventBits>: ~Copyable where EventBits: OptionSet, EventBits.RawValue == UInt32 {
    /// The underlying FreeRTOS event group handle
    private let eventGroup: EventGroupHandle_t

    /// Creates a new event group.
    ///
    /// - Returns: An `EventGroup` instance if creation succeeds
    public init() throws(PlatformError) {
        guard let eventGroup = xEventGroupCreate() else {
            throw .freeRtosError(errCOULD_NOT_ALLOCATE_REQUIRED_MEMORY)
        }
        self.eventGroup = eventGroup
    }

    deinit {
        vEventGroupDelete(eventGroup)
    }

    /// Waits for any of the specified event bits to be set.
    ///
    /// This method blocks the current task until any of the specified event bits is set or the timeout expires.
    /// The matching bits are automatically cleared after being read.
    ///
    /// - Parameters:
    ///   - events: The event bits to wait for. Any one of them is sufficient to unblock.
    ///   - timeoutMs: The maximum time to wait in milliseconds. If `nil`, waits indefinitely.
    /// - Returns: The event bits that were set at the time of return.
    public borrowing func wait(_ events: EventBits..., timeoutMs: UInt32? = nil) -> EventBits {
        EventBits(
            rawValue: xEventGroupWaitBits(
                eventGroup, EventBits_t(events), pdTRUE, pdFALSE, TickType_t(ms: timeoutMs)))
    }

    /// Sets the specified event bits.
    ///
    /// This method can be called from tasks to set event bits, potentially unblocking waiting tasks.
    ///
    /// - Parameter events: The event bits to set.
    public borrowing func set(_ events: EventBits...) {
        xEventGroupSetBits(eventGroup, EventBits_t(events))
    }

    /// Creates an ISR handler that sets the specified event bits when called from an interrupt.
    ///
    /// Use this method to create a handler that can be installed in an ISR to set event bits without
    /// the restrictions of ISR-safe functions.
    ///
    /// - Important: The returned `IsrHandler` captures the raw `eventGroup` handle, not a reference
    ///   to `self`. The caller must ensure this `EventGroup` outlives both the `IsrHandler` and the
    ///   ISR registration that installs it — the handler does not keep the event group alive.
    /// - Parameter events: The event bits to set when the handler is called.
    /// - Returns: An `IsrHandler` instance that can be used to set the event bits from an ISR.
    public borrowing func isrHandler(setting events: EventBits...) -> IsrHandler {
        guard let args = eventGroupIsrArgsAllocate(eventGroup, EventBits_t(events)) else {
            fatalError("EventGroup ISR args allocation failed: out of memory")
        }
        return IsrHandler(handler: eventGroupIsrHandler, args: args)
    }
}

extension EventBits_t {
    fileprivate init<EventBits>(_ eventBits: [EventBits]) where EventBits: OptionSet, EventBits.RawValue == UInt32 {
        self = EventBits_t(eventBits.reduce(0) { $0 | $1.rawValue })
    }
}
