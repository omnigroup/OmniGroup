// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIDocumentPicker.h>

#import <MessageUI/MFMailComposeViewController.h>
#import <MobileCoreServices/UTCoreTypes.h>
#import <MobileCoreServices/UTType.h>
#import <OmniFoundation/NSFileManager-OFSimpleExtensions.h>
#import <OmniFoundation/OFBinding.h>
#import <OmniUI/OUIAppController.h>
#import <OmniUI/OUIDocumentProxy.h>
#import <OmniUI/OUIDocumentPickerView.h>
#import <OmniUI/OUIDocumentPickerDelegate.h>
#import <OmniUI/OUIToolbarViewController.h>
#import <OmniFoundation/NSMutableArray-OFExtensions.h>
#import <OmniFoundation/NSFileManager-OFSimpleExtensions.h>
#import <OmniQuartz/CALayer-OQExtensions.h>
#import <OmniQuartz/OQDrawing.h>
#import <sys/stat.h> // For S_IWUSR

#import <MobileCoreServices/UTCoreTypes.h>

#import "OUIDocumentProxy-Internal.h"
#import "OUIDocumentProxyView.h"
#import "OUIDocumentPDFPreview.h"

RCS_ID("$Id$");

#if 0 && defined(DEBUG)
    #define PICKER_DEBUG(format, ...) NSLog(@"PICKER: " format, ## __VA_ARGS__)
#else
    #define PICKER_DEBUG(format, ...)
#endif

static NSString * const ProxiesBinding = @"proxies";

@interface OUIDocumentPicker (/*Private*/) <UIActionSheetDelegate, MFMailComposeViewControllerDelegate>
- (NSString *)_dateStringForDocumentProxy:(OUIDocumentProxy *)proxy;
- (void)_loadProxies;
- (void)_setupProxiesBinding;
- (OUIDocumentProxy *)_makeProxyForURL:(NSURL *)fileURL;
- (void)_documentProxyTapped:(OUIDocumentProxy *)proxy;
- (void)_sendEmailWithSubject:(NSString *)subject attachmentName:(NSString *)name data:(NSData *)data fileType:(NSString *)fileType;
- (UIImage *)_cameraRollImageForProxy:(OUIDocumentProxy *)documentProxy;
- (void)_deleteWithoutConfirmation;
@end

@implementation OUIDocumentPicker

static NSString * const PositionAdjustAnimation = @"positionAdjust";

static void _pushAndFadeAnimation(UIView *view, CGPoint direction, BOOL fade)
{
    if (!view)
        return; // _favoriteButton
    
    const CGFloat kFadeDistance = 64;
    
    CGSize offset = CGSizeMake(direction.x * kFadeDistance, direction.y * kFadeDistance);
    
    // Push the title and date down off screen (and fade them out?)
    CABasicAnimation *positionAnimation = [CABasicAnimation animationWithKeyPath:@"position"];
    CGPoint position = view.layer.position;
    CGPoint fadePosition = CGPointMake(position.x + offset.width, position.y + offset.height);
    positionAnimation.fromValue = [NSValue valueWithCGPoint:fade ? position : fadePosition];
    positionAnimation.toValue = [NSValue valueWithCGPoint:fade ? fadePosition : position];
    
    CABasicAnimation *opacityAnimation = [CABasicAnimation animationWithKeyPath:@"opacity"];
    opacityAnimation.fromValue = [NSNumber numberWithFloat:fade ? 1 : 0];
    opacityAnimation.toValue = [NSNumber numberWithFloat:fade ? 0 : 1];
    
    CAAnimationGroup *group = [CAAnimationGroup animation];
    group.fillMode = kCAFillModeForwards;
    group.removedOnCompletion = !fade;
    group.animations = [NSArray arrayWithObjects:positionAnimation, opacityAnimation, nil];
    
    [view.layer addAnimation:group forKey:PositionAdjustAnimation];
}

typedef enum {
    AnimateNeighborProxies,  
    AnimateTitleAndButtons,
} AnimationType;

static void _addPushAndFadeAnimations(OUIDocumentPicker *self, BOOL fade, AnimationType type)
{
    if (type == AnimateTitleAndButtons) {
        CGPoint down = CGPointMake(0, 1);
        _pushAndFadeAnimation(self->_titleLabel, down, fade);
        _pushAndFadeAnimation(self->_dateLabel, down, fade);
        _pushAndFadeAnimation(self->_favoriteButton, down, fade);
        _pushAndFadeAnimation(self->_exportButton, down, fade);
        _pushAndFadeAnimation(self->_newDocumentButton, down, fade);
        _pushAndFadeAnimation(self->_deleteButton, down, fade);
    } else if (type == AnimateNeighborProxies) {
        OUIDocumentProxy *proxy = self->_previewScrollView.proxyClosestToCenter;
        if (proxy) { // New document?
            OUIDocumentProxy *neighbor;
            
            if ((neighbor = [self->_previewScrollView proxyToLeftOfProxy:proxy])) {
                CGPoint left = CGPointMake(-1, 0);
                _pushAndFadeAnimation(neighbor.view, left, fade);
            }
            if ((neighbor = [self->_previewScrollView proxyToRightOfProxy:proxy])) {
                CGPoint right = CGPointMake(1, 0);
                _pushAndFadeAnimation(neighbor.view, right, fade);
            }
        }
    } else {
        OBASSERT_NOT_REACHED("Bad type");
    }
}

+ (NSString *)userDocumentsDirectory;
{
    static NSString *documentDirectory = nil; // Avoid trying the creation on each call.
    
    if (!documentDirectory) {
        documentDirectory = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES/*expandTilde*/) lastObject] copy];
        OBASSERT(documentDirectory);

        if (![[NSFileManager defaultManager] directoryExistsAtPath:documentDirectory]) {
            NSError *error = nil;
            if (![[NSFileManager defaultManager] createDirectoryAtPath:documentDirectory withIntermediateDirectories:YES attributes:nil error:&error]) {
                NSLog(@"Error creating %@: %@", documentDirectory, [error toPropertyList]);
            }
        }
    }
        
    return documentDirectory;
}

+ (NSString *)sampleDocumentsDirectory;
{
    NSString *samples = [[NSBundle mainBundle] pathForResource:@"Samples" ofType:@""];
    OBASSERT(samples);
    return samples;
}

+ (void)copySampleDocumentsToUserDocuments;
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *sampleDocumentsDirectory = [[self class] sampleDocumentsDirectory];
    NSString *userDocumentsDirectory = [[self class] userDocumentsDirectory];
    NSArray *fileNames = [fileManager directoryContentsAtPath:sampleDocumentsDirectory];
    for (NSString *fileName in fileNames) {
        NSString *samplePath = [sampleDocumentsDirectory stringByAppendingPathComponent:fileName];
        NSString *documentPath = [userDocumentsDirectory stringByAppendingPathComponent:fileName];
        NSError *error = nil;
        if (![[NSFileManager defaultManager] copyItemAtPath:samplePath toPath:documentPath error:&error]) {
            NSLog(@"Unable to copy %@ to %@: %@", samplePath, documentPath, [error toPropertyList]);
        } else if ([[fileName stringByDeletingPathExtension] isEqualToString:@"Welcome"]) {
            [fileManager touchFile:documentPath];
        }
    }
}
          
