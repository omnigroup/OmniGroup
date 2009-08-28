// Copyright 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#define STEnableDeprecatedAssertionMacros
#import "OFTestCase.h"

#import <OmniFoundation/NSData-OFExtensions.h>
#import <OmniFoundation/NSDictionary-OFExtensions.h>
#import <OmniFoundation/NSMutableData-OFExtensions.h>
#import <OmniFoundation/NSString-OFExtensions.h>
#import <OmniFoundation/OFScratchFile.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OFErrors.h>

#import <OmniFoundation/OFFilterProcess.h>

RCS_ID("$Id$");

@interface OFDataTest : OFTestCase
{
}


@end


@implementation OFDataTest

- (void)testPipe
{
    NSData *smallData   = [NSData dataWithBytes:"Just remember ... wherever you go ... there you are." length:52];
    NSData *smallData13 = [NSData dataWithBytes:"Whfg erzrzore ... jurerire lbh tb ... gurer lbh ner." length:52];
    NSError *uniqueErrorObject = [NSError errorWithDomain:@"blah" code:42 userInfo:[NSDictionary dictionary]];
    NSError *err = uniqueErrorObject;
    
    STAssertEqualObjects(([smallData filterDataThroughCommandAtPath:@"/usr/bin/tr" withArguments:[NSArray arrayWithObjects:@"A-Za-z", @"N-ZA-Mn-za-m", nil] error:&err]),
                         smallData13, @"Piping through rot13");
    STAssertTrue(err == uniqueErrorObject, @"should not have modified *error (is now %@)", err);
    
    int mediumSize = 67890;
    NSData *mediumData = [NSData randomDataOfLength:mediumSize];
    NSData *mediumR = [mediumData filterDataThroughCommandAtPath:@"/usr/bin/wc" withArguments:[NSArray arrayWithObject:@"-c"] error:NULL];
    STAssertTrue(mediumSize == atoi([mediumR bytes]), @"Piping through wc");
    
    err = uniqueErrorObject;
    STAssertEqualObjects(([mediumData filterDataThroughCommandAtPath:@"/bin/cat" withArguments:[NSArray array] error:NULL]),
                         mediumData, @"");
    STAssertTrue(err == uniqueErrorObject, @"should not have modified *error (is now %@)", err);
    
    err = nil;
    OFScratchFile *scratch = [OFScratchFile scratchFileNamed:@"ofdatatest" error:&err];
    STAssertNotNil(scratch, @"scratch file");
    if (!scratch)
        return;
    
    [mediumData writeToFile:[scratch filename] atomically:NO];
    
    err = uniqueErrorObject;
    STAssertEqualObjects(([[NSData data] filterDataThroughCommandAtPath:@"/bin/cat" withArguments:[NSArray arrayWithObject:[scratch filename]] error:NULL]),
                         mediumData, @"");
    STAssertTrue(err == uniqueErrorObject, @"should not have modified *error (is now %@)", err);
}

- (void)testPipeLarge
{
    if (![[self class] shouldRunSlowUnitTests]) {
        NSLog(@"*** SKIPPING slow test [%@ %s]", [self class], _cmd);
        return;
    }
    
    /* Make a big random plist */
    NSData *pldata;
    {
        NSAutoreleasePool *p = [[NSAutoreleasePool alloc] init];
        NSMutableArray *a = [NSMutableArray array];
        int i;
        for(i = 0; i < 300; i++) {
            NSMutableDictionary *d = [[NSMutableDictionary alloc] init];
            int j;
            for(j = 0; j < 250; j++) {
                NSString *s = [[NSData randomDataOfLength:15] lowercaseHexString];
                [d setObject:[NSData randomDataOfLength:72] forKey:s];
            }
            [a addObject:d];
            [d release];
        }
        pldata = (NSData *)CFPropertyListCreateXMLData(kCFAllocatorDefault, (CFPropertyListRef)a);
        [p release];
    }
    
    NSData *bzipme = [pldata filterDataThroughCommandAtPath:@"/usr/bin/bzip2" withArguments:[NSArray arrayWithObject:@"--compress"] error:NULL];
    NSData *unzipt = [bzipme filterDataThroughCommandAtPath:@"/usr/bin/bzip2" withArguments:[NSArray arrayWithObject:@"--decompress"] error:NULL];
    STAssertEqualObjects(pldata, unzipt, @"bzip+bunzip");
    
    NSData *gzipme  = [pldata filterDataThroughCommandAtPath:@"/usr/bin/gzip" withArguments:[NSArray arrayWithObject:@"-cf9"] error:NULL];
    NSData *ungzipt = [gzipme filterDataThroughCommandAtPath:@"/usr/bin/gzip" withArguments:[NSArray arrayWithObject:@"-cd"] error:NULL];
    STAssertEqualObjects(pldata, ungzipt, @"gzip+gunzip");
    
    [pldata release];
}

