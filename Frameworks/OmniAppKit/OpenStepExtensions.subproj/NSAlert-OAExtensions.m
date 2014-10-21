// Copyright 1997-2009, 2013-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/NSAlert-OAExtensions.h>

RCS_ID("$Id$")

void OABeginAlertSheet(NSString *title, NSString *defaultButton, NSString *alternateButton, NSString *otherButton, NSWindow *docWindow, OAAlertSheetCompletionHandler completionHandler, NSString *msgFormat, ...)
{
    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    alert.messageText = title;
    
    if (msgFormat) {
        va_list args;
        va_start(args, msgFormat);
        NSString *informationalText = [[NSString alloc] initWithFormat:msgFormat arguments:args];
        va_end(args);
        
        alert.informativeText = informationalText;
        [informationalText release];
    }
    
    if (defaultButton)
        [alert addButtonWithTitle:defaultButton];
    if (alternateButton)
        [alert addButtonWithTitle:alternateButton];
    if (otherButton)
        [alert addButtonWithTitle:otherButton];
    
    [alert beginSheetModalForWindow:docWindow completionHandler:completionHandler];
}
