##
## Copyright (c) 2026 Nicolas Christe
##
## Permission is hereby granted, free of charge, to any person obtaining a copy
## of this software and associated documentation files (the "Software"), to deal
## in the Software without restriction, including without limitation the rights
## to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
## copies of the Software, and to permit persons to whom the Software is
## furnished to do so, subject to the following conditions:
##
## The above copyright notice and this permission notice shall be included in all
## copies or substantial portions of the Software.
##
## THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
## IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
## FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
## AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
## LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
## OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
## SOFTWARE.
##

idf_component_register(
    SRCS
        src/error.c
        src/Error.swift
        src/log.c
        src/Logger.swift
        src/TickType.swift
        src/event_group.c
        src/EventGroup.swift
        src/task.c
        src/Task.swift
        src/platform.c
        src/IsrHandler.swift

    PRIV_INCLUDE_DIRS "src"
    PRIV_REQUIRES esp-swift-support
)

swift_configure(
    MODULE_NAME Platform
)

# Export Swift-accessible logging defines derived from sdkconfig's
# CONFIG_LOG_MAXIMUM_LEVEL. We export per-level Swift compile-time
# flags (mapping: ERROR=1, WARN=2, INFO=3, DEBUG=4, VERBOSE=5) as
# `LOG_<LEVEL>_ENABLED` defines usable from Swift with
# `#if LOG_INFO_ENABLED` or similar.
if(DEFINED CONFIG_LOG_MAXIMUM_LEVEL)
    # Per-level boolean defines (mapping: ERROR=1, WARN=2, INFO=3, DEBUG=4, VERBOSE=5)
    if(CONFIG_LOG_MAXIMUM_LEVEL GREATER_EQUAL 1)
        target_compile_options(${COMPONENT_LIB} PRIVATE "$<$<COMPILE_LANGUAGE:Swift>:-DLOG_ERROR_ENABLED>")
    endif()
    if(CONFIG_LOG_MAXIMUM_LEVEL GREATER_EQUAL 2)
        target_compile_options(${COMPONENT_LIB} PRIVATE "$<$<COMPILE_LANGUAGE:Swift>:-DLOG_WARN_ENABLED>")
    endif()
    if(CONFIG_LOG_MAXIMUM_LEVEL GREATER_EQUAL 3)
        target_compile_options(${COMPONENT_LIB} PRIVATE "$<$<COMPILE_LANGUAGE:Swift>:-DLOG_INFO_ENABLED>")
    endif()
    if(CONFIG_LOG_MAXIMUM_LEVEL GREATER_EQUAL 4)
        target_compile_options(${COMPONENT_LIB} PRIVATE "$<$<COMPILE_LANGUAGE:Swift>:-DLOG_DEBUG_ENABLED>")
    endif()
    if(CONFIG_LOG_MAXIMUM_LEVEL GREATER_EQUAL 5)
        target_compile_options(${COMPONENT_LIB} PRIVATE "$<$<COMPILE_LANGUAGE:Swift>:-DLOG_VERBOSE_ENABLED>")
    endif()
endif()
