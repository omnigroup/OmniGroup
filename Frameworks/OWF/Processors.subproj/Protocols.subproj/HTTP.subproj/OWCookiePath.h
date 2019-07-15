// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFObject.h>
#import <OmniFoundation/OFDataBuffer.h>

@class NSArray, NSMutableArray;
@class OWCookie;

@interface OWCookiePath : OFObject
{
    NSString *_path;
    NSMutableArray *_cookies;
}

- initWithPath:(NSString *)aPath;

- (NSString *)path;

- (BOOL)appliesToPath:(NSString *)fetchPath;

- (void)addCookie:(OWCookie *)cookie;
- (void)removeCookie:(OWCookie *)cookie;
- (NSArray *)cookies;

- (OWCookie *)cookieNamed:(NSString *)name;

// For use by OWCookieDomain
- (void)addCookie:(OWCookie *)cookie andNotify:(BOOL)shouldNotify;
- (void)addNonExpiredCookiesToArray:(NSMutableArray *)array usageIsSecure:(BOOL)secure includeRejected:(BOOL)includeRejected;
- (void)addCookiesToSaveToArray:(NSMutableArray *)array;
                       
@end
