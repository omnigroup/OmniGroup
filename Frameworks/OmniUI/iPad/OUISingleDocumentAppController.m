// Copyright 2010-2011 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUISingleDocumentAppController.h>

#import <MobileCoreServices/MobileCoreServices.h>
#import <OmniFoundation/OFBundleRegistry.h>
#import <OmniFoundation/OFPreference.h>
#import <OmniUI/OUIBarButtonItem.h>
#import <OmniUI/OUIDocument.h>
#import <OmniUI/OUIDocumentPicker.h>
#import <OmniUI/OUIDocumentProxy.h>
#import <OmniUI/OUIDocumentProxyView.h>
#import <OmniUI/OUIInspector.h>
#import <OmniUI/OUIToolbarViewController.h>
#import <OmniBase/OmniBase.h>
#import <OmniFileStore/OFSFileManager.h>
#import <OmniFileStore/OFSFileInfo.h>
#import <OmniUI/UIView-OUIExtensions.h>

#import "OUIToolbarViewController-Internal.h"

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
- (void)_setupGesturesOnTitleTextField;
- (void)_proxyFinishedLoadingPreview:(OUIDocumentProxy *)proxy;
- (void)_proxyFinishedLoadingPreviewNotification:(NSNotification *)note;
@end

@interface OUIToolbarTitleButton : UIButton
{
    BOOL _touchesInside;
    UIImageView *_highlightView;
}

@end

@implementation OUISingleDocumentAppController

+ (void)initialize;
{
    OBINITIALIZE;

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
    
    OBASSERT(_undoBarButtonItem.undoManager == nil);
    _undoBarButtonItem.undoBarButtonItemTarget = nil;
    [_undoBarButtonItem release];
    
    [_documentTitleTextField release];
    [_documentTitleToolbarItem release];
    
    [super dealloc];
}

@synthesize window = _window;
@synthesize toolbarViewController = _toolbarViewController;
@synthesize appTitleToolbarButton = _appTitleToolbarButton;
@synthesize documentTitleTextField = _documentTitleTextField;
@synthesize documentTitleToolbarItem = _documentTitleToolbarItem;

- (OUIBarButtonItem *)closeDocumentBarButtonItem;
{
    if (!_closeDocumentBarButtonItem) {
        NSString *closeDocumentTitle = NSLocalizedStringWithDefaultValue(@"Documents <back button>", @"OmniUI", OMNI_BUNDLE, @"Documents", @"Toolbar button title for returning to list of documents.");
        _closeDocumentBarButtonItem = [[OUIBarButtonItem alloc] initWithTitle:closeDocumentTitle
                                                                        style:UIBarButtonItemStyleBordered target:self action:@selector(_closeDocument:)];
    }
    return _closeDocumentBarButtonItem;
}

- (OUIBarButtonItem *)infoBarButtonItem;
{
    if (!_infoBarButtonItem)
        _infoBarButtonItem = [[OUIInspector inspectorBarButtonItemWithTarget:self action:@selector(_showInspector:)] retain];
    return _infoBarButtonItem;
}

- (OUIUndoBarButtonItem *)undoBarButtonItem;
{
    if (!_undoBarButtonItem) {
        _undoBarButtonItem = [[OUIUndoBarButtonItem alloc] init];
        _undoBarButtonItem.undoBarButtonItemTarget = self;
    }
    return _undoBarButtonItem;
}

- (IBAction)makeNewDocument:(id)sender;
{
    [self.documentPicker newDocument:sender];
}

/* We haven't actually implemented favorites yet

- (void)toggleFavorites:(id)sender;
{
    [self.documentPicker setSelectedProxy:self.documentPicker.previewScrollView.lastProxy scrolling:YES animated:NO];
}
*/

