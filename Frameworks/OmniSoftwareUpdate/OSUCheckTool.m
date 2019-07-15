// Copyright 2002-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniSoftwareUpdate/OSUCheckOperation.h>
#import <OmniFoundation/NSString-OFSimpleMatching.h>
#import <Foundation/Foundation.h>

#import <OmniBase/OmniBase.h>

RCS_ID("$Id$");

#define OSUTool_Success	0
#define OSUTool_Failure	1

static char *programName;

static void fwriteData(CFDataRef buf, FILE *fp);

static void exit_with_plist(id plist)
{
#if 0 && defined(DEBUG)
    NSLog(@"exiting with plist:\n%@\n", plist);
#endif
    NSString *errorDescription = nil;
    NSData *outputData = [NSPropertyListSerialization dataFromPropertyList:plist format:NSPropertyListXMLFormat_v1_0 errorDescription:&errorDescription];
    if (outputData)
        fwriteData((CFDataRef)outputData, stdout);
    else {
#ifdef DEBUG    
        NSLog(@"Error archiving result dictionary: %@", errorDescription);
#endif	
        exit(OSUTool_Failure);
    }
    
    exit(0); // The result status is in the plist -- if there was an error, it is in the OSUCheckResultsErrorKey entry.
}

static void exit_with_error(NSError *error)
{
    NSDictionary *dict = [[NSDictionary alloc] initWithObjectsAndKeys:[error toPropertyList], OSUCheckResultsErrorKey, nil];
    exit_with_plist(dict);
    [dict release]; // clang
}


static void usage()
{
    fprintf(stderr,
            "usage: %s firsthophost url app-identifier app-version track {with|without}-hardware {query,report} license-type osu-version\n"
            "\tUnobtrusively retrieves the specified URL, which must contain\n"
            "\ta plist, and writes its contents to stdout.\n\tExit code indicates reason for failure.\n",
            programName);
    exit(OSUTool_Failure);
}

int main(int _argc, char **_argv) // Don't use these directly
{
    // We are short lived -- we'll just create a top-level pool and leak everything that goes into it.
    [[NSAutoreleasePool alloc] init];
    
    programName = _argv[0];

#ifdef DEBUG
    if (_argc == 2 && strcmp(_argv[1], "glext-compress-test") == 0) {
        [[NSAutoreleasePool alloc] init];
        OSULogTestGLExtensionCompressionTestVector();
        return 0;
    }
#endif
    
    if (_argc != 10)
        usage();

    // Extract arguments by position.  We have a lot of them, so lets keep that code right here.
    OSURunOperationParameters params = {0};
    params.firstHopHost = [NSString stringWithUTF8String:_argv[1]];
    params.baseURLString = [NSString stringWithUTF8String:_argv[2]];
    params.appIdentifier = [NSString stringWithUTF8String:_argv[3]];
    params.appVersionString = [NSString stringWithUTF8String:_argv[4]];
    params.track = [NSString stringWithUTF8String:_argv[5]];
    const char *includeHardwareCString = _argv[6];
    const char *reportModeCString = _argv[7];
    params.licenseType = [NSString stringWithUTF8String:_argv[8]];
    params.osuVersionString = [NSString stringWithUTF8String:_argv[9]];

    if (![params.baseURLString containsString:@":"])
        usage();
    
    
    if (strcmp(includeHardwareCString, "with-hardware") == 0)
        params.includeHardwareInfo = true;
    else if (strcmp(includeHardwareCString, "without-hardware") == 0)
        params.includeHardwareInfo = false;
    else
        usage();

    if (strcmp(reportModeCString, "report") == 0)
        params.reportMode = true;
    else if (strcmp(reportModeCString, "query") == 0)
        params.reportMode = false;
    else
        usage();

    NSError *error = nil;
    NSDictionary *result = OSURunOperation(&params, &error);
    if (!result)
        exit_with_error(error);
    else
        exit_with_plist(result);

    return OSUTool_Success;
}

static void fwriteData(CFDataRef buf, FILE *fp)
{
    fwrite(CFDataGetBytePtr(buf), 1, CFDataGetLength(buf), fp);
}

