// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIFontInspectorSlice.h>

#import <OmniUI/OUIInspector.h>
#import <OmniUI/OUIInspectorTextWell.h>
#import <OmniUI/OUIInspectorStepperButton.h>
#import <OmniUI/OUIFontInspectorPane.h>
#import <OmniUI/OUIInspectorSegmentedControl.h>
#import <OmniUI/OUIInspectorSegmentedControlButton.h>

#import "OUIFontUtilities.h"

#import <OmniAppKit/OAFontDescriptor.h>
#import <OmniBase/OmniBase.h>

RCS_ID("$Id$");

@interface OUIFontInspectorSlice (/*Private*/)
- (IBAction)_showFontFamilies:(id)sender;
@end

@implementation OUIFontInspectorSlice

- (void)dealloc;
{
    [_fontFamilyTextWell release];

    [_fontAttributeSegmentedControl release];
    [_boldFontAttributeButton release];
    [_italicFontAttributeButton release];
    [_underlineFontAttributeButton release];
    [_strikethroughFontAttributeButton release];
    
    [_fontSizeDecreaseStepperButton release];
    [_fontSizeIncreaseStepperButton release];
    [_fontSizeTextWell release];
    [_fontFacesPane release];
    [super dealloc];
}

@synthesize fontFamilyTextWell = _fontFamilyTextWell;
@synthesize fontAttributeSegmentedControl = _fontAttributeSegmentedControl;
@synthesize fontSizeDecreaseStepperButton = _fontSizeDecreaseStepperButton;
@synthesize fontSizeIncreaseStepperButton = _fontSizeIncreaseStepperButton;
@synthesize fontSizeTextWell = _fontSizeTextWell;
@synthesize fontFacesPane = _fontFacesPane;
@synthesize showStrikethrough = _showStrikethrough;

static const CGFloat kMinimiumFontSize = 2;

static void _setFontSize(OUIFontInspectorSlice *self, CGFloat fontSize, BOOL relative)
{
    OUIInspector *inspector = self.inspector;
    [inspector willBeginChangingInspectedObjects];
    {
        for (id <OUIFontInspection> object in self.appropriateObjectsForInspection) {
            OAFontDescriptor *fontDescriptor = [object fontDescriptorForInspectorSlice:self];
            if (fontDescriptor) {
                CGFloat newSize = relative? ( [fontDescriptor size] + fontSize ) : fontSize;
                if (newSize < kMinimiumFontSize)
                    newSize = kMinimiumFontSize;
                fontDescriptor = [fontDescriptor newFontDescriptorWithSize:newSize];
            } else {
                UIFont *font = [UIFont systemFontOfSize:[UIFont labelFontSize]];
                CGFloat newSize = relative? ( font.pointSize + fontSize ) : fontSize;
                if (newSize < kMinimiumFontSize)
                    newSize = kMinimiumFontSize;
                fontDescriptor = [[OAFontDescriptor alloc] initWithFamily:font.familyName size:newSize];
            }
            [object setFontDescriptor:fontDescriptor fromInspectorSlice:self];
            [fontDescriptor release];
        }
    }
    [inspector didEndChangingInspectedObjects];
    
    // Update the interface
    [self updateInterfaceFromInspectedObjects];
}

- (IBAction)increaseFontSize:(id)sender;
{
    [_fontSizeTextWell endEditing:YES/*force*/];
    _setFontSize(self, 1, YES /* relative */);
}

- (IBAction)decreaseFontSize:(id)sender;
{
    [_fontSizeTextWell endEditing:YES/*force*/];
    _setFontSize(self, -1, YES /* relative */);
}

- (IBAction)fontSizeTextWellAction:(OUIInspectorTextWell *)sender;
{
    _setFontSize(self, [[sender text] floatValue], NO /* not relative */);
}

