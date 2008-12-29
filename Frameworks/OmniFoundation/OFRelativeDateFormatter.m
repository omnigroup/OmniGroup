// Copyright 2006-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFRelativeDateFormatter.h>

#import <OmniFoundation/OFRelativeDateParser.h>
#import <OmniFoundation/OFPreference.h>

RCS_ID("$Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/trunk/OmniGroup/Templates/Developer%20Tools/File%20Templates/%20Omni/OmniFoundation%20public%20class.pbfiletemplate/class.m 70671 2005-11-22 01:01:39Z kc $");

@implementation OFRelativeDateFormatter

- (void)dealloc;
{
    [_defaultTimeDateComponents release];
    [super dealloc];
}

#pragma mark API

- (void)setDefaultTimeDateComponents:(NSDateComponents *)dateComponents;
{
    if (_defaultTimeDateComponents == dateComponents)
        return;
    [_defaultTimeDateComponents release];
    _defaultTimeDateComponents = [dateComponents copy];
}

- (NSDateComponents *)defaultTimeDateComponents;
{
    return _defaultTimeDateComponents;
}

- (void)setUseEndOfDuration:(BOOL)useEndOfDuration;
{
    _useEndOfDuration = useEndOfDuration;
}

- (BOOL)useEndOfDuration;
{
    return _useEndOfDuration;
}

#pragma mark NSFomatter subclass

#if 0
- (NSString *)stringForObjectValue:(id)obj;
{
    NSString *result = [super stringForObjectValue:obj];
    //NSLog(@"%s: obj:%@ result:%@", __PRETTY_FUNCTION__, obj, result);
    return result;
}
#endif

#if 0
- (NSAttributedString *)attributedStringForObjectValue:(id)obj withDefaultAttributes:(NSDictionary *)attrs;
{
    NSAttributedString *result = [super attributedStringForObjectValue:obj withDefaultAttributes:attrs];
    //NSLog(@"%s: obj:%@ result:%@", __PRETTY_FUNCTION__, obj, result);
    return result;
}
#endif

- (NSString *)editingStringForObjectValue:(id)obj;
{
    return [super stringForObjectValue:obj];
}

- (BOOL)getObjectValue:(id *)obj forString:(NSString *)string errorDescription:(NSString **)error;
{
    //NSLog(@"%s: string:%@", __PRETTY_FUNCTION__, string);
    NSError *relativeError = nil;
    NSDate *date = nil;
    
    BOOL success = [[OFRelativeDateParser sharedParser] getDateValue:&date forString:string useEndOfDuration:_useEndOfDuration defaultTimeDateComponents:_defaultTimeDateComponents error:&relativeError];

    //NSLog(@"%s: date:%@ %@", __PRETTY_FUNCTION__, [date class], date);
    *obj = date;

    if (success) {
//        *obj = date;
        //NSLog(@"date = %@", date);
        return YES;
    }

    //*error = [relativeError localizedDescription];
    return NO;
 }

- (BOOL)isPartialStringValid:(NSString **)partialStringPtr proposedSelectedRange:(NSRangePointer)proposedSelRangePtr originalString:(NSString *)origString originalSelectedRange:(NSRange)origSelRange errorDescription:(NSString **)error;
{
    //NSLog(@"%s: string:%@", __PRETTY_FUNCTION__, *partialStringPtr);
    NSError *relativeError = nil;
    NSDate *date = nil;
    BOOL success = [[OFRelativeDateParser sharedParser] getDateValue:&date forString:*partialStringPtr useEndOfDuration:_useEndOfDuration defaultTimeDateComponents:_defaultTimeDateComponents error:&relativeError];

    if (success) {
        //NSLog(@"date = %@", date);
        return YES;
    }
    return NO;
}

- (BOOL)getObjectValue:(id *)obj forString:(NSString *)string range:(inout NSRange *)rangep error:(NSError **)error;
{
    //NSLog(@"%s: string:%@", __PRETTY_FUNCTION__, string);
    NSDate *date = nil;
    BOOL success = [[OFRelativeDateParser sharedParser] getDateValue:&date forString:string useEndOfDuration:_useEndOfDuration defaultTimeDateComponents:_defaultTimeDateComponents error:error];

    //NSLog(@"%s: date:%@ %@", __PRETTY_FUNCTION__, [date class], date);
    *obj = date;

    if (success) {
        //*obj = date;
        return YES;
    }
    return NO;
}

- (NSString *)stringFromDate:(NSDate *)date;
{
    OBASSERT_NOT_REACHED("x");
    return nil;
}

- (NSDate *)dateFromString:(NSString *)string;
{
    OBASSERT_NOT_REACHED("x");
    return nil;
}

@end