- (NSString *)documentTypeForURL:(NSURL *)url;
{
    NSString *uti = [OFSFileInfo UTIForURL:url];
    OBASSERT(uti);
    OBASSERT([uti hasPrefix:@"dyn."] == NO); // should be registered
    return uti;
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
    
    if (proxy != nil && proxyCount > 1) {
        NSUInteger proxyIndex = [proxies indexOfObjectIdenticalTo:proxy];
        if (proxyIndex == NSNotFound) {
            OBASSERT_NOT_REACHED("Missing proxy");
            proxyIndex = 1; // less terrible.
        }
        
        NSString *counterFormat = NSLocalizedStringWithDefaultValue(@"%d of %d <document index", @"OmniUI", OMNI_BUNDLE, @"%@ (%d of %d)", @"format for showing the main title, document index and document count, in that order");
        title = [NSString stringWithFormat:counterFormat, title, proxyIndex + 1, proxyCount];
    }
    
    [_appTitleToolbarButton setTitle:title forState:UIControlStateNormal];
    _appTitleToolbarButton.titleLabel.font = [UIFont boldSystemFontOfSize:17.0];
    [_appTitleToolbarButton sizeToFit];
    [_appTitleToolbarButton layoutIfNeeded];
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

#pragma mark -
#pragma mark UITextFieldDelegate

- (BOOL)textFieldShouldBeginEditing:(UITextField *)textField;
{
    OBPRECONDITION(textField == _documentTitleTextField);

    textField.text = [self.documentPicker editNameForDocumentURL:[_document url]];
    return YES;
}

- (void)textFieldDidEndEditing:(UITextField *)textField;
{
    OBPRECONDITION(textField == _documentTitleTextField);
    
    // If we are new, there will be no proxy.
    NSString *originalName = [self.documentPicker editNameForDocumentURL:_document.url];
    NSString *newName = [textField text];
    if (!newName || [newName length] == 0) {
        textField.text = originalName;
        return;
    }
    
    if (![newName isEqualToString:originalName]) {
        OUIDocumentProxy *oldProxy = _document.proxy;
        NSURL *oldURL = [[[oldProxy url] retain] autorelease];
        OUIDocumentPicker *documentPicker = self.documentPicker;
        if (oldProxy) {
            NSString *documentType = [self documentTypeForURL:oldProxy.url];
            NSURL *newProxyURL = [documentPicker renameProxy:oldProxy toName:newName type:documentType];
            
            // <bug://bugs/61021> Code below checks for "/" in the name, but there could still be other renaming problems that we don't know about.
            if (oldURL == newProxyURL) {
                NSString *msg = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Unable to rename document to \"%@\".", @"OmniUI", OMNI_BUNDLE, @"error when renaming a document"), newName];                
                NSError *err = [[NSError alloc] initWithDomain:NSURLErrorDomain code:0 userInfo:[NSDictionary dictionaryWithObjectsAndKeys:msg, NSLocalizedDescriptionKey, msg, NSLocalizedFailureReasonErrorKey, nil]];
                OUI_PRESENT_ERROR(err);
                [err release];
            } else {
                [_document proxyURLChanged];
            }
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
        }
        
        textField.text = [self.documentPicker displayNameForDocumentURL:[_document url]];
    }
    
    // UITextField adjusts its recognizers when it starts editing. Put ours back.
    [self _setupGesturesOnTitleTextField];
}

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string;
{
    OBPRECONDITION(textField == _documentTitleTextField);
    
    // <bug://bugs/61021>
    NSRange r = [string rangeOfString:@"/"];
    if (r.location != NSNotFound) {
        return NO;
    }
    
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
        
        CGFloat interItemPadding = [self.toolbarViewController interItemPadding];
        CGFloat leftWidth = 0.0f;
        CGFloat rightWidth = 0.0f;
        NSInteger itemCount = -1;

        if (documentPicker.documentTypeForNewFiles != nil) {
            UIBarButtonItem *addItem = [[[OUIBarButtonItem alloc] initWithTitle:NSLocalizedStringFromTableInBundle(@"New Document", @"OmniUI", OMNI_BUNDLE, @"Toolbar button for creating a new, empty document.")
                                                                          style:UIBarButtonItemStyleBordered
                                                                         target:self action:@selector(makeNewDocument:)] autorelease];
            [toolbarItems addObject:addItem];
            leftWidth += CGRectGetWidth([[addItem customView] bounds]);
            itemCount++;
        }
        
        if ([[OFPreferenceWrapper sharedPreferenceWrapper] boolForKey:@"OUIImportEnabled"]) {
            UIBarButtonItem *importItem = [[[OUIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"OUIToolbarButtonImport.png"] 
                                                                             style:UIBarButtonItemStyleBordered 
                                                                            target:self action:@selector(showSyncMenu:)] autorelease];
            [toolbarItems addObject:importItem];
            leftWidth += CGRectGetWidth([[importItem customView] bounds]);
            itemCount++;
        }
        
        if (itemCount > 0)
        leftWidth += interItemPadding;
        rightWidth = CGRectGetWidth([self.appMenuBarItem.customView bounds]);
        UIBarButtonItem *leftPadding = nil;
        UIBarButtonItem *rightPadding = nil;
        
        if (leftWidth > rightWidth) {
            rightPadding = [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFixedSpace target:nil action:NULL] autorelease];
            [rightPadding setWidth:leftWidth - rightWidth + interItemPadding];
        } else if (rightWidth > leftWidth) {
            leftPadding = [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFixedSpace target:nil action:NULL] autorelease];
            [leftPadding setWidth:rightWidth - leftWidth + interItemPadding];
        }

        if (leftPadding)
            [toolbarItems addObject:leftPadding];
        [toolbarItems addObject:[[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:NULL] autorelease]];
        
        UIButton *titleButton = [OUIToolbarTitleButton buttonWithType:UIButtonTypeCustom];
        UIImage *disclosureImage = [UIImage imageNamed:@"OUIToolbarTitleDisclosureButton.png"];
        OBASSERT(disclosureImage != nil);
        [titleButton setImage:disclosureImage forState:UIControlStateNormal];
        titleButton.adjustsImageWhenHighlighted = NO;
        [titleButton addTarget:self.documentPicker action:@selector(filterAction:) forControlEvents:UIControlEventTouchUpInside];
        self.appTitleToolbarButton = titleButton;

        [self _updateTitle];

        UIBarButtonItem *titleItem = [[UIBarButtonItem alloc] initWithCustomView:titleButton];
        [toolbarItems addObject:titleItem];
        [titleItem release];
        
        [toolbarItems addObject:[[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:NULL] autorelease]];
        if (rightPadding)
            [toolbarItems addObject:rightPadding];
        
