// Copyright 2014-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>

@class OAWebPageViewer;
@class NSDictionary;
@class NSMenuItem;

@protocol OAWebPageViewerDelegate <NSObject>

@optional
- (BOOL)viewer:(OAWebPageViewer *)viewer shouldDisplayContextMenuItem:(NSMenuItem *)menuItem forElement:(NSDictionary *)element;
- (void)viewer:(OAWebPageViewer *)viewer windowWillClose:(NSNotification *)notification;
- (void)viewer:(OAWebPageViewer *)viewer didLoadURL:(NSURL *)url;

@end
