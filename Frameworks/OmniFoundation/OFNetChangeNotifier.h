// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>
#import <Foundation/NSNetServices.h>
#import <OmniFoundation/OFFeatures.h>

#if !OF_ENABLE_NET_STATE
#error Should not be imported on this platform
#endif

@interface OFNetChangeNotifier : NSObject <NSNetServiceDelegate, NSNetServiceBrowserDelegate>
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