+ (NSString *)pathToSampleDocumentNamed:(NSString *)name ofType:(NSString *)fileType;
{
    CFStringRef extension = UTTypeCopyPreferredTagWithClass((CFStringRef)fileType, kUTTagClassFilenameExtension);
    if (!extension)
        OBRequestConcreteImplementation(self, _cmd); // UTI not registered in the Info.plist?
    
    NSString *path = [[self sampleDocumentsDirectory] stringByAppendingPathComponent:[name stringByAppendingPathExtension:(NSString *)extension]];
    CFRelease(extension);
    
    return path;
}

static NSString *_availablePath(NSString *directory, NSString *baseName, NSString *extension, NSUInteger *ioCounter)
{
    NSUInteger counter = *ioCounter; // starting counter
    
    NSString *result = nil;
    while (!result) {
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        
        NSString *fileName = [[NSString alloc] initWithFormat:@"%@.%@", baseName, extension];
        NSString *path = [directory stringByAppendingPathComponent:fileName];
        [fileName release];
        
        if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
            result = [path copy];
        } else {
            if (counter == 0)
                counter = 2; // First duplicate should be "Foo 2".
            
            fileName = [[NSString alloc] initWithFormat:@"%@ %d.%@", baseName, counter, extension];
            counter++;
            
            NSString *path = [directory stringByAppendingPathComponent:fileName];
            [fileName release];
            
            if (![[NSFileManager defaultManager] fileExistsAtPath:path])
                result = [path copy];
        }
        
        [pool release];
    }
    
    *ioCounter = counter; // report how many we used
    return [result autorelease];
}

+ (NSString *)availablePathInDirectory:(NSString *)dir baseName:(NSString *)baseName extension:(NSString *)extension counter:(NSUInteger *)ioCounter;
{
    return _availablePath(dir, baseName, extension, ioCounter);
}

- (OUIDocumentProxy *)proxyByInstantiatingSampleDocumentNamed:(NSString *)name ofType:(NSString *)fileType;
{
    CFStringRef extension = UTTypeCopyPreferredTagWithClass((CFStringRef)fileType, kUTTagClassFilenameExtension);
    if (!extension)
        OBRequestConcreteImplementation(self, _cmd); // UTI not registered in the Info.plist?

    NSUInteger counter = 0;
    
    NSString *samplePath = [[self class] pathToSampleDocumentNamed:name ofType:fileType];
    NSString *documentPath = _availablePath([[self class] userDocumentsDirectory], name, (NSString *)extension, &counter);
    CFRelease(extension);

    NSError *error = nil;
    if (![[NSFileManager defaultManager] copyItemAtPath:samplePath toPath:documentPath error:&error]) {
        NSLog(@"Unable to copy %@ to %@: %@", samplePath, documentPath, [error toPropertyList]);
        return nil;
    }
    
    // This is the reason we return a proxy; we need to rescan and don't want to let the caller forget.
    [self rescanDocuments];

    // Hack. We expect the caller to want to immediately open this proxy, but until layout, the proxy's view isn't in our scroll view. And that causes the open animation to fail.
    [self view];
    [_previewScrollView layoutSubviews];
    
    OUIDocumentProxy *proxy = [self proxyWithURL:[NSURL fileURLWithPath:documentPath]];
    OBASSERT(proxy);
    return proxy;
}
          
static id _commonInit(OUIDocumentPicker *self)
{
    self.directory = [[self class] userDocumentsDirectory]; // accessor does the scan
    
    return self;
}

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil;
{
    if (!(self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil]))
        return nil;
    return _commonInit(self);
}

- initWithCoder:(NSCoder *)coder;
{
    if (!(self = [super initWithCoder:coder]))
        return nil;
    return _commonInit(self);
}

- (void)dealloc;
{
    [_previewScrollView release];
    [_titleLabel release];
    [_dateLabel release];
    [_buttonGroupView release];
    [_favoriteButton release];
    [_exportButton release];
    [_newDocumentButton release];
    [_deleteButton release];
    
    [_proxiesBinding invalidate];
    [_proxiesBinding release];
    [_directory release];
    [_proxies release];
    [_proxyTappedTarget release];
    [_actionSheetActions release];
    
    [super dealloc];
}

#pragma mark -
#pragma mark KVC

@synthesize delegate = _nonretained_delegate;
- (void)setDelegate:(id <OUIDocumentPickerDelegate>)delegate;
{
    if (_nonretained_delegate == delegate)
        return;
    _nonretained_delegate = delegate;

    [self _loadProxies];
}


@synthesize previewScrollView = _previewScrollView;
@synthesize titleLabel = _titleLabel;
@synthesize dateLabel = _dateLabel;
@synthesize favoriteButton = _favoriteButton;
@synthesize exportButton = _exportButton;
@synthesize newDocumentButton = _newDocumentButton;
@synthesize deleteButton = _deleteButton;
@synthesize buttonGroupView = _buttonGroupView;

@synthesize directory = _directory;
- (void)setDirectory:(NSString *)directory;
{
    if (OFISEQUAL(directory, _directory))
        return;
    [_directory release];
    _directory = [directory copy];
    
    [self _loadProxies];
}

@synthesize proxyTappedTarget = _proxyTappedTarget;
@synthesize proxyTappedAction = _proxyTappedAction;

- (void)rescanDocumentsScrollingToURL:(NSURL *)targetURL;
{
    [self rescanDocumentsScrollingToURL:targetURL animated:(_previewScrollView.window != nil)];
}

- (void)rescanDocumentsScrollingToURL:(NSURL *)targetURL animated:(BOOL)animated;
{
    [[targetURL retain] autorelease];
    
    // This depends on the caller to have *also* poked the proxies into reloading any metadata that will be used to sort or filter them. That is, we don't reload all that info right now.
    [self _loadProxies];

    // We need our view if we are to do the scrolling <bug://bugs/60388> (OGS isn't restoring the the last selected document on launch)
    [self view];
    
    // <bug://bugs/60005> (Document picker scrolls to empty spot after editing file)
    [_previewScrollView.window layoutIfNeeded];
    
    OUIDocumentProxy *proxy = [self proxyWithURL:targetURL];
    if (!proxy)
        proxy = _previewScrollView.firstProxy;
    
    [_previewScrollView snapToProxy:proxy animated:animated];
}

- (void)rescanDocuments;
{
    [self rescanDocumentsScrollingToURL:_previewScrollView.proxyClosestToCenter.url];
}

- (OUIDocumentProxy *)revealAndActivateNewDocumentAtURL:(NSURL *)newDocumentURL;
{
    [self _loadProxies];
    OUIDocumentProxy *createdProxy = [self proxyWithURL:newDocumentURL];
    OBASSERT(createdProxy);
    
    // At first it should not take up space.
    createdProxy.layoutShouldAdvance = NO;
    [_previewScrollView layoutSubviews];
    [_previewScrollView snapToProxy:createdProxy animated:NO];

    OBASSERT(createdProxy.view != nil); // should have had a view assigned.
    createdProxy.view.alpha = 0; // start out transparent

    // Turn on layout advancing for this proxy and do an animated layout, sliding to make room for it.
    createdProxy.layoutShouldAdvance = YES;

    [UIView beginAnimations:@"slide old documents to make room for new document" context:createdProxy];
    [UIView setAnimationDuration:0.3];
    [UIView setAnimationDelegate:self];
    [UIView setAnimationCurve:UIViewAnimationCurveEaseIn];
    [UIView setAnimationDidStopSelector:@selector(_revealNewDocumentAnimationDidStop:finished:context:)];
    {
        [_previewScrollView layoutSubviews];
    }
    [UIView commitAnimations];
    
    return createdProxy;
}

