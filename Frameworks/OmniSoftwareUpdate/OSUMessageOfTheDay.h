// Copyright 2007 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <AppKit/NSWindowController.h>

@class WebView;

@interface OSUMessageOfTheDay : NSWindowController
{
    IBOutlet WebView *webView;
    
    NSString *_path;
}

+ (OSUMessageOfTheDay *)sharedMessageOfTheDay;

- (IBAction)showMessageOfTheDay:(id)sender;

- (void)checkMessageOfTheDay;
    // This will display the message of the day if it has changed since the last time it was displayed.

@end
