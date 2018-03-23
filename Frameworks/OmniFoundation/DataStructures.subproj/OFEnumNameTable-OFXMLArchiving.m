// Copyright 2002-2018 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFEnumNameTable-OFXMLArchiving.h>

#import <OmniFoundation/OFXMLCursor.h>
#import <OmniFoundation/OFXMLDocument.h>
#import <OmniFoundation/OFXMLElement.h>
#import <OmniFoundation/CFDictionary-OFExtensions.h>
#import <OmniBase/rcsid.h>

#import "OFEnumNameTable-Internal.h"

RCS_ID("$Id$");

NS_ASSUME_NONNULL_BEGIN

@implementation OFEnumNameTable (OFXMLArchiving)

// Archiving (primarily for OAEnumStyleAttribute)
+ (NSString *)xmlElementName;
{
    return @"enum-name-table";
}

static int _compareIntptrs(const void *arg1, const void *arg2) {
    void *ptr1 = *(void * const *)arg1;
    void *ptr2 = *(void * const *)arg2;
    intptr_t int1 = (intptr_t)ptr1;
    intptr_t int2 = (intptr_t)ptr2;
    
    return ( int1 > int2 )? 1 : ( (int1 == int2)? 0 : -1 );
}

static inline int _writableEnumValue(NSInteger value)
{
    OBASSERT(value >= INT32_MIN && value <= INT32_MAX); // The writing code currently uses `int`; make sure we don't need to update to 64-bit (soon 32-bit support will be deprecated...)
    return (int)value;
}

- (void)appendXML:(OFXMLDocument *)doc;
{
    [doc pushElement:[[self class] xmlElementName]];
    {
        [doc setAttribute:@"default-value" integer:_writableEnumValue(_defaultEnumValue)];
        
        // Store elements sorted by enum value
        NSInteger enumIndex, enumCount = CFDictionaryGetCount(_enumToName);
        OBASSERT(enumCount == CFDictionaryGetCount(_nameToEnum));
        
        intptr_t *values = malloc(sizeof(intptr_t) * enumCount);
        CFDictionaryGetKeysAndValues(_nameToEnum, NULL, (const void **)values);
        
        qsort(values, enumCount, sizeof(intptr_t), _compareIntptrs);
        
        for (enumIndex = 0; enumIndex < enumCount; enumIndex++) {
            [doc pushElement:@"enum-name-table-element"];
            {
                intptr_t value = values[enumIndex];
                
                [doc setAttribute:@"value" integer:_writableEnumValue(value)];
                
                NSString *name = [self nameForEnum:value];
                NSString *displayName = [self displayNameForEnum:value];
                
                [doc setAttribute:@"name" string:name];
                
                if (![name isEqualToString:displayName])
                    [doc setAttribute:@"display-name" string:displayName];
            }
            [doc popElement];
        }
        free(values);
    }
    [doc popElement];
}

- initFromXML:(OFXMLCursor *)cursor;
{
    OBPRECONDITION([[cursor name] isEqualToString:[[self class] xmlElementName]]);
    
    _defaultEnumValue = [[cursor attributeNamed:@"default-value"] intValue];
    
    if (!(self = [self initWithDefaultEnumValue:_defaultEnumValue]))
        return nil;
    
    id child;
    while ((child = [cursor nextChild])) {
        if (![child isKindOfClass:[OFXMLElement class]])
            continue;
        OFXMLElement *element = child;
        
        if (![[element name] isEqualToString:@"enum-name-table-element"])
            continue;
        
        int value = [[element attributeNamed:@"value"] intValue];
        NSString *name  = [element attributeNamed:@"name"];
        NSString *displayName = [element attributeNamed:@"display-name"];
        
        if (OFCFDictionaryContainsIntegerKey(_enumToName, value)) {
            [self release];
            [NSException raise:NSInvalidArgumentException
                        format:@"Unable to unarchive OFEnumNameTable: %@", @"Duplicate enum value"];
        }
        
        if (CFDictionaryContainsKey(_nameToEnum, (const void *)name)) {
            [self release];
            [NSException raise:NSInvalidArgumentException
                        format:@"Unable to unarchive OFEnumNameTable: %@", @"Duplicate enum name"];
        }
        
        if (!displayName)
            displayName = name;
        
        [self setName:name displayName:displayName forEnumValue:value];
    }
    
    if (!OFCFDictionaryContainsIntegerKey(_enumToName, _defaultEnumValue)) {
        [self release];
        [NSException raise:NSInvalidArgumentException
                    format:@"Unable to unarchive OFEnumNameTable: %@", @"Missing definition for default enum value"];
    }
    
    return self;
}

@end

NS_ASSUME_NONNULL_END