#if 0 // Punting on favorites for 1.0
        UIBarButtonItem *favoritesItem = [[[OUIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"OUIToolbarFavoriteHollow.png"] style:UIBarButtonItemStyleBordered target:self action:@selector(toggleFavorites:)] autorelease];
        [toolbarItems addObject:favoritesItem];
        
        UISearchBar *searchBar = [[[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, 200, 20)] autorelease];
        UIBarButtonItem *searchItem = [[[UIBarButtonItem alloc] initWithCustomView:searchBar] autorelease];
        [toolbarItems addObject:searchItem];
#endif
        [toolbarItems addObject:self.appMenuBarItem];
        
        documentPicker.toolbarItems = [[toolbarItems copy] autorelease];
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
        
        [documentPicker setSelectedProxy:proxyToSelect scrolling:YES animated:NO];
    }
    
    return YES;
}

- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url sourceApplication:(NSString *)sourceApplication annotation:(id)annotation;
{
    if ([self isSpecialURL:url]) {
        return [self handleSpecialURL:url];
    }

    [self.documentPicker performSelector:@selector(_loadProxies)];

    OUIDocumentProxy *proxy = [self.documentPicker proxyWithURL:url];
    if (!proxy)
        return NO;

    NSString *path = [[[url path] stringByExpandingTildeInPath] stringByStandardizingPath];
    NSString *extension = [path pathExtension];
    
    // Move the proxy out of the Inbox immediately
    if ([path hasPrefix:[[OUIDocumentPicker userDocumentsDirectory] stringByExpandingTildeInPath]] && 
        [[[path stringByDeletingLastPathComponent] lastPathComponent] isEqualToString:@"Inbox"]) {
        if (extension != nil) {
            NSString *name;
            NSUInteger counter;
            OFSFileManagerSplitNameAndCounter(proxy.name, &name, &counter);
            NSString *duplicatePath = [OUIDocumentPicker availablePathInDirectory:[OUIDocumentPicker userDocumentsDirectory] baseName:name extension:extension counter:&counter];
            NSError *error = nil;
            if ([[NSFileManager defaultManager] copyItemAtPath:path toPath:duplicatePath error:&error]) {
                [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
                NSURL *duplicateURL = [NSURL fileURLWithPath:duplicatePath];
                [self.documentPicker performSelector:@selector(_loadProxies)];
                proxy = [self.documentPicker proxyWithURL:duplicateURL];
            }
        }
    }
    
    if (!proxy)
        return NO;
    
    [self _openDocument:proxy animated:NO];
    return YES;
}

- (void)_saveDocumentAndState;
{
    NSArray *nextLaunchAction = nil;
    
    OUIWithoutAnimating(^{
        [_window endEditing:YES];
        [_window layoutIfNeeded];
    });
    
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
}

- (void)applicationDidEnterBackground:(UIApplication *)application;
// From the documentation:  "Your implementation of this method has approximately five seconds to perform any tasks and return.  You should perform any tasks relating to adjusting your user interface before this method exits but other tasks (such as saving state) should be moved to a concurrent dispatch queue or secondary thread as needed."
{
    // For now, we'll just hope that saving happens within five seconds (like we have been doing for app termination)
    [self _saveDocumentAndState];
}

- (void)applicationWillTerminate:(UIApplication *)application;
{
    [self _saveDocumentAndState];
    
    [super applicationWillTerminate:application];
}

#pragma mark -
#pragma mark OUIDocumentPickerDelegate

- (BOOL)createNewDocumentAtURL:(NSURL *)url error:(NSError **)outError;
{
    OBPRECONDITION(_document == nil);
    
    Class cls = [self documentClassForURL:url];
    OBASSERT(OBClassIsSubclassOfClass(cls, [OUIDocument class]));
    
    OUIDocument *document = [[[cls alloc] initEmptyDocumentToBeSavedToURL:url error:outError] autorelease];
    if (document == nil)
        return NO;
    
    // We aren't going to open this document instance -- it will get thrown away. But we want to at least size it correctly so that any PDF preview is emitted correctly.
    [_toolbarViewController adjustSizeToMatch:document.viewController];
    
    // We do go ahead and save the document immediately so that we can animate it into view most easily.
    BOOL ok = [document saveAsNewDocumentToURL:url error:outError];
    [document willClose];
    return ok;
}

#pragma mark -
#pragma mark OUIUndoBarButtonItemTarget

- (void)undo:(id)sender;
{
    [_document undo:sender];
}

- (void)redo:(id)sender;
{
    [_document redo:sender];
}

- (BOOL)canPerformAction:(SEL)action withSender:(id)sender;
{
    if (action == @selector(undo:))
        return [_document.undoManager canUndo];
    else if (action == @selector(redo:))
        return [_document.undoManager canRedo];
        
    return YES;
}

#pragma mark -
#pragma mark Private

- (void)_openDocument:(OUIDocumentProxy *)proxy;
{
    // If we crash in trying to open this document, we should select it the next time we launch rather than trying to open it over and over again
    NSArray *nextLaunchAction = [NSArray arrayWithObjects:SelectAction, [proxy.url absoluteString], nil];
    [[NSUserDefaults standardUserDefaults] setObject:nextLaunchAction forKey:OUINextLaunchActionDefaultsKey];
    [[NSUserDefaults standardUserDefaults] synchronize];

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
    
    NSString *title = [self.documentPicker displayNameForDocumentURL:[_document url]];
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

    // Start automatically tracking undo state from this document's undo manager
    _undoBarButtonItem.undoManager = _document.undoManager;

    // Might be a newly created document that was never edited and trivially returns YES to saving. Make sure there is a proxy before overwriting our last default value.
    NSURL *url = _document.url;
    OUIDocumentProxy *proxy = [self.documentPicker proxyWithURL:url];
    if (proxy) {
        NSArray *nextLaunchAction = [NSArray arrayWithObjects:OpenAction, [url absoluteString], nil];
        [[NSUserDefaults standardUserDefaults] setObject:nextLaunchAction forKey:OUINextLaunchActionDefaultsKey];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }

    // UIWindow will automatically create an undo manager if one isn't found along the responder chain. We want to be darn sure that don't end up getting two undo managers and accidentally splitting our registrations between them.
    OBASSERT([_document undoManager] == [_document.viewController undoManager]);
    OBASSERT([_document undoManager] == [_document.viewController.view undoManager]); // Does your view controller implement -undoManager? We don't do this for you right now.
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
    
    // Stop tracking the state from this document's undo manager
    _undoBarButtonItem.undoManager = nil;
    
    OUIWithoutAnimating(^{
        [_window endEditing:YES];
        [_window layoutIfNeeded];
    });
    
    // The inspector would animate closed and raise an exception, having detected it was getting deallocated while still visible (but animating away).
    [self dismissPopoverAnimated:NO];
    
    // Ending editing may have started opened an undo group, with the nested group stuff for autosave (see OUIDocument). Give the runloop a chance to close the nested group.
    if ([_document.undoManager groupingLevel] > 0) {
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate distantPast]];
        OBASSERT([_document.undoManager groupingLevel] == 0);
    }
    
    // Start up the spinner and stop accepting events. We are NOT passing the picker here since that would add it to the view and lay it out. This is usually OK, but if we've rotated the device since opening, the picker layout would provoke the previews to load new previews (due to their size changing). Here we just want to start the spinner.
    [_toolbarViewController willAnimateToInnerViewController:nil];
    
    // Save the document. We don't currently do this in a background thread (letting the spinner go) since it draws a PDF preview. This uses the global UIKit graphics context stack and isn't thread-safe (only the raw CGContextRef stuff is).
    NSError *error = nil;
    if (![_document saveForClosing:&error])
        OUI_PRESENT_ERROR(error);
    
    // Now, start a rescan of the proxies
    OUIDocumentPicker *picker = self.documentPicker;
    NSURL *closingURL = [[_document.url copy] autorelease];
    [picker.previewScrollView sortProxies];
    [picker rescanDocumentsScrollingToURL:closingURL animated:NO];
    
    OUIDocumentProxy *proxy = [picker proxyWithURL:closingURL];
    
    if (proxy.isLoadingPreview) {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_proxyFinishedLoadingPreviewNotification:) name:OUIDocumentProxyPreviewDidLoadNotification object:proxy];
    } else {
        [self _proxyFinishedLoadingPreview:proxy];
    }
}

