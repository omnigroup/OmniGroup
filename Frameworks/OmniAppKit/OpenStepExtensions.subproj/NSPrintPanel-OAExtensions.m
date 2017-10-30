// Copyright 2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.


// <bug:///143999> (Mac-OmniOutliner Crasher: Crash printing to PDF and overwriting existing PDF [radar])
// <bug:///137497> (Mac-OmniGraffle Crasher: [radar] [7.5] -[NSPrintPanel _sheet:didEndWithResult:contextInfo:] (in AppKit) "NSRunAlertPanel may not be invoked inside of transaction commit")
// With gratitude to frank.illenberger and https://openradar.appspot.com/30674481

#import "NSPrintPanel-OAExtensions.h"

// $Id$

static id (*originalBeginSheetWithPrintInfo)(NSPrintPanel *self, SEL _cmd, NSPrintInfo *printInfo, NSWindow *window, id delegate, SEL didEndSelector, void *contextInfo) = NULL;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wundeclared-selector"

OBPerformPosing(^{
    if ([OFVersionNumber isOperatingSystemSierraWithTouchBarOrLater] && ![OFVersionNumber isOperatingSystemHighSierraOrLater]) {
        originalBeginSheetWithPrintInfo = (typeof(originalBeginSheetWithPrintInfo))OBReplaceMethodImplementationWithSelector([NSPrintPanel class], @selector(beginSheetWithPrintInfo:modalForWindow:delegate:didEndSelector:contextInfo:), @selector(replacement_beginSheetWithPrintInfo:modalForWindow:delegate:didEndSelector:contextInfo:));
    }
});
#pragma clang diagnostic pop

@implementation NSPrintPanel (OAExtensions)

- (void)replacement_beginSheetWithPrintInfo:(NSPrintInfo *)printInfo modalForWindow:(NSWindow *)docWindow delegate:(nullable id)delegate didEndSelector:(nullable SEL)didEndSelector contextInfo:(nullable void *)contextInfo
{
    NSInvocation *invocation = nil;
    if (delegate != nil && didEndSelector != NULL) {
        invocation = [NSInvocation invocationWithMethodSignature:[delegate methodSignatureForSelector:didEndSelector]];
        invocation.target = delegate;
        invocation.selector = didEndSelector;
        NSPrintPanel *printPanel = self;
        [invocation setArgument:&printPanel atIndex:2];
        [invocation setArgument:&contextInfo atIndex:4];
        OBStrongRetain(invocation);
    }

    originalBeginSheetWithPrintInfo(self, _cmd, printInfo, docWindow, self, @selector(omni_printPanelDidEnd:returnCode:contextInfo:), (__bridge void *)invocation);
}

- (void)omni_printPanelDidEnd:(NSPrintPanel *)printPanel returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo
{
    NSInvocation *invocation = (__bridge NSInvocation *)contextInfo;
    [invocation setArgument:&returnCode atIndex:3];

    // Defer the invocation by one run-loop cycle.
    [invocation performSelector:@selector(invoke) withObject:nil afterDelay:0.0];
    OBStrongRelease(invocation);
}

@end
