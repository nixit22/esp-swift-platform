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

#include "event_group.h"
#include <esp_attr.h>
#include <esp_heap_caps.h>

typedef struct EventGroupIsrArg_t
{
    EventGroupHandle_t eventGroup;
    EventBits_t bitsToSet;
} EventGroupIsrArg_t;

void *eventGroupIsrArgsAllocate(EventGroupHandle_t eventGroup, uint32_t bitsToSet)
{
    EventGroupIsrArg_t *args = (EventGroupIsrArg_t *)heap_caps_malloc(sizeof(EventGroupIsrArg_t), MALLOC_CAP_INTERNAL);
    if (args == NULL)
    {
        return NULL;
    }
    args->eventGroup = eventGroup;
    args->bitsToSet = bitsToSet;
    return args;
}

void IRAM_ATTR eventGroupIsrHandler(void *arg)
{
    EventGroupIsrArg_t *eventGroup = (EventGroupIsrArg_t *)arg;
    BaseType_t xHigherPriorityTaskWoken, xResult;
    xHigherPriorityTaskWoken = pdFALSE;
    xResult = xEventGroupSetBitsFromISR(eventGroup->eventGroup, eventGroup->bitsToSet, &xHigherPriorityTaskWoken);
    if (xResult != pdFAIL)
    {
        portYIELD_FROM_ISR(xHigherPriorityTaskWoken);
    }
}
