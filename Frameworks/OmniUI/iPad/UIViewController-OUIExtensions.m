// Copyright 2010-2011 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "UIViewController-OUIExtensions.h"

#import <OmniBase/OBUtilities.h>

RCS_ID("$Id$");

//#ifdef DEBUG_correia
//    #define DEBUG_VIEW_CONTROLLER_EXTESIONS
//#endif

static void (*original_dealloc)(id self, SEL _cmd) = NULL;
static void (*original_presentModalViewControllerAnimated)(id self, SEL _cmd, UIViewController *viewController, BOOL animated) = NULL;
static void (*original_dismissModalViewControllerAnimated)(id self, SEL _cmd, BOOL animated) = NULL;

static NSMutableDictionary *_extraMap;
@class OUIViewControllerExtra;
@interface UIViewController (OUIExtensionsPrivate)

+ (OUIViewControllerExtra *)extraForInstance:(UIViewController *)instance;
+ (void)setExtra:(OUIViewControllerExtra *)extra forInstance:(UIViewController *)instance;

@property (nonatomic, readonly) OUIViewControllerExtra *ouiExtra;
- (OUIViewControllerExtra *)extraCreateIfNecessary:(BOOL)createIfNecessary;

- (void)replacement_presentModalViewController:(UIViewController *)viewController animated:(BOOL)animated;
- (void)replacement_dismissModalViewControllerAnimated:(BOOL)animated;

@end

#pragma mark -

@interface OUIViewControllerExtra : NSObject {
  @private
     UIViewController *_owner;
     BOOL _dismissingModalViewControllerAnimated;
     BOOL _isPollingChildModalViewController;
     NSMutableArray *_modalViewControllerQueue;
}

- (id)initWithViewController:(UIViewController *)viewController;

@property (nonatomic, readonly) UIViewController *owner;
@property (nonatomic, getter=isDismissingModalViewControllerAnimated) BOOL dismissingModalViewControllerAnimated;

- (void)enqueueModalViewController:(UIViewController *)viewController presentAnimated:(BOOL)animated;
- (UIViewController *)dequeueModalViewControllerShouldPresentAnimated:(BOOL *)outPresentAnimated;

- (void)startPollingChildModalViewController;
- (void)pollChildModalViewControllerCallback;

@end

#pragma mark -

@implementation UIViewController (OUIExtensions)

+ (void)performPosing;
{
    [self installOUIExtensions];
}

+ (void)installOUIExtensions;
{
    static BOOL _installed = NO;
    if (_installed)
        return;
    
    _installed = YES;

    original_dealloc = (typeof(original_dealloc))OBReplaceMethodImplementationWithSelector(self, @selector(dealloc), @selector(replacement_dealloc));
    original_presentModalViewControllerAnimated = (typeof(original_presentModalViewControllerAnimated))OBReplaceMethodImplementationWithSelector(self, @selector(presentModalViewController:animated:), @selector(replacement_presentModalViewController:animated:));

    original_dismissModalViewControllerAnimated = (typeof(original_dismissModalViewControllerAnimated))OBReplaceMethodImplementationWithSelector(self, @selector(dismissModalViewControllerAnimated:), @selector(replacement_dismissModalViewControllerAnimated:));
}

- (void)enqueueModalViewController:(UIViewController *)viewController presentAnimated:(BOOL)animated;
{
    OBASSERT(viewController);
    
    if (!self.modalViewController) {
        [self presentModalViewController:viewController animated:animated];
    } else {
        [[self extraCreateIfNecessary:YES] enqueueModalViewController:viewController presentAnimated:animated];
    }
}

#pragma mark -

- (UIViewController *)modalParentViewController;
{
    UIViewController *modalParent = self.parentViewController;

    do {
        if (modalParent.modalViewController != nil)
            return modalParent;
    } while (nil != (modalParent = modalParent.parentViewController));

    return nil;
}

@end

@implementation UIViewController (OUIExtensionsPrivate)

+ (OUIViewControllerExtra *)extraForInstance:(UIViewController *)instance;
{
    // WTB objc_getAssociatedObject, but this doesn't appear in the simulator SDK headers, and is not exported.

    OBPRECONDITION(instance != nil);
    if (_extraMap == nil)
        return nil;
        
    NSValue *key = [NSValue valueWithPointer:instance];
    return [_extraMap objectForKey:key];
}

+ (void)setExtra:(OUIViewControllerExtra *)extra forInstance:(UIViewController *)instance;
{
    // WTB objc_setAssociatedObject, but this doesn't appear in the simulator SDK headers, and is not exported.

    OBPRECONDITION(instance != nil);
    NSValue *key = [NSValue valueWithPointer:instance];

    if (extra == nil) {
        [_extraMap removeObjectForKey:key];
    } else {
        if (_extraMap == nil)
            _extraMap = [[NSMutableDictionary alloc] initWithCapacity:0];
        [_extraMap setObject:extra forKey:key];
    }
}

