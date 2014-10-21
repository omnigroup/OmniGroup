// Copyright 2012-2014 Omni Development. Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import "OABoxSeparator.h"

// This subclass extends the color customization of OABoxSeparator further to
// allow you to assign an NSGradient for line and background drawing. If
// lineGradient or backgroundGradient are not assigned, the class falls back on
// OABoxSeparator's lineColor and backgroundColor properties, respectively, to
// create a three-stop gradient going from 0% alpha to 100% and back again.

@class NSGradient;

@interface OAGradientBoxSeparator : OABoxSeparator

@property (nonatomic, retain) NSGradient *lineGradient;
@property (nonatomic, retain) NSGradient *backgroundGradient;

@end
