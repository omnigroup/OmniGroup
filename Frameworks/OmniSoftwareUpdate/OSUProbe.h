// Copyright 2014-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>

NS_ASSUME_NONNULL_BEGIN

/// Sent immediately before probe values are computed or transmitted for an OSU/OSI query. Subscribers should use this notification as an opportunity to update probe values for any lazy or cached probes that are not kept up to date otherwise. The object of this notification is of an unspecified type, but will represent the query for which probes need updating.
extern NSString * const OSUProbeFinalizeForQueryNotification;

typedef NS_OPTIONS(NSUInteger, OSUProbeOption) {
    OSUProbeOptionResetOnSubmit = (1<<0), // If set, this probe will be reset to zero the next time a software update query is successfully sent.
    
    OSUProbeOptionIsFileSize = (1<<1), // When formatted for a display string, NSByteCountFormatter will be used.
    OSUProbeOptionHasAppSpecificDisplay = (1<<2), // Probe is not automatically formatted for display; the app is responsible for formatting it
};

@interface OSUProbe : NSObject

/// Returns all registered OSUProbe instances
+ (NSArray<OSUProbe *> *)allProbes;

/// Returns an existing OSUProbe instance registered for the given key. If no probe has ever been created for that key, returns nil.
+ (nullable OSUProbe *)existingProbeWithKey:(NSString *)key;

/// Returns a new OSUProbe with the given key and localized title. The created probe uses a default options mask. Do not use this method to fetch an existing key, even if you are able to match the localized title; instead, use <code>+existingProbeWithKey:</code>.
+ (instancetype)probeWithKey:(NSString *)key title:(NSString *)title;

/// Returns a new OSUProbe with the given key and localized title. Do not use this method to fetch an existing key, even if you are able to match the localized title and options; instead, use <code>+existingProbeWithKey:</code>.
+ (instancetype)probeWithKey:(NSString *)key options:(OSUProbeOption)options title:(NSString *)title;

/// Formats the given probe value for display, respecting the given options.
+ (NSString *)displayStringForValue:(id)value options:(OSUProbeOption)options;

@property(nonatomic,readonly) NSString *key;
@property(nonatomic,readonly) OSUProbeOption options;
@property(nonatomic,readonly,nullable) id value;
@property(nonatomic,readonly) NSString *title; // For the application preferences/settings display so that users know what information we are sending.

// Returns a formatted string for the receiver's value, based on the options mask. See also <code>+displayStringForValue:options:</code>.
@property(nonatomic,readonly) NSString *displayString;

// Mutations are serialized with the -value getter for use on any queue.
- (void)reset;
- (void)increment;
- (void)setIntegerValue:(NSInteger)value;
- (void)setNumberValue:(NSNumber *)value;
- (void)setStringValue:(NSString *)value;

@end

NS_ASSUME_NONNULL_END
