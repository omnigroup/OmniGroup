// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIFontInspectorSlice.h>

#import <OmniUI/OUIImages.h>
#import <OmniUI/OUIInspector.h>
#import <OmniUI/OUIInspectorTextWell.h>
#import <OmniUI/OUIInspectorStepperButton.h>
#import <OmniUI/OUIFontInspectorPane.h>
#import <OmniUI/OUIFontUtilities.h>
#import <OmniUI/OUIInspectorSliceView.h>
#import <OmniUI/UIView-OUIExtensions.h>

#import <OmniAppKit/OAFontDescriptor.h>
#import <OmniBase/OmniBase.h>

RCS_ID("$Id$");

@implementation OUIFontInspectorSliceFontDisplay
@end

@implementation OUIFontInspectorSlice
{
    NSNumberFormatter *_wholeNumberFormatter;
    NSNumberFormatter *_fractionalNumberFormatter;
    UIView *_fontSizeControl;
    BOOL _touchIsDown;
}

// TODO: should these be ivars?
static const CGFloat kMinimumFontSize = 2;
static const CGFloat kMaximumFontSize = 128;
static const CGFloat kPrecision = 1000.0f;
    // Font size will be rounded to nearest 1.0f/kPrecision
static const NSString *kDigitsPrecision = @"###";
    // Number of hashes here should match the number of digits after the decimal point in the decimal representation of  1.0f/kPrecision.

static CGFloat _normalizeFontSize(CGFloat fontSize)
{
    CGFloat result = fontSize;

    result = rint(result * kPrecision) / kPrecision;
    
    if (result < kMinimumFontSize)
        result = kMinimumFontSize;
    else if (result > kMaximumFontSize)
        result = kMaximumFontSize;
    
    return result;
}

- (void)_setFontSize:(CGFloat)fontSize;
{
    if (!_touchIsDown) {
        [self.inspector willBeginChangingInspectedObjects];
        _touchIsDown = YES;
    }
    
    for (id <OUIFontInspection> object in self.appropriateObjectsForInspection) {
        OAFontDescriptor *fontDescriptor = [object fontDescriptorForInspectorSlice:self];
        if (fontDescriptor) {
            CGFloat newSize = [fontDescriptor size] + fontSize;
            newSize = _normalizeFontSize(newSize);
            fontDescriptor = [fontDescriptor newFontDescriptorWithSize:newSize];
        } else {
            UIFont *font = [UIFont systemFontOfSize:[UIFont labelFontSize]];
            CGFloat newSize = font.pointSize + fontSize;
            newSize = _normalizeFontSize(newSize);
            fontDescriptor = [[OAFontDescriptor alloc] initWithFamily:font.familyName size:newSize];
        }
        [object setFontDescriptor:fontDescriptor fromInspectorSlice:self];
    }
    
    [self updateInterfaceFromInspectedObjects:OUIInspectorUpdateReasonObjectsEdited];
    UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, self->_fontSizeControl.accessibilityValue);
}

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil;
{
    // should usually get these from -[OUIInspectorSlice init] and custom class support.
    OBPRECONDITION(nibNameOrNil);
    OBPRECONDITION(nibBundleOrNil);
    
    if (!(self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil]))
        return nil;
    
    NSString *baseFormat = @"#,##0";
    
    _wholeNumberFormatter = [[NSNumberFormatter alloc] init];
    [_wholeNumberFormatter setPositiveFormat:baseFormat];
    
    NSString *decimalFormat = [[NSString alloc] initWithFormat:@"%@.%@", baseFormat, kDigitsPrecision];
    
    _fractionalNumberFormatter = [[NSNumberFormatter alloc] init];
    [_fractionalNumberFormatter setPositiveFormat:decimalFormat];
    
    
    return self;
}

- (void)dealloc;
{
    // Attempting to fix ARC weak reference cleanup crasher in <bug:///93163> (Crash after setting font color on Level 1 style)
    _fontFacesPane.parentSlice = nil;
}

- (IBAction)stepperTouchesEnded:(id)sender;
{
    [self.inspector didEndChangingInspectedObjects];
    _touchIsDown = NO;
}

- (IBAction)increaseFontSize:(id)sender;
{
    [self _setFontSize:1];
}

- (IBAction)decreaseFontSize:(id)sender;
{
    [self _setFontSize:-1];
}

- (void)showFacesForFamilyBaseFont:(UIFont *)font;
{
    _fontFacesPane.showFacesOfFont = font;
    _fontFacesPane.title = OUIDisplayNameForFont(font, YES/*useFamilyName*/);

    [self.inspector pushPane:_fontFacesPane];
}