- (void)_revealNewDocumentAnimationDidStop:(NSString *)animationID finished:(NSNumber *)finished context:(void *)context;
{
    OUIDocumentProxy *proxy = context;

    [UIView beginAnimations:@"fade in new document" context:NULL];
    [UIView setAnimationDuration:0.3];
    {
        proxy.view.alpha = 1;
    }
    [UIView commitAnimations];

    // Not -_documentProxyTapped: since that starts a scroll to the proxy if it isn't the one currently in the middle, but we might still be animating to the new docuemnt
    [_proxyTappedTarget performSelector:_proxyTappedAction withObject:proxy];
}

- (BOOL)hasDocuments;
{
    return [_proxies count] != 0;
}

- (OUIDocumentProxy *)selectedProxy;
{
    return _previewScrollView.proxyClosestToCenter;
}

- (OUIDocumentProxy *)proxyWithURL:(NSURL *)url;
{
    if (url == nil || ![url isFileURL])
        return nil;

    NSString *standardizedPathForURL = [[url path] stringByStandardizingPath];
    for (OUIDocumentProxy *proxy in _proxies) {
        NSString *proxyPath = [[[proxy url] path] stringByStandardizingPath];
        if ([proxyPath isEqual:standardizedPathForURL])
            return proxy;
    }
    return nil;
}

- (OUIDocumentProxy *)proxyNamed:(NSString *)name;
{
    for (OUIDocumentProxy *proxy in _proxies)
        if ([proxy.name isEqual:name])
            return proxy;
    return nil;
}

- (BOOL)canEditProxy:(OUIDocumentProxy *)proxy;
{
    NSString *documentsPath = [[[self class] userDocumentsDirectory] stringByExpandingTildeInPath];
    if (![documentsPath hasSuffix:@"/"])
        documentsPath = [documentsPath stringByAppendingString:@"/"];
    
    NSString *proxyPath = [[[proxy.url absoluteURL] path] stringByExpandingTildeInPath];
    return [proxyPath hasPrefix:documentsPath];
}

- (BOOL)deleteDocumentWithoutPrompt:(OUIDocumentProxy *)proxy error:(NSError **)outError;
{
    if (proxy == nil)
        return YES;
    return [[NSFileManager defaultManager] removeItemAtPath:[proxy.url path] error:outError];
}

- (OUIDocumentProxy *)renameProxy:(OUIDocumentProxy *)proxy toName:(NSString *)name type:(NSString *)documentUTI;
{
    CFStringRef extension = UTTypeCopyPreferredTagWithClass((CFStringRef)documentUTI, kUTTagClassFilenameExtension);
    if (!extension)
        OBRequestConcreteImplementation(self, _cmd); // UTI not registered in the Info.plist?
    
    NSString *directory = [[self class] userDocumentsDirectory];
    NSUInteger emptyCounter = 0;
    NSString *safePath = _availablePath(directory, name, (NSString *)extension, &emptyCounter);
    CFRelease(extension);
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSURL *oldURL = [proxy url];
    NSError *error = nil;
    if (![fileManager moveItemAtPath:[oldURL path] toPath:safePath error:&error]) {
        NSLog(@"Unable to copy %@ to %@: %@", [oldURL path], safePath, [error toPropertyList]);
        return proxy;
    }
    NSDictionary *attributes = [fileManager attributesOfItemAtPath:safePath error:NULL];
    if (attributes != nil) {
        NSUInteger mode = [attributes filePosixPermissions];
        if ((mode & S_IWUSR) == 0) {
            mode |= S_IWUSR;
            [fileManager setAttributes:[NSDictionary dictionaryWithObject:[NSNumber numberWithUnsignedInteger:mode] forKey:NSFilePosixPermissions] ofItemAtPath:safePath error:NULL]; // Not bothering to check for errors:  if this fails, we'll find out when it matters
        }
    }

    NSURL *newURL = [NSURL fileURLWithPath:safePath];
    [self rescanDocumentsScrollingToURL:newURL];
    OUIDocumentProxy *newProxy = [self proxyWithURL:newURL];    
    
    return newProxy;
}

- (NSURL *)urlForNewDocumentOfType:(NSString *)documentUTI;
{
    NSString *baseName = [_nonretained_delegate documentPickerBaseNameForNewFiles:self];
    if (!baseName) {
        OBASSERT_NOT_REACHED("No delegate? You probably want one to provide a better base untitled document name.");
        baseName = @"My Document";
    }
    return [self urlForNewDocumentWithName:baseName ofType:documentUTI];
}

- (NSURL *)urlForNewDocumentWithName:(NSString *)name ofType:(NSString *)documentUTI;
{
    OBPRECONDITION(documentUTI);

    CFStringRef extension = UTTypeCopyPreferredTagWithClass((CFStringRef)documentUTI, kUTTagClassFilenameExtension);
    if (!extension)
        OBRequestConcreteImplementation(self, _cmd); // UTI not registered in the Info.plist?

    static NSString * const UntitledDocumentCreationCounterKey = @"OUIUntitledDocumentCreationCounter";

    NSString *directory = [[self class] userDocumentsDirectory];
    NSUInteger counter = [[NSUserDefaults standardUserDefaults] integerForKey:UntitledDocumentCreationCounterKey];

    NSString *path = _availablePath(directory, name, (NSString *)extension, &counter);
    CFRelease(extension);
    
    [[NSUserDefaults standardUserDefaults] setInteger:counter forKey:UntitledDocumentCreationCounterKey];
    return [NSURL fileURLWithPath:path];
}

- (void)scrollToProxy:(OUIDocumentProxy *)proxy animated:(BOOL)animated;
{
    [_previewScrollView snapToProxy:proxy animated:animated];
}

- (IBAction)favorite:(id)sender;
{
    NSLog(@"%s", __PRETTY_FUNCTION__);
}

- (IBAction)newDocumentMenu:(id)sender;
{
    OUIDocumentProxy *proxy = _previewScrollView.proxyClosestToCenter;
    NSURL *url = proxy.url;
    if (url == nil) {
        // No document is selected, so we can't duplicate one, so don't bother presenting a menu with a single choice
        [self newDocument:sender];
        return;
    }

    UIActionSheet *actionSheet = [[[UIActionSheet alloc] initWithTitle:nil delegate:self cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles:nil] autorelease];
    [_actionSheetActions release];
    _actionSheetActions = [[NSMutableArray alloc] init];

    [actionSheet addButtonWithTitle:NSLocalizedStringFromTableInBundle(@"New Document", @"OmniUI", OMNI_BUNDLE, @"Menu option in the document picker view")];
    [_actionSheetActions addObject:NSStringFromSelector(@selector(newDocument:))];

    [actionSheet addButtonWithTitle:NSLocalizedStringFromTableInBundle(@"Duplicate Document", @"OmniUI", OMNI_BUNDLE, @"Menu option in the document picker view")];
    [_actionSheetActions addObject:NSStringFromSelector(@selector(duplicateDocument:))];

    OBASSERT(sender == _newDocumentButton); // If not, we'll be popping this up from the wrong place
    [actionSheet showFromRect:[_newDocumentButton frame] inView:[_newDocumentButton superview] animated:YES];
    
    _nonretainedActionSheet = actionSheet;
}

