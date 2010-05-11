// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUISingleDocumentAppController.h>

#import <MobileCoreServices/MobileCoreServices.h>
#import <OmniFoundation/OFBundleRegistry.h>
#import <OmniFoundation/OFPreference.h>
#import <OmniUI/OUIDocument.h>
#import <OmniUI/OUIDocumentPicker.h>
#import <OmniUI/OUIDocumentProxy.h>
#import <OmniUI/OUIDocumentProxyView.h>
#import <OmniUI/OUIInspector.h>
#import <OmniUI/OUIToolbarViewController.h>

RCS_ID("$Id$");

static NSString * const OUINextLaunchActionDefaultsKey = @"OUINextLaunchAction";
static NSString * const OpenAction = @"open";
static NSString * const SelectAction = @"select";

@interface OUISingleDocumentAppController (/*Private*/)
- (void)_openDocument:(OUIDocumentProxy *)proxy;
- (void)_backgroundThread_openDocument:(OUIDocumentProxy *)proxy;
- (void)_mainThread_finishedLoadingDocument:(id)result;
- (void)_openDocument:(OUIDocumentProxy *)proxy animated:(BOOL)animated;
- (void)_closeDocument:(id)sender;
- (void)_undo:(id)sender;
- (void)_setupGesturesOnTitleTextField;
- (void)_proxyFinishedLoadingPreview:(NSNotification *)note;
@end

@implementation OUISingleDocumentAppController

+ (void)initialize;
{
#if 0 && defined(DEBUG) && OUI_GESTURE_RECOGNIZER_DEBUG
    [UIGestureRecognizer enableStateChangeLogging];
#endif
    
#if 0 && defined(DEBUG)
    sleep(3); // see the default image
#endif
    
    // Poke OFPreference to get default values registered
#ifdef DEBUG
    NSDictionary *defaults = [NSDictionary dictionaryWithObjectsAndKeys:
                              [NSNumber numberWithBool:YES], @"NSShowNonLocalizableStrings",
                              [NSNumber numberWithBool:YES], @"NSShowNonLocalizedStrings",
                              nil
                              ];
    [[NSUserDefaults standardUserDefaults] registerDefaults:defaults];
#endif
    [OFBundleRegistry registerKnownBundles];
    [OFPreference class];
}

- (void)dealloc;
{
    [_toolbarViewController release];
    [_document willClose];
    [_document release];
    [_window release];
    
    [_closeDocumentBarButtonItem release];
    [_infoBarButtonItem release];
    [_undoBarButtonItem release];
    [_documentTitleTextField release];
    [_documentTitleToolbarItem release];
    
    [super dealloc];
}

@synthesize window = _window;
@synthesize toolbarViewController = _toolbarViewController;
@synthesize appTitleToolbarItem = _appTitleToolbarItem;
@synthesize appTitleToolbarTextField = _appTitleToolbarTextField;
@synthesize documentTitleTextField = _documentTitleTextField;
@synthesize documentTitleToolbarItem = _documentTitleToolbarItem;

- (UIBarButtonItem *)closeDocumentBarButtonItem;
{
    if (!_closeDocumentBarButtonItem) {
        NSString *closeDocumentTitle = NSLocalizedStringWithDefaultValue(@"Documents <back button>", nil, OMNI_BUNDLE, @"Documents", @"Toolbar button title for returning to list of documents.");
        _closeDocumentBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:closeDocumentTitle
                                                                       style:UIBarButtonItemStyleBordered target:self action:@selector(_closeDocument:)];
    }
    return _closeDocumentBarButtonItem;
}

- (UIBarButtonItem *)infoBarButtonItem;
{
    if (!_infoBarButtonItem)
        _infoBarButtonItem = [[OUIInspector inspectorBarButtonItemWithTarget:self action:@selector(_showInspector:)] retain];
    return _infoBarButtonItem;
}

- (UIBarButtonItem *)undoBarButtonItem;
{
    if (!_undoBarButtonItem)
        _undoBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemUndo target:self action:@selector(_undo:)];
    return _undoBarButtonItem;
}

