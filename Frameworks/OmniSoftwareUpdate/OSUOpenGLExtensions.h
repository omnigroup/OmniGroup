// Copyright 2002-2005, 2007, 2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

extern CFStringRef OSUCopyCompactedOpenGLExtensionsList(CFStringRef extList) CF_RETURNS_RETAINED;
extern CFSetRef OSUCopyParsedOpenGLExtensionsList(CFStringRef extList) CF_RETURNS_RETAINED;

#ifdef DEBUG
void OSULogTestGLExtensionCompressionTestVector(void);
#endif
