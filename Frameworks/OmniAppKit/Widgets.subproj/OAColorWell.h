// Copyright 2003-2005 Omni Development, Inc.  All rights reserved.
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
+ (BOOL)hasActiveColorWell;
+ (NSArray *)activeColorWells;
+ (void)deactivateAllColorWells;

- (IBAction)setPatternColorByPickingImage:(id)sender;

@end

extern NSString * const OAColorWellWillActivate;
