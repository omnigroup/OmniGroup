// Copyright 2007 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OmniFoundation.h>
#import <OmniBase/OmniBase.h>
#import <Foundation/Foundation.h>
#import <SenTestingKit/SenTestingKit.h>
#import <OmniFoundation/OFTransformStream.h>
#import <OmniFoundation/OFCompressionStream.h>

RCS_ID("$Id$");

@interface OFStreamTransformTests : SenTestCase
{
}

@end

@interface NullTransform : NSObject <OFStreamTransformer>
{
    BOOL noMoreInput;
    struct OFTransformStreamBuffer buf;
}
@end

@implementation NullTransform

- init
{
    [super init];
    noMoreInput = NO;
    buf.buffer = NULL;
    buf.dataStart = buf.dataLength = buf.bufferSize = 0;
    return self;
}

- (void)open;
{
}

- (void)noMoreInput;
{
    noMoreInput = YES;
}

- (struct OFTransformStreamBuffer *)inputBuffer;
{
    return &buf;
}

- (unsigned int)goodBufferSize;
{
    return 0;
}

- (enum OFStreamTransformerResult)transform:(struct OFTransformStreamBuffer *)intoBuffer error:(NSError **)outError;
{
    if (buf.dataLength == 0) {
        if (noMoreInput)
            return OFStreamTransformerFinished;
        else
            return OFStreamTransformerNeedInput;
    }
    
    unsigned availSpace = intoBuffer->bufferSize - ( intoBuffer->dataStart + intoBuffer->dataLength );
    unsigned tocopy = MIN(availSpace, buf.dataLength);
    
    if (tocopy == 0)
        return OFStreamTransformerNeedOutputSpace;
        
    memcpy(intoBuffer->buffer + ( intoBuffer->dataStart + intoBuffer->dataLength ), buf.buffer + buf.dataStart, tocopy);
    buf.dataStart += tocopy;
    buf.dataLength -= tocopy;
    intoBuffer->dataLength += tocopy;
    
    return OFStreamTransformerContinue;
}

- (NSArray *)allKeys;
{
    return nil;
}

- propertyForKey:(NSString *)aKey;
{
    OBRejectInvalidCall(self, _cmd, @"%@ does not have a property named %@", [self class], aKey);
}

- (void)setProperty:prop forKey:(NSString *)aKey;
{
    OBRejectInvalidCall(self, _cmd, @"%@ does not have a property named %@", [self class], aKey);
}

@end


@implementation OFStreamTransformTests

- (void)testNullTransform
{
    NSData *s = [@"This is a short piece of text." dataUsingEncoding:NSASCIIStringEncoding];
    NSInputStream *is = [NSInputStream inputStreamWithData:s];
    NSInputStream *ts = [[[OFInputTransformStream alloc] initWithStream:is transform:[[[NullTransform alloc] init] autorelease]] autorelease];
    NSMutableData *o = [NSMutableData data];
    
    [ts open];
    for(;;) {
        char buf[12];
        int r = [ts read:(void *)buf maxLength:12];
        NSLog(@"read %d bytes: [%.*s]", r, r, buf);
        [o appendBytes:buf length:r];
        if ([ts streamStatus] != NSStreamStatusOpen)
            break;
    }
    
    STAssertTrue([ts streamStatus] == NSStreamStatusAtEnd, @"");
    STAssertEqualObjects(o, s, @"");
}

- (void)testInput:(NSData *)inData output:(NSData *)outData transform:(NSObject <OFStreamTransformer> *)xform description:(NSString *)s
{    
    NSInputStream *is = [NSInputStream inputStreamWithData:inData];
    
    NSInputStream *ts = [[[OFInputTransformStream alloc] initWithStream:is transform:xform] autorelease];
    
    NSMutableData *o = [NSMutableData data];
    
    [ts open];
    for(;;) {
        char buf[12];
        int r = [ts read:(void *)buf maxLength:12];
        NSLog(@"read %d bytes: [%.*s]", r, r, buf);
        [o appendBytes:buf length:r];
        if ([ts streamStatus] != NSStreamStatusOpen)
            break;
    }
    
    STAssertTrue([ts streamStatus] == NSStreamStatusAtEnd, s);
    STAssertTrue([o length] == [outData length], s);
    STAssertTrue(memcmp([o bytes], [outData bytes], [o length]) == 0, s);
}

- (void)testSmallBzip2
{
    const char c[] = {
        0x42, 0x5a, 0x68, 0x39, 0x31, 0x41, 0x59, 0x26, 0x53, 0x59, 0x4d,
        0x52, 0xd6, 0x5a, 0x00, 0x00, 0x06, 0x13, 0x80, 0x40, 0x05, 0x04,
        0x00, 0x3b, 0xe7, 0xde, 0x40, 0x20, 0x00, 0x48, 0x6a, 0x9e, 0x53,
        0x7a, 0xa1, 0x8d, 0x46, 0x8d, 0xea, 0x6a, 0x14, 0x68, 0xc8, 0x1a,
        0x34, 0xc8, 0xd3, 0x2e, 0xc6, 0xe8, 0x59, 0x46, 0xef, 0x5a, 0x83,
        0xae, 0xf1, 0x81, 0xd2, 0x40, 0xfb, 0xab, 0x78, 0xdb, 0x70, 0x18,
        0x21, 0xcb, 0xc0, 0xb8, 0x31, 0x26, 0x66, 0xbf, 0x17, 0x72, 0x45,
        0x38, 0x50, 0x90, 0x4d, 0x52, 0xd6, 0x5a
    };
    const char *u = "This is a longer piece of text, but not much longer.";
    
    NSInputStream *is = [NSInputStream inputStreamWithData:[NSData dataWithBytesNoCopy:c length:sizeof(c) freeWhenDone:NO]];
    
    NSInputStream *ts = [[[OFInputTransformStream alloc] initWithStream:is transform:[[[OFBzip2DecompressTransform alloc] init] autorelease]] autorelease];
    
    NSMutableData *o = [NSMutableData data];
    
    [ts open];
    for(;;) {
        char buf[12];
        int r = [ts read:(void *)buf maxLength:12];
        NSLog(@"read %d bytes: [%.*s]", r, r, buf);
        [o appendBytes:buf length:r];
        if ([ts streamStatus] != NSStreamStatusOpen)
            break;
    }
    
    STAssertTrue([ts streamStatus] == NSStreamStatusAtEnd, @"");
    STAssertTrue([o length] == strlen(u), @"");
    STAssertTrue(memcmp([o bytes], u, [o length]) == 0, @"");
    
    NSData *compressedData = [NSData dataWithBytesNoCopy:c length:sizeof(c) freeWhenDone:NO];
    NSData *noncompressedData = [NSData dataWithBytesNoCopy:u length:strlen(u) freeWhenDone:NO];
    [self testInput:compressedData output:noncompressedData transform:[[OFBzip2DecompressTransform alloc] init] description:@"OFBzip2DecompressTransform"];
    [self testInput:noncompressedData output:compressedData transform:[[OFBzip2CompressTransform alloc] init] description:@"OFBzip2CompressTransform"];
}

@end

