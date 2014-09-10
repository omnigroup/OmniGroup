// Copyright 2010-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/NSUndoManager-OUIExtensions.h>
#import <OmniBase/OBUtilities.h>

RCS_ID("$Id$");

NSString * const OUIUndoManagerDidRemoveAllActionsNotification = @"OUIUndoManagerDidRemoveAllActionsNotification";

static void (*original_removeAllActions)(id self, SEL _cmd) = NULL;
static void (*original_removeAllActionsWithTarget)(id self, SEL _cmd, id target) = NULL;

@implementation NSUndoManager (OUIExtensions)

+ (void)load;
{
    [self installOUIUndoManagerExtensions];
}

+ (void)installOUIUndoManagerExtensions;
{
#define REPL(old, name) old = (typeof(old))OBReplaceMethodImplementationWithSelector(self, @selector(name), @selector(replacement_ ## name))
    
    REPL(original_removeAllActions, removeAllActions);
    REPL(original_removeAllActionsWithTarget, removeAllActionsWithTarget:);

}

- (void)replacement_removeAllActions;
{
    original_removeAllActions(self, _cmd);

    [[NSNotificationCenter defaultCenter] postNotificationName:OUIUndoManagerDidRemoveAllActionsNotification object:self];
}

- (void)replacement_removeAllActionsWithTarget:(id)target;
{
    original_removeAllActionsWithTarget(self, _cmd, target);
    
    BOOL canUndo = [self canUndo];
    BOOL canRedo = [self canRedo];
    if (!canUndo && !canRedo) {
        [[NSNotificationCenter defaultCenter] postNotificationName:OUIUndoManagerDidRemoveAllActionsNotification object:self];
    }
}

@end
