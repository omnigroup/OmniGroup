// Copyright 2012-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OABoxSeparator.h>

// This subclass extends the color customization of OABoxSeparator further to
// allow you to assign an NSGradient for line and background drawing. If
// lineGradient or backgroundGradient are not assigned, the class falls back on
// OABoxSeparator's lineColor and backgroundColor properties, respectively, to
// create a three-stop gradient going from 0% alpha to 100% and back again.

@class NSGradient;

@interface OAGradientBoxSeparator : OABoxSeparator

@property (nonatomic, strong) NSGradient *lineGradient;
@property (nonatomic, strong) NSGradient *backgroundGradient;

@end
