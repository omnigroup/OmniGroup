// Copyright 2014-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <AppKit/NSButton.h>

@interface OADisclosureButton : NSButton

@property (nonatomic, strong) IBInspectable NSImage *collapsedImage;
@property (nonatomic, strong) IBInspectable NSImage *expandedImage;
@property (nonatomic) IBInspectable BOOL showsStateByAlpha;

@end
