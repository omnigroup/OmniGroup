// Copyright 2010-2011 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIFontAttributesInspectorSlice.h>

#import <OmniUI/OUIInspectorSegmentedControl.h>
#import <OmniUI/OUIInspector.h>
#import <OmniAppKit/OAFontDescriptor.h>
#import <CoreText/CTStringAttributes.h>

#import "OUIFontUtilities.h"

RCS_ID("$Id$");

@implementation OUIFontAttributesInspectorSlice

//@synthesize fontAttributeSegmentedControl = _fontAttributeSegmentedControl;
@synthesize showStrikethrough = _showStrikethrough;

- (void)dealloc;
{
    [_fontAttributeSegmentedControl release];
    [_boldFontAttributeButton release];
    [_italicFontAttributeButton release];
    [_underlineFontAttributeButton release];
    [_strikethroughFontAttributeButton release];
    
    [super dealloc];
}

- (OUIInspectorSegmentedControlButton *)fontAttributeButtonForType:(OUIFontAttributeButtonType)type; // Useful when overriding -updateFontAttributeButtons
{
    OUIInspectorSegmentedControlButton *button = nil;
    
    switch (type) {
        case OUIFontAttributeButtonTypeBold:
            button = _boldFontAttributeButton;
            break;
        case OUIFontAttributeButtonTypeItalic:
            button = _italicFontAttributeButton;
            break;
        case OUIFontAttributeButtonTypeUnderline:
            button = _underlineFontAttributeButton;
            break;
        case OUIFontAttributeButtonTypeStrikethrough:
            button = _strikethroughFontAttributeButton;
            break;
        default:
            break;
    }
    
    return button;
}

- (void)updateFontAttributeButtonsWithFontDescriptors:(NSArray *)fontDescriptors;
{
    BOOL bold = NO, italic = NO;
    for (OAFontDescriptor *fontDescriptor in fontDescriptors) {
        bold |= [fontDescriptor bold];
        italic |= [fontDescriptor italic];
    }
    
    [_boldFontAttributeButton setSelected:bold];
    [_italicFontAttributeButton setSelected:italic];
    
    BOOL underline = NO, strikethrough = NO;
    for (id <OUIFontInspection> object in self.appropriateObjectsForInspection) {
        if ([object underlineStyleForInspectorSlice:self] != kCTUnderlineStyleNone)
            underline = YES;
        if (_showStrikethrough) {
            if ([object strikethroughStyleForInspectorSlice:self] != kCTUnderlineStyleNone)
                strikethrough = YES;
        }
    }
    [_underlineFontAttributeButton setSelected:underline];
    [_strikethroughFontAttributeButton setSelected:strikethrough];
}

#pragma mark -
#pragma mark UIViewController subclass;

- (void)loadView;
{
    _fontAttributeSegmentedControl = [[OUIInspectorSegmentedControl alloc] initWithFrame:CGRectMake(0, 0, 100, [OUIInspectorSegmentedControl buttonHeight])];
    
    _fontAttributeSegmentedControl.sizesSegmentsToFit = YES;
    _fontAttributeSegmentedControl.allowsMulitpleSelection = YES;
    
    _boldFontAttributeButton = [[_fontAttributeSegmentedControl addSegmentWithImageNamed:@"OUIFontStyle-Bold.png"] retain];
    [_boldFontAttributeButton addTarget:self action:@selector(_toggleBold:)];
    
    _italicFontAttributeButton = [[_fontAttributeSegmentedControl addSegmentWithImageNamed:@"OUIFontStyle-Italic.png"] retain];
    [_italicFontAttributeButton addTarget:self action:@selector(_toggleItalic:)];
    
    _underlineFontAttributeButton = [[_fontAttributeSegmentedControl addSegmentWithImageNamed:@"OUIFontStyle-Underline.png"] retain];
    [_underlineFontAttributeButton addTarget:self action:@selector(_toggleUnderline:)];
    
    if (_showStrikethrough) {
        _strikethroughFontAttributeButton = [[_fontAttributeSegmentedControl addSegmentWithImageNamed:@"OUIFontStyle-Strikethrough.png"] retain];
        [_strikethroughFontAttributeButton addTarget:self action:@selector(_toggleStrikethrough:)];
    }
    
    self.view = _fontAttributeSegmentedControl;
}