- (IBAction)newDocument:(id)sender;
{
    [[OUIAppController controller] dismissAppMenu];

    NSString *documentType = [_nonretained_delegate documentPickerDocumentTypeForNewFiles:self];
    NSURL *newDocumentURL = [self urlForNewDocumentOfType:documentType];
    NSError *error = nil;
    id <OUIDocument> document = [_nonretained_delegate createNewDocumentAtURL:newDocumentURL error:&error];
    if (document == nil) {
        OUI_PRESENT_ERROR(error);
        return;
    }
    [document setProxy:[self revealAndActivateNewDocumentAtURL:newDocumentURL]];
}

- (IBAction)duplicateDocument:(id)sender;
{
    OUIDocumentProxy *proxy = _previewScrollView.proxyClosestToCenter;
    if (!proxy) {
        OBASSERT_NOT_REACHED("Make this button be disabled");
        return;
    }
    
    NSURL *url = proxy.url;
    NSString *originalPath = [[url absoluteURL] path];
    NSString *extension = [[originalPath lastPathComponent] pathExtension];
    if (extension == nil)
        return;
    
    // If the proxy name ends in a number, we are likely duplicating a duplicate.  Take that as our starting counter.  Of course, this means that if we duplicate "Revenue 2010", we'll get "Revenue 2011". But, w/o this we'll get "Revenue 2010 2", "Revenue 2010 2 2", etc.
    NSString *name;
    NSUInteger counter;
    OUIDocumentProxySplitNameAndCounter(proxy.name, &name, &counter);
    
    NSString *duplicatePath = _availablePath([[self class] userDocumentsDirectory], name, (NSString *)extension, &counter);

    NSError *error = nil;
    if (![[NSFileManager defaultManager] copyItemAtPath:originalPath toPath:duplicatePath error:&error]) {
        NSLog(@"Unable to duplicate %@ to %@: %@", originalPath, duplicatePath, [error toPropertyList]);
        return;
    }
    
    NSURL *duplicateURL = [NSURL fileURLWithPath:duplicatePath];

    // Scan for new proxies and set up the new one.
    OUIDocumentProxy *duplicateProxy;
    {
        [self _loadProxies];
        
        duplicateProxy = [self proxyWithURL:duplicateURL];
        OBASSERT(duplicateProxy);
        OBASSERT(duplicateProxy.currentPreview == nil);
        
        // At first it should not take up space.
        duplicateProxy.layoutShouldAdvance = NO;
        
        // The duplicate has exactly the same preview as the original, avoid loading it redundantly.
        [duplicateProxy previewDidLoad:proxy.currentPreview];
        OBASSERT(duplicateProxy.currentPreview != nil);
    }
    
    // Do a non-animated layout. This gets the proxy a view (hidden) assigned to it.
    OBASSERT(duplicateProxy.view == nil); // starts out without a view
    [_previewScrollView layoutSubviews];
    [_previewScrollView snapToProxy:duplicateProxy animated:NO]; // shouldn't need to animate since it *should* typically be right next to the original. not always if there is a gap in numbering dups, though.
    OBASSERT(duplicateProxy.view != nil); // should have had a view assigned.
    duplicateProxy.view.alpha = 0; // start out transparent
    
    // Turn on layout advancing for this proxy and do an animated layout, sliding to make room for it.
    duplicateProxy.layoutShouldAdvance = YES;

    // The end result will have the new document proxy in place, but transparent.
    [UIView beginAnimations:@"duplicate document slide" context:duplicateProxy];
    [UIView setAnimationDuration:0.2];
    [UIView setAnimationDidStopSelector:@selector(_duplicationSlideAnimationDidStop:finished:context:)];
    [UIView setAnimationDelegate:self];
    {
        [_previewScrollView layoutSubviews];
    }
    [UIView commitAnimations];
}

// Once the sliding of layout has happened in duplication, fade in the new proxy.
- (void)_duplicationSlideAnimationDidStop:(NSString *)animationID finished:(NSNumber *)finished context:(void *)context;
{
    OUIDocumentProxy *duplicateProxy = context;
    
    [UIView beginAnimations:@"fade in document" context:NULL];
    [UIView setAnimationDuration:0.2];
    [UIView setAnimationDelegate:self];
    [UIView setAnimationWillStartSelector:@selector(_logAnimationWillStart:context:)];
    {
        duplicateProxy.view.alpha = 1.0;
    }
    [UIView commitAnimations];
}

- (IBAction)delete:(id)sender;
{
    UIActionSheet *actionSheet = [[[UIActionSheet alloc] initWithTitle:nil delegate:self
                                                     cancelButtonTitle:nil
                                                destructiveButtonTitle:NSLocalizedStringFromTableInBundle(@"Delete Document", @"OmniUI", OMNI_BUNDLE, @"delete button title")
                                                     otherButtonTitles:nil] autorelease];

    [_actionSheetActions release];
    _actionSheetActions = [[NSMutableArray alloc] init];

    [_actionSheetActions addObject:NSStringFromSelector(@selector(_deleteWithoutConfirmation))];

    // Passing a cancelButtonTitle only adds a button on iPhone.  We really want one, though.
    [actionSheet addButtonWithTitle:NSLocalizedStringFromTableInBundle(@"Cancel", @"OmniUI", OMNI_BUNDLE, @"cancel button title")];
    [_actionSheetActions addObject:NSStringFromSelector(@selector(actionSheetCancel:))]; // Not really an action, part of the delegate API that gets called when tapping outside the popover on iPad (and you have a cancel button define, which we don't).
    
    OBASSERT(sender == _deleteButton); // If not, we'll be popping this up from the wrong place
    [actionSheet showFromRect:[_deleteButton frame] inView:[_deleteButton superview] animated:YES];
    
    _nonretainedActionSheet = actionSheet;
}

- (IBAction)export:(id)sender;
{
    OUIDocumentProxy *proxy = _previewScrollView.proxyClosestToCenter;
    if (!proxy) {
        OBASSERT_NOT_REACHED("Make this button be disabled");
        return;
    }
    
    NSURL *url = proxy.url;
    if (url == nil)
        return;

    UIActionSheet *actionSheet = [[[UIActionSheet alloc] initWithTitle:nil delegate:self cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles:nil] autorelease];
    [_actionSheetActions release];
    _actionSheetActions = [[NSMutableArray alloc] init];

    BOOL canMakePDF = [_nonretained_delegate respondsToSelector:@selector(documentPicker:PDFDataForProxy:error:)];
    BOOL canMakeImage = [_nonretained_delegate respondsToSelector:@selector(documentPicker:cameraRollImageForProxy:)];
    
    if ([MFMailComposeViewController canSendMail]) {
        // All email options should go here (within the test for whether we can send email)

        [actionSheet addButtonWithTitle:NSLocalizedStringFromTableInBundle(@"Send via Mail", @"OmniUI", OMNI_BUNDLE, @"Menu option in the document picker view")];
        [_actionSheetActions addObject:NSStringFromSelector(@selector(emailDocument:))];

        if (canMakePDF) {
            [actionSheet addButtonWithTitle:NSLocalizedStringFromTableInBundle(@"Send PDF via Mail", @"OmniUI", OMNI_BUNDLE, @"Menu option in the document picker view")];
            [_actionSheetActions addObject:NSStringFromSelector(@selector(emailPDF:))];
        }
    }
    
    if (canMakePDF || canMakeImage) {
        [actionSheet addButtonWithTitle:NSLocalizedStringFromTableInBundle(@"Copy as Image", @"OmniUI", OMNI_BUNDLE, @"Menu option in the document picker view")];
        [_actionSheetActions addObject:NSStringFromSelector(@selector(copyAsImage:))];
    }
    
    if (canMakeImage) {
        [actionSheet addButtonWithTitle:NSLocalizedStringFromTableInBundle(@"Send to Photos", @"OmniUI", OMNI_BUNDLE, @"Menu option in the document picker view")];
        [_actionSheetActions addObject:NSStringFromSelector(@selector(sendToCameraRoll:))];
    }

    OBASSERT(sender == _exportButton); // If not, we'll be popping this up from the wrong place
    [actionSheet showFromRect:[_exportButton frame] inView:[_exportButton superview] animated:YES];
    
    _nonretainedActionSheet = actionSheet;
}