- (OUIFontInspectorSliceFontDisplay *)fontNameDisplayForFontDescriptor:(OAFontDescriptor *)fontDescriptor;
{
    OUIFontInspectorSliceFontDisplay *display = [OUIFontInspectorSliceFontDisplay new];

    CGFloat fontSize = [OUIInspectorTextWell fontSize];

    UIFont *font = [fontDescriptor font];
    OBASSERT(font);
    
    if (font) {
        NSString *familyName = font.familyName;
        OBASSERT(familyName);
        
        NSString *postscriptName = font.fontName;
        OBASSERT(postscriptName);
        
        NSString *displayName = OUIDisplayNameForFont(font, NO/*useFamilyName*/);
        OBASSERT(displayName);
        
        // Using the whole display name gets kinda long in the fixed space we have. Can swap which line is commented below to try it out.
        display.text = OUIIsBaseFontNameForFamily(postscriptName, familyName) ? familyName : displayName;
        //display.text = (id)familyName;
        display.font = postscriptName ? [UIFont fontWithName:postscriptName size:fontSize] : [UIFont systemFontOfSize:fontSize];
        
    } else {
        display.text = @"???";
        display.font = nil;
    }
    
    return display;
}

- (OUIFontInspectorSliceFontDisplay *)fontNameDisplayForFontDescriptors:(NSArray *)fontDescriptors;
{
//    CGFloat fontSize = [OUIInspectorTextWell fontSize];
    
    OUIFontInspectorSliceFontDisplay *display = [OUIFontInspectorSliceFontDisplay new];
    
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

- (UIView *)makeFontSizeControlWithFrame:(CGRect)frame; // Return a new view w/o adding it to the view heirarchy

{
    UILabel *label = [[UILabel alloc] initWithFrame:frame];
    label.textColor = [OUIInspector disabledLabelTextColor];
    label.font = [UIFont boldSystemFontOfSize:[OUIInspectorTextWell fontSize]];
    return label;
}

- (void)updateFontSizeControl:(UIView *)fontSizeControl forFontSizes:(NSArray *)fontSizes extent:(OFExtent)fontSizeExtent;
{
    NSString *valueText;
    
    switch ([fontSizes count]) {
        case 0:
            OBASSERT_NOT_REACHED("why are we even visible?");
            // leave value where ever it was
            // disable controls? 
            valueText = nil;
            break;
        case 1:
            valueText = [self _formatFontSize:OFExtentMin(fontSizeExtent)];
            break;
        default:
            {
                CGFloat minSize = floor(OFExtentMin(fontSizeExtent));
                CGFloat maxSize = ceil(OFExtentMax(fontSizeExtent));

                // If either size is fractional, slap a ~ on the front.
                NSString *format = nil;
                if (minSize != OFExtentMin(fontSizeExtent) || maxSize != OFExtentMax(fontSizeExtent)) 
                    format = @"~ %@\u2013%@";  /* tilde, two numbers, en-dash */
                else
                    format = @"%@\u2013%@";  /* two numbers, en-dash */
                valueText = [NSString stringWithFormat:format, [self _formatFontSize:minSize], [self _formatFontSize:maxSize]];
            }
            break;
    }
    
    NSString *text = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"%@ points", @"OUIInspectors", OMNI_BUNDLE, @"font size label format string in points"), valueText];

    [self updateFontSizeControl:_fontSizeControl withText:text];
}

- (void)updateFontSizeControl:(UIView *)fontSizeControl withText:(NSString *)text;
{
    UILabel *label = OB_CHECKED_CAST(UILabel, fontSizeControl);
    label.text = text;
}

#pragma mark - OUIInspectorSlice subclass

- (BOOL)isAppropriateForInspectedObject:(id)object;
{
    return [object shouldBeInspectedByInspectorSlice:self protocol:@protocol(OUIFontInspection)];
}


- (CGFloat)paddingToInspectorLeft;
{
    return 0.0f; // Stretch all the way to the left
}

- (CGFloat)paddingToInspectorRight;
{
    return 0.0f; // stretch all the way to the right
}

static void _configureTextWellDisplay(OUIInspectorTextWell *textWell, OUIFontInspectorSliceFontDisplay *display)
{
    textWell.text = display.text;
    textWell.font = display.font;
}

- (void)updateInterfaceFromInspectedObjects:(OUIInspectorUpdateReason)reason;
{
    [super updateInterfaceFromInspectedObjects:reason];
    
    OUIFontSelection *selection = OUICollectFontSelection(self, self.appropriateObjectsForInspection);
    
    _configureTextWellDisplay(_fontFamilyTextWell, [self fontNameDisplayForFontDescriptors:selection.fontDescriptors]);
    
    OUIWithoutAnimating(^{
        [self updateFontSizeControl:_fontSizeControl forFontSizes:selection.fontSizes extent:selection.fontSizeExtent];
    });
}

#pragma mark - UIViewController subclass

