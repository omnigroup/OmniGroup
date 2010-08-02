// Copyright 2003-2005, 2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <AppKit/NSColorWell.h>

#import <AppKit/NSNibDeclarations.h> // For IBAction, IBOutlet

@interface OAColorWell : NSColorWell
{
    BOOL _showsColorWhenDisabled;
}

+ (NSColor *)inactiveColor;

+ (BOOL)hasActiveColorWell;
+ (NSArray *)activeColorWells;
+ (void)deactivateAllColorWells;

@property(nonatomic,assign) BOOL showsColorWhenDisabled;

@end

extern NSString * const OAColorWellWillActivate;
