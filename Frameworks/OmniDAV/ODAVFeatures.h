// Copyright 2008-2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Availability.h>

// If on, use NSURLSession frokm iOS 7 and Mac OS X 10.9, otherwise NSURLConnection.
// Off for now due to Radar 14563278: NSURLSession PUT with zero byte data hangs and annoys Apache
#define ODAV_NSURLSESSION 0

#if ODAV_NSURLSESSION
#define ODAV_NSURLSESSIONCONFIGURATION_CLASS NSURLSessionConfiguration
#else
#define ODAV_NSURLSESSIONCONFIGURATION_CLASS ODAVConnectionConfiguration
#endif
