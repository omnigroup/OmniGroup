// Copyright 2010-2011 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUITextColorsInspectorSlice.h>

#import <OmniAppKit/OATextAttributes.h>
#import <OmniFoundation/NSSet-OFExtensions.h>
#import <OmniQuartz/OQColor.h>
#import <OmniUI/OUIColorSwatchPicker.h>
#import <OmniUI/OUIEditableFrame.h>
#import <OmniUI/OUIInspectorTextWell.h>
#import <OmniUI/OUIStackedSlicesInspectorPane.h>
#import <OmniUI/OUITextColorInspectorWell.h>

#import "OUITextSpanColorAttributeInspectorSlice.h"
#import "OUEFTextSpan.h"

RCS_ID("$Id$");

@implementation OUITextColorsInspectorSlice

+ (Class)textWellClass;
{
    return [OUITextColorInspectorWell class];
}

- init;
{
    return [super initWithTitle:NSLocalizedStringFromTableInBundle(@"Color", @"OUIInspectors", OMNI_BUNDLE, @"Inspector button title for showing style text foreground and background color.")
                      paneMaker:
            ^(OUIDetailInspectorSlice *slice){
                OUIStackedSlicesInspectorPane *pane = [[[OUIStackedSlicesInspectorPane alloc] init] autorelease];
                pane.title = NSLocalizedStringFromTableInBundle(@"Color", @"OUIInspectors", OMNI_BUNDLE, @"Title above color swatch picker for the background color.");
                
                NSMutableArray *slices = [NSMutableArray array];
                OUITextSpanColorAttributeInspectorSlice *colorSlice;
                colorSlice = [[[OUITextSpanColorAttributeInspectorSlice alloc] init] autorelease];
                colorSlice.title = NSLocalizedStringFromTableInBundle(@"Text", @"OUIInspectors", OMNI_BUNDLE, @"Title above color swatch picker for the text color.");
                colorSlice.attribute = OAForegroundColorAttributeName;
                colorSlice.palettePreferenceKey = OUIColorSwatchPickerTextColorPalettePreferenceKey;
                [slices addObject:colorSlice];
                
                colorSlice = [[[OUITextSpanColorAttributeInspectorSlice alloc] init] autorelease];
                colorSlice.title = NSLocalizedStringFromTableInBundle(@"Background", @"OUIInspectors", OMNI_BUNDLE, @"Title above color swatch picker for the background color.");
                colorSlice.attribute = OABackgroundColorAttributeName;
                colorSlice.palettePreferenceKey = OUIColorSwatchPickerTextBackgroundPalettePreferenceKey;
                [slices addObject:colorSlice];
                
                pane.slices = slices;
                
                return pane;
            }];
}

- (BOOL)isAppropriateForInspectedObject:(id)object;
{
    return [object isKindOfClass:[OUEFTextSpan class]];
}

- (void)updateInterfaceFromInspectedObjects;
{
    [super updateInterfaceFromInspectedObjects];
    
    OBASSERT([self.appropriateObjectsForInspection count] <= 1); // Multiple selection support?
    OUEFTextSpan *span = [self.appropriateObjectsForInspection anyObject];
    
    CGColorRef foregroundColor = (CGColorRef)[span.frame attribute:OAForegroundColorAttributeName inRange:span];
    CGColorRef backgroundColor = (CGColorRef)[span.frame attribute:OABackgroundColorAttributeName inRange:span];

    OUITextColorInspectorWell *textWell = (OUITextColorInspectorWell *)self.textWell;

    textWell.textForegroundColor = foregroundColor ? [OQColor colorWithCGColor:foregroundColor] : nil;
    textWell.textBackgroundColor = backgroundColor ? [OQColor colorWithCGColor:backgroundColor] : nil;
}

@end
