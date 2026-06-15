#import "XCFBNativeAutomation.h"

#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>

static NSString *RFAString(const char *value) {
    if (value == NULL) { return @""; }
    return [NSString stringWithUTF8String:value] ?: @"";
}

static int RFAFail(char **errorOut, NSString *message) {
    if (errorOut != NULL) {
        *errorOut = strdup(message.UTF8String);
    }
    return 1;
}

void XCFBFeedbackAssistantFree(char *value) {
    free(value);
}

static NSString *RFAAttributeString(AXUIElementRef element, CFStringRef attribute) {
    CFTypeRef value = NULL;
    if (AXUIElementCopyAttributeValue(element, attribute, &value) != kAXErrorSuccess || value == NULL) {
        return @"";
    }
    NSString *result;
    if (CFGetTypeID(value) == CFStringGetTypeID()) {
        result = [(__bridge NSString *)value copy];
    } else {
        result = [NSString stringWithFormat:@"%@", value];
    }
    CFRelease(value);
    return result ?: @"";
}

static CFArrayRef RFACopyElementArray(AXUIElementRef element, CFStringRef attribute) {
    CFTypeRef value = NULL;
    if (AXUIElementCopyAttributeValue(element, attribute, &value) != kAXErrorSuccess || value == NULL) {
        return NULL;
    }
    if (CFGetTypeID(value) != CFArrayGetTypeID()) {
        CFRelease(value);
        return NULL;
    }
    return (CFArrayRef)value;
}

static BOOL RFAMatchesString(NSString *candidate, NSString *wanted) {
    if (candidate.length == 0 || wanted.length == 0) { return NO; }
    return [candidate isEqualToString:wanted]
        || [candidate hasPrefix:wanted]
        || [candidate rangeOfString:wanted options:NSCaseInsensitiveSearch].location != NSNotFound;
}

static BOOL RFAMatches(AXUIElementRef element, NSString *wanted) {
    return RFAMatchesString(RFAAttributeString(element, kAXTitleAttribute), wanted)
        || RFAMatchesString(RFAAttributeString(element, kAXDescriptionAttribute), wanted)
        || RFAMatchesString(RFAAttributeString(element, kAXValueAttribute), wanted)
        || RFAMatchesString(RFAAttributeString(element, kAXIdentifierAttribute), wanted);
}

static NSString *RFARole(AXUIElementRef element) {
    return RFAAttributeString(element, kAXRoleAttribute);
}

static BOOL RFAIsTextInput(AXUIElementRef element) {
    NSString *role = RFARole(element);
    return [role isEqualToString:NSAccessibilityTextFieldRole] || [role isEqualToString:NSAccessibilityTextAreaRole];
}

static AXUIElementRef RFAFindDescendantWithDepth(AXUIElementRef root, NSInteger depth, BOOL (^predicate)(AXUIElementRef element)) {
    if (root == NULL || depth < 0) { return NULL; }

    CFStringRef attributes[] = { kAXChildrenAttribute, kAXRowsAttribute, kAXVisibleChildrenAttribute, CFSTR("AXSheets") };
    for (NSUInteger attributeIndex = 0; attributeIndex < 4; attributeIndex++) {
        CFArrayRef children = RFACopyElementArray(root, attributes[attributeIndex]);
        if (children == NULL) { continue; }
        CFIndex count = CFArrayGetCount(children);
        for (CFIndex index = 0; index < count; index++) {
            AXUIElementRef child = (AXUIElementRef)CFArrayGetValueAtIndex(children, index);
            if (child != NULL && predicate(child)) {
                CFRetain(child);
                CFRelease(children);
                return child;
            }
            AXUIElementRef found = RFAFindDescendantWithDepth(child, depth - 1, predicate);
            if (found != NULL) {
                CFRelease(children);
                return found;
            }
        }
        CFRelease(children);
    }
    return NULL;
}

