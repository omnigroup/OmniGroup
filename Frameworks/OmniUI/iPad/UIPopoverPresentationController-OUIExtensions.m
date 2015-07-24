// Copyright 2015 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/UIPopoverPresentationController-OUIExtensions.h>

RCS_ID("$Id$");

static unsigned int _DisabledManagedBarButtonItemsKey;

@interface UIPopoverPresentationController (OUIPrivateExtensions)

@property (nonatomic) BOOL OUI_isPresented;
@property (nonatomic, copy) NSSet *disabledManagedBarButtonItems;

@end

#pragma mark -

static unsigned int _ManagedBarButtonItemsKey;

@implementation UIPopoverPresentationController (OUIExtensions)

- (NSSet *)managedBarButtonItems;
{
    NSSet *barButtonItems = objc_getAssociatedObject(self, &_ManagedBarButtonItemsKey);
    if (barButtonItems == nil) {
        barButtonItems = [NSSet set];
    }
    
    return barButtonItems;
}

- (void)setManagedBarButtonItems:(NSSet *)managedBarButtonItems;
{
    OBPRECONDITION(![self OUI_isPresented], "Cannot mutate managed bar button items during presentation");
    if ([self OUI_isPresented]) {
        return;
    }
    
    objc_setAssociatedObject(self, &_ManagedBarButtonItemsKey, managedBarButtonItems, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

- (void)addManagedBarButtonItems:(NSSet *)barButtonItems;
{
    OBPRECONDITION(barButtonItems != nil);

    NSMutableSet *managedBarButtonItems = [self.managedBarButtonItems mutableCopy];
    [managedBarButtonItems unionSet:barButtonItems];
    self.managedBarButtonItems = managedBarButtonItems;
}

- (void)addManagedBarButtonItemsObject:(UIBarButtonItem *)barButtonItem;
{
    OBPRECONDITION(barButtonItem != nil);

    NSSet *set = [NSSet setWithObject:barButtonItem];
    [self addManagedBarButtonItems:set];
}

- (void)removeManagedBarButtonItems:(NSSet *)barButtonItems;
{
    OBPRECONDITION(barButtonItems != nil);
    
    NSMutableSet *managedBarButtonItems = [self.managedBarButtonItems mutableCopy];
    [managedBarButtonItems minusSet:barButtonItems];
    self.managedBarButtonItems = managedBarButtonItems;
}

- (void)removeManagedBarButtonItemsObject:(UIBarButtonItem *)barButtonItem;
{
    OBPRECONDITION(barButtonItem != nil);
    
    NSSet *set = [NSSet setWithObject:barButtonItem];
    [self removeManagedBarButtonItems:set];
}

#pragma mark Convenience Methods

- (void)addManagedBarButtonItemsFromNavigationController:(UINavigationController *)navigationController;
{
    [self addManagedBarButtonItemsFromNavigationItem:navigationController.navigationBar.topItem];
}

- (void)addManagedBarButtonItemsFromNavigationItem:(UINavigationItem *)navigationItem;
{
    NSMutableSet *managedBarButtonItems = [NSMutableSet set];

    [managedBarButtonItems addObjectsFromArray:navigationItem.leftBarButtonItems];
    [managedBarButtonItems addObjectsFromArray:navigationItem.rightBarButtonItems];

    [self addManagedBarButtonItems:managedBarButtonItems];
}

- (void)addManagedBarButtonItemsFromToolbar:(UIToolbar *)toolbar;
{
    NSSet *managedBarButtonItems = [NSSet setWithArray:toolbar.items];

    [self addManagedBarButtonItems:managedBarButtonItems];
}

@end

#pragma mark -

static unsigned int _OUIIsPresentedKey;

static void (*original_presentationTransitionWillBegin)(id self, SEL _cmd);
static void (*original_presentationTransitionDidEnd)(id self, SEL _cmd, BOOL completed);
static void (*original_dismissalTransitionWillBegin)(id self, SEL _cmd);
static void (*original_dismissalTransitionDidEnd)(id self, SEL _cmd, BOOL completed);

@implementation UIPopoverPresentationController (OUIPrivateExtensions)

static void _PerformPosing(void) __attribute__((constructor));
static void _PerformPosing(void)
{
    Class cls = [UIPopoverPresentationController class];
    
    original_presentationTransitionWillBegin = (typeof(original_presentationTransitionWillBegin))OBReplaceMethodImplementationWithSelector(cls, @selector(presentationTransitionWillBegin), @selector(replacement_presentationTransitionWillBegin));

    original_presentationTransitionDidEnd = (typeof(original_presentationTransitionDidEnd))OBReplaceMethodImplementationWithSelector(cls, @selector(presentationTransitionDidEnd:), @selector(replacement_presentationTransitionDidEnd:));

    original_dismissalTransitionWillBegin = (typeof(original_dismissalTransitionWillBegin))OBReplaceMethodImplementationWithSelector(cls, @selector(dismissalTransitionWillBegin), @selector(replacement_dismissalTransitionWillBegin));

    original_dismissalTransitionDidEnd = (typeof(original_dismissalTransitionDidEnd))OBReplaceMethodImplementationWithSelector(cls, @selector(dismissalTransitionDidEnd:), @selector(replacement_dismissalTransitionDidEnd:));
}

- (BOOL)OUI_isPresented;
{
    id isBeingPresented = objc_getAssociatedObject(self, &_OUIIsPresentedKey);
    return [isBeingPresented boolValue];
}

- (void)setOUI_isPresented:(BOOL)isBeingPresented;
{
    objc_setAssociatedObject(self, &_OUIIsPresentedKey, [NSNumber numberWithBool:isBeingPresented], OBJC_ASSOCIATION_COPY_NONATOMIC);
}

- (NSSet *)disabledManagedBarButtonItems;
{
    NSSet *disabledManagedBarButtonItems = objc_getAssociatedObject(self, &_DisabledManagedBarButtonItemsKey);
    if (disabledManagedBarButtonItems == nil) {
        disabledManagedBarButtonItems = [NSSet set];
    }
    
    return disabledManagedBarButtonItems;
}

- (void)setDisabledManagedBarButtonItems:(NSSet *)disabledManagedBarButtonItems;
{
    objc_setAssociatedObject(self, &_DisabledManagedBarButtonItemsKey, disabledManagedBarButtonItems, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

- (void)replacement_presentationTransitionWillBegin;
{
    original_presentationTransitionWillBegin(self, _cmd);
    
    NSMutableSet *disabledManagedBarButtonItems = [NSMutableSet set];
    for (UIBarButtonItem *barButtonItem in self.managedBarButtonItems) {
        if ([barButtonItem isEnabled]) {
            [barButtonItem setEnabled:NO];
            [disabledManagedBarButtonItems addObject:barButtonItem];
        }
    }
    
    self.disabledManagedBarButtonItems = disabledManagedBarButtonItems;
}

- (void)replacement_presentationTransitionDidEnd:(BOOL)completed;
{
    original_presentationTransitionDidEnd(self, _cmd, completed);
}

- (void)replacement_dismissalTransitionWillBegin;
{
    original_dismissalTransitionWillBegin(self, _cmd);
    
    for (UIBarButtonItem *barButtonItem in self.disabledManagedBarButtonItems) {
        [barButtonItem setEnabled:YES];
    }
    
    self.disabledManagedBarButtonItems = nil;
}

- (void)replacement_dismissalTransitionDidEnd:(BOOL)completed;
{
    original_dismissalTransitionDidEnd(self, _cmd, completed);
}

@end
