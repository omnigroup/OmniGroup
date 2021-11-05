// Copyright 2007-2019, 2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OAWebPageViewer.h>

#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>
#import <OmniAppKit/OmniAppKit.h>
#import <WebKit/WebKit.h>

// <bug:///175663> (Frameworks-Mac Unassigned: Convert OAWebPageViewer to WKWebView)
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

@interface OAWebPageViewer () <OAFindControllerTarget, NSWindowDelegate, WebPolicyDelegate>
@property (nonatomic, copy) NSString *name;
@property (nonatomic, strong) NSView <WebDocumentView> *webDocumentView;
@property (nonatomic, copy) void (^loadCompletion)(BOOL success, NSURL *url, NSError *error);
@end

#pragma mark -

@implementation OAWebPageViewer
{
    BOOL _usesWebPageTitleForWindowTitle;
    NSMutableDictionary *_scriptObjects;
    BOOL _showWindowWhenNavigationCompletes;
}

static NSMutableDictionary *sharedViewerCache = nil;

+ (OAWebPageViewer *)sharedViewerNamed:(NSString *)name options:(OAWebPageViewerOptions)options;
{
    if (name == nil) {
        return nil;
    }

    if (sharedViewerCache == nil) {
        sharedViewerCache = [[NSMutableDictionary alloc] init];
    }

    OAWebPageViewer *cachedViewer = sharedViewerCache[name];
    if (cachedViewer != nil) {
        return cachedViewer;
    }

    OAWebPageViewer *newViewer = [[self alloc] init];
    newViewer.name = name;
    sharedViewerCache[name] = newViewer;
    
    // PlugIns are disabled by default. They can be turned on per instance if necessary.
    // (If PlugIns are enabled, Adobe Acrobat will interfere with displaying inline PDFs in our help content.)
    newViewer.plugInsEnabled = NO;
    
    newViewer.usesWebPageTitleForWindowTitle = YES;
    
    if ((options & OAWebPageViewerOptionsAuxilliaryWindow) != 0) {
        newViewer.window.collectionBehavior = (NSWindowCollectionBehaviorMoveToActiveSpace | NSWindowCollectionBehaviorFullScreenAuxiliary);
    }
    
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
        // This cleanup can mean we'll be deallocated. Don't let that happen while we're still poking our ivars <bug:///114229> (Unassigned: Crash closing the About panel or other OAWebPageViewer (Help, typically))
        OBRetainAutorelease(self);
        
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

    _showWindowWhenNavigationCompletes = YES;
    [[_webView mainFrame] loadRequest:request];
}

- (void)loadRequest:(NSURLRequest *)request onCompletion:(void (^)(BOOL success, NSURL *url, NSError *error))completionBlock;
{
    self.loadCompletion = completionBlock;
    [self loadRequest:request];
}

