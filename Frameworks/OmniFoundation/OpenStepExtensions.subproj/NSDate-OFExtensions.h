// Copyright 1997-2005, 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniFoundation/OpenStepExtensions.subproj/NSDate-OFExtensions.h 104649 2008-09-09 07:07:00Z kc $

#import <Foundation/NSDate.h>

@class NSCalendar, NSString, NSTimeZone;

@interface NSDate (OFExtensions)

- (NSString *)descriptionWithHTTPFormat; // rfc1123 format with TZ forced to GMT

- (void)sleepUntilDate;

- (BOOL)isAfterDate: (NSDate *) otherDate;
- (BOOL)isBeforeDate: (NSDate *) otherDate;

// XML Schema / ISO 8601 support
+ (NSTimeZone *)UTCTimeZone;
+ (NSCalendar *)gregorianUTCCalendar;

// date formatted according to http://www.w3.org/2001/XMLSchema-datatypes
- initWithXMLDateString:(NSString *)xmlString;
- (NSString *)xmlDateString;

- initWithXMLString:(NSString *)xmlString;
// dateTime formatted according to http://www.w3.org/2001/XMLSchema-datatypes
- (NSString *)xmlString;

@end