- (IBAction)emailDocument:(id)sender;
{
    OUIDocumentProxy *documentProxy = _previewScrollView.selectedProxy;
    if (!documentProxy) {
        OBASSERT_NOT_REACHED("button should have been disabled");
        return;
    }

    NSURL *documentURL = [documentProxy url];

    NSString *documentExtension = [[documentURL path] pathExtension];
    NSString *documentType = [(NSString *)UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, (CFStringRef)documentExtension, NULL) autorelease];
    OBASSERT(documentType != nil); // UTI should be registered in the Info.plist under CFBundleDocumentTypes
    NSData *documentData = [NSData dataWithContentsOfURL:documentURL];
    NSString *documentFilename = [[documentURL path] lastPathComponent];

    [self _sendEmailWithSubject:[documentProxy name] attachmentName:documentFilename data:documentData fileType:documentType];
}

- (void)emailPDF:(id)sender;
{
    OUIDocumentProxy *documentProxy = _previewScrollView.selectedProxy;
    if (!documentProxy) {
        OBASSERT_NOT_REACHED("button should have been disabled");
        return;
    }
    
    NSError *error = nil;
    NSData *pdfData = [_nonretained_delegate documentPicker:self PDFDataForProxy:documentProxy error:&error];
    if (!pdfData) {
        OUI_PRESENT_ERROR(error);
        return;
    }
    
    NSString *documentFilename = [[documentProxy.url path] lastPathComponent];
    NSString *pdfFilename = [[documentFilename stringByDeletingPathExtension] stringByAppendingPathExtension:@"pdf"];

    [self _sendEmailWithSubject:[documentProxy name] attachmentName:pdfFilename data:pdfData fileType:(NSString *)kUTTypePDF];
}

- (void)copyAsImage:(id)sender;
{
    OUIDocumentProxy *documentProxy = _previewScrollView.selectedProxy;
    if (!documentProxy) {
        OBASSERT_NOT_REACHED("button should have been disabled");
        return;
    }

    UIPasteboard *pboard = [UIPasteboard generalPasteboard];
    NSMutableArray *items = [NSMutableArray array];
    
    BOOL canMakePDF = [_nonretained_delegate respondsToSelector:@selector(documentPicker:PDFDataForProxy:error:)];
    BOOL canMakeImage = [_nonretained_delegate respondsToSelector:@selector(documentPicker:cameraRollImageForProxy:)];

    if (canMakeImage) {
        UIImage *image = [self _cameraRollImageForProxy:documentProxy];
        if (image) {
            // -setImage: will register our image as being for the JPEG type. But, our image isn't a photo.
            [items addObject:[NSDictionary dictionaryWithObject:image forKey:(id)kUTTypePNG]];
        }
    }
    
    // -setImage: also puts a title on the pasteboard, so we might as well. They append .jpg, but it isn't clear whether we should append .pdf or .png. Appending nothing.
    NSString *title = [documentProxy name];
    if (![NSString isEmptyString:title])
        [items addObject:[NSDictionary dictionaryWithObject:title forKey:(id)kUTTypeUTF8PlainText]];
    
    if (canMakePDF) {
        NSError *error = nil;
        NSData *pdfData = [_nonretained_delegate documentPicker:self PDFDataForProxy:documentProxy error:&error];
        if (!pdfData)
            OUI_PRESENT_ERROR(error);
        else
            [items addObject:[NSDictionary dictionaryWithObject:pdfData forKey:(id)kUTTypePDF]];
    }
    
    if ([items count] > 0)
        pboard.items = items;
    else
        OBASSERT_NOT_REACHED("No items?");
}

- (void)sendToCameraRoll:(id)sender;
{
    OUIDocumentProxy *documentProxy = _previewScrollView.selectedProxy;
    if (!documentProxy) {
        OBASSERT_NOT_REACHED("button should have been disabled");
        return;
    }

    UIImage *image = [self _cameraRollImageForProxy:documentProxy];

    if (image)
        UIImageWriteToSavedPhotosAlbum(image, self, @selector(_sendToCameraRollImage:didFinishSavingWithError:contextInfo:), NULL);
}

- (void)_sendToCameraRollImage:(UIImage *)image didFinishSavingWithError:(NSError *)error contextInfo:(void *)contextInfo;
{
    OUI_PRESENT_ERROR(error);
}

#pragma mark -
#pragma mark UIViewController subclass

- (void)viewDidLoad;
{
    [super viewDidLoad];
    
    // We want the scroll view of documents to be touchable over the whole screen, but not have the previews overlap the title and stuff.
    CGRect viewBounds = self.view.bounds;
    _previewScrollView.bottomGap = CGRectGetHeight(viewBounds) - CGRectGetHeight(_previewScrollView.frame);
    _previewScrollView.frame = viewBounds;
    
    if (_directory) {
        [self _setupProxiesBinding];
        [self _loadProxies];
    }
}

