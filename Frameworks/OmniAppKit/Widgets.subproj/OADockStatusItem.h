// Copyright 2001-2005, 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>

@class NSColor, NSImage;

#import <Foundation/NSGeometry.h>

@interface OADockStatusItem : NSObject 
{
    NSImage *icon;
    NSUInteger count;
    BOOL isHidden;
}

- initWithIcon:(NSImage *)newIcon;

// API
- (void)setCount:(NSUInteger)aCount;
- (void)setNoCount;

- (void)hide;
- (void)show;
- (BOOL)isHidden;

@end
