// Copyright 2008, 2010-2011 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniAppKit/OAColorProfile.h>
#import <ApplicationServices/ApplicationServices.h>
#import <OmniAppKit/OAFeatures.h>


@interface OAColorProfile (Deprecated)
#if OA_USE_COLOR_MANAGER
- (BOOL)_rawProfileIsBuiltIn:(CMProfileRef)rawProfile;
#endif
@end
