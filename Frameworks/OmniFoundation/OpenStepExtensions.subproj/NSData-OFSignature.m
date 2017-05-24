// Copyright 1998-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSData-OFSignature.h>

#import <OmniFoundation/CFData-OFExtensions.h>
#import <OmniBase/macros.h>

RCS_ID("$Id$")

@implementation NSData (OFSignature)

- (NSData *)copySHA1Signature;
{
    return (OB_BRIDGE NSData *)OFDataCreateSHA1Digest(kCFAllocatorDefault, (CFDataRef)self);
}

- (NSData *)sha1Signature;
{
    return [[self copySHA1Signature] autorelease];
}

- (NSData *)sha256Signature;
{
    return CFBridgingRelease(OFDataCreateSHA256Digest(kCFAllocatorDefault, (CFDataRef)self));
}

- (NSData *)md5Signature;
{
    return CFBridgingRelease(OFDataCreateMD5Digest(kCFAllocatorDefault, (CFDataRef)self));
}

- (NSData *)signatureWithAlgorithm:(NSString *)algName;
{
    switch ([algName caseInsensitiveCompare:@"sha1"]) {
        case NSOrderedSame:
            return [self sha1Signature];
        case NSOrderedAscending:
            switch ([algName caseInsensitiveCompare:@"md5"]) {
                case NSOrderedSame:
                    return [self md5Signature];
                default:
                    break;
            }
            break;
        case NSOrderedDescending:
            switch ([algName caseInsensitiveCompare:@"sha256"]) {
                case NSOrderedSame:
                    return [self sha256Signature];
                default:
                    break;
            }
            break;
        default:
            break;
    }
    
    return nil;
}

@end

#if defined(DEBUG)

@interface OFSignatureTimingOperation ()

@property (nonatomic, assign) size_t dataSize;
@property (nonatomic, copy) NSString *algorithmName;

@property (nonatomic, assign, readwrite) NSUInteger iterations;
@property (nonatomic, assign, readwrite) NSTimeInterval averageTime;
@property (nonatomic, assign, readwrite) double standardDeviation;

@end

@implementation OFSignatureTimingOperation

- (id)initWithDataSize:(size_t)dataSize algorithm:(NSString *)algorithmName;
{
    if (!(self = [super init])) {
        return nil;
    }
    
    _dataSize = dataSize;
    _algorithmName = [algorithmName copy];
    
    _averageTime = -1;
    _standardDeviation = -1;
    
    return self;
}

- (void)dealloc;
{
    [_algorithmName release];
    
    [super dealloc];
}

static NSTimeInterval timeIntervalAverage(NSTimeInterval *intervals, NSUInteger count) {
    NSTimeInterval total = 0;
    for (NSUInteger i = 0; i < count; i++) {
        total += intervals[i];
    }
    return total / count;
}

static double timeIntervalStandardDeviation(NSTimeInterval *intervals, NSUInteger count) {
    NSTimeInterval average = timeIntervalAverage(intervals, count);
    NSTimeInterval squaredDeviationsSum = 0;
    for (NSUInteger i = 0; i < count; i++) {
        NSTimeInterval deviation = intervals[i] - average;
        squaredDeviationsSum += (deviation * deviation);
    }
    NSTimeInterval variance = squaredDeviationsSum / count;
    return sqrt(variance);
}

- (void)main;
{
    NSMutableData *data = [[NSMutableData alloc] initWithLength:self.dataSize];
    memset([data mutableBytes], 0, self.dataSize);
    
    NSUInteger iterations = 10;
    NSTimeInterval *intervals = malloc(iterations * sizeof(NSTimeInterval));
    NSTimeInterval overallStartTime = [NSDate timeIntervalSinceReferenceDate];
    
    for (NSUInteger iteration = 1; iteration <= iterations; iteration++) {
        NSTimeInterval startTime = [NSDate timeIntervalSinceReferenceDate];
        NSData *hash = [data signatureWithAlgorithm:self.algorithmName];
        OB_UNUSED_VALUE(hash);
        NSTimeInterval endTime = [NSDate timeIntervalSinceReferenceDate];
        
        intervals[iteration-1] = endTime - startTime;
        
        if (iteration == iterations) {
            NSTimeInterval average = timeIntervalAverage(intervals, iterations);
            double standardDeviation = timeIntervalStandardDeviation(intervals, iterations);
            
            NSTimeInterval overallEndTime = [NSDate timeIntervalSinceReferenceDate];
            if (standardDeviation > 0.1 * average && iterations < 1000 && overallEndTime - overallStartTime < 60) {
                iterations = 2 * iterations;
                intervals = realloc(intervals, iterations * sizeof(NSTimeInterval));
            } else {
                self.averageTime = average;
                self.standardDeviation = standardDeviation;
                self.iterations = iterations;
            }
        }
    }
    
    free(intervals);
    [data release];
}

@end

#endif
