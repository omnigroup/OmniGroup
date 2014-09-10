// Copyright 2010-2011, 2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniUI/OUIInspectorSlice.h>
#import <OmniUI/OUIColorInspectorPaneParentSlice.h>

@class OQColor;
@class OUIInspectorSelectionValue;

@interface OUIAbstractColorInspectorSlice : OUIInspectorSlice <OUIColorInspectorPaneParentSlice>
{
@private
    OUIInspectorSelectionValue *_selectionValue;
    BOOL _inContinuousChange;
    BOOL _allowsNone;
    OQColor *_defaultColor;
}

// Must be subclassed, in addition to -isAppropriateForInspectedObject:.
- (OQColor *)colorForObject:(id)object;
- (void)setColor:(OQColor *)color forObject:(id)object;

- (void)handleColorChange:(OQColor *)color; // Hook so that Graffle can handle mass changes a little differently

@end

