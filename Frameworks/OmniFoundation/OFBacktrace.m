// Copyright 1998-2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFBacktrace.h>

#import <OmniFoundation/NSString-OFReplacement.h>
#import <OmniFoundation/NSString-OFConversion.h>
#import <execinfo.h>

NS_ASSUME_NONNULL_BEGIN


NSString *OFCopyNumericBacktraceString(int framesToSkip)
{
#define MAX_BACKTRACE_DEPTH 128
    void *frames[MAX_BACKTRACE_DEPTH];
    int framecount = backtrace(frames, MAX_BACKTRACE_DEPTH);
    NSMutableString *backtraceText = [[NSMutableString alloc] initWithCapacity:( framecount * ( 2*sizeof(void *) + 2 ) )];
    for(int frameindex = framesToSkip+1; frameindex < framecount; frameindex++) {
        if (frameindex > 0)
            [backtraceText appendString:@"  "];  // Two spaces, for compatibility with NSStackTraceKey
        [backtraceText appendFormat:@"%p", frames[frameindex]];
    }
    
    return backtraceText;
}

NSString *OFCopySymbolicBacktrace(void)
{
    NSString *numericTrace = OFCopyNumericBacktraceString(1);
    NSString *symbolicTrace = OFCopySymbolicBacktraceForNumericBacktrace(numericTrace);
    [numericTrace release];
    return symbolicTrace;
}

NSString *OFCopySymbolicBacktraceForNumericBacktrace(NSString *numericTrace)
{
#if 1
    // #include <execinfo.h>
    // #include <stdio.h>
    NSArray *stackStrings = [[numericTrace stringByCollapsingWhitespaceAndRemovingSurroundingWhitespace] componentsSeparatedByString:@" "];
    NSUInteger frameCount = [stackStrings count];
    void *callstack[frameCount];
    for (NSUInteger frameIndex = 0; frameIndex < frameCount; frameIndex++) {
        NSString *stackString = [stackStrings objectAtIndex:frameIndex];
        callstack[frameIndex] = (void *)(uintptr_t)[stackString maxHexValue];
    }
    OBASSERT(frameCount <= UINT_MAX); // That's all backtrace_symbols() can handle
    char **symbols = backtrace_symbols(callstack, (unsigned int)frameCount);
    NSMutableString *symbolicBacktrace = [[NSMutableString alloc] init];
    for (NSUInteger frameIndex = 0; frameIndex < frameCount; frameIndex++) {
        [symbolicBacktrace appendFormat:@"%p -- %s\n", callstack[frameIndex], symbols[frameIndex]];
#if 0 && defined(DEBUG)
        printf("%s\n", symbols[frameIndex]);
#endif
    }
    free(symbols);
    return symbolicBacktrace;
#else
    // atos is in the developer tools package, so it might not be present
    NSString *atosPath = @"/usr/bin/atos";
    if (![[NSFileManager defaultManager] isExecutableFileAtPath:atosPath])
	return [numericTrace copy];
    
    // We could use backtrace_symbols()  /  dladdr() here, but atos gives more accurate results
    
    NSString *outputString;
    @try {
        NSError *error = nil;
        NSData *inputData = [numericTrace dataUsingEncoding:NSUTF8StringEncoding];
        NSData *outputData = [inputData filterDataThroughCommandAtPath:atosPath
                                                         withArguments:[NSArray arrayWithObjects:@"-p", [NSString stringWithFormat:@"%u", getpid()], nil]
                                                 includeErrorsInOutput:YES
                                                           errorStream:nil
                                                                 error:&error];
        
        if (!outputData) {
            outputString = [[error description] copy]; // for now, just return something for the result
        } else {
            outputString = [[NSString alloc] initWithData:outputData encoding:NSUTF8StringEncoding];
            if (!outputString) {
                outputString = [[NSString alloc] initWithFormat:@"Unable to convert output data to UTF-8:\n%@", outputData];
            }
        }
    } @catch (NSException *exc) {
        // This method can get called for unhandled exceptions, so let's not have any.
        outputString = [[NSString alloc] initWithFormat:@"Exception raised while converting numeric backtrace: %@\n%@", numericTrace, exc];
    }
    return outputString;
#endif
}

void OFLogBacktrace(void)
{
    NSString *backtrace = OFCopySymbolicBacktrace();
    NSData *data = [backtrace dataUsingEncoding:NSUTF8StringEncoding];
    [backtrace release];
    
    fwrite([data bytes], [data length], 1, stderr);
}

NS_ASSUME_NONNULL_END
