// Copyright 2014-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/UIDevice-OUIExtensions.h>

#import <sys/sysctl.h>
#import <OmniFoundation/NSString-OFConversion.h>

RCS_ID("$Id$");


@interface UIDeviceHardwareInfo () {
@private
    NSString *_platform;
    UIDeviceHardwareFamily _family;
    NSUInteger _majorHardwareIdentifier;
    NSUInteger _minorHardwareIdentifier;
}

- (id)initWithPlatformString:(NSString *)platformString;

@end

#pragma mark -

@implementation UIDevice (OUIExtensions)

- (BOOL)isMultitaskingEnabled;
{
    static BOOL multitaskingEnabled;
    static dispatch_once_t token;
    
    dispatch_once(&token, ^{
        multitaskingEnabled = [self isMultitaskingSupported];
        if (multitaskingEnabled) {
            NSDictionary *infoDictionary = [[NSBundle mainBundle] infoDictionary];
            if ([[infoDictionary objectForKey:@"UIApplicationExitsOnSuspend"] boolValue]) {
                multitaskingEnabled = NO;
            }
        }
    });
    
    return multitaskingEnabled;
}

- (NSString *)platform;
{
    static NSString *platform = nil;
    static dispatch_once_t token;
    
    dispatch_once(&token, ^{
        platform = [[self sysctlbyname:"hw.machine"] copy];
    });
    
    return platform;
}

- (NSString *)hardwareModel;
{
    static NSString *platform = nil;
    static dispatch_once_t token;
    
    dispatch_once(&token, ^{
        platform = [[self sysctlbyname:"hw.model"] copy];
    });
    
    return platform;
}

- (UIDeviceHardwareInfo *)hardwareInfo;
{
    static UIDeviceHardwareInfo *hardwareInfo = nil;
    static dispatch_once_t token;
    
    dispatch_once(&token, ^{
        hardwareInfo = [[UIDeviceHardwareInfo alloc] initWithPlatformString:self.platform];
    });
    
    return hardwareInfo;
}

- (NSUInteger)pixelsPerInch;
{
    NSUInteger ppi = 0;
    UIDeviceHardwareInfo *hardwareInfo = [[UIDevice currentDevice] hardwareInfo];
    switch (hardwareInfo.family) {
        case UIDeviceHardwareFamily_iPhoneSimulator: {
            // TODO: making a guess based on screen size
            OBASSERT_NOT_REACHED("WYSIWYG does not work in simulator. bug:///137376");

            ppi = 326;
            break;
        }
        case UIDeviceHardwareFamily_iPhone: {
            switch (hardwareInfo.majorHardwareIdentifier) {
                case 1: // iPhone 3G
                case 2: // iPhone 3GS
                {
                    ppi = 163;
                    break;
                }
                case 3: // iPhone 4
                case 4: // iPhone 4s
                {
                    ppi = 326;
                    break;
                }
                case 5: // iPhone 5
                case 6: // iPhone 5s
                {
                    ppi = 326;
                    break;
                }
                case 7:
                {
                    if (hardwareInfo.minorHardwareIdentifier == 1) {    // iPhone 6+
                        ppi = 401;
                    } else {    // iPhone 6
                        ppi = 326;
                    }
                    
                    break;
                }
                case 8:
                {
                    if (hardwareInfo.minorHardwareIdentifier == 2) {    // iPhone 6s+
                        ppi = 401;
                    } else {    // iPhone 6s
                        ppi = 326;
                    }
                    
                    break;
                }
                default:
                {
                    OBASSERT_NOT_REACHED("Unknown iPhone hardware model");
                }
            }
            break;
        }
            
        case UIDeviceHardwareFamily_iPodTouch: {
            switch (hardwareInfo.majorHardwareIdentifier) {
                case 1: // iPod 1G
                case 2: // iPod 2G
                case 3: // iPod 3G
                {
                    ppi = 163;
                    break;
                }
                case 4: // iPod 4G
                case 5: // iPod 5G
                {
                    ppi = 326;
                    break;
                }
                default:
                {
                    OBASSERT_NOT_REACHED("Unknown iPod hardware model");
                }
            }
            break;
        }
            
        case UIDeviceHardwareFamily_iPad: {
            switch (hardwareInfo.majorHardwareIdentifier) {
                case 1: // iPad 1
                case 2: // iPad 2, Mini
                {
                    ppi = 132;
                    break;
                }
                case 3: // iPad 3, iPad 4
                {
                    ppi = 264;
                    break;
                }
                case 4: // iPad Air, Mini 2, Mini 3
                {
                    if (hardwareInfo.minorHardwareIdentifier == 1 || hardwareInfo.minorHardwareIdentifier == 2 || hardwareInfo.minorHardwareIdentifier == 3) {  // iPad Air
                        ppi = 264;
                    } else {    // iPad Mini 2, Mini 3
                        ppi = 326;
                    }
                    
                    break;
                }
                case 5: // iPad Air 2
                {
                    ppi = 264;
                    break;
                }
                case 6: // iPad Pro
                {
                    ppi = 264;
                    break;
                }
                default:
                {
                    OBASSERT_NOT_REACHED("Unknown iPad hardware model");
                }
            }
            break;
        }
            
        case UIDeviceHardwareFamily_Unknown: {
            break;
        }
    }
    return ppi;
}

