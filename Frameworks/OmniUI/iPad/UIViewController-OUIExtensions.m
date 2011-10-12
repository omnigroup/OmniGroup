// Copyright 2010-2011 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniBase/OBUtilities.h>
#import "UIViewController-OUIExtensions.h"

RCS_ID("$Id$");

#ifdef DEBUG_correia
    #define DEBUG_VIEW_CONTROLLER_EXTESIONS
#endif

static void (*original_viewWillAppear)(id self, SEL _cmd, BOOL animated) = NULL;
static void (*original_viewDidAppear)(id self, SEL _cmd, BOOL animated) = NULL;
static void (*original_viewWillDisappear)(id self, SEL _cmd, BOOL animated) = NULL;
static void (*original_viewDidDisappear)(id self, SEL _cmd, BOOL animated) = NULL;
static void (*original_presentModalViewControllerAnimated)(id self, SEL _cmd, UIViewController *viewController, BOOL animated) = NULL;
static void (*original_dismissModalViewControllerAnimated)(id self, SEL _cmd, BOOL animated) = NULL;

const NSTimeInterval OUIViewControllerExtraModalViewControllerPollInterval = 0.05;

@class OUIViewControllerExtra;

@interface UIViewController (OUIExtensionsPrivate)

+ (OUIViewControllerExtra *)viewControllerExtraForInstance:(UIViewController *)instance;
+ (void)setViewControllerExtra:(OUIViewControllerExtra *)extra forInstance:(UIViewController *)instance;

@property (nonatomic, readonly) OUIViewControllerExtra *viewControllerExtra;

- (void)replacement_viewWillAppear:(BOOL)animated;
- (void)replacement_viewDidAppear:(BOOL)animated;

- (void)replacement_viewWillDisappear:(BOOL)animated;
- (void)replacement_viewDidDisappear:(BOOL)animated;

- (void)replacement_presentModalViewController:(UIViewController *)viewController animated:(BOOL)animated;
- (void)replacement_dismissModalViewControllerAnimated:(BOOL)animated;

- (void)OUI_processModalViewControllerQueue;
- (void)OUI_checkForQueuedModalViewControllers;

@end

#ifdef DEBUG_VIEW_CONTROLLER_EXTESIONS

static NSString * NSStringFromOUIViewControllerState(OUIViewControllerState state)
{
    switch (state) {
        case OUIViewControllerStateOffscreen:
            return @"OUIViewControllerStateOffscreen";

        case OUIViewControllerStateAppearing:
            return @"OUIViewControllerStateAppearing";

        case OUIViewControllerStateDisappearing:
            return @"OUIViewControllerStateDisappearing";

        case OUIViewControllerStateOnscreen:
            return @"OUIViewControllerStateOnscreen";
    }

    OBASSERT_NOT_REACHED("Unknown OUIViewControllerState enum.");
    return nil;
}

#endif

#pragma mark -

@interface OUIViewControllerExtra : NSObject {
  @private
     UIViewController *_owner;
     OUIViewControllerState _viewControllerState;
     BOOL _dismissingModalViewControllerAnimated;
     NSMutableArray *_modalViewControllerQueue;
}

- (id)initWithViewController:(UIViewController *)viewController;

@property (nonatomic, readonly) UIViewController *owner;
@property (nonatomic) OUIViewControllerState viewControllerState;
@property (nonatomic, getter=isDismissingModalViewControllerAnimated) BOOL dismissingModalViewControllerAnimated;

- (void)enqueuePresentModalViewController:(UIViewController *)viewController animated:(BOOL)animated;
- (UIViewController *)dequeueModalViewControllerShouldPresentAnimated:(BOOL *)outPresentAnimated;

@end

#pragma mark -

@implementation UIViewController (OUIExtensions)

+ (void)performPosing;
{
    [self installOUIViewControllerExtensions];
}

+ (void)installOUIViewControllerExtensions;
{
    static BOOL _installed = NO;
    if (_installed)
        return;
    
    _installed = YES;

    original_viewWillAppear = (typeof(original_viewWillAppear))OBReplaceMethodImplementationWithSelector(self, @selector(viewWillAppear:), @selector(replacement_viewWillAppear:));
    original_viewDidAppear = (typeof(original_viewDidAppear))OBReplaceMethodImplementationWithSelector(self, @selector(viewDidAppear:), @selector(replacement_viewDidAppear:));

    original_viewWillDisappear = (typeof(original_viewWillDisappear))OBReplaceMethodImplementationWithSelector(self, @selector(viewWillDisappear:), @selector(replacement_viewWillDisappear:));
    original_viewDidDisappear = (typeof(original_viewDidDisappear))OBReplaceMethodImplementationWithSelector(self, @selector(viewDidDisappear:), @selector(replacement_viewDidDisappear:));

    original_presentModalViewControllerAnimated = (typeof(original_presentModalViewControllerAnimated))OBReplaceMethodImplementationWithSelector(self, @selector(presentModalViewController:animated:), @selector(replacement_presentModalViewController:animated:));
    original_dismissModalViewControllerAnimated = (typeof(original_dismissModalViewControllerAnimated))OBReplaceMethodImplementationWithSelector(self, @selector(dismissModalViewControllerAnimated:), @selector(replacement_dismissModalViewControllerAnimated:));
}