- (IBAction)makeNewDocument:(id)sender;
{
    [self.documentPicker newDocument:sender];
}

- (void)toggleFavorites:(id)sender;
{
    [self.documentPicker.previewScrollView snapToProxy:self.documentPicker.previewScrollView.lastProxy animated:NO];
}

- (NSString *)documentTypeForURL:(NSURL *)url;
{
    NSString *extension = [[url path] pathExtension];
    CFStringRef uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, (CFStringRef)extension, NULL/*conformingToUTI*/);
    OBASSERT(uti);
    OBASSERT([(NSString *)uti hasPrefix:@"dyn."] == NO); // should be registered
    
    return [NSMakeCollectable(uti) autorelease];
}

- (OUIDocument *)document;
{
    return _document;
}

- (void)_updateTitle;
{
    OUIDocumentPicker *picker = self.documentPicker;
    OUIDocumentProxy *proxy = picker.selectedProxy;
    
    NSString *title = NSLocalizedStringWithDefaultValue(@"Documents <main toolbar title>", @"OmniUI", OMNI_BUNDLE, @"Documents", @"Main toolbar title");
    NSArray *proxies = picker.previewScrollView.sortedProxies;
    NSUInteger proxyCount = [proxies count];
    
    if (!proxy || proxyCount < 2) {
        _appTitleToolbarTextField.text = title;
        return;
    }
    
    NSUInteger proxyIndex = [proxies indexOfObjectIdenticalTo:proxy];
    if (proxyIndex == NSNotFound) {
        OBASSERT_NOT_REACHED("Missing proxy");
        proxyIndex = 1; // less terrible.
    }
    
    NSString *counterFormat = NSLocalizedStringWithDefaultValue(@"%d of %d <document index", @"OmniUI", OMNI_BUNDLE, @"%@ (%d of %d)", @"format for showing the main title, document index and document count, in that order");
    title = [NSString stringWithFormat:counterFormat, title, proxyIndex + 1, proxyCount];
    
    _appTitleToolbarTextField.text = title;
}

- (void)documentPicker:(OUIDocumentPicker *)picker scannedProxies:(NSSet *)proxies;
{
    [self _updateTitle];
}

- (void)documentPicker:(OUIDocumentPicker *)picker didSelectProxy:(OUIDocumentProxy *)proxy;
{
    // Bail if we are in the middle of deleting a proxy; it is still animating out. Avoids a temporary counter change to an incorrect value
    if (proxy.layoutShouldAdvance == NO)
        return;
    [self _updateTitle];
}

#pragma mark -
#pragma mark OUIAppController subclass

- (UIViewController *)topViewController;
{
    return _toolbarViewController;
}

#pragma mark -
#pragma mark Subclass responsibility

- (Class)documentClassForURL:(NSURL *)url;
{
    OBRequestConcreteImplementation(self, _cmd);
}

- (UIView *)pickerAnimationViewForTarget:(OUIDocument *)document;
{
    OBRequestConcreteImplementation(self, _cmd);
}

- (NSArray *)toolbarItemsForDocument:(OUIDocument *)document;
{
    OBRequestConcreteImplementation(self, _cmd);
}

- (void)showInspectorFromBarButtonItem:(UIBarButtonItem *)item;
{
    OBRequestConcreteImplementation(self, _cmd);
}

- (void)dismissInspectorImmediately;
{
    OBRequestConcreteImplementation(self, _cmd);
}

#pragma mark -
#pragma mark UITextFieldDelegate