#pragma mark -
#pragma mark OUIInspectorSlice subclass

- (BOOL)isAppropriateForInspectedObject:(id)object;
{
    return [object shouldBeInspectedByInspectorSlice:self protocol:@protocol(OUIFontInspection)];
}

- (void)updateInterfaceFromInspectedObjects:(OUIInspectorUpdateReason)reason;
{
    [super updateInterfaceFromInspectedObjects:reason];
    
    OUIFontSelection selection = OUICollectFontSelection(self, self.appropriateObjectsForInspection);

    [self updateFontAttributeButtonsWithFontDescriptors:selection.fontDescriptors];
}

#pragma mark -
#pragma mark Private

static id <OUIFontInspection> _firstFont(OUIFontAttributesInspectorSlice *self)
{
    NSArray *inspectedFonts = self.appropriateObjectsForInspection;
    if ([inspectedFonts count] == 0)
        return nil;
    
    return [inspectedFonts objectAtIndex:0];
}

static BOOL _toggledFlagToAssign(OUIFontAttributesInspectorSlice *self, SEL sel)
{
    id <OUIFontInspection> firstFont = _firstFont(self);
    if (!firstFont)
        return NO;
    
    OAFontDescriptor *desc = [firstFont fontDescriptorForInspectorSlice:self];
    
    BOOL (*getter)(id obj, SEL _cmd) = (typeof(getter))[desc methodForSelector:sel];
    OBASSERT(getter); // not checking the type...
    
    return !getter(desc, sel);
}

- (void)_toggleBold:(id)sender;
{
    [self.inspector willBeginChangingInspectedObjects];
    {
        BOOL flag = _toggledFlagToAssign(self, @selector(bold));
        
        for (id <OUIFontInspection> object in self.appropriateObjectsForInspection) {
            OAFontDescriptor *desc = [object fontDescriptorForInspectorSlice:self];
            desc = [[desc newFontDescriptorWithBold:flag] autorelease];
            [object setFontDescriptor:desc fromInspectorSlice:self];
        }
    }
    [self.inspector didEndChangingInspectedObjects];
}
- (void)_toggleItalic:(id)sender;
{
    [self.inspector willBeginChangingInspectedObjects];
    {
        BOOL flag = _toggledFlagToAssign(self, @selector(italic));
        
        for (id <OUIFontInspection> object in self.appropriateObjectsForInspection) {
            OAFontDescriptor *desc = [object fontDescriptorForInspectorSlice:self];
            desc = [[desc newFontDescriptorWithItalic:flag] autorelease];
            [object setFontDescriptor:desc fromInspectorSlice:self];
        }
    }
    [self.inspector didEndChangingInspectedObjects];
}
- (void)_toggleUnderline:(id)sender;
{
    [self.inspector willBeginChangingInspectedObjects];
    {
        id <OUIFontInspection> font = _firstFont(self);
        CTUnderlineStyle underline = [font underlineStyleForInspectorSlice:self];
        underline = (underline == kCTUnderlineStyleNone) ? kCTUnderlineStyleSingle : kCTUnderlineStyleNone; // Press and hold for menu someday?
        
        for (id <OUIFontInspection> object in self.appropriateObjectsForInspection)
            [object setUnderlineStyle:underline fromInspectorSlice:self];
    }
    [self.inspector didEndChangingInspectedObjects];
}
- (void)_toggleStrikethrough:(id)sender;
{
    [self.inspector willBeginChangingInspectedObjects];
    {
        id <OUIFontInspection> font = _firstFont(self);
        CTUnderlineStyle strikethrough = [font strikethroughStyleForInspectorSlice:self];
        strikethrough = (strikethrough == kCTUnderlineStyleNone) ? kCTUnderlineStyleSingle : kCTUnderlineStyleNone; // Press and hold for menu someday?
        
        for (id <OUIFontInspection> object in self.appropriateObjectsForInspection)
            [object setStrikethroughStyle:strikethrough fromInspectorSlice:self];
    }
    [self.inspector didEndChangingInspectedObjects];
}

@end
