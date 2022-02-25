// Copyright 2015-2022 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIFontFamilyInspectorSlice.h>

@import OmniBase;
@import OmniFoundation.OFPreference;
@import OmniAppKit.OAFontDescriptor;

#import <OmniUI/OUIAbstractFontInspectorSlice.h>
#import <OmniUI/OUIImages.h>
#import <OmniUI/OUIInspector.h>
#import <OmniUI/OUIInspectorTextWell.h>
#import <OmniUI/OUIFontInspectorPane.h>
#import <OmniUI/OUIFontUtilities.h>
#import <OmniUI/OUIInspectorSliceView.h>
#import <OmniUI/UIView-OUIExtensions.h>

@interface OUIFontFamilyInspectorSlice () <UIFontPickerViewControllerDelegate>
@end

@implementation OUIFontFamilyInspectorSlice

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil;
{
    return [self initWithTitle:NSLocalizedStringFromTableInBundle(@"Font", @"OUIInspectors", OMNI_BUNDLE, @"Inspector slice title for font family")
                        action:@selector(_showFontFamilies:)];
}

- (void)showFacesForFamilyBaseFont:(UIFont *)font;
{
    _fontFacesPane.showFacesOfFont = font;
    _fontFacesPane.title = OUIDisplayNameForFont(font, YES/*useFamilyName*/);

    [self.inspector pushPane:_fontFacesPane];
}

- (UIFontPickerViewControllerConfiguration *)fontPickerConfiguration;
{
    UIFontPickerViewControllerConfiguration *fontConfig = [[UIFontPickerViewControllerConfiguration alloc] init];
    fontConfig.includeFaces = YES;
    return fontConfig;
}

#pragma mark - OUIActionInspectorSlice subclass

+ (OUIInspectorTextWellStyle)textWellStyle;
{
    return OUIInspectorTextWellStyleSeparateLabelAndText;
}

+ (OUIInspectorWellBackgroundType)textWellBackgroundType;
{
    return OUIInspectorWellBackgroundTypeNormal;
}

#pragma mark - OUIInspectorSlice subclass

- (BOOL)isAppropriateForInspectedObject:(id)object;
{
    return [object shouldBeInspectedByInspectorSlice:self protocol:@protocol(OUIFontInspection)];
}

static void _configureTextWellDisplay(OUIInspectorTextWell *textWell, OUIAbstractFontInspectorSliceFontDisplay *display)
{
    textWell.text = display.text;
    textWell.font = display.font;
}

- (void)updateInterfaceFromInspectedObjects:(OUIInspectorUpdateReason)reason;
{
    [super updateInterfaceFromInspectedObjects:reason];
    
    OUIFontSelection *selection = OUICollectFontSelection(self, self.appropriateObjectsForInspection);

    id displayClass;
    if ([self respondsToSelector:@selector(fontNameDisplayForFontDescriptors:)]) {
        displayClass = self;
    } else {
        displayClass = [OUIAbstractFontInspectorSlice class];
    }
    _configureTextWellDisplay(self.textWell, [displayClass fontNameDisplayForFontDescriptors:selection.fontDescriptors]);
}

#pragma mark - UIViewController subclass

- (void)viewDidLoad;
{
    [super viewDidLoad];

    self.textWell.label = NSLocalizedStringFromTableInBundle(@"Font", @"OUIInspectors", OMNI_BUNDLE, @"Title for the font family list in the inspector");
    self.textWell.labelFont = [[self.textWell class] defaultLabelFont];
    [self.textWell setNavigationTarget:self action:@selector(_showFontFamilies:)];

    // Setup detail pane
    OUIFontInspectorPane *familiesPane = [[OUIFontInspectorPane alloc] init];
    self.detailPane = familiesPane;
    UITableView *fontFamiliesTableView = [[UITableView alloc] init];
    fontFamiliesTableView.delegate = familiesPane;
    fontFamiliesTableView.dataSource = familiesPane;
    familiesPane.view = fontFamiliesTableView;

    // setup font faces pane.
    _fontFacesPane = [[OUIFontInspectorPane alloc] init];
    UITableView *fontFacesTableView = [[UITableView alloc] init];
    fontFacesTableView.delegate = _fontFacesPane;
    fontFacesTableView.dataSource = _fontFacesPane;
    _fontFacesPane.view = fontFacesTableView;

    // Superclass does this for the family detail.
    _fontFacesPane.parentSlice = self;
}

#pragma mark - Private

- (IBAction)_showFontFamilies:(id)sender;
{
    NSString *title = NSLocalizedStringFromTableInBundle(@"Font", @"OUIInspectors", OMNI_BUNDLE, @"Title for the font family list in the inspector");
    if ([[OFPreference preferenceForKey:@"UseLegacyFontPicker" defaultValue:@NO] boolValue]) {
        OUIFontInspectorPane *familyPane = (OUIFontInspectorPane *)self.detailPane;
        OBPRECONDITION(familyPane);

        familyPane.title = title;
        familyPane.showFacesOfFont = nil; // shows families
        [self.inspector pushPane:familyPane];
    } else {
        UIFontPickerViewController *fontPicker = [[UIFontPickerViewController alloc] initWithConfiguration:self.fontPickerConfiguration];
        fontPicker.title = title;
        fontPicker.delegate = self;
        OUIFontSelection *selection = OUICollectFontSelection(self, self.appropriateObjectsForInspection);
        NSArray <OAFontDescriptor *> *fontDescriptors = selection.fontDescriptors;
        fontPicker.selectedFontDescriptor = fontDescriptors.firstObject.font.fontDescriptor;
        [self.navigationController pushViewController:fontPicker animated:YES];
    }
}

#pragma mark - UIFontPickerViewControllerDelegate protocol

- (void)fontPickerViewControllerDidPickFont:(UIFontPickerViewController *)viewController;
{
    UIFontDescriptor *uiFontDescriptor = viewController.selectedFontDescriptor;
    UIFont *font = [UIFont fontWithDescriptor:uiFontDescriptor size:0.0];

    OUIInspector *inspector = self.inspector;
    [inspector willBeginChangingInspectedObjects];
    {
        for (id <OUIFontInspection> object in self.appropriateObjectsForInspection) {
            // Grab any existing font size in order to preserve it
            OAFontDescriptor *fontDescriptor = [object fontDescriptorForInspectorSlice:self];
            CGFloat fontSize;
            if (fontDescriptor)
                fontSize = [fontDescriptor size];
            else
                fontSize = [UIFont labelFontSize];

            // We're looking at font faces within a family; create a font descriptor for the newly-selected item (font face)
            fontDescriptor = [[OAFontDescriptor alloc] initWithFont:font];
            fontDescriptor = [fontDescriptor newFontDescriptorWithSize:fontSize];

            if (fontDescriptor) {
                [object setFontDescriptor:fontDescriptor fromInspectorSlice:self];
            }
        }
    }
//    FinishUndoGroup();  // I think this should be here for Graffle iOS, but our build dependencies won't allow it and testing shows this isn't currently a problem
    [inspector didEndChangingInspectedObjects];

}

@end

