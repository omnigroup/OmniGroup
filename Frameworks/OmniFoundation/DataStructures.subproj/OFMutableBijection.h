// Copyright 2013-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFBijection.h>

@interface OFMutableBijection : OFBijection

- (void)setObject:(id)anObject forKey:(id)aKey;
- (void)setKey:(id)aKey forObject:(id)anObject;

- (void)setObject:(id)anObject forKeyedSubscript:(id)aKey;

- (void)invert;

@end
