// Copyright 2001-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniFoundation/DataStructures.subproj/OFClobberDetectionZone.h 69339 2005-10-17 23:59:02Z wiml $

#import <malloc/malloc.h>

extern malloc_zone_t *OFClobberDetectionZoneCreate(void);

extern void OFUseClobberDetectionZoneAsDefaultZone(void);
