#import "RDCommon.h"
#import "RDType.h"

NS_ASSUME_NONNULL_BEGIN

#define RDValueBox(VALUE) ({ __auto_type v = (VALUE); [[RDValue alloc] initWithBytes:&v objCType:@encode(typeof(v))]; })
#define RDValueSet(RDVALUE, VALUE) ({ __auto_type v = (VALUE); [(RDVALUE) setValue:&v objCType:@encode(typeof(v))]; })
#define RDValueSetAt(RDVALUE, INDEX, VALUE) ({ __auto_type v = (VALUE); [(RDVALUE) setValue:&v objCType:@encode(typeof(v)) atIndex:(INDEX)]; })
#define RDValueGet(RDVALUE, VALUE) ({ __auto_type v = (VALUE); [(RDVALUE) getValue:v objCType:@encode(typeof(*v))]; })
#define RDValueGetAt(RDVALUE, INDEX, VALUE) ({ __auto_type v = (VALUE); [(RDVALUE) getValue:v objCType:@encode(typeof(*v)) atIndex:(INDEX)]; })

@class RDMutableValue;

@interface RDValue : NSObject<NSCopying, NSMutableCopying, NSSecureCoding>

@property (nonatomic, readonly) RDType *type;
@property (nonatomic, readonly) const char *objCType;

+ (instancetype)valueWithBytes:(const void *)bytes ofType:(RDType *)type;
+ (instancetype)valueWithBytes:(const void *)bytes objCType:(const char *)type;

- (instancetype)init NS_DESIGNATED_INITIALIZER;
- (nullable instancetype)initWithBytes:(const void *)bytes objCType:(const char *)type;
- (nullable instancetype)initWithBytes:(const void *)bytes ofType:(RDType *)type NS_DESIGNATED_INITIALIZER;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;

- (BOOL)getValue:(void *)value objCType:(const char *)type;
- (BOOL)getValue:(void *)value type:(RDType *)type;
- (BOOL)getValue:(void *)value objCType:(const char *)type atIndex:(NSUInteger)index;
- (BOOL)getValue:(void *)value type:(RDType *)type atIndex:(NSUInteger)index;
- (BOOL)getValue:(void *)value objCType:(const char *)type forKey:(nullable NSString *)key;
- (BOOL)getValue:(void *)value type:(RDType *)type forKey:(nullable NSString *)key;

- (RDValue *)copy;
- (RDValue *)copyWithZone:(nullable NSZone *)zone;
- (RDMutableValue *)mutableCopy;
- (RDMutableValue *)mutableCopyWithZone:(nullable NSZone *)zone;

- (nullable RDValue *)objectAtIndexedSubscript:(NSUInteger)index;
- (nullable RDValue *)objectAtKeyedSubscript:(nullable NSString *)index;

@end

@interface RDMutableValue : RDValue

- (BOOL)setValue:(void *)value objCType:(const char *)type;
- (BOOL)setValue:(void *)value type:(RDType *)type;
- (BOOL)setValue:(void *)value objCType:(const char *)type atIndex:(NSUInteger)index;
- (BOOL)setValue:(void *)value type:(RDType *)type atIndex:(NSUInteger)index;
- (BOOL)setValue:(void *)value objCType:(const char *)type forKey:(NSString *)key;
- (BOOL)setValue:(void *)value type:(RDType *)type forKey:(NSString *)key;

- (BOOL)setObject:(RDValue *)value atIndexedSubscript:(NSUInteger)index;
- (BOOL)setObject:(RDValue *)value atKeyedSubscript:(nullable NSString *)key;

@end

NS_ASSUME_NONNULL_END
