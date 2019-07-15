// Copyright 2014-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <AppKit/NSButtonCell.h>

@interface OADisclosureButtonCell : NSButtonCell

@property (nonatomic, strong) NSImage *collapsedImage;
@property (nonatomic, strong) NSImage *expandedImage;
@property (nonatomic, strong) NSColor *tintColor;
@property (nonatomic) BOOL showsStateByAlpha;

@end