- (void)textFieldDidEndEditing:(UITextField *)textField;
{
    OBPRECONDITION(textField == _documentTitleTextField);
    
    // If we are new, there will be no proxy.
    NSString *originalName = [[[_document.url path] lastPathComponent] stringByDeletingPathExtension];
    NSString *newName = [textField text];
    if (!newName || [newName length] == 0) {
        textField.text = originalName;
        return;
    }
    
    if (![newName isEqualToString:originalName]) {
        OUIDocumentProxy *oldProxy = _document.proxy;
        OUIDocumentPicker *documentPicker = self.documentPicker;
        if (oldProxy) {
            NSString *documentType = [self documentTypeForURL:oldProxy.url];
            OUIDocumentProxy *newProxy = [documentPicker renameProxy:oldProxy toName:newName type:documentType];
            OBASSERT(newProxy);
            [_document setProxy:newProxy];
        } else {
            // new document does not have a proxy yet
            NSError *error = nil;
            NSString *documentType = [self documentPickerDocumentTypeForNewFiles:documentPicker];
            NSURL *safeURL = [documentPicker urlForNewDocumentWithName:newName ofType:documentType];
            BOOL success = [_document saveAsNewDocumentToURL:safeURL error:&error];
            if (!success) {
                NSLog(@"Error renaming unsaved document to %@: %@", [safeURL path], [error toPropertyList]);
            }
            [documentPicker rescanDocuments];
            
            NSString *safeName = [[[safeURL path] lastPathComponent] stringByDeletingPathExtension];
            textField.text = safeName;
        }
        
    }
    
    // UITextField adjusts its recognizers when it starts editing. Put ours back.
    [self _setupGesturesOnTitleTextField];
}

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string;
{
    OBPRECONDITION(textField == _documentTitleTextField);
    return YES;
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField;
{
    OBPRECONDITION(textField == _documentTitleTextField);
    
    if (_documentTitleTextField.isEditing)
        [_documentTitleTextField endEditing:YES];
    
    return YES;
}

#pragma mark -
#pragma mark UIApplicationDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions;
{
    
    [self _setupGesturesOnTitleTextField];
    
    OUIDocumentPicker *documentPicker = self.documentPicker;
    
    {
        NSMutableArray *toolbarItems = [NSMutableArray array];
        
        UIBarButtonItem *addItem = [[[UIBarButtonItem alloc] initWithTitle:NSLocalizedStringFromTableInBundle(@"New Document", @"OmniUI", OMNI_BUNDLE, @"Toolbar button for creating a new, empty document.")
                                                                     style:UIBarButtonItemStyleBordered
                                                                    target:self action:@selector(makeNewDocument:)] autorelease];
        [toolbarItems addObject:addItem];
        
        [toolbarItems addObject:[[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:NULL] autorelease]];
        
        [toolbarItems addObject:_appTitleToolbarItem];
        
        [toolbarItems addObject:[[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:NULL] autorelease]];
        
#if 0 // Punting on favorites for 1.0
        UIBarButtonItem *favoritesItem = [[[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"OUIToolbarFavoriteHollow.png"] style:UIBarButtonItemStyleBordered target:self action:@selector(toggleFavorites:)] autorelease];
        [toolbarItems addObject:favoritesItem];
        
        UISearchBar *searchBar = [[[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, 200, 20)] autorelease];
        UIBarButtonItem *searchItem = [[[UIBarButtonItem alloc] initWithCustomView:searchBar] autorelease];
        [toolbarItems addObject:searchItem];
#endif
        [toolbarItems addObject:self.appMenuBarItem];
        
        documentPicker.toolbarItems = [toolbarItems copy];
    }
    
    [OUIDocumentProxyView setPlaceholderPreviewImage:[UIImage imageNamed:@"DocumentPreviewPlaceholder.png"]];
    
    documentPicker.proxyTappedTarget = self;
    documentPicker.proxyTappedAction = @selector(_openDocument:);
    
    _toolbarViewController.resizesToAvoidKeyboard = YES;
    
    BOOL startedOpeningDocument = NO;
    OUIDocumentProxy *proxyToSelect = nil;
    
    NSURL *launchDocumentURL = [launchOptions objectForKey:UIApplicationLaunchOptionsURLKey];
    OUIDocumentProxy *launchDocumentProxy = [documentPicker proxyWithURL:launchDocumentURL];
    if (launchDocumentURL == nil && ![documentPicker hasDocuments]) {
        // Copy in a welcome document if one exists and we don't have any other documents
        [OUIDocumentPicker copySampleDocumentsToUserDocuments];
        [documentPicker rescanDocuments];
        OUIDocumentProxy *welcomeProxy = [documentPicker proxyNamed:@"Welcome"];
        if (welcomeProxy != nil) {
            [self _openDocument:welcomeProxy animated:NO];
            startedOpeningDocument = YES;
        }
    }
    
    if (launchDocumentProxy != nil) {
        [self _openDocument:launchDocumentProxy animated:NO];
        startedOpeningDocument = YES;
    } else {
        // Restore our selected or open document if we didn't get a command from on high.
        NSArray *launchAction = [[NSUserDefaults standardUserDefaults] objectForKey:OUINextLaunchActionDefaultsKey];
        
        if ([launchAction isKindOfClass:[NSArray class]] && [launchAction count] == 2) {
            OUIDocumentProxy *proxy = [documentPicker proxyWithURL:[NSURL URLWithString:[launchAction objectAtIndex:1]]];
            if (proxy) {
                [documentPicker scrollToProxy:proxy animated:NO];
                NSString *action = [launchAction objectAtIndex:0];
                if ([action isEqualToString:OpenAction]) {
                    [self _openDocument:proxy animated:NO];
                    startedOpeningDocument = YES;
                } else
                    proxyToSelect = proxy;
            }
        }
    }
    
#if 0 && defined(DEBUG_bungi)
    // open the first document
    [self _openDocument:documentPicker.previewScrollView.firstProxy animated:NO];
    
#if 0
    // select the object that has the inspector I want to test at the moment.
    CGPoint point = {180.703, 578.25};
    RSGraphElement *GE = [GRAPH_VIEW.editor.hitTester elementUnderPoint:point];
    //NSLog(@"GE = %@", GE);
    
    id hand = [GRAPH_VIEW valueForKey:@"_currentTool"];
    //NSLog(@"hand = %@", hand);
    
    // This doesn't add a selection view, but it makes it so the object is selected for the purposes of the inspector
    [hand setValue:GE forKeyPath:@"s.selection"];
    //NSLog(@"hand objects = %@", [hand valueForKey:@"affectedObjects"]);
    
    // bring up the inspector after giving things enough time to finish animating
    [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(_showInspector:) userInfo:nil repeats:NO];
#endif
#endif
    
    // Iff we didn't open a document, go to the document picker. We don't want to start loading of previews if the user is going directly to a document (particularly the welcome document).
    // Can't base this off whether innerViewController is set since it will always be nil here (since document loading happens in the background).
    OBASSERT(_toolbarViewController.innerViewController == nil);
    if (!startedOpeningDocument)
        _toolbarViewController.innerViewController = documentPicker;
    
    _toolbarViewController.view.frame = _window.screen.applicationFrame;
    [_window addSubview:_toolbarViewController.view];
    [_window makeKeyAndVisible];
    
    // Now that we are on screen, if we are waiting for a document to open, start the activity indicator in the middle of the hardboard
    if (startedOpeningDocument)
        [self showActivityIndicatorInView:_toolbarViewController.view];
    else {
        if (!proxyToSelect)
            proxyToSelect = documentPicker.previewScrollView.firstProxy;
        
        [documentPicker.previewScrollView layoutSubviews];
        [documentPicker.previewScrollView snapToProxy:proxyToSelect animated:NO];
    }
    
    return YES;
}

- (void)applicationWillTerminate:(UIApplication *)application;
{
    NSArray *nextLaunchAction = nil;
    
    [_window endEditing:YES];
    
    if (_document) {
        NSError *error = nil;
        if (![_document saveForClosing:&error])
            NSLog(@"Unable to save document %@ on application exit %@", _document.url, [error toPropertyList]);
        
        // Might be a newly created document that was never edited and trivially returns YES to saving. Make sure there is a proxy before overwriting our last default value.
        NSURL *url = _document.url;
        OUIDocumentProxy *proxy = [self.documentPicker proxyWithURL:url];
        if (proxy)
            nextLaunchAction = [NSArray arrayWithObjects:OpenAction, [url absoluteString], nil];
    } else {
        OUIDocumentProxy *proxy = self.documentPicker.selectedProxy;
        if (proxy)
            nextLaunchAction = [NSArray arrayWithObjects:SelectAction, [proxy.url absoluteString], nil];
    }
    
    if (nextLaunchAction)
        [[NSUserDefaults standardUserDefaults] setObject:nextLaunchAction forKey:OUINextLaunchActionDefaultsKey];
    
    [super applicationWillTerminate:application];
}

#pragma mark -
#pragma mark OUIDocumentPickerDelegate

- (id <OUIDocument>)createNewDocumentAtURL:(NSURL *)url error:(NSError **)outError;
{
    OBPRECONDITION(_document == nil);
    
    Class cls = [self documentClassForURL:url];
    OBASSERT(OBClassIsSubclassOfClass(cls, [OUIDocument class]));
    
    OUIDocument *document = [[[cls alloc] initEmptyDocumentToBeSavedToURL:url error:outError] autorelease];
    if (document == nil)
        return nil;
    
    // This positions the view controller's view as it will be and thus allows it to emit the right PDF.
    [_toolbarViewController willAnimateToInnerViewController:document.viewController];
    
    // We do go ahead and save the document immediately so that we can animate it into view most easily.
    if (![document saveAsNewDocumentToURL:url error:outError])
        return nil;
    
    return document;
}

#pragma mark -
#pragma mark Private

- (void)_openDocument:(OUIDocumentProxy *)proxy;
{
    // We will have already set _document and prepared for the animation in this case
    BOOL isOpeningNewDocument = [proxy.url isEqual:_document.url];
    
    if (isOpeningNewDocument) {
        _openAnimated = YES;
        [self _mainThread_finishedLoadingDocument:_document];
    } else
        [self _openDocument:proxy animated:YES];
}

- (void)_backgroundThread_openDocument:(OUIDocumentProxy *)proxy;
{
    OBPRECONDITION(![NSThread isMainThread]);
    
#if 0 && defined(DEBUG_bungi)
    sleep(4);
#endif
    
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    NSURL *url = proxy.url;
    OBASSERT(url);
    
    Class cls = [self documentClassForURL:url];
    OBASSERT(OBClassIsSubclassOfClass(cls, [OUIDocument class]));
    
    NSError *error = nil;
    OUIDocument *document = [[[cls alloc] initWithExistingDocumentProxy:proxy error:&error] autorelease];
    
    [self performSelectorOnMainThread:@selector(_mainThread_finishedLoadingDocument:) withObject:document ? (id)document : (id)error waitUntilDone:NO];
    
    [pool release];
}

- (void)_mainThread_finishedLoadingDocument:(id)result;
{
    if ([result isKindOfClass:[NSError class]]) {
        OUI_PRESENT_ERROR(result);
        _toolbarViewController.innerViewController = self.documentPicker;
        return;
    }
    
    if (_document != result) {
        [_document willClose];
        [_document release];
        _document = [result retain];
    }
    
    NSString *title = [[[_document.url path] lastPathComponent] stringByDeletingPathExtension];
    _documentTitleTextField.text = title;
    
    _document.viewController.toolbarItems = [self toolbarItemsForDocument:_document];
    [_document.viewController view]; // make sure the view is loaded in case -pickerAnimationViewForTarget: doesn't and return a subview thereof.
    
    if (_openAnimated) {
        OUIDocumentProxyView *proxyView = (OUIDocumentProxyView *)_document.proxy.view;
        UIView *documentView = [self pickerAnimationViewForTarget:_document];
        [_toolbarViewController setInnerViewController:_document.viewController animatingView:proxyView toView:documentView];
    } else {
        _toolbarViewController.innerViewController = _document.viewController;
        [self hideActivityIndicator]; // will be up for the initial app load
    }
}

- (void)_openDocument:(OUIDocumentProxy *)proxy animated:(BOOL)animated;
{
    OBPRECONDITION(proxy);
    
    _openAnimated = animated;
    if (_openAnimated)
        [_toolbarViewController willAnimateToInnerViewController:nil /*unknown*/];
    
    [_document willClose];
    [_document release];
    _document = nil;
    
    // Wrap up extra state more nicely?
    [NSThread detachNewThreadSelector:@selector(_backgroundThread_openDocument:) toTarget:self withObject:proxy];
}

- (void)_closeDocument:(id)sender;
{
    OBPRECONDITION(_document);
    
    if (!_document) {
        // Uh. Whatever.
        _toolbarViewController.innerViewController = self.documentPicker;
        return;
    }
    
    [_window endEditing:YES];
    
    // The inspector would animate closed and raise an exception, having detected it was getting deallocated while still visible (but animating away).
    [self dismissInspectorImmediately];
    
    // Start up the spinner and stop accepting events. We are NOT passing the picker here since that would add it to the view and lay it out. This is usually OK, but if we've rotated the device since opening, the picker layout would provoke the previews to load new previews (due to their size changing). Here we just want to start the spinner.
    [_toolbarViewController willAnimateToInnerViewController:nil];
    
    // Save the document. We don't currently do this in a background thread (letting the spinner go) since it draws a PDF preview. This uses the global UIKit graphics context stack and isn't thread-safe (only the raw CGContextRef stuff is).
    NSError *error = nil;
    if (![_document saveForClosing:&error])
        OUI_PRESENT_ERROR(error);
    
    // Now, start a rescan of the proxies
    OUIDocumentPicker *picker = self.documentPicker;
    NSURL *closingURL = [[_document.url copy] autorelease];
    [picker rescanDocumentsScrollingToURL:closingURL animated:NO];
    
    OUIDocumentProxy *proxy = [picker proxyWithURL:closingURL];
    
    if (proxy.isLoadingPreview) {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_proxyFinishedLoadingPreview:) name:OUIDocumentProxyPreviewDidLoadNotification object:proxy];
    } else {
        [self _proxyFinishedLoadingPreview:nil];
    }
}

