// Copyright 2001-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OWAboutURLProcessor.h"

#import <Foundation/Foundation.h>
#import <OmniFoundation/OmniFoundation.h>
#import <OmniBase/OmniBase.h>
#import <OWF/OWAddress.h>
#import <OWF/OWContentType.h>
#import <OWF/OWURL.h>
#import <OWF/OWPipeline.h>

RCS_ID("$Id$");

@implementation OWAboutURLProcessor

static NSString *aboutAliasFilename = nil;

OBDidLoad(^{
    Class self = [OWAboutURLProcessor class];
    [self registerProcessorClass:self fromContentType:[OWURL contentTypeForScheme:@"about"] toContentType:[OWContentType wildcardContentType] cost:1.0f producingSource:YES];
});

+ (void)initialize
{
    if (aboutAliasFilename == nil) {
        aboutAliasFilename = [[NSBundle bundleForClass:[self class]] pathForResource:@"aboutSchemeAliases" ofType:@"plist"];
    }
    
    [super initialize];
}

// Override -startProcessing, since we just do a dictionary lookup (well, we read a file too) and add a new address, so there's no need to spawn another thread.
- (void)startProcessing
{
    [self processInThread];
}

- (void)process
{
    OWURL *aboutURL = [sourceAddress url];
    NSString *aboutWhat = [aboutURL schemeSpecificPart];
    if (aboutWhat == nil)
        aboutWhat = @"";
    
    NSDictionary *aliases = [NSDictionary dictionaryWithContentsOfFile:aboutAliasFilename];
    NSString *redirectTo = nil;
    if (aliases == nil || (redirectTo = [aliases objectForKey:aboutWhat]) == nil) {
        NSException *exception;
        
        if (aliases == nil)
            exception = [NSException exceptionWithName:@"OWAboutMissingResource" reason:NSLocalizedStringFromTableInBundle(@"Unable to locate about: aliases resource", @"OWF", [OWAboutURLProcessor bundle], "about: protocol error") userInfo:nil];
        else
            exception = [NSException exceptionWithName:@"Not Found" reason:[NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Unknown about: item \"%@\"", @"OWF", [OWAboutURLProcessor bundle], "the about: has its version of 404-not-found"), aboutWhat] userInfo:nil];
        [exception raise];
    }
    
    OWAddress *newAddress = [OWAddress addressWithURL:[aboutURL urlFromRelativeString:redirectTo] target:[sourceAddress target] methodString:[sourceAddress methodString] methodDictionary:[sourceAddress methodDictionary] effect:[sourceAddress effect] forceAlwaysUnique:NO contextDictionary:[sourceAddress contextDictionary]];
    
    [self.pipeline addRedirectionContent:newAddress sameURI:NO];
}

@end

