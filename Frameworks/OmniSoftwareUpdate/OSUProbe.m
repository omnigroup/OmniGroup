// Copyright 2014-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniSoftwareUpdate/OSUProbe.h>

#import <OmniFoundation/NSString-OFSimpleMatching.h>
#import <OmniFoundation/OFPreference.h>

RCS_ID("$Id$");

OFDeclareDebugLogLevel(OSUProbeDebug)

#define DEBUG_PROBE(level, format, ...) do { \
    if (OSUProbeDebug >= (level)) \
        NSLog(@"PROBE %@: " format, [self shortDescription], ## __VA_ARGS__); \
} while (0)

NSString * const OSUProbeFinalizeForQueryNotification = @"OSUProbeFinalizeForQuery";

@interface OSUProbe ()
@property (nonatomic, readwrite) id value;
@end

@implementation OSUProbe

static dispatch_queue_t ProbeQueue;
static NSMutableDictionary *ProbeByKey;

+ (void)initialize;
{
    OBINITIALIZE;
    
    ProbeQueue = dispatch_queue_create("com.omnigroup.OmniSoftwareUpdate", DISPATCH_QUEUE_SERIAL);
    ProbeByKey = [[NSMutableDictionary alloc] init];
}

+ (NSArray *)allProbes;
{
    __block NSArray *probes;
    
    dispatch_sync(ProbeQueue, ^{
        probes = [[ProbeByKey allValues] copy];
    });
    
    return probes;
}

+ (OSUProbe *)existingProbeWithKey:(NSString *)key;
{
    __block OSUProbe *probe = nil;
    
    dispatch_sync(ProbeQueue, ^{
        probe = ProbeByKey[key];
    });
    
    return probe;
}

+ (instancetype)probeWithKey:(NSString *)key title:(NSString *)title;
{
    return [self probeWithKey:key options:0 title:title];
}

+ (instancetype)probeWithKey:(NSString *)key options:(OSUProbeOption)options title:(NSString *)title;
{
    __block OSUProbe *probe;
    
    dispatch_sync(ProbeQueue, ^{
        OSUProbe *existingProbe = ProbeByKey[key];
        if (existingProbe) {
            OBASSERT(existingProbe.options == options);
            OBASSERT([existingProbe.title isEqual:title]);
            probe = existingProbe;
            return;
        }

        probe = [[self alloc] _initWithKey:key options:options title:title];
        ProbeByKey[key] = probe;
    });
    
    return probe;
}

+ (NSString *)displayStringForValue:(id)value options:(OSUProbeOption)options;
{
    if ([value isKindOfClass:[NSString class]]) {
        return value;
    }
    
    if (options & OSUProbeOptionIsFileSize) {
        return [NSByteCountFormatter stringFromByteCount:[value longLongValue] countStyle:NSByteCountFormatterCountStyleFile];
    }
    
    // Don't expect this method to be called too often, so not caching this formatter
    NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
    formatter.formattingContext = NSFormattingContextStandalone;
    formatter.numberStyle = NSNumberFormatterDecimalStyle;
    
    return [formatter stringFromNumber:value];
}

- init;
{
    OBRejectUnusedImplementation(self, _cmd);
}

// Our getters are read-only and immutable *except* for the current value.

- (id)value;
{
    __block id value;
    
    dispatch_sync(ProbeQueue, ^{
        value = self->_value;
    });
    
    return value;
}

- (NSString *)displayString;
{
    return [OSUProbe displayStringForValue:self.value options:self.options];
}

- (void)reset;
{
    dispatch_async(ProbeQueue, ^{
        [self _setValue:@(0) action:@"Reset"];
    });
}

- (void)increment;
{
    dispatch_async(ProbeQueue, ^{
        NSInteger value = [self->_value integerValue] + 1;
        [self _setValue:[NSNumber numberWithInteger:value] action:@"Increment"];
    });
}

- (void)setIntegerValue:(NSInteger)value;
{
    [self setNumberValue:[NSNumber numberWithInteger:value]];
}

- (void)setNumberValue:(NSNumber *)value;
{
    dispatch_async(ProbeQueue, ^{
        [self _setValue:value action:@"Set"];
    });
}

- (void)setStringValue:(NSString *)value;
{
    OBPRECONDITION(value != nil);
    dispatch_async(ProbeQueue, ^{
        [self _setValue:value action:@"Set"];
    });
}

#pragma mark - Debugging

- (NSString  *)shortDescription;
{
    return [NSString stringWithFormat:@"<%@:%p %@>", NSStringFromClass([self class]), self, _key];
}

#pragma mark - Private

static NSString *_defaultsKey(NSString *key)
{
    // Our keys are short for the HTTP query; give them something a bit more reasonable/understandable for a defaults key.
    return [NSString stringWithFormat:@"OSUProbe.%@", key];
}

- _initWithKey:(NSString *)key options:(OSUProbeOption)options title:(NSString *)title;
{
    OBPRECONDITION(![NSString isEmptyString:key]);
    OBPRECONDITION(![NSString isEmptyString:title]);
    
    if (!(self = [super init]))
        return nil;
    
    _key = [key copy];
    _options = options;
    _title = [title copy];
    
    // Since these are per-app, not (necessarily) global across apps, we don't store them in the shared group container.
    NSInteger value = [[NSUserDefaults standardUserDefaults] integerForKey:_defaultsKey(_key)];
    _value = [[NSNumber alloc] initWithInteger:value];
    
    return self;
}

// Must be called on the probe queue.
- (void)_setValue:(id)value action:(NSString *)action;
{
    OBPRECONDITION(value != nil);

    if ([_value isEqual:value])
        return;
    
    DEBUG_PROBE(1, "%@ to %@", action, value);

    _value = value;

    NSString *key = _defaultsKey(_key);
    // We cannot poke NSUserDefaults here. It posts a notification which could have an observer on the main thread (NSNC seems to do some operation queuing/waiting) where the main thread is blocked looking up a probe. Deadlock.
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSUserDefaults standardUserDefaults] setObject:value forKey:key];
    });
}

@end
