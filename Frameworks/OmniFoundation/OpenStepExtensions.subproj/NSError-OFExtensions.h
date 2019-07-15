// Copyright 2016-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSError.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSError (OFExtensions)

/// Returns self or underlying server certificate error; or nil.
- (nullable NSError *)serverCertificateError;

/// Returns an error with the same domain and code as the receiver, but with the key/value pairs in the given userInfo dictionary merged into the receiver's existing userInfo. If the given dictionary shares a key with the existing userInfo, the new value in the given dictionary will overwrite the existing value; see `-[NSMutableDictionary addEntriesFromDictionary:]` for details.
- (NSError *)errorByAddingUserInfo:(NSDictionary *)userInfo;

@end

NS_ASSUME_NONNULL_END
