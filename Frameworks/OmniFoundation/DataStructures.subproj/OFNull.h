// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>

@interface OFNull : NSObject
+ (id)nullObject;
+ (NSString *)nullStringObject;
@end

#import <Foundation/NSObject.h>

@interface NSObject (Null)
@property(nonatomic,readonly) BOOL isNull;
@end

static inline BOOL OFNOTNULL(id ptr) {
    return (ptr != nil && ![ptr isNull]);
}

static inline BOOL OFISNULL(id ptr) {
    return (ptr == nil || [ptr isNull]);
}

static inline BOOL OFISEQUAL(id a, id b) {
    return (a == b || (OFISNULL(a) && OFISNULL(b)) || [a isEqual: b]);
}
static inline BOOL OFNOTEQUAL(id a, id b) {
    return !OFISEQUAL(a, b);
}
