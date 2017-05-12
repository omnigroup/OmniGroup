// Copyright 2008-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniDataObjects/ODOVersion.h>

#if !defined(NON_OMNI_BUILD_ENVIRONMENT)

// In the case of the standalone framework, this will be generated from it.  Otherwise from the wrapper iPhone app.
#import "SVNVersion.h"

RCS_ID("$Id$")

const uint32_t ODOVersionNumber = SVNREVISION;

#endif