- (void)_proxyFinishedLoadingPreview:(NSNotification *)note;
{
    OUIDocumentPicker *picker = self.documentPicker;
    
    [[NSNotificationCenter defaultCenter] removeObserver:self name:OUIDocumentProxyPreviewDidLoadNotification object:[note object]];
    
    UIView *documentView = [self pickerAnimationViewForTarget:_document];
    [_toolbarViewController setInnerViewController:self.documentPicker animatingView:documentView toView:picker.selectedProxy.view];
    
    [_document willClose];
    [_document release];
    _document = nil;
}

- (void)_showInspector:(id)sender;
{
    // We don't update the text editor editor live, so this is easiest for now.
    [_window endEditing:YES/*force*/];
    
    [self showInspectorFromBarButtonItem:_infoBarButtonItem];
}

- (void)_undo:(id)sender;
{
    [_document undo:sender];
}

- (void)_handleTitleTapGesture:(UIGestureRecognizer*)gestureRecognizer;
{
    // do not want an action here
    OBASSERT(gestureRecognizer.view == _documentTitleTextField);
}

- (void)_handleTitleDoubleTapGesture:(UIGestureRecognizer*)gestureRecognizer;
{
    OBASSERT(gestureRecognizer.view == _documentTitleTextField);
    [_documentTitleTextField becomeFirstResponder];
}

- (void)_setupGesturesOnTitleTextField;
{
    static UITapGestureRecognizer *titleTextFieldTap = nil;
    if (!titleTextFieldTap)
        titleTextFieldTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(_handleTitleTapGesture:)];
    
    static UITapGestureRecognizer *titleTextFieldDoubleTap = nil;
    if (!titleTextFieldDoubleTap) {
        titleTextFieldDoubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(_handleTitleDoubleTapGesture:)];
        titleTextFieldDoubleTap.numberOfTapsRequired = 2;
        
        [titleTextFieldTap requireGestureRecognizerToFail:titleTextFieldDoubleTap];
    }
    
    [_documentTitleTextField addGestureRecognizer:titleTextFieldTap];
    [_documentTitleTextField addGestureRecognizer:titleTextFieldDoubleTap];
}

@end
