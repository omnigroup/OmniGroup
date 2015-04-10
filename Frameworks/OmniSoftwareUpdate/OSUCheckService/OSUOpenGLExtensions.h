// Copyright 2002-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

extern NSString *OSUCopyCompactedOpenGLExtensionsList(NSString *extList) NS_RETURNS_RETAINED;
extern NSSet *OSUCopyParsedOpenGLExtensionsList(NSString *extList) NS_RETURNS_RETAINED;

#ifdef DEBUG
void OSULogTestGLExtensionCompressionTestVector(void);
#endif
