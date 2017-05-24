// Copyright 2014-2017 Omni Development. Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <AppKit/NSButton.h>

@interface OIDisclosureButton : NSButton

@property (nonatomic, strong) IBInspectable NSImage *collapsedImage;
@property (nonatomic, strong) IBInspectable NSImage *expandedImage;
@property (nonatomic, strong) IBInspectable NSString *tintColorDarkThemeKey;
@property (nonatomic, strong) IBInspectable NSString *tintColorLightThemeKey;
@property (nonatomic) IBInspectable BOOL showsStateByAlpha;

@end
