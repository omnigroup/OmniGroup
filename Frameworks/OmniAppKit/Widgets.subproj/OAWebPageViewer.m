// Copyright 2007-2008, 2010-2011, 2013 Omni Development, Inc.All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OAWebPageViewer.h"

#import <WebKit/WebKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>
#import <OmniAppKit/OmniAppKit.h>

RCS_ID("$Id$")

@interface OAWebPageViewer () <OAFindControllerTarget>
@property (nonatomic, copy) NSString *name;
@end

@implementation OAWebPageViewer

+ (OAWebPageViewer *)sharedViewerNamed:(NSString *)name;
{
    static NSMutableDictionary *cache = nil;

    if (name == nil)
        return nil;

    if (cache == nil)
        cache = [[NSMutableDictionary alloc] init];

    OAWebPageViewer *cachedViewer = cache[name];
    if (cachedViewer != nil)
        return cachedViewer;

    OAWebPageViewer *newViewer = [[self alloc] init];
    newViewer.name = name;
    cache[name] = newViewer;

    return [newViewer autorelease];
}

- (void)loadPath:(NSString *)path;
{
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL fileURLWithPath:path]];
    [self loadRequest:request];
}

- (void)loadRequest:(NSURLRequest *)request;
{
    NSWindow *window = [self window];

    if (_name != nil)
        [window setFrameAutosaveName:[NSString stringWithFormat:@"OAWebPageViewer:%@", _name]];

    [[_webView mainFrame] loadRequest:request];
    [self showWindow:nil];
}

#pragma mark -
#pragma mark NSWindowController subclass

- (NSString *)windowNibName;
{
    return NSStringFromClass([self class]);
}

- (id)owner;
{
    return self;
}

#pragma mark -
#pragma mark NSObject (OAFindControllerAware)

- (id <OAFindControllerTarget>)omniFindControllerTarget;
{
    return self;
}

#pragma mark -
#pragma mark NSObject (WebPolicyDelegate)

- (BOOL)_urlIsFromAllowedBundle:(NSURL *)url;
{
    NSString *path = nil;
    if ([url isFileURL])
        path = [[[url path] stringByStandardizingPath] stringByResolvingSymlinksInPath];
    
    if ([path hasPrefix:[[[[NSBundle mainBundle] bundlePath] stringByStandardizingPath] stringByResolvingSymlinksInPath]])
        return YES;
    else 
        return NO;
}

- (void)webView:(WebView *)aWebView decidePolicyForNavigationAction:(NSDictionary *)actionInformation request:(NSURLRequest *)request frame:(WebFrame *)frame decisionListener:(id<WebPolicyDecisionListener>)listener;
{
    NSURL *url = [actionInformation objectForKey:WebActionOriginalURLKey];
    
    // Initial content
    WebNavigationType webNavigationType = [[actionInformation objectForKey:WebActionNavigationTypeKey] intValue];
    if (webNavigationType == WebNavigationTypeOther ) {
        if ([self _urlIsFromAllowedBundle:url])
            [listener use];
        else {
            NSLog(@"Attempted to load from '%@', but this URL is not within the app.", url);
            [listener ignore];
        }
        return;
    } else if (webNavigationType == WebNavigationTypeLinkClicked && [[actionInformation objectForKey:WebActionElementKey] objectForKey:WebElementLinkTargetFrameKey] == [_webView mainFrame]) {
        if ([self _urlIsFromAllowedBundle:url]) {
            [listener use];
            return;
        }
    }
    
    // Open links in the user's browser
    [[NSWorkspace sharedWorkspace] openURL:url];
    [listener ignore];
}

#pragma mark - NSObject (WebFrameLoadDelegate)

- (void)webView:(WebView *)sender didReceiveTitle:(NSString *)title forFrame:(WebFrame *)frame;
{
    if (frame == [_webView mainFrame])
        [[self window] setTitle:title];
}

#pragma mark - OAFindControllerTarget Protocol

- (NSString *)_recursiveFindPattern:(id <OAFindPattern>)pattern inFrame:(WebFrame *)frame;
{
    //check myself for the string
    NSString *string = nil;
    if ([[[frame frameView] documentView] conformsToProtocol:@protocol(WebDocumentText)])
         string = [[(id <WebDocumentText>)[[frame frameView] documentView] attributedString] string];
    NSRange range = {0, 0};
    //walk the frame hierarchy grabbing source & searching for my string
#ifdef DEBUG_0
    NSLog(@"string: %@", string);
#endif
    if ([NSString isEmptyString:string])
        return nil;
    
    BOOL found = [pattern findInString:string foundRange:&range];      
    if (found)
        return [string substringWithRange:range];
    else {
        //otherwise search my children
        NSArray *children = [frame childFrames];
        NSUInteger childIndex, childCount = [children count];
        if (children != nil && childCount > 0) {
            NSString *foundString = nil;
            for (childIndex = 0; childIndex < childCount; childIndex++) {
                foundString = [self _recursiveFindPattern:pattern inFrame:[children objectAtIndex:childIndex]];
                if (foundString)
                    break;
            }
            return foundString;
        }
        return nil;
    }
}

- (BOOL)findPattern:(id <OAFindPattern>)pattern backwards:(BOOL)backwards wrap:(BOOL)wrap;
{
    if (![pattern isRegularExpression])
        return [_webView searchFor:[pattern findPattern] direction:!backwards caseSensitive:[pattern isCaseSensitive] wrap:wrap];
    else {
        NSString *foundString = [self _recursiveFindPattern:pattern inFrame:[_webView mainFrame]];
        if (foundString)
            return [_webView searchFor:foundString direction:!backwards caseSensitive:[pattern isCaseSensitive] wrap:wrap];
        else
            return NO;
    }
}

@end