- (void)showFacesForFamilyBaseFont:(UIFont *)font;
{
    _fontFacesPane.showFacesOfFont = font;
    _fontFacesPane.title = OUIDisplayNameForFont(font, YES/*useFamilyName*/);

    [self.inspector pushPane:_fontFacesPane];
}

#pragma mark -
#pragma mark OUIInspectorSlice subclass

- (BOOL)isAppropriateForInspectedObject:(id)object;
{
    return [object shouldBeInspectedByInspectorSlice:self protocol:@protocol(OUIFontInspection)];
}

- (void)updateInterfaceFromInspectedObjects;
{
    [super updateInterfaceFromInspectedObjects];
    
    OUIFontSelection selection = OUICollectFontSelection(self, self.appropriateObjectsForInspection);
        
    CGFloat fontSize = [OUIInspectorTextWell fontSize];

    switch ([selection.fontDescriptors count]) {
        case 0:
            _fontFamilyTextWell.text = NSLocalizedStringFromTableInBundle(@"No Selection", @"OUIInspectors", OMNI_BUNDLE, @"popover inspector label title for no selected objects");
            _fontFamilyTextWell.font = [UIFont systemFontOfSize:fontSize];
            break;
        case 1: {
            OAFontDescriptor *fontDescriptor = [selection.fontDescriptors anyObject];
            CTFontRef font = [fontDescriptor font];
            OBASSERT(font);
            
            if (font) {
                CFStringRef familyName = CTFontCopyFamilyName(font);
                OBASSERT(familyName);
                CFStringRef postscriptName = CTFontCopyPostScriptName(font);
                OBASSERT(postscriptName);
                CFStringRef displayName = CTFontCopyDisplayName(font);
                OBASSERT(displayName);
                
                
                // Using the whole display name gets kinda long in the fixed space we have. Can swap which line is commented below to try it out.
                //_fontFamilyTextWell.text = OUIIsBaseFontNameForFamily((NSString *)postscriptName, (id)familyName) ? (id)familyName : (id)displayName;
                _fontFamilyTextWell.text = (id)familyName;
                _fontFamilyTextWell.font = postscriptName ? [UIFont fontWithName:(id)postscriptName size:fontSize] : [UIFont systemFontOfSize:fontSize];
                
                if (familyName)
                    CFRelease(familyName);
                if (postscriptName)
                    CFRelease(postscriptName);
                if (displayName)
                    CFRelease(displayName);
            }
            break;
        default:
            _fontFamilyTextWell.text = NSLocalizedStringFromTableInBundle(@"Multiple Selection", @"OUIInspectors", OMNI_BUNDLE, @"popover inspector label title for mulitple selection");
            _fontFamilyTextWell.font = [UIFont systemFontOfSize:fontSize];
            break;
        }
    }
    
    switch ([selection.fontDescriptors count]) {
        case 0:
            _fontSizeTextWell.text = nil;
            // leave value where ever it was
            // disable controls? 
            OBASSERT_NOT_REACHED("why are we even visible?");
            break;
        case 1:
            _fontSizeTextWell.text = [NSString stringWithFormat:@"%d", (int)rint(selection.minFontSize)];
            break;
        default:
            _fontSizeTextWell.text = [NSString stringWithFormat:@"%d\u2013%d", (int)floor(selection.minFontSize), (int)ceil(selection.maxFontSize)]; /* Two numbers, en-dash */
            break;
    }
    
    BOOL bold = NO, italic = NO;
    for (OAFontDescriptor *fontDescriptor in selection.fontDescriptors) {
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
#pragma mark UIViewController subclass

- (void)viewDidLoad;
{
    [super viewDidLoad];

    _fontFamilyTextWell.rounded = YES;
    
    [_fontFamilyTextWell setNavigationTarget:self action:@selector(_showFontFamilies:)];
    
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

    _fontSizeDecreaseStepperButton.title = @"A";
    _fontSizeDecreaseStepperButton.titleFont = [UIFont boldSystemFontOfSize:14];
    _fontSizeDecreaseStepperButton.titleColor = [UIColor whiteColor];
    _fontSizeDecreaseStepperButton.flipped = YES;

    _fontSizeIncreaseStepperButton.title = @"A";
    _fontSizeIncreaseStepperButton.titleFont = [UIFont boldSystemFontOfSize:32];
    _fontSizeIncreaseStepperButton.titleColor = [UIColor whiteColor];

    CGFloat fontSize = [OUIInspectorTextWell fontSize];
    _fontSizeTextWell.font = [UIFont boldSystemFontOfSize:fontSize];
    _fontSizeTextWell.label = NSLocalizedStringFromTableInBundle(@"%@ points", @"OUIInspectors", OMNI_BUNDLE, @"font size label format string in points");
    _fontSizeTextWell.labelFont = [UIFont systemFontOfSize:fontSize];
    _fontSizeTextWell.editable = YES;
    [_fontSizeTextWell setKeyboardType:UIKeyboardTypeNumberPad];

    // Superclass does this for the family detail.
    _fontFacesPane.parentSlice = self;
}

#pragma mark -
#pragma mark Private

- (IBAction)_showFontFamilies:(id)sender;
{
    OUIFontInspectorPane *familyPane = (OUIFontInspectorPane *)self.detailPane;
    OBPRECONDITION(familyPane);
    
    familyPane.title = NSLocalizedStringFromTableInBundle(@"Font", @"OUIInspectors", OMNI_BUNDLE, @"Title for the font family list in the inspector");
    familyPane.showFacesOfFont = nil; // shows families
    
    [self.inspector pushPane:familyPane];
}

- (void)_toggleBold:(id)sender;
{
    [self.inspector willBeginChangingInspectedObjects];
    {
        for (id <OUIFontInspection> object in self.appropriateObjectsForInspection) {
            OAFontDescriptor *desc = [object fontDescriptorForInspectorSlice:self];
            desc = [[desc newFontDescriptorWithBold:![desc bold]] autorelease];
            [object setFontDescriptor:desc fromInspectorSlice:self];
        }
    }
    [self.inspector didEndChangingInspectedObjects];
}
- (void)_toggleItalic:(id)sender;
{
    [self.inspector willBeginChangingInspectedObjects];
    {
        for (id <OUIFontInspection> object in self.appropriateObjectsForInspection) {
            OAFontDescriptor *desc = [object fontDescriptorForInspectorSlice:self];
            desc = [[desc newFontDescriptorWithItalic:![desc italic]] autorelease];
            [object setFontDescriptor:desc fromInspectorSlice:self];
        }
    }
    [self.inspector didEndChangingInspectedObjects];
}
- (void)_toggleUnderline:(id)sender;
{
    [self.inspector willBeginChangingInspectedObjects];
    {
        for (id <OUIFontInspection> object in self.appropriateObjectsForInspection) {
            CTUnderlineStyle underline = [object underlineStyleForInspectorSlice:self];
            underline = (underline == kCTUnderlineStyleNone) ? kCTUnderlineStyleSingle : kCTUnderlineStyleNone; // Press and hold for menu someday?
            [object setUnderlineStyle:underline fromInspectorSlice:self];
        }
    }
    [self.inspector didEndChangingInspectedObjects];
}
- (void)_toggleStrikethrough:(id)sender;
{
    [self.inspector willBeginChangingInspectedObjects];
    {
        for (id <OUIFontInspection> object in self.appropriateObjectsForInspection) {
            CTUnderlineStyle strikethrough = [object strikethroughStyleForInspectorSlice:self];
            strikethrough = (strikethrough == kCTUnderlineStyleNone) ? kCTUnderlineStyleSingle : kCTUnderlineStyleNone; // Press and hold for menu someday?
            [object setStrikethroughStyle:strikethrough fromInspectorSlice:self];
        }
    }
    [self.inspector didEndChangingInspectedObjects];
}

@end

