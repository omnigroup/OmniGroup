// Copyright 2007, 2013 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <AppKit/NSWindowController.h>

@class WebView;

@interface OAWebPageViewer : NSWindowController

+ (OAWebPageViewer *)sharedViewerNamed:(NSString *)name;

@property (nonatomic, retain) WebView *webView;
@property (nonatomic, assign) NSString *mediaStyle;

- (void)loadPath:(NSString *)path;
- (void)loadRequest:(NSURLRequest *)request;

@end
