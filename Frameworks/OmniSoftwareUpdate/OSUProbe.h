// Copyright 2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>

typedef NS_OPTIONS(NSUInteger, OSUProbeOption) {
    OSUProbeOptionResetOnSubmit = (1<<0), // If set, this probe will be reset to zero the next time a software update query is successfully sent.
    
    OSUProbeOptionIsFileSize = (1<<1), // When formatted for a display string, NSByteCountFormatter will be used.
};

@interface OSUProbe : NSObject

+ (NSArray *)allProbes;
+ (instancetype)probeWithKey:(NSString *)key title:(NSString *)title;
+ (instancetype)probeWithKey:(NSString *)key options:(OSUProbeOption)options title:(NSString *)title;

@property(nonatomic,readonly) NSString *key;
@property(nonatomic,readonly) OSUProbeOption options;
@property(nonatomic,readonly) id value;
@property(nonatomic,readonly) NSString *title; // For the application preferences/settings display so that users know what information we are sending.

@property(nonatomic,readonly) NSString *displayString; // Formatted string for the value, based on the options mask.

// Mutations are serialized with the -value getter for use on any queue.
- (void)reset;
- (void)increment;
- (void)setIntegerValue:(NSInteger)value;

@end