- (void)_proxyFinishedLoadingPreview:(OUIDocumentProxy *)proxy;
{
    OBPRECONDITION(proxy != nil);

    UIView *documentView = [self pickerAnimationViewForTarget:_document];
    self.documentPicker.selectedProxy = proxy;
    [_toolbarViewController setInnerViewController:self.documentPicker animatingView:documentView toView:self.documentPicker.viewForSelectedProxy];

    [_document willClose];
    [_document release];
    _document = nil;
}

- (void)_proxyFinishedLoadingPreviewNotification:(NSNotification *)note;
{
    OUIDocumentProxy *proxy = [note object];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:OUIDocumentProxyPreviewDidLoadNotification object:proxy];
    [self _proxyFinishedLoadingPreview:proxy];
}

- (void)_showInspector:(id)sender;
{
    [self showInspectorFromBarButtonItem:_infoBarButtonItem];
}

- (void)_handleTitleTapGesture:(UIGestureRecognizer*)gestureRecognizer;
{
    // do not want an action here
    OBASSERT(gestureRecognizer.view == _documentTitleTextField);
}

- (void)_handleTitleDoubleTapGesture:(UIGestureRecognizer*)gestureRecognizer;
{
    OBASSERT(gestureRecognizer.view == _documentTitleTextField);
    
    // Switch to a white background while editing so that the text loupe will work properly.
    [_documentTitleTextField setTextColor:[UIColor blackColor]];
    [_documentTitleTextField setBackgroundColor:[UIColor whiteColor]];
    _documentTitleTextField.borderStyle = UITextBorderStyleBezel;
    
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
    
    // Restore the regular colors of the text field.
    [_documentTitleTextField setTextColor:[UIColor whiteColor]];
    [_documentTitleTextField setBackgroundColor:[UIColor clearColor]];
    _documentTitleTextField.borderStyle = UITextBorderStyleNone;
}