static AXUIElementRef RFAFindDescendant(AXUIElementRef root, BOOL (^predicate)(AXUIElementRef element)) {
    return RFAFindDescendantWithDepth(root, 12, predicate);
}

static AXUIElementRef RFAFirstWindow(AXUIElementRef app) {
    CFArrayRef windows = RFACopyElementArray(app, kAXWindowsAttribute);
    if (windows == NULL || CFArrayGetCount(windows) == 0) {
        if (windows != NULL) { CFRelease(windows); }
        return NULL;
    }
    AXUIElementRef window = (AXUIElementRef)CFArrayGetValueAtIndex(windows, 0);
    if (window != NULL) { CFRetain(window); }
    CFRelease(windows);
    return window;
}

static AXUIElementRef RFACopyAncestorWindow(AXUIElementRef element) {
    if (element == NULL) { return NULL; }
    AXUIElementRef current = element;
    CFRetain(current);
    for (NSInteger depth = 0; depth < 16 && current != NULL; depth++) {
        if ([RFARole(current) isEqualToString:NSAccessibilityWindowRole]) {
            return current;
        }

        CFTypeRef parent = NULL;
        AXError error = AXUIElementCopyAttributeValue(current, kAXParentAttribute, &parent);
        CFRelease(current);
        if (error != kAXErrorSuccess || parent == NULL) {
            return NULL;
        }
        current = (AXUIElementRef)parent;
    }
    if (current != NULL) { CFRelease(current); }
    return NULL;
}

static AXUIElementRef RFAFindWindow(AXUIElementRef app, BOOL (^predicate)(AXUIElementRef window)) {
    CFArrayRef windows = RFACopyElementArray(app, kAXWindowsAttribute);
    if (windows == NULL) { return NULL; }
    AXUIElementRef result = NULL;
    CFIndex count = CFArrayGetCount(windows);
    for (CFIndex index = 0; index < count; index++) {
        AXUIElementRef window = (AXUIElementRef)CFArrayGetValueAtIndex(windows, index);
        if (window != NULL && predicate(window)) {
            result = window;
            CFRetain(result);
            break;
        }
    }
    CFRelease(windows);
    return result;
}

static BOOL RFAPress(AXUIElementRef element);

static AXUIElementRef RFAFindButton(AXUIElementRef root, NSString *name) {
    return RFAFindDescendant(root, ^BOOL(AXUIElementRef element) {
        return [RFARole(element) isEqualToString:NSAccessibilityButtonRole] && RFAMatches(element, name);
    });
}

static BOOL RFAPress(AXUIElementRef element) {
    return AXUIElementPerformAction(element, kAXPressAction) == kAXErrorSuccess;
}

static BOOL RFAPerformActionOnly(AXUIElementRef element, CFStringRef action) {
    return element != NULL && AXUIElementPerformAction(element, action) == kAXErrorSuccess;
}

static int RFASetText(AXUIElementRef root, NSString *label, NSString *value, char **errorOut) {
    AXUIElementRef input = RFAFindDescendant(root, ^BOOL(AXUIElementRef element) {
        return RFAIsTextInput(element) && RFAMatches(element, label);
    });
    if (input == NULL) {
        return RFAFail(errorOut, [NSString stringWithFormat:@"Could not find text input: %@", label]);
    }

    AXError setError = AXUIElementSetAttributeValue(input, kAXValueAttribute, (__bridge CFStringRef)value);
    if (setError != kAXErrorSuccess) {
        CFRelease(input);
        return RFAFail(errorOut, [NSString stringWithFormat:@"Could not passively set text input %@: %d", label, setError]);
    }
    if (![RFAAttributeString(input, kAXValueAttribute) isEqualToString:value]) {
        CFRelease(input);
        return RFAFail(errorOut, [NSString stringWithFormat:@"Text input did not passively commit value for %@", label]);
    }
    CFRelease(input);
    return 0;
}

