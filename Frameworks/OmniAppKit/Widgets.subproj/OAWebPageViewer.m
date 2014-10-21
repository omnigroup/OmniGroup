// Copyright 2007-2008, 2010-2011, 2013-2014 Omni Development, Inc.All rights reserved.
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

@interface OAWebPageViewer () <OAFindControllerTarget, NSWindowDelegate> {
  @private
    BOOL _usesWebPageTitleForWindowTitle;
    NSMutableDictionary *_scriptObjects;
}

@property (nonatomic, copy) NSString *name;
@property (nonatomic, strong) NSView <WebDocumentView> *webDocumentView;

@end

#pragma mark -

@implementation OAWebPageViewer

static NSMutableDictionary *sharedViewerCache = nil;

+ (OAWebPageViewer *)sharedViewerNamed:(NSString *)name;
{
    if (name == nil)
        return nil;

    if (sharedViewerCache == nil)
        sharedViewerCache = [[NSMutableDictionary alloc] init];

    OAWebPageViewer *cachedViewer = sharedViewerCache[name];
    if (cachedViewer != nil)
        return cachedViewer;

    OAWebPageViewer *newViewer = [[self alloc] init];
    newViewer.name = name;
    sharedViewerCache[name] = newViewer;
    
    // PlugIns are disabled by default. They can be turned on per instance if necessary.
    // (If PlugIns are enabled, Adobe Acrobat will interfere with displaying inline PDFs in our help content.)
    newViewer.plugInsEnabled = NO;
    
    newViewer.usesWebPageTitleForWindowTitle = YES;

    return newViewer;
}

#pragma mark -
#pragma mark API

- (void)setScriptObject:(id)scriptObject forWindowKey:(NSString *)key;
{
    if (_scriptObjects == nil)
        _scriptObjects = [[NSMutableDictionary alloc] init];
    [_scriptObjects setObject:scriptObject forKey:key];
}

- (void)invalidate;
{
    @autoreleasepool {
        self.webDocumentView = nil;

        [_scriptObjects removeAllObjects];

        _webView.UIDelegate = nil;
        _webView.resourceLoadDelegate = nil;
        _webView.downloadDelegate = nil;
        _webView.frameLoadDelegate = nil;
        _webView.policyDelegate = nil;
        _webView.hostWindow = nil;

        [_webView close];
        [_webView removeFromSuperview];
        _webView = nil;
        
        if (_name != nil)
            [sharedViewerCache removeObjectForKey:_name];
    }
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
}

#pragma mark -
#pragma mark Accessors

- (NSString *)mediaStyle;
{
    [self _ensureWindowLoaded];
    return _webView.mediaStyle;
}

- (void)setMediaStyle:(NSString *)mediaStyle;
{
    [self _ensureWindowLoaded];
    _webView.mediaStyle = mediaStyle;
}

- (BOOL)plugInsEnabled;
{
    [self _ensureWindowLoaded];
    return [_webView.preferences arePlugInsEnabled];
}

- (void)setPlugInsEnabled:(BOOL)plugInsEnabled;
{
    [self _ensureWindowLoaded];
    [_webView.preferences setPlugInsEnabled:plugInsEnabled];
}

- (BOOL)usesWebPageTitleForWindowTitle;
{
    return _usesWebPageTitleForWindowTitle;
}

- (void)setUsesWebPageTitleForWindowTitle:(BOOL)flag;
{
    if (_usesWebPageTitleForWindowTitle != flag) {
        _usesWebPageTitleForWindowTitle = flag;
        
        if (_usesWebPageTitleForWindowTitle) {
            WebDataSource *dataSource = _webView.mainFrame.dataSource;
            NSString *pageTitle = dataSource.pageTitle;
            if (![NSString isEmptyString:pageTitle]) {
                self.window.title = pageTitle;
            }
        }
    }
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

- (void)windowDidLoad;
{
    [super windowDidLoad];
    
    OBASSERT(_webView != nil);
    _webView.layerUsesCoreImageFilters = YES;
    _webView.preferences.usesPageCache = NO;
    _webView.preferences.cacheModel = WebCacheModelDocumentBrowser;
    _webView.preferences.suppressesIncrementalRendering = YES;
    [_webView setMaintainsBackForwardList:NO];
}

- (void)windowWillClose:(NSNotification *)notification;
{
    @autoreleasepool {
        [self invalidate];
    }
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
    if (OFISEQUAL([url scheme], @"help")) {
        [NSApp showHelpURL:[url resourceSpecifier]];
        [listener ignore];
        return;
    }

    // Initial content
    WebNavigationType webNavigationType = [[actionInformation objectForKey:WebActionNavigationTypeKey] intValue];
    if (webNavigationType == WebNavigationTypeOther || webNavigationType == WebNavigationTypeReload) {
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
    [[OAController sharedController] openURL:url];
    [listener ignore];
}

#pragma mark - NSObject (WebFrameLoadDelegate)

- (void)webView:(WebView *)sender didReceiveTitle:(NSString *)title forFrame:(WebFrame *)frame;
{
    if (_usesWebPageTitleForWindowTitle && frame == [_webView mainFrame]) {
        [[self window] setTitle:title];
    }
}

- (void)setWebDocumentView:(NSView <WebDocumentView> *)webDocumentView;
{
    // This can't be good for scrolling performance, but we now watch for scroll notifications in the main frame and when scrolling happens we immediately perform layout and display on the main frame's document view.

    NSNotificationCenter *defaultCenter = [NSNotificationCenter defaultCenter];

    if (_webDocumentView != nil) {
        [defaultCenter removeObserver:self name:NSViewBoundsDidChangeNotification object:_webDocumentView];
        [_webDocumentView.superview setPostsBoundsChangedNotifications:NO];
    }

    _webDocumentView = webDocumentView;
    _webDocumentView.wantsLayer = YES;

    if (_webDocumentView != nil) {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_webDocumentScrolledNotification:) name:NSViewBoundsDidChangeNotification object:_webDocumentView.superview];
    }
}

