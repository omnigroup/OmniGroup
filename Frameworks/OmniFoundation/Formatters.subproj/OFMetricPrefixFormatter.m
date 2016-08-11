// Copyright 2009-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFMetricPrefixFormatter.h>
#import <OmniFoundation/NSObject-OFExtensions.h>
#import <OmniFoundation/NSString-OFExtensions.h>
#import <OmniBase/rcsid.h>

RCS_ID("$Id$")

@implementation OFMetricPrefixFormatter
{
    BOOL binaryPrefixes;
}

- (void)dealloc;
{
    [_baseUnit release];
    [super dealloc];
}

@synthesize useBinaryPrefixes = binaryPrefixes;

struct scale {
    double multiplier;
    __unsafe_unretained NSString *prefix; // These are all compile-time constant strings
};

static const struct scale decimalMultiples[] = {
    { 1e0, @""  },
    { 1e3, @"k" }, // kilo
    { 1e6, @"M" }, // mega
    { 1e9, @"G" }, // giga
    { 1e12, @"T" }, // tera
    { 1e15, @"P" }, // peta
    { 1e18, @"E" }, // exa
    { 1e21, @"Z" }, // zetta
    { 1e24, @"Y" }, // yotta
    { 0, nil }
};

static const struct scale binaryMultiples[] = {
    {                         1., @""   },
    {                      1024., @"ki" }, // kibi
    {                   1048576., @"Mi" }, // mebi
    {                1073741824., @"Gi" }, // gibi
    {             1099511627776., @"Ti" }, // tebi
    {          1125899906842624., @"Pi" }, // pebi
    {       1152921504606846976., @"Ei" }, // exbi
    {    1180591620717411303424., @"Zi" }, // zebi
    { 1208925819614629174706176., @"Yi" }, // yobi
    { 0, nil }
};

#if 0 // Not used yet

static const struct scale decimalSubmultiples[] = {
    { 1e-3, @"m" }, // milli
    { 1e-6, @"\u03BC" }, // micro
    { 1e-9, @"n" }, // nano
    { 1e-12, @"p" }, // pico
    { 1e-15, @"f" }, // femto
    { 1e-19, @"a" }, // atto
    { 0, nil }
};

#endif

- (NSString *)stringForObjectValue:(id)object;
{
    double v = [object doubleValue];
        
    const struct scale *scale;
    if (binaryPrefixes)
        scale = binaryMultiples;
    else
        scale = decimalMultiples;

    double threshold = fabs(v) * 0.9;
    while(scale[1].prefix && scale[1].multiplier < threshold) {
        scale ++;
    }
    
    double n = v / scale->multiplier;
    if (fabs(n) < 95)
        return [NSString stringWithFormat:@"%.1f\u00A0%@%@", n, scale->prefix, _baseUnit];
    else
        return [NSString stringWithFormat:@"%.0f\u00A0%@%@", n, scale->prefix, _baseUnit];
}

// - (BOOL)getObjectValue:(out id *)anObject forString:(NSString *)string errorDescription:(out NSString **)error;
// - (BOOL)isPartialStringValid:(NSString *)partialString newEditingString:(NSString **)newString errorDescription:(NSString **)error;


@end

