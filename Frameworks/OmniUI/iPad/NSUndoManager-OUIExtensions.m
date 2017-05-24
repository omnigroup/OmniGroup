// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
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
    // -[NSUndoManager removeAllActions] will close any open undo groups as a side effect.
    //
    // Send OUIUndoManagerDidRemoveAllActionsNotification if we removed actions, *or* closed groups, so that clients can react accordingly, and note that any group they thought they had open has been closed underneath them.
    
    BOOL shouldNotify = self.canUndo || self.canRedo || self.groupingLevel > 0;

    original_removeAllActions(self, _cmd);

    if (shouldNotify) {
        OBASSERT(self.groupingLevel == 0);
        [[NSNotificationCenter defaultCenter] postNotificationName:OUIUndoManagerDidRemoveAllActionsNotification object:self];
    }
}

- (void)replacement_removeAllActionsWithTarget:(id)target;
{
    // -[NSUndoManager removeAllActionsWithTarget:] doesn't appear to close open undo groups (see above), but let's be defensive and send OUIUndoManagerDidRemoveAllActionsNotification if we detect that it has.
    
    BOOL hadActions = self.canUndo || self.canRedo;
    NSInteger priorGroupingLevel = self.groupingLevel;
    
    original_removeAllActionsWithTarget(self, _cmd, target);
    
    BOOL closedGroups = self.groupingLevel < priorGroupingLevel;
    if (hadActions || closedGroups) {
        BOOL isUndoStackEmpty = !self.canUndo && !self.canRedo;
        if (isUndoStackEmpty || closedGroups) {
            [[NSNotificationCenter defaultCenter] postNotificationName:OUIUndoManagerDidRemoveAllActionsNotification object:self];
        }
    }
}

@end
