// Copyright 2001-2006 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OWF/Processors.subproj/OWFilteredAddressCache.h 79093 2006-09-08 00:05:45Z kc $

#import <OmniFoundation/OFObject.h>

#import "OWContentCacheProtocols.h" // For OWCacheArcProvider;

@interface OWFilteredAddressCache : OFObject <OWCacheArcProvider>
{
}

@end

#define OWFilteredAddressErrorName (@"FilteredAddress")