- (void)viewDidLoad;
{
    [super viewDidLoad];
    
    CGRect superBounds = _fontFamilyTextWell.superview.bounds;
    UIEdgeInsets alignmentInsets = self.alignmentInsets;
    
    _fontFamilyTextWell.style = OUIInspectorTextWellStyleSeparateLabelAndText;
    _fontFamilyTextWell.backgroundType = OUIInspectorWellBackgroundTypeNormal;
    _fontFamilyTextWell.label = NSLocalizedStringFromTableInBundle(@"Font", @"OUIInspectors", OMNI_BUNDLE, @"Title for the font family list in the inspector");
    _fontFamilyTextWell.labelFont = [[_fontFamilyTextWell class] defaultLabelFont];
    _fontFamilyTextWell.cornerType = OUIInspectorWellCornerTypeLargeRadius;
    // Fixup the text well's frame so the content aligns with the alignment insets
    {
        UIEdgeInsets borderEdgeInsets = _fontFamilyTextWell.borderEdgeInsets;
        CGRect frame = _fontFamilyTextWell.frame;
        frame.origin.x = CGRectGetMinX(superBounds) + alignmentInsets.left - borderEdgeInsets.left;
        frame.size.width = CGRectGetMaxX(superBounds) - CGRectGetMinX(frame) - alignmentInsets.right + borderEdgeInsets.right;
        _fontFamilyTextWell.frame = frame;
    }
    
    [_fontFamilyTextWell setNavigationTarget:self action:@selector(_showFontFamilies:)];
    [(UIImageView *)_fontFamilyTextWell.rightView setHighlightedImage:[OUIInspectorWell navigationArrowImageHighlighted]];
    
    _fontSizeDecreaseStepperButton.image = OUIStepperMinusImage();
    _fontSizeDecreaseStepperButton.accessibilityLabel = NSLocalizedStringFromTableInBundle(@"Font smaller", @"OUIInspectors", OMNI_BUNDLE, @"Decrement font size button accessibility label");
    [_fontSizeDecreaseStepperButton addTarget:self action:@selector(stepperTouchesEnded:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside| UIControlEventTouchCancel];
    _fontSizeIncreaseStepperButton.image = OUIStepperPlusImage();
    _fontSizeIncreaseStepperButton.accessibilityLabel = NSLocalizedStringFromTableInBundle(@"Font bigger", @"OUIInspectors", OMNI_BUNDLE, @"Increment font size button accessibility label");
    [_fontSizeIncreaseStepperButton addTarget:self action:@selector(stepperTouchesEnded:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside| UIControlEventTouchCancel];

    // Put the font size control beside the two buttons.
    CGRect decreaseStepperFrame = _fontSizeDecreaseStepperButton.frame;
    CGRect fontSizeFrame;
    fontSizeFrame.size.width = 110.0f;
    fontSizeFrame.size.height = CGRectGetHeight(decreaseStepperFrame);
    fontSizeFrame.origin.x = CGRectGetMinX(decreaseStepperFrame) - 8.0f - fontSizeFrame.size.width;
    fontSizeFrame.origin.y = CGRectGetMinY(decreaseStepperFrame);
    _fontSizeControl = [self makeFontSizeControlWithFrame:fontSizeFrame];
    _fontSizeControl.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [_fontSizeDecreaseStepperButton.superview addSubview:_fontSizeControl];
    _fontSizeControl.accessibilityLabel = @"Font size";
    
    CGRect fontSizeLabelFrame = _fontSizeLabel.frame;
    fontSizeLabelFrame.origin.x = alignmentInsets.left;
    fontSizeLabelFrame.size.width = CGRectGetMinX(fontSizeFrame) - 8.0f /* spacing between controls */ - CGRectGetMinX(fontSizeLabelFrame);
    _fontSizeLabel.frame = fontSizeLabelFrame;
    _fontSizeLabel.text = NSLocalizedStringFromTableInBundle(@"Size", @"OUIInspectors", OMNI_BUNDLE, @"Label for font size controls");
    
    // Add a separator line between the two effective slices we contain
    superBounds = _fontSizeDecreaseStepperButton.superview.bounds;
    CGRect separatorFrame = CGRectMake(CGRectGetMinX(superBounds), CGRectGetMinY(_fontFamilyTextWell.frame) - 1.0f, CGRectGetWidth(superBounds), 1.0f);
    OUIInspectorSliceView *separatorView = [[OUIInspectorSliceView alloc] initWithFrame:separatorFrame];
    separatorView.inspectorSliceGroupPosition = OUIInspectorSliceGroupPositionCenter;
    separatorView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [_fontSizeDecreaseStepperButton.superview addSubview:separatorView];

    // Superclass does this for the family detail.
    _fontFacesPane.parentSlice = self;
}

#pragma mark - Private

- (IBAction)_showFontFamilies:(id)sender;
{
    OUIFontInspectorPane *familyPane = (OUIFontInspectorPane *)self.detailPane;
    OBPRECONDITION(familyPane);
    
    familyPane.title = NSLocalizedStringFromTableInBundle(@"Font", @"OUIInspectors", OMNI_BUNDLE, @"Title for the font family list in the inspector");
    familyPane.showFacesOfFont = nil; // shows families
    
    [self.inspector pushPane:familyPane];
}

- (NSString *)_formatFontSize:(CGFloat)fontSize;
{
    CGFloat displaySize = _normalizeFontSize(fontSize);
    NSNumberFormatter *formatter = nil;
    if (rint(displaySize) != displaySize)
        formatter = _fractionalNumberFormatter;
    else
        formatter = _wholeNumberFormatter;
    
    return [formatter stringFromNumber:[NSNumber numberWithDouble:displaySize]];
}

@end

