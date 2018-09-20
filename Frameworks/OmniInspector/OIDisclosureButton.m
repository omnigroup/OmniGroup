// Copyright 2014-2018 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OIDisclosureButton.h"

#import <OmniAppKit/NSAppearance-OAExtensions.h>
#import <OmniInspector/OIAppearance.h>

#import "OIDisclosureButtonCell.h"

RCS_ID("$Id$");

@implementation OIDisclosureButton {
    BOOL _hasDarkAppearance;
}

static BOOL _isDarkAppearance(NSAppearance *appearance)
{
    return appearance.OA_isDarkAppearance;
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
    [self _updateDarkAppearance:_isDarkAppearance(self.effectiveAppearance)];
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
    OADisclosureButtonCell *cell = OB_CHECKED_CAST(OADisclosureButtonCell, self.cell);
    cell.tintColor = tintColorThemeKey != nil ? [[OIAppearance appearance] colorForKeyPath:tintColorThemeKey] : nil;
    _hasDarkAppearance = isDarkAppearance;
}

@end