- (void)loadCachedHTML:(NSURL *)cachedFileURL forWebURL:(NSURL *)webURL;
{
    NSURL *baseURL = [[webURL URLByDeletingLastPathComponent] URLByDeletingLastPathComponent];
    NSString *htmlString = [NSString stringWithContentsOfURL:cachedFileURL encoding:kCFStringEncodingUTF8 error:nil];
    if (htmlString) {
        [[_webView mainFrame] loadHTMLString:htmlString baseURL:baseURL];
    } else {
        [self loadRequest:[NSURLRequest requestWithURL:webURL]];
    }
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

- (BOOL)webViewShouldUseLayer;
{
    return YES;
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
    _webView.preferences.loadsImagesAutomatically = YES;
    _webView.preferences.allowsAnimatedImages = YES;
    [_webView setMaintainsBackForwardList:NO];
}

- (void)windowWillClose:(NSNotification *)notification;
{
    @autoreleasepool {
        id<OAWebPageViewerDelegate> delegate = _delegate;
        if ([delegate respondsToSelector:@selector(viewer:windowWillClose:)]) {
            [delegate viewer:self windowWillClose:notification];
        }
        [self invalidate];
    }
}

#pragma mark -
#pragma mark NSObject (OAFindControllerAware)

- (nullable id <OAFindControllerTarget>)omniFindControllerTarget;
{
    return self;
}

#pragma mark -
#pragma mark NSObject (WebPolicyDelegate)

- (BOOL)_urlIsFromAllowedBundle:(NSURL *)url;
{
    if (OFISEQUAL(url.scheme, @"about") || OFISEQUAL(url.scheme, @"applewebdata") || OFISEQUAL(url.scheme, @"x-omnijs-documentation"))
        return YES;

    if ([url isFileURL]) {
        NSString *path = [[[url path] stringByStandardizingPath] stringByResolvingSymlinksInPath];
        
        if ([path hasPrefix:NSTemporaryDirectory()])
            return YES;
        return [path hasPrefix:[[[[NSBundle mainBundle] bundlePath] stringByStandardizingPath] stringByResolvingSymlinksInPath]];
    }

    return NO;
}

- (void)webView:(WebView *)aWebView decidePolicyForNavigationAction:(NSDictionary *)actionInformation request:(NSURLRequest *)request frame:(WebFrame *)frame decisionListener:(id<WebPolicyDecisionListener>)listener;
{
    NSURL *url = [actionInformation objectForKey:WebActionOriginalURLKey];
    if (OFISEQUAL(url.scheme, @"help")) {
        [[OAApplication sharedApplication] showHelpURL:[url resourceSpecifier]];
        [listener ignore];
        return;
    }
    
    if ([url.scheme hasPrefix:@"omni"]) {
        [[OAController sharedController] openURL:url];
        [listener ignore];
        return;
    }

    // News urls are not in our bundle, but we want to allow the web view to load.
    NSString *newsURLString = [[[OFPreferenceWrapper sharedPreferenceWrapper] preferenceForKey:@"OSUCurrentNewsURL"] stringValue];
    if (newsURLString) {
        if (OFISEQUAL(url.absoluteString, newsURLString)) {
            [listener use];
            return;
        }
    }
    
    // Cached news urls are in the user's Library folder
    NSURL *userLibrary = [[NSFileManager defaultManager] URLForDirectory:NSLibraryDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:NO error:nil];
    if ([[url path] hasPrefix:[userLibrary path]]) {
        [listener use];
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
    
#if MAC_APP_STORE_RETAIL_DEMO
    [OAController runFeatureNotEnabledAlertForWindow:self.window completion:nil];
#else
    // Open links in the user's browser
    [[OAController sharedController] openURL:url];
#endif
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
    _webDocumentView = webDocumentView;

    // See <bug:///108704> (Crasher: Yosemite: Crash using '?' to access help viewer a second time)
    // Allow overriding this to avoid  <bug:///146472> (Mac-OmniOutliner Bug: API Reference / Scripting Interface window is black and does not display text).
    _webDocumentView.wantsLayer = self.webViewShouldUseLayer;
}

- (void)webView:(WebView *)sender didFinishLoadForFrame:(WebFrame *)frame;
{
    if (frame == [sender mainFrame])
        self.webDocumentView = frame.frameView.documentView;

    [self _showWindowIfDeferred];
    [self _handleLoadCompletionWithSuccess:YES url:[[[frame provisionalDataSource] request] URL] error:nil];
}

- (void)_showWindowIfDeferred;
{
    if (!_showWindowWhenNavigationCompletes)
        return;
    _showWindowWhenNavigationCompletes = NO;
    [self showWindow:nil];
}

- (void)webView:(WebView *)sender didChangeLocationWithinPageForFrame:(WebFrame *)frame;
{
    // If the user clicks on a page that is already loaded, we want to show our window even though we didn't get a -webView:didFinishLoadForFrame: message.
    [self _showWindowIfDeferred];
}

- (void)webView:(WebView *)sender didFailLoadWithError:(NSError *)error forFrame:(WebFrame *)frame;
{
    NSLog(@"%@ [%@]: %@ (%@)", _name, [frame.dataSource.request.URL relativeString], [error localizedDescription], [error localizedRecoverySuggestion]);
    [self _handleLoadCompletionWithSuccess:NO url:[[[frame provisionalDataSource] request] URL] error:error];
    
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
    [self _handleLoadCompletionWithSuccess:NO url:[[dataSource initialRequest] URL] error:error];
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

- (void)_handleLoadCompletionWithSuccess:(BOOL)success url:(NSURL *)url error:(NSError *)error
{
    if (self.loadCompletion) {
        self.loadCompletion(success, url, error);
        if (success) {
            // nil out the completion handler so subsequent load attempts to incorrectly call.
            // we don't do this if we have not gotten success because it is possible to get an unsuccessful message followed by a successful one.
            self.loadCompletion = nil;
        }
    }

    id<OAWebPageViewerDelegate> delegate = _delegate;
    if (success && [delegate respondsToSelector:@selector(viewer:didLoadURL:)]) {
        [delegate viewer:self didLoadURL:url];
    }
}
@end


@interface OAWebPageContainerView : NSView
@end

@implementation OAWebPageContainerView

- (void)resizeSubviewsWithOldSize:(NSSize)oldSize {

    // <bug:///110229> (Unassigned: White line at top of Help window looks odd)
    // For some reason a 1-point-tall line would sometimes appear between the WebView and the window title bar. This makes sure that that won't happen.

    [super resizeSubviewsWithOldSize:oldSize];

    WebView *webview = self.subviews.firstObject;
    if (!NSEqualRects(webview.frame, self.bounds)) {
        webview.frame = self.bounds;
    }
}

@end
