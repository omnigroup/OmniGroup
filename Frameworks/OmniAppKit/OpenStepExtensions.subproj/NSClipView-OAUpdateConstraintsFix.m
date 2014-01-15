// Copyright 2013 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <AppKit/NSClipView.h>
#import <Foundation/Foundation.h>
#import <OmniBase/OBUtilities.h>
#import <OmniAppKit/OAVersion.h>

RCS_ID("$Id$")

/*
 * WORKAROUND FOR RADAR 13038793 owner:kyle
 *
 * -[NSClipView updateConstraints] forces its autoresizing mask to a bogus value (NSViewWidthSizable|NSViewHeightSizable) whenever its superview is an instance of NSScrollView.
 *
 * This might be appropriate for clip views that are the content view of a scroll view, but it is NOT correct for other clip views that might just happen to be direct subviews of the scroll view.
 *
 * For example, NSScrollView creates an instance of NSClipView to contain a scroll view's headerView. This scroll view erroneously sets its autoresizing mask in -updateConstraints, which casues problems when the view is resized below the size it was at when it received its first -updateConstraints message.
 *
 * The autoresizing mask of the header view's clip view needs to have the NSViewMinYSizable (or NSViewMaxYSizable, depending on the flippedness of the scroll view) bit set in order to avoid causing problems when the scroll view is resized. -[NSClipView updateConstraints] prevents this from happening.
 */

@interface NSClipView (OAUpdateConstraintsFix)
- (void)_replacement_updateConstraints;
@end


@implementation NSClipView (OAUpdateConstraintsFix)

static NSMutableSet *ClipViewsCurrentlyUpdatingConstraints;
static void (*_original_updateConstraints)(id self, SEL _cmd);
static void (*_original_setAutoresizingMask)(id self, SEL _cmd, NSUInteger mask);

- (void)_replacement_setAutoresizingMask:(NSUInteger)mask;
{
    if (!([ClipViewsCurrentlyUpdatingConstraints containsObject:self])) {
        if (_original_setAutoresizingMask)
            _original_setAutoresizingMask(self, _cmd, mask);
        else
            [super setAutoresizingMask:mask];
    }
}

- (void)_replacement_updateConstraints;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    [ClipViewsCurrentlyUpdatingConstraints addObject:self];
    _original_updateConstraints(self, _cmd);
    [ClipViewsCurrentlyUpdatingConstraints removeObject:self];
}

+ (void)performPosing;
{
    if (NSAppKitVersionNumber < OAAppKitVersionNumber10_9) {
        _original_updateConstraints = (typeof(_original_updateConstraints))OBReplaceMethodImplementationWithSelector(self, @selector(updateConstraints), @selector(_replacement_updateConstraints));
        
        if (OBClassImplementingMethod(self, @selector(setAutoresizingMask:)) == self) {
            _original_setAutoresizingMask = (typeof(_original_setAutoresizingMask))OBReplaceMethodImplementationWithSelector(self, @selector(setAutoresizingMask:), @selector(_replacement_setAutoresizingMask:));
        } else {
            OBRegisterInstanceMethodWithSelector(self, @selector(_replacement_setAutoresizingMask:), @selector(setAutoresizingMask:));
        }
        
        ClipViewsCurrentlyUpdatingConstraints = [[NSMutableSet alloc] init];
    }
}

@end
