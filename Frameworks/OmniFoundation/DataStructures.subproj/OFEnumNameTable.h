// Copyright 2002-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniFoundation/DataStructures.subproj/OFEnumNameTable.h 103792 2008-08-06 04:02:53Z wiml $

#import <Foundation/NSObject.h>
#import <Foundation/NSString.h>
#import <CoreFoundation/CFDictionary.h>
#import <CoreFoundation/CFArray.h>

@class OFXMLCursor, OFXMLDocument;

@interface OFEnumNameTable : NSObject
{
    int                    _defaultEnumValue;
    CFMutableArrayRef      _enumOrder;
    CFMutableDictionaryRef _enumToName;
    CFMutableDictionaryRef _enumToDisplayName;
    CFMutableDictionaryRef _nameToEnum;
}

- initWithDefaultEnumValue: (int) defaultEnumValue;
- (int) defaultEnumValue;

- (void)setName:(NSString *)enumName forEnumValue:(int)enumValue;
- (void)setName:(NSString *)enumName displayName:(NSString *)displayName forEnumValue:(int)enumValue;

- (NSString *)nameForEnum:(int)enumValue;
- (NSString *)displayNameForEnum:(int)enumValue;
- (int) enumForName: (NSString *) name;
- (BOOL) isEnumValue: (int) enumValue;
- (BOOL) isEnumName: (NSString *) name;

- (unsigned int)count;
- (int)enumForIndex:(CFIndex)enumIndex;
- (int)nextEnum:(int)enumValue;
- (NSString *)nextName:(NSString *)name;

// Comparison
- (BOOL) isEqual: (id)anotherEnumeration;

// Masks

// Archving (primarily for OAEnumStyleAttribute)
+ (NSString *)xmlElementName;
- (void)appendXML:(OFXMLDocument *)doc;
- initFromXML:(OFXMLCursor *)cursor;

@end