- (void)viewDidUnload;
{
    [super viewDidUnload];
    
    [_previewScrollView release];
    _previewScrollView = nil;
    
    [_titleLabel release];
    _titleLabel = nil;

    [_dateLabel release];
    _dateLabel = nil;
    
    [_buttonGroupView release];
    _buttonGroupView = nil;
    
    [_favoriteButton release];
    _favoriteButton = nil;
    
    [_exportButton release];
    _exportButton = nil;
    
    [_newDocumentButton release];
    _newDocumentButton = nil;
    
    [_deleteButton release];
    _deleteButton = nil;
    
    [_proxiesBinding invalidate];
    [_proxiesBinding release];
    _proxiesBinding = nil;

    [_proxies release];
    _proxies = nil;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation;
{
    return YES;
}

- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration;
{
    [super willRotateToInterfaceOrientation:toInterfaceOrientation duration:duration];
    
    _selectedProxyBeforeOrientationChange = [[_previewScrollView selectedProxy] retain];
    [_previewScrollView willRotate];
    
    if (_nonretainedActionSheet) {
        OBASSERT([_nonretainedActionSheet isKindOfClass:[UIActionSheet class]]);
        [_nonretainedActionSheet dismissWithClickedButtonIndex:-1 animated:NO];
        _nonretainedActionSheet = nil;
    }
}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation;
{
    if (_selectedProxyBeforeOrientationChange) {
        [_previewScrollView snapToProxy:_selectedProxyBeforeOrientationChange animated:NO];
        [_selectedProxyBeforeOrientationChange release];
        _selectedProxyBeforeOrientationChange = nil;
    }
    
    [_previewScrollView didRotate];

    [super didRotateFromInterfaceOrientation:fromInterfaceOrientation];
}

#pragma mark -
#pragma mark UIActionSheetDelegate

- (void)actionSheetCancel:(UIActionSheet *)actionSheet;
{
    // Nothing. Cleanup done in the dismiss hook.
}

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex;
{
    // -1 means cancel (clicked out) if you don't have a cancel item
    if (buttonIndex >= 0 && buttonIndex != [actionSheet cancelButtonIndex]) {
        NSString *actionString = [_actionSheetActions objectAtIndex:buttonIndex];
        [self performSelector:NSSelectorFromString(actionString) withObject:actionSheet];
    }
    
    // cleanup done in dismiss below.
}

- (void)actionSheet:(UIActionSheet *)actionSheet didDismissWithButtonIndex:(NSInteger)buttonIndex;  // after animation
{
    [_actionSheetActions release];
    _actionSheetActions = nil;
    
    _nonretainedActionSheet = nil;
}

#pragma mark -
#pragma mark MFMailComposeViewControllerDelegate

- (void)mailComposeController:(MFMailComposeViewController *)controller didFinishWithResult:(MFMailComposeResult)result error:(NSError *)error;
{
    [[[OUIAppController controller] topViewController] dismissModalViewControllerAnimated:YES];
}

#pragma mark -
#pragma mark OUIDocumentPickerViewDelegate

- (void)documentPickerView:(OUIDocumentPickerView *)pickerView didSelectProxy:(OUIDocumentProxy *)proxy;
{
    if (!proxy) {
        _titleLabel.hidden = YES;
        _dateLabel.hidden = YES;
    } else {
        _titleLabel.hidden = NO;
        _dateLabel.hidden = NO;
    }
    
    _titleLabel.text = [proxy name];
    _dateLabel.text = [self _dateStringForDocumentProxy:proxy];

    _exportButton.enabled = (proxy != nil);
    _favoriteButton.enabled = (proxy != nil);
    _deleteButton.enabled = [self canEditProxy:proxy];

    if ([_nonretained_delegate respondsToSelector:@selector(documentPicker:didSelectProxy:)])
        [_nonretained_delegate documentPicker:self didSelectProxy:proxy];
}

#pragma mark -
#pragma mark UIViewController (OUIToolbarViewControllerExtensions)

- (UIView *)prepareToResignInnerToolbarControllerAndReturnParentViewForActivityIndicator:(OUIToolbarViewController *)toolbarViewController;
{
    [self view];
    
    _addPushAndFadeAnimations(self, YES/*fade*/, AnimateTitleAndButtons);
    
//    [self.view.window layoutIfNeeded];
//    [CATransaction flush];
    
    return _titleLabel;
}

- (void)willResignInnerToolbarController:(OUIToolbarViewController *)toolbarViewController animated:(BOOL)animated;
{
    if (_nonretainedActionSheet) {
        OBASSERT([_nonretainedActionSheet isKindOfClass:[UIActionSheet class]]);
        [_nonretainedActionSheet dismissWithClickedButtonIndex:-1 animated:NO];
        _nonretainedActionSheet = nil;
    }
    
    if (animated) {
        _addPushAndFadeAnimations(self, YES/*fade*/, AnimateNeighborProxies);

        // Tell our proxy list  to stop doing layout while we are animating.
        self.previewScrollView.disableLayout = YES;
        PICKER_DEBUG(@"LAYOUT DISABLED");
    }

    [super willResignInnerToolbarController:toolbarViewController animated:animated];
}

- (void)didResignInnerToolbarController:(OUIToolbarViewController *)toolbarViewController;
{
    [super didResignInnerToolbarController:toolbarViewController];
    
    // OK for us to do layout again.
    PICKER_DEBUG(@"LAYOUT ENABLED");
    self.previewScrollView.disableLayout = NO;
}

- (void)willBecomeInnerToolbarController:(OUIToolbarViewController *)toolbarViewController animated:(BOOL)animated;
{
    // Necessary if the device has been rotated while we weren't on screen.
    [self.previewScrollView snapToProxy:self.previewScrollView.proxyClosestToCenter animated:NO];
    [self.view layoutIfNeeded];

    // The set of proxies might change so we can't just do right left here for removing old animations.
    [self.view.layer recursivelyRemoveAnimationForKey:PositionAdjustAnimation];
    
    if (animated) {
        _addPushAndFadeAnimations(self, NO/*fade*/, AnimateTitleAndButtons);
        _addPushAndFadeAnimations(self, NO/*fade*/, AnimateNeighborProxies);

        // Tell our proxy list  to stop doing layout while we are animating.
        self.previewScrollView.disableLayout = YES;
        PICKER_DEBUG(@"LAYOUT DISABLED");
    }
    
    [super willBecomeInnerToolbarController:toolbarViewController animated:animated];

}

- (void)didBecomeInnerToolbarController:(OUIToolbarViewController *)toolbarViewController;
{
    [super didBecomeInnerToolbarController:toolbarViewController];
    
    // OK for us to do layout again.
    PICKER_DEBUG(@"LAYOUT ENABLED");
    self.previewScrollView.disableLayout = NO;
}

- (BOOL)isEditingViewController;
{
    return NO;
}

#pragma mark -
#pragma mark UIDocumentInteractionControllerDelegate

- (UIViewController *)documentInteractionControllerViewControllerForPreview:(UIDocumentInteractionController *)controller;
{
    NSLog(@"%s", __PRETTY_FUNCTION__);
    return nil;
}

- (CGRect)documentInteractionControllerRectForPreview:(UIDocumentInteractionController *)controller;
{
    NSLog(@"%s", __PRETTY_FUNCTION__);
    return CGRectZero;
}

- (UIView *)documentInteractionControllerViewForPreview:(UIDocumentInteractionController *)controller;
{
    NSLog(@"%s", __PRETTY_FUNCTION__);
    return nil;
}

- (BOOL)documentInteractionController:(UIDocumentInteractionController *)controller canPerformAction:(SEL)action;
{
    NSLog(@"%s %@", __PRETTY_FUNCTION__, NSStringFromSelector(action));
    return NO;
}
- (BOOL)documentInteractionController:(UIDocumentInteractionController *)controller performAction:(SEL)action;
{
    NSLog(@"%s %@", __PRETTY_FUNCTION__, NSStringFromSelector(action));

    if (action == @selector(copy:))
        return YES;
    return NO;
}

#pragma mark -
#pragma mark Private

static NSDate *_day(NSDate *date)
{
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSDateComponents *components = [calendar components:NSYearCalendarUnit|NSMonthCalendarUnit|NSDayCalendarUnit fromDate:date];
    return [calendar dateFromComponents:components];
}

static NSDate *_dayOffset(NSDate *date, NSInteger offset)
{
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSDateComponents *components = [[NSDateComponents alloc] init];
    [components setDay:offset];
    NSDate *result = [calendar dateByAddingComponents:components toDate:date options:0];
    [components release];
    return result;
}

- (NSString *)_dateStringForDocumentProxy:(OUIDocumentProxy *)proxy;
{
    static NSDateFormatter *dateFormatter = nil;
    static NSDateFormatter *timeFormatter = nil;


    if (!dateFormatter) {
        dateFormatter = [[NSDateFormatter alloc] init];
        [dateFormatter setDateStyle:NSDateFormatterFullStyle];
        [dateFormatter setTimeStyle:NSDateFormatterNoStyle];
        
        timeFormatter = [[NSDateFormatter alloc] init];
        [timeFormatter setDateStyle:NSDateFormatterNoStyle];
        [timeFormatter setTimeStyle:NSDateFormatterShortStyle];
    }
    
    NSDate *today = _day([NSDate date]);
    NSDate *yesterday = _dayOffset(today, -1);
    
    NSDate *day = _day(proxy.date);
    
    //NSDate *day = _day([NSDate dateWithTimeIntervalSinceNow:-1000000]);
    //NSDate *day = _day([NSDate dateWithTimeIntervalSinceNow:-86400]);
    //NSDate *day = today;
    
    if ([day isEqualToDate:today]) {
        NSString *dayFormat = NSLocalizedStringWithDefaultValue(@"Today, %@ <day name>", @"OmniUI", OMNI_BUNDLE, @"Today, %@", @"time display format for today");
        NSString *timePart = [timeFormatter stringFromDate:proxy.date];
        return [NSString stringWithFormat:dayFormat, timePart];
    } else if ([day isEqualToDate:yesterday]) {
        NSString *dayFormat = NSLocalizedStringWithDefaultValue(@"Yesterday, %@ <day name>", @"OmniUI", OMNI_BUNDLE, @"Yesterday, %@", @"time display format for yesterday");
        NSString *timePart = [timeFormatter stringFromDate:proxy.date];
        return [NSString stringWithFormat:dayFormat, timePart];
    } else {
        return [dateFormatter stringFromDate:day];
    }    
}

+ (BOOL)_canViewTypeWithIdentifier:(NSString *)uti;
{
    if (uti == nil)
        return NO;

    static NSMutableDictionary *contentTypeRoles = nil;
    if (contentTypeRoles == nil) {
        // Make a fast index of all our declared UTIs
        contentTypeRoles = [[NSMutableDictionary alloc] init];
        NSArray *documentTypes = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleDocumentTypes"];
        for (NSDictionary *documentType in documentTypes) {
            NSString *role = [documentType objectForKey:@"CFBundleTypeRole"];
            NSArray *contentTypes = [documentType objectForKey:@"LSItemContentTypes"];
            for (NSString *contentType in contentTypes)
                [contentTypeRoles setObject:role forKey:[contentType lowercaseString]];
        }
    }
    NSString *role = [contentTypeRoles objectForKey:uti];
    if (role == nil)
        return NO;

    OBASSERT([role isEqualToString:@"Editor"] || [role isEqualToString:@"Viewer"]); // Otherwise why did we bother declaring it? And the next statement is wrong
    return YES;
}

- (void)_loadProxies;
{
    // Need to know both where to scan and what class of proxies to make
    if (!_directory || !_nonretained_delegate)
        return;
    
    PICKER_DEBUG(@"Scanning %@", _directory);
    
    // TODO: Allow a scan to happen with search criteria (favorites/search).
    // TODO: Need to filter out things that aren't documents. Should probably have a list of file types (UTIs or extensions if that doesn't work).
    // TODO: Allow setting whether we recurse into Documents/Shared? Or just do it?

    // Build an index of the old groups and the union of all the old proxies
    NSMutableDictionary *urlToExistingProxy = [NSMutableDictionary dictionary];
    for (OUIDocumentProxy *proxy in _proxies) {
        OBASSERT([urlToExistingProxy objectForKey:proxy.url] == nil);
        [urlToExistingProxy setObject:proxy forKey:proxy.url];
    }
    //NSLog(@"urlToExistingProxy = %@", urlToExistingProxy);
    
    // Scan the existing documents directory, reusing proxies when possible
    NSMutableSet *updatedProxies = [NSMutableSet set];
    {
        //NSLog(@"today %@", today);
        //NSLog(@"yesterday %@", yesterday);
        
        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSMutableArray *scanDirectories = [NSMutableArray arrayWithObject:_directory];
        while ([scanDirectories count] != 0) {
            NSString *scanDirectory = [scanDirectories lastObject]; // We're building a set, and it's faster to remove the last object than the first
            [scanDirectories removeLastObject];
            NSArray *fileNames = [fileManager directoryContentsAtPath:scanDirectory];
            for (NSString *fileName in fileNames) {
                NSString *fileExtension = [fileName pathExtension];
                NSString *uti = [(NSString *)UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, (CFStringRef)fileExtension, NULL) autorelease];
                NSString *filePath = [scanDirectory stringByAppendingPathComponent:fileName];

                if (![OUIDocumentPicker _canViewTypeWithIdentifier:uti]) {
                    if ([fileManager directoryExistsAtPath:filePath traverseLink:YES])
                        [scanDirectories addObject:filePath];
                    continue;
                }
                
                NSURL *fileURL = [NSURL fileURLWithPath:filePath];
                OUIDocumentProxy *proxy = [urlToExistingProxy objectForKey:fileURL];
                if (proxy) {
                    [urlToExistingProxy removeObjectForKey:fileURL]; // mark this as used
                    //NSLog(@"  reused proxy %@ for %@", proxy, fileURL);
                } else {
                    proxy = [self _makeProxyForURL:fileURL];
                }
                if (proxy)
                    [updatedProxies addObject:proxy];
            }
        }
    }
    
    // Any proxies we had before that we didn't re-use have gone missing (deleted or filtered out) and we should remove them.
    if ([self isViewLoaded]) {
        NSArray *proxiesToRemove = [urlToExistingProxy allValues];
        for (OUIDocumentProxy *proxy in proxiesToRemove)
            [proxy invalidate];
    }
    
    BOOL proxiesChanged = OFNOTEQUAL(_proxies, updatedProxies);
    if (proxiesChanged) {
        [self willChangeValueForKey:ProxiesBinding];
        [_proxies release];
        _proxies = [[NSSet alloc] initWithSet:updatedProxies];
        [self didChangeValueForKey:ProxiesBinding];

    }

    if ([self isViewLoaded])
        [self _setupProxiesBinding];
    
    if ([_nonretained_delegate respondsToSelector:@selector(documentPicker:scannedProxies:)])
        [_nonretained_delegate documentPicker:self scannedProxies:_proxies];
}

