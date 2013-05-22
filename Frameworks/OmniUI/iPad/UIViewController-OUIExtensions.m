// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/UIViewController-OUIExtensions.h>

#import <OmniBase/OBUtilities.h>

RCS_ID("$Id$");

#ifdef DEBUG_correia
    #define DEBUG_VIEW_CONTROLLER_EXTESIONS
#endif

static void (*original_viewWillAppear)(id self, SEL _cmd, BOOL animated) = NULL;
static void (*original_viewDidAppear)(id self, SEL _cmd, BOOL animated) = NULL;
static void (*original_viewWillDisappear)(id self, SEL _cmd, BOOL animated) = NULL;
static void (*original_viewDidDisappear)(id self, SEL _cmd, BOOL animated) = NULL;
static void (*original_presentViewControllerAnimatedCompletion)(id self, SEL _cmd, UIViewController *viewController, BOOL animated, void (^completion)(void)) = NULL;
static void (*original_dismissViewControllerAnimatedCompletion)(id self, SEL _cmd, BOOL animated, void (^completion)(void)) = NULL;

const NSTimeInterval OUIViewControllerExtraPresentViewControllerPollInterval = 0.05;

@class OUIViewControllerExtra;

@interface UIViewController (OUIExtensionsPrivate)

+ (OUIViewControllerExtra *)viewControllerExtraForInstance:(UIViewController *)instance;
+ (void)setViewControllerExtra:(OUIViewControllerExtra *)extra forInstance:(UIViewController *)instance;

@property (nonatomic, readonly) OUIViewControllerExtra *viewControllerExtra;

- (void)replacement_viewWillAppear:(BOOL)animated;
- (void)replacement_viewDidAppear:(BOOL)animated;

- (void)replacement_viewWillDisappear:(BOOL)animated;
- (void)replacement_viewDidDisappear:(BOOL)animated;

- (void)replacement_presentViewController:(UIViewController *)viewController animated:(BOOL)animated completion:(void (^)(void))completion;
- (void)replacement_dismissViewControllerAnimated:(BOOL)animated completion:(void (^)(void))completion;

- (void)OUI_processPresentViewControllerQueue;
- (void)OUI_checkForQueuedPresentViewControllers;

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

@interface OUIPresentViewControllerRecord : NSObject
@property(nonatomic,retain) UIViewController *viewController;
@property(nonatomic,assign) BOOL animated;
@property(nonatomic,copy) void  (^completion)(void);
@end
@implementation OUIPresentViewControllerRecord
@end

@interface OUIViewControllerExtra : NSObject {
  @private
     UIViewController *_owner;
     OUIViewControllerState _viewControllerState;
     BOOL _dismissingViewControllerAnimated;
     NSMutableArray *_presentViewControllerQueue;
}

- (id)initWithViewController:(UIViewController *)viewController;

@property (nonatomic, readonly) UIViewController *owner;
@property (nonatomic) OUIViewControllerState viewControllerState;
@property (nonatomic, getter=isDismissingViewControllerAnimated) BOOL dismissingViewControllerAnimated;

- (void)enqueuePresentViewController:(UIViewController *)viewController animated:(BOOL)animated completion:(void (^)(void))completion;
- (OUIPresentViewControllerRecord *)dequeuePresentViewControllerRecord;

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

    original_presentViewControllerAnimatedCompletion = (typeof(original_presentViewControllerAnimatedCompletion))OBReplaceMethodImplementationWithSelector(self, @selector(presentViewController:animated:completion:), @selector(replacement_presentViewController:animated:completion:));
    original_dismissViewControllerAnimatedCompletion = (typeof(original_dismissViewControllerAnimatedCompletion))OBReplaceMethodImplementationWithSelector(self, @selector(dismissViewControllerAnimated:completion:), @selector(replacement_dismissViewControllerAnimated:completion:));
}

- (void)enqueuePresentViewController:(UIViewController *)viewController animated:(BOOL)animated completion:(void (^)(void))completion;
{
    OBPRECONDITION(viewController);
    
    if (self.OUI_viewControllerState != OUIViewControllerStateOnscreen) {
        [[self viewControllerExtra] enqueuePresentViewController:viewController animated:animated completion:completion];
    } else {
        [self presentViewController:viewController animated:animated completion:completion];
    }
}

#pragma mark -

- (UIViewController *)modalParentViewController;
{
    OBFinishPortingLater("Reevaluate this for iOS 6?");
    
    // What we really want here is the view controller which presented us, which iOS 5 happily tells us
    
    if ([self respondsToSelector:@selector(presentingViewController)])
        return self.presentingViewController;
    
    // Otherwise on iOS 4 and earlier, we do it the hard way by walking the parent view controller chain

    UIViewController *modalParent = self.parentViewController;

    do {
        if (modalParent.presentedViewController != nil)
            return modalParent;
    } while (nil != (modalParent = modalParent.presentedViewController));

    return nil;
}

