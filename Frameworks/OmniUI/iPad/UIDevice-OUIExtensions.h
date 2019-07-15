// Copyright 2014-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <UIKit/UIDevice.h>

@class UIDeviceHardwareInfo;

@interface UIDevice (OUIExtensions)

/// Returns YES if the current device supports multitasking, and it has not been disabled in the Info.plist via UIApplicationExitsOnSuspend
@property (nonatomic, readonly, getter=isMultitaskingEnabled) BOOL multitaskingEnabled;

/// The unparsed result of sysctl("hw.machine") e.g. iPhone5,1 iPad4,1 x86_64
@property (nonatomic, readonly) NSString *platform;

/// The result of sysctl("hw.model"); this is unlikely to be useful other than as a curiosity
@property (nonatomic, readonly) NSString *hardwareModel;

/// A UIDeviceHardwareInfo object which represents the parsed result from inspecting `platform`.
@property (nonatomic, readonly) UIDeviceHardwareInfo *hardwareInfo;

- (NSUInteger)pixelsPerInch;

@end


#pragma mark -


typedef NS_ENUM(NSInteger, UIDeviceHardwareFamily) {
    UIDeviceHardwareFamily_Unknown,
    UIDeviceHardwareFamily_iPhoneSimulator,
    UIDeviceHardwareFamily_iPhone,
    UIDeviceHardwareFamily_iPodTouch,
    UIDeviceHardwareFamily_iPad,
};

@interface UIDeviceHardwareInfo : NSObject

@property (nonatomic, readonly) UIDeviceHardwareFamily family;
@property (nonatomic, readonly) NSUInteger majorHardwareIdentifier;
@property (nonatomic, readonly) NSUInteger minorHardwareIdentifier;

@end