- (OUIDocumentProxy *)_makeProxyForURL:(NSURL *)fileURL;
{
    // This assumes that the choice of proxy class is consistent for each URL (since we will reuse proxies).  Could double-check in this loop that the existing proxy has the right class if we ever want this to be dynamic.
    Class proxyClass = [_nonretained_delegate documentPicker:self proxyClassForURL:fileURL];
    if (!proxyClass) {
        // We have a UTI for this, but the delegate doesn't want it to show up in the listing (OmniGraffle templates, for example).
        return nil;
    }
    OBASSERT(OBClassIsSubclassOfClass(proxyClass, [OUIDocumentProxy class]));
    
    OUIDocumentProxy *proxy = [[[proxyClass alloc] initWithURL:fileURL] autorelease];
    proxy.target = self;
    proxy.action = @selector(_documentProxyTapped:);
    //NSLog(@"  made new proxy %@ for %@", proxy, fileURL);
    return proxy;
}

- (void)_setupProxiesBinding;
{
    if (_proxiesBinding && [_proxiesBinding destinationPoint].object == _previewScrollView)
        return;
    
    _proxiesBinding = [[OFSetBinding alloc] initWithSourcePoint:OFBindingPointMake(self, ProxiesBinding)
                                               destinationPoint:OFBindingPointMake(_previewScrollView, OUIDocumentPickerViewProxiesBinding)];
    [_proxiesBinding propagateCurrentValue];
}