static int RFASelectPopup(
    AXUIElementRef app,
    AXUIElementRef window,
    NSArray<NSString *> *labels,
    NSString *value,
    char **errorOut
) {
    if (value.length == 0) {
        return RFAFail(errorOut, [NSString stringWithFormat:@"No value provided for popup: %@", [labels componentsJoinedByString:@" / "]]);
    }

    AXUIElementRef popup = RFAFindDescendant(window, ^BOOL(AXUIElementRef element) {
        if (![RFARole(element) isEqualToString:NSAccessibilityPopUpButtonRole]) { return NO; }
        for (NSString *label in labels) {
            if (RFAMatches(element, label)) { return YES; }
        }
        return NO;
    });
    if (popup == NULL) {
        return RFAFail(errorOut, [NSString stringWithFormat:@"Could not find popup: %@", [labels componentsJoinedByString:@" / "]]);
    }

    if ([RFAAttributeString(popup, kAXValueAttribute) caseInsensitiveCompare:value] == NSOrderedSame) {
        CFRelease(popup);
        return 0;
    }

    AXUIElementSetAttributeValue(popup, kAXValueAttribute, (__bridge CFStringRef)value);
    [NSThread sleepForTimeInterval:0.25];
    if ([RFAAttributeString(popup, kAXValueAttribute) rangeOfString:value options:NSCaseInsensitiveSearch].location != NSNotFound) {
        CFRelease(popup);
        return 0;
    }

    if (!RFAPress(popup)) {
        CFRelease(popup);
        return RFAFail(errorOut, [NSString stringWithFormat:@"Could not open popup: %@", [labels componentsJoinedByString:@" / "]]);
    }

    AXUIElementRef menuItem = NULL;
    for (NSInteger attempt = 0; attempt < 20 && menuItem == NULL; attempt++) {
        menuItem = RFAFindDescendant(app, ^BOOL(AXUIElementRef element) {
            return [RFARole(element) isEqualToString:NSAccessibilityMenuItemRole]
                && [RFAAttributeString(element, kAXTitleAttribute) caseInsensitiveCompare:value] == NSOrderedSame;
        });
        if (menuItem == NULL) { [NSThread sleepForTimeInterval:0.1]; }
    }

    if (menuItem == NULL || !RFAPress(menuItem)) {
        if (menuItem != NULL) { CFRelease(menuItem); }
        CFRelease(popup);
        return RFAFail(errorOut, [NSString stringWithFormat:@"Could not select popup value '%@' for %@", value, [labels componentsJoinedByString:@" / "]]);
    }
    CFRelease(menuItem);

    for (NSInteger attempt = 0; attempt < 20; attempt++) {
        if ([RFAAttributeString(popup, kAXValueAttribute) caseInsensitiveCompare:value] == NSOrderedSame) {
            CFRelease(popup);
            return 0;
        }
        [NSThread sleepForTimeInterval:0.1];
    }

    CFRelease(popup);
    return RFAFail(errorOut, [NSString stringWithFormat:@"Popup did not commit value '%@' for %@", value, [labels componentsJoinedByString:@" / "]]);
}

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
) {
    if (!AXIsProcessTrusted()) {
        return RFAFail(errorOut, @"Accessibility permission is required for native form filling");
    }

    NSArray<NSRunningApplication *> *apps = [NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.apple.appleseed.FeedbackAssistant"];
    NSRunningApplication *runningApp = apps.firstObject;
    if (runningApp == nil) {
        return RFAFail(errorOut, @"Feedback Assistant is not running");
    }
    AXUIElementRef app = AXUIElementCreateApplication(runningApp.processIdentifier);

    AXUIElementRef chooseTopicWindow = NULL;
    for (NSInteger attempt = 0; attempt < 32 && chooseTopicWindow == NULL; attempt++) {
        chooseTopicWindow = RFAFindWindow(app, ^BOOL(AXUIElementRef window) {
            return RFAMatches(window, @"Choose Topic");
        });
        if (chooseTopicWindow == NULL) { [NSThread sleepForTimeInterval:0.25]; }
    }

    if (chooseTopicWindow != NULL) {
        NSString *topicString = RFAString(topic);
        AXUIElementRef row = RFAFindDescendant(chooseTopicWindow, ^BOOL(AXUIElementRef element) {
            if (![RFARole(element) isEqualToString:NSAccessibilityRowRole]) { return NO; }
            return RFAFindDescendant(element, ^BOOL(AXUIElementRef child) { return RFAMatches(child, topicString); }) != NULL;
        });
        if (row == NULL) {
            CFRelease(app);
            return RFAFail(errorOut, [NSString stringWithFormat:@"Could not find topic: %@", topicString]);
        }
        AXUIElementSetAttributeValue(row, kAXSelectedAttribute, kCFBooleanTrue);
        AXUIElementRef continueButton = RFAFindButton(chooseTopicWindow, @"Continue");
        if (continueButton == NULL || !RFAPress(continueButton)) {
            CFRelease(app);
            return RFAFail(errorOut, @"Could not press Continue");
        }
    }

    AXUIElementRef titleInput = NULL;
    for (NSInteger attempt = 0; attempt < 48 && titleInput == NULL; attempt++) {
        titleInput = RFAFindDescendant(app, ^BOOL(AXUIElementRef element) {
            return RFAIsTextInput(element) && RFAMatches(element, @"Please provide a descriptive title for your feedback:");
        });
        if (titleInput == NULL) { [NSThread sleepForTimeInterval:0.25]; }
    }
    if (titleInput == NULL) {
        CFRelease(app);
        return RFAFail(errorOut, @"Timed out waiting for Feedback Assistant form");
    }

    AXUIElementRef window = RFACopyAncestorWindow(titleInput);
    CFRelease(titleInput);
    if (window == NULL) { window = RFAFirstWindow(app); }
    if (window == NULL) { window = app; CFRetain(window); }
    int result = RFASetText(window, @"Please provide a descriptive title for your feedback:", RFAString(title), errorOut);
    if (result != 0) { CFRelease(app); return result; }
    result = RFASetText(window, @"Please describe the issue and what steps we can take to reproduce it", RFAString(description), errorOut);
    if (result != 0) { CFRelease(app); return result; }

    NSString *bundleString = RFAString(bundleID);
    if (bundleString.length > 0) {
        RFASetText(window, @"Please provide the bundleId or appAppleId of your app:", bundleString, NULL);
    }

    if (selectPopups) {
        [runningApp unhide];
        [runningApp activateWithOptions:NSApplicationActivateAllWindows];
        [NSThread sleepForTimeInterval:0.25];

        NSString *platformString = RFAString(platform);
        if (platformString.length > 0) {
            result = RFASelectPopup(
                app,
                window,
                @[@"Which platform is most relevant for your report?"],
                platformString,
                errorOut
            );
            if (result != 0) { CFRelease(app); return result; }
        }
        result = RFASelectPopup(
            app,
            window,
            @[@"Which technology does your report involve?", @"Which area are you seeing an issue with?"],
            RFAString(area),
            errorOut
        );
        if (result != 0) { CFRelease(app); return result; }
        result = RFASelectPopup(
            app,
            window,
            @[@"What type of feedback are you reporting?", @"What type of issue are you reporting?"],
            RFAString(kind),
            errorOut
        );
        if (result != 0) { CFRelease(app); return result; }
    }

    if (confirmSubmit) {
        AXUIElementRef submitButton = RFAFindButton(window, @"Submit");
        if (submitButton == NULL || !RFAPress(submitButton)) {
            CFRelease(app);
            return RFAFail(errorOut, @"Could not find or press Submit button");
        }
    }

    CFRelease(window);
    CFRelease(app);
    return 0;
}
