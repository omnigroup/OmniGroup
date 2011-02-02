// Copyright 2010-2011 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUITextSpanColorAttributeInspectorSlice.h"

#import <OmniUI/OUIColorSwatchPicker.h>
#import <OmniUI/OUIEditableFrame.h>
#import <OmniQuartz/OQColor.h>

#import "OUEFTextSpan.h"

RCS_ID("$Id$");

@implementation OUITextSpanColorAttributeInspectorSlice

@synthesize attribute = _attribute;
@synthesize palettePreferenceKey = _palettePreferenceKey;

- (void)dealloc;
{
    [_attribute release];
    [_palettePreferenceKey release];
    [super dealloc];
}

#pragma mark -
#pragma mark OUIAbstractColorInspectorSlice subclass

- (BOOL)isAppropriateForInspectedObject:(id)object;
{
    return [object isKindOfClass:[OUEFTextSpan class]];
}

- (NSSet *)getColorsFromObject:(id)object;
{
    OBPRECONDITION(_attribute);
    
    OUEFTextSpan *span = object;
    CGColorRef color = (CGColorRef)[span.frame attribute:(id)_attribute inRange:span];
    if (color == NULL) {
        return [NSSet set];
    }
    return [NSSet setWithObject:[OQColor colorWithCGColor:color]];
}

- (void)setColor:(OQColor *)color forObject:(id)object;
{
    OBPRECONDITION(_attribute);

    OUEFTextSpan *span = object;
    [span.frame setValue:(id)[[color toColor] CGColor] forAttribute:(id)_attribute inRange:span];
}

- (void)loadColorSwatchesForObject:(id)object;
{
    OBPRECONDITION(_palettePreferenceKey);
    
    self.swatchPicker.palettePreferenceKey = _palettePreferenceKey;
}

#pragma mark -
#pragma mark UIViewController subclass

- (void)viewDidLoad;
{
    [super viewDidLoad];
    
    self.swatchPicker.showsNoneSwatch = YES;
}

@end
