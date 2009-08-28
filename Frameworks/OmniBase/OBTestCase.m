// Copyright 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OBTestCase.h"

#import <OmniBase/OmniBase.h>

RCS_ID("$Id$")

#ifdef COVERAGE
#import <crt_externs.h>
#import <mach-o/arch.h>
// When run from Xcode, unit tests get run once for each architecture via various scripts in $SYSTEM_DEVELOPER_DIR/Tools.  This is the easiest way to hook into the per-arch setup.
static void OBTestCaseReportCoverage(void)
{
    const char *coverageTool = getenv("OBCOVERAGE_TOOL");
    const char *archName = getenv("CURRENT_ARCH"); // NXGetLocalArchInfo()->name; --> i486, but we want i386.
    const char *targetName = getenv("OBCOVERAGE_TARGET");
    if (coverageTool) {
        fprintf(stderr, "##\n## Running coverage tool '%s' from '%s' target:%s arch:'%s'...\n##\n", coverageTool, getcwd(NULL, 0), targetName, archName);
        char ***envp = _NSGetEnviron();
        if (envp) {
            char **env = *envp;
            while (*env) {
                fprintf(stderr, "%s\n", *env);
                env++;
            }
        }
        
        int child = fork();
        if (child) {
            // parent -- wait for the child
            int status = 0;
            waitpid(child, &status, WNOHANG);
        } else {
            execle(coverageTool, coverageTool, targetName, archName, NULL, *envp);
            perror("execle");
            exit(1);
        }
    }
}
#endif

@implementation OBTestCase

+ (void) initialize;
{
    OBINITIALIZE;
#ifdef COVERAGE
    atexit(OBTestCaseReportCoverage);
#endif
    [OBPostLoader processClasses];
}

+ (BOOL)shouldRunSlowUnitTests;
{
    return getenv("RunSlowUnitTests") != NULL;
}

@end
