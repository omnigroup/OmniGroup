// Copyright 1997-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OWF/OWFileDataStream.h>

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

@interface OWFileDataStream (private)
@end

RCS_ID("$Id$")

@implementation OWFileDataStream
{
    NSString *inputFilename;
}

// Init and dealloc

- (instancetype)initWithData:(NSData *)data filename:(NSString *)aFilename;
{
    if (data == nil) {
	self = nil;
	return nil;
    }

    self = [super init];
    if (self == nil)
        return nil;
    
    inputFilename = aFilename;
    [self writeData:data];
    [self dataEnd];

    return self;
}

- (instancetype)initWithContentsOfFile:(NSString *)aFilename;
{
    NSData *data;
    id returnValue;
    
    aFilename = [aFilename stringByExpandingTildeInPath];
    data = [[NSData alloc] initWithContentsOfFile:aFilename];
    returnValue = [self initWithData:data filename:aFilename];
    return returnValue;
}

- (instancetype)initWithContentsOfMappedFile:(NSString *)aFilename;
{
    aFilename = [aFilename stringByExpandingTildeInPath];

    NSData *data = [[NSData alloc] initWithContentsOfFile:aFilename options:NSDataReadingMappedIfSafe error:NULL];
    id returnValue = [self initWithData:data filename:aFilename];
    return returnValue;
}

// OWDataStream subclass

- (BOOL)pipeToFilename:(NSString *)aFilename withAttributes:(NSDictionary *)fileAttributes shouldPreservePartialFile:(BOOL)shouldPreserve;
{
    // Don't copy our input data unnecessarily
    if (inputFilename != nil)
	return NO;
    return [super pipeToFilename:aFilename withAttributes:fileAttributes shouldPreservePartialFile:shouldPreserve];
}

- (NSString *)filename;
{
    // Return our input filename
    if (inputFilename != nil)
        return inputFilename;
    return [super filename];
}

@end