- (void)testPipeRunloop
{
    NSLog(@"Starting %@ %@", OBShortObjectDescription(self), NSStringFromSelector(_cmd));
    
    /* Make a moderately-large random plist */
    NSData *pldata;
    {
        NSAutoreleasePool *p = [[NSAutoreleasePool alloc] init];
        NSMutableArray *a = [NSMutableArray array];
        int i;
        for(i = 0; i < 100; i++) {
            NSMutableDictionary *d = [[NSMutableDictionary alloc] init];
            int j;
            for(j = 0; j < 100; j++) {
                NSString *s = [[NSData randomDataOfLength:15] lowercaseHexString];
                [d setObject:[NSData randomDataOfLength:72] forKey:s];
            }
            [a addObject:d];
            [d release];
        }
        pldata = (NSData *)CFPropertyListCreateXMLData(kCFAllocatorDefault, (CFPropertyListRef)a);
        [p release];
    }
    

    NSRunLoop *l = [NSRunLoop currentRunLoop];
    
    NSOutputStream *resultStream1 = [NSOutputStream outputStreamToMemory];
    OFFilterProcess *bzip = [[OFFilterProcess alloc] initWithParameters:[NSDictionary dictionaryWithObjectsAndKeys:
                                                                         @"/usr/bin/bzip2", OFFilterProcessCommandPathKey,
                                                                         [NSArray arrayWithObject:@"--compress"], OFFilterProcessArgumentsKey,
                                                                         pldata, OFFilterProcessInputDataKey,
                                                                         @"NO", OFFilterProcessDetachTTYKey,
                                                                         nil]
                                                         standardOutput:resultStream1
                                                          standardError:nil];
    [bzip scheduleInRunLoop:l forMode:NSRunLoopCommonModes];
    
    NSOutputStream *resultStream2 = [NSOutputStream outputStreamToMemory];
    OFFilterProcess *gzip = [[OFFilterProcess alloc] initWithParameters:[NSDictionary dictionaryWithObjectsAndKeys:
                                                                         @"/usr/bin/gzip", OFFilterProcessCommandPathKey,
                                                                         [NSArray arrayWithObject:@"-cf7"], OFFilterProcessArgumentsKey,
                                                                         pldata, OFFilterProcessInputDataKey,
                                                                         @"NO", OFFilterProcessDetachTTYKey,
                                                                         nil]
                                                         standardOutput:resultStream2
                                                          standardError:nil];
    [gzip scheduleInRunLoop:l forMode:NSRunLoopCommonModes];
    
    OFFilterProcess *bunzip = nil, *gunzip = nil;
    NSOutputStream *resultStream3 = nil, *resultStream4 = nil;
    
    for(;;) {
        [l runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        
        if (bzip && ![bzip isRunning]) {
            resultStream3 = [NSOutputStream outputStreamToMemory];
            bunzip = [[OFFilterProcess alloc] initWithParameters:[NSDictionary dictionaryWithObjectsAndKeys:
                                                                  @"/usr/bin/bzip2", OFFilterProcessCommandPathKey,
                                                                  [NSArray arrayWithObject:@"--decompress"], OFFilterProcessArgumentsKey,
                                                                  [resultStream1 propertyForKey:NSStreamDataWrittenToMemoryStreamKey], OFFilterProcessInputDataKey,
                                                                  @"NO", OFFilterProcessDetachTTYKey,
                                                                  nil]
                                                  standardOutput:resultStream3
                                                   standardError:nil];
            [bunzip scheduleInRunLoop:l forMode:NSRunLoopCommonModes];
            [bzip release];
            bzip = nil;
        }
        
        if (gzip && ![gzip isRunning]) {
            resultStream4 = [NSOutputStream outputStreamToMemory];
            gunzip = [[OFFilterProcess alloc] initWithParameters:[NSDictionary dictionaryWithObjectsAndKeys:
                                                                  @"/usr/bin/gzip", OFFilterProcessCommandPathKey,
                                                                  [NSArray arrayWithObject:@"-cd"], OFFilterProcessArgumentsKey,
                                                                  [resultStream2 propertyForKey:NSStreamDataWrittenToMemoryStreamKey], OFFilterProcessInputDataKey,
                                                                  @"NO", OFFilterProcessDetachTTYKey,
                                                                  nil]
                                                  standardOutput:resultStream4
                                                   standardError:nil];
            [gunzip scheduleInRunLoop:l forMode:NSRunLoopCommonModes];
            [gzip removeFromRunLoop:l forMode:NSRunLoopCommonModes];
            [gzip autorelease];
            gzip = nil;
        }
        
        if ((!bzip && bunzip && ![bunzip isRunning]) &&
            (!gzip && gunzip && ![gunzip isRunning]))
            break;
    }
    
    [bunzip release];
    [gunzip release];
        
    STAssertEqualObjects(pldata, [resultStream3 propertyForKey:NSStreamDataWrittenToMemoryStreamKey], @"bzip+unbzip");
    STAssertEqualObjects(pldata, [resultStream4 propertyForKey:NSStreamDataWrittenToMemoryStreamKey], @"gzip+gunzip");
    
    [pldata release];
}

- (void)testPipeFailure
{
    NSData *smallData   = [NSData dataWithBytes:"Just remember ... wherever you go ... there you are." length:52];
    NSError *errbuf;
    
    errbuf = nil;
    STAssertNil([smallData filterDataThroughCommandAtPath:@"/usr/bin/false" withArguments:[NSArray array] error:&errbuf], @"command should fail");
    STAssertNotNil(errbuf, @"");
    //NSLog(@"fail w/ exit status: %@", errbuf);
    
    errbuf = nil;
    STAssertNil([smallData filterDataThroughCommandAtPath:@"/bin/quux-nonexist" withArguments:[NSArray array] error:&errbuf], @"command should fail");
    STAssertNotNil(errbuf, @"");
    //NSLog(@"fail w/ exec failure: %@", errbuf);
    
    errbuf = nil;
    STAssertNil([smallData filterDataThroughCommandAtPath:@"/bin/sh" withArguments:([NSArray arrayWithObjects:@"-c", @"kill -TERM $$", nil]) error:&errbuf], @"command should fail");
    STAssertNotNil(errbuf, @"");
    //NSLog(@"fail w/ signal: %@", errbuf);
    STAssertEquals((int)[[[[errbuf userInfo] objectForKey:NSUnderlyingErrorKey] userInfo] intForKey:OFProcessExitSignalErrorKey], (int)SIGTERM, @"properly collected exit status");
    
    errbuf = nil;
    STAssertEqualObjects([NSData data],
                         [smallData filterDataThroughCommandAtPath:@"/usr/bin/true" withArguments:[NSArray array] error:&errbuf], @"command should succeed without output");
    STAssertNil(errbuf, @"");
}

/* This is really a test of OFFilterProcess, but the main use of that class is for filtering NSDatas, so it's here */
- (void)testFilterEnv
{
    BOOL ok;
    NSData *outBuf, *errBuf;
    NSError *err;
    
    
    /* Invoke printenv, and make sure it sees the additional environment variables we set */
    outBuf = nil;
    errBuf = nil;
    err = nil;
    ok = [OFFilterProcess runWithParameters:[NSDictionary dictionaryWithObjectsAndKeys:@"/usr/bin/printenv", OFFilterProcessCommandPathKey,
                                             [NSArray array], OFFilterProcessArgumentsKey,
                                             [NSData data], OFFilterProcessInputDataKey,
                                             [NSDictionary dictionaryWithObjectsAndKeys:@"bar", @"BAR",
                                              [NSData dataWithBytes:"spoon" length:5], [NSData dataWithBytes:"TICK" length:4],
                                              nil], OFFilterProcessAdditionalEnvironmentKey,
                                             nil]
                                     inMode:nil standardOutput:&outBuf standardError:&errBuf error:&err];
    STAssertTrue(ok, @"running process 'printenv'");
    STAssertEqualObjects(errBuf, [NSData data], @"should produce no output on stderr");
    if (err) NSLog(@"error: %@", err);
    STAssertNil(err, nil);
    NSString *outStr = [NSString stringWithData:outBuf encoding:NSASCIIStringEncoding];
    STAssertTrue([outStr containsString:@"BAR=bar"], @"process environment contains string");
    STAssertTrue([outStr containsString:@"TICK=spoon"], @"process environment contains string generated from NSData");
    
    /* Invoke printenv via the shell, with a $PATH that doesn't include printenv: case 1, replace entire environment */
    outBuf = nil;
    errBuf = nil;
    err = nil;
    ok = [OFFilterProcess runWithParameters:[NSDictionary dictionaryWithObjectsAndKeys:@"/bin/sh", OFFilterProcessCommandPathKey,
                                             [NSArray arrayWithObjects:@"-c", @"printenv", nil], OFFilterProcessArgumentsKey,
                                             [NSData data], OFFilterProcessInputDataKey,
                                             [NSDictionary dictionaryWithObjectsAndKeys:@"/tmp:/", @"PATH",
                                              nil], OFFilterProcessReplacementEnvironmentKey,
                                             nil]
                                     inMode:nil standardOutput:&outBuf standardError:&errBuf error:&err];
    STAssertFalse(ok, @"running process 'printenv'");
    // if (err) NSLog(@"error: %@", err);
    STAssertNotNil(err, @"should have returned an error to us");
    if(err) {
        STAssertEqualObjects([err domain], @"com.omnigroup.framework.OmniFoundation", nil);
        STAssertEquals([err code], (NSInteger)OFFilterDataCommandReturnedErrorCodeError, nil);
        STAssertTrue([[[err userInfo] objectForKey:OFProcessExitStatusErrorKey] intValue] > 0, @"should indicate process had nonzero exit");
    }
    STAssertFalse([errBuf isEqual:[NSData data]], @"captured stderr should be nonempty");
    
    
    /* Invoke printenv via the shell, using OFFilterProcessAdditionalPathEntryKey to ensure $PATH contains its path */
    outBuf = nil;
    errBuf = nil;
    err = nil;
    ok = [OFFilterProcess runWithParameters:[NSDictionary dictionaryWithObjectsAndKeys:@"/bin/sh", OFFilterProcessCommandPathKey,
                                             [NSArray arrayWithObjects:@"-c", @"printenv", nil], OFFilterProcessArgumentsKey,
                                             [NSData data], OFFilterProcessInputDataKey,
                                             [NSDictionary dictionaryWithObjectsAndKeys:@"/tmp:/", @"PATH",
                                              nil], OFFilterProcessReplacementEnvironmentKey,
                                             @"/usr/bin", OFFilterProcessAdditionalPathEntryKey,
                                             nil]
                                     inMode:nil standardOutput:&outBuf standardError:&errBuf error:&err];
    STAssertTrue(ok, @"running process 'printenv'");
    if (err) NSLog(@"error: %@", err);
    STAssertNil(err, nil);
    STAssertEqualObjects(errBuf, [NSData data], @"should produce no output on stderr");
    outStr = [NSString stringWithData:outBuf encoding:NSASCIIStringEncoding];
    STAssertTrue([outStr containsString:@"PATH=/tmp:/:/usr/bin"], @"process environment $PATH value");
    
    /* Invoke printenv via the shell, with a $PATH that doesn't include printenv: case 2, just override $PATH */
    outBuf = nil;
    errBuf = nil;
    err = nil;
    ok = [OFFilterProcess runWithParameters:[NSDictionary dictionaryWithObjectsAndKeys:@"/bin/sh", OFFilterProcessCommandPathKey,
                                             [NSArray arrayWithObjects:@"-c", @"printenv", nil], OFFilterProcessArgumentsKey,
                                             [NSData data], OFFilterProcessInputDataKey,
                                             [NSDictionary dictionaryWithObjectsAndKeys:@"/tmp:/", @"PATH",
                                              nil], OFFilterProcessAdditionalEnvironmentKey,
                                             nil]
                                     inMode:nil standardOutput:&outBuf standardError:&errBuf error:&err];
    STAssertFalse(ok, @"running process 'printenv'");
    // if (err) NSLog(@"error: %@", err);
    STAssertNotNil(err, @"should have returned an error to us");
    STAssertFalse([errBuf isEqual:[NSData data]], @"captured stderr should be nonempty");
    
    /* Invoke printenv via the shell, using OFFilterProcessAdditionalPathEntryKey to ensure $PATH contains its path: case 2 */
    outBuf = nil;
    errBuf = nil;
    err = nil;
    ok = [OFFilterProcess runWithParameters:[NSDictionary dictionaryWithObjectsAndKeys:@"/bin/sh", OFFilterProcessCommandPathKey,
                                             [NSArray arrayWithObjects:@"-c", @"printenv", nil], OFFilterProcessArgumentsKey,
                                             [NSData data], OFFilterProcessInputDataKey,
                                             [NSDictionary dictionaryWithObjectsAndKeys:@"/tmp:/", @"PATH",
                                              nil], OFFilterProcessAdditionalEnvironmentKey,
                                             @"/usr/bin", OFFilterProcessAdditionalPathEntryKey,
                                             nil]
                                     inMode:nil standardOutput:&outBuf standardError:&errBuf error:&err];
    STAssertTrue(ok, @"running process 'printenv'");
    if (err) NSLog(@"error: %@", err);
    STAssertNil(err, nil);
    STAssertEqualObjects(errBuf, [NSData data], @"should produce no output on stderr");
    outStr = [NSString stringWithData:outBuf encoding:NSASCIIStringEncoding];
    STAssertTrue([outStr containsString:@"PATH=/tmp:/:/usr/bin"], @"process environment $PATH value");
    
    /* Make sure that a redundant OFFilterProcessAdditionalPathEntryKey doesn't screw anything up */
    outBuf = nil;
    errBuf = nil;
    err = nil;
    ok = [OFFilterProcess runWithParameters:[NSDictionary dictionaryWithObjectsAndKeys:@"/usr/bin/printenv", OFFilterProcessCommandPathKey,
                                             [NSArray array], OFFilterProcessArgumentsKey,
                                             [NSData data], OFFilterProcessInputDataKey,
                                             [NSDictionary dictionaryWithObjectsAndKeys:@"/usr/bin:/bin:/tmp:/sbin:/usr/local/bin", @"PATH",
                                              nil], OFFilterProcessAdditionalEnvironmentKey,
                                             @"/tmp", OFFilterProcessAdditionalPathEntryKey,
                                             nil]
                                     inMode:nil standardOutput:&outBuf standardError:&errBuf error:&err];
    STAssertTrue(ok, @"running process 'printenv'");
    if (err) NSLog(@"error: %@", err);
    STAssertNil(err, nil);
    STAssertEqualObjects(errBuf, [NSData data], @"should produce no output on stderr");
    outStr = [NSString stringWithData:outBuf encoding:NSASCIIStringEncoding];
    STAssertTrue([outStr containsString:@"PATH=/usr/bin:/bin:/tmp:/sbin:/usr/local/bin\n"], @"process environment $PATH value");
}

- (void)testMergingStdoutAndStderr;
{
    NSError *error = nil;
    NSData *outputData = [[NSData data] filterDataThroughCommandAtPath:@"/bin/sh" withArguments:[NSArray arrayWithObjects:@"-c", @"echo foo; echo bar 1>&2", nil] includeErrorsInOutput:YES errorStream:nil error:&error];
    STAssertEqualObjects(outputData, [@"foo\nbar\n" dataUsingEncoding:NSUTF8StringEncoding], @"");
    STAssertTrue(error == nil, @"");
}

- (void)testSendingStderrToStream;
{
    // Errors go to the stream, output to the output data
    NSError *error = nil;
    NSOutputStream *errorStream = [NSOutputStream outputStreamToMemory];
    [errorStream open]; // Else, an error will result when writing to the stream
    
    NSData *outputData = [[NSData data] filterDataThroughCommandAtPath:@"/bin/sh" withArguments:[NSArray arrayWithObjects:@"-c", @"echo foo; echo bar 1>&2", nil] includeErrorsInOutput:NO errorStream:errorStream error:&error];
    
    STAssertEqualObjects(outputData, [@"foo\n" dataUsingEncoding:NSUTF8StringEncoding], @"");
    STAssertEqualObjects([errorStream propertyForKey:NSStreamDataWrittenToMemoryStreamKey], [@"bar\n" dataUsingEncoding:NSUTF8StringEncoding], @"");
    STAssertTrue(error == nil, @"no error");
}

- (void)testAppendString
{
    NSData *d1 = [NSData dataWithBytesNoCopy:"foobar" length:6 freeWhenDone:NO];
    NSData *d2 = [NSData dataWithBytesNoCopy:"f\0o\0o\0\0b\0a\0r" length:12 freeWhenDone:NO];
    NSData *d3 = [NSData dataWithBytesNoCopy:"this\0that" length:9 freeWhenDone:NO];
    
    const unichar ch[5] = { 'i', 's', 0, 't', 'h' };
    NSString *st = [NSString stringWithCharacters:ch length:5];
    NSString *st2 = [NSString stringWithData:[st dataUsingEncoding:NSMacOSRomanStringEncoding] encoding:NSMacOSRomanStringEncoding];
    
    NSMutableData *buf;
    
    buf = [NSMutableData data];
    [buf appendString:@"foo" encoding:NSASCIIStringEncoding];
    [buf appendString:@"bar" encoding:NSUTF8StringEncoding];
    STAssertEqualObjects(buf, d1, @"");
    
    buf = [NSMutableData data];
    [buf appendString:@"fo" encoding:NSISOLatin1StringEncoding];
    [buf appendString:@"obar" encoding:NSMacOSRomanStringEncoding];
    STAssertEqualObjects(buf, d1, @"");
    
    buf = [NSMutableData data];
    [buf appendString:@"foo" encoding:NSUTF16LittleEndianStringEncoding];
    [buf appendString:@"bar" encoding:NSUTF16BigEndianStringEncoding];
    STAssertEqualObjects(buf, d2, @"");
    
    buf = [NSMutableData data];
    [buf appendString:@"th" encoding:NSASCIIStringEncoding];
    [buf appendString:st encoding:NSASCIIStringEncoding];
    [buf appendString:@"at" encoding:NSASCIIStringEncoding];
    STAssertEqualObjects(buf, d3, @"");
    
    buf = [NSMutableData data];
    [buf appendString:@"th" encoding:NSASCIIStringEncoding];
    [buf appendString:st2 encoding:NSMacOSRomanStringEncoding];
    [buf appendString:@"at" encoding:NSASCIIStringEncoding];
    STAssertEqualObjects(buf, d3, @"");
    
}

@end
