// Copyright 1999-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSString-OFPathExtensions.h>

#import <OmniFoundation/OFCharacterSet.h>


RCS_ID("$Id$")

@implementation NSString (OFPathExtensions)

/*" Reformats a path as 'lastComponent emdash stringByByRemovingLastPathComponent' "*/
- (NSString *) prettyPathString;
{
    NSString *last, *prefix;
    
    last = [self lastPathComponent];
    prefix = [self stringByDeletingLastPathComponent];
    
    if (![last length] || ![prefix length])
        // was a single component?
        return self;
    
    // 0x2014 is emdash (this is more efficient than calling +emdashString and also means we don't have to pull in OFExtensions for iOS)
    return [NSString stringWithFormat: @"%@ %C %@", last, (unichar)0x2014, prefix];
}

+ (NSString *)pathSeparator;
{
    return [NSOpenStepRootDirectory() substringToIndex:1];
}

NSArray *OFCommonRootPathComponents(NSString *filename, NSString *otherFilename, NSArray **componentsLeft, NSArray **componentsRight)
{
    NSUInteger i;

    NSArray *filenameArray = [filename pathComponents];
    NSArray *otherArray = [[otherFilename stringByStandardizingPath] pathComponents];
    NSUInteger minLength = MIN([filenameArray count], [otherArray count]);
    NSMutableArray *resultArray = [NSMutableArray arrayWithCapacity:minLength];

    for (i = 0; i < minLength; i++) {
        if ([[filenameArray objectAtIndex:i] isEqualToString:[otherArray objectAtIndex:i]])
            [resultArray addObject:[filenameArray objectAtIndex:i]];
        else
            break;
    }
        
    if ([resultArray count] == 0)
        return nil;

    if (componentsLeft)
        *componentsLeft = [filenameArray subarrayWithRange:(NSRange){i, [filenameArray count] - i}];
    if (componentsRight)
        *componentsRight = [otherArray subarrayWithRange:(NSRange){i, [otherArray count] - i}];
    
    return resultArray;
}

+ (NSString *)commonRootPathOfFilename:(NSString *)filename andFilename:(NSString *)otherFilename;
{
    NSArray *components = OFCommonRootPathComponents(filename, otherFilename, NULL, NULL);
    return components? [NSString pathWithComponents:components] : nil;
}

- (NSString *)relativePathToFilename:(NSString *)otherFilename;
{
    NSArray *commonRoot, *myUniquePart, *otherUniquePart;
    NSUInteger numberOfStepsUp, i;

    otherFilename = [otherFilename stringByStandardizingPath];
    commonRoot = OFCommonRootPathComponents([self stringByStandardizingPath], otherFilename, &myUniquePart, &otherUniquePart);
    if (commonRoot == nil || [commonRoot count] == 0)
        return otherFilename;
    
    numberOfStepsUp = [myUniquePart count];
    if (numberOfStepsUp == 0)
        return [NSString pathWithComponents:otherUniquePart];
    if ([[myUniquePart lastObject] isEqualToString:@""])
        numberOfStepsUp --;
    if (numberOfStepsUp == 0)
        return [NSString pathWithComponents:otherUniquePart];
    
    NSMutableArray *stepsUpArray = [[otherUniquePart mutableCopy] autorelease];
    for (i = 0; i < numberOfStepsUp; i++) {
        NSString *steppingUpPast = [myUniquePart objectAtIndex:i];
        if ([steppingUpPast isEqualToString:@".."]) {
            if ([[stepsUpArray objectAtIndex:0] isEqualToString:@".."])
                [stepsUpArray removeObjectAtIndex:0];
            else {
                // Gack! Just give up.
                return nil;
            }
        } else
            [stepsUpArray insertObject:@".." atIndex:0];
    }

    return [[NSString pathWithComponents:stepsUpArray] stringByStandardizingPath];
}

- (void)splitName:(NSString * OB_AUTORELEASING *)outName andCounter:(NSUInteger *)outCounter;
{
    NSString *name = nil;
    NSUInteger counter = 0;
    NSRange notNumberRange = [name rangeOfCharacterFromSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet] options:NSBackwardsSearch];
    
    // Has at least one digit at the end and isn't all digits?
    if (notNumberRange.length > 0 && NSMaxRange(notNumberRange) < [name length]) {
        // Is there a space before the digits?
        if ([name characterAtIndex:NSMaxRange(notNumberRange) - 1] == ' ') {
            counter = [[name substringFromIndex:NSMaxRange(notNumberRange)] intValue];
            name = [name substringToIndex:NSMaxRange(notNumberRange) - 1];
        }
    }
    
    if (name == nil) {
        name = [[self copy] autorelease];
    }
    
    *outName = name;
    *outCounter = counter;
}

@end
