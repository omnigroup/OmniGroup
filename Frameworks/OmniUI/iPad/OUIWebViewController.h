// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIViewController.h>

@interface OUIWebViewController : UIViewController <UIWebViewDelegate>
{
@private
    UIBarButtonItem *_backButton;
}

@property (retain) NSURL *URL;
@property (nonatomic, readonly, retain) UIWebView *webView;

- (void)loadData:(NSData *)data ofType:(NSString *)mimeType;

@end
