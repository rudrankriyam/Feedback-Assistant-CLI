#ifndef XCFB_NATIVE_AUTOMATION_H
#define XCFB_NATIVE_AUTOMATION_H

#include <stdbool.h>

int XCFBFeedbackAssistantFill(
    const char *title,
    const char *description,
    const char *topic,
    const char *platform,
    const char *area,
    const char *kind,
    const char *snapshot,
    const char *bundleID,
    bool selectPopups,
    bool confirmSubmit,
    char **errorOut
);

void XCFBFeedbackAssistantFree(char *value);

#endif
