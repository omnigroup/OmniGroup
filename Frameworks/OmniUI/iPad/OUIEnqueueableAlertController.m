// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIEnqueueableAlertController.h>

@interface OUIExtendedAlertAction ()

@property (nonatomic, strong) NSMutableArray *completionBlocks;

@end

#pragma mark -

@implementation OUIExtendedAlertAction

+ (instancetype)extendedActionWithTitle:(nullable NSString *)title style:(UIAlertActionStyle)style handler:(void (^ __nonnull)(OUIExtendedAlertAction *action))handler;
{
    void (^handlerCopy)(OUIExtendedAlertAction *) = [handler copy];
    return [self actionWithTitle:title style:style handler:^(UIAlertAction * _Nonnull action) {
        OUIExtendedAlertAction *extendedAction = OB_CHECKED_CAST(OUIExtendedAlertAction, action);
        handlerCopy(extendedAction);
    }];
}

- (void)extendedActionComplete
{
    for (id (^block)(void) in self.completionBlocks) {
        block();
    }
    
    self.completionBlocks = nil;
}

- (void)addInteractionCompletion:(nonnull void (^)(void))interactionCompletionHandler {
    if (self.completionBlocks == nil) {
        self.completionBlocks = [NSMutableArray array];
    }
    
    [self.completionBlocks addObject:[interactionCompletionHandler copy]];
}

@end

#pragma mark -

@interface OUIEnqueueableAlertController ()

@property (nonatomic, strong) NSMutableArray *completionBlocks;

@end

#pragma mark -

@implementation OUIEnqueueableAlertController

+ (instancetype)alertControllerWithTitle:(NSString *)title message:(NSString *)message preferredStyle:(UIAlertControllerStyle)preferredStyle;
{
    OBASSERT(preferredStyle == UIAlertControllerStyleAlert, "The size class at presentation time cannot be known; OUIEnqueueableAlertController must use the UIAlertControllerStyleAlert presentation style.");
    
    return [super alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
}

- (void)addAction:(UIAlertAction *)action
{
    OBRejectUnusedImplementation(self, _cmd);
}

- (void)addExtendedAction:(OUIExtendedAlertAction *)action;
{
    [action addInteractionCompletion:^{
        [self interactionComplete];
    }];
    [super addAction:action];
}

- (UIAlertAction *)addActionWithTitle:(nullable NSString *)title style:(UIAlertActionStyle)style handler:(void (^ __nullable)(UIAlertAction *action))handler;
{
    void (^ handlerCopy)(UIAlertAction *) = [handler copy];
    UIAlertAction *alertAction = [UIAlertAction actionWithTitle:title style:style handler:^(UIAlertAction * _Nonnull action) {
        if (handlerCopy != nil) {
            handlerCopy(action);
        }
        [self interactionComplete];
    }];
    [super addAction:alertAction];
    return alertAction;
}

- (void)addInteractionCompletion:(nonnull void (^)(void))interactionCompletionHandler {
    if (self.completionBlocks == nil) {
        self.completionBlocks = [NSMutableArray array];
    }
    
    [self.completionBlocks addObject:[interactionCompletionHandler copy]];
}

- (void)interactionComplete
{
    for (id (^block)(void) in self.completionBlocks) {
        block();
    }
    
    self.completionBlocks = nil;
}

@end

