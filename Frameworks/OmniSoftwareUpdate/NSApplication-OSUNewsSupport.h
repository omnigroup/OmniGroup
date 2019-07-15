// Copyright 2016-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <AppKit/NSApplication.h>
#import <AppKit/NSNibDeclarations.h> // For IBAction

@interface NSApplication (OSUNewsSupport)
- (IBAction)showNews:(id)sender;
@end

extern NSNotificationName const OSUDidShowNewsNotifiation;