- (void)enqueuePresentModalViewController:(UIViewController *)viewController animated:(BOOL)animated;
{
    OBPRECONDITION(viewController);
    
    if (self.OUI_viewControllerState != OUIViewControllerStateOnscreen) {
        [[self viewControllerExtra] enqueuePresentModalViewController:viewController animated:animated];
    } else {
        [self presentModalViewController:viewController animated:animated];
    }
}

- (BOOL)OUI_defaultShouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation;
{
    // iPad default
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad)
        return YES;
    
    return interfaceOrientation != UIInterfaceOrientationPortraitUpsideDown;
}

#pragma mark -

- (UIViewController *)modalParentViewController;
{
    // What we really want here is the view controller which presented us, which iOS 5 happy tells us
    
    if ([self respondsToSelector:@selector(presentingViewController)])
        return self.presentingViewController;
    
    // Otherwise on iOS 4 and earlier, we do it the hard way by walking the parent view controller chain

    UIViewController *modalParent = self.parentViewController;

    do {
        if (modalParent.modalViewController != nil)
            return modalParent;
    } while (nil != (modalParent = modalParent.parentViewController));

    return nil;
}

- (OUIViewControllerState)OUI_viewControllerState;
{
    OUIViewControllerExtra *viewControllerExtra = [self viewControllerExtra];
    return viewControllerExtra.viewControllerState;
}

- (BOOL)OUI_isDismissingModalViewControllerAnimated;
{
    OUIViewControllerExtra *viewControllerExtra = [self viewControllerExtra];
    if (viewControllerExtra)
        return [viewControllerExtra isDismissingModalViewControllerAnimated];
    
    return NO;
}

@end

@implementation UIViewController (OUIExtensionsPrivate)

static void *OUIViewControllerExtraAssociatedObjectKey = &OUIViewControllerExtraAssociatedObjectKey;

+ (OUIViewControllerExtra *)viewControllerExtraForInstance:(UIViewController *)instance;
{
    return objc_getAssociatedObject(instance, OUIViewControllerExtraAssociatedObjectKey);
}

+ (void)setViewControllerExtra:(OUIViewControllerExtra *)extra forInstance:(UIViewController *)instance;
{
    OBPRECONDITION(instance != nil);
    OBPRECONDITION(extra != nil);

    objc_setAssociatedObject(instance, OUIViewControllerExtraAssociatedObjectKey, extra, OBJC_ASSOCIATION_RETAIN);
}

- (OUIViewControllerExtra *)viewControllerExtra;
{
    OUIViewControllerExtra *extra = [[self class] viewControllerExtraForInstance:self];

    if (extra == nil) {
        extra = [[[OUIViewControllerExtra alloc] initWithViewController:self] autorelease];
        [[self class] setViewControllerExtra:extra forInstance:self];
    }
    
    return extra;
}

- (void)replacement_viewWillAppear:(BOOL)animated;
{
    original_viewWillAppear(self, _cmd, animated);
    
    OUIViewControllerExtra *viewControllerExtra = [self viewControllerExtra];
    viewControllerExtra.viewControllerState = OUIViewControllerStateAppearing;
}

- (void)replacement_viewDidAppear:(BOOL)animated;
{
    original_viewDidAppear(self, _cmd, animated);

    OUIViewControllerExtra *viewControllerExtra = [self viewControllerExtra];
    viewControllerExtra.viewControllerState = OUIViewControllerStateOnscreen;
}

- (void)replacement_viewWillDisappear:(BOOL)animated;
{
    original_viewWillDisappear(self, _cmd, animated);

    OUIViewControllerExtra *viewControllerExtra = [self viewControllerExtra];
    viewControllerExtra.viewControllerState = OUIViewControllerStateDisappearing;
}

- (void)replacement_viewDidDisappear:(BOOL)animated;
{
    original_viewDidDisappear(self, _cmd, animated);

    OUIViewControllerExtra *viewControllerExtra = [self viewControllerExtra];
    viewControllerExtra.viewControllerState = OUIViewControllerStateOffscreen;
}

