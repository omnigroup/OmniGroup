// Copyright 2016-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSCache.h>
#import <cache.h>

@interface NSCache (OFExtensions)

#ifdef DEBUG

// These methods use SPI and should be used for debug purposes in DEBUG builds only
- (void *)omni_cache_t;
- (void)omni_debug_printCache;
- (NSDictionary *)omni_debug_asDictionary;

#endif // DEBUG

@end
