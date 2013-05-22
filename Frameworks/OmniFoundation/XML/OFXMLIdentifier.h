// Copyright 2004-2005, 2007-2008, 2010, 2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSString.h>
#import <OmniBase/objc.h>

@class NSData;

extern BOOL OFXMLIsValidID(NSString *identifier);
extern NSString *OFXMLCreateID(void) NS_RETURNS_RETAINED;
extern NSString *OFXMLCreateIDFromData(NSData *data) NS_RETURNS_RETAINED;

