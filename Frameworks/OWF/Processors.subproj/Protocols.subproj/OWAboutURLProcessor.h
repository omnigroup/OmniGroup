// Copyright 2001-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OWF/OWAddressProcessor.h>

// This processor implements the non-standard about: url scheme.
// about: appeared in Netscape as a way to get to various browser-internal information. Unfortunately, the "about:blank" URL has become a common way for people to create a blank page or frame from JavaScript. So we have to support it. We implement it as a simple list of aliases for other URLs.


@interface OWAboutURLProcessor : OWAddressProcessor
{
}


@end
