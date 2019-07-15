// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <AppKit/NSAlert.h>

typedef void (^OAAlertSheetCompletionHandler)(NSModalResponse returnCode);

extern void OABeginAlertSheet(NSString *title, NSString *defaultButton, NSString *alternateButton, NSString *otherButton, NSWindow *docWindow, OAAlertSheetCompletionHandler completionHandler, NSString *msgFormat, ...) NS_FORMAT_FUNCTION(7,8);