@end

@implementation OUIToolbarTitleButton

#pragma mark -
#pragma mark UIControl subclass

- (BOOL)beginTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event;
{
    _touchesInside = YES;
    
    _highlightView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"OUIToolbarButtonFauxHighlight.png"]];
    CGRect imageRect = [self bounds];
    imageRect.origin.x = floor(CGRectGetMidX(imageRect));
    imageRect.origin.y = floor(CGRectGetMidY(imageRect));
    imageRect.size = [_highlightView frame].size;
    imageRect.origin.x -= floor(imageRect.size.width/2);
    imageRect.origin.y -= floor(imageRect.size.height/2);
    [_highlightView setFrame:imageRect];
    [self addSubview:_highlightView];
    return [super beginTrackingWithTouch:touch withEvent:event];
}

- (BOOL)continueTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event;
{
    CGPoint location = [touch locationInView:self];
    CGRect rect = [self bounds];
    BOOL inside = CGRectContainsPoint(rect, location);
    if (inside != _touchesInside) {
        _touchesInside = inside;
        [_highlightView setHidden:!_touchesInside];
    }
    return [super continueTrackingWithTouch:touch withEvent:event];
}

- (void)endTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event
{
    [super endTrackingWithTouch:touch withEvent:event];
    [_highlightView removeFromSuperview];
    [_highlightView release];
    _highlightView = nil;
}

- (void)cancelTrackingWithEvent:(UIEvent *)event;
{
    [super cancelTrackingWithEvent:event];
    [_highlightView removeFromSuperview];
    [_highlightView release];
    _highlightView = nil;
}

- (void)dealloc;
{
    [_highlightView release];
    [super dealloc];
}

#pragma mark -
#pragma mark UIButton subclass

- (CGRect)titleRectForContentRect:(CGRect)contentRect;
{
    CGRect originalTitleRect = [super titleRectForContentRect:contentRect];
    CGRect titleRect = originalTitleRect;
    titleRect.origin.x = CGRectGetMinX(contentRect);
    return titleRect;
}

- (CGRect)imageRectForContentRect:(CGRect)contentRect;
{
    CGRect originalImageRect = [super imageRectForContentRect:contentRect];
    CGRect imageRect = originalImageRect;
    imageRect.origin.x = CGRectGetMaxX(contentRect) - imageRect.size.width;
    return imageRect;
}

@end
