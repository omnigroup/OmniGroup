// Copyright 2016-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#if OSU_FULL
#import <OmniSoftwareUpdate/NSApplication-OSUNewsSupport.h>
#import <OmniSoftwareUpdate/OSUChecker.h>
#else
#import <OmniSystemInfo/NSApplication-OSUNewsSupport.h>
#import <OmniSystemInfo/OSUChecker.h>
#endif

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <OmniAppKit/OAWebPageViewer.h>
#import <OmniBase/rcsid.h>
#import <OmniFoundation/NSString-OFSimpleMatching.h>

#import <WebKit/WebKit.h>

RCS_ID("$Id$");

@interface NSApplication (OSUNewsSupportInternal)
- (BOOL)replacement_validateMenuItem:(NSMenuItem *)menuItem;
@end

@implementation NSApplication (OSUNewsSupport)

static BOOL (*originalValidateMenuItem)(NSApplication *self, SEL _cmd, NSMenuItem *menuItem);

OBDidLoad(^{
    originalValidateMenuItem = (typeof(originalValidateMenuItem))OBReplaceMethodImplementationWithSelector([NSApplication class], @selector(validateMenuItem:), @selector(replacement_validateMenuItem:));
});

- (IBAction)showNews:(id)sender;
{
    NSURL *newsURL = [OSUChecker sharedUpdateChecker].currentNewsURL;
    OBASSERT(newsURL != nil);
    if (! newsURL) {
        // don't open to an empty URL.
        return;
    }
    
    OAWebPageViewer *webViewer = [OAWebPageViewer sharedViewerNamed:@"News"];
    
    // don't go fullscreen
    NSRect frame = [[webViewer window] frame];
    frame.size.width = 800;
    [[webViewer window] setFrame:frame display:NO];
    [[webViewer window] setMinSize:NSMakeSize(800, 400)];
    [[webViewer window] setMaxSize:NSMakeSize(800, FLT_MAX)];
    
    webViewer.usesWebPageTitleForWindowTitle = YES;
    webViewer.mediaStyle = @"release-notes";
    [webViewer loadRequest:[NSURLRequest requestWithURL:newsURL] onCompletion:^(BOOL success, NSURL *url, NSError *error) {
       if (success) {
           [OSUChecker sharedUpdateChecker].unreadNewsAvailable = NO;
       } else {
           
#if 0 && defined(DEUB_kilodelta)
           NSLog(@"failed to NEWS URL: %@", url);
#endif
           // include the newsURL as the baseURL so that the URL is considered "approved" by OAWebPageViewer. Otherwise, OAWebPageViewer won't be displayed.
           [webViewer.webView.mainFrame loadAlternateHTMLString:[self _displayableNewsHTMLForError:error] baseURL:nil forUnreachableURL:newsURL];
           [webViewer showWindow:nil];
        }
   }];
}

- (BOOL)replacement_validateMenuItem:(NSMenuItem *)menuItem
{
    // Validate the News menu item to only show when there is a currentNewsURL.
    if (menuItem.action == @selector(showNews:)) {
        NSString *newsURLString = [[[OSUChecker sharedUpdateChecker] currentNewsURL] absoluteString];
        if ([NSString isEmptyString:newsURLString]) {
            menuItem.hidden = YES;
            return NO;
        } else {
            menuItem.hidden = NO;
            return YES;
        }
    }
    
    return originalValidateMenuItem(self, _cmd, menuItem);
}

#pragma mark - Private

- (NSString *)_displayableNewsHTMLForError:(NSError *)error
{
    NSString *localizedTitle = NSLocalizedStringFromTableInBundle(@"News", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"News webpage title");
    NSString *localizedNewsErrorHeader = NSLocalizedStringFromTableInBundle(@"Cannot connect to News", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"News error header");

    NSError *noNewsError = nil;
    NSURL *noNewsURL = [OMNI_BUNDLE URLForResource:@"nonews" withExtension:@"html"];
    NSString *htmlString = [NSString stringWithContentsOfURL:noNewsURL encoding:NSUTF8StringEncoding error:&noNewsError];
    OBASSERT(noNewsError == nil);
    if (noNewsError) {
        // failed to load the nonews.html from the bundle for some reason.
        // return some kind of made up page that isn't pretty but will get the job done.
        return [NSString stringWithFormat:@"<title>%@</title>%@", localizedTitle, error.localizedDescription];
    }

    NSMutableString *html = [htmlString mutableCopy];
    NSRange range = [html rangeOfString:@"%news_title%"];
    if (range.location != NSNotFound) {
        [html replaceCharactersInRange:range withString:localizedTitle];
    }
    
    range = [html rangeOfString:@"%news_error_header%"];
    if (range.location != NSNotFound) {
        [html replaceCharactersInRange:range withString:localizedNewsErrorHeader];
    }

    range = [html rangeOfString:@"%news_error%"];
    if (range.location != NSNotFound) {
        [html replaceCharactersInRange:range withString:error.localizedDescription];
    }
    
    return html;
}
@end

