// Copyright 2008-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSNumber-OFExtensions-CGTypes.h>
#import <CoreFoundation/CoreFoundation.h>
#import <OmniBase/rcsid.h>

RCS_ID("$Id$")

NS_ASSUME_NONNULL_BEGIN

@implementation NSNumber (OFCGTypeExtensions)

+ (NSNumber *)numberWithCGFloat:(CGFloat)value
{
    return CFBridgingRelease(CFNumberCreate(kCFAllocatorDefault, kCFNumberCGFloatType, &value));
}

// Convenience initializers warn incorrectly with -Wobjc-designated-initializers when returning a new object <http://llvm.org/bugs/show_bug.cgi?id=20390>
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-designated-initializers"
- (id)initWithCGFloat:(CGFloat)value;
{
    [self release];
    return (OB_BRIDGE NSNumber *)CFNumberCreate(kCFAllocatorDefault, kCFNumberCGFloatType, &value);
}
#pragma clang diagnostic pop

- (CGFloat)cgFloatValue
{
    // If we're a real CFNumber, try to extract a CGFloat directly
    if (CFGetTypeID((CFTypeRef)self) == CFNumberGetTypeID()) {
        CGFloat v;
        if (CFNumberGetValue((CFTypeRef)self, kCFNumberCGFloatType, &v))
            return v;
    }
    
    // Rely on compile-time optimization of the call, and implicit conversion of the retrieved float type to our return type
    if (sizeof(CGFloat) > sizeof(float)) {
        return (CGFloat)[self doubleValue];
    } else {
        return (CGFloat)[self floatValue];
    }
}

@end

@implementation NSString (OFCGTypeExtensions)

- (CGFloat)cgFloatValue
{
    // Rely on compile-time optimization of the call, and implicit conversion of the retrieved float type to our return type
    if (sizeof(CGFloat) > sizeof(float)) {
        return (CGFloat)[self doubleValue];
    } else {
        return (CGFloat)[self floatValue];
    }
}

@end

NS_ASSUME_NONNULL_END
