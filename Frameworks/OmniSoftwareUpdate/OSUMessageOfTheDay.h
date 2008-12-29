// Copyright 2007 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniSoftwareUpdate/OSUMessageOfTheDay.h 94355 2007-11-09 21:51:45Z kc $

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
