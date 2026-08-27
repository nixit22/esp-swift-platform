/*
 * Copyright (c) 2026 Nicolas Christe
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

import ESP_Platform

public enum PlatformError: Swift.Error {
    case espError(esp_err_t)
    case freeRtosError(Int32)
}

extension PlatformError {
    public var name: String {
        switch self {
        case .espError(let code):
            if let cString = esp_err_to_name(code) {
                return String(cString: cString)
            } else {
                return "Unknown ESP error code \(code)"
            }
        case .freeRtosError(let code):
            return "FreeRTOS error code \(code)"
        }
    }
}

extension esp_err_t {
    public var name: String {
        if let cString = esp_err_to_name(self) {
            return String(cString: cString)
        } else {
            return "Unknown ESP error code \(self)"
        }
    }

    public func throwEspError(_ cb: ((esp_err_t) -> Void)? = nil) throws(PlatformError) {
        if self != ESP_OK {
            cb?(self)
            throw PlatformError.espError(self)
        }
    }

    public func abortOnError(_ cb: ((esp_err_t) -> Void)? = nil) {
        if self != ESP_OK {
            cb?(self)
            fatalError()
        }
    }
}

extension BaseType_t {
    public func throwFreeRtosError(_ cb: ((BaseType_t) -> Void)? = nil) throws(PlatformError) {
        if self != pdPASS {
            cb?(self)
            throw PlatformError.freeRtosError(self)
        }
    }
}
