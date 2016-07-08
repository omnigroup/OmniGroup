// Copyright 2016 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSCache-OFExtensions.h>

RCS_ID("$Id$");

#ifdef DEBUG

extern void cache_print(void *cache);

typedef void (*cache_callback)(id value, id key, void *ctx);
extern void cache_invoke(void *cache, void *cache_callback, void *ctx);

static void omni_cache_invoke_block(id key, id value, void *ctx)
{
    void (^callback)(id key, id value) = (void (^)(id key, id value))ctx;
    callback(key, value);
}

#endif // DEBUG

#pragma mark -

@implementation NSCache(OFExtensions)

#ifdef DEBUG

- (void *)omni_cache_t;
{
    Ivar ivar = class_getInstanceVariable([self class], "_private");
    ptrdiff_t offset = ivar_getOffset(ivar);
    void *base = (void *)self;
    void **private = (void **)(base + offset);
    void *cache = private[1];
    return cache;
}

- (void)omni_debug_printCache;
{
    cache_print([self omni_cache_t]);
}

- (NSDictionary *)omni_debug_asDictionary;
{
    NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
    void (^callback)(id key, id value) = ^(id key, id value) {
        dictionary[key] = value;
    };
    
    cache_invoke([self omni_cache_t], omni_cache_invoke_block, callback);
    return dictionary;
}

- (NSString *)debugDescription;
{
    NSMutableString *description = [NSMutableString string];
    NSDictionary *dictionaryRepresentation = [self omni_debug_asDictionary];
    NSArray *keys = [[dictionaryRepresentation allKeys] sortedArrayUsingSelector:@selector(compare:)];
    
    [description appendFormat:@"%@ = {\n", [super description]];
    for (NSString *key in keys) {
        if ([key isKindOfClass:[NSString class]]) {
            [description appendFormat:@"    \"%@\" = %@\n", key, dictionaryRepresentation[key]];
        } else {
            [description appendFormat:@"    %@ = %@\n", key, dictionaryRepresentation[key]];
        }
    }
    [description appendString:@"}\n"];

    return description;
}

#endif // DEBUG

@end

