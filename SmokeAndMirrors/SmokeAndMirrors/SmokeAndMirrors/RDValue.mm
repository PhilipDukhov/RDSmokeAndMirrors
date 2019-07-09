#import "RDValue.h"
#import "RDPrivate.h"
#import <malloc/malloc.h>
#import <objc/runtime.h>

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

static constexpr size_t kAssumedMallocAlignmentBytes = 16;
static constexpr size_t kAssumendInstanceSizeBytes = 32;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface RDType(RDValue)

- (void)_value_retainBytes:(void *)bytes;
- (void)_value_releaseBytes:(void *)bytes;
- (NSString *)_value_describeBytes:(void *)bytes additionalInfo:(NSMutableArray<NSString *> *)info;
- (NSString *)_value_formatWithBytes:(void *)bytes;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

static bool copy(void *dst, RDType *dstType, const void *src, RDType *srcType) {
    BOOL isSafe = src != NULL
               && dst != NULL
               && srcType != nil
               && dstType != nil
               && dstType.size != RDTypeSizeUnknown
               && dstType.alignment != RDTypeAlignmentUnknown
               && [dstType isAssignableFromType:srcType]
               && (uintptr_t)dst % dstType.alignment == 0;
    
    if (!isSafe)
        return NO;
    
    [dstType _value_releaseBytes:dst];
    memcpy(dst, src, dstType.size);
    [dstType _value_retainBytes:dst];
    return YES;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface RDValue()

- (instancetype)_init NS_DESIGNATED_INITIALIZER;

@end

@implementation RDValue {
    @protected
    RDType *_type;
    void *_data;
    @private
    uintptr_t _reserved;
}

#pragma mark Initialization

+ (instancetype)allocWithZone:(struct _NSZone *)zone {
    if (self == RDValue.self || self == RDMutableValue.self) {
        static RDValue *instance = class_createInstance(RDValue.self, 0);
        static RDMutableValue *mutableInstance = class_createInstance(RDMutableValue.self, 0);
        return (self == RDValue.self ? instance : mutableInstance);
    } else {
        return [super alloc];
    }
}

- (void)dealloc {
    [_type _value_releaseBytes:_data];
}

+ (instancetype)valueWithBytes:(const void *)bytes ofType:(RDType *)type {
    return [[self alloc] initWithBytes:bytes ofType:type];
}

+ (instancetype)valueWithBytes:(const void *)bytes objCType:(const char *)type {
    return [[self alloc] initWithBytes:bytes objCType:type];
}

- (instancetype)_init {
    self = [super init];
    if (self) {
        _type = [RDUnknownType instance];
        _data = NULL;
    }
    return self;
}

- (instancetype)init {
    static RDValue *instance = [(RDValue *)class_createInstance(self.class, 0) _init];
    return instance;
}

- (instancetype)initWithBytes:(const void *)bytes objCType:(const char *)type {
    if (RDType *rdtype = [RDType typeWithObjcTypeEncoding:type]; rdtype != nil)
        return [self initWithBytes:bytes ofType:rdtype];
    else
        return nil;
}

- (instancetype)initWithBytes:(const void *)bytes ofType:(RDType *)type {
    if (type == nil || bytes == nil)
        return nil;
    
    size_t size = type.size;
    size_t alignment = type.alignment;

    if (size == RDTypeSizeUnknown || size == 0 || alignment == RDTypeAlignmentUnknown || alignment == 0)
        return nil;
    
    size_t alignmentPad = alignment > kAssumedMallocAlignmentBytes ? alignment - kAssumedMallocAlignmentBytes : 0;
    size_t instanceSize = class_getInstanceSize(self.class);
    NSAssert(instanceSize == kAssumendInstanceSizeBytes, @"RDValue has different instance size than expected");
    
    self = class_createInstance(self.class, size + alignmentPad);

    void *data = ({
        uintptr_t ptr = (uintptr_t)self;
        NSAssert(ptr % kAssumedMallocAlignmentBytes == 0, @"Allocated instance has weaker alignment than expected");
        ptr += instanceSize;
        while (ptr % alignment != 0)
            ++ptr;
        (void *)ptr;
    });
    
    self = [super init];
    if (self) {
        _type = type;
        _data = data;
        memcpy(_data, bytes, size);
        [_type _value_retainBytes:_data];
    }
    return self;
}

#pragma mark Interface

- (BOOL)getValue:(void *)value size:(NSUInteger)size {
    if (_data == NULL || value == NULL || _type.size != size || (uintptr_t)value % _type.alignment != 0)
        return NO;
    
    memcpy(value, _data, size);
    return YES;
}

- (BOOL)getValue:(void *)value objCType:(const char *)type {
    if (_data == NULL || value == NULL || type == NULL)
        return NO;
    
    if (RDType *rdtype = [RDType typeWithObjcTypeEncoding:type]; type != nil)
        return [self getValue:value type:rdtype];
    else
        return NO;
}

- (BOOL)getValue:(void *)value type:(RDType *)type {
    return copy(value, type, _data, _type);
}

- (NSString *)description {
    return [NSString stringWithFormat:[self.type _value_formatWithBytes:_data],
            [NSString stringWithFormat:@"value_at_%p", self]];
}

- (NSString *)debugDescription {
    return [self.type _value_describeBytes:_data additionalInfo:nil];
}

- (const char *)objCType {
    return _type.objCTypeEncoding;
}

#pragma mark <NSCopying>

- (RDValue *)copy {
    return [self copyWithZone:nil];
}

- (RDValue *)copyWithZone:(NSZone *)zone {
    if (self.class == RDValue.self)
        return self;
    else
        return [[RDValue alloc] initWithBytes:_data ofType:_type];
}

#pragma mark <NSMutableCopying>

- (RDMutableValue *)mutableCopy {
    return [self mutableCopyWithZone:nil];
}

- (RDMutableValue *)mutableCopyWithZone:(NSZone *)zone {
    return [[RDMutableValue alloc] initWithBytes:_data ofType:_type];
}

#pragma mark <NSSecureCopying>

+ (BOOL)supportsSecureCoding {
    return YES;
}

#pragma mark <NSCopying>

- (nullable instancetype)initWithCoder:(NSCoder *)coder {
    RDType *type = [coder decodeObjectOfClass:RDType.self forKey:@"type"];
    if (type == nil)
        return nil;
    
    NSUInteger size = 0;
    const uint8_t *bytes = [coder decodeBytesForKey:@"data" returnedLength:&size];
    if (bytes == NULL || size != type.size)
        return nil;
    
    return [[self.class alloc] initWithBytes:bytes ofType:type];
}

- (void)encodeWithCoder:(nonnull NSCoder *)coder {
    if (_data != nil && _type != nil && _type.size != RDTypeSizeUnknown) {
        [coder encodeObject:_type forKey:@"type"];
        [coder encodeBytes:(const uint8_t *)_data length:_type.size forKey:@"data"];
    } else {
        [coder encodeObject:nil forKey:@"type"];
    }
}

#pragma mark Subscripting

- (RDValue *)objectAtIndexedSubscript:(NSUInteger)index {
    if (RDArrayType *type = RD_CAST(self.type, RDArrayType); type != nil) {
        if (index < type.count)
            return [RDValue valueWithBytes:(uint8_t *)_data + [type offsetForElementAtIndex:index] ofType:type.type];
        else
            return nil;

    } else if (RDAggregateType *type = RD_CAST(self.type, RDAggregateType); type != nil) {
        if (index >= type.fields.count)
            return nil;
            
        if (RDField *field = type.fields[index]; field != nil && field.type != nil && field.offset != RDFieldOffsetUnknown)
            return [RDValue valueWithBytes:(uint8_t *)_data + field.offset ofType:field.type];
        else
            return nil;

    } else {
        return nil;
    }
}

- (RDValue *)objectAtKeyedSubscript:(NSString *)key {
    if (key == nil) {
        return nil;
    } else if (RDAggregateType *type = RD_CAST(self.type, RDAggregateType); type != nil) {
        for (RDField *field in type.fields)
            if ([key isEqualToString:field.name] && field.type != nil && field.offset != RDFieldOffsetUnknown)
                return [RDValue valueWithBytes:(uint8_t *)_data + field.offset ofType:field.type];

        return nil;
        
    } else {
        return nil;
    }
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation RDMutableValue

- (BOOL)setValue:(void *)value objCType:(const char *)type {
    if (_data == NULL || value == NULL || type == NULL)
        return NO;

    if (RDType *rdtype = [RDType typeWithObjcTypeEncoding:type]; rdtype != nil)
        return [self setValue:value type:rdtype];
    else
        return NO;
}

- (BOOL)setValue:(void *)value type:(RDType *)type {
    return copy(_data, _type, value, type);
}

- (BOOL)setObject:(RDValue *)value atIndexedSubscript:(NSUInteger)index {
    if (RDArrayType *type = RD_CAST(self.type, RDArrayType); type != nil) {
        if (index < type.count)
            return copy((uint8_t *)_data + [type offsetForElementAtIndex:index], type.type, value->_data, value->_type);
        else
            return NO;
        
    } else if (RDAggregateType *type = RD_CAST(self.type, RDAggregateType); type != nil) {
        if (index >= type.fields.count)
            return NO;
        
        if (RDField *field = type.fields[index]; field != nil && field.type != nil && field.offset != RDFieldOffsetUnknown)
            return copy((uint8_t *)_data + field.offset, field.type, value->_data, value->_type);
        else
            return NO;
        
    } else {
        return NO;
    }
}

- (BOOL)setObject:(RDValue *)value atKeyedSubscript:(NSString *)key {
    if (key == nil) {
        return NO;
    } else if (RDAggregateType *type = RD_CAST(self.type, RDAggregateType); type != nil) {
        for (RDField *field in type.fields)
            if ([key isEqualToString:field.name] && field.type != nil && field.offset != RDFieldOffsetUnknown)
                return copy((uint8_t *)_data + field.offset, field.type, value->_data, value->_type);
        
        return NO;
        
    } else {
        return NO;
    }
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation RDType(RDValue)

- (void)_value_retainBytes:(void *_Nonnull)bytes {
    // Do nothing for non-retainable types by default
}

- (void)_value_releaseBytes:(void *_Nonnull)bytes {
    // Do nothing for non-retainable types by default
}

- (NSString *)_value_describeBytes:(void *)bytes additionalInfo:(NSMutableArray<NSString *> *)info {
    return nil;
}

- (NSString *)_value_formatWithBytes:(void *)bytes {
    NSMutableArray *more = [NSMutableArray array];
    NSString *desc = [self _value_describeBytes:bytes additionalInfo:more];
    NSString *decl = self.format;
    return [NSString stringWithFormat:@"%@ = %@;\n%@", decl, desc, [more componentsJoinedByString:@"\n\n"]];
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface RDUnknownType(RDValue)
@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface RDObjectType(RDValue)
@end

@implementation RDObjectType(RDValue)

- (void)_value_retainBytes:(void *_Nonnull)bytes {
    *(void **)bytes = (__bridge void *)objc_retain((__bridge id)*(void **)bytes);
}

- (void)_value_releaseBytes:(void *_Nonnull)bytes {
    objc_release((__bridge id)*(void **)bytes);
}

- (NSString *)_value_describeBytes:(void *)bytes {
    return [(__bridge id)*(void **)bytes description];
}

- (NSString *)_value_describeBytes:(void *)bytes additionalInfo:(NSMutableArray<NSString *> *)info {
    if (NSString *description = [(__bridge id)*(void **)bytes description]; description != nil)
        [info addObject:[NSString stringWithFormat:@"Printing description of (%@)%p:\n%@", self.description, *(void **)bytes, description]];
    
    return [NSString stringWithFormat:@"(%@)%p", self.description, *(void **)bytes];
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface RDVoidType(RDValue)
@end

@implementation RDVoidType(RDValue)

- (NSString *)_value_describeBytes:(void *)bytes additionalInfo:(NSMutableArray<NSString *> *)info {
    return @"void";
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface RDBlockType(RDValue)
@end

@implementation RDBlockType(RDValue)

- (void)_value_retainBytes:(void *)bytes {
    if (bytes != NULL)
        *(void **)bytes = (__bridge void *)objc_retainBlock((__bridge id)*(void **)bytes);
}

- (void)_value_releaseBytes:(void *)bytes {
    if (bytes != NULL)
        objc_release((__bridge id)*(void **)bytes);
}

- (NSString *)_value_describeBytes:(void *)bytes additionalInfo:(NSMutableArray<NSString *> *)info {
    if (NSString *description = [(__bridge id)*(void **)bytes description]; description != nil)
        [info addObject:[NSString stringWithFormat:@"Printing description of (%@)%p:\n%@", self.description, *(void **)bytes, description]];
    
    if (void *ptr = *(void **)bytes; ptr != NULL)
        return [NSString stringWithFormat:@"(%@)%p", self.description, ptr];
    else
        return @"nil";
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface RDPrimitiveType(RDValue)
@end

@implementation RDPrimitiveType(RDValue)

- (NSString *)_value_describeBytes:(void *)bytes additionalInfo:(NSMutableArray<NSString *> *)info {
    switch (self.kind) {
        case RDPrimitiveTypeKindClass:
            return [NSString stringWithFormat:@"%@.self", NSStringFromClass(*(Class *)bytes)];
        case RDPrimitiveTypeKindSelector:
            return [NSString stringWithFormat:@"@selector(%s)", sel_getName(*(SEL *)bytes)];
        case RDPrimitiveTypeKindCString:
            return [NSString stringWithFormat:@"c string at \"%p\"", *(const char **)bytes];
        case RDPrimitiveTypeKindAtom:
            return [NSString stringWithFormat:@"?"];
        case RDPrimitiveTypeKindChar:
            return [NSString stringWithFormat:@"'%c'", *(char *)bytes];
        case RDPrimitiveTypeKindUnsignedChar:
            return [NSString stringWithFormat:@"(unsigned char)'%c'", *(unsigned char *)bytes];
        case RDPrimitiveTypeKindBool:
            return [NSString stringWithFormat:@"%s", *(unsigned char *)bytes ? "true" : "false"];
        case RDPrimitiveTypeKindShort:
            return [NSString stringWithFormat:@"(short)%d", *(short *)bytes];
        case RDPrimitiveTypeKindUnsignedShort:
            return [NSString stringWithFormat:@"(unsigned short)%du", *(unsigned short *)bytes];
        case RDPrimitiveTypeKindInt:
            return [NSString stringWithFormat:@"%d", *(int *)bytes];
        case RDPrimitiveTypeKindUnsignedInt:
            return [NSString stringWithFormat:@"%du", *(unsigned int *)bytes];
        case RDPrimitiveTypeKindLong:
            return [NSString stringWithFormat:@"%ldl", *(long *)bytes];
        case RDPrimitiveTypeKindUnsignedLong:
            return [NSString stringWithFormat:@"%luul", *(unsigned long *)bytes];
        case RDPrimitiveTypeKindLongLong:
            return [NSString stringWithFormat:@"%lldll", *(long long int *)bytes];
        case RDPrimitiveTypeKindUnsignedLongLong:
            return [NSString stringWithFormat:@"%lluull", *(unsigned long long *)bytes];
        case RDPrimitiveTypeKindInt128:
            return [NSString stringWithFormat:@"(int128_t)%lld", (long long)*(__int128_t *)bytes];
        case RDPrimitiveTypeKindUnsignedInt128:
            return [NSString stringWithFormat:@"(uint128_t)%llu", (unsigned long long)*(__uint128_t *)bytes];
        case RDPrimitiveTypeKindFloat:
            return [NSString stringWithFormat:@"%ff", *(float *)bytes];
        case RDPrimitiveTypeKindDouble:
            return [NSString stringWithFormat:@"%f", *(double *)bytes];
        case RDPrimitiveTypeKindLongDouble:
            return [NSString stringWithFormat:@"%Lfl", *(long double *)bytes];
    }
    return nil;
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface RDCompositeType(RDValue)
@end

@implementation RDCompositeType(RDValue)

- (NSString *)_value_describeBytes:(void *)bytes additionalInfo:(NSMutableArray<NSString *> *)info {
    return [self.type _value_describeBytes:bytes additionalInfo:info];
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface RDBitfieldType(RDValue)
@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface RDArrayType(RDValue)
@end

@implementation RDArrayType(RDValue)

- (void)_value_retainBytes:(void *)bytes {
    if (bytes != NULL)
        for (NSUInteger i = 0; i < self.count; ++i)
            if (size_t offset = [self offsetForElementAtIndex:i]; offset != RDFieldOffsetUnknown)
                [self.type _value_retainBytes:(uint8_t *)bytes + offset];
}

- (void)_value_releaseBytes:(void *)bytes {
    if (bytes != NULL)
        for (NSUInteger i = 0; i < self.count; ++i)
            if (size_t offset = [self offsetForElementAtIndex:i]; offset != RDFieldOffsetUnknown)
                [self.type _value_releaseBytes:(uint8_t *)bytes + offset];
}

- (NSString *)_value_describeBytes:(void *)bytes additionalInfo:(NSMutableArray<NSString *> *)info {
    NSMutableArray<NSString *> *values = [NSMutableArray array];
    for (NSUInteger i = 0; i < self.count; ++i)
        [values addObject:[self.type _value_describeBytes:(uint8_t *)bytes + [self offsetForElementAtIndex:i] additionalInfo:info]];
    return [NSString stringWithFormat:@"{ %@ }", [values componentsJoinedByString:@", "]];
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface RDAggregateType(RDValue)
@end

@implementation RDAggregateType(RDValue)

- (void)_value_retainBytes:(void *)bytes {
    if (self.kind == RDAggregateTypeKindStruct)
        if (bytes != NULL)
            for (RDField *field in self.fields)
                if (size_t offset = field.offset; offset != RDFieldOffsetUnknown)
                    [field.type _value_retainBytes:(uint8_t *)bytes + offset];
}

- (void)_value_releaseBytes:(void *)bytes {
    if (self.kind == RDAggregateTypeKindStruct)
        if (bytes != NULL)
            for (RDField *field in self.fields)
                if (size_t offset = field.offset; offset != RDFieldOffsetUnknown)
                    [field.type _value_releaseBytes:(uint8_t *)bytes + offset];
}

- (NSString *)_value_describeBytes:(void *)bytes additionalInfo:(NSMutableArray<NSString *> *)info {
    NSMutableArray<NSString *> *values = [NSMutableArray array];
    for (NSUInteger i = 0; i < self.fields.count; ++i)
        if (RDField *field = self.fields[i]; field.offset != RDFieldOffsetUnknown)
            [values addObject:[NSString stringWithFormat:@".%@ = %@",
                               field.name ?: [NSString stringWithFormat:@"field%zu", i],
                               [field.type _value_describeBytes:(uint8_t *)bytes + field.offset additionalInfo:info]]];

    return [NSString stringWithFormat:@"(%@%@) { %@ }",
                                      self.kind == RDAggregateTypeKindUnion ? @"union" : @"struct",
                                      self.name ? [NSString stringWithFormat:@" %@", self.name] : @"",
                                      [values componentsJoinedByString:@", "]];
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////