#pragma mark Private

- (NSString *)sysctlbyname:(char *)selector;
{
    OBPRECONDITION(selector != NULL);
    
    size_t size = 0;
    int rc = sysctlbyname(selector, NULL, &size, NULL, 0);
    if (rc == -1) {
        return nil;
    }
    
    char *value = malloc(size);
    
    @try {
        rc = sysctlbyname(selector, value, &size, NULL, 0);
        if (rc == -1) {
            return nil;
        }
        
        return [NSString stringWithUTF8String:value];
    } @finally {
        free(value);
    }
    
    OBASSERT_NOT_REACHED("unreachable");
    return nil;
}

@end

#pragma mark -

@implementation  UIDeviceHardwareInfo : NSObject

- (id)init;
{
    OBRejectUnusedImplementation(self, _cmd);
    return nil;
}

- (id)initWithPlatformString:(NSString *)platformString;
{
    OBPRECONDITION(![NSString isEmptyString:platformString]);
    
    self = [super init];
    if (self == nil) {
        return nil;
    }
    
    _platform = [platformString copy];
    _family = UIDeviceHardwareFamily_Unknown;
    _majorHardwareIdentifier = 0;
    _minorHardwareIdentifier = 0;
    
#if TARGET_IPHONE_SIMULATOR
    _family = UIDeviceHardwareFamily_iPhoneSimulator;
#else
    __autoreleasing NSError *error = nil;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"(.*?)(\\d+),(\\d+)" options:0 error:&error];
    if (regex != nil) {
        NSTextCheckingResult *match = [regex firstMatchInString:platformString options:0 range:NSMakeRange(0, platformString.length)];
        NSString *familyString = [self capturedResultAtIndex:1 inString:platformString fromTextCheckingResult:match];
        NSString *majorHardwareIdentifierString = [self capturedResultAtIndex:2 inString:platformString fromTextCheckingResult:match];
        NSString *minorHardwareIdentifierString = [self capturedResultAtIndex:3 inString:platformString fromTextCheckingResult:match];
        
        _family = [self _deviceHardwareFamilyFromString:familyString];
        _majorHardwareIdentifier = [majorHardwareIdentifierString unsignedIntValue];
        _minorHardwareIdentifier = [minorHardwareIdentifierString unsignedIntValue];
    } else {
        NSLog(@"Error creating regex in %s: %@", __func__, error);
    }
#endif
    
    return self;
}

- (NSString *)description;
{
    return [NSString stringWithFormat:@"%@ - %@", [super description], _platform];
}

- (UIDeviceHardwareFamily)family;
{
    return _family;
}

- (NSUInteger)majorHardwareIdentifier;
{
    return _majorHardwareIdentifier;
}

- (NSUInteger)minorHardwareIdentifier;
{
    return _minorHardwareIdentifier;
}

#pragma mark Private

- (NSString *)capturedResultAtIndex:(NSUInteger)captureGroup inString:(NSString *)string fromTextCheckingResult:(NSTextCheckingResult *)textCheckingResult;
{
    OBPRECONDITION(string != nil);
    OBPRECONDITION(textCheckingResult != nil);
    OBPRECONDITION(captureGroup < [textCheckingResult numberOfRanges]);
    
    NSRange range = [textCheckingResult rangeAtIndex:captureGroup];
    return [string substringWithRange:range];
}

- (UIDeviceHardwareFamily)_deviceHardwareFamilyFromString:(NSString *)string;
{
    if ([string isEqualToString:@"i386"] || [string isEqualToString:@"x86_64"]) {
        return UIDeviceHardwareFamily_iPhoneSimulator;
    }
    
    if ([string isEqualToString:@"iPhone"]) {
        return UIDeviceHardwareFamily_iPhone;
    }
    
    if ([string isEqualToString:@"iPod"]) {
        return UIDeviceHardwareFamily_iPodTouch;
    }
    
    if ([string isEqualToString:@"iPad"]) {
        return UIDeviceHardwareFamily_iPad;
    }
    
    return UIDeviceHardwareFamily_Unknown;
}

@end
