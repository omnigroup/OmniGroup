// Copyright 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniDataObjects/ODOAttribute.h>

RCS_ID("$Id$")

NSString * const ODOAttributeElementName = @"attribute";
NSString * const ODOAttributeTypeAttributeName = @"type";
NSString * const ODOAttributeDefaultValueAttributeName = @"default";
NSString * const ODOAttributePrimaryKeyAttributeName = @"primary";

OFEnumNameTable *ODOAttributeTypeEnumNameTable(void)
{
    static OFEnumNameTable *table = nil;
    
    if (!table) {
        table = [[OFEnumNameTable alloc] initWithDefaultEnumValue:ODOAttributeTypeInvalid];
        [table setName:@"--invalid--" forEnumValue:ODOAttributeTypeInvalid];
        
        [table setName:@"undefined" forEnumValue:ODOAttributeTypeUndefined];
        [table setName:@"int16" forEnumValue:ODOAttributeTypeInt16];
        [table setName:@"int32" forEnumValue:ODOAttributeTypeInt32];
        [table setName:@"int64" forEnumValue:ODOAttributeTypeInt64];
        [table setName:@"decimal" forEnumValue:ODOAttributeTypeDecimal];
        [table setName:@"float32" forEnumValue:ODOAttributeTypeFloat32];
        [table setName:@"float64" forEnumValue:ODOAttributeTypeFloat64];
        [table setName:@"string" forEnumValue:ODOAttributeTypeString];
        [table setName:@"boolean" forEnumValue:ODOAttributeTypeBoolean];
        [table setName:@"date" forEnumValue:ODOAttributeTypeDate];
        [table setName:@"data" forEnumValue:ODOAttributeTypeData];
    }
    
    return table;
}

@implementation ODOAttribute

- (void)dealloc;
{
    [_defaultValue release];
    [super dealloc];
}

- (ODOAttributeType)type;
{
    return _type;
}

- (id)defaultValue;
{
    OBPRECONDITION(!_defaultValue || [_defaultValue isKindOfClass:_valueClass]);
    return _defaultValue;
}

- (Class)valueClass;
{
    OBPRECONDITION(_valueClass);
    return _valueClass;
}

#pragma mark -
#pragma mark Debugging

#ifdef DEBUG
- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *dict = [super debugDictionary];
    [dict setObject:[ODOAttributeTypeEnumNameTable() nameForEnum:_type] forKey:@"type"];
    if (_defaultValue)
        [dict setObject:_defaultValue forKey:@"defaultValue"];
    return dict;
}
#endif

@end

#import "ODOAttribute-Internal.h"
#import "ODOProperty-Internal.h"

@implementation ODOAttribute (Internal)

