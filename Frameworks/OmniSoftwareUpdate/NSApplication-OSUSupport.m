// Copyright 2003-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniSoftwareUpdate/NSApplication-OSUSupport.h>

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <OmniBase/rcsid.h>

#import <OmniSoftwareUpdate/OSUController.h>

RCS_ID("$Id$");

@implementation NSApplication (OSUSupport)

// Check for new version of this application on Omni's web site. Triggered by direct user action.
- (IBAction)checkForNewVersion:(id)sender;
{
    [[OSUController class] checkSynchronouslyWithUIAttachedToWindow:nil];
}

@end

