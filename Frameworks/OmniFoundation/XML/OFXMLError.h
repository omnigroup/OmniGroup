// Copyright 2003-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.


/*
 Note: This header is public, but excluded from the module so that we don't pull in libxml.
 */

#import <libxml/parser.h>
#import <libxml/xmlerror.h>
#import <OmniBase/objc.h>

@class NSError;

// Returns nil if the error should be ignored.
NSError *OFXMLCreateError(xmlErrorPtr error) NS_RETURNS_RETAINED;
