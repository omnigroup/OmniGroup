// Copyright 2007-2008, 2010-2011 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OSUMessageOfTheDay.h"

#import <WebKit/WebKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>
#import <OmniAppKit/OmniAppKit.h>

RCS_ID("$Id$")

@interface OSUMessageOfTheDay (FindControllerTarget) <OAFindControllerTarget>
@end

@implementation OSUMessageOfTheDay

+ (OSUMessageOfTheDay *)sharedMessageOfTheDay;
{
    static BOOL alreadyInitialized = NO;
    static OSUMessageOfTheDay *sharedMessageOfTheDay = nil;

    if (!alreadyInitialized) {
        sharedMessageOfTheDay = [[self alloc] init];
        alreadyInitialized = YES;
    }

    return sharedMessageOfTheDay;
}

- init;
{
    if (!(self = [super init]))
        return nil;

    _path = [[[NSBundle mainBundle] pathForResource:@"MessageOfTheDay" ofType:@"html"] copy];
    if (_path == nil) {
	[self release];
	return nil;
    }
    
    return self;
}

- (IBAction)showMessageOfTheDay:(id)sender;
{
    [self window];
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL fileURLWithPath:_path]];
    [[webView mainFrame] loadRequest:request];
    [self showWindow:nil];
}

- (void)checkMessageOfTheDay;
{
    NSData *motdData = [NSData dataWithContentsOfFile:_path];
    NSData *seenSignature = [[NSUserDefaults standardUserDefaults] objectForKey:@"MessageOfTheDaySignature"];
    if (motdData) {
	NSData *newSignature = [[[[OFSignature alloc] initWithData:motdData] autorelease] signatureData];
	if (OFNOTEQUAL(newSignature, seenSignature)) {
            NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	    [defaults setObject:newSignature forKey:@"MessageOfTheDaySignature"];

            // 10.5 9A410; the default policy guy has a zombie reference that gets hit sometimes.  Radar 5229858.  Setting our own policy doesn't help either.
            [defaults synchronize]; // in case WebKit is crashy, let's only crash once.
            
	    [self showMessageOfTheDay:nil];
	}
    }
}

#pragma mark -
#pragma mark NSWindowController subclass

- (void)windowDidLoad;
{
    [super windowDidLoad];
    
    // Allow @media {...} in the release notes to display differently when we are showing the content
    [webView setMediaStyle:@"release-notes"];
    
    NSWindow *window = [self window];
    [window setFrameAutosaveName:@"Message of the Day"];
    [window setTitle:NSLocalizedStringFromTableInBundle(@"Release Notes", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"Window title for the release notes window")];
}

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

- (void)webView:(WebView *)aWebView decidePolicyForNavigationAction:(NSDictionary *)actionInformation request:(NSURLRequest *)request frame:(WebFrame *)frame
decisionListener:(id<WebPolicyDecisionListener>)listener;
{
    NSURL *url = [actionInformation objectForKey:WebActionOriginalURLKey];
    
    // Initial content
    WebNavigationType webNavigationType = [[actionInformation objectForKey:WebActionNavigationTypeKey] intValue];
    if (webNavigationType == WebNavigationTypeOther ) {
        if ([self _urlIsFromAllowedBundle:url])
            [listener use];
        else {
            NSLog(@"Attempted to load from '%@', but this is URL is not within the app.", url);
            [listener ignore];
        }
        return;
    } else if (webNavigationType == WebNavigationTypeLinkClicked && [[actionInformation objectForKey:WebActionElementKey] objectForKey:WebElementLinkTargetFrameKey] == [webView mainFrame]) {
        if ([self _urlIsFromAllowedBundle:url]) {
            [listener use];
            return;
        }
    }
    
    // Open links in the user's browser
    [[NSWorkspace sharedWorkspace] openURL:url];
    [listener ignore];
}

@end

@implementation OSUMessageOfTheDay (FindControllerTarget)

// OAFindControllerTarget Protocol

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
        return [webView searchFor:[pattern findPattern] direction:!backwards caseSensitive:[pattern isCaseSensitive] wrap:wrap];
    else {
        NSString *foundString = [self _recursiveFindPattern:pattern inFrame:[webView mainFrame]];
        if (foundString)
            return [webView searchFor:foundString direction:!backwards caseSensitive:[pattern isCaseSensitive] wrap:wrap];
        else
            return NO;
    }
}

@end