- (void)_documentProxyTapped:(OUIDocumentProxy *)proxy;
{
    // Tapping the selected proxy opens it. Otherwise, we want to scroll it into view.
    if (proxy == _previewScrollView.selectedProxy)
        [_proxyTappedTarget performSelector:_proxyTappedAction withObject:proxy];
    else
        [_previewScrollView snapToProxy:proxy animated:YES];
}

- (void)_sendEmailWithSubject:(NSString *)subject attachmentName:(NSString *)attachmentFileName data:(NSData *)attachmentData fileType:(NSString *)fileType;
{
    NSString *mimeType = [(NSString *)UTTypeCopyPreferredTagWithClass((CFStringRef)fileType, kUTTagClassMIMEType) autorelease];
    OBASSERT(mimeType != nil); // The UTI's mime type should be registered in the Info.plist under UTExportedTypeDeclarations:UTTypeTagSpecification
    if (mimeType == nil)
        mimeType = @"application/octet-stream";
#ifdef DEBUG_kc
    NSLog(@"Sending email with %@ attachment (%@)", mimeType, subject);
#endif
    
    
    MFMailComposeViewController *controller = [[MFMailComposeViewController alloc] init];
    controller.navigationBar.barStyle = UIBarStyleBlack;
    controller.mailComposeDelegate = self;
    [controller setSubject:subject];
    [controller addAttachmentData:attachmentData mimeType:mimeType fileName:attachmentFileName];
    [[[OUIAppController controller] topViewController] presentModalViewController:controller animated:YES];
    [controller autorelease];
}

- (UIImage *)_cameraRollImageForProxy:(OUIDocumentProxy *)documentProxy;
{
    UIImage *image = [_nonretained_delegate documentPicker:self cameraRollImageForProxy:documentProxy];
    if (!image) {
        // Use the default behavior of drawing the document's preview.
        OUIDocumentProxyView *proxyView = (OUIDocumentProxyView *)documentProxy.view;
        
        CGSize maxSize = self.view.window.bounds.size; // This is the portrait size always
        if (UIDeviceOrientationIsLandscape([[UIDevice currentDevice] orientation]))
            SWAP(maxSize.width, maxSize.height);
        
        UIImage *result = nil;
        id <OUIDocumentPreview> preview = proxyView.preview;
        
        if ([preview isKindOfClass:[OUIDocumentPDFPreview class]]) {
            OUIDocumentPDFPreview *pdfPreview = (OUIDocumentPDFPreview *)preview;

            CGRect maxBounds = CGRectMake(0, 0, maxSize.width, maxSize.height);
            
            CGAffineTransform xform = [pdfPreview transformForTargetRect:maxBounds];
            CGRect paperRect = pdfPreview.untransformedPageRect;
            CGRect transformedTarget = CGRectApplyAffineTransform(paperRect, xform);

            UIGraphicsBeginImageContext(transformedTarget.size);
            {
                CGContextRef ctx = UIGraphicsGetCurrentContext();
                
                OQFlipVerticallyInRect(ctx, CGRectMake(0, 0, transformedTarget.size.width, transformedTarget.size.height)); // flip w/in the image
                CGContextTranslateCTM(ctx, -transformedTarget.origin.x, -transformedTarget.origin.y); // the sizing transform centers us in the original rect we gave, but we ended up giving a smaller rect to just fit the content.
                CGContextConcatCTM(ctx, xform); // size the page to the target rect we wanted

                // Fill the background with white in case the PDF doesn't have an embedded background color.
                CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceGray();
                CGFloat whiteComponents[] = {1.0, 1.0};
                CGColorRef white = CGColorCreate(colorSpace, whiteComponents);
                CGContextSetFillColorWithColor(ctx, white);
                CGColorRelease(white);
                CGColorSpaceRelease(colorSpace);
                CGContextFillRect(ctx, paperRect);
                
                // the PDF is happy to draw outside its page rect.
                CGContextAddRect(ctx, paperRect);
                CGContextClip(ctx);
                    
                [pdfPreview drawInTransformedContext:ctx];

                result = UIGraphicsGetImageFromCurrentImageContext();
            }
            UIGraphicsEndImageContext();
        } else {
            result = preview.cachedImage;
        }
        
        image = result;
    }
    
    return image;
}

typedef struct {
    OUIDocumentProxy *deleteProxy;
    NSURL *nextProxyURL;
} DeleteProxyContext;

- (void)_deleteWithoutConfirmation;
{
    NSError *error = nil;
    OUIDocumentProxy *deleteProxy = _previewScrollView.selectedProxy;
    OUIDocumentProxy *nextProxy = [_previewScrollView proxyToRightOfProxy:deleteProxy];
    if (nextProxy == nil)
        nextProxy = [_previewScrollView proxyToLeftOfProxy:deleteProxy];
    if (![self deleteDocumentWithoutPrompt:deleteProxy error:&error]) {
        OUI_PRESENT_ERROR(error);
        return;
    }
    
    DeleteProxyContext *ctx = calloc(1, sizeof(*ctx));
    ctx->deleteProxy = [deleteProxy retain];
    ctx->nextProxyURL = [nextProxy.url retain];
    
    [UIView beginAnimations:@"deleting document" context:ctx];
    [UIView setAnimationDuration:0.3];
    [UIView setAnimationDelegate:self];
    [UIView setAnimationCurve:UIViewAnimationCurveEaseIn];
    [UIView setAnimationDidStopSelector:@selector(_deleteDocumentAnimationDidStop:finished:context:)];
    {
        deleteProxy.view.alpha = 0;

        CGRect frame = deleteProxy.view.frame;
        frame.origin.y += frame.size.height;
        deleteProxy.view.frame = frame;
    }
    
    [UIView commitAnimations];
}

- (void)_deleteDocumentAnimationDidStop:(NSString *)animationID finished:(NSNumber *)finished context:(void *)context;
{
    DeleteProxyContext *ctx = context;
    
    // Hide the view (OUIDocumentPicker will unhide when it reuses the view) and restore the alpha for the next user.
    OBASSERT(ctx->deleteProxy.view != nil);
    ctx->deleteProxy.view.hidden = YES;
    ctx->deleteProxy.view.alpha = 1;
    
    [UIView beginAnimations:@"delete document slide" context:ctx];
    [UIView setAnimationDuration:0.3];
    [UIView setAnimationCurve:UIViewAnimationCurveEaseIn];
    {
        [self rescanDocumentsScrollingToURL:ctx->nextProxyURL];
    }
    [UIView commitAnimations];
    
    OBASSERT(ctx->deleteProxy.view == nil);
    
    [ctx->nextProxyURL release];
    [ctx->deleteProxy release];
    free(ctx);
}


@end

