// Copyright 1997-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OWF/OWMailToProcessor.h>

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

RCS_ID("$Id$")

@interface OWMailToProcessor (Private)
- (NSString *)contentString;
@end

#import <OWF/OWAddress.h>
#import <OWF/OWDocumentTitle.h>
#import <OWF/OWURL.h>
#import <OWF/OWWebPipeline.h>

@implementation OWMailToProcessor

// These parameter keys match both MailViewer's API and Netscape's parameter keys.

NSString *OWMailToProcessorToParameterKey = @"to";
NSString *OWMailToProcessorSubjectParameterKey = @"subject";
NSString *OWMailToProcessorBodyParameterKey = @"body";

- initWithContent:(OWContent *)initialContent context:(id <OWProcessorContext>)aPipeline;
{
    if (![super initWithContent:initialContent context:aPipeline])
        return nil;

    mailToAddress = [(OWAddress *)initialContent retain];

    return self;
}

- (void)dealloc;
{
    [mailToAddress release];
    [super dealloc];
}

- (void)process;
{
    OWURL *mailURL;
    NSString *emailAddress;
    NSString *subject;
    NSString *parameterString;
    NSMutableDictionary *newParameterDictionary;

    [pipeline addContent:nil fromProcessor:self];
    [pipeline startProcessingContent];

    [self setStatusFormat:NSLocalizedStringFromTableInBundle(@"Parsing mail address", @"OWF", [OWMailToProcessor bundle], @"mailto status")];

    newParameterDictionary = [[NSMutableDictionary alloc] initWithCapacity:3];
    [parameterDictionary release];
    parameterDictionary = [newParameterDictionary retain];

    mailURL = [mailToAddress url];
    emailAddress = [mailURL netLocation];
    if (!emailAddress)
	emailAddress = [mailURL schemeSpecificPart];
    if (!emailAddress)
	[NSException raise:@"No address" format:NSLocalizedStringFromTableInBundle(@"No mail address", @"OWF", [OWMailToProcessor bundle], @"mailto error")];

    emailAddress = [NSString decodeURLString:emailAddress];
    if ([emailAddress containsString:@"?"]) {
	NSArray *components;

	components = [emailAddress componentsSeparatedByString:@"?"];
	emailAddress = [components objectAtIndex:0];
	parameterString = [components objectAtIndex:1];
    } else {
        parameterString = [mailURL query];
    }

    if (parameterString) {
        NSArray *parameterArray;
        unsigned int parameterIndex, parameterCount;

        parameterArray = [parameterString componentsSeparatedByString:@"&"];
        parameterCount = [parameterArray count];
        for (parameterIndex = 0; parameterIndex < parameterCount; parameterIndex++) {
            NSString *aParameter;

            aParameter = [parameterArray objectAtIndex:parameterIndex];
            if ([aParameter containsString:@"="]) {
                NSArray *keyValueArray;
                NSString *key, *value;

                keyValueArray = [aParameter componentsSeparatedByString:@"="];
                key = [keyValueArray objectAtIndex:0];
                value = [keyValueArray objectAtIndex:1];
                [newParameterDictionary setObject:value forKey:[key lowercaseString]];
            } else {
                // No parameter name specified: set the body (as we did in OmniWeb 2.x)
                [newParameterDictionary setObject:aParameter forKey:OWMailToProcessorBodyParameterKey];
            }
        }
    }

    if ([[mailToAddress methodString] isEqualToString:@"POST"]) {
        [newParameterDictionary setObject:[self contentString] forKey:OWMailToProcessorBodyParameterKey];
    }

    subject = [newParameterDictionary objectForKey:OWMailToProcessorSubjectParameterKey];
    if (!subject) {
        OWAddress *referringAddress;

        // We fetch the message's title from the title of the document that contained the mailto: anchor.

        referringAddress = [aPipeline contextObjectForKey:OWCacheArcReferringAddressKey];
        if (referringAddress) {
            subject = [OWDocumentTitle titleForAddress:referringAddress];
            if (!subject)
                subject = [referringAddress addressString];
        }
        if (!subject)
            subject = NSLocalizedStringFromTableInBundle(@"Web page", @"OWF", [OWMailToProcessor bundle], @"mailto fallback subject line");

        subject = [NSLocalizedStringFromTableInBundle(@"Re: ", @"OWF", [OWMailToProcessor bundle], @"mailto subject line before page name") stringByAppendingString:subject];
    }

    // Replace newlines in the subject with spaces.
    subject = [[subject componentsSeparatedByString:@"\n"] componentsJoinedByString:@" "];

    [newParameterDictionary setObject:subject forKey:OWMailToProcessorSubjectParameterKey];
    [newParameterDictionary setObject:emailAddress forKey:OWMailToProcessorToParameterKey];
    [newParameterDictionary release];

    [self setStatusFormat:NSLocalizedStringFromTableInBundle(@"Sending mail to %@", @"OWF", [OWMailToProcessor bundle], @"mailto status"), emailAddress];
    [self deliver];
}

// Callbacks

- (void)deliver;
{
    // This must be implemented by a subclass.
}

@end

@implementation OWMailToProcessor (Private)

- (NSString *)contentString;
{
    return [[mailToAddress methodDictionary] objectForKey:OWAddressContentStringMethodKey];
}

@end
