// Copyright 2013-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFBijection.h>

@class NSMapTable;

@interface OFBijection ()

@property (nonatomic, strong) NSMapTable *keysToObjects;
@property (nonatomic, strong) NSMapTable *objectsToKeys;

#if defined(OMNI_ASSERTIONS_ON)
- (BOOL)checkInvariants;
#endif

@end
