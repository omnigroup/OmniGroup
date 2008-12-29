// Copyright 2001-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OWF/Processors.subproj/Protocols.subproj/OWAboutURLProcessor.h 68913 2005-10-03 19:36:19Z kc $

#import <OWF/OWAddressProcessor.h>

// This processor implements the non-standard about: url scheme.
// about: appeared in Netscape as a way to get to various browser-internal information. Unfortunately, the "about:blank" URL has become a common way for people to create a blank page or frame from JavaScript. So we have to support it. We implement it as a simple list of aliases for other URLs.


@interface OWAboutURLProcessor : OWAddressProcessor
{
}


@end
