// Copyright 2014-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Cocoa/Cocoa.h>

@interface OIDisclosureButtonCell : NSButtonCell

@property (nonatomic, strong) NSImage *collapsedImage;
@property (nonatomic, strong) NSImage *expandedImage;
@property (nonatomic, strong) NSColor *tintColor;
@property (nonatomic) BOOL showsStateByAlpha;

@end
