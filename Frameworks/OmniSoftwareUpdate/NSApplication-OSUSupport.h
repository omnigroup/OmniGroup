// Copyright 2004-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <AppKit/NSApplication.h>
#import <AppKit/NSNibDeclarations.h> // For IBAction

@interface NSApplication (OSUSupport)
- (IBAction)checkForNewVersion:(id)sender;
@end


// hooks for an external class to provide UI for OmniSoftwareUpdate
@protocol OASoftwareUpdateUI
+ (void)checkSynchronouslyWithUIAttachedToWindow:(NSWindow *)aWindow;
    // Use aWindow if you want to present your UI as a sheet
@end