- (void)replacement_presentModalViewController:(UIViewController *)viewController animated:(BOOL)animated;
{
    BOOL shouldEnqueue = [self OUI_isDismissingModalViewControllerAnimated];
    
    if (shouldEnqueue) {
        OUIViewControllerExtra *viewControllerExtra = [self viewControllerExtra];
        [viewControllerExtra enqueuePresentModalViewController:viewController animated:animated];
#ifdef DEBUG_VIEW_CONTROLLER_EXTESIONS
        NSLog(@"Automatically deferring -presentModalViewController:animated: on parent controller %@ with current view state: %@", self, NSStringFromOUIViewControllerState(self.OUI_viewControllerState));
#endif
    } else {
        original_presentModalViewControllerAnimated(self, _cmd, viewController, animated);
    }
}

- (void)replacement_dismissModalViewControllerAnimated:(BOOL)animated;
{
    UIViewController *modalParent = (self.modalViewController ? self : self.modalParentViewController);
    if (modalParent && animated) {
        OUIViewControllerExtra *extra = [modalParent viewControllerExtra];
        OBASSERT(extra);
        extra.dismissingModalViewControllerAnimated = YES;
        [modalParent performSelector:@selector(OUI_checkForQueuedModalViewControllers) withObject:nil afterDelay:OUIViewControllerExtraModalViewControllerPollInterval];
#ifdef DEBUG_VIEW_CONTROLLER_EXTESIONS
        NSLog(@"Recording isDismissingModalViewControllerAnimated=YES for %p.", self);
#endif
    }

    original_dismissModalViewControllerAnimated(self, _cmd, animated);
}

- (void)OUI_processModalViewControllerQueue;
{
    OUIViewControllerExtra *viewControllerExtra = [self viewControllerExtra];
    if (viewControllerExtra.viewControllerState != OUIViewControllerStateOnscreen)
        return;

    // Dequeue and present any pending modal view controller now
    BOOL presentAnimated = NO;
    UIViewController *viewController = [viewControllerExtra dequeueModalViewControllerShouldPresentAnimated:&presentAnimated];
    if (viewController)
        [self presentModalViewController:viewController animated:presentAnimated];
}

- (void)OUI_checkForQueuedModalViewControllers;
{
    OUIViewControllerExtra *extra = [self viewControllerExtra];
    OBASSERT(extra);
    OBASSERT(extra.dismissingModalViewControllerAnimated);
    
    if (extra.dismissingModalViewControllerAnimated) {
        UIViewController *modalChildViewController = [self modalViewController];
        if (!modalChildViewController) {
            extra.dismissingModalViewControllerAnimated = NO;
            [self performSelector:@selector(OUI_processModalViewControllerQueue) withObject:nil afterDelay:0];
        } else {
            [self performSelector:_cmd withObject:nil afterDelay:OUIViewControllerExtraModalViewControllerPollInterval];
        }
    }
}

@end

#pragma mark -

@implementation OUIViewControllerExtra

- (id)init
{
    OBRejectUnusedImplementation(self, _cmd);
    [self release];
    return nil;
}

- (id)initWithViewController:(UIViewController *)viewController;
{
    self = [super init];
    if (!self)
        return nil;
    
    _owner = viewController;

    if ([_owner isViewLoaded])
        _viewControllerState = _owner.view.window ? OUIViewControllerStateOnscreen : OUIViewControllerStateOffscreen;
    else
        _viewControllerState = OUIViewControllerStateOffscreen;

    return self;
}

- (void)dealloc;
{
    [_modalViewControllerQueue release];
    [super dealloc];
}

@synthesize owner = _owner;
@synthesize viewControllerState = _viewControllerState;
@synthesize dismissingModalViewControllerAnimated = _dismissingModalViewControllerAnimated;

- (void)enqueuePresentModalViewController:(UIViewController *)viewController animated:(BOOL)animated;
{
    if (!_modalViewControllerQueue)
        _modalViewControllerQueue = [[NSMutableArray alloc] init];
        
    NSDictionary *dictionary = [NSDictionary dictionaryWithObjectsAndKeys:  
        viewController, @"viewController",
        [NSNumber numberWithBool:animated], @"animated",
        nil
    ];
    
    [_modalViewControllerQueue addObject:dictionary];
}   

- (UIViewController *)dequeueModalViewControllerShouldPresentAnimated:(BOOL *)outPresentAnimated;
{
    if (!_modalViewControllerQueue || [_modalViewControllerQueue count] == 0)
        return nil;
        
    NSDictionary *dictionary = [[[_modalViewControllerQueue objectAtIndex:0] retain] autorelease];
    [_modalViewControllerQueue removeObjectAtIndex:0];
    
    if (outPresentAnimated)
        *outPresentAnimated = [[dictionary objectForKey:@"animated"] boolValue];
    
    return [dictionary objectForKey:@"viewController"];
}

@end
