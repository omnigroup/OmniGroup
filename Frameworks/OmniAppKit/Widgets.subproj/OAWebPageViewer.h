// Copyright 2007-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <AppKit/NSWindowController.h>

#import <OmniAppKit/OAWebPageViewerDelegate.h>
@class WebView;

@interface OAWebPageViewer : NSWindowController

+ (OAWebPageViewer *)sharedViewerNamed:(NSString *)name;

@property (nonatomic, strong) WebView *webView;

@property (nonatomic, copy) NSString *mediaStyle;
@property (nonatomic) BOOL plugInsEnabled; // Defaults to NO

@property (nonatomic) BOOL usesWebPageTitleForWindowTitle; // Defaults to YES

@property (nonatomic, weak) id <OAWebPageViewerDelegate> delegate;

- (void)setScriptObject:(id)scriptObject forWindowKey:(NSString *)key;
- (void)invalidate;

- (void)loadPath:(NSString *)path;
- (void)loadRequest:(NSURLRequest *)request;

/// on a successful load, success will be true, and error will be nil. If a failure, success will be false and error set. URL is set in all cases and points to the original request's url.
- (void)loadRequest:(NSURLRequest *)request onCompletion:(void (^)(BOOL success, NSURL *url, NSError *error))completionBlock;

@property(nonatomic,readonly) BOOL webViewShouldUseLayer;

@end
