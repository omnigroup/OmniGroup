// Copyright 2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniDataObjects/ODOFloatingDate.h>

@import Foundation.NSTimeZone;
@import OmniFoundation.NSDate_OFExtensions;

@interface ODOFloatingDate () <NSCopying, NSCoding>
@property (nonatomic, readonly) NSDate *_absoluteDate;
@end

@implementation ODOFloatingDate
{
    NSString *_floatingXMLString;
    NSDate *_cachedAbsoluteDate;
    NSUInteger _cachedAbsoluteDateTimeZoneGeneration;
}

static NSUInteger _timeZoneGeneration;
static NSTimeZone *_lastTimeZone;

static void _checkForTimeZoneChange(void)
{
    NSTimeZone *systemTimeZone = NSTimeZone.systemTimeZone;
    if (_lastTimeZone == systemTimeZone)
        return;
    _timeZoneGeneration++;
    _lastTimeZone = systemTimeZone;
}

- (instancetype)initWithFloatingXMLString:(NSString *)floatingXMLString;
{
    self = [super init];
    if (self == nil)
        return nil;

    _floatingXMLString = floatingXMLString;

    return self;
}

- (instancetype)initWithDate:(NSDate *)date;
{
    return [self initWithFloatingXMLString:date.floatingTimeZoneXMLString];
}

- (NSDate *)_absoluteDate;
{
    _checkForTimeZoneChange(); // We can get asked for our current time interval before we receive our time zone change notification (because someone else is responding to it first)

    NSDate *date = _cachedAbsoluteDate;
    if (date == nil || _cachedAbsoluteDateTimeZoneGeneration != _timeZoneGeneration) {
        date = [[NSDate alloc] initWithXMLString:_floatingXMLString allowFloating:YES outIsFloating:NULL];
        _cachedAbsoluteDate = date;
        _cachedAbsoluteDateTimeZoneGeneration = _timeZoneGeneration;
    }
    return date;
}

#pragma mark - NSDate subclass

- (NSDate *)initWithXMLString:(NSString *)xmlString; // Can return a non-floating date
{
    BOOL isFloating = NO;
    NSDate *date = [[NSDate alloc] initWithXMLString:xmlString allowFloating:YES outIsFloating:&isFloating];
    if (isFloating)
        return [self initWithFloatingXMLString:xmlString];
    else
        return (id)date;
}

- (NSTimeInterval)timeIntervalSinceReferenceDate;
{
    return self._absoluteDate.timeIntervalSinceReferenceDate;
}

- (instancetype)init;
{
    return [self initWithDate:[NSDate date]];
}

- (instancetype)initWithTimeIntervalSinceReferenceDate:(NSTimeInterval)ti;
{
    NSDate *date = [[NSDate alloc] initWithTimeIntervalSinceReferenceDate:ti];
    return [self initWithDate:date];
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder;
{
    OBASSERT_NOT_REACHED("Our implementation of -replacementObjectForCoder: should prevent our class from ever being encoded.");

    NSString *floatingXMLString = [coder decodeObjectOfClass:[NSString class] forKey:@"floatingXMLString"];
    if (floatingXMLString == nil)
        return nil;
    return [self initWithFloatingXMLString:floatingXMLString];
}

- (void)encodeWithCoder:(NSCoder *)coder;
{
    OBASSERT_NOT_REACHED("Our implementation of -replacementObjectForCoder: should prevent our class from ever being encoded.");

    [coder encodeObject:_floatingXMLString forKey:@"floatingXMLString"];
}

- (nullable id)replacementObjectForCoder:(NSCoder *)coder;
{
    // Within OmniFocus itself, we archive floating dates using our XML string. But if we pass this date to some system service that tries to archive it, they'll probably be happiest if we hand them a simple NSDate instead. (Especially important if this is a date that they want to send to another process, where our class doesn't exist.)
    return self._absoluteDate;
}

#pragma mark - NSDate(OFExtensions)

- (NSString *)xmlString;
{
    return _floatingXMLString;
}

- (NSString *)floatingTimeZoneXMLString;
{
    return _floatingXMLString;
}

#pragma mark - NSDate(XMLDataExtensions)

- (BOOL)isFloating;
{
    return YES;
}

- (NSDate *)floatingDate;
{
    return self;
}

- (NSDate *)fixedDate;
{
    return self._absoluteDate;
}

#pragma mark - NSSecureCoding

- (BOOL)supportsSecureCoding;
{
    return YES;
}

@end

@implementation NSDate (XMLDataExtensions)

- (BOOL)isFloating;
{
    return NO;
}

- (NSDate *)floatingDate;
{
    return [[ODOFloatingDate alloc] initWithDate:self];
}

- (NSDate *)fixedDate;
{
    return self;
}

@end
