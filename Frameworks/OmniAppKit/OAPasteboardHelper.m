// Copyright 1997-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OAPasteboardHelper.h>

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

RCS_ID("$Id$")

@implementation OAPasteboardHelper

+ (OAPasteboardHelper *)helperWithPasteboard:(NSPasteboard *)newPasteboard;
{
    return [[[self alloc] initWithPasteboard:newPasteboard] autorelease];
}

+ (OAPasteboardHelper *)helperWithPasteboardNamed:(NSString *)pasteboardName;
{
    return [[[self alloc] initWithPasteboardNamed:pasteboardName] autorelease];
}

- initWithPasteboard:(NSPasteboard *)newPasteboard;
{
    [super init];

    pasteboard = [newPasteboard retain];
    typeToOwner = [[NSMutableDictionary alloc] init];

    return self;
}

- initWithPasteboardNamed:(NSString *)pasteboardName;
{
    return [self initWithPasteboard:[NSPasteboard pasteboardWithName:pasteboardName]];
}

- (void)dealloc;
{
    [self absolvePasteboardResponsibility];
    [typeToOwner release];
    [pasteboard release];
    [super dealloc];	
}


// Public API

- (void)addTypes:(NSArray *)someTypes owner:(id)anOwner;
{
    OBPRECONDITION(anOwner);
    OBPRECONDITION(someTypes);

    if ([typeToOwner count] == 0) {
        [pasteboard declareTypes:someTypes owner:self];
        if (responsible++ == 0)
            [self retain]; // We must stay around until no longer responsible
    } else
	[pasteboard addTypes:someTypes owner:self];

    [typeToOwner setObject:anOwner forKeys:someTypes];
}

- (NSPasteboard *)pasteboard;
{
    return pasteboard;
}

- (void)declareTypes:(NSArray *)someTypes owner:(id)anOwner;
{
    [self absolvePasteboardResponsibility];
    [self addTypes:someTypes owner:anOwner];
}

- (void)absolvePasteboardResponsibility;
{
    [typeToOwner removeAllObjects];
}

// Pasteboard delegate methods

- (void)pasteboard:(NSPasteboard *)aPasteboard provideDataForType:(NSString *)type;
{
    id realOwner;

    realOwner = [typeToOwner objectForKey:type];
    [realOwner pasteboard:aPasteboard provideDataForType:type];
}

- (void)pasteboardChangedOwner:(NSPasteboard *)aPasteboard;
{
    if (--responsible == 0) {
	[self absolvePasteboardResponsibility];
        [self release]; // No longer responsible, so dump the extra retain we added in -addTypes:owner:
    }
}

// Debugging

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *debugDictionary;

    debugDictionary = [super debugDictionary];
    if (pasteboard)
        [debugDictionary setObject:pasteboard forKey:@"pasteboard"];
    if (typeToOwner)
        [debugDictionary setObject:typeToOwner forKey:@"typeToOwner"];
    return debugDictionary;
}

@end
