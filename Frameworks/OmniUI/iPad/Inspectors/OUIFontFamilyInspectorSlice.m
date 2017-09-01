// Copyright 2015-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIFontFamilyInspectorSlice.h>

#import <OmniUI/OUIAbstractFontInspectorSlice.h>
#import <OmniUI/OUIImages.h>
#import <OmniUI/OUIInspector.h>
#import <OmniUI/OUIInspectorTextWell.h>
#import <OmniUI/OUIFontInspectorPane.h>
#import <OmniUI/OUIFontUtilities.h>
#import <OmniUI/OUIInspectorSliceView.h>
#import <OmniUI/UIView-OUIExtensions.h>

#import <OmniAppKit/OAFontDescriptor.h>
#import <OmniBase/OmniBase.h>

RCS_ID("$Id$");

@implementation OUIFontFamilyInspectorSlice

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil;
{
    return [self initWithTitle:NSLocalizedStringFromTableInBundle(@"Font", @"OUIInspectors", OMNI_BUNDLE, @"Inspector slice title for font family")
                        action:@selector(_showFontFamilies:)];
}

- (void)dealloc;
{
    // Attempting to fix ARC weak reference cleanup crasher in <bug:///93163> (Crash after setting font color on Level 1 style)
    _fontFacesPane.parentSlice = nil;
}

- (void)showFacesForFamilyBaseFont:(UIFont *)font;
{
    _fontFacesPane.showFacesOfFont = font;
    _fontFacesPane.title = OUIDisplayNameForFont(font, YES/*useFamilyName*/);

    [self.inspector pushPane:_fontFacesPane];
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

- (void)loadView;
{
    [super loadView];

    self.textWell.label = NSLocalizedStringFromTableInBundle(@"Font", @"OUIInspectors", OMNI_BUNDLE, @"Title for the font family list in the inspector");
    self.textWell.labelFont = [[self.textWell class] defaultLabelFont];
    [self.textWell setNavigationTarget:self action:@selector(_showFontFamilies:)];
}

- (void)viewDidLoad;
{
    [super viewDidLoad];

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
    OUIFontInspectorPane *familyPane = (OUIFontInspectorPane *)self.detailPane;
    OBPRECONDITION(familyPane);
    
    familyPane.title = NSLocalizedStringFromTableInBundle(@"Font", @"OUIInspectors", OMNI_BUNDLE, @"Title for the font family list in the inspector");
    familyPane.showFacesOfFont = nil; // shows families
    [self.inspector pushPane:familyPane];
}

@end

