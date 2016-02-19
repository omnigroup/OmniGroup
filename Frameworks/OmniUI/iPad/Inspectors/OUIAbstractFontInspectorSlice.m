// Copyright 2015-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIAbstractFontInspectorSlice.h>

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

@implementation OUIAbstractFontInspectorSliceFontDisplay
@end

@implementation OUIAbstractFontInspectorSlice

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil;
{
    // should usually get these from -[OUIInspectorSlice init] and custom class support.
    OBPRECONDITION(nibNameOrNil);
    OBPRECONDITION(nibBundleOrNil);
    
    if (!(self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil]))
        return nil;

    return self;
}

+ (OUIAbstractFontInspectorSliceFontDisplay *)fontNameDisplayForFontDescriptor:(OAFontDescriptor *)fontDescriptor;
{
    OUIAbstractFontInspectorSliceFontDisplay *display = [OUIAbstractFontInspectorSliceFontDisplay new];

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

+ (OUIAbstractFontInspectorSliceFontDisplay *)fontNameDisplayForFontDescriptors:(NSArray *)fontDescriptors;
{
//    CGFloat fontSize = [OUIInspectorTextWell fontSize];
    
    OUIAbstractFontInspectorSliceFontDisplay *display = [OUIAbstractFontInspectorSliceFontDisplay new];
    
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

#pragma mark - OUIInspectorSlice subclass

- (BOOL)isAppropriateForInspectedObject:(id)object;
{
    return [object shouldBeInspectedByInspectorSlice:self protocol:@protocol(OUIFontInspection)];
}

@end

