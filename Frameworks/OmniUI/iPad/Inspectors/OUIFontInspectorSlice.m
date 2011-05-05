// Copyright 2010-2011 The Omni Group.  All rights reserved.
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

    [_fontSizeDecreaseStepperButton release];
    [_fontSizeIncreaseStepperButton release];
    [_fontSizeTextWell release];
    [_fontFacesPane release];
    [super dealloc];
}

@synthesize fontFamilyTextWell = _fontFamilyTextWell;
@synthesize fontSizeDecreaseStepperButton = _fontSizeDecreaseStepperButton;
@synthesize fontSizeIncreaseStepperButton = _fontSizeIncreaseStepperButton;
@synthesize fontSizeTextWell = _fontSizeTextWell;
@synthesize fontFacesPane = _fontFacesPane;

static const CGFloat kMinimumFontSize = 2;
static const CGFloat kMaximumFontSize = 128;

static void _setFontSize(OUIFontInspectorSlice *self, CGFloat fontSize, BOOL relative)
{
    OUIInspector *inspector = self.inspector;
    [inspector willBeginChangingInspectedObjects];
    {
        for (id <OUIFontInspection> object in self.appropriateObjectsForInspection) {
            OAFontDescriptor *fontDescriptor = [object fontDescriptorForInspectorSlice:self];
            if (fontDescriptor) {
                CGFloat newSize = relative? ( [fontDescriptor size] + fontSize ) : fontSize;
                if (newSize < kMinimumFontSize)
                    newSize = kMinimumFontSize;
                else if (newSize > kMaximumFontSize)
                    newSize = kMaximumFontSize;
                fontDescriptor = [fontDescriptor newFontDescriptorWithSize:newSize];
            } else {
                UIFont *font = [UIFont systemFontOfSize:[UIFont labelFontSize]];
                CGFloat newSize = relative? ( font.pointSize + fontSize ) : fontSize;
                if (newSize < kMinimumFontSize)
                    newSize = kMinimumFontSize;
                else if (newSize > kMaximumFontSize)
                    newSize = kMaximumFontSize;
                fontDescriptor = [[OAFontDescriptor alloc] initWithFamily:font.familyName size:newSize];
            }
            [object setFontDescriptor:fontDescriptor fromInspectorSlice:self];
            [fontDescriptor release];
        }
    }
    [inspector didEndChangingInspectedObjects];
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

- (OUIFontInspectorSliceFontDisplay)fontNameDisplayForFontDescriptor:(OAFontDescriptor *)fontDescriptor;
{
    OUIFontInspectorSliceFontDisplay display;

    CGFloat fontSize = [OUIInspectorTextWell fontSize];

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
        display.text = OUIIsBaseFontNameForFamily((NSString *)postscriptName, (id)familyName) ? (id)familyName : (id)displayName;
        //display.text = (id)familyName;
        display.font = postscriptName ? [UIFont fontWithName:(id)postscriptName size:fontSize] : [UIFont systemFontOfSize:fontSize];
        
        if (familyName)
            CFRelease(familyName);
        if (postscriptName)
            CFRelease(postscriptName);
        if (displayName)
            CFRelease(displayName);
    } else {
        display.text = @"???";
        display.font = nil;
    }
    
    return display;
}

- (OUIFontInspectorSliceFontDisplay)fontNameDisplayForFontDescriptors:(NSArray *)fontDescriptors;
{
//    CGFloat fontSize = [OUIInspectorTextWell fontSize];
    
    OUIFontInspectorSliceFontDisplay display;
    
    switch ([fontDescriptors count]) {
        case 0:
            display.text = NSLocalizedStringFromTableInBundle(@"No Selection", @"OUIInspectors", OMNI_BUNDLE, @"popover inspector label title for no selected objects");
            display.font = [OUIInspector labelFont];
            break;
        case 1:
            display = [self fontNameDisplayForFontDescriptor:[fontDescriptors objectAtIndex:0]];
            break;
        default:
            display.text = NSLocalizedStringFromTableInBundle(@"Multiple Selection", @"OUIInspectors", OMNI_BUNDLE, @"popover inspector label title for mulitple selection");
            display.font = [OUIInspector labelFont];
            break;
    }
    
    return display;
}

- (void)updateFontSizeTextWellForFontSizes:(NSArray *)fontSizes extent:(OFExtent)fontSizeExtent;
{
    CGFloat fontSize = [OUIInspectorTextWell fontSize];
    _fontSizeTextWell.font = [UIFont systemFontOfSize:fontSize];

    switch ([fontSizes count]) {
        case 0:
            OBASSERT_NOT_REACHED("why are we even visible?");
            // leave value where ever it was
            // disable controls? 
            _fontSizeTextWell.text = nil;
            break;
        case 1:
            _fontSizeTextWell.text = [NSString stringWithFormat:@"%d", (int)rint(OFExtentMin(fontSizeExtent))];
            break;
        default:
            _fontSizeTextWell.text = [NSString stringWithFormat:@"%d\u2013%d", (int)floor(OFExtentMin(fontSizeExtent)), (int)ceil(OFExtentMax(fontSizeExtent))]; /* Two numbers, en-dash */
            break;
    }
}

#pragma mark -
#pragma mark OUIInspectorSlice subclass

- (BOOL)isAppropriateForInspectedObject:(id)object;
{
    return [object shouldBeInspectedByInspectorSlice:self protocol:@protocol(OUIFontInspection)];
}

static void _configureTextWellDisplay(OUIInspectorTextWell *textWell, OUIFontInspectorSliceFontDisplay display)
{
    textWell.text = display.text;
    textWell.font = display.font;
}

- (void)updateInterfaceFromInspectedObjects:(OUIInspectorUpdateReason)reason;
{
    [super updateInterfaceFromInspectedObjects:reason];
    
    OUIFontSelection selection = OUICollectFontSelection(self, self.appropriateObjectsForInspection);
    
    _configureTextWellDisplay(_fontFamilyTextWell, [self fontNameDisplayForFontDescriptors:selection.fontDescriptors]);
    
    [self updateFontSizeTextWellForFontSizes:selection.fontSizes extent:selection.fontSizeExtent];
}

#pragma mark -
#pragma mark UIViewController subclass

- (void)viewDidLoad;
{
    [super viewDidLoad];

    _fontFamilyTextWell.style = OUIInspectorTextWellStyleSeparateLabelAndText;
    _fontFamilyTextWell.label = NSLocalizedStringFromTableInBundle(@"Font", @"OUIInspectors", OMNI_BUNDLE, @"Title for the font family list in the inspector");
    _fontFamilyTextWell.labelFont = [[_fontFamilyTextWell class] defaultLabelFont];
    _fontFamilyTextWell.rounded = YES;
    
    [_fontFamilyTextWell setNavigationTarget:self action:@selector(_showFontFamilies:)];
    
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


@end