- (OUIViewControllerExtra *)ouiExtra;
{
    return [[self class] extraForInstance:self];
}

- (OUIViewControllerExtra *)extraCreateIfNecessary:(BOOL)createIfNecessary;
{
    OUIViewControllerExtra *extra = [[self class] extraForInstance:self];

    if (extra == nil && createIfNecessary) {
        extra = [[[OUIViewControllerExtra alloc] initWithViewController:self] autorelease];
        [[self class] setExtra:extra forInstance:self];
    }
    
    return extra;
}

- (void)replacement_dealloc;
{
    [UIViewController setExtra:nil forInstance:self];

    original_dealloc(self, _cmd);
}

- (void)replacement_presentModalViewController:(UIViewController *)viewController animated:(BOOL)animated;
{
    OUIViewControllerExtra *extra = [self ouiExtra];
    if (extra && [extra isDismissingModalViewControllerAnimated]) {
#ifdef DEBUG_VIEW_CONTROLLER_EXTESIONS
        NSLog(@"Will defer -presentModalViewController:animated: for self=%p, viewController=%p; current view controller is animating out.", self, viewController);
#endif
        [extra enqueueModalViewController:viewController presentAnimated:animated];
        return;
    }
    
    if (self.modalViewController) {
        // Presenting a modal view controller on a view controller which already has a modal child view controller does not do anything.
        // Assert so we can catch and fix call sites which do this.
        OBASSERT_NOT_REACHED("Presenting modal view controller on a view controller which already has a modal child view controller.");
#ifdef DEBUG
        NSLog(@"----------\n");
        NSLog(@"Presenting modal view controller on a view controller which already has a modal child view controller.");
        NSLog(@"   Current modal view controller: %@", self.modalViewController);
        if ([self.modalViewController isKindOfClass:[UINavigationController class]])
            NSLog(@"      Top view controller: %@", [(id)self.modalViewController topViewController]);
        NSLog(@"   New modal view controller: %@", viewController);
        if ([viewController isKindOfClass:[UINavigationController class]])
            NSLog(@"      Top view controller: %@", [(id)viewController topViewController]);
        NSLog(@"----------\n");
#endif        
    }

    original_presentModalViewControllerAnimated(self, _cmd, viewController, animated);
}

- (void)replacement_dismissModalViewControllerAnimated:(BOOL)animated;
{
    UIViewController *modalParent = (self.modalViewController ? self : self.modalParentViewController);
    if (modalParent && animated) {
        OUIViewControllerExtra *extra = [modalParent extraCreateIfNecessary:YES];
        OBASSERT(extra);
        if (![extra isDismissingModalViewControllerAnimated]) {
            [extra setDismissingModalViewControllerAnimated:YES];
            [extra startPollingChildModalViewController];
        }    
#ifdef DEBUG_VIEW_CONTROLLER_EXTESIONS
        NSLog(@"Recording isDismissingModalViewControllerAnimated=YES for %p.", self);
#endif
    }

    original_dismissModalViewControllerAnimated(self, _cmd, animated);
}

@end

#pragma mark -

const CGFloat MODAL_VIEW_CONTROLLER_POLL_INTERVAL = 0.1;

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
    return self;
}

- (void)dealloc;
{
    [_modalViewControllerQueue release];
    [super dealloc];
}

@synthesize owner = _owner;
@synthesize dismissingModalViewControllerAnimated = _dismissingModalViewControllerAnimated;

- (void)enqueueModalViewController:(UIViewController *)viewController presentAnimated:(BOOL)animated;
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

- (void)startPollingChildModalViewController;
{
    if (_isPollingChildModalViewController)
        return;
        
    [self performSelector:@selector(pollChildModalViewControllerCallback) withObject:nil afterDelay:MODAL_VIEW_CONTROLLER_POLL_INTERVAL];
}

- (void)pollChildModalViewControllerCallback;
{
    // Sadly, UIViewController doesn't change this in a KVO compliant way so we are reduced to polling.
    // At least the ugliness is encapsulated in one place.
    
    if (_owner.modalViewController) {
        [self performSelector:_cmd withObject:nil afterDelay:MODAL_VIEW_CONTROLLER_POLL_INTERVAL];
        return;
    }
        
#ifdef DEBUG_VIEW_CONTROLLER_EXTESIONS
    NSLog(@"Finished polling for modal view controller animation completion for %p.", _owner);
#endif

    [self setDismissingModalViewControllerAnimated:NO];
    
    BOOL animated = NO;
    UIViewController *viewController = [self dequeueModalViewControllerShouldPresentAnimated:&animated];
    if (viewController)
        [_owner presentModalViewController:viewController animated:animated];
}

@end
