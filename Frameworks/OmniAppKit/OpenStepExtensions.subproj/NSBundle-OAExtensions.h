// Copyright 1997-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSBundle.h>

@interface NSBundle (OAExtensions)
- (void)loadNibNamed:(NSString *)nibName owner:(id <NSObject>)owner;
    // Raises an exception if unable to load successfully
@end
