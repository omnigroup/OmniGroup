// Copyright 2014-2017 Omni Development. Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OIDisclosureButton.h"

#import <OmniInspector/OIAppearance.h>

#import "OIDisclosureButtonCell.h"

RCS_ID("$Id$");

@implementation OIDisclosureButton
{
    BOOL _hasDarkAppearance;
}

+ (Class)cellClass;
{
    return [OIDisclosureButtonCell class];
}

- (id)initWithFrame:(NSRect)frame;
{
    self = [super initWithFrame:frame];
    if (self == nil) {
        return nil;
    }
    
    [self OIDisclosureButton_commonInit];
    
    return self;
}

- (id)initWithCoder:(NSCoder *)coder;
{
    self = [super initWithCoder:coder];
    if (self == nil) {
        return nil;
    }
    
    [self OIDisclosureButton_commonInit];
    
    return self;
}

- (void)OIDisclosureButton_commonInit;
{
#ifdef OMNI_ASSERTIONS_ON
    Class cellClass = [[self class] cellClass];
    OBASSERT([[self cell] isKindOfClass:cellClass]);
#endif

    [self setImagePosition:NSImageOnly];
    [self setBezelStyle:NSShadowlessSquareBezelStyle];
    [self setButtonType:NSMomentaryPushInButton];
    [self setBordered:NO];

    [[self cell] setImageDimsWhenDisabled:NO];
    [self _updateDarkAppearance:_isDarkAppearance(self.effectiveAppearance)];
}

- (NSImage *)collapsedImage;
{
    OIDisclosureButtonCell *cell = OB_CHECKED_CAST(OIDisclosureButtonCell, self.cell);
    return cell.collapsedImage;
}

- (void)setCollapsedImage:(NSImage *)collapsedImage;
{
    OIDisclosureButtonCell *cell = OB_CHECKED_CAST(OIDisclosureButtonCell, self.cell);
    cell.collapsedImage = collapsedImage;
}

- (NSImage *)expandedImage;
{
    OIDisclosureButtonCell *cell = OB_CHECKED_CAST(OIDisclosureButtonCell, self.cell);
    return cell.collapsedImage;
}

- (void)setExpandedImage:(NSImage *)expandedImage;
{
    OIDisclosureButtonCell *cell = OB_CHECKED_CAST(OIDisclosureButtonCell, self.cell);
    cell.expandedImage = expandedImage;
}

- (BOOL)showsStateByAlpha;
{
    OIDisclosureButtonCell *cell = OB_CHECKED_CAST(OIDisclosureButtonCell, self.cell);
    return cell.showsStateByAlpha;
}

- (void)setShowsStateByAlpha:(BOOL)showsStateByAlpha;
{
    OIDisclosureButtonCell *cell = OB_CHECKED_CAST(OIDisclosureButtonCell, self.cell);
    cell.showsStateByAlpha = showsStateByAlpha;
}

#pragma mark -

static BOOL _isDarkAppearance(NSAppearance *appearance)
{
    return OFISEQUAL(appearance.name, NSAppearanceNameVibrantDark);
}

- (void)viewWillDraw;
{
    [super viewWillDraw];

    BOOL isDarkAppearance = _isDarkAppearance(self.effectiveAppearance);
    if (_hasDarkAppearance != isDarkAppearance) {
        [self _updateDarkAppearance:isDarkAppearance];
    }
}

- (void)_updateDarkAppearance:(BOOL)isDarkAppearance;
{
    NSString *tintColorThemeKey = isDarkAppearance ? _tintColorDarkThemeKey : _tintColorLightThemeKey;
    OIDisclosureButtonCell *cell = OB_CHECKED_CAST(OIDisclosureButtonCell, self.cell);
    cell.tintColor = tintColorThemeKey != nil ? [[OIAppearance appearance] colorForKeyPath:tintColorThemeKey] : nil;
    _hasDarkAppearance = isDarkAppearance;
}

@end
