// Copyright 2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
#import <Foundation/NSNetServices.h>
#endif

@interface OFNetChangeNotifier : NSObject 
#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
<NSNetServiceDelegate, NSNetServiceBrowserDelegate>
#endif
{
    id nonretainedDelegate;
    NSString *uuidString;
    NSDate *lastChangeDate, *lastUpdateDate;
    NSNetService *notifierService;
    NSNetServiceBrowser *browser; 
    NSMutableDictionary *watchedServices;
}

- initWithUUIDString:(NSString *)aString lastUpdateDate:(NSDate *)anUpdateDate delegate:(id)aDelegate;

- (void)setLastChangedDate:(NSDate *)aDate;
- (void)setLastUpdateDate:(NSDate *)aDate;

@end

@protocol OFNetChangeNotifierDelegate
- (void)netChangeNotifierNewChange:(OFNetChangeNotifier *)notifier;
@end