- (void)webView:(WebView *)sender didFinishLoadForFrame:(WebFrame *)frame;
{
    if (frame == [sender mainFrame])
        self.webDocumentView = frame.frameView.documentView;

    [self _layoutDocumentView];
    [self showWindow:nil];
}

- (void)_layoutDocumentView;
{
    // We would call -setNeedsLayout: and -setNeedsDisplay:, but then layout won't actually happen immediately when the window is being scrolled in the background--which means our fixed CSS elements will wander out of place.
    [_webDocumentView layout];
    [_webDocumentView display];
}

- (void)_webDocumentScrolledNotification:(NSNotification *)note
{
    [self _layoutDocumentView];
}

- (void)webView:(WebView *)sender didChangeLocationWithinPageForFrame:(WebFrame *)frame;
{
    // If the user clicks on a page that is already loaded, we want to show our window even though we didn't get a -webView:didFinishLoadForFrame: message.
    [self _layoutDocumentView];
    [self showWindow:nil];
}

- (void)webView:(WebView *)sender didFailLoadWithError:(NSError *)error forFrame:(WebFrame *)frame;
{
    NSLog(@"%@ [%@]: %@ (%@)", _name, [frame.dataSource.request.URL relativeString], [error localizedDescription], [error localizedRecoverySuggestion]);
}

- (void)webView:(WebView *)sender didClearWindowObject:(WebScriptObject *)windowObject forFrame:(WebFrame *)frame
{
    for (NSString *key in [_scriptObjects keyEnumerator])
        [windowObject setValue:_scriptObjects[key] forKey:key];
}

#pragma mark - NSObject (WebResourceLoadDelegate)

- (void)webView:(WebView *)sender resource:(id)identifier didFailLoadingWithError:(NSError *)error fromDataSource:(WebDataSource *)dataSource
{
    NSLog(@"%@: error=%@", _name, error);
}

#pragma mark - NSObject (WebUIDelegate)

- (void)webView:(WebView *)sender setResizable:(BOOL)resizable;
{
    NSLog(@"%@ [%@]: setResizable:%@", _name, [sender.mainFrame.dataSource.request.URL relativeString], resizable ? @"YES" : @"NO");
}

- (void)webView:(WebView *)sender setFrame:(NSRect)frame;
{
    NSLog(@"%@ [%@]: setFrame:%@", _name, [sender.mainFrame.dataSource.request.URL relativeString], NSStringFromRect(frame));
}

- (void)webView:(WebView *)sender runJavaScriptAlertPanelWithMessage:(NSString *)message initiatedByFrame:(WebFrame *)frame;
{
    NSLog(@"%@ [%@]: %@", _name, [frame.dataSource.request.URL relativeString], message);
}

- (NSArray *)webView:(WebView *)sender contextMenuItemsForElement:(NSDictionary *)element defaultMenuItems:(NSArray *)defaultMenuItems;
{
    if (![self.delegate respondsToSelector:@selector(viewer:shouldDisplayContextMenuItem:forElement:)]) {
        return defaultMenuItems;
    }
    
    return [defaultMenuItems filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id evaluatedObject, NSDictionary *bindings) {
        OBPRECONDITION([evaluatedObject isKindOfClass:[NSMenuItem class]]);
        return [self.delegate viewer:self shouldDisplayContextMenuItem:evaluatedObject forElement:element];
    }]];
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

#pragma mark -
#pragma mark Private

- (void)_ensureWindowLoaded;
{
    (void)[self window];
}

@end
