// Copyright 2015-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/UIPopoverPresentationController-OUIExtensions.h>

RCS_ID("$Id$");

NS_ASSUME_NONNULL_BEGIN

static unsigned int _DisabledManagedBarButtonItemsKey;

@interface UIPopoverPresentationController (OUIPrivateExtensions)

@property (nonatomic) BOOL OUI_isPresented;
@property (nonatomic, nullable, copy) NSHashTable *disabledManagedBarButtonItems;

@end

#pragma mark -

static unsigned int _ManagedBarButtonItemsKey;

@implementation UIPopoverPresentationController (OUIExtensions)

- (NSHashTable *)managedBarButtonItems;
{
    NSHashTable *barButtonItems = objc_getAssociatedObject(self, &_ManagedBarButtonItemsKey);
    if (barButtonItems == nil) {
        barButtonItems = [NSHashTable hashTableWithOptions:NSHashTableObjectPointerPersonality];
        
        if (![self OUI_isPresented]) {
            self.managedBarButtonItems = barButtonItems;
        }
    }
    
    return barButtonItems;
}

- (void)setManagedBarButtonItems:(NSHashTable *)managedBarButtonItems;
{
    OBPRECONDITION(![self OUI_isPresented], "Cannot mutate managed bar button items during presentation");
    if ([self OUI_isPresented]) {
        return;
    }
    
    objc_setAssociatedObject(self, &_ManagedBarButtonItemsKey, managedBarButtonItems, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

- (void)setManagedBarButtonItemsFromArray:(NSArray<UIBarButtonItem *> *)barButtonItems;
{
    [self clearManagedBarButtonItems];
    [self addManagedBarButtonItems:barButtonItems];
}

- (void)clearManagedBarButtonItems;
{
    [self.managedBarButtonItems removeAllObjects];
}

- (void)addManagedBarButtonItems:(nullable NSArray<UIBarButtonItem *> *)barButtonItems;
{
    if (barButtonItems == nil) {
        return;
    }

    for (UIBarButtonItem *item in barButtonItems) {
        [self.managedBarButtonItems addObject:item];
    }
}

- (void)addManagedBarButtonItemsObject:(UIBarButtonItem *)barButtonItem;
{
    OBPRECONDITION(barButtonItem != nil);

    [self.managedBarButtonItems addObject:barButtonItem];
}

- (void)removeManagedBarButtonItems:(NSArray<UIBarButtonItem *> *)barButtonItems;
{
    OBPRECONDITION(barButtonItems != nil);
    
    for (UIBarButtonItem *item in barButtonItems) {
        [self.managedBarButtonItems removeObject:item];
    }
}

- (void)removeManagedBarButtonItemsObject:(UIBarButtonItem *)barButtonItem;
{
    OBPRECONDITION(barButtonItem != nil);
    
    [self.managedBarButtonItems removeObject:barButtonItem];
}

#pragma mark Convenience Methods

- (void)addManagedBarButtonItemsFromNavigationController:(nullable UINavigationController *)navigationController;
{
    if (navigationController != nil) {
        [self addManagedBarButtonItemsFromNavigationItem:navigationController.navigationBar.topItem];
        [self addManagedBarButtonItemsFromToolbar:navigationController.toolbar];
    }
}

- (void)addManagedBarButtonItemsFromNavigationItem:(nullable UINavigationItem *)navigationItem;
{
    if (navigationItem != nil) {
        [self addManagedBarButtonItems:navigationItem.leftBarButtonItems];
        [self addManagedBarButtonItems:navigationItem.rightBarButtonItems];
    }
}

- (void)addManagedBarButtonItemsFromToolbar:(nullable UIToolbar *)toolbar;
{
    if (toolbar != nil) {
        [self addManagedBarButtonItems:toolbar.items];
    }
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

- (nullable NSHashTable *)disabledManagedBarButtonItems;
{
    NSHashTable *disabledManagedBarButtonItems = objc_getAssociatedObject(self, &_DisabledManagedBarButtonItemsKey);
    if (disabledManagedBarButtonItems == nil) {
        disabledManagedBarButtonItems = [NSHashTable hashTableWithOptions:NSHashTableObjectPointerPersonality];
    }
    
    return disabledManagedBarButtonItems;
}

- (void)setDisabledManagedBarButtonItems:(nullable NSHashTable *)disabledManagedBarButtonItems;
{
    objc_setAssociatedObject(self, &_DisabledManagedBarButtonItemsKey, disabledManagedBarButtonItems, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

- (void)replacement_presentationTransitionWillBegin;
{
    original_presentationTransitionWillBegin(self, _cmd);
    
    NSHashTable *disabledManagedBarButtonItems = [NSHashTable hashTableWithOptions:NSHashTableObjectPointerPersonality];
    for (UIBarButtonItem *barButtonItem in self.managedBarButtonItems) {
        if ([barButtonItem isEnabled]) {
            barButtonItem.enabled = NO;
            barButtonItem.OUI_enabledStateIsManagedByPopoverPresentationController = YES;

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
        barButtonItem.OUI_enabledStateIsManagedByPopoverPresentationController = NO;
        barButtonItem.enabled = YES;
    }
    
    self.disabledManagedBarButtonItems = nil;
}

- (void)replacement_dismissalTransitionDidEnd:(BOOL)completed;
{
    original_dismissalTransitionDidEnd(self, _cmd, completed);
}

@end

#pragma mark -

static unsigned int _EnabledStateIsManagedByPopoverPresentationControllerKey;


@implementation UIBarButtonItem (OUIPopoverPresentationExtensions)

- (BOOL)OUI_enabledStateIsManagedByPopoverPresentationController;
{
    id value = objc_getAssociatedObject(self, &_EnabledStateIsManagedByPopoverPresentationControllerKey);

    if (value != nil && [value isKindOfClass:[NSNumber class]]) {
        return [value boolValue];
    } else {
        return NO;
    }
}

- (void)setOUI_enabledStateIsManagedByPopoverPresentationController:(BOOL)enabledStateIsManagedByPopoverPresentationController;
{
    objc_setAssociatedObject(self, &_EnabledStateIsManagedByPopoverPresentationControllerKey, @(enabledStateIsManagedByPopoverPresentationController), OBJC_ASSOCIATION_COPY_NONATOMIC);
}

@end


NS_ASSUME_NONNULL_END

