// Copyright 2006-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFRelativeDateFormatter.h>

#import <OmniFoundation/OFRelativeDateParser.h>
#import <OmniFoundation/OFPreference.h>

RCS_ID("$Id$");

@implementation OFRelativeDateFormatter

- (void)dealloc;
{
    [_defaultTimeDateComponents release];
    [super dealloc];
}

#pragma mark API

@synthesize defaultTimeDateComponents = _defaultTimeDateComponents;
@synthesize useEndOfDuration = _useEndOfDuration;

#pragma mark NSFomatter subclass

- (NSString *)editingStringForObjectValue:(id)obj;
{
    return [super stringForObjectValue:obj];
}

- (BOOL)getObjectValue:(id *)obj forString:(NSString *)string errorDescription:(NSString **)error;
{
    NSError *relativeError = nil;
    NSDate *date = nil;
    
    BOOL success = [[OFRelativeDateParser sharedParser] getDateValue:&date forString:string useEndOfDuration:_useEndOfDuration defaultTimeDateComponents:_defaultTimeDateComponents error:&relativeError];

    if (success)
        *obj = date;
    
    return success;
 }

- (BOOL)isPartialStringValid:(NSString **)partialStringPtr proposedSelectedRange:(NSRangePointer)proposedSelRangePtr originalString:(NSString *)origString originalSelectedRange:(NSRange)origSelRange errorDescription:(NSString **)error;
{
    NSError *relativeError = nil;
    NSDate *date = nil;
    return [[OFRelativeDateParser sharedParser] getDateValue:&date forString:*partialStringPtr useEndOfDuration:_useEndOfDuration defaultTimeDateComponents:_defaultTimeDateComponents error:&relativeError];
}

- (BOOL)getObjectValue:(id *)obj forString:(NSString *)string range:(inout NSRange *)rangep error:(NSError **)error;
{
    NSDate *date = nil;
    BOOL success = [[OFRelativeDateParser sharedParser] getDateValue:&date forString:string useEndOfDuration:_useEndOfDuration defaultTimeDateComponents:_defaultTimeDateComponents error:error];

    if (success)
        *obj = date;

    return success;
}

- (NSString *)stringFromDate:(NSDate *)date;
{
    OBRejectUnusedImplementation(self, _cmd);
    return nil;
}

- (NSDate *)dateFromString:(NSString *)string;
{
    OBRejectUnusedImplementation(self, _cmd);
    return nil;
}

#pragma mark NSCopying

- (id)copyWithZone:(NSZone *)zone;
{
    OFRelativeDateFormatter *copy = [super copyWithZone:zone];
    copy->_defaultTimeDateComponents = [_defaultTimeDateComponents copy];
    return copy;
}

@end