- (OUIViewControllerState)OUI_viewControllerState;
{
    OUIViewControllerExtra *viewControllerExtra = [self viewControllerExtra];
    return viewControllerExtra.viewControllerState;
}

- (BOOL)OUI_isDismissingViewControllerAnimated;
{
    OUIViewControllerExtra *viewControllerExtra = [self viewControllerExtra];
    if (viewControllerExtra)
        return [viewControllerExtra isDismissingViewControllerAnimated];
    
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

- (void)replacement_presentViewController:(UIViewController *)viewController animated:(BOOL)animated completion:(void (^)(void))completion;
{
    BOOL shouldEnqueue = [self OUI_isDismissingViewControllerAnimated];
    
    if (shouldEnqueue) {
        OUIViewControllerExtra *viewControllerExtra = [self viewControllerExtra];
        [viewControllerExtra enqueuePresentViewController:viewController animated:animated completion:completion];
#ifdef DEBUG_VIEW_CONTROLLER_EXTESIONS
        NSLog(@"Automatically deferring -presentViewController:animated:completion: on parent controller %@ with current view state: %@", self, NSStringFromOUIViewControllerState(self.OUI_viewControllerState));
#endif
    } else {
        original_presentViewControllerAnimatedCompletion(self, _cmd, viewController, animated, completion);
    }
}

- (void)replacement_dismissViewControllerAnimated:(BOOL)animated completion:(void (^)(void))completion;
{
    UIViewController *modalParent = (self.presentedViewController ? self : self.modalParentViewController);
    if (modalParent && animated) {
        OUIViewControllerExtra *extra = [modalParent viewControllerExtra];
        OBASSERT(extra);
        extra.dismissingViewControllerAnimated = YES;
        [modalParent performSelector:@selector(OUI_checkForQueuedPresentViewControllers) withObject:nil afterDelay:OUIViewControllerExtraPresentViewControllerPollInterval];
#ifdef DEBUG_VIEW_CONTROLLER_EXTESIONS
        NSLog(@"Recording isDismissingViewControllerAnimated=YES for %p.", self);
#endif
    }

    original_dismissViewControllerAnimatedCompletion(self, _cmd, animated, completion);
}

- (void)OUI_processPresentViewControllerQueue;
{
    OUIViewControllerExtra *viewControllerExtra = [self viewControllerExtra];
    if (viewControllerExtra.viewControllerState != OUIViewControllerStateOnscreen)
        return;

    // Dequeue and present any pending view controller presentation
    OUIPresentViewControllerRecord *record = [viewControllerExtra dequeuePresentViewControllerRecord];
    if (record)
        [self presentViewController:record.viewController animated:record.animated completion:record.completion];
}

- (void)OUI_checkForQueuedPresentViewControllers;
{
    OUIViewControllerExtra *extra = [self viewControllerExtra];
    OBASSERT(extra);
    OBASSERT(extra.dismissingViewControllerAnimated);
    
    if (extra.dismissingViewControllerAnimated) {
        UIViewController *modalChildViewController = self.presentedViewController;
        if (!modalChildViewController) {
            extra.dismissingViewControllerAnimated = NO;
            [self performSelector:@selector(OUI_processPresentViewControllerQueue) withObject:nil afterDelay:0];
        } else {
            [self performSelector:_cmd withObject:nil afterDelay:OUIViewControllerExtraPresentViewControllerPollInterval];
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
    [_presentViewControllerQueue release];
    [super dealloc];
}

@synthesize owner = _owner;
@synthesize viewControllerState = _viewControllerState;
@synthesize dismissingViewControllerAnimated = _dismissingViewControllerAnimated;

- (void)enqueuePresentViewController:(UIViewController *)viewController animated:(BOOL)animated completion:(void (^)(void))completion;
{
    if (!_presentViewControllerQueue)
        _presentViewControllerQueue = [[NSMutableArray alloc] init];
        
    OUIPresentViewControllerRecord *record = [OUIPresentViewControllerRecord new];
    record.viewController = viewController;
    record.animated = animated;
    record.completion = completion;
    
    [_presentViewControllerQueue addObject:record];
}   

- (OUIPresentViewControllerRecord *)dequeuePresentViewControllerRecord;
{
    if ([_presentViewControllerQueue count] == 0)
        return nil;
    
    OUIPresentViewControllerRecord *record = [[[_presentViewControllerQueue objectAtIndex:0] retain] autorelease];
    [_presentViewControllerQueue removeObjectAtIndex:0];
    
    return record;
}

@end