- (id)initWithCursor:(OFXMLCursor *)cursor entity:(ODOEntity *)entity error:(NSError **)outError;
{
    OBPRECONDITION([[cursor name] isEqualToString:ODOAttributeElementName]);
    
    NSString *primaryKeyString = [cursor attributeNamed:ODOAttributePrimaryKeyAttributeName];
    if (primaryKeyString) {
        OBASSERT([primaryKeyString isEqualToString:@"true"] || [primaryKeyString isEqualToString:@"false"]);
        _isPrimaryKey = [primaryKeyString isEqualToString:@"true"];
    }
    
    struct _ODOPropertyFlags baseFlags;
    memset(&baseFlags, 0, sizeof(baseFlags));
    baseFlags.snapshotIndex = ODO_NON_SNAPSHOT_PROPERTY_INDEX; // start out not being in the snapshot properties; this'll get updated later if we are
    
    if (_isPrimaryKey)
        // The primary key isn't in the snapshot, but has a special marker for that.
        baseFlags.snapshotIndex = ODO_PRIMARY_KEY_SNAPSHOT_INDEX;
    
    if (![super initWithCursor:cursor entity:entity baseFlags:baseFlags error:outError])
        return nil;
    
    // Ensure the property didn't find a setter for the primary key attribute
    OBASSERT(!_isPrimaryKey || ![self _setterSelector]);
    
    NSString *typeName = [cursor attributeNamed:ODOAttributeTypeAttributeName];
    if ([NSString isEmptyString:typeName]) {
        NSString *reason = NSLocalizedStringFromTableInBundle(@"Attribute specified no type.", nil, OMNI_BUNDLE, @"error reason");
        NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to load model.", nil, OMNI_BUNDLE, @"error description");
        ODOError(outError, ODOUnableToLoadModel, description, reason, nil);
        [self release];
        return nil;
    }
    
    _type = [ODOAttributeTypeEnumNameTable() enumForName:typeName];
    if (_type == ODOAttributeTypeInvalid) {
        NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Attribute specified invalid type of '%@'.", nil, OMNI_BUNDLE, @"error reason"), typeName];
        NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to load model.", nil, OMNI_BUNDLE, @"error description");
        ODOError(outError, ODOUnableToLoadModel, description, reason, nil);
        [self release];
        return nil;
    }

    switch (_type) {
        case ODOAttributeTypeUndefined:
            _valueClass = [NSObject class];
            break;
        case ODOAttributeTypeInt16:
        case ODOAttributeTypeInt32:
        case ODOAttributeTypeInt64:
        case ODOAttributeTypeBoolean:
            _valueClass = [NSNumber class];
            break;
        case ODOAttributeTypeDecimal:
            _valueClass = [NSDecimalNumber class];
            break;
        case ODOAttributeTypeFloat32:
        case ODOAttributeTypeFloat64:
            _valueClass = [NSNumber class];
            break;
        case ODOAttributeTypeString:
            _valueClass = [NSString class];
            break;
        case ODOAttributeTypeDate:
            _valueClass = [NSDate class];
            break;
        case ODOAttributeTypeData:
            _valueClass = [NSData class];
            break;
        default:
            OBASSERT_NOT_REACHED("Unknown types should have been caught above");
            _valueClass = [NSObject class];
            break;
    }
    
    NSString *defaultValueString = [cursor attributeNamed:ODOAttributeDefaultValueAttributeName];
    if (defaultValueString) { // empty string is valid for strings!
        switch (_type) {
            case ODOAttributeTypeInt32:
                OBASSERT(![NSString isEmptyString:defaultValueString]);
                OBASSERT([defaultValueString rangeOfCharacterFromSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]].length == 0);
                _defaultValue = [[NSNumber alloc] initWithInt:[defaultValueString intValue]];
                break;
            case ODOAttributeTypeBoolean:
                OBASSERT([defaultValueString isEqualToString:@"true"] || [defaultValueString isEqualToString:@"false"]);
                _defaultValue = [[NSNumber alloc] initWithBool:[defaultValueString isEqualToString:@"true"]];
                break;
            default: {
                NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Attribute specified default value '%@' for attribute of type of '%@'.", nil, OMNI_BUNDLE, @"error reason"), defaultValueString, typeName];
                NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to load model.", nil, OMNI_BUNDLE, @"error description");
                ODOError(outError, ODOUnableToLoadModel, description, reason, nil);
                [self release];
                return nil;
            }
        }
    }
    
    if (_isPrimaryKey && ([self isTransient] || [self isOptional])) {
        NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Attribute %@.%@ specified a transient or optional primary key.", nil, OMNI_BUNDLE, @"error reason"), typeName];
        NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to load model.", nil, OMNI_BUNDLE, @"error description");
        ODOError(outError, ODOUnableToLoadModel, description, reason, nil);
        [self release];
        return nil;
    }
    
    if ((_type == ODOAttributeTypeUndefined) && ![self isTransient]) {
        // I suppose we could support this with NSCoding, but not needed for now.
        NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Attribute %@.%@ has unknown value type but isn't transient.", nil, OMNI_BUNDLE, @"error reason"), typeName];
        NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to load model.", nil, OMNI_BUNDLE, @"error description");
        ODOError(outError, ODOUnableToLoadModel, description, reason, nil);
        [self release];
        return nil;
    }
    
    return self;
}

- (BOOL)isPrimaryKey;
{
    return _isPrimaryKey;
}

@end
