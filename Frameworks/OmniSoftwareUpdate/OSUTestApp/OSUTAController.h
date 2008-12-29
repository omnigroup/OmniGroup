// Copyright 2006 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniAppKit/OAController.h>

@class NSTextField, NSTextView, NSWindow;


@interface OSUTAController : OAController
{
    IBOutlet NSWindow *window;
    IBOutlet NSTextField *bundleIdentifierField;
    IBOutlet NSTextField *marketingVersionField;
    IBOutlet NSTextField *buildVersionField;
    IBOutlet NSTextField *systemVersionField;
    IBOutlet NSTextView *visibleTracksTextView;
}

@end

