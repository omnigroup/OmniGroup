// Copyright 2013-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.


#import <OmniFoundation/OFNumberFormatter.h>

RCS_ID("$Id$");


@interface OFNumberFormatter ()
@property (nonatomic,retain) NSNumber *clampingMaximum;
@property (nonatomic,retain) NSNumber *clampingMinimum;
@end


#ifdef DEBUG
#define OFNFDEBUG(...) do{ if(self.debugLevel>0) NSLog(__VA_ARGS__); }while(0)
#else
#define OFNFDEBUG(...) do{  }while(0)
#endif


@implementation OFNumberFormatter

- (void)dealloc;
{
    [_clampingMaximum release];
    [_clampingMinimum release];
    [super dealloc];
}

#pragma mark - Properties and API

- (void)setClampsRange:(BOOL)clamps;
{
    if (clamps == _clampsRange) {
        return;
    }
    
    _clampsRange = clamps;
    
    if (_clampsRange) {
        self.clampingMinimum = self.minimum;
        self.minimum = nil;
        self.clampingMaximum = self.maximum;
        self.maximum = nil;
    } else {
        self.minimum = self.clampingMinimum;
        self.clampingMinimum = nil;
        self.maximum = self.clampingMaximum;
        self.clampingMaximum = nil;
    }
}

#pragma mark - NSFormatter subclass

#ifdef DEBUG_0
- (NSString *)stringForObjectValue:(id)objectValue;
{
    NSString *stringValue = [super stringForObjectValue:objectValue];
    OFNFDEBUG(@"| %p %s - string \"%@\" for object value %@", self, __PRETTY_FUNCTION__, stringValue, objectValue);
    return stringValue;
}
#endif // DEBUG

#pragma mark - NSNumberFormatter subclass

- (BOOL)getObjectValue:(out id *)outObjectValue forString:(NSString *)string range:(inout NSRange *)rangePtr error:(out NSError **)outError;
{
    if (![super getObjectValue:outObjectValue forString:string range:rangePtr error:outError]) {
        OFNFDEBUG(@"| %p %s - failed to create object value for string: \"%@\"", self, __PRETTY_FUNCTION__, string);
        return NO;
    }
    
    OFNFDEBUG(@"> %p %s - object value %@ (%@) for string \"%@\"", self, __PRETTY_FUNCTION__, *outObjectValue, [*outObjectValue class], string);
    if (*outObjectValue != NULL) {
        if (self.clampsRange) {
            NSNumber *min = self.clampingMinimum;
            if ((min != nil) && ([min compare:*outObjectValue] == NSOrderedDescending)) {
                OFNFDEBUG(@"  %p %s - clamping to minimum of %@", self, __PRETTY_FUNCTION__, min);
                *outObjectValue = min;
            }
            NSNumber *max = self.clampingMaximum;
            if ((max != nil) && ([max compare:*outObjectValue] == NSOrderedAscending)) {
                OFNFDEBUG(@"  %p %s - clamping to maximum of %@", self, __PRETTY_FUNCTION__, max);
                *outObjectValue = max;
            }
        }
        
        // If we're clamping precision, have the superclass format a string for this object value, then get the object value for that string, so that the returned object value will match the precision of the formatted string value.
        if (self.clampsPrecision) {
            NSString *formattedString = [self stringForObjectValue:*outObjectValue];
            OFNFDEBUG(@"  %p %s - clamping precision by reinterpreting based on string value of \"%@\"", self, __PRETTY_FUNCTION__, formattedString);
            id reinterpretedObject = nil;
            NSRange formattedStringRange = NSMakeRange(0, [formattedString length]);
            if ([super getObjectValue:&reinterpretedObject forString:formattedString range:&formattedStringRange error:outError]) {
                *outObjectValue = reinterpretedObject;
            }
        }
    }
    OFNFDEBUG(@"< %p %s - final object value: %@ (%@)", self, __PRETTY_FUNCTION__, *outObjectValue, [*outObjectValue class]);
    
    return YES;
}

- (void)setMinimum:(NSNumber *)minimum;
{
    if (self.clampsRange) {
        self.clampingMinimum = minimum;
    } else {
        super.minimum = minimum;
    }
}

- (void)setMaximum:(NSNumber *)maximum;
{
    if (self.clampsRange) {
        self.clampingMaximum = maximum;
    } else {
        super.maximum = maximum;
    }
}

@end